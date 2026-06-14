-- 1. Restore standard table-level SELECT permissions
GRANT SELECT ON public.shops TO authenticated;
GRANT SELECT ON public.shops TO anon;

GRANT SELECT ON public.products TO authenticated;
GRANT SELECT ON public.products TO anon;

-- 2. Make sure Row Level Security allows reading
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public read access to shops" ON public.shops;
DROP POLICY IF EXISTS "Allow public read access to products" ON public.products;

CREATE POLICY "Allow public read access to shops" 
  ON public.shops FOR SELECT USING (true);

CREATE POLICY "Allow public read access to products" 
  ON public.products FOR SELECT USING (true);

-- 3. Reload schema so the API recognizes the new permissions instantly
NOTIFY pgrst, 'reload schema';
