-- =============================================================================
-- Migration: 20290000000061_100x_drop_ambiguous_update_order_status.sql
-- Description: Drops obsolete 4-arg update_order_status to resolve PostgREST PGRST203 ambiguity
-- =============================================================================

DROP FUNCTION IF EXISTS public.update_order_status(UUID, text, timestamptz, numeric);
