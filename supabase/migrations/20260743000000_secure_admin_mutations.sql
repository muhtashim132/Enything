-- =============================================================================
-- Migration: Secure Admin Mutations
-- Description: Revokes excessive UPDATE privileges on critical columns 
-- (role, kyc_status, verification_status, is_active, withdrawal status) from 
-- the authenticated role to prevent privilege escalation and bypasses. 
-- Introduces strict SECURITY DEFINER RPCs to handle these mutations securely.
-- =============================================================================

-- 1. Revoke Excessive Column Privileges
-- Prevent users from updating their own roles or KYC statuses
REVOKE UPDATE (role, kyc_status, verification_status) ON public.profiles FROM authenticated;

-- Prevent shops from updating their KYC status or active status
REVOKE UPDATE (verification_status, is_active) ON public.shops FROM authenticated;

-- Prevent delivery partners from updating their KYC status or active status
REVOKE UPDATE (verification_status, is_active) ON public.delivery_partners FROM authenticated;

-- Prevent users from updating the status of their own withdrawals
REVOKE UPDATE ON public.withdrawals FROM authenticated;
-- Only allow authenticated users to view and insert withdrawals
GRANT SELECT, INSERT ON public.withdrawals TO authenticated;


-- 2. Create Secure Admin RPCs

-- A. Process Withdrawal
CREATE OR REPLACE FUNCTION admin_process_withdrawal(
  p_withdrawal_id UUID, 
  p_status TEXT, 
  p_transaction_id TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status text;
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT status INTO v_current_status
  FROM withdrawals WHERE id = p_withdrawal_id FOR UPDATE;

  IF v_current_status != 'pending' THEN
    RAISE EXCEPTION 'Withdrawal is already %', v_current_status;
  END IF;

  IF p_status NOT IN ('processed', 'rejected') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;

  UPDATE withdrawals
  SET 
    status = p_status,
    transaction_id = p_transaction_id,
    processed_at = CASE WHEN p_status = 'processed' THEN NOW() ELSE NULL END
  WHERE id = p_withdrawal_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_process_withdrawal(UUID, TEXT, TEXT) TO authenticated;


-- B. Update KYC Status
CREATE OR REPLACE FUNCTION admin_update_kyc(
  p_target_id UUID, 
  p_type TEXT, 
  p_status TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  IF p_status NOT IN ('verified', 'approved', 'rejected', 'pending') THEN
    RAISE EXCEPTION 'Invalid KYC status: %', p_status;
  END IF;

  IF p_type = 'customer' THEN
    UPDATE profiles
    SET kyc_status = p_status, verification_status = p_status
    WHERE id = p_target_id;
  ELSIF p_type = 'shop' OR p_type = 'seller' THEN
    UPDATE shops
    SET verification_status = p_status
    WHERE id = p_target_id;
  ELSIF p_type = 'rider' OR p_type = 'delivery_partner' THEN
    UPDATE delivery_partners
    SET verification_status = p_status
    WHERE id = p_target_id;
  ELSE
    RAISE EXCEPTION 'Invalid entity type: %', p_type;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_kyc(UUID, TEXT, TEXT) TO authenticated;


-- C. Toggle Active Status (Ban/Unban)
CREATE OR REPLACE FUNCTION admin_toggle_active(
  p_target_id UUID, 
  p_type TEXT, 
  p_is_active BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  IF p_type = 'customer' THEN
    UPDATE profiles
    SET is_active = p_is_active
    WHERE id = p_target_id;
  ELSIF p_type = 'shop' OR p_type = 'seller' THEN
    UPDATE shops
    SET is_active = p_is_active
    WHERE id = p_target_id;
  ELSIF p_type = 'rider' OR p_type = 'delivery_partner' THEN
    UPDATE delivery_partners
    SET is_active = p_is_active
    WHERE id = p_target_id;
  ELSE
    RAISE EXCEPTION 'Invalid entity type: %', p_type;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_toggle_active(UUID, TEXT, BOOLEAN) TO authenticated;


-- D. Update User Role
CREATE OR REPLACE FUNCTION admin_update_role(
  p_user_id UUID, 
  p_role TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Optional: Prevent super admins from modifying themselves if desired
  -- Or just ensure only valid roles can be set
  IF p_role NOT IN ('admin', 'finance_admin', 'support_admin', 'viewer', 'customer', 'seller', 'delivery_partner') THEN
    RAISE EXCEPTION 'Invalid role: %', p_role;
  END IF;

  UPDATE profiles
  SET role = p_role
  WHERE id = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_update_role(UUID, TEXT) TO authenticated;
