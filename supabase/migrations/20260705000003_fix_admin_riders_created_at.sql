-- ============================================================================
-- Migration: 20260705000003_fix_admin_riders_created_at.sql
-- Description: Fixes PostgrestException for missing dp.created_at column
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_get_all_riders();
CREATE OR REPLACE FUNCTION public.admin_get_all_riders()
RETURNS TABLE (
  id                    UUID,
  verification_status   TEXT,
  vehicle_type          TEXT,
  vehicle_number        TEXT,
  aadhar_number         TEXT,
  pan_number            TEXT,
  bank_account_number   TEXT,
  bank_ifsc             TEXT,
  bank_account_holder   TEXT,
  is_active             BOOLEAN,
  is_available          BOOLEAN,
  is_online             BOOLEAN,
  total_deliveries      INT,
  preferred_nav_app     TEXT,
  created_at            TIMESTAMPTZ,
  profiles              JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only callable by active admins
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  RETURN QUERY
  SELECT
    dp.id,
    dp.verification_status,
    dp.vehicle_type,
    dp.vehicle_number,
    dp.aadhar_number,
    dp.pan_number,
    dp.bank_account_number,
    dp.bank_ifsc,
    dp.bank_account_holder,
    dp.is_active,
    dp.is_available,
    dp.is_online,
    dp.total_deliveries,
    dp.preferred_nav_app,
    p.created_at,        -- FIXED: Changed from dp.created_at to p.created_at
    jsonb_build_object(
      'id',         p.id,
      'full_name',  p.full_name,
      'phone',      p.phone,
      'email',      p.email,
      'avatar_url', p.avatar_url
    ) AS profiles
  FROM public.delivery_partners dp
  LEFT JOIN public.profiles p ON p.id = dp.id
  ORDER BY p.created_at DESC; -- FIXED: Changed from dp.created_at to p.created_at
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_all_riders() TO authenticated;
