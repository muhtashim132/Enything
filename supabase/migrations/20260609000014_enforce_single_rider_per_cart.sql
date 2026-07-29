-- ============================================================================
-- Enforce Single Rider per Cart Group (Prevent Split Earnings Flaw)
-- ============================================================================

CREATE OR REPLACE FUNCTION check_single_rider_per_cart()
RETURNS TRIGGER AS $$
DECLARE
  existing_rider UUID;
BEGIN
  -- Only care if a rider is claiming the order
  IF NEW.delivery_partner_id IS NOT NULL AND OLD.delivery_partner_id IS NULL AND NEW.cart_group_id IS NOT NULL THEN
    -- Check if another order in the same cart already has a different rider
    SELECT delivery_partner_id INTO existing_rider
    FROM public.orders
    WHERE cart_group_id = NEW.cart_group_id
      AND delivery_partner_id IS NOT NULL
      AND id != NEW.id
    LIMIT 1;

    IF existing_rider IS NOT NULL AND existing_rider != NEW.delivery_partner_id THEN
      RAISE EXCEPTION 'Another delivery partner (%) has already claimed an order in this cart group (%)', existing_rider, NEW.cart_group_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_single_rider_per_cart ON public.orders;
CREATE TRIGGER trg_check_single_rider_per_cart
BEFORE UPDATE OF delivery_partner_id ON public.orders
FOR EACH ROW
EXECUTE FUNCTION check_single_rider_per_cart();
