-- ============================================================================
-- Create public storage buckets for background removal pipeline
-- ============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES 
  ('raw-product-images', 'raw-product-images', true),
  ('clean-cutouts', 'clean-cutouts', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Ensure public access to read from clean-cutouts
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Public Access Clean Cutouts' AND tablename = 'objects' AND schemaname = 'storage'
    ) THEN
        CREATE POLICY "Public Access Clean Cutouts" ON storage.objects FOR SELECT USING (bucket_id = 'clean-cutouts');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Public Access Raw Images' AND tablename = 'objects' AND schemaname = 'storage'
    ) THEN
        CREATE POLICY "Public Access Raw Images" ON storage.objects FOR SELECT USING (bucket_id = 'raw-product-images');
    END IF;
END $$;
