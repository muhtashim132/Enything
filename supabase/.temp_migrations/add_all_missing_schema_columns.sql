-- ============================================================================
-- Migration: add_all_missing_schema_columns.sql
-- Description: Ensures all necessary columns exist for products, delivery_partners,
--              and shops to fix PostgREST schema cache errors.
--              Includes a schema cache reload command at the end.
-- ============================================================================

-- 1. Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- 2. Customers missing columns
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS address TEXT,
  ADD COLUMN IF NOT EXISTS location geography(Point, 4326);

-- 3. Products Table missing columns
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS category TEXT,
  ADD COLUMN IF NOT EXISTS sub_category TEXT,
  ADD COLUMN IF NOT EXISTS brand TEXT,
  ADD COLUMN IF NOT EXISTS original_price NUMERIC,
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS images JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS is_veg BOOLEAN,
  ADD COLUMN IF NOT EXISTS menu_category TEXT,
  ADD COLUMN IF NOT EXISTS prep_time_minutes INTEGER,
  ADD COLUMN IF NOT EXISTS special_tags JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS rating NUMERIC DEFAULT 4.0,
  ADD COLUMN IF NOT EXISTS requires_prescription BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS medicine_type TEXT DEFAULT 'General',
  ADD COLUMN IF NOT EXISTS weight_per_unit NUMERIC DEFAULT 0.5,
  ADD COLUMN IF NOT EXISTS unit_type TEXT DEFAULT 'pieces',
  ADD COLUMN IF NOT EXISTS total_quantity INTEGER DEFAULT NULL;

-- 2. Delivery Partners missing columns (KYC & Details)
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS aadhar_number TEXT,
  ADD COLUMN IF NOT EXISTS pan_number TEXT,
  ADD COLUMN IF NOT EXISTS driving_license TEXT,
  ADD COLUMN IF NOT EXISTS insurance_number TEXT,
  ADD COLUMN IF NOT EXISTS vehicle_reg_number TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_number TEXT,
  ADD COLUMN IF NOT EXISTS bank_ifsc TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_holder TEXT,
  ADD COLUMN IF NOT EXISTS kyc_documents JSONB,
  ADD COLUMN IF NOT EXISTS verification_status TEXT DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS location geography(Point, 4326),
  ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT false;

-- 3. Shops missing columns
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS kyc_documents JSONB,
  ADD COLUMN IF NOT EXISTS verification_status TEXT DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS banner_url TEXT,
  ADD COLUMN IF NOT EXISTS open_time TEXT DEFAULT '09:00',
  ADD COLUMN IF NOT EXISTS close_time TEXT DEFAULT '21:00',
  ADD COLUMN IF NOT EXISTS location geography(Point, 4326),
  ADD COLUMN IF NOT EXISTS average_rating NUMERIC DEFAULT 0.0;

-- 4. Refresh Column-Level Privileges for Shops and Delivery Partners
-- Since they use column-level RLS grants, new columns won't be readable unless we re-grant them.
DO $$
DECLARE
  v_sensitive_shops TEXT[] := ARRAY[
    'aadhar_number', 'pan_number', 'gst_number',
    'trade_license', 'bank_account_number', 'bank_ifsc', 'bank_account_holder'
  ];
  v_sensitive_dps TEXT[] := ARRAY[
    'aadhar_number', 'insurance_number', 'pan_number', 'driving_license', 'vehicle_reg_number',
    'bank_account_number', 'bank_ifsc', 'bank_account_holder'
  ];
  v_cols_shops TEXT;
  v_cols_dps TEXT;
BEGIN
  -- Refresh shops
  REVOKE SELECT ON public.shops FROM authenticated;
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_cols_shops
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'shops' AND column_name != ALL(v_sensitive_shops);
  IF v_cols_shops IS NOT NULL THEN
    EXECUTE format('GRANT SELECT (%s) ON public.shops TO authenticated', v_cols_shops);
  END IF;

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

-- 5. Reload PostgREST schema cache
-- This ensures that the PostgREST API is immediately aware of the new columns.
NOTIFY pgrst, 'reload schema';
