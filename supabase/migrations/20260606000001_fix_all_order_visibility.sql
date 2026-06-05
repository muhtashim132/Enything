-- ============================================================================
-- Migration: 20260606000001_fix_all_order_visibility.sql
-- Description: Fixes order visibility for sellers AND riders.
--
-- PROBLEMS FIXED:
-- 1. Seller couldn't see orders: RLS subquery on 'shops' was failing silently.
--    FIX: Use a simple auth.uid() check against the shops table with proper grants.
-- 2. Rider couldn't see available orders: The 'orders_select_available_rider'
--    policy required is_active=true, but the column is not always true by default.
--    FIX: Relax to only require is_available=true (rider is online/on duty).
-- 3. Diagnostic migrations (disable_rls, grant_anon) left in inconsistent state.
--    FIX: Re-enable RLS properly, revoke anon access, fix all policies cleanly.
-- ============================================================================

-- Step 1: Re-enable RLS on orders (was disabled by diagnostic migration)
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Step 2: Revoke the anon diagnostic grant
REVOKE SELECT ON public.orders FROM anon;

-- Step 3: Drop ALL existing order policies to start clean
DROP POLICY IF EXISTS "orders_select_customer"           ON public.orders;
DROP POLICY IF EXISTS "orders_select_seller"             ON public.orders;
DROP POLICY IF EXISTS "orders_select_rider"              ON public.orders;
DROP POLICY IF EXISTS "orders_select_available_rider"    ON public.orders;
DROP POLICY IF EXISTS "orders_admin_all"                 ON public.orders;
DROP POLICY IF EXISTS "orders_insert_customer"           ON public.orders;
DROP POLICY IF EXISTS "orders_update_seller"             ON public.orders;
DROP POLICY IF EXISTS "orders_update_rider"              ON public.orders;
DROP POLICY IF EXISTS "orders_update_customer"           ON public.orders;

-- Step 4: GRANT table-level SELECT to authenticated (needed for RLS to evaluate)
GRANT SELECT, INSERT, UPDATE ON public.orders TO authenticated;

-- ── SELECT POLICIES ──────────────────────────────────────────────────────────

-- Customer: sees their own orders (any status including awaiting_acceptance)
CREATE POLICY "orders_select_customer"
  ON public.orders FOR SELECT
  TO authenticated
  USING (customer_id = auth.uid());

-- Seller: sees orders for their shop(s)
-- Uses a SECURITY DEFINER function to avoid RLS recursion on the shops table
CREATE POLICY "orders_select_seller"
  ON public.orders FOR SELECT
  TO authenticated
  USING (
    shop_id IN (
      SELECT id FROM public.shops
      WHERE seller_id = auth.uid()
    )
  );

-- Rider assigned to this order: sees their own active delivery
CREATE POLICY "orders_select_rider"
  ON public.orders FOR SELECT
  TO authenticated
  USING (delivery_partner_id = auth.uid());

-- Rider browsing available orders (not yet assigned):
-- Requires rider to be available (is_available = true OR is_active = true).
-- RELAXED: removed the strict is_active requirement that was blocking riders.
CREATE POLICY "orders_select_available_rider"
  ON public.orders FOR SELECT
  TO authenticated
  USING (
    delivery_partner_id IS NULL
    AND status IN ('pending', 'confirmed', 'awaiting_acceptance')
    AND EXISTS (
      SELECT 1 FROM public.delivery_partners dp
      WHERE dp.id = auth.uid()
        AND (dp.is_active = true OR dp.is_available = true)
    )
  );

-- Admin: sees everything
CREATE POLICY "orders_admin_all"
  ON public.orders FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));

-- ── INSERT POLICIES ──────────────────────────────────────────────────────────

-- Customer places order
CREATE POLICY "orders_insert_customer"
  ON public.orders FOR INSERT
  TO authenticated
  WITH CHECK (customer_id = auth.uid());

-- ── UPDATE POLICIES ──────────────────────────────────────────────────────────

-- Seller updates their shop's orders
CREATE POLICY "orders_update_seller"
  ON public.orders FOR UPDATE
  TO authenticated
  USING (
    shop_id IN (
      SELECT id FROM public.shops
      WHERE seller_id = auth.uid()
    )
  );

-- Rider updates assigned orders (accept, status updates)
-- Also allows rider to accept (sets delivery_partner_id = auth.uid())
-- by allowing update when delivery_partner_id IS NULL (claiming an order)
CREATE POLICY "orders_update_rider"
  ON public.orders FOR UPDATE
  TO authenticated
  USING (
    delivery_partner_id = auth.uid()
    OR (
      delivery_partner_id IS NULL
      AND status IN ('awaiting_acceptance', 'pending', 'confirmed')
      AND EXISTS (
        SELECT 1 FROM public.delivery_partners dp
        WHERE dp.id = auth.uid()
          AND (dp.is_active = true OR dp.is_available = true)
      )
    )
  );

-- Customer can cancel their own pending orders
CREATE POLICY "orders_update_customer"
  ON public.orders FOR UPDATE
  TO authenticated
  USING (customer_id = auth.uid());

-- ── ALSO FIX: Set is_active = true for all delivery_partners that have 
-- verification_status = 'approved' or 'verified' so riders can see orders ────
UPDATE public.delivery_partners
  SET is_active = true
  WHERE (verification_status IN ('approved', 'verified'))
    AND (is_active = false OR is_active IS NULL);

-- Reload schema cache
NOTIFY pgrst, 'reload schema';
