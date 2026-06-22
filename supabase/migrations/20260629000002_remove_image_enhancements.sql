-- ============================================================================
-- Migration: 20260629000002_remove_image_enhancements.sql
-- Description: Removes image enhancement and background removal triggers/columns
-- ============================================================================

-- Drop the triggers
DROP TRIGGER IF EXISTS trigger_enhance_image ON storage.objects;
DROP TRIGGER IF EXISTS trigger_remove_background ON storage.objects;

-- Drop the edge function wrapper functions
DROP FUNCTION IF EXISTS public.notify_enhance_image();
DROP FUNCTION IF EXISTS public.notify_remove_background();

-- Drop the added columns
ALTER TABLE public.products DROP COLUMN IF EXISTS enhanced_url;
ALTER TABLE public.products DROP COLUMN IF EXISTS cutout_url;

-- Drop RLS policies for enhanced-product-images bucket (clean-cutouts is still fine, but can drop to be safe)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Enhanced images public read' AND tablename = 'objects' AND schemaname = 'storage') THEN
    DROP POLICY "Enhanced images public read" ON storage.objects;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role can write enhanced images' AND tablename = 'objects' AND schemaname = 'storage') THEN
    DROP POLICY "Service role can write enhanced images" ON storage.objects;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role can upsert enhanced images' AND tablename = 'objects' AND schemaname = 'storage') THEN
    DROP POLICY "Service role can upsert enhanced images" ON storage.objects;
  END IF;
END $$;

-- Force PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
