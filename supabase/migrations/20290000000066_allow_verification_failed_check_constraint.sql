-- =============================================================================
-- Migration: 20290000000066_allow_verification_failed_check_constraint.sql
-- =============================================================================
-- Description:
--   Updates the `orders_status_check` constraint on public.orders to allow
--   'verification_failed' (used when pharmacy rejects invalid prescriptions).
-- =============================================================================

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders ADD CONSTRAINT orders_status_check CHECK (
  status = ANY (ARRAY[
    'awaiting_acceptance'::text,
    'awaiting_payment'::text,
    'pending'::text,
    'confirmed'::text,
    'preparing'::text,
    'ready_for_pickup'::text,
    'picked_up'::text,
    'out_for_delivery'::text,
    'delivered'::text,
    'cancelled'::text,
    'seller_rejected'::text,
    'partner_rejected'::text,
    'verification_failed'::text
  ])
);
