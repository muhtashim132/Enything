-- Migration: 20260710000004_fix_seller_grants_and_rls.sql
-- Description: Fix "Grant SELECT error" and missing rows for sellers without changing existing logic. Purely additive.

-- 1. Ensure table-level SELECT grants exist for authenticated users on all involved tables.
GRANT SELECT ON public.orders TO authenticated;
GRANT SELECT ON public.order_items TO authenticated;
GRANT SELECT ON public.shops TO authenticated;
GRANT SELECT ON public.ratings TO authenticated;
GRANT INSERT ON public.app_logs TO authenticated;

-- 2. Provide additive RLS policies to ensure no missing rows for sellers.
-- These use DO blocks to avoid errors if policies already exist.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'shops' AND policyname = 'shops_select_seller_additive'
    ) THEN
        CREATE POLICY "shops_select_seller_additive"
        ON public.shops FOR SELECT
        TO authenticated
        USING (seller_id = auth.uid());
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'orders' AND policyname = 'orders_select_seller_additive'
    ) THEN
        CREATE POLICY "orders_select_seller_additive"
        ON public.orders FOR SELECT
        TO authenticated
        USING (
            EXISTS (
                SELECT 1 FROM public.shops 
                WHERE shops.id = orders.shop_id AND shops.seller_id = auth.uid()
            )
        );
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'order_items' AND policyname = 'order_items_select_seller_additive'
    ) THEN
        CREATE POLICY "order_items_select_seller_additive"
        ON public.order_items FOR SELECT
        TO authenticated
        USING (
            EXISTS (
                SELECT 1 FROM public.orders
                JOIN public.shops ON shops.id = orders.shop_id
                WHERE orders.id = order_items.order_id AND shops.seller_id = auth.uid()
            )
        );
    END IF;
END
$$;

-- Grant INSERT on app_logs for the background logging to work without permission errors
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'app_logs' AND policyname = 'app_logs_insert_authenticated'
    ) THEN
        CREATE POLICY "app_logs_insert_authenticated"
        ON public.app_logs FOR INSERT
        TO authenticated
        WITH CHECK (true);
    END IF;
END
$$;
