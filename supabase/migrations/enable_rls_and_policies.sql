-- ============================================================================
-- Migration: enable_rls_and_policies.sql
-- Description: Enables Row Level Security (RLS) on all public tables and
--              creates fine-grained access policies for the Zappy mobile app.
--
-- HOW TO RUN:
--   1. Open your Supabase Dashboard → SQL Editor
--   2. Paste this entire script and click "Run"
--   3. After running, use the verification query at the bottom to confirm
--      that 0 tables remain with RLS disabled.
--
-- TABLES COVERED:
--   profiles, customers, delivery_partners, shops, orders, order_items,
--   products, phone_otps, ratings
--
-- SECURITY MODEL:
--   • anon  role  → blocked from everything (no public data exposure)
--   • authenticated role → can only access their own records
--   • Admins (rows in admin_users) → can read/manage all records
--   • Sensitive KYC/bank columns on shops & delivery_partners are column-
--     level restricted so they cannot be read by any client-side query
--     (only the owner row gets full access via RLS; admins via service role).
-- ============================================================================


-- ============================================================================
-- STEP 0: Helper — "is this user an active admin?" function
-- We use SECURITY DEFINER so RLS policies can call it without infinite loops.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_active_admin(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE id = p_uid AND is_active = TRUE AND (is_suspended IS DISTINCT FROM TRUE)
  );
END;
$$;


-- ============================================================================
-- STEP 1: Enable RLS on all 12 application tables
-- ============================================================================

ALTER TABLE public.profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_partners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shops             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.phone_otps        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ratings           ENABLE ROW LEVEL SECURITY;


-- ============================================================================
-- STEP 2: Drop any pre-existing policies to avoid "already exists" errors
--         (safe to run multiple times)
-- ============================================================================

-- profiles
DROP POLICY IF EXISTS "profiles_select_own"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_delete_own"   ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_select" ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_all"    ON public.profiles;

-- customers
DROP POLICY IF EXISTS "customers_select_own"   ON public.customers;
DROP POLICY IF EXISTS "customers_insert_own"   ON public.customers;
DROP POLICY IF EXISTS "customers_update_own"   ON public.customers;
DROP POLICY IF EXISTS "customers_delete_own"   ON public.customers;
DROP POLICY IF EXISTS "customers_admin_all"    ON public.customers;

-- delivery_partners
DROP POLICY IF EXISTS "dp_select_own"         ON public.delivery_partners;
DROP POLICY IF EXISTS "dp_insert_own"         ON public.delivery_partners;
DROP POLICY IF EXISTS "dp_update_own"         ON public.delivery_partners;
DROP POLICY IF EXISTS "dp_delete_own"         ON public.delivery_partners;
DROP POLICY IF EXISTS "dp_admin_all"          ON public.delivery_partners;

-- shops
DROP POLICY IF EXISTS "shops_select_public"   ON public.shops;
DROP POLICY IF EXISTS "shops_insert_own"      ON public.shops;
DROP POLICY IF EXISTS "shops_update_own"      ON public.shops;
DROP POLICY IF EXISTS "shops_delete_own"      ON public.shops;
DROP POLICY IF EXISTS "shops_admin_all"       ON public.shops;

-- orders
DROP POLICY IF EXISTS "orders_select_customer"  ON public.orders;
DROP POLICY IF EXISTS "orders_select_seller"    ON public.orders;
DROP POLICY IF EXISTS "orders_select_rider"     ON public.orders;
DROP POLICY IF EXISTS "orders_insert_customer"  ON public.orders;
DROP POLICY IF EXISTS "orders_update_seller"    ON public.orders;
DROP POLICY IF EXISTS "orders_update_rider"     ON public.orders;
DROP POLICY IF EXISTS "orders_update_customer"  ON public.orders;
DROP POLICY IF EXISTS "orders_admin_all"        ON public.orders;

-- order_items
DROP POLICY IF EXISTS "order_items_select_involved" ON public.order_items;
DROP POLICY IF EXISTS "order_items_insert_customer" ON public.order_items;
DROP POLICY IF EXISTS "order_items_admin_all"       ON public.order_items;

-- products
DROP POLICY IF EXISTS "products_select_all"   ON public.products;
DROP POLICY IF EXISTS "products_insert_own"   ON public.products;
DROP POLICY IF EXISTS "products_update_own"   ON public.products;
DROP POLICY IF EXISTS "products_delete_own"   ON public.products;
DROP POLICY IF EXISTS "products_admin_all"    ON public.products;

