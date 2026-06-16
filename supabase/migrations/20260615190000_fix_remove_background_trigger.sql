-- ============================================================================
-- Migration: 20260615190000_fix_remove_background_trigger.sql
-- Description: Fixes the DB trigger for the background removal Edge Function.
--
-- ROOT CAUSE OF BUG:
--   The previous trigger used supabase_functions.http_request with an empty
--   body '{}'. The Edge Function received no data (payload.record was undefined)
--   and immediately returned "Ignored: bucket=unknown" without ever calling
--   the Hugging Face API.
--
-- FIX:
--   1. Create a PL/pgSQL wrapper function that builds the JSON body dynamically
--      using the actual row values (NEW.name, NEW.bucket_id) and calls the
--      Edge Function via pg_net HTTP request.
--   2. Bind the trigger to this wrapper so it only fires for 'raw-product-images'.
--
-- WHY NOT supabase_functions.http_request() directly?
--   supabase_functions.http_request() accepts only literal TEXT parameters —
--   it cannot use expressions like (NEW.name) or string concatenation.
--   A PL/pgSQL SECURITY DEFINER wrapper function solves this correctly.
-- ============================================================================

-- Drop the old broken trigger first
DROP TRIGGER IF EXISTS trigger_remove_background ON storage.objects;

-- Drop the old wrapper function if it exists (clean slate)
DROP FUNCTION IF EXISTS public.notify_remove_background();

-- ── Create a PL/pgSQL wrapper that dynamically builds the HTTP body ───────
-- Uses pg_net (available on all Supabase projects) to make the async HTTP call.
-- SECURITY DEFINER runs as the function owner (postgres) who has full DB access.
CREATE OR REPLACE FUNCTION public.notify_remove_background()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_service_role_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1tZHJnY3VhZXR3b2hmbGN2em91Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Nzk5NzUxMCwiZXhwIjoyMDkzNTczNTEwfQ.rzX0mupREQDLgTgZLISBocfdtWH-IPVE0bsz7oc_Z8c';
  v_payload JSONB;
BEGIN
  -- Build the JSON body with the actual row values
  v_payload := jsonb_build_object(
    'name',      NEW.name,
    'bucket_id', NEW.bucket_id
  );

  -- Fire-and-forget async HTTP POST to the Edge Function via pg_net
  PERFORM net.http_post(
    url     := 'https://mmdrgcuaetwohflcvzou.supabase.co/functions/v1/remove-background',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_role_key
    ),
    body    := v_payload::TEXT
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never fail the storage insert due to HTTP errors — just log
  RAISE WARNING 'notify_remove_background: failed to call Edge Function: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- ── Bind the trigger — only fires for raw-product-images bucket ───────────
CREATE TRIGGER trigger_remove_background
  AFTER INSERT ON storage.objects
  FOR EACH ROW
  WHEN (NEW.bucket_id = 'raw-product-images')
  EXECUTE FUNCTION public.notify_remove_background();

-- ── Grants ────────────────────────────────────────────────────────────────
-- service_role needs SELECT on storage.objects for the function context
GRANT SELECT ON TABLE storage.objects TO service_role;

-- service_role needs UPDATE on cutout_url to write results back
GRANT UPDATE (cutout_url) ON public.products TO service_role;

-- Force PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
