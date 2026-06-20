-- ============================================================================
-- Migration: 20260620000006_sync_customer_address_to_saved.sql
-- Description: Adds a trigger on the customers table to automatically sync
--              the address provided during signup into the saved_addresses 
--              table as their default 'Home' address. Also ensures that proper
--              SELECT grants are applied to fix any access errors.
-- ============================================================================

-- 1. Create or replace the function to sync customer address
CREATE OR REPLACE FUNCTION public.sync_customer_address_to_saved()
RETURNS TRIGGER AS $$
DECLARE
  extracted_lat DOUBLE PRECISION := 0;
  extracted_lng DOUBLE PRECISION := 0;
  has_address BOOLEAN := false;
  address_text TEXT := '';
BEGIN
  -- We only want to sync if an address is provided. 
  -- Checking the default_address from the customers table.
  IF NEW.default_address IS NOT NULL AND TRIM(NEW.default_address) != '' THEN
    has_address := true;
    address_text := TRIM(NEW.default_address);
  ELSIF NEW.address IS NOT NULL AND TRIM(NEW.address) != '' THEN
    has_address := true;
    address_text := TRIM(NEW.address);
  END IF;

  IF has_address THEN
    -- Try to extract latitude and longitude from the PostGIS point if present
    IF NEW.location IS NOT NULL THEN
      BEGIN
        extracted_lng := ST_X(NEW.location::geometry);
        extracted_lat := ST_Y(NEW.location::geometry);
      EXCEPTION WHEN OTHERS THEN
        -- Fallback to 0,0 if parsing fails
        extracted_lat := 0;
        extracted_lng := 0;
      END;
    END IF;

    -- Insert into saved_addresses
    -- We use ON CONFLICT DO NOTHING just in case, though there shouldn't be
    -- a conflict since we generate a new UUID for the saved_addresses row.
    INSERT INTO public.saved_addresses (
      user_id,
      label,
      address,
      landmark,
      pincode,
      latitude,
      longitude,
      is_default
    ) VALUES (
      NEW.id,
      'Home',
      address_text,
      COALESCE(TRIM(NEW.landmark), ''),
      COALESCE(TRIM(NEW.pincode), ''),
      extracted_lat,
      extracted_lng,
      true
    ) ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Drop the trigger if it already exists to ensure idempotency
DROP TRIGGER IF EXISTS trg_sync_customer_address ON public.customers;

-- 3. Create the trigger on public.customers
CREATE TRIGGER trg_sync_customer_address
  AFTER INSERT ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_customer_address_to_saved();

-- 4. Explicitly restate Grants on saved_addresses to fix any "Grant SELECT errors"
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_addresses TO authenticated;
REVOKE ALL ON public.saved_addresses FROM anon;