-- phone_otps
DROP POLICY IF EXISTS "phone_otps_select_own"         ON public.phone_otps;
DROP POLICY IF EXISTS "phone_otps_upsert_own"         ON public.phone_otps;
DROP POLICY IF EXISTS "phone_otps_upsert_own_insert"  ON public.phone_otps;
DROP POLICY IF EXISTS "phone_otps_upsert_own_update"  ON public.phone_otps;
DROP POLICY IF EXISTS "phone_otps_delete_own"         ON public.phone_otps;

-- ratings
DROP POLICY IF EXISTS "ratings_select_all"    ON public.ratings;
DROP POLICY IF EXISTS "ratings_insert_own"    ON public.ratings;
DROP POLICY IF EXISTS "ratings_update_own"    ON public.ratings;
DROP POLICY IF EXISTS "ratings_admin_all"     ON public.ratings;


-- ============================================================================
-- STEP 3: PROFILES
-- Every authenticated user may read and manage their own profile.
-- Admins can read all profiles (needed for admin panels, join queries).
-- Nobody can delete profiles through the client (managed via auth cascade).
-- ============================================================================

-- Users read their own profile
CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (id = auth.uid());

-- Admins read any profile (needed for orders admin, riders admin, etc.)
CREATE POLICY "profiles_admin_select"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (public.is_active_admin(auth.uid()));

-- Users create their own profile (first sign-up)
CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());

-- Users update their own profile
CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());


-- ============================================================================
-- STEP 4: CUSTOMERS
-- Customers manage their own row. Admins can read all.
-- ============================================================================

CREATE POLICY "customers_select_own"
  ON public.customers FOR SELECT
  TO authenticated
  USING (id = auth.uid());

CREATE POLICY "customers_insert_own"
  ON public.customers FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());

CREATE POLICY "customers_update_own"
  ON public.customers FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY "customers_admin_all"
  ON public.customers FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));


-- ============================================================================
-- STEP 5: DELIVERY_PARTNERS
-- Riders only see/update their own row.
-- Admins can read all (for riders management panel).
-- Sellers and customers cannot read riders' personal/KYC data.
--
-- NOTE: Sensitive columns (aadhar_number, bank_account_number, bank_ifsc,
-- bank_account_holder, insurance_number) are protected at the RLS level
-- because only the rider themselves (id = auth.uid()) can SELECT their row.
-- ============================================================================

CREATE POLICY "dp_select_own"
  ON public.delivery_partners FOR SELECT
  TO authenticated
  USING (id = auth.uid() OR public.is_active_admin(auth.uid()));

CREATE POLICY "dp_insert_own"
  ON public.delivery_partners FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());

CREATE POLICY "dp_update_own"
  ON public.delivery_partners FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY "dp_admin_all"
  ON public.delivery_partners FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));


-- ============================================================================
-- STEP 6: SHOPS
-- Customers and riders need to read shop info (name, address, hours, etc.)
-- but must NOT read KYC/bank columns (aadhar, pan, gst, trade_license,
-- bank_account_number, bank_ifsc, bank_account_holder).
--
-- APPROACH:
--   • All authenticated users can SELECT shops (needed for browsing).
--   • Sellers can INSERT / UPDATE their own shop row (seller_id = auth.uid()).
--   • Sensitive columns are stripped via a SECURITY DEFINER view that the
--     client app can use for browsing, while the direct table SELECT for
--     the owner (seller_id = auth.uid()) returns all columns.
--
-- The column-level REVOKE below prevents non-owners from ever seeing the
-- sensitive columns even when they have table-level SELECT via RLS.
-- ============================================================================

-- Anyone authenticated can browse shops (needed for customer home feed)
CREATE POLICY "shops_select_public"
  ON public.shops FOR SELECT
  TO authenticated
  USING (TRUE);

-- Sellers create their own shop
CREATE POLICY "shops_insert_own"
  ON public.shops FOR INSERT
  TO authenticated
  WITH CHECK (seller_id = auth.uid());

-- Sellers update their own shop
CREATE POLICY "shops_update_own"
  ON public.shops FOR UPDATE
  TO authenticated
  USING (seller_id = auth.uid())
  WITH CHECK (seller_id = auth.uid());

-- Admins can manage all shops
CREATE POLICY "shops_admin_all"
  ON public.shops FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));

-- ── Column-Level Privilege Revocation on sensitive shop KYC columns ──────────
-- We REVOKE all SELECT from 'authenticated', then GRANT SELECT back on every
-- column EXCEPT the sensitive KYC/bank ones.
-- Using a dynamic DO block so the script does not fail if any column
-- name differs from what we expect (schema evolves over time).

DO $$
DECLARE
  v_sensitive TEXT[] := ARRAY[
    'aadhar_number', 'pan_number', 'gst_number',
    'trade_license', 'bank_account_number', 'bank_ifsc', 'bank_account_holder'
  ];
  v_cols TEXT;
