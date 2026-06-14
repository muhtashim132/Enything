-- Add pincode column to relevant tables
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS pincode TEXT;
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS pincode TEXT;
ALTER TABLE public.delivery_partners ADD COLUMN IF NOT EXISTS pincode TEXT;
