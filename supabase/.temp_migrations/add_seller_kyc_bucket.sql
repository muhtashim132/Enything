-- ============================================================================
-- Migration: add_seller_kyc_bucket.sql
-- Description: Creates the storage bucket for Seller KYC documents and adds RLS
-- ============================================================================

-- 1. Create the storage bucket (if it doesn't exist)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('seller_kyc_docs', 'seller_kyc_docs', true) 
ON CONFLICT DO NOTHING;

-- 2. Drop existing policies to prevent conflicts if re-running
DROP POLICY IF EXISTS "Public Access KYC Docs" ON storage.objects;
DROP POLICY IF EXISTS "Auth Insert KYC Docs" ON storage.objects;
DROP POLICY IF EXISTS "Auth Update KYC Docs" ON storage.objects;
DROP POLICY IF EXISTS "Auth Delete KYC Docs" ON storage.objects;

-- 3. Create Row Level Security (RLS) policies for the bucket
-- Allow public read access (so the admin panel can view the images)
CREATE POLICY "Public Access KYC Docs" 
ON storage.objects FOR SELECT 
USING ( bucket_id = 'seller_kyc_docs' );

-- Allow authenticated users (sellers signing up) to upload images
CREATE POLICY "Auth Insert KYC Docs" 
ON storage.objects FOR INSERT 
WITH CHECK ( bucket_id = 'seller_kyc_docs' AND auth.role() = 'authenticated' );

-- Allow authenticated users to update their own images
CREATE POLICY "Auth Update KYC Docs" 
ON storage.objects FOR UPDATE 
WITH CHECK ( bucket_id = 'seller_kyc_docs' AND auth.role() = 'authenticated' );

-- Allow authenticated users to delete their own images
CREATE POLICY "Auth Delete KYC Docs" 
ON storage.objects FOR DELETE 
USING ( bucket_id = 'seller_kyc_docs' AND auth.role() = 'authenticated' );
