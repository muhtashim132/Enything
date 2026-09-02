-- 20290000000102_verify_all_legitimate_shops_and_riders.sql
-- Set verification_status = 'verified' and is_active = true for legitimate shops and owner rider profile

-- 1. Verify and activate all legitimate shops
UPDATE public.shops
   SET verification_status = 'verified',
       is_verified = true,
       is_approved = true,
       is_active = true,
       is_open = true,
       is_accepting_orders = true,
       updated_at = now()
 WHERE verification_status IS NULL 
    OR verification_status != 'verified';

-- 2. Ensure seller_kyc row exists for Kamrans Restaurant / Muhtashim Kamran Nazki
INSERT INTO public.seller_kyc (
    id,
    user_id,
    shop_id,
    status,
    business_name,
    created_at,
    updated_at
)
SELECT 
    gen_random_uuid(),
    '99da01b7-4f89-445d-b8a5-48a8b59cbcc6',
    'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce',
    'approved',
    'Kamrans Restaurant',
    now(),
    now()
WHERE NOT EXISTS (
    SELECT 1 FROM public.seller_kyc 
    WHERE user_id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6'
);

-- 3. Verify and activate owner delivery partner account
UPDATE public.delivery_partners
   SET verification_status = 'verified',
       is_verified = true,
       is_active = true,
       is_available = true,
       is_accepting_orders = true,
       status = 'approved',
       name = COALESCE(name, 'Muhtashim KAMRAN'),
       phone = COALESCE(phone, '+917006464241'),
       updated_at = now()
 WHERE id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6';

-- 4. Ensure delivery_partner_kyc row exists and is approved for Muhtashim Kamran Nazki
INSERT INTO public.delivery_partner_kyc (
    id,
    user_id,
    status,
    vehicle_type,
    created_at,
    updated_at
)
SELECT 
    gen_random_uuid(),
    '99da01b7-4f89-445d-b8a5-48a8b59cbcc6',
    'approved',
    'bike',
    now(),
    now()
WHERE NOT EXISTS (
    SELECT 1 FROM public.delivery_partner_kyc 
    WHERE user_id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6'
);
