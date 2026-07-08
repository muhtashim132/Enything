-- =============================================================================
-- Migration: 100x Inventory Integrity Fix
-- Description:
--   1. Fixes Post-Delivery Ghost Stock: Adds a physical condition to 
--      `restore_product_stock_on_cancel`. If an order is cancelled by an 
--      Admin AFTER the food has physically left the kitchen (i.e. status was 
--      already `picked_up`, `out_for_delivery`, or `delivered`), the database 
--      will refuse to restore the inventory, correctly mirroring the physical loss.
--   2. Fixes Shop Dispute Stock Leak: Adds `shop_dispute` and 
--      `shop_dispute_cancel` to the cancellation state array so stock is 
--      correctly restored when a seller aborts an unfulfilled order.
-- =============================================================================

CREATE OR REPLACE FUNCTION restore_product_stock_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item_row RECORD;
BEGIN
  -- Only restore stock when transitioning INTO a terminal state
  IF NEW.status IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider', 'payment_failed', 'timeout', 'shop_dispute', 'shop_dispute_cancel')
     AND OLD.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider', 'payment_failed', 'timeout', 'shop_dispute', 'shop_dispute_cancel') THEN
     
     -- 100x FIX: Do NOT restore inventory if the physical items already left the restaurant.
     -- If it was picked up, out for delivery, or delivered, the food is gone. Ghost stock prevention.
     IF OLD.status NOT IN ('picked_up', 'out_for_delivery', 'delivered') THEN
        FOR item_row IN
          SELECT product_id, quantity FROM order_items WHERE order_id = NEW.id
        LOOP
          UPDATE products
          SET total_quantity = total_quantity + item_row.quantity
          WHERE id = item_row.product_id
            AND total_quantity IS NOT NULL;
        END LOOP;
     END IF;
  END IF;

  RETURN NEW;
END;
$$;
