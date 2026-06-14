-- Add missing columns for Settings and Profile

-- Shops (Business Hours)
ALTER TABLE shops
  ADD COLUMN IF NOT EXISTS opening_time text DEFAULT '09:00 AM',
  ADD COLUMN IF NOT EXISTS closing_time text DEFAULT '10:00 PM';

-- Customers (Saved Addresses)
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS default_address text;
