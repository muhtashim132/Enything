-- Add phone number columns to orders table for inter-party communication
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS customer_phone text,
ADD COLUMN IF NOT EXISTS shop_phone text,
ADD COLUMN IF NOT EXISTS rider_phone text;
