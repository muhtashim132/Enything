-- =============================================================================
-- Migration: 20260851000000_auto_activate_approved_shops.sql
-- Description: Additive trigger to automatically activate shops and riders
--              when their KYC verification_status is set to approved or verified.
--              Also includes a retroactive fix for currently stuck test accounts.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trg_auto_activate_on_approval()
RETURNS trigger AS $$
BEGIN
  IF NEW.verification_status IN ('approved', 'verified') AND OLD.verification_status NOT IN ('approved', 'verified') THEN
    NEW.is_active = true;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS auto_activate_shop ON public.shops;
CREATE TRIGGER auto_activate_shop
  BEFORE UPDATE OF verification_status ON public.shops
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_auto_activate_on_approval();

DROP TRIGGER IF EXISTS auto_activate_rider ON public.delivery_partners;
CREATE TRIGGER auto_activate_rider
  BEFORE UPDATE OF verification_status ON public.delivery_partners
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_auto_activate_on_approval();

-- Retroactively activate any shops/riders that are already approved but inactive
UPDATE public.shops 
SET is_active = true 
WHERE verification_status IN ('approved', 'verified') AND is_active = false;

UPDATE public.delivery_partners 
SET is_active = true 
WHERE verification_status IN ('approved', 'verified') AND is_active = false;
