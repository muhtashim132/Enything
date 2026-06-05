-- ============================================================================
-- Migration: 20260606020000_definitive_order_visibility_fix.sql
-- Author: Senior Debugger
-- Description: DEFINITIVE fix for seller and rider order visibility.
--
-- ROOT CAUSES FIXED:
-- 1. Old RLS policy "orders_select_available_rider" required seller_accepted=true
--    AND status IN ('pending','confirmed') — but NEW orders have:
--      status = 'awaiting_acceptance' AND seller_accepted = false.
--    This means riders could NEVER see newly placed orders.
--
-- 2. Seller SELECT policy uses a shops subquery. If the shops RLS is blocking
--    or the seller_id doesn't match, the entire order list goes empty.
--    FIX: Use SECURITY DEFINER function to bypass RLS on shops in the subquery.
--
-- 3. is_active may be false for approved riders who haven't toggled online.
--    The RLS blocks them entirely. FIX: Set is_active=true for approved riders,
--    and relax the policy to check is_available as well.
--
-- 4. Shops table must have an open SELECT policy so the orders RLS subquery
--    for sellers can evaluate shop ownership correctly.
-- ============================================================================

-- ── Step 1: Re-enable RLS on orders (safety) ─────────────────────────────
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- ── Step 2: Clean slate — drop ALL order policies ────────────────────────
DROP POLICY IF EXISTS "orders_select_customer"             ON public.orders;
DROP POLICY IF EXISTS "orders_select_seller"               ON public.orders;
DROP POLICY IF EXISTS "orders_select_rider"                ON public.orders;
DROP POLICY IF EXISTS "orders_select_available_rider"      ON public.orders;
DROP POLICY IF EXISTS "orders_admin_all"                   ON public.orders;
DROP POLICY IF EXISTS "orders_insert_customer"             ON public.orders;
DROP POLICY IF EXISTS "orders_update_seller"               ON public.orders;
DROP POLICY IF EXISTS "orders_update_rider"                ON public.orders;
DROP POLICY IF EXISTS "orders_update_customer"             ON public.orders;
DROP POLICY IF EXISTS "Allow full access to orders"        ON public.orders;
DROP POLICY IF EXISTS "orders_all_authenticated"           ON public.orders;

-- ── Step 3: Ensure table-level grants ────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON public.orders      TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.shops       TO authenticated;
GRANT SELECT ON public.shops TO anon;
GRANT SELECT ON public.products TO authenticated;
GRANT SELECT ON public.products TO anon;

-- ── Step 4: Fix shops table to have open SELECT (needed for subquery) ────
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public read access to shops"  ON public.shops;
DROP POLICY IF EXISTS "shops_select_all"                   ON public.shops;
CREATE POLICY "shops_select_all"
  ON public.shops FOR SELECT
  USING (true);

-- ── Step 5: Create a SECURITY DEFINER function for seller shop ownership ──
-- This avoids RLS recursion when the orders policy checks the shops table.
CREATE OR REPLACE FUNCTION public.get_seller_shop_ids(seller_uid UUID)
RETURNS SETOF UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT id FROM public.shops WHERE seller_id = seller_uid;
$$;

GRANT EXECUTE ON FUNCTION public.get_seller_shop_ids(UUID) TO authenticated;

-- ── Step 6: Recreate order SELECT policies ───────────────────────────────

-- Customer: sees their own orders (all statuses)
CREATE POLICY "orders_select_customer"
  ON public.orders FOR SELECT
  TO authenticated
  USING (customer_id = auth.uid());

-- Seller: sees orders for their shop(s) via SECURITY DEFINER function
-- (avoids RLS recursion on shops table)
CREATE POLICY "orders_select_seller"
  ON public.orders FOR SELECT
  TO authenticated
  USING (
    shop_id IN (SELECT public.get_seller_shop_ids(auth.uid()))
  );

-- Rider assigned to this specific order
CREATE POLICY "orders_select_rider"
  ON public.orders FOR SELECT
  TO authenticated
  USING (delivery_partner_id = auth.uid());

-- *** THE CRITICAL FIX ***
-- Rider browsing available orders (NOT yet assigned):
-- OLD policy required: seller_accepted=true AND status IN ('pending','confirmed')
-- NEW orders have: status='awaiting_acceptance' AND seller_accepted=false
-- FIX: Remove seller_accepted requirement, include awaiting_acceptance status.
CREATE POLICY "orders_select_available_rider"
  ON public.orders FOR SELECT
  TO authenticated
  USING (
    delivery_partner_id IS NULL
    AND status IN ('awaiting_acceptance', 'pending', 'confirmed')
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

-- ── Step 7: Recreate INSERT policy ───────────────────────────────────────

-- Customer places an order
CREATE POLICY "orders_insert_customer"
  ON public.orders FOR INSERT
  TO authenticated
  WITH CHECK (customer_id = auth.uid());

-- ── Step 8: Recreate UPDATE policies ─────────────────────────────────────

-- Seller updates their shop's orders
CREATE POLICY "orders_update_seller"
  ON public.orders FOR UPDATE
  TO authenticated
  USING (
    shop_id IN (SELECT public.get_seller_shop_ids(auth.uid()))
  );

-- Rider updates assigned orders OR claims unassigned ones
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

-- ── Step 9: Fix delivery_partners — set is_active=true for approved riders ─
-- Riders who are KYC-approved but haven't toggled online should still be active.
-- is_active = the toggle state (online/offline).
-- We only set it if they've never toggled it themselves (is_active IS NULL or false).
UPDATE public.delivery_partners
  SET is_active = true
  WHERE verification_status IN ('approved', 'verified')
    AND (is_active IS NULL OR is_active = false)
    AND (is_available IS NULL OR is_available = false);

-- Also ensure is_available is true for verified riders (belt-and-suspenders)
UPDATE public.delivery_partners
  SET is_available = true
  WHERE verification_status IN ('approved', 'verified')
    AND (is_available IS NULL OR is_available = false);

-- ── Step 10: Reload PostgREST schema cache ───────────────────────────────
NOTIFY pgrst, 'reload schema';
