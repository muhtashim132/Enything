-- 20260613000000_grant_select_shops_products.sql
-- Fixes the "Grant SELECT error" when fetching products with joined shop data.

-- 1. Grant SELECT privileges to anon and authenticated roles for the shops table
GRANT SELECT ON public.shops TO anon;
GRANT SELECT ON public.shops TO authenticated;

-- 2. Grant SELECT privileges to anon and authenticated roles for the products table
GRANT SELECT ON public.products TO anon;
GRANT SELECT ON public.products TO authenticated;

-- 3. Ensure RLS policies exist to allow public read access for shops
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'shops' AND c.relrowsecurity = true
    ) THEN
        DROP POLICY IF EXISTS "Enable read access for all users on shops" ON public.shops;
        CREATE POLICY "Enable read access for all users on shops" ON public.shops FOR SELECT USING (true);
    END IF;
END $$;

-- 4. Ensure RLS policies exist to allow public read access for products
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'products' AND c.relrowsecurity = true
    ) THEN
        DROP POLICY IF EXISTS "Enable read access for all users on products" ON public.products;
        CREATE POLICY "Enable read access for all users on products" ON public.products FOR SELECT USING (true);
    END IF;
END $$;
