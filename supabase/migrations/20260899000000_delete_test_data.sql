-- Additive update: Delete all test shops, their products, and associated relational records

DELETE FROM public.reviews WHERE order_id IN (SELECT id FROM public.orders WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE '%Test Shop%'));
DELETE FROM public.reviews WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE '%Test Shop%');
DELETE FROM public.order_items WHERE product_id IN (SELECT id FROM public.products WHERE name ILIKE 'item s%' OR name ILIKE '%test product%' OR shop_id IN (SELECT id FROM public.shops WHERE name ILIKE '%Test Shop%'));
DELETE FROM public.orders WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE '%Test Shop%');
DELETE FROM public.products WHERE name ILIKE 'item s%' OR name ILIKE '%test product%' OR shop_id IN (SELECT id FROM public.shops WHERE name ILIKE '%Test Shop%');
DELETE FROM public.shops WHERE name ILIKE '%Test Shop%';
