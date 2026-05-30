-- This script completely fixes any Row Level Security (RLS) blocks 
-- that prevent Customers from seeing Shops and Products.

-- 1. Ensure RLS is enabled but we have policies to allow reads
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing SELECT policies just in case they are conflicting
DROP POLICY IF EXISTS "Allow public read access to shops" ON public.shops;
DROP POLICY IF EXISTS "Allow public read access to products" ON public.products;
DROP POLICY IF EXISTS "Allow authenticated read access to shops" ON public.shops;
DROP POLICY IF EXISTS "Allow authenticated read access to products" ON public.products;

-- 3. Create policies that allow ALL users (authenticated and anonymous) to see shops and products
CREATE POLICY "Allow public read access to shops" 
  ON public.shops FOR SELECT 
  USING (true);

CREATE POLICY "Allow public read access to products" 
  ON public.products FOR SELECT 
  USING (true);

-- 4. Force Supabase API to reload the schema and apply the new rules instantly
NOTIFY pgrst, 'reload schema';
