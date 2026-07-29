-- Migration: fix_delivery_partners_permissions.sql
-- Description: Refreshes column-level SELECT privileges for delivery_partners and reloads the schema cache.

DO $$
DECLARE
  v_sensitive_dps TEXT[] := ARRAY[
    'aadhar_number', 'insurance_number', 'pan_number', 'driving_license', 'vehicle_reg_number',
    'bank_account_number', 'bank_ifsc', 'bank_account_holder'
  ];
  v_cols_dps TEXT;
BEGIN
  -- Refresh delivery_partners
  REVOKE SELECT ON public.delivery_partners FROM authenticated;
  
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_cols_dps
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'delivery_partners' AND column_name != ALL(v_sensitive_dps);
  
  IF v_cols_dps IS NOT NULL THEN
    EXECUTE format('GRANT SELECT (%s) ON public.delivery_partners TO authenticated', v_cols_dps);
  END IF;
END;
$$;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
