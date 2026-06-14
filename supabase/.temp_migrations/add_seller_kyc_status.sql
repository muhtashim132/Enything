-- Add verification status and JSONB for document uploads
ALTER TABLE shops
  ADD COLUMN IF NOT EXISTS verification_status TEXT DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS kyc_documents JSONB DEFAULT '{}'::jsonb;
