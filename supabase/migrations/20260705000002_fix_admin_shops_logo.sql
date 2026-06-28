-- ============================================================================
-- Migration: 20260705000002_fix_admin_shops_logo.sql
-- Description: Fixes PostgrestException for missing s.logo_url column
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_get_all_shops();
CREATE OR REPLACE FUNCTION public.admin_get_all_shops()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- Only callable by active admins
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Permission denied: admin only';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',                   s.id,
      'seller_id',            s.seller_id,
      'shop_name',            s.name,       -- alias so Dart s['shop_name'] works
      'name',                 s.name,
      'category',             s.category,
      'address',              s.address,
      'is_active',            s.is_active,
      'verification_status',  s.verification_status,
      'logo_url',             NULL,         -- Fixed: 's.logo_url' does not exist in shops table
      'gst_number',           s.gst_number,
      'aadhar_number',        s.aadhar_number,
      'pan_number',           s.pan_number,
      'trade_license',        s.trade_license,
      'bank_account_number',  s.bank_account_number,
      'bank_ifsc',            s.bank_ifsc,
      'bank_account_holder',  s.bank_account_holder,
      'kyc_documents',        s.kyc_documents,
      'average_rating',       s.average_rating,
      'total_orders',         s.total_orders,
      'created_at',           s.created_at,
      'profiles', jsonb_build_object(
        'id',         p.id,
        'full_name',  COALESCE(p.full_name, p.name, 'Unknown'),
        'phone',      p.phone,
        'avatar_url', p.avatar_url
      )
    )
    ORDER BY s.created_at DESC
  )
  INTO v_result
  FROM public.shops s
  LEFT JOIN public.profiles p ON p.id = s.seller_id;

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_all_shops() TO authenticated;
