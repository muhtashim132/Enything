-- ============================================================================
-- Migration: fix_admin_rpc_no_email.sql
-- Fix: Remove p.email reference from admin_get_all_shops() and
-- admin_get_all_riders() since the profiles table has no email column.
-- ============================================================================

-- Fix admin_get_all_shops
CREATE OR REPLACE FUNCTION public.admin_get_all_shops()
RETURNS TABLE (
  id UUID,
  seller_id UUID,
  shop_name TEXT,
  category TEXT,
  logo_url TEXT,
  verification_status TEXT,
  is_active BOOLEAN,
  kyc_documents JSONB,
  aadhar_number TEXT,
  pan_number TEXT,
  gst_number TEXT,
  trade_license TEXT,
  bank_account_number TEXT,
  bank_ifsc TEXT,
  bank_account_holder TEXT,
  created_at TIMESTAMPTZ,
  profiles JSONB
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
    s.id, s.seller_id, s.name AS shop_name, s.category, NULL::TEXT AS logo_url,
    s.verification_status, s.is_active, s.kyc_documents,
    s.aadhar_number, s.pan_number, s.gst_number, s.trade_license,
    s.bank_account_number, s.bank_ifsc, s.bank_account_holder,
    s.created_at,
    jsonb_build_object(
      'full_name', p.full_name,
      'phone', p.phone
    ) AS profiles
  FROM public.shops s
  LEFT JOIN public.profiles p ON p.id = s.seller_id
  ORDER BY s.created_at DESC;
END;
$$;


-- Fix admin_get_all_riders
DROP FUNCTION IF EXISTS public.admin_get_all_riders();

CREATE OR REPLACE FUNCTION public.admin_get_all_riders()
RETURNS TABLE (
  id UUID,
  vehicle_type TEXT,
  vehicle_reg_number TEXT,
  insurance_number TEXT,
  driving_license TEXT,
  pan_number TEXT,
  verification_status TEXT,
  is_active BOOLEAN,
  is_available BOOLEAN,
  kyc_documents JSONB,
  aadhar_number TEXT,
  bank_account_number TEXT,
  bank_ifsc TEXT,
  bank_account_holder TEXT,
  created_at TIMESTAMPTZ,
  profiles JSONB
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
      'phone', p.phone
    ) AS profiles
  FROM public.delivery_partners dp
  LEFT JOIN public.profiles p ON p.id = dp.id
  ORDER BY dp.created_at DESC;
END;
$$;
