-- =============================================================================
-- Migration: Secure Admin RPCs
-- Description: Injects strict is_active_admin checks into all vulnerable 
-- SECURITY DEFINER admin RPCs to prevent privilege escalation.
-- =============================================================================

-- 1. admin_cancel_order
CREATE OR REPLACE FUNCTION admin_cancel_order(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status IN ('cancelled', 'delivered') THEN
    RAISE EXCEPTION 'Order is already %', v_status;
  END IF;

  UPDATE orders
  SET
    status           = 'cancelled',
    cancelled_reason = 'admin',
    refund_status    = CASE
                         WHEN v_payment_status = 'captured' THEN 'processing'
                         ELSE refund_status
                       END
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_cancel_order(UUID) TO authenticated;


-- 2. admin_issue_refund
CREATE OR REPLACE FUNCTION admin_issue_refund(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status = 'delivered' THEN
    RAISE EXCEPTION 'Cannot refund a delivered order directly without dispute';
  END IF;

  IF v_status IN ('cancelled', 'seller_rejected', 'verification_failed', 'shop_dispute') THEN
    IF v_payment_status != 'captured' THEN
      RAISE EXCEPTION 'Order % has no captured payment to refund.', p_order_id;
    END IF;
    UPDATE orders
    SET refund_status = 'processing'
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET
      status           = 'cancelled',
      refund_status    = 'processing',
      cancelled_reason = 'admin_refund'
    WHERE id = p_order_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_issue_refund(UUID) TO authenticated;


-- 3. admin_get_overview_stats
CREATE OR REPLACE FUNCTION admin_get_overview_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_orders INT;
  v_total_revenue NUMERIC;
  v_total_users INT;
  v_pending_kyc INT;
  v_pending_withdrawals INT;
  v_revenue_spots JSONB;
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT COUNT(*) INTO v_total_orders FROM orders 
  WHERE status NOT IN ('awaiting_acceptance', 'awaiting_payment') 
  AND NOT (status IN ('cancelled', 'seller_rejected', 'partner_rejected') AND payment_status != 'captured');

  SELECT COALESCE(SUM(grand_total_collected), 0) INTO v_total_revenue 
  FROM orders WHERE payment_status = 'captured'
  AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'shop_dispute_cancel');

  SELECT COUNT(*) INTO v_total_users FROM profiles;

  SELECT COUNT(*) INTO v_pending_kyc FROM shops WHERE verification_status = 'pending';

  BEGIN
    SELECT COUNT(*) INTO v_pending_withdrawals FROM withdrawals WHERE status = 'pending';
  EXCEPTION WHEN OTHERS THEN
    v_pending_withdrawals := 0;
  END;

  WITH days AS (
    SELECT generate_series(CURRENT_DATE - INTERVAL '6 days', CURRENT_DATE, '1 day')::date AS d
  ),
  daily_rev AS (
    SELECT (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata')::date AS d, SUM(grand_total_collected) as rev
    FROM orders
    WHERE payment_status = 'captured' AND created_at >= (CURRENT_DATE - INTERVAL '6 days')
    GROUP BY 1
  )
  SELECT jsonb_agg(jsonb_build_object('date', days.d, 'revenue', COALESCE(daily_rev.rev, 0))) INTO v_revenue_spots
  FROM days LEFT JOIN daily_rev ON days.d = daily_rev.d;

  RETURN jsonb_build_object(
    'total_orders', v_total_orders,
    'total_revenue', v_total_revenue,
    'total_users', v_total_users,
    'pending_kyc', v_pending_kyc,
    'pending_withdrawals', v_pending_withdrawals,
    'revenue_spots', COALESCE(v_revenue_spots, '[]'::jsonb)
  );
END;
$$;


-- 4. admin_get_analytics_stats
CREATE OR REPLACE FUNCTION admin_get_analytics_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_orders INT;
  v_delivered_orders INT;
  v_cancelled_orders INT;
  v_avg_order_value NUMERIC;
  v_orders_by_status JSONB;
  v_hourly_distribution JSONB;
  v_top_sellers JSONB;
  v_top_riders JSONB;
  v_new_users_today INT;
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT COUNT(*), 
         COUNT(*) FILTER (WHERE status = 'delivered'),
         COUNT(*) FILTER (WHERE status = 'cancelled'),
         COALESCE(AVG(COALESCE(grand_total_collected, total_amount)), 0)
  INTO v_total_orders, v_delivered_orders, v_cancelled_orders, v_avg_order_value
  FROM orders;

  SELECT jsonb_object_agg(status, cnt) INTO v_orders_by_status
  FROM (SELECT status, COUNT(*) as cnt FROM orders GROUP BY status) t;

  SELECT jsonb_object_agg(h::text, cnt) INTO v_hourly_distribution
  FROM (
    SELECT EXTRACT(HOUR FROM (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata'))::int AS h, COUNT(*) as cnt
    FROM orders WHERE created_at >= (CURRENT_DATE - INTERVAL '7 days')
    GROUP BY h
  ) t;

  SELECT jsonb_agg(jsonb_build_object('name', COALESCE(s.name, 'Unknown'), 'orders', t.cnt)) INTO v_top_sellers
  FROM (SELECT shop_id, COUNT(*) as cnt FROM orders WHERE shop_id IS NOT NULL GROUP BY shop_id ORDER BY cnt DESC LIMIT 5) t
  LEFT JOIN shops s ON t.shop_id = s.id;

  SELECT jsonb_agg(jsonb_build_object('name', COALESCE(p.full_name, 'Unknown Rider'), 'orders', t.cnt)) INTO v_top_riders
  FROM (SELECT delivery_partner_id, COUNT(*) as cnt FROM orders WHERE delivery_partner_id IS NOT NULL GROUP BY delivery_partner_id ORDER BY cnt DESC LIMIT 5) t
  LEFT JOIN profiles p ON t.delivery_partner_id = p.id;

  SELECT COUNT(*) INTO v_new_users_today FROM profiles WHERE created_at >= CURRENT_DATE::timestamp;

  RETURN jsonb_build_object(
    'total_orders', v_total_orders,
    'delivered_orders', v_delivered_orders,
    'cancelled_orders', v_cancelled_orders,
    'avg_order_value', v_avg_order_value,
    'orders_by_status', COALESCE(v_orders_by_status, '{}'::jsonb),
    'hourly_distribution', COALESCE(v_hourly_distribution, '{}'::jsonb),
    'top_sellers', COALESCE(v_top_sellers, '[]'::jsonb),
    'top_riders', COALESCE(v_top_riders, '[]'::jsonb),
    'new_users_today', v_new_users_today
  );
END;
$$;


-- 5. admin_get_finance_stats
CREATE OR REPLACE FUNCTION admin_get_finance_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gmv NUMERIC;
  v_pure_profit NUMERIC;
  v_seller_payouts NUMERIC;
  v_rider_earnings NUMERIC;
  v_pending_settlements INT;
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT 
    COALESCE(SUM(grand_total_collected), 0),
    COALESCE(SUM(
      COALESCE(enything_commission, 0) + 
      (COALESCE(platform_fee, 0) - COALESCE(gst_platform, 0)) + 
      (COALESCE(delivery_charges, 0) - COALESCE(gst_delivery, 0) - COALESCE(rider_earnings, 0)) - 
      COALESCE(gateway_deduction, 0)
    ), 0)
  INTO v_gmv, v_pure_profit
  FROM orders WHERE status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'shop_dispute_cancel');

  SELECT 
    COALESCE(SUM(COALESCE(seller_payout, 0) - COALESCE(tds_amount, 0) - COALESCE(tcs_amount, 0)), 0),
    COALESCE(SUM(rider_earnings), 0),
    COUNT(*)
  INTO v_seller_payouts, v_rider_earnings, v_pending_settlements
  FROM orders WHERE status = 'delivered';

  RETURN jsonb_build_object(
    'gmv', v_gmv,
    'pure_profit', v_pure_profit,
    'seller_payouts', v_seller_payouts,
    'rider_earnings', v_rider_earnings,
    'pending_settlements', v_pending_settlements
  );
END;
$$;


-- 6. admin_get_gst_statement
CREATE OR REPLACE FUNCTION admin_get_gst_statement(p_month INT, p_year INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_s9_5_gst NUMERIC;
  v_delivery_gst NUMERIC;
  v_platform_gst NUMERIC;
  v_commission_gst NUMERIC;
  v_non_food_gst NUMERIC;
  v_tcs NUMERIC;
  v_tds NUMERIC;
  v_delivered_orders INT;
  v_grouped_items JSONB;
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  WITH bounds AS (
    SELECT make_date(p_year, p_month, 1) AS start_date,
           (make_date(p_year, p_month, 1) + INTERVAL '1 month') AS end_date
  ),
  delivered_orders AS (
    SELECT * FROM orders 
    WHERE status = 'delivered' 
      AND (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata') >= (SELECT start_date FROM bounds)
      AND (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata') < (SELECT end_date FROM bounds)
  )
  SELECT 
    COALESCE(SUM(s9_5_gst_amount), 0),
    COALESCE(SUM(gst_delivery), 0),
    COALESCE(SUM(gst_platform), 0),
    COALESCE(SUM(enything_commission * 0.18), 0),
    COALESCE(SUM(non_food_gst_amount), 0),
    COALESCE(SUM(tcs_amount), 0),
    COALESCE(SUM(tds_amount), 0),
    COUNT(*)
  INTO v_s9_5_gst, v_delivery_gst, v_platform_gst, v_commission_gst, v_non_food_gst, v_tcs, v_tds, v_delivered_orders
  FROM delivered_orders;

  WITH delivered_orders AS (
    SELECT id FROM orders 
    WHERE status = 'delivered' 
      AND (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata') >= make_date(p_year, p_month, 1)
      AND (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata') < (make_date(p_year, p_month, 1) + INTERVAL '1 month')
  )
  SELECT jsonb_agg(jsonb_build_object(
    'category', COALESCE(p.category, 'Other'),
    'price', COALESCE(t.price, 0),
    'quantity', t.total_qty
  )) INTO v_grouped_items
  FROM (
    SELECT product_id, price, SUM(quantity) as total_qty
    FROM order_items oi
    JOIN delivered_orders o ON oi.order_id = o.id
    GROUP BY product_id, price
  ) t
  LEFT JOIN products p ON t.product_id = p.id;

  RETURN jsonb_build_object(
    's9_5_gst', v_s9_5_gst,
    'delivery_gst', v_delivery_gst,
    'platform_gst', v_platform_gst,
    'commission_gst', v_commission_gst,
    'non_food_gst', v_non_food_gst,
    'tcs', v_tcs,
    'tds', v_tds,
    'delivered_orders', v_delivered_orders,
    'grouped_items', COALESCE(v_grouped_items, '[]'::jsonb)
  );
END;
$$;
