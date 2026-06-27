-- Migration: Add Product Variants (Size/Quantity)
-- Date: 2026-07-02 (Logical Date for Migration)

-- 1. Add `variants` JSONB to `products`
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS variants JSONB DEFAULT '[]'::jsonb;

-- 2. Add `variant_name` to `order_items`
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS variant_name TEXT;

-- 3. Ensure SELECT permissions are maintained to avoid "Grant SELECT error"
GRANT SELECT ON public.products TO anon, authenticated;
GRANT SELECT, INSERT ON public.order_items TO anon, authenticated;
