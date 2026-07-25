-- ============================================================================
-- Migration: 20271125000005_seed_magic_user_profiles.sql
-- Description: ADDITIVE — seeds public-schema data for the 3 magic reviewer
--   accounts that were created by GoTrue Admin API with these UUIDs:
--
--   Rajesh Kumar   (Customer)          a0fc05b6-e3cc-4e0c-adc6-fc7fe8dc70c7
--   Amit Bandana   (Seller)            dac335b8-4833-4ce0-9f16-8858113555af
--   Kishan Nadda   (Delivery Partner)  20e95634-e655-4b68-856f-3c6afa0da41a
--
-- These UUIDs were created by GoTrue via Admin API — they are permanent.
-- Zero impact on any real accounts.
-- ============================================================================

DO $$
DECLARE
  v_customer_id   uuid := 'a0fc05b6-e3cc-4e0c-adc6-fc7fe8dc70c7';
  v_seller_id     uuid := 'dac335b8-4833-4ce0-9f16-8858113555af';
  v_dp_id         uuid := '20e95634-e655-4b68-856f-3c6afa0da41a';
  v_bandipora     geography := ST_SetSRID(ST_MakePoint(74.6366, 34.4225), 4326)::geography;
BEGIN

  -- ── Profiles ──────────────────────────────────────────────────────────────
  -- First delete any orphan profile rows with conflicting phones (from old
  -- deterministic-UUID migrations that left stale data).
  DELETE FROM public.saved_addresses
    WHERE user_id IN (
      SELECT id FROM public.profiles
      WHERE phone IN ('+919999999996', '+919999999997', '+919999999998')
        AND id NOT IN (v_customer_id, v_seller_id, v_dp_id)
    );
  DELETE FROM public.customers
    WHERE id IN (
      SELECT id FROM public.profiles
      WHERE phone IN ('+919999999996', '+919999999997', '+919999999998')
        AND id NOT IN (v_customer_id, v_seller_id, v_dp_id)
    );
  DELETE FROM public.delivery_partners
    WHERE id IN (
      SELECT id FROM public.profiles
      WHERE phone IN ('+919999999996', '+919999999997', '+919999999998')
        AND id NOT IN (v_customer_id, v_seller_id, v_dp_id)
    );
  DELETE FROM public.profiles
    WHERE phone IN ('+919999999996', '+919999999997', '+919999999998')
      AND id NOT IN (v_customer_id, v_seller_id, v_dp_id);

  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES
    (v_customer_id, 'Rajesh Kumar',  'customer',         '+919999999996'),
    (v_seller_id,   'Amit Bandana',  'seller',            '+919999999997'),
    (v_dp_id,       'Kishan Nadda',  'delivery_partner',  '+919999999998')
  ON CONFLICT (id) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        role      = EXCLUDED.role,
        phone     = EXCLUDED.phone;

  -- ── Customer row ──────────────────────────────────────────────────────────
  INSERT INTO public.customers (id, location)
  VALUES (v_customer_id, v_bandipora)
  ON CONFLICT (id) DO UPDATE
    SET location = EXCLUDED.location;

  -- ── Delivery partner row ──────────────────────────────────────────────────
  INSERT INTO public.delivery_partners (id, is_active, verification_status, location)
  VALUES (v_dp_id, true, 'verified', v_bandipora)
  ON CONFLICT (id) DO UPDATE
    SET is_active           = true,
        verification_status = 'verified',
        location            = EXCLUDED.location;

  -- ── Amit Medical Store (seller's shop) ───────────────────────────────────────────
  -- Delete old shop (from old deterministic-UUID seller) and re-insert
  DELETE FROM public.shops WHERE seller_id = v_seller_id;
  -- Also delete any orphan shops from old seller UUID migrations
  DELETE FROM public.shops
    WHERE seller_id IN (
      SELECT id FROM public.profiles
      WHERE phone = '+919999999997'
        AND id <> v_seller_id
    );
  INSERT INTO public.shops (
    seller_id, name, category, categories,
    address, is_active, is_accepting_orders, verification_status,
    location, opening_hours, open_time, close_time
  ) VALUES (
    v_seller_id,
    'Amit Medical Store',
    'Medical Store',
    '["Medical Store"]'::jsonb,
    'Main Market, Bandipora, J&K 193502',
    true, true, 'verified',
    v_bandipora,
    '00:00 - 23:59',
    '00:00:00'::time,
    '23:59:59'::time
  );

  -- ── Saved address for Rajesh Kumar (so he can place orders) ───────────────
  -- Delete first to avoid duplicates
  DELETE FROM public.saved_addresses WHERE user_id = v_customer_id;
  INSERT INTO public.saved_addresses (
    user_id, label, address, landmark, pincode,
    latitude, longitude, is_default
  ) VALUES (
    v_customer_id,
    'Home',
    'Main Market, Bandipora',
    'Near Jamia Masjid',
    '193502',
    34.4225, 74.6366, true
  );

  -- ── Saved address for Kishan Nadda (delivery partner) ────────────────────
  DELETE FROM public.saved_addresses WHERE user_id = v_dp_id;
  INSERT INTO public.saved_addresses (
    user_id, label, address, landmark, pincode,
    latitude, longitude, is_default
  ) VALUES (
    v_dp_id,
    'Home',
    'Main Market, Bandipora',
    'Near Jamia Masjid',
    '193502',
    34.4225, 74.6366, true
  );

  RAISE NOTICE 'Magic reviewer profiles seeded successfully.';
  RAISE NOTICE 'Customer  (Rajesh Kumar)  : %', v_customer_id;
  RAISE NOTICE 'Seller    (Amit Bandana)  : %', v_seller_id;
  RAISE NOTICE 'DelivPart (Kishan Nadda)  : %', v_dp_id;

END $$;

NOTIFY pgrst, 'reload schema';
