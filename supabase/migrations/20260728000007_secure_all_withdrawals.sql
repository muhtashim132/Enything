-- =============================================================================
-- Migration: Secure All Withdrawals (Sellers and Riders)
-- Description: Creates request_rider_withdrawal, adds transaction-level locking
-- to both withdrawal RPCs to prevent TOCTOU race conditions, and removes direct
-- INSERT access on the withdrawals table.
-- =============================================================================

-- 1. Revoke direct INSERT on withdrawals from authenticated role to force RPC usage
REVOKE INSERT ON public.withdrawals FROM authenticated;
-- Ensure service_role still has access
GRANT SELECT, INSERT, UPDATE, DELETE ON public.withdrawals TO service_role;

-- 2. Secure Seller Withdrawal (Adding explicit locking)
CREATE OR REPLACE FUNCTION request_seller_withdrawal(
  p_amount NUMERIC,
  p_upi_id TEXT DEFAULT NULL,
  p_bank_account_number TEXT DEFAULT NULL,
  p_bank_ifsc TEXT DEFAULT NULL,
  p_bank_account_holder TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  v_user_id UUID;
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Acquire an advisory lock to serialize withdrawal requests for this user
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

  -- Calculate total earned across all shops owned by the seller
  SELECT COALESCE(SUM(seller_payout), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND shop_id IN (SELECT id FROM shops WHERE seller_id = v_user_id);

  -- Calculate total paid (or pending)
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = v_user_id
  AND user_role = 'seller'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  IF p_amount > v_available_balance THEN
    RAISE EXCEPTION 'Insufficient balance. Available: %', v_available_balance;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  -- Insert withdrawal
  INSERT INTO withdrawals (
    user_id, user_role, amount, upi_id, bank_account_number, bank_ifsc, bank_account_holder, status
  ) VALUES (
    v_user_id, 'seller', p_amount, p_upi_id, p_bank_account_number, p_bank_ifsc, p_bank_account_holder, 'pending'
  );

  RETURN json_build_object('success', true, 'remaining_balance', v_available_balance - p_amount);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION request_seller_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- 3. Create Secure Rider Withdrawal RPC
CREATE OR REPLACE FUNCTION request_rider_withdrawal(
  p_amount NUMERIC,
  p_upi_id TEXT DEFAULT NULL,
  p_bank_account_number TEXT DEFAULT NULL,
  p_bank_ifsc TEXT DEFAULT NULL,
  p_bank_account_holder TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  v_user_id UUID;
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Acquire an advisory lock to serialize withdrawal requests for this user
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

  -- Calculate total earned by the rider
  SELECT COALESCE(SUM(rider_earnings), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND delivery_partner_id = v_user_id;

  -- Calculate total paid (or pending)
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = v_user_id
  AND user_role = 'delivery_partner'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  IF p_amount > v_available_balance THEN
    RAISE EXCEPTION 'Insufficient balance. Available: %', v_available_balance;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  -- Insert withdrawal
  INSERT INTO withdrawals (
    user_id, user_role, amount, upi_id, bank_account_number, bank_ifsc, bank_account_holder, status
  ) VALUES (
    v_user_id, 'delivery_partner', p_amount, p_upi_id, p_bank_account_number, p_bank_ifsc, p_bank_account_holder, 'pending'
  );

  RETURN json_build_object('success', true, 'remaining_balance', v_available_balance - p_amount);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION request_rider_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
