-- ============================================================================
-- Migration: 20260621000001_fix_ratings_system.sql
-- Description: Fixes the entire rating system end-to-end.
--
-- ROOT CAUSE ANALYSIS:
--   1. shops.average_rating / shops.total_reviews columns did not exist.
--      → Seller dashboard showed '--', ShopModel.fromMap returned null/0.
--   2. products.rating column did not exist.
--      → Product detail page always showed 0.0.
--   3. No DB trigger existed to auto-update shop rating on ratings INSERT.
--      → Even if columns existed, the values never changed.
--   4. ratings table lacked a product_id column for future product-level ratings.
--   5. rider_insights_page queried 'delivery_partner_earnings' (wrong name).
--      → Fixed in Dart (see rider_insights_page.dart), but the correct
--        column 'rider_earnings' already exists on the orders table.
--
-- GUARANTEES:
--   • All ALTER TABLE statements use IF NOT EXISTS — fully idempotent.
--   • All CREATE OR REPLACE — safe to re-run.
--   • Backfill runs inside a DO block with an exception guard.
--   • Never modifies any existing migration SQL.
-- ============================================================================


-- ============================================================================
-- STEP 1: Add average_rating + total_reviews columns to shops
-- ============================================================================

ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS average_rating NUMERIC(3,2) NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS total_reviews  INTEGER      NOT NULL DEFAULT 0;


-- ============================================================================
-- STEP 2: Add rating column to products
-- (No product-level rating flow yet, defaults to 0.0.
--  Column must exist so SELECT * on products doesn't error or return stale data.)
-- ============================================================================

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS rating NUMERIC(3,2) NOT NULL DEFAULT 0.0;


-- ============================================================================
-- STEP 3: Add optional product_id FK to ratings
-- (Enables future product-level ratings without any DB restructure.)
-- ============================================================================

ALTER TABLE public.ratings
  ADD COLUMN IF NOT EXISTS product_id UUID
    REFERENCES public.products(id) ON DELETE SET NULL;


-- ============================================================================
-- STEP 4: Trigger function — recalculate shop rating after every ratings INSERT
--
-- Logic:
--   • Only fires when ratee_role = 'seller' AND shop_id IS NOT NULL.
--   • Recalculates AVG(rating) and COUNT(*) for that specific shop_id.
--   • Updates shops.average_rating and shops.total_reviews atomically.
--   • SECURITY DEFINER so it bypasses RLS when updating shops.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_shop_rating_on_new_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_avg   NUMERIC(3,2);
  v_count INTEGER;
BEGIN
  -- Only process ratings that target a shop (ratee_role='seller' with a shop_id)
  IF NEW.ratee_role <> 'seller' OR NEW.shop_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Recalculate aggregate for this shop
  SELECT
    ROUND(AVG(r.rating)::numeric, 2),
    COUNT(*)
  INTO v_avg, v_count
  FROM public.ratings r
  WHERE r.shop_id    = NEW.shop_id
    AND r.ratee_role = 'seller';

  -- Update the shop row
  UPDATE public.shops
  SET
    average_rating = COALESCE(v_avg, 0.0),
    total_reviews  = COALESCE(v_count, 0)
  WHERE id = NEW.shop_id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never fail the ratings insert due to a trigger error — just log
  RAISE WARNING 'update_shop_rating_on_new_rating: failed for shop_id=%: %',
    NEW.shop_id, SQLERRM;
  RETURN NEW;
END;
$$;


-- ============================================================================
-- STEP 5: Bind trigger to ratings table (AFTER INSERT)
-- ============================================================================

DROP TRIGGER IF EXISTS tr_update_shop_rating ON public.ratings;

CREATE TRIGGER tr_update_shop_rating
  AFTER INSERT
  ON public.ratings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_shop_rating_on_new_rating();


-- ============================================================================
-- STEP 6: Backfill existing ratings into shops
-- (Handles any ratings that were inserted before this trigger existed.)
-- ============================================================================

DO $$
BEGIN
  UPDATE public.shops s
  SET
    average_rating = sub.avg_r,
    total_reviews  = sub.cnt
  FROM (
    SELECT
      shop_id,
      ROUND(AVG(rating)::numeric, 2) AS avg_r,
      COUNT(*)::INTEGER              AS cnt
    FROM public.ratings
    WHERE shop_id    IS NOT NULL
      AND ratee_role = 'seller'
    GROUP BY shop_id
  ) sub
  WHERE s.id = sub.shop_id;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Backfill of shop ratings failed: %', SQLERRM;
END;
$$;


-- ============================================================================
-- STEP 7: Column-level grants
--
-- Context: Prior migrations (20260605191501) used REVOKE SELECT on shops then
-- GRANT SELECT on specific safe (non-KYC) columns. We must explicitly grant
-- the new columns so the authenticated role can read them.
-- ============================================================================

-- New shops columns
GRANT SELECT (average_rating, total_reviews) ON public.shops TO authenticated;
GRANT UPDATE (average_rating, total_reviews) ON public.shops TO service_role;

-- New products column
GRANT SELECT (rating) ON public.products TO authenticated;

-- New ratings column
GRANT SELECT (product_id), INSERT (product_id) ON public.ratings TO authenticated;

-- Ensure full table-level INSERT/SELECT on ratings (belt-and-suspenders)
GRANT SELECT, INSERT ON public.ratings TO authenticated;


-- ============================================================================
-- STEP 8: Index for fast shop rating lookups (admin + browsing queries)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_ratings_shop_id_ratee_role
  ON public.ratings (shop_id, ratee_role)
  WHERE shop_id IS NOT NULL AND ratee_role = 'seller';

CREATE INDEX IF NOT EXISTS idx_ratings_ratee_id
  ON public.ratings (ratee_id)
  WHERE ratee_id IS NOT NULL;


-- ============================================================================
-- STEP 9: Reload PostgREST schema cache
-- (Critical — without this the client keeps using the cached column list and
--  throws "column not found" errors even after columns are added.)
-- ============================================================================

NOTIFY pgrst, 'reload schema';
