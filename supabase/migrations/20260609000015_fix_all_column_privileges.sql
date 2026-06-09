-- ============================================================================
-- Migration: 20260609000015_fix_all_column_privileges.sql
-- Description: Re-grants SELECT privileges for all non-sensitive columns 
--              added to shops and delivery_partners tables to authenticated users.
--              This fixes "Permission denied" errors for vehicle_type, pincode, etc.
-- ============================================================================

-- 1. Fix shops table column privileges
DO $$
DECLARE
  v_sensitive TEXT[] := ARRAY[
    'aadhar_number', 'pan_number', 'gst_number',
    'trade_license', 'bank_account_number', 'bank_ifsc', 'bank_account_holder'
  ];
  v_cols TEXT;
BEGIN
  -- Revoke full table SELECT first to reset
  REVOKE SELECT ON public.shops FROM authenticated;

  -- Build a comma-separated list of safe (non-sensitive) columns
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_cols
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name   = 'shops'
    AND column_name != ALL(v_sensitive);

  -- Grant SELECT only on those safe columns
  IF v_cols IS NOT NULL THEN
    EXECUTE format('GRANT SELECT (%s) ON public.shops TO authenticated', v_cols);
  END IF;
END;
$$;

-- 2. Fix delivery_partners table column privileges
DO $$
DECLARE
  v_sensitive TEXT[] := ARRAY[
    'aadhar_number', 'insurance_number', 'driving_license', 'pan_number',
    'bank_account_number', 'bank_ifsc', 'bank_account_holder'
  ];
  v_cols TEXT;
BEGIN
  -- Revoke full table SELECT first to reset
  REVOKE SELECT ON public.delivery_partners FROM authenticated;

  -- Build a comma-separated list of safe (non-sensitive) columns
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_cols
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name   = 'delivery_partners'
    AND column_name != ALL(v_sensitive);

  -- Grant SELECT only on those safe columns
  IF v_cols IS NOT NULL THEN
    EXECUTE format('GRANT SELECT (%s) ON public.delivery_partners TO authenticated', v_cols);
  END IF;
END;
$$;
