BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"1ad97706-0830-48c0-a001-785a5bc6a076", "role":"authenticated"}', true);
SELECT set_config('role', 'authenticated', true);
SELECT o.id, (SELECT json_agg(oi.*) FROM public.order_items oi WHERE oi.order_id = o.id) as order_items FROM public.orders o JOIN public.shops s ON o.shop_id = s.id WHERE delivery_partner_id IS NULL AND status IN ('awaiting_acceptance', 'pending', 'confirmed');
COMMIT;
