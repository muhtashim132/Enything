-- ============================================================================
-- Migration: 20260625000001_image_enhancement_pipeline.sql
-- Description: 10x Image Enhancement Pipeline
--
-- Adds:
--   1. enhanced_url TEXT column on products (stores auto-enhanced image URL)
--   2. enhanced-product-images storage bucket (public)
--   3. Storage RLS policies for the new bucket
--   4. notify_enhance_image() trigger function → enhance-image edge function
--   5. trigger_enhance_image ON storage.objects INSERT
--
-- SAFETY: Uses ADD COLUMN IF NOT EXISTS + ON CONFLICT DO NOTHING.
--         Zero changes to any existing columns, triggers, or policies.
-- ============================================================================

-- ── 1. Add enhanced_url column ─────────────────────────────────────────────
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS enhanced_url TEXT;

-- Grants for the new column
GRANT SELECT (enhanced_url) ON public.products TO authenticated;
GRANT SELECT (enhanced_url) ON public.products TO anon;
GRANT UPDATE (enhanced_url) ON public.products TO service_role;

-- ── 2. Create enhanced-product-images storage bucket ───────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('enhanced-product-images', 'enhanced-product-images', true)
ON CONFLICT (id) DO NOTHING;

-- ── 3. Storage RLS policies ────────────────────────────────────────────────
-- Public read (customers can view enhanced images)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Enhanced images public read'
  ) THEN
    CREATE POLICY "Enhanced images public read"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'enhanced-product-images');
  END IF;
END $$;

-- Service role write (edge function uploads here)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Service role can write enhanced images'
  ) THEN
    CREATE POLICY "Service role can write enhanced images"
      ON storage.objects FOR INSERT TO service_role
      WITH CHECK (bucket_id = 'enhanced-product-images');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Service role can upsert enhanced images'
  ) THEN
    CREATE POLICY "Service role can upsert enhanced images"
      ON storage.objects FOR UPDATE TO service_role
      USING (bucket_id = 'enhanced-product-images');
  END IF;
END $$;

-- ── 4. Drop old function/trigger if they exist (clean re-run safety) ───────
DROP TRIGGER IF EXISTS trigger_enhance_image ON storage.objects;
DROP FUNCTION IF EXISTS public.notify_enhance_image();

-- ── 5. Create PL/pgSQL wrapper that calls the enhance-image edge function ──
CREATE OR REPLACE FUNCTION public.notify_enhance_image()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- Same service role key used by notify_remove_background
  v_service_role_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1tZHJnY3VhZXR3b2hmbGN2em91Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Nzk5NzUxMCwiZXhwIjoyMDkzNTczNTEwfQ.rzX0mupREQDLgTgZLISBocfdtWH-IPVE0bsz7oc_Z8c';
  v_payload JSONB;
BEGIN
  v_payload := jsonb_build_object(
    'name',      NEW.name,
    'bucket_id', NEW.bucket_id
  );

  PERFORM net.http_post(
    url     := 'https://mmdrgcuaetwohflcvzou.supabase.co/functions/v1/enhance-image',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_role_key
    ),
    body    := v_payload::TEXT
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never fail the storage insert due to HTTP errors — just log
  RAISE WARNING 'notify_enhance_image: failed to call edge function: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- ── 6. Bind trigger — fires only for raw-product-images bucket ──────────────
CREATE TRIGGER trigger_enhance_image
  AFTER INSERT ON storage.objects
  FOR EACH ROW
  WHEN (NEW.bucket_id = 'raw-product-images')
  EXECUTE FUNCTION public.notify_enhance_image();

-- ── 7. Ensure service_role can SELECT storage.objects (for context) ─────────
GRANT SELECT ON TABLE storage.objects TO service_role;

-- Force PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
