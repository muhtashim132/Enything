-- Add landmark and addresses columns
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS address_home JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS address_work JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS landmark TEXT;

ALTER TABLE shops
  ADD COLUMN IF NOT EXISTS landmark TEXT;

ALTER TABLE delivery_partners
  ADD COLUMN IF NOT EXISTS landmark TEXT;
