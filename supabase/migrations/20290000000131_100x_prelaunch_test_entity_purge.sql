-- =============================================================================
-- Migration 20290000000131: 100x Pre-Launch Test Entity Purge
-- Description:
--   Comprehensive pre-launch purge of all mock test shops, test products,
--   test orders, test reviews, test delivery partners, test admins, and test profiles.
--   Strictly preserves all 13 legitimate production stores, real merchant/customer/rider
--   accounts, and official Apple App Store review credentials.
-- =============================================================================

-- 1. Clean Reviews referencing test shops
DELETE FROM public.reviews
WHERE shop_id NOT IN (
    'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf', -- Mirhart Studio
    'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce', -- Kamrans Restaurant
    '04d8c6b9-b5bb-49ab-9a81-a5116984c798', -- Valley Choice
    'da7c5b00-1c7d-4737-b7f1-59af89556f3d', -- Haji Super Mart
    'a1cb8f85-9c53-4f73-ad6c-aea457aec27d', -- Mubashir Medical Shop
    '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc', -- Musadiq clothes Store
    '026e8cad-9c84-46c1-8b79-588a446b88a3', -- Raashids shop
    '30acf893-72e7-46cc-9ef0-5e01f7d56b46', -- Dubai Laces
    '3f6ea8b4-6843-418a-a769-fb64ade0caca', -- Cravings
    '90447e3f-0e15-4736-9b85-dd1720037822', -- Top In Town
    'd80a840f-9f48-4870-b075-6fbcea27d13c', -- Goodluck Stationers
    'b31cbf6c-16f3-4832-b15b-0ba07bab6091', -- Townmart
    '14016b11-1ccb-48da-bc1e-1105a36a86e6'  -- Apple Demo Store
);

-- 2. Clean Order Items belonging to test shops or test products
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
        '026e8cad-9c84-46c1-8b79-588a446b88a3',
        '30acf893-72e7-46cc-9ef0-5e01f7d56b46',
        '3f6ea8b4-6843-418a-a769-fb64ade0caca',
        '90447e3f-0e15-4736-9b85-dd1720037822',
        'd80a840f-9f48-4870-b075-6fbcea27d13c',
        'b31cbf6c-16f3-4832-b15b-0ba07bab6091',
        '14016b11-1ccb-48da-bc1e-1105a36a86e6'
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
        '026e8cad-9c84-46c1-8b79-588a446b88a3',
        '30acf893-72e7-46cc-9ef0-5e01f7d56b46',
        '3f6ea8b4-6843-418a-a769-fb64ade0caca',
        '90447e3f-0e15-4736-9b85-dd1720037822',
        'd80a840f-9f48-4870-b075-6fbcea27d13c',
        'b31cbf6c-16f3-4832-b15b-0ba07bab6091',
        '14016b11-1ccb-48da-bc1e-1105a36a86e6'
    )
    OR name ILIKE '%test item%'
    OR name ILIKE '%stock test%'
    OR name ILIKE '%refund test%'
    OR name ILIKE '%test burger%'
    OR name IN ('Item S1', 'Item S2')
);

-- 3. Clean Orders belonging to test shops
DELETE FROM public.orders
WHERE shop_id NOT IN (
    'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf',
    'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce',
    '04d8c6b9-b5bb-49ab-9a81-a5116984c798',
    'da7c5b00-1c7d-4737-b7f1-59af89556f3d',
    'a1cb8f85-9c53-4f73-ad6c-aea457aec27d',
    '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc',
    '026e8cad-9c84-46c1-8b79-588a446b88a3',
    '30acf893-72e7-46cc-9ef0-5e01f7d56b46',
    '3f6ea8b4-6843-418a-a769-fb64ade0caca',
    '90447e3f-0e15-4736-9b85-dd1720037822',
    'd80a840f-9f48-4870-b075-6fbcea27d13c',
    'b31cbf6c-16f3-4832-b15b-0ba07bab6091',
    '14016b11-1ccb-48da-bc1e-1105a36a86e6'
);

-- 4. Clean Products belonging to test shops or explicit test items
DELETE FROM public.products
WHERE shop_id NOT IN (
    'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf',
    'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce',
    '04d8c6b9-b5bb-49ab-9a81-a5116984c798',
    'da7c5b00-1c7d-4737-b7f1-59af89556f3d',
    'a1cb8f85-9c53-4f73-ad6c-aea457aec27d',
    '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc',
    '026e8cad-9c84-46c1-8b79-588a446b88a3',
    '30acf893-72e7-46cc-9ef0-5e01f7d56b46',
    '3f6ea8b4-6843-418a-a769-fb64ade0caca',
    '90447e3f-0e15-4736-9b85-dd1720037822',
    'd80a840f-9f48-4870-b075-6fbcea27d13c',
    'b31cbf6c-16f3-4832-b15b-0ba07bab6091',
    '14016b11-1ccb-48da-bc1e-1105a36a86e6'
)
OR name ILIKE '%test item%'
OR name ILIKE '%stock test%'
OR name ILIKE '%refund test%'
OR name ILIKE '%test burger%'
OR name IN ('Item S1', 'Item S2');

