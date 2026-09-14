-- =============================================================================
-- Migration: Maintenance Mode Order Blocker
-- Description:
--   1. Seeds 'maintenance_mode' (boolean) and 'maintenance_message' (string)
--      keys in platform_config.
--   2. Creates a BEFORE INSERT ON orders trigger that aborts order creation
--      when maintenance_mode is true, raising the admin's custom message.
--   3. Trigger named 'trigger_aa_check_maintenance_mode' to fire BEFORE the
--      existing 'trigger_generate_delivery_otp' (alphabetical order).
--
-- Zero changes to any existing RPC, trigger, table schema, or financial logic.
-- =============================================================================

-- ── 1. Seed platform_config keys (idempotent) ──────────────────────────────

INSERT INTO public.platform_config (key, value, label, description)
VALUES
  ('maintenance_mode', 'false'::jsonb, 'Maintenance Mode',
   'When true, all new customer orders are blocked platform-wide'),
  ('maintenance_message',
   '"We are currently updating our platform to serve you better. Ordering will resume shortly."'::jsonb,
   'Maintenance Message',
   'Custom message shown to customers during maintenance')
ON CONFLICT (key) DO NOTHING;


-- ── 2. Trigger function: check maintenance_mode BEFORE any order insert ────

CREATE OR REPLACE FUNCTION check_maintenance_mode_before_order()
RETURNS TRIGGER AS $$
DECLARE
  v_enabled boolean := false;
  v_message text;
BEGIN
  -- Read the maintenance_mode flag safely from platform_config without jsonb cast error
  SELECT COALESCE(value #>> '{}' = 'true', false) INTO v_enabled
  FROM platform_config
  WHERE key = 'maintenance_mode';

  -- If maintenance mode is active, block the order
  IF COALESCE(v_enabled, false) THEN
    -- Extract the raw text from the JSONB string value
    SELECT value #>> '{}' INTO v_message
    FROM platform_config
    WHERE key = 'maintenance_message';

    RAISE EXCEPTION 'MAINTENANCE_MODE_ACTIVE: %',
      COALESCE(v_message, 'Platform is temporarily under maintenance. Please try again later.')
      USING ERRCODE = 'P0001';
  END IF;

  -- Not in maintenance mode — allow the insert to proceed
  RETURN NEW;
END;
$$ LANGUAGE plpgsql STABLE;


-- ── 3. Create the trigger (idempotent drop + create) ───────────────────────
-- Named 'trigger_aa_*' so it fires BEFORE 'trigger_generate_delivery_otp'
-- (PostgreSQL fires BEFORE triggers in alphabetical order by name).

DROP TRIGGER IF EXISTS trigger_aa_check_maintenance_mode ON orders;
CREATE TRIGGER trigger_aa_check_maintenance_mode
BEFORE INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION check_maintenance_mode_before_order();
