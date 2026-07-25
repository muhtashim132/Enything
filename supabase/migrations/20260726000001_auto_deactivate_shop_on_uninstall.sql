-- ============================================================================
-- Migration: 20260726000001_auto_deactivate_shop_on_uninstall.sql
-- Description: Auto-deactivate shop (and delivery partner) when the user
--   has zero active FCM device tokens. This specifically handles the edge case
--   where the app is uninstalled without logging out or closing the shop.
--
-- Constraints: Additive only. Does not alter any existing SQL logic.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.auto_deactivate_shop_on_no_devices()
RETURNS TRIGGER AS $$
DECLARE
    remaining_tokens INT;
    is_seller BOOLEAN;
    is_delivery BOOLEAN;
BEGIN
    -- Only proceed if we have a valid user_id
    IF OLD.user_id IS NULL THEN
        RETURN OLD;
    END IF;

    -- Check how many tokens remain for this user
    SELECT count(*) INTO remaining_tokens 
    FROM public.device_tokens 
    WHERE user_id = OLD.user_id;

    -- If no tokens remain, the user is completely offline on all devices
    IF remaining_tokens = 0 THEN
        -- Check and deactivate if they are a seller
        SELECT EXISTS(SELECT 1 FROM public.shops WHERE seller_id = OLD.user_id) INTO is_seller;
        IF is_seller THEN
            UPDATE public.shops 
            SET is_active = false 
            WHERE seller_id = OLD.user_id 
              AND is_active = true;
        END IF;

        -- Check and deactivate if they are a delivery partner
        SELECT EXISTS(SELECT 1 FROM public.delivery_partners WHERE id = OLD.user_id) INTO is_delivery;
        IF is_delivery THEN
            UPDATE public.delivery_partners 
            SET is_active = false 
            WHERE id = OLD.user_id 
              AND is_active = true;
        END IF;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure idempotency by dropping the trigger if it exists
DROP TRIGGER IF EXISTS tr_auto_deactivate_shop_on_no_devices ON public.device_tokens;

-- Create the trigger to fire AFTER DELETE
CREATE TRIGGER tr_auto_deactivate_shop_on_no_devices
AFTER DELETE ON public.device_tokens
FOR EACH ROW
EXECUTE FUNCTION public.auto_deactivate_shop_on_no_devices();
