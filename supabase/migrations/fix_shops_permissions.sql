-- Fix for: permission denied for table shops
-- When we granted column-level privileges and revoked table-level privileges, 
-- it broke the `select()` (which translates to `select *`) queries in the Flutter app.
-- PostgREST requires table-level SELECT permission to perform a `select *` when 
-- some columns are excluded from column-level grants.

-- Restore full table-level SELECT access so that `.select()` works.
GRANT SELECT ON public.shops TO authenticated;
GRANT SELECT ON public.shops TO anon;

GRANT SELECT ON public.delivery_partners TO authenticated;
GRANT SELECT ON public.delivery_partners TO anon;

-- Note: Sensitive data protection should rely on RLS policies or returning specific columns 
-- from the client (e.g. `.select('id, name, location, etc')`) if column-level grants are too strict for `select *`.
