-- =============================================================================
-- Migration: 100x Global Inventory Inflation Fortress (Phase 5)
-- Description:
--   1. Fixes a Catastrophic Cross-Tenant Inventory Inflation Exploit inside 
--      the global `restore_product_stock_on_cancel_stmt` trigger.
--   2. Injects strict Tenant Sandboxing (`JOIN products p ON ... p.shop_id = n.shop_id`)
--      to mathematically guarantee that a forged order can never maliciously 
--      inflate a competitor's inventory count out of thin air.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.restore_product_stock_on_cancel_stmt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_item RECORD;
BEGIN
  -- Aggregate all items from all newly cancelled orders in this statement update.
  -- The strict `ORDER BY oi.product_id` ensures that regardless of which orders 
  -- are cancelled concurrently, the database locks are acquired in the exact same sequence.
  FOR v_item IN
    SELECT oi.product_id, SUM(oi.quantity) as total_restored
    FROM new_orders n
    JOIN old_orders o ON n.id = o.id
    JOIN order_items oi ON oi.order_id = n.id
    -- 100x STRESS TEST FIX (Phase 5): Strict Tenant Sandboxing (Block Inventory Inflation Vandalism)
    JOIN products p ON p.id = oi.product_id AND p.shop_id = n.shop_id
    WHERE n.status IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider', 'payment_failed', 'timeout', 'shop_dispute', 'shop_dispute_cancel')
      AND o.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider', 'payment_failed', 'timeout', 'shop_dispute', 'shop_dispute_cancel')
      -- 100x FIX: Do NOT restore inventory if the physical items already left the restaurant.
      -- If it was picked up, out for delivery, or delivered, the food is gone. Ghost stock prevention.
      AND o.status NOT IN ('picked_up', 'out_for_delivery', 'delivered')
    GROUP BY oi.product_id
    ORDER BY oi.product_id
  LOOP
    UPDATE products
    SET total_quantity = total_quantity + v_item.total_restored
    WHERE id = v_item.product_id
      AND total_quantity IS NOT NULL;
  END LOOP;

  RETURN NULL;
END;
$function$;
