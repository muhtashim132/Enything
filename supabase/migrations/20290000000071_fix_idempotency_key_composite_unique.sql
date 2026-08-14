-- =============================================================================
-- Migration: 20290000000071_fix_idempotency_key_composite_unique.sql
-- =============================================================================
-- Description:
--   Updates idx_orders_idempotency_key to UNIQUE (idempotency_key, shop_id)
--   to seamlessly support multi-shop cart checkouts where each sub-order shares
--   the cart transaction's idempotency key.
-- =============================================================================

DROP INDEX IF EXISTS public.idx_orders_idempotency_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_idempotency_key 
ON public.orders(idempotency_key, shop_id) 
WHERE idempotency_key IS NOT NULL;
