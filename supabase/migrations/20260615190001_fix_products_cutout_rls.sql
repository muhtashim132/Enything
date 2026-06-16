-- ============================================================================
-- Migration: 20260615190001_fix_products_cutout_rls.sql
-- Description: Ensures that cutout_url (and all product columns) are readable
--              by anon and authenticated roles. The previous migration only
--              added column-level GRANTs which may be overridden by RLS.
--              This migration adds explicit policies so Flutter's SELECT queries
--              always return cutout_url.
-- ============================================================================

-- ── 1. Full table-level GRANT (idempotent) ───────────────────────────────
-- Ensures no column is accidentally excluded by column-level permissions.
GRANT SELECT ON public.products TO anon;
GRANT SELECT ON public.products TO authenticated;
GRANT SELECT ON public.products TO service_role;

-- ── 2. Grant INSERT/UPDATE/DELETE to authenticated (seller writes) ───────
GRANT INSERT, UPDATE, DELETE ON public.products TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.products TO service_role;

-- ── 3. Ensure cutout_url UPDATE grant to service_role is in place ────────
GRANT UPDATE (cutout_url) ON public.products TO service_role;

-- ── 4. RLS Policies ─────────────────────────────────────────────────────
-- Check if RLS is enabled on products. If so, we need permissive SELECT
-- policies so customers (anon) and authenticated users can read all products.

-- Allow anyone to read available products (customer-facing)
DO $$
BEGIN
  -- Public product reads (anon — customer browsing without login)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'products'
      AND policyname = 'Products are publicly readable'
  ) THEN
    CREATE POLICY "Products are publicly readable"
      ON public.products
      FOR SELECT
      TO anon, authenticated
      USING (true);
  END IF;

  -- Authenticated users can insert products for their shop
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'products'
      AND policyname = 'Sellers can insert their own products'
  ) THEN
    CREATE POLICY "Sellers can insert their own products"
      ON public.products
      FOR INSERT
      TO authenticated
      WITH CHECK (
        shop_id IN (
          SELECT id FROM public.shops WHERE seller_id = auth.uid()
        )
      );
  END IF;

  -- Authenticated users can update/delete products belonging to their shop
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'products'
      AND policyname = 'Sellers can manage their own products'
  ) THEN
    CREATE POLICY "Sellers can manage their own products"
      ON public.products
      FOR ALL
      TO authenticated
      USING (
        shop_id IN (
          SELECT id FROM public.shops WHERE seller_id = auth.uid()
        )
      )
      WITH CHECK (
        shop_id IN (
          SELECT id FROM public.shops WHERE seller_id = auth.uid()
        )
      );
  END IF;

  -- Service role bypass (used by Edge Functions to update cutout_url)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'products'
      AND policyname = 'Service role has full products access'
  ) THEN
    CREATE POLICY "Service role has full products access"
      ON public.products
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

-- Enable RLS on products (safe to run even if already enabled)
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- ── 5. Also fix shops table SELECT (needed for products join) ────────────
GRANT SELECT ON public.shops TO anon;
GRANT SELECT ON public.shops TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'shops'
      AND policyname = 'Shops are publicly readable'
  ) THEN
    CREATE POLICY "Shops are publicly readable"
      ON public.shops
      FOR SELECT
      TO anon, authenticated
      USING (true);
  END IF;
END $$;

-- ── 6. Reload PostgREST schema cache ────────────────────────────────────
NOTIFY pgrst, 'reload schema';
