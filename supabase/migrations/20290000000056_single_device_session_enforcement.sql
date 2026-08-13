-- ============================================================================
-- Migration: 20290000000056_single_device_session_enforcement.sql
-- Description: 100x Strict Single-Device Session Enforcement ("One Phone Number = One Active Device").
-- When a user logs in on a new device, any previous device is immediately invalidated
-- in real-time across all user roles (Rider, Seller, Customer, Admin).
-- ============================================================================

-- 1. Add session tracking columns to public.profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS current_session_id TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS current_device_id TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS session_created_at TIMESTAMPTZ DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_current_session_id 
  ON public.profiles (current_session_id) 
  WHERE current_session_id IS NOT NULL;

-- 2. Enable Realtime for public.profiles so connected devices get instant WebSocket push on session changes
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'profiles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
  END IF;
END $$;

-- 3. Set replica identity to FULL so realtime update payloads include all columns (especially current_session_id and id)
ALTER TABLE public.profiles REPLICA IDENTITY FULL;

-- 4. Atomic RPC to enforce single device login
CREATE OR REPLACE FUNCTION public.enforce_single_device_login(
  p_user_id UUID,
  p_session_id TEXT,
  p_device_id TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
  -- 1. Update profiles table with active session and device ID
  UPDATE public.profiles
  SET 
    current_session_id = p_session_id,
    current_device_id = p_device_id,
    session_created_at = NOW()
  WHERE id = p_user_id;

  -- 2. Purge stale device tokens for other physical devices so old devices stop receiving FCM pushes
  IF p_device_id IS NOT NULL AND p_device_id <> '' THEN
    DELETE FROM public.device_tokens
    WHERE user_id = p_user_id
      AND (device_id IS NULL OR device_id <> p_device_id);
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC to check if a session is currently active
CREATE OR REPLACE FUNCTION public.is_session_active(
  p_user_id UUID,
  p_session_id TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
  v_current_session TEXT;
BEGIN
  SELECT current_session_id INTO v_current_session
  FROM public.profiles
  WHERE id = p_user_id;

  -- If no session set yet in DB, consider active (fallback)
  IF v_current_session IS NULL THEN
    RETURN TRUE;
  END IF;

  RETURN v_current_session = p_session_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Permissions
GRANT EXECUTE ON FUNCTION public.enforce_single_device_login(UUID, TEXT, TEXT) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.is_session_active(UUID, TEXT) TO authenticated, anon, service_role;
GRANT SELECT, UPDATE(current_session_id, current_device_id, session_created_at) ON public.profiles TO authenticated, anon, service_role;
