-- Add Supabase RPC for seller daily stats

CREATE OR REPLACE FUNCTION get_seller_daily_stats(p_shop_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_orders integer := 0;
    v_pending_orders integer := 0;
    v_todays_earning numeric := 0.0;
    v_products integer := 0;
BEGIN
    -- Get total orders
    SELECT count(*) INTO v_total_orders
    FROM orders
    WHERE shop_id = p_shop_id
      AND status NOT IN ('cancelled', 'seller_rejected');

    -- Get pending orders
    SELECT count(*) INTO v_pending_orders
    FROM orders
    WHERE shop_id = p_shop_id
      AND status IN ('pending', 'awaiting_acceptance');

    -- Get today's earnings
    SELECT COALESCE(SUM(
        COALESCE(seller_payout, 0) - COALESCE(tds_amount, 0) - COALESCE(tcs_amount, 0)
    ), 0.0) INTO v_todays_earning
    FROM orders
    WHERE shop_id = p_shop_id
      AND status = 'delivered'
      AND DATE(created_at AT TIME ZONE 'Asia/Kolkata') = DATE(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata');

    -- Get products count
    SELECT count(*) INTO v_products
    FROM products
    WHERE shop_id = p_shop_id;

    RETURN json_build_object(
        'total_orders', v_total_orders,
        'pending_orders', v_pending_orders,
        'todays_earning', v_todays_earning,
        'products', v_products
    );
END;
$$;

-- Grant execute
GRANT EXECUTE ON FUNCTION get_seller_daily_stats(uuid) TO authenticated;
