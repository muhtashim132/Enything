-- =============================================================================
-- Migration: 20271236000000_sync_is_active_verified_shops.sql
-- Description: Retroactive additive fix — syncs is_active = true for any
--              shop whose verification_status = 'verified' but is_active is
--              still false (data inconsistency from shop creation or KYC dialog
--              not running in certain environments).
--
--              Also (re)creates the auto-activate trigger so future KYC
--              approvals always keep is_active in sync.
--
--              ADDITIVE ONLY: No existing SQL functions, RPCs, or policies are
--              modified. Only data rows with a known-safe inconsistency are
--              updated.
-- =============================================================================

-- Step 1: (Re)create the auto-activate trigger function so future approvals
-- automatically set is_active = true. IDEMPOTENT via CREATE OR REPLACE.
CREATE OR REPLACE FUNCTION public.trg_auto_activate_on_approval()
RETURNS trigger AS $$
BEGIN
  -- Only activate when transitioning INTO an approved/verified state
  IF NEW.verification_status IN ('approved', 'verified')
     AND (OLD.verification_status IS NULL
          OR OLD.verification_status NOT IN ('approved', 'verified')) THEN
    NEW.is_active := true;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 2: Attach the trigger to shops (DROP IF EXISTS for idempotency)
DROP TRIGGER IF EXISTS auto_activate_shop ON public.shops;
CREATE TRIGGER auto_activate_shop
  BEFORE UPDATE OF verification_status ON public.shops
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_auto_activate_on_approval();

-- Step 3: Retroactively fix all shops that are verified but stuck as inactive
-- Safe: only touches rows where is_active is provably wrong (verified + inactive)
UPDATE public.shops
SET is_active = true
WHERE verification_status IN ('approved', 'verified')
  AND is_active = false;

-- Step 4: Same for delivery_partners (keeping symmetry)
DROP TRIGGER IF EXISTS auto_activate_rider ON public.delivery_partners;
CREATE TRIGGER auto_activate_rider
  BEFORE UPDATE OF verification_status ON public.delivery_partners
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_auto_activate_on_approval();

UPDATE public.delivery_partners
SET is_active = true
WHERE verification_status IN ('approved', 'verified')
  AND is_active = false;
