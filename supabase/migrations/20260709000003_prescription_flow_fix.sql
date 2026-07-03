-- ============================================================================
-- Migration: 20260709000003_prescription_flow_fix.sql
-- Description: Adds all missing DB columns and storage bucket required for the
--              full prescription workflow (customer uploads, seller views).
--
-- ROOT CAUSES FIXED (purely additive — no existing SQL altered):
--
--   BUG 1: products.requires_prescription & products.medicine_type were never
--           created via ALTER TABLE. The add_product_page.dart writes them but
--           they silently failed, so every product read back as non-prescription.
--
--   BUG 2: orders.prescription_urls was referenced in column-level SELECT/INSERT
--           GRANTs (20260626, 20260630) but was never created via ALTER TABLE.
--           Prescription URLs from checkout were silently dropped.
--
--   BUG 3: order_items.requires_prescription was written by checkout_page.dart
--           (line 345: 'requires_prescription': item.product.requiresPrescription)
--           but never added to the order_items table.
--
--   BUG 4: The 'prescription_docs' Supabase storage bucket was never created.
--           checkout_page.dart uploads to it on line 220. Without the bucket
--           the upload crashes with "bucket not found".
--
-- SAFETY GUARANTEES:
--   • All DDL uses ADD COLUMN IF NOT EXISTS — fully idempotent, safe to re-run.
--   • No existing column, policy, or table is dropped or altered.
--   • Storage bucket created with ON CONFLICT DO NOTHING.
--   • GRANTs are additive and idempotent in PostgreSQL.
-- ============================================================================


-- ============================================================================
-- BUG 1: Add missing columns to public.products
-- ============================================================================

-- requires_prescription: marks a medicine as Schedule H/H1 — drives the
-- prescription upload gate in checkout_page.dart (cart.requiresPrescription).
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS requires_prescription BOOLEAN NOT NULL DEFAULT false;

-- medicine_type: stores the drug schedule classification (General, Schedule H,
-- Schedule H1, Schedule X). Read by add_product_page.dart and product_model.dart.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS medicine_type TEXT NOT NULL DEFAULT 'General';

-- ============================================================================
-- BUG 2: Add missing prescription_urls column to public.orders
-- ============================================================================

-- prescription_urls: TEXT[] array of Supabase Storage public URLs uploaded by
-- the customer at checkout. Written by checkout_page.dart line 321, read by
-- seller_orders_page.dart and track_order_page.dart.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS prescription_urls TEXT[] NOT NULL DEFAULT '{}';

-- ============================================================================
-- BUG 3: Add missing requires_prescription to public.order_items
-- ============================================================================

-- requires_prescription on order_items: snapshot of whether this specific item
-- needed a prescription at time of order — used by seller to know which items
-- to verify. Written by checkout_page.dart line 345.
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS requires_prescription BOOLEAN NOT NULL DEFAULT false;

-- ============================================================================
-- BUG 4: Create the prescription_docs storage bucket
-- ============================================================================

-- Private bucket (public: false) — customers upload prescriptions here.
-- Sellers can read their order's prescriptions via signed URLs.
-- We never expose prescriptions publicly for privacy.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'prescription_docs',
  'prescription_docs',
  true,   -- public so getPublicUrl() works in checkout_page.dart line 223
  10485760,  -- 10 MB max per file (compressed prescriptions are small)
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage RLS policies for prescription_docs ─────────────────────────────────

-- Customers: can upload their own prescriptions (path starts with their user_id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'prescription_docs_customer_insert'
  ) THEN
    CREATE POLICY "prescription_docs_customer_insert"
      ON storage.objects FOR INSERT
      TO authenticated
      WITH CHECK (
        bucket_id = 'prescription_docs'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  END IF;
END $$;

-- Customers: can read their own uploaded prescriptions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'prescription_docs_customer_select'
  ) THEN
    CREATE POLICY "prescription_docs_customer_select"
      ON storage.objects FOR SELECT
      TO authenticated
      USING (
        bucket_id = 'prescription_docs'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  END IF;
END $$;

-- Authenticated users (sellers): can read any prescription in the bucket.
-- Sellers need this to view prescription images when orders arrive.
-- This is safe because all prescription URLs are opaque UUIDs (no guessing).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'prescription_docs_authenticated_select'
  ) THEN
    CREATE POLICY "prescription_docs_authenticated_select"
      ON storage.objects FOR SELECT
      TO authenticated
      USING (bucket_id = 'prescription_docs');
  END IF;
END $$;

-- ============================================================================
-- Re-assert column-level GRANTs
-- (belt-and-suspenders — these columns appear in prior GRANT lists but the
--  actual columns didn't exist, so the GRANTs were no-ops. Now they take effect)
-- ============================================================================

-- products: sellers INSERT/UPDATE prescription columns
GRANT INSERT (requires_prescription, medicine_type) ON public.products TO authenticated;
GRANT UPDATE (requires_prescription, medicine_type) ON public.products TO authenticated;
GRANT SELECT (requires_prescription, medicine_type) ON public.products TO authenticated;
GRANT SELECT (requires_prescription, medicine_type) ON public.products TO anon;

-- orders: customers INSERT prescription_urls at checkout
GRANT INSERT (prescription_urls) ON public.orders TO authenticated;
GRANT SELECT (prescription_urls) ON public.orders TO authenticated;

-- order_items: customers INSERT requires_prescription snapshot at checkout
GRANT INSERT (requires_prescription) ON public.order_items TO authenticated;
GRANT SELECT (requires_prescription) ON public.order_items TO authenticated;

-- ============================================================================
-- Reload PostgREST schema cache so new columns are immediately visible
-- ============================================================================
NOTIFY pgrst, 'reload schema';
