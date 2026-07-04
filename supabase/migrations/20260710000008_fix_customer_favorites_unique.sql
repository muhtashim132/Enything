-- Migration: 20260710000008_fix_customer_favorites_unique.sql
-- Description: Fixes unique constraints for customer favorites to avoid NULLS NOT DISTINCT bug, allowing users to select multiple shops/products as favorites. Ensures proper SELECT permissions for service_role and anon.

-- Drop the buggy constraints
ALTER TABLE public.customer_favorites DROP CONSTRAINT IF EXISTS customer_favorites_product_unique;
ALTER TABLE public.customer_favorites DROP CONSTRAINT IF EXISTS customer_favorites_shop_unique;

-- Add standard UNIQUE constraints (which default to NULLS DISTINCT in PostgreSQL)
ALTER TABLE public.customer_favorites ADD CONSTRAINT customer_favorites_product_unique UNIQUE (customer_id, product_id);
ALTER TABLE public.customer_favorites ADD CONSTRAINT customer_favorites_shop_unique UNIQUE (customer_id, shop_id);

-- Ensure anon, authenticated, and service_role have full necessary access.
-- This fixes the 'Grant SELECT error' when accessing via service_role or other roles.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.customer_favorites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.customer_favorites TO service_role;
GRANT SELECT ON public.customer_favorites TO anon;

-- Ensure schema usage is granted
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
