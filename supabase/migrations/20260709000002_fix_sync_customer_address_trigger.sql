-- ============================================================================
-- Migration: 20260709000002_fix_sync_customer_address_trigger.sql
-- Description: Fixes the trg_sync_customer_address trigger so that it reliably
--              inserts into saved_addresses even when auth.uid() is NULL
--              (which happens in trigger context). Also adds house_number ->
--              flat_number capture which was previously missing.
--
-- CHANGES (purely additive — CREATE OR REPLACE, no existing SQL altered):
--   1. Replace sync_customer_address_to_saved() with a version that sets
--      SET row_security = off so it bypasses RLS (runs as postgres/owner).
--   2. Recreate the trigger (DROP IF EXISTS + CREATE) — idempotent.
-- ============================================================================

-- 1. Replace the trigger function with RLS bypass + house_number support
CREATE OR REPLACE FUNCTION public.sync_customer_address_to_saved()
RETURNS TRIGGER AS $$
DECLARE
  extracted_lat DOUBLE PRECISION := 0;
  extracted_lng DOUBLE PRECISION := 0;
  has_address BOOLEAN := false;
  address_text TEXT := '';
BEGIN
  -- We only want to sync if an address is provided.
  IF NEW.default_address IS NOT NULL AND TRIM(NEW.default_address) != '' THEN
    has_address := true;
    address_text := TRIM(NEW.default_address);
  ELSIF NEW.address IS NOT NULL AND TRIM(NEW.address) != '' THEN
    has_address := true;
    address_text := TRIM(NEW.address);
  END IF;

  IF NOT has_address THEN
    RETURN NEW;
  END IF;

  -- Try to extract latitude and longitude from the PostGIS point if present
  IF NEW.location IS NOT NULL THEN
    BEGIN
      extracted_lng := ST_X(NEW.location::geometry);
      extracted_lat := ST_Y(NEW.location::geometry);
    EXCEPTION WHEN OTHERS THEN
      extracted_lat := 0;
      extracted_lng := 0;
    END;
  END IF;

  -- Only insert if the user doesn't already have a Home saved address
  IF NOT EXISTS (
    SELECT 1 FROM public.saved_addresses
    WHERE user_id = NEW.id AND label = 'Home'
  ) THEN
    -- Clear any existing default flags first
    UPDATE public.saved_addresses
    SET is_default = false
    WHERE user_id = NEW.id;

    INSERT INTO public.saved_addresses (
      user_id,
      label,
      flat_number,
      address,
      landmark,
      pincode,
      latitude,
      longitude,
      is_default
    ) VALUES (
      NEW.id,
      'Home',
      NULLIF(TRIM(COALESCE(NEW.house_number, '')), ''),
      address_text,
      NULLIF(TRIM(COALESCE(NEW.landmark, '')), ''),
      NULLIF(TRIM(COALESCE(NEW.pincode, '')), ''),
      extracted_lat,
      extracted_lng,
      true
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET row_security = off;

-- 2. Recreate the trigger (idempotent)
DROP TRIGGER IF EXISTS trg_sync_customer_address ON public.customers;
CREATE TRIGGER trg_sync_customer_address
  AFTER INSERT ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_customer_address_to_saved();

-- 3. Re-assert grants
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_addresses TO authenticated;
REVOKE ALL ON public.saved_addresses FROM anon;

-- 4. Reload schema cache
NOTIFY pgrst, 'reload schema';
