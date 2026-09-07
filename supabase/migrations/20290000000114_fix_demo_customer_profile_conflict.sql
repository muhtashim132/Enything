-- =============================================================================
-- Phase 114: Fix Demo Customer Profile Conflict & Enable Instant Login
-- =============================================================================

-- 1. Remove dead mock user records that conflict with real auth phone numbers
DELETE FROM public.saved_addresses WHERE user_id::text LIKE '00000000-0000-0000-0000-91999999999%';
DELETE FROM public.customers WHERE id::text LIKE '00000000-0000-0000-0000-91999999999%';
DELETE FROM public.delivery_partners WHERE id::text LIKE '00000000-0000-0000-0000-91999999999%';
DELETE FROM public.shops WHERE seller_id::text LIKE '00000000-0000-0000-0000-91999999999%';
DELETE FROM public.profiles WHERE id::text LIKE '00000000-0000-0000-0000-91999999999%';
DELETE FROM auth.users WHERE id::text LIKE '00000000-0000-0000-0000-91999999999%';

-- 2. Pre-provision the active Customer demo account (919999999991@auth.enything.app)
INSERT INTO public.profiles (id, full_name, role, phone)
VALUES (
  'a0b41f87-157c-4a43-ad10-71aa59f83219',
  'Apple Reviewer (Customer)',
  'customer',
  '+919876500001'
)
ON CONFLICT (id) DO UPDATE SET
  full_name = EXCLUDED.full_name,
  role = EXCLUDED.role,
  phone = EXCLUDED.phone;

-- 3. Customer record
INSERT INTO public.customers (id, name, phone, default_address, address_home)
VALUES (
  'a0b41f87-157c-4a43-ad10-71aa59f83219',
  'Apple Reviewer (Customer)',
  '+919876500001',
  'Plan Bandipora, Ward No. 2, Bandipora, Jammu & Kashmir — 193502',
  '{"house": "Ward No. 2", "landmark": "Near Jamia Masjid", "area": "Plan Bandipora"}'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  phone = EXCLUDED.phone,
  default_address = EXCLUDED.default_address,
  address_home = EXCLUDED.address_home;

-- 4. Pre-configured saved address in Bandipora
DELETE FROM public.saved_addresses WHERE user_id = 'a0b41f87-157c-4a43-ad10-71aa59f83219';
INSERT INTO public.saved_addresses (
  user_id, label, address, flat_number, landmark, pincode, latitude, longitude, is_default
) VALUES (
  'a0b41f87-157c-4a43-ad10-71aa59f83219',
  'Home',
  'Plan Bandipora, Ward No. 2, Bandipora, Jammu & Kashmir — 193502',
  'Ward No. 2',
  'Near Jamia Masjid',
  '193502',
  34.4225,
  74.6366,
  true
);

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
