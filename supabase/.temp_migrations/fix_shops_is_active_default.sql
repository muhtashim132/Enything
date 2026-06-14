-- Fix: All existing shops were created with is_active = false due to a missing
-- default in the insert call. Activate all shops so they appear to customers.
-- Sellers can still manually close their shop via Shop Management toggle.

UPDATE public.shops
  SET is_active = true
  WHERE is_active = false OR is_active IS NULL;

-- Also fix the DB default so future inserts without explicit is_active get true
ALTER TABLE public.shops
  ALTER COLUMN is_active SET DEFAULT true;

NOTIFY pgrst, 'reload schema';
