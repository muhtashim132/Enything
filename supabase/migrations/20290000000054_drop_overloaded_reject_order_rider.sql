-- =============================================================================
-- Migration: 20290000000054_drop_overloaded_reject_order_rider.sql
-- Description: Drops obsolete 4-argument reject_order_rider to resolve
-- PostgREST PGRST203 Multiple Choices overloading ambiguity.
-- =============================================================================

DROP FUNCTION IF EXISTS public.reject_order_rider(UUID, TEXT, NUMERIC, BOOLEAN);

NOTIFY pgrst, 'reload schema';
