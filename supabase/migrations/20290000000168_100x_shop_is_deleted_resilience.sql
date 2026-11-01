-- ============================================================================
-- Migration: 20290000000168_100x_shop_is_deleted_resilience.sql
-- Description:
--   100x Forensic Database Resilience: Add is_deleted column to public.shops
--   table with safe DEFAULT false.
--
-- Background:
--   While the project soft-delete rule primarily applies to products, queries
--   in practice simulation, bulk kitchen assignment, and admin tools sometimes
--   reference `is_deleted = false` on shops. Adding this column with DEFAULT false
--   guarantees that:
--   1. Any SQL query or PostgREST call checking `is_deleted = false` succeeds
--      without 42703 (undefined column) exceptions.
--   2. Backward compatibility is 100% preserved (all existing shops remain false).
-- ============================================================================

ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_shops_is_deleted
  ON public.shops(is_deleted);

