-- Migration 20260872000000_100x_rebalance_fortress.sql
-- Fixes Phase 18: Cascading Negative Payout in Rebalance

CREATE OR REPLACE FUNCTION rebalance_active_delivery_fees(p_cart_group_id UUID)
RETURNS void AS $EX$
DECLARE
  v_active_count INT;
  v_total_delivery NUMERIC;
  v_total_surcharge NUMERIC;
  v_total_small NUMERIC;
  v_total_heavy NUMERIC;
  
  v_split_delivery NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
  
  rec RECORD;
BEGIN
  -- 1. Get active count
  SELECT COUNT(id) INTO v_active_count
  FROM orders
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup');
    
  IF v_active_count = 0 THEN RETURN; END IF;
  
  -- 2. Sum up all fees across ALL active orders
  SELECT 
    COALESCE(SUM(delivery_charges), 0),
    COALESCE(SUM(multi_shop_surcharge), 0),
    COALESCE(SUM(small_cart_fee), 0),
    COALESCE(SUM(heavy_order_fee), 0)
  INTO v_total_delivery, v_total_surcharge, v_total_small, v_total_heavy
  FROM orders
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup');
    
  v_split_delivery := v_total_delivery / v_active_count;
  v_split_surcharge := v_total_surcharge / v_active_count;
  v_split_small := v_total_small / v_active_count;
  v_split_heavy := v_total_heavy / v_active_count;
  
  -- 3. Update all active orders with the equal split
  FOR rec IN 
    SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, COALESCE(coupon_discount, 0) as coupon_discount, payment_status
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup')
  LOOP
    UPDATE orders
    SET delivery_charges = v_split_delivery,
        multi_shop_surcharge = v_split_surcharge,
        small_cart_fee = v_split_small,
        heavy_order_fee = v_split_heavy,
        -- 100x STRESS TEST FIX: Floor rider earnings at 0
        rider_earnings = GREATEST(0, ((v_split_delivery - (v_split_delivery * 0.18)) - v_split_small) * 0.80),
        gst_delivery = v_split_delivery * 0.18,
        grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_split_delivery + v_split_surcharge + v_split_small + v_split_heavy - rec.coupon_discount),
        grand_total_collected = CASE WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_split_delivery + v_split_surcharge + v_split_small + v_split_heavy - rec.coupon_discount) ELSE 0 END
    WHERE id = rec.id;
  END LOOP;
END;
$EX$ LANGUAGE plpgsql SECURITY DEFINER;
