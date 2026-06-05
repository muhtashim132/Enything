-- Fix permission denied for table shops
GRANT SELECT, INSERT, UPDATE, DELETE ON public.shops TO authenticated;
GRANT SELECT ON public.shops TO anon;

-- Ensure public.products is also granted just in case
GRANT SELECT, INSERT, UPDATE, DELETE ON public.products TO authenticated;
GRANT SELECT ON public.products TO anon;

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
