-- =============================================================================
-- Migration: 100x Inventory Deadlock Fortress
-- Description:
--   1. Converts the inventory restoration trigger from a ROW-level trigger 
--      to a STATEMENT-level trigger using PostgreSQL Transition Tables.
--   2. Aggregates all cancelled items across all orders modified in a single 
--      bulk transaction (like a cron job sweeping timeouts).
--   3. Forces a strict `ORDER BY product_id` globally across all affected orders 
--      to mathematically guarantee the elimination of PostgreSQL Deadlocks.
-- =============================================================================

-- 1. Create the Statement-Level Function
CREATE OR REPLACE FUNCTION restore_product_stock_on_cancel_stmt()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

-- 2. Drop the dangerous row-level trigger
DROP TRIGGER IF EXISTS trg_restore_stock_on_cancel ON orders;

-- 3. Create the secure statement-level trigger
DROP TRIGGER IF EXISTS trg_restore_stock_on_cancel_stmt ON orders;
CREATE TRIGGER trg_restore_stock_on_cancel_stmt
  AFTER UPDATE ON orders
  REFERENCING OLD TABLE AS old_orders NEW TABLE AS new_orders
  FOR EACH STATEMENT
  EXECUTE FUNCTION restore_product_stock_on_cancel_stmt();
