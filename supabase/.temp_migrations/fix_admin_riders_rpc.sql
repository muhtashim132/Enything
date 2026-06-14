-- ============================================================================
-- Migration: fix_admin_riders_rpc.sql
-- Description: Adds pan_number and driving_license to admin_get_all_riders()
-- so the KYC Review page shows full rider documents.
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_get_all_riders();

CREATE OR REPLACE FUNCTION public.admin_get_all_riders()
RETURNS TABLE (
  id                  UUID,
  vehicle_type        TEXT,
  vehicle_reg_number  TEXT,
  insurance_number    TEXT,
  driving_license     TEXT,
  pan_number          TEXT,
  verification_status TEXT,
  is_active           BOOLEAN,
  is_available        BOOLEAN,
  kyc_documents       JSONB,
  aadhar_number       TEXT,
  bank_account_number TEXT,
  bank_ifsc           TEXT,
  bank_account_holder TEXT,
  created_at          TIMESTAMPTZ,
  profiles            JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  SELECT 
    dp.id, dp.vehicle_type, dp.vehicle_reg_number, dp.insurance_number,
    dp.driving_license, dp.pan_number,
    dp.verification_status, dp.is_active, dp.is_available, dp.kyc_documents,
    dp.aadhar_number, dp.bank_account_number, dp.bank_ifsc, dp.bank_account_holder,
    dp.created_at,
    jsonb_build_object(
      'full_name', p.full_name,
      'email', p.email,
      'phone', p.phone,
      'avatar_url', p.avatar_url
    ) AS profiles
  FROM public.delivery_partners dp
  LEFT JOIN public.profiles p ON p.id = dp.id
  ORDER BY dp.created_at DESC;
END;
$$;
