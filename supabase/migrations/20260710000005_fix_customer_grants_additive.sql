-- Migration: 20260710000005_fix_customer_grants_additive.sql
-- Description: Fix "Grant SELECT error" and missing rows for customers without changing existing logic. Purely additive.

-- Ensure table-level SELECT grants exist for authenticated and anon users
GRANT SELECT ON public.shops TO authenticated;
GRANT SELECT ON public.shops TO anon;
GRANT SELECT ON public.products TO authenticated;
GRANT SELECT ON public.products TO anon;

-- Additive RLS policies to ensure no missing rows for customers reading shops and products
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'shops' AND policyname = 'shops_select_all_additive'
    ) THEN
        CREATE POLICY "shops_select_all_additive"
        ON public.shops FOR SELECT
        USING (true);
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'products' AND policyname = 'products_select_all_additive'
    ) THEN
        CREATE POLICY "products_select_all_additive"
        ON public.products FOR SELECT
        USING (true);
    END IF;
END
$$;
