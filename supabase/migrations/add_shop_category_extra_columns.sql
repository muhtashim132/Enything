-- Migration: Add missing category-specific extra columns to the shops table
-- These columns correspond to the fields collected in CategoryExtraFields during seller sign up.

ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS fssai_number TEXT,
  ADD COLUMN IF NOT EXISTS food_type TEXT,
  ADD COLUMN IF NOT EXISTS avg_prep_time_mins INTEGER,
  ADD COLUMN IF NOT EXISTS packaging_charge NUMERIC DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS drug_license_number TEXT,
  ADD COLUMN IF NOT EXISTS pharmacist_name TEXT,
  ADD COLUMN IF NOT EXISTS accepts_returns BOOLEAN,
  ADD COLUMN IF NOT EXISTS order_cutoff TEXT,
  ADD COLUMN IF NOT EXISTS return_policy TEXT;

-- Refresh Column-Level Privileges for Shops
-- Since the shops table uses column-level RLS grants, new columns won't be readable to customers unless we re-grant them.
DO $$
DECLARE
  v_sensitive_shops TEXT[] := ARRAY[
    'aadhar_number', 'pan_number', 'gst_number',
    'trade_license', 'bank_account_number', 'bank_ifsc', 'bank_account_holder'
  ];
  v_cols_shops TEXT;
BEGIN
  -- Revoke existing select to cleanly re-apply
  REVOKE SELECT ON public.shops FROM authenticated;
  
  -- Gather all non-sensitive columns (including the ones we just added)
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_cols_shops
  FROM information_schema.columns
  WHERE table_schema = 'public' 
    AND table_name = 'shops' 
    AND column_name != ALL(v_sensitive_shops);
    
  -- Grant SELECT on the non-sensitive columns
  IF v_cols_shops IS NOT NULL THEN
    EXECUTE format('GRANT SELECT (%s) ON public.shops TO authenticated', v_cols_shops);
  END IF;
END;
$$;
