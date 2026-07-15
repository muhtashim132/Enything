-- Additive migration for missing KYC fields needed by ShopModel and Seller Registration.
-- Avoids PGRST116 / 204 exceptions during signup.

ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS fssai_number TEXT;
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS prep_time_minutes INT DEFAULT 30;
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS is_veg_only BOOLEAN DEFAULT false;
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;
