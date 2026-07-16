-- Migration: 100x_rider_withdrawals_fix
-- Description: Creates get_rider_balance RPC to prevent Rider OOMs and UI balance spoofing.

-- 1. Create the RPC function securely matching the backend transaction logic
CREATE OR REPLACE FUNCTION get_rider_balance(p_rider_id UUID)
RETURNS JSON AS $$
DECLARE
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  -- Sum all positive earnings from delivered and valid cancelled orders
  SELECT COALESCE(SUM(COALESCE(rider_earnings, 0) + COALESCE(wait_time_penalty, 0)), 0) INTO v_total_earned
  FROM orders
  WHERE (status = 'delivered' OR (status = 'cancelled' AND rider_earnings > 0))
  AND delivery_partner_id = p_rider_id;

  -- Sum all valid withdrawals
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = p_rider_id
  AND user_role = 'delivery_partner'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  RETURN json_build_object(
    'total_earned', v_total_earned,
    'total_paid', v_total_paid,
    'available_balance', v_available_balance
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Grant execution permissions
GRANT EXECUTE ON FUNCTION get_rider_balance(UUID) TO authenticated;
