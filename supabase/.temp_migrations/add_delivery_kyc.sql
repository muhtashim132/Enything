-- ============================================================================
-- Migration: add_delivery_kyc.sql
-- Description: Adds KYC status and documents to delivery_partners, plus storage bucket
-- ============================================================================

-- 1. Add columns to delivery_partners
ALTER TABLE public.delivery_partners 
ADD COLUMN IF NOT EXISTS verification_status TEXT DEFAULT 'pending',
ADD COLUMN IF NOT EXISTS kyc_documents JSONB DEFAULT '{}'::jsonb;

-- 2. Create the storage bucket (if it doesn't exist)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('delivery_kyc_docs', 'delivery_kyc_docs', true) 
ON CONFLICT DO NOTHING;

-- 3. Drop existing policies to prevent conflicts if re-running
DROP POLICY IF EXISTS "Public Access Delivery KYC Docs" ON storage.objects;
DROP POLICY IF EXISTS "Auth Insert Delivery KYC Docs" ON storage.objects;
DROP POLICY IF EXISTS "Auth Update Delivery KYC Docs" ON storage.objects;
DROP POLICY IF EXISTS "Auth Delete Delivery KYC Docs" ON storage.objects;

-- 4. Create Row Level Security (RLS) policies for the bucket
-- Allow public read access (so the admin panel can view the images)
CREATE POLICY "Public Access Delivery KYC Docs" 
ON storage.objects FOR SELECT 
USING ( bucket_id = 'delivery_kyc_docs' );

-- Allow authenticated users to upload images
CREATE POLICY "Auth Insert Delivery KYC Docs" 
ON storage.objects FOR INSERT 
WITH CHECK ( bucket_id = 'delivery_kyc_docs' AND auth.role() = 'authenticated' );

-- Allow authenticated users to update their own images
CREATE POLICY "Auth Update Delivery KYC Docs" 
ON storage.objects FOR UPDATE 
WITH CHECK ( bucket_id = 'delivery_kyc_docs' AND auth.role() = 'authenticated' );

-- Allow authenticated users to delete their own images
CREATE POLICY "Auth Delete Delivery KYC Docs" 
ON storage.objects FOR DELETE 
USING ( bucket_id = 'delivery_kyc_docs' AND auth.role() = 'authenticated' );