-- 5. Clean all test shops outside the whitelist
DELETE FROM public.shops
WHERE id NOT IN (
    'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf',
    'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce',
    '04d8c6b9-b5bb-49ab-9a81-a5116984c798',
    'da7c5b00-1c7d-4737-b7f1-59af89556f3d',
    'a1cb8f85-9c53-4f73-ad6c-aea457aec27d',
    '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc',
    '026e8cad-9c84-46c1-8b79-588a446b88a3',
    '30acf893-72e7-46cc-9ef0-5e01f7d56b46',
    '3f6ea8b4-6843-418a-a769-fb64ade0caca',
    '90447e3f-0e15-4736-9b85-dd1720037822',
    'd80a840f-9f48-4870-b075-6fbcea27d13c',
    'b31cbf6c-16f3-4832-b15b-0ba07bab6091',
    '14016b11-1ccb-48da-bc1e-1105a36a86e6'
);

-- 6. Clean mock delivery partner entries
DELETE FROM public.delivery_partners
WHERE id NOT IN (
    '99da01b7-4f89-445d-b8a5-48a8b59cbcc6', -- Muhtashim Kamran
    '6633cf4a-37e0-46be-892f-26ffd692880a', -- Suhaib
    '821a4442-34da-4032-b31c-bc5a8d0fa06f'  -- Apple Reviewer (Universal)
);

UPDATE public.delivery_partners
SET name = 'Suhaib', phone = '+917006601112'
WHERE id = '6633cf4a-37e0-46be-892f-26ffd692880a';

-- 7. Clean test admin rows
DELETE FROM public.admin_users
WHERE full_name ILIKE 'Test Admin%';

-- 8. Clean test user profiles & auth users
CREATE TEMP TABLE IF NOT EXISTS prelaunch_test_users_to_delete AS
SELECT id FROM public.profiles
WHERE id NOT IN (
    '99da01b7-4f89-445d-b8a5-48a8b59cbcc6', -- Muhtashim Kamran
    '6633cf4a-37e0-46be-892f-26ffd692880a', -- Suhaib
    '821a4442-34da-4032-b31c-bc5a8d0fa06f', -- Apple Reviewer (Universal)
    'be3e2821-5653-4eb3-a419-3eee9c99ad06', -- Razorpay Reviewer
    '4f7ead0c-3f85-40b5-8b01-66f366f2a60e', -- Razorpay Reviewer
    '8ccd0018-184b-4a77-840c-5cff3ea4f5ee', -- Razorpay Reviewer
    'c7da706d-26ea-4c88-8e41-9a6418dfdc29', -- Syed Ufaq (Mirhart Studio)
    '932d50dd-cca9-4238-9ee9-a9c9cc453458', -- Valley Choice
    '1819e2c8-fe6d-4e49-9990-6b51a8f2fea9', -- Haji Super Mart
    '4da8c13b-d473-457f-b286-62e5eb6e42b7', -- Mubashir Medical Shop
    'd40b97d4-1e09-4967-9fe6-f8c425b97171', -- Musadiq clothes Store
    '59d23d78-9ebf-4678-84e6-c2f635bfd2e3', -- Raashids shop
    'bb295f9e-884e-4cab-a80e-ad6a1f2bef5c', -- Dubai Laces
    'e475c673-d192-4d28-a8fa-cca138a7bab0', -- Cravings
    '5930c3ec-361e-4418-a54f-a0235a294643', -- Top In Town
    '17b14421-0e0b-4234-ac0b-25c1069030cd', -- Goodluck Stationers
    'f64d4684-f846-4016-aeb4-e5f68e02ae4f'  -- Townmart
) AND (
    phone LIKE '+919999%'
    OR phone LIKE '+918888%'
    OR phone LIKE '+9198888%'
    OR phone LIKE '997%'
    OR phone LIKE '998%'
    OR phone LIKE '999%'
    OR length(phone) > 13
    OR full_name ILIKE 'Test %'
);

DELETE FROM auth.users WHERE id IN (SELECT id FROM prelaunch_test_users_to_delete);
DROP TABLE IF EXISTS prelaunch_test_users_to_delete;
