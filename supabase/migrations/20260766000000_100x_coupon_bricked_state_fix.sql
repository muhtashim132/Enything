-- =============================================================================
-- Migration: 100x Bricked State Cancellation Fix (Coupon Leakage)
-- Description:
--   1. Fixes the `restore_coupon_usage_stmt` trigger which incorrectly 
--      decremented `current_uses` (a non-existent column). This caused a fatal 
--      SQL error when any order with a coupon was cancelled, effectively 
--      bricking the cancellation state machine and locking funds/orders forever.
--      Now correctly decrements the `usage_count` column.
-- =============================================================================

CREATE OR REPLACE FUNCTION restore_coupon_usage_stmt()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Find the counts of coupons to decrement. We only decrement if a group is FULLY cancelled.
  WITH cancelled_orders AS (
      SELECT n.coupon_id, n.cart_group_id, n.id
      FROM new_orders n
      JOIN old_orders o ON n.id = o.id
      WHERE n.coupon_id IS NOT NULL
        AND n.status IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
        AND o.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
  ),
  decrements AS (
      SELECT coupon_id, COUNT(DISTINCT COALESCE(cart_group_id::text, id::text)) as dec_count
      FROM cancelled_orders c
      WHERE NOT EXISTS (
          SELECT 1 FROM orders o2
          WHERE o2.cart_group_id = c.cart_group_id
            AND o2.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
      )
      GROUP BY coupon_id
  )
  UPDATE coupons c
  SET usage_count = GREATEST(c.usage_count - d.dec_count, 0)
  FROM decrements d
  WHERE c.id = d.coupon_id;

  RETURN NULL;
END;
$$;
