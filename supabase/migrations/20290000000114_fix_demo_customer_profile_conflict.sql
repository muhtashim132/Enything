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
DO $$
DECLARE
  v_demo_user_id uuid;
BEGIN
  -- Look up the active Customer demo account by email or phone
  SELECT id INTO v_demo_user_id 
  FROM auth.users 
  WHERE email = '919999999991@auth.enything.app' OR phone = '+919999999991'
  ORDER BY created_at DESC 
  LIMIT 1;

  IF v_demo_user_id IS NOT NULL THEN
    -- Profiles record
    INSERT INTO public.profiles (id, full_name, role, phone)
    VALUES (
      v_demo_user_id,
      'Apple Reviewer (Customer)',
      'customer',
      '+919876500001'
    )
    ON CONFLICT (id) DO UPDATE SET
      full_name = EXCLUDED.full_name,
      role = EXCLUDED.role,
      phone = EXCLUDED.phone;

    -- Customers record
    INSERT INTO public.customers (id, name, phone, default_address, address_home)
    VALUES (
      v_demo_user_id,
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

    -- Pre-configured saved address in Bandipora
    DELETE FROM public.saved_addresses WHERE user_id = v_demo_user_id;
    INSERT INTO public.saved_addresses (
      user_id, label, address, flat_number, landmark, pincode, latitude, longitude, is_default
    ) VALUES (
      v_demo_user_id,
      'Home',
      'Plan Bandipora, Ward No. 2, Bandipora, Jammu & Kashmir — 193502',
      'Ward No. 2',
      'Near Jamia Masjid',
      '193502',
      34.4225,
      74.6366,
      true
    );
  END IF;
END $$;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
