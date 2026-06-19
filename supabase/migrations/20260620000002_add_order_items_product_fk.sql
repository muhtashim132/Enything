-- ============================================================================
-- Migration: 20260620000002_add_order_items_product_fk.sql
-- Description:
--   1. Add a foreign key from order_items.product_id → products.id (idempotent).
--      This lets PostgREST resolve the relationship for nested selects and
--      allows the Admin GST Statement page to join items with product categories.
--   2. Grant SELECT on products to anon + authenticated (was missing for anon).
--   3. Grant SELECT on order_items to anon + authenticated (belt-and-suspenders).
-- ============================================================================

-- ── Step 1: Add FK (idempotent) ───────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   information_schema.table_constraints
    WHERE  constraint_schema = 'public'
      AND  constraint_name   = 'order_items_product_id_fkey'
  ) THEN
    ALTER TABLE public.order_items
      ADD CONSTRAINT order_items_product_id_fkey
      FOREIGN KEY (product_id)
      REFERENCES public.products(id)
      ON DELETE SET NULL;   -- if a product is deleted, keep order_item with NULL product_id
  END IF;
END $$;

-- ── Step 2: Ensure SELECT grants (idempotent — GRANT is always safe to re-run) ─
GRANT SELECT ON public.products     TO anon, authenticated;
GRANT SELECT ON public.order_items  TO anon, authenticated;
GRANT SELECT ON public.orders       TO anon, authenticated;
GRANT SELECT ON public.shops        TO anon, authenticated;

-- ── Step 3: Reload PostgREST schema cache ─────────────────────────────────────
-- Without this the new FK relationship won't appear in the schema cache
-- and nested queries (order_items → products) will fail with PGRST200.
NOTIFY pgrst, 'reload schema';
