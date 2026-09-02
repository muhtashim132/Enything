-- 20290000000101_reconcile_phone_auth_and_multirole_accounts.sql
-- Fix split auth identity for Muhtashim Kamran Nazki (+917006464241)

-- 1. Transfer any newly saved addresses from orphan user to master multirole account
UPDATE public.saved_addresses
   SET user_id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6'
 WHERE user_id = 'b34d1b55-2885-4db4-aa03-6493203d9fbf';

-- 2. Remove orphan placeholder in customers
DELETE FROM public.customers
 WHERE id = 'b34d1b55-2885-4db4-aa03-6493203d9fbf';

-- 3. Delete orphan auth identities & auth user
DELETE FROM auth.identities
 WHERE user_id = 'b34d1b55-2885-4db4-aa03-6493203d9fbf';

DELETE FROM auth.users
 WHERE id = 'b34d1b55-2885-4db4-aa03-6493203d9fbf';

-- 4. Update master account in auth.users with verified phone
UPDATE auth.users
   SET phone = '917006464241',
       phone_confirmed_at = COALESCE(phone_confirmed_at, now()),
       raw_app_meta_data = jsonb_build_object(
           'provider', 'phone',
           'providers', ARRAY['phone', 'email']
       ),
       updated_at = now()
 WHERE id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6';

-- 5. Ensure phone provider identity exists for master account in auth.identities
DELETE FROM auth.identities
 WHERE provider = 'phone' AND provider_id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6';

INSERT INTO auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
)
VALUES (
    gen_random_uuid(),
    '99da01b7-4f89-445d-b8a5-48a8b59cbcc6',
    jsonb_build_object(
        'sub', '99da01b7-4f89-445d-b8a5-48a8b59cbcc6',
        'phone', '+917006464241',
        'phone_verified', true
    ),
    'phone',
    '99da01b7-4f89-445d-b8a5-48a8b59cbcc6',
    now(),
    now(),
    now()
);

-- 6. Ensure master profile has active_roles synchronized
UPDATE public.profiles
   SET phone = '+917006464241'
 WHERE id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6';
