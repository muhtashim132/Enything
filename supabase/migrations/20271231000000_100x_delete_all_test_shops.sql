-- Additive update: Delete all lingering test shops and associated records
-- Ensures "Amit Medical Store" and other magic logic remains completely unaffected
-- as it relies strictly on "Test Shop%" names.

DELETE FROM public.reviews WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE 'Test Shop%');
DELETE FROM public.reviews WHERE order_id IN (SELECT id FROM public.orders WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE 'Test Shop%'));
DELETE FROM public.order_items WHERE product_id IN (SELECT id FROM public.products WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE 'Test Shop%'));
DELETE FROM public.orders WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE 'Test Shop%');
DELETE FROM public.products WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE 'Test Shop%');
DELETE FROM public.shops WHERE name ILIKE 'Test Shop%';
