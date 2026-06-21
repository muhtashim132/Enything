-- ============================================================================
-- Migration: 20260624000001_10x_customer_favorites_fix.sql
-- Description: 10x debug pass — creates the completely missing customer_favorites table
--              which caused silent failures across the app's favorites functionality.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.customer_favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES public.shops(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique constraints to prevent duplicate favorites (optimistic UI relies on toggle logic)
ALTER TABLE public.customer_favorites ADD CONSTRAINT customer_favorites_product_unique UNIQUE NULLS NOT DISTINCT (customer_id, product_id);
ALTER TABLE public.customer_favorites ADD CONSTRAINT customer_favorites_shop_unique UNIQUE NULLS NOT DISTINCT (customer_id, shop_id);

-- Indexes for quick lookups
CREATE INDEX IF NOT EXISTS idx_customer_favorites_customer ON public.customer_favorites (customer_id);

-- Grants
GRANT SELECT, INSERT, DELETE ON public.customer_favorites TO authenticated;

-- RLS Policies
ALTER TABLE public.customer_favorites ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'customer_favorites' AND policyname = 'Customers can manage their own favorites'
    ) THEN
        CREATE POLICY "Customers can manage their own favorites"
            ON public.customer_favorites FOR ALL TO authenticated
            USING (customer_id = auth.uid())
            WITH CHECK (customer_id = auth.uid());
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