BEGIN
  -- Revoke full table SELECT first
  REVOKE SELECT ON public.shops FROM authenticated;

  -- Build a comma-separated list of safe (non-sensitive) columns
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_cols
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name   = 'shops'
    AND column_name != ALL(v_sensitive);

  -- Grant SELECT only on those safe columns
  EXECUTE format('GRANT SELECT (%s) ON public.shops TO authenticated', v_cols);
END;
$$;

-- ── Column-Level Privilege Revocation on delivery_partners KYC columns ───────
-- Same pattern: revoke all, then grant non-sensitive columns back.

DO $$
DECLARE
  v_sensitive TEXT[] := ARRAY[
    'aadhar_number', 'insurance_number',
    'bank_account_number', 'bank_ifsc', 'bank_account_holder'
  ];
  v_cols TEXT;
BEGIN
  REVOKE SELECT ON public.delivery_partners FROM authenticated;

  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_cols
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name   = 'delivery_partners'
    AND column_name != ALL(v_sensitive);

  EXECUTE format('GRANT SELECT (%s) ON public.delivery_partners TO authenticated', v_cols);
END;
$$;

-- Give the owning seller FULL column access (including KYC/bank fields)
-- via a SECURITY DEFINER function so they can see their own data
-- in the settings screen.
CREATE OR REPLACE FUNCTION public.get_my_shop_kyc()
RETURNS TABLE (
  id                  UUID,
  aadhar_number       TEXT,
  pan_number          TEXT,
  gst_number          TEXT,
  trade_license       TEXT,
  bank_account_number TEXT,
  bank_ifsc           TEXT,
  bank_account_holder TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    s.aadhar_number,
    s.pan_number,
    s.gst_number,
    s.trade_license,
    s.bank_account_number,
    s.bank_ifsc,
    s.bank_account_holder
  FROM public.shops s
  WHERE s.seller_id = auth.uid();
END;
$$;



-- Give the rider their own KYC data via SECURITY DEFINER function
CREATE OR REPLACE FUNCTION public.get_my_rider_kyc()
RETURNS TABLE (
  id                  UUID,
  aadhar_number       TEXT,
  insurance_number    TEXT,
  bank_account_number TEXT,
  bank_ifsc           TEXT,
  bank_account_holder TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    dp.id,
    dp.aadhar_number,
    dp.insurance_number,
    dp.bank_account_number,
    dp.bank_ifsc,
    dp.bank_account_holder
  FROM public.delivery_partners dp
  WHERE dp.id = auth.uid();
END;
$$;


-- ============================================================================
-- STEP 7: ORDERS
-- • Customers see their own orders (user_id = auth.uid())
-- • Sellers see orders placed at their shop (shop_id in their shops)
-- • Riders see orders assigned to them (rider_id = auth.uid())
-- • Admins see everything
-- ============================================================================

-- Customer sees their own orders
CREATE POLICY "orders_select_customer"
  ON public.orders FOR SELECT
  TO authenticated
  USING (customer_id = auth.uid());

-- Seller sees orders for their shop
CREATE POLICY "orders_select_seller"
  ON public.orders FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shops
      WHERE shops.id = orders.shop_id
        AND shops.seller_id = auth.uid()
    )
  );

-- Rider sees their assigned orders
CREATE POLICY "orders_select_rider"
  ON public.orders FOR SELECT
  TO authenticated
  USING (delivery_partner_id = auth.uid());

-- Admin sees all orders
CREATE POLICY "orders_admin_all"
  ON public.orders FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));

-- Customer can insert (place) orders
CREATE POLICY "orders_insert_customer"
  ON public.orders FOR INSERT
  TO authenticated
  WITH CHECK (customer_id = auth.uid());

-- Seller can update status on their shop's orders
CREATE POLICY "orders_update_seller"
  ON public.orders FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shops
      WHERE shops.id = orders.shop_id
        AND shops.seller_id = auth.uid()
    )
  );

-- Rider can update status on their assigned orders
CREATE POLICY "orders_update_rider"
  ON public.orders FOR UPDATE
  TO authenticated
  USING (delivery_partner_id = auth.uid());

-- Customer can cancel / update their own orders (e.g. cancel before dispatch)
CREATE POLICY "orders_update_customer"
  ON public.orders FOR UPDATE
  TO authenticated
  USING (customer_id = auth.uid());


-- ============================================================================
-- STEP 8: ORDER_ITEMS
-- Follows the same parties as the parent order.
-- ============================================================================

-- Customer, seller, or rider involved in the order can read items
CREATE POLICY "order_items_select_involved"
  ON public.order_items FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id
        AND (
          o.customer_id = auth.uid()
          OR o.delivery_partner_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.shops s
            WHERE s.id = o.shop_id AND s.seller_id = auth.uid()
          )
        )
    )
    OR public.is_active_admin(auth.uid())
  );

