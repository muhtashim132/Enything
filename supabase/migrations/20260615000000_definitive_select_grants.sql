-- ============================================================================
-- Migration: 20260615000000_definitive_select_grants.sql
-- Description: Definitively fixes "Grant SELECT error" on shops and products.
--              Ensures `anon` and `authenticated` roles can read the data and
--              reloads the PostgREST cache immediately.
-- ============================================================================

-- 1. Grant usage on schema public (usually present, but safe to repeat)
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- 2. Explicitly grant SELECT on shops and products
GRANT SELECT ON public.shops TO anon, authenticated;
GRANT SELECT ON public.products TO anon, authenticated;

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

-- 5. Force PostgREST to reload the schema and permissions cache
NOTIFY pgrst, 'reload schema';
