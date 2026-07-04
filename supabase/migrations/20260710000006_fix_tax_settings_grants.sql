-- Migration: 20260710000006_fix_tax_settings_grants.sql
-- Description: Fix "Grant SELECT error" and missing rows/columns by strictly adding proper RLS policies and SELECT grants.

-- 1. Ensure table-level SELECT grants exist for authenticated users and anon users on tax_config and product_gst_overrides.
GRANT SELECT ON public.product_gst_overrides TO anon, authenticated;
GRANT SELECT ON public.tax_config TO anon, authenticated;

-- Ensure SELECT on products columns for anon/authenticated (specifically the gst_rate_override)
GRANT SELECT (gst_rate_override) ON public.products TO anon, authenticated;

-- 2. Provide additive RLS policies to ensure no missing rows for reads.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'product_gst_overrides' AND policyname = 'product_gst_overrides_select_additive'
    ) THEN
        CREATE POLICY "product_gst_overrides_select_additive"
        ON public.product_gst_overrides FOR SELECT
        TO anon, authenticated
        USING (true);
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'tax_config' AND policyname = 'tax_config_select_additive'
    ) THEN
        CREATE POLICY "tax_config_select_additive"
        ON public.tax_config FOR SELECT
        TO anon, authenticated
        USING (true);
    END IF;
END
$$;

-- 3. Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