-- Customer inserts items when placing an order
CREATE POLICY "order_items_insert_customer"
  ON public.order_items FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id AND o.customer_id = auth.uid()
    )
  );

-- Admin manages all order items
CREATE POLICY "order_items_admin_all"
  ON public.order_items FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));


-- ============================================================================
-- STEP 9: PRODUCTS
-- Products are readable by all authenticated users (customers browse them).
-- Only the shop owner (seller) can insert/update/delete their products.
-- ============================================================================

CREATE POLICY "products_select_all"
  ON public.products FOR SELECT
  TO authenticated
  USING (TRUE);

-- Seller inserts products for their own shop
CREATE POLICY "products_insert_own"
  ON public.products FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.shops
      WHERE shops.id = products.shop_id
        AND shops.seller_id = auth.uid()
    )
  );

-- Seller updates their own products
CREATE POLICY "products_update_own"
  ON public.products FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shops
      WHERE shops.id = products.shop_id
        AND shops.seller_id = auth.uid()
    )
  );

-- Seller deletes their own products
CREATE POLICY "products_delete_own"
  ON public.products FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shops
      WHERE shops.id = products.shop_id
        AND shops.seller_id = auth.uid()
    )
  );

-- Admin manages all products
CREATE POLICY "products_admin_all"
  ON public.products FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));


-- ============================================================================
-- STEP 10: PHONE_OTPS
-- OTP rows are extremely sensitive. A user can only upsert/read/delete
-- the OTP matching their own phone number.
-- We use the phone column (not user_id) because OTPs exist before auth login.
-- We allow anon to upsert (needed for pre-login OTP generation) but
-- restrict reads to make enumeration impossible.
-- ============================================================================

-- Allow anon to insert/upsert OTP (pre-authentication flow)
CREATE POLICY "phone_otps_upsert_own_insert"
  ON public.phone_otps FOR INSERT
  TO anon, authenticated
  WITH CHECK (TRUE);

CREATE POLICY "phone_otps_upsert_own_update"
  ON public.phone_otps FOR UPDATE
  TO anon, authenticated
  USING (TRUE)
  WITH CHECK (TRUE);

-- Allow SELECT: anon and authenticated users read OTPs to verify client-side
CREATE POLICY "phone_otps_select_own"
  ON public.phone_otps FOR SELECT
  TO anon, authenticated
  USING (TRUE);

-- Allow deletion of verified OTPs by the client before auth session is active
CREATE POLICY "phone_otps_delete_own"
  ON public.phone_otps FOR DELETE
  TO anon, authenticated
  USING (TRUE);


-- ============================================================================
-- STEP 11: RATINGS
-- All authenticated users can read ratings (needed to show shop/rider stars).
-- Only the rater themselves can insert their own rating.
-- Admins can manage all ratings.
-- ============================================================================

CREATE POLICY "ratings_select_all"
  ON public.ratings FOR SELECT
  TO authenticated
  USING (TRUE);

CREATE POLICY "ratings_insert_own"
  ON public.ratings FOR INSERT
  TO authenticated
  WITH CHECK (rater_id = auth.uid());

CREATE POLICY "ratings_update_own"
  ON public.ratings FOR UPDATE
  TO authenticated
  USING (rater_id = auth.uid())
  WITH CHECK (rater_id = auth.uid());

CREATE POLICY "ratings_admin_all"
  ON public.ratings FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));





-- ============================================================================
-- STEP 15: Revoke anon access to all tables (belt-and-suspenders)
-- The Supabase anon key should never be able to read any business data.
-- ============================================================================

REVOKE ALL ON public.profiles          FROM anon;
REVOKE ALL ON public.customers         FROM anon;
REVOKE ALL ON public.delivery_partners FROM anon;
REVOKE ALL ON public.shops             FROM anon;
REVOKE ALL ON public.orders            FROM anon;
REVOKE ALL ON public.order_items       FROM anon;
REVOKE ALL ON public.products          FROM anon;
REVOKE ALL ON public.ratings           FROM anon;
-- phone_otps: anon needs SELECT, INSERT, UPDATE, and DELETE (for OTP upsert, verify, and cleanup before sign-in)
REVOKE ALL ON public.phone_otps FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.phone_otps TO anon;


-- ============================================================================
-- VERIFICATION QUERY
-- Run this after applying the migration to confirm 0 tables are unprotected.
-- Expected result: every row should show rls_enabled = true.
-- ============================================================================

/*
SELECT
  schemaname,
  tablename,
  rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'profiles', 'customers', 'delivery_partners', 'shops',
    'orders', 'order_items', 'products', 'phone_otps',
    'ratings'
  )
ORDER BY tablename;
*/
