-- ============================================================================
-- Migration: add_pharmacy_rules.sql
-- Description: Adds schema support for Indian E-Pharmacy Govt Norms
-- ============================================================================

-- 1. Update Products Table for Medicine Rules
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS requires_prescription BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS medicine_type TEXT DEFAULT 'General'; 
  -- Allowed types: 'General', 'OTC', 'Schedule H', 'Schedule H1'
  -- Note: 'Schedule X' and 'NDPS' will be blocked at the app logic level.

-- 2. Update Orders Table for Prescription Uploads
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS prescription_urls JSONB DEFAULT '[]'::jsonb;

-- 3. The 'status' column in orders is TEXT, so we don't need to alter an ENUM,
-- but we will introduce the 'pending_verification' status in the app logic.

-- 4. Create Storage Bucket for Prescriptions
INSERT INTO storage.buckets (id, name, public) 
VALUES ('prescription_docs', 'prescription_docs', true) 
ON CONFLICT DO NOTHING;

-- 5. RLS for prescription bucket
DROP POLICY IF EXISTS "Public Access Prescriptions" ON storage.objects;
DROP POLICY IF EXISTS "Auth Insert Prescriptions" ON storage.objects;
DROP POLICY IF EXISTS "Auth Update Prescriptions" ON storage.objects;
DROP POLICY IF EXISTS "Auth Delete Prescriptions" ON storage.objects;

-- Admins and Sellers might need to view them, so public read is easiest for now
CREATE POLICY "Public Access Prescriptions" 
ON storage.objects FOR SELECT 
USING ( bucket_id = 'prescription_docs' );

-- Customers upload prescriptions
CREATE POLICY "Auth Insert Prescriptions" 
ON storage.objects FOR INSERT 
WITH CHECK ( bucket_id = 'prescription_docs' AND auth.role() = 'authenticated' );

-- Customers can update/delete their own before verification
CREATE POLICY "Auth Update Prescriptions" 
ON storage.objects FOR UPDATE 
WITH CHECK ( bucket_id = 'prescription_docs' AND auth.role() = 'authenticated' );

CREATE POLICY "Auth Delete Prescriptions" 
ON storage.objects FOR DELETE 
USING ( bucket_id = 'prescription_docs' AND auth.role() = 'authenticated' );
