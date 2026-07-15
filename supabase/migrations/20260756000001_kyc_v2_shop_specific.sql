CREATE OR REPLACE FUNCTION submit_seller_kyc_v2(
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
    SELECT 1 FROM shops 
    WHERE id = p_shop_id AND seller_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Shop does not belong to user';
  END IF;

  UPDATE shops
  SET 
    aadhar_number = p_aadhar_number,
    pan_number = p_pan_number,
    gst_number = p_gst_number,
    trade_license = p_trade_license,
    bank_account_holder = p_bank_account_holder,
    bank_account_number = p_bank_account_number,
    bank_ifsc = p_bank_ifsc,
    kyc_documents = p_kyc_documents,
    verification_status = 'pending'
  WHERE id = p_shop_id;
END;
$$;
GRANT EXECUTE ON FUNCTION submit_seller_kyc_v2(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) TO authenticated;
