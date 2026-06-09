-- ============================================================================
-- Migration: 20260610000001_definitive_permissions_and_rls_fix.sql
-- Description: Definitively fixes "Grant SELECT" / "Missing columns" errors
--              by asserting table-level grants and reloading the PostgREST cache.
--              Also fixes the "Missing rows" bug for order items by ensuring
--              unassigned riders and sellers can properly read order_items.
-- ============================================================================

-- ── Step 1: Fix order_items visibility (Missing Rows Fix) ───────────────────
-- Previously, riders could only see items for orders they were already assigned to.
-- This caused unassigned riders to see 0 items when browsing available orders.
-- Also, the seller policy was querying 'shops' directly instead of using the
-- secure 'get_seller_shop_ids' function, causing RLS infinite loop risks.

DROP POLICY IF EXISTS "order_items_select_involved" ON public.order_items;
CREATE POLICY "order_items_select_involved"
  ON public.order_items FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id
        AND (
          -- 1. Customer who placed the order
          o.customer_id = auth.uid()
          
          -- 2. Rider already assigned to the order
          OR o.delivery_partner_id = auth.uid()
          
          -- 3. Seller whose shop received the order (safely bypasses shops RLS)
          OR o.shop_id IN (SELECT public.get_seller_shop_ids(auth.uid()))
          
          -- 4. Rider browsing available (unassigned) orders
          OR (
            o.delivery_partner_id IS NULL
            AND o.status IN ('awaiting_acceptance', 'pending', 'confirmed')
            AND EXISTS (
              SELECT 1 FROM public.delivery_partners dp
              WHERE dp.id = auth.uid()
                AND (dp.is_active = true OR dp.is_available = true)
            )
          )
        )
    )
    -- 5. Admin users see all
    OR public.is_active_admin(auth.uid())
  );

-- ── Step 2: Assert Definitive Table-Level Grants ─────────────────────────────
-- This guarantees no "Permission denied" errors for standard select() queries.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.orders            TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.order_items       TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.shops             TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.delivery_partners TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles          TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.customers         TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.products          TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ratings           TO authenticated;

-- ── Step 3: Flush PostgREST Schema Cache (CRITICAL) ──────────────────────────
-- Without this, Supabase caches previous column-level restrictions and 
-- continues throwing "Permission denied" errors for the client.
NOTIFY pgrst, 'reload schema';
