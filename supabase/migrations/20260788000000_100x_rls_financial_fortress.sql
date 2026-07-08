-- =============================================================================
-- Migration: 100x RLS Financial Fortress (Infinite Money Glitch Fix)
-- Description:
--   1. Drops extremely permissive `FOR ALL` and `UPDATE` RLS policies on 
--      `withdrawals` and `orders` that allowed bypassing backend RPC logic.
--   2. Revokes mutating table privileges (`INSERT`, `UPDATE`, `DELETE`) on 
--      `withdrawals` and `orders` from `authenticated` users, forcing all 
--      operations through `SECURITY DEFINER` RPCs.
--   3. Creates strict `SELECT`-only policies for historical viewing.
-- =============================================================================

-- 1. Strip all dangerous mutating table privileges from public and authenticated users
REVOKE INSERT, UPDATE, DELETE ON public.withdrawals FROM public, anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.orders FROM public, anon, authenticated;

-- Ensure service_role retains full access for Edge Functions and RPCs
GRANT SELECT, INSERT, UPDATE, DELETE ON public.withdrawals TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.orders TO service_role;

-- 2. Drop dangerous RLS policies on Withdrawals
DROP POLICY IF EXISTS "Users can manage their own withdrawals" ON public.withdrawals;
DROP POLICY IF EXISTS "Sellers can manage their own withdrawals" ON public.withdrawals;

-- Recreate strict SELECT-only policy for withdrawals
CREATE POLICY "Users can view their own withdrawals"
    ON public.withdrawals FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- 3. Drop dangerous RLS policies on Orders
DROP POLICY IF EXISTS "orders_update_seller" ON public.orders;
DROP POLICY IF EXISTS "orders_update_rider" ON public.orders;
DROP POLICY IF EXISTS "orders_update_customer" ON public.orders;
DROP POLICY IF EXISTS "orders_insert_customer" ON public.orders;

-- 4. Re-assert read-only grants to authenticated to ensure UI functions work
GRANT SELECT ON public.withdrawals TO authenticated;
GRANT SELECT ON public.orders TO authenticated;
