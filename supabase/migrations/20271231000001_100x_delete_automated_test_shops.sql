-- Additive update: Delete all automated test shops and associated records
-- Specifically targeting dummy shops with the prefix "Shop +918888887" created during edge cases testing.
-- Ensures "Amit Medical Store" and other real/magic logic remains completely unaffected.

DELETE FROM public.reviews WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE 'Shop +918888887%');
DELETE FROM public.reviews WHERE order_id IN (SELECT id FROM public.orders WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE 'Shop +918888887%'));
DELETE FROM public.order_items WHERE product_id IN (SELECT id FROM public.products WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE 'Shop +918888887%'));
DELETE FROM public.orders WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE 'Shop +918888887%');
DELETE FROM public.products WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE 'Shop +918888887%');
DELETE FROM public.shops WHERE name ILIKE 'Shop +918888887%';
