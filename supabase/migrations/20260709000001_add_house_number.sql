-- Migration to add 'house_number' column to customers, shops, and delivery_partners tables.
-- This ensures that the profile setup process can save the house number without PGRST204 errors.

-- 1. Add column to customers
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS house_number text;

-- 2. Add column to shops
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS house_number text;

-- 3. Add column to delivery_partners
ALTER TABLE public.delivery_partners ADD COLUMN IF NOT EXISTS house_number text;

-- 4. Re-grant privileges to ensure no 'Grant SELECT error' happens
-- Granting usage on schema
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Granting select, insert, update, delete on these tables
GRANT SELECT, INSERT, UPDATE, DELETE ON public.customers TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.shops TO anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.delivery_partners TO anon, authenticated, service_role;

-- Notify postgrest to reload the schema cache so the new columns are immediately available
NOTIFY pgrst, 'reload schema';
