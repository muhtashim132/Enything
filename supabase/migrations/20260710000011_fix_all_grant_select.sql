-- Migration: 20260710000011_fix_all_grant_select.sql
-- Description: Fix "Grant SELECT error" on delivery partners and related tables without changing logic, purely additive.

-- Ensure table-level SELECT grants exist for authenticated users on essential tables
GRANT SELECT ON public.delivery_partners TO authenticated, anon;
GRANT SELECT ON public.orders TO authenticated, anon;
GRANT SELECT ON public.order_items TO authenticated, anon;
GRANT SELECT ON public.products TO authenticated, anon;
GRANT SELECT ON public.shops TO authenticated, anon;

-- Ensure an additive policy exists to allow delivery partners to select their own data
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'delivery_partners' AND policyname = 'delivery_partners_select_self_additive'
    ) THEN
        CREATE POLICY "delivery_partners_select_self_additive"
        ON public.delivery_partners FOR SELECT
        TO authenticated
        USING (id = auth.uid());
    END IF;
END
$$;
