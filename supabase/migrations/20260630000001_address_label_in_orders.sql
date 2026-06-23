-- ============================================================================
-- Add address_label column to orders table
-- Stores the emoji + label (e.g. "🏠 Home", "💼 Office") separately from the
-- full address string, so the rider dashboard can display them distinctly.
-- PURELY ADDITIVE — zero risk to existing rows (they get NULL, handled in Dart).
-- ============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS address_label TEXT;

-- Re-affirm grants (safe to run multiple times)
GRANT SELECT, INSERT, UPDATE ON public.orders TO authenticated;
GRANT SELECT ON public.orders TO anon;
