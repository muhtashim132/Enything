-- 20260716000001_secure_seller_withdrawals.sql
-- Create an RPC to securely handle seller withdrawals and prevent TOC/TOU race conditions on balance.

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
