-- =============================================================================
-- Migration: 100x Final Idempotency Constraint Fix
-- Description:
--   Fixes the multi-shop checkout crash. The original idempotency constraint 
--   was UNIQUE (idempotency_key). Because a multi-shop cart places multiple 
--   orders with the same idempotency key (one per shop), this would trigger a 
--   Unique Constraint Violation and crash every multi-shop checkout attempt.
--   We change this to UNIQUE (idempotency_key, shop_id), which flawlessly 
--   supports multi-shop orders while perfectly blocking duplicate concurrent 
--   network requests for the same checkout event.
-- =============================================================================

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_idempotency_key_key;
ALTER TABLE public.orders ADD CONSTRAINT orders_idempotency_key_shop_id_key UNIQUE (idempotency_key, shop_id);
