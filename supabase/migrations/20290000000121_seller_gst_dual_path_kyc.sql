-- ============================================================================
-- Migration: 20290000000121_seller_gst_dual_path_kyc.sql
-- Description: 100% Additive: Adds optional enrolment_id to shops and updates
--              submit_seller_kyc_v2 to safely record enrolment_id without
--              modifying RPC parameter signatures.
-- ============================================================================

-- 1. Safely add enrolment_id column to shops if it doesn't already exist
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS enrolment_id TEXT;

-- 2. Update submit_seller_kyc_v2 with exact same parameter signature
CREATE OR REPLACE FUNCTION public.submit_seller_kyc_v2(
  p_shop_id UUID,
  p_aadhar_number TEXT,
  p_pan_number TEXT,
  p_gst_number TEXT,
  p_trade_license TEXT,
  p_bank_account_holder TEXT,
  p_bank_account_number TEXT,
  p_bank_ifsc TEXT,
  p_kyc_documents JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verify the shop belongs to the currently authenticated user
  IF NOT EXISTS (
    SELECT 1 FROM public.shops 
    WHERE id = p_shop_id AND seller_id = auth.uid()
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
  WHERE id = p_shop_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_seller_kyc_v2(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) TO authenticated;
