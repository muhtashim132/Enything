-- Drop existing policies if any to avoid errors
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Auth Insert" ON storage.objects;
DROP POLICY IF EXISTS "Auth Update" ON storage.objects;
DROP POLICY IF EXISTS "Auth Delete" ON storage.objects;

DROP POLICY IF EXISTS "Public Access Products" ON storage.objects;
DROP POLICY IF EXISTS "Auth Insert Products" ON storage.objects;
DROP POLICY IF EXISTS "Auth Update Products" ON storage.objects;
DROP POLICY IF EXISTS "Auth Delete Products" ON storage.objects;

-- Add storage bucket for shop banners
INSERT INTO storage.buckets (id, name, public) VALUES ('shops', 'shops', true) ON CONFLICT DO NOTHING;
CREATE POLICY "Public Access" ON storage.objects FOR SELECT USING ( bucket_id = 'shops' );
CREATE POLICY "Auth Insert" ON storage.objects FOR INSERT WITH CHECK ( bucket_id = 'shops' AND auth.role() = 'authenticated' );
CREATE POLICY "Auth Update" ON storage.objects FOR UPDATE WITH CHECK ( bucket_id = 'shops' AND auth.role() = 'authenticated' );
CREATE POLICY "Auth Delete" ON storage.objects FOR DELETE USING ( bucket_id = 'shops' AND auth.role() = 'authenticated' );

-- Add storage bucket for products
INSERT INTO storage.buckets (id, name, public) VALUES ('products', 'products', true) ON CONFLICT DO NOTHING;
CREATE POLICY "Public Access Products" ON storage.objects FOR SELECT USING ( bucket_id = 'products' );
CREATE POLICY "Auth Insert Products" ON storage.objects FOR INSERT WITH CHECK ( bucket_id = 'products' AND auth.role() = 'authenticated' );
CREATE POLICY "Auth Update Products" ON storage.objects FOR UPDATE WITH CHECK ( bucket_id = 'products' AND auth.role() = 'authenticated' );
CREATE POLICY "Auth Delete Products" ON storage.objects FOR DELETE USING ( bucket_id = 'products' AND auth.role() = 'authenticated' );
