-- 2029000000100_purge_all_test_shops_and_test_products.sql
-- Comprehensive cleanup of mock/test shops, mock items, test orders, and test seller accounts.

-- 1. Delete reviews referencing test shops
DELETE FROM public.reviews
WHERE shop_id NOT IN (
    'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf', -- Mirhart Studio
    'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce', -- Kamrans Restaurant
    '04d8c6b9-b5bb-49ab-9a81-a5116984c798', -- Valley Choice
    'da7c5b00-1c7d-4737-b7f1-59af89556f3d', -- Haji Super Mart
    'a1cb8f85-9c53-4f73-ad6c-aea457aec27d', -- Mubashir Medical Shop
    '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc', -- Musadiq clothes Store
    '026e8cad-9c84-46c1-8b79-588a446b88a3'  -- Raashids shop
);

-- 2. Delete order items
DELETE FROM public.order_items
WHERE order_id IN (
    SELECT id FROM public.orders 
    WHERE shop_id NOT IN (
        'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf',
        'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce',
        '04d8c6b9-b5bb-49ab-9a81-a5116984c798',
        'da7c5b00-1c7d-4737-b7f1-59af89556f3d',
        'a1cb8f85-9c53-4f73-ad6c-aea457aec27d',
        '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc',
        '026e8cad-9c84-46c1-8b79-588a446b88a3'
    )
)
OR product_id IN (
    SELECT id FROM public.products
    WHERE shop_id NOT IN (
        'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf',
        'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce',
        '04d8c6b9-b5bb-49ab-9a81-a5116984c798',
        'da7c5b00-1c7d-4737-b7f1-59af89556f3d',
        'a1cb8f85-9c53-4f73-ad6c-aea457aec27d',
        '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc',
        '026e8cad-9c84-46c1-8b79-588a446b88a3'
    )
    OR name ILIKE 'Test Item%'
    OR name ILIKE 'Stock Test%'
    OR name ILIKE 'Refund Test Item%'
    OR name IN ('Item S1', 'Item S2')
);

-- 3. Delete orders belonging to test shops
DELETE FROM public.orders
WHERE shop_id NOT IN (
    'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf',
    'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce',
    '04d8c6b9-b5bb-49ab-9a81-a5116984c798',
    'da7c5b00-1c7d-4737-b7f1-59af89556f3d',
    'a1cb8f85-9c53-4f73-ad6c-aea457aec27d',
    '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc',
    '026e8cad-9c84-46c1-8b79-588a446b88a3'
);

-- 4. Delete all products belonging to test shops or explicit test items
DELETE FROM public.products
WHERE shop_id NOT IN (
    'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf',
    'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce',
    '04d8c6b9-b5bb-49ab-9a81-a5116984c798',
    'da7c5b00-1c7d-4737-b7f1-59af89556f3d',
    'a1cb8f85-9c53-4f73-ad6c-aea457aec27d',
    '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc',
    '026e8cad-9c84-46c1-8b79-588a446b88a3'
)
OR name ILIKE 'Test Item%'
OR name ILIKE 'Stock Test%'
OR name ILIKE 'Refund Test Item%'
OR name IN ('Item S1', 'Item S2');

-- 5. Delete all test shops outside the whitelist
DELETE FROM public.shops
WHERE id NOT IN (
    'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf',
    'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce',
    '04d8c6b9-b5bb-49ab-9a81-a5116984c798',
    'da7c5b00-1c7d-4737-b7f1-59af89556f3d',
    'a1cb8f85-9c53-4f73-ad6c-aea457aec27d',
    '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc',
    '026e8cad-9c84-46c1-8b79-588a446b88a3'
);
