-- ============================================================================
-- Migration: 20290000000137_100x_seller_kyc_null_shop_fallback.sql
-- Description: 100% Additive: Fortifies submit_seller_kyc_v2 RPC to automatically
--              resolve p_shop_id from the authenticated user's registered shop
--              if p_shop_id is NULL or omitted, preventing unhandled exceptions.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.submit_seller_kyc_v2(
  p_shop_id UUID DEFAULT NULL,
  p_aadhar_number TEXT DEFAULT NULL,
  p_pan_number TEXT DEFAULT NULL,
  p_gst_number TEXT DEFAULT NULL,
  p_trade_license TEXT DEFAULT NULL,
  p_bank_account_holder TEXT DEFAULT NULL,
  p_bank_account_number TEXT DEFAULT NULL,
  p_bank_ifsc TEXT DEFAULT NULL,
  p_kyc_documents JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shop_id UUID := p_shop_id;
BEGIN
  -- 100x Defense: If p_shop_id is NULL or not provided, automatically resolve the user's shop
  IF v_shop_id IS NULL THEN
    SELECT id INTO v_shop_id 
    FROM public.shops 
    WHERE seller_id = auth.uid() 
    ORDER BY created_at DESC 
    LIMIT 1;
  END IF;

  IF v_shop_id IS NULL THEN
    RAISE EXCEPTION 'No shop found for authenticated user: %', auth.uid();
  END IF;

  -- Verify the shop belongs to the currently authenticated user
  IF NOT EXISTS (
    SELECT 1 FROM public.shops 
    WHERE id = v_shop_id AND seller_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Shop does not belong to user';
  END IF;

  UPDATE public.shops
  SET 
    aadhar_number = p_aadhar_number,
    pan_number = p_pan_number,
    gst_number = NULLIF(trim(p_gst_number), ''),
    enrolment_id = NULLIF(trim(p_kyc_documents->>'enrolment_id'), ''),
    trade_license = p_trade_license,
    bank_account_holder = p_bank_account_holder,
    bank_account_number = p_bank_account_number,
    bank_ifsc = p_bank_ifsc,
    kyc_documents = p_kyc_documents,
    verification_status = 'pending'
  WHERE id = v_shop_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_seller_kyc_v2(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) TO authenticated, service_role;
