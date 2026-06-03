-- Migration: Add address column to orders
-- It looks like the 'address' column was missing from the orders table

ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS address TEXT;

-- Reload schema cache to ensure PostgREST sees the new column immediately
NOTIFY pgrst, 'reload schema';
