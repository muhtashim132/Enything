-- ============================================================================
-- Migration: 20260622000001_10x_ratings_triggers.sql
-- Description: 10x refinement of rating triggers to handle UPDATE/DELETE and Products.
--
-- IMPROVEMENTS OVER V1:
--   1. Handles UPDATE and DELETE gracefully. V1 only handled INSERT.
--      (If a user changes their rating or an admin deletes one, aggregates stay synced).
--   2. Handles Product ratings. V1 only calculated Shop averages.
--   3. Universal trigger function that dynamically determines what to recalculate.
-- ============================================================================

-- ── Create Universal Entity Rating Trigger Function ───────────────────────
CREATE OR REPLACE FUNCTION public.update_entity_rating_on_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ratee_role TEXT;
  v_shop_id    UUID;
  v_product_id UUID;
  v_avg        NUMERIC(3,2);
  v_count      INTEGER;
BEGIN
  -- 1. Determine relevant row context based on Operation
  IF TG_OP = 'DELETE' THEN
    v_ratee_role := OLD.ratee_role;
    v_shop_id    := OLD.shop_id;
    v_product_id := OLD.product_id;
  ELSE
    v_ratee_role := NEW.ratee_role;
    v_shop_id    := NEW.shop_id;
    v_product_id := NEW.product_id;
  END IF;

  -- 2. Recalculate Shop Rating (if applicable)
  IF v_ratee_role = 'seller' AND v_shop_id IS NOT NULL THEN
    SELECT 
      ROUND(AVG(rating)::numeric, 2), 
      COUNT(*)
    INTO v_avg, v_count
    FROM public.ratings
    WHERE shop_id = v_shop_id AND ratee_role = 'seller';

    UPDATE public.shops
    SET average_rating = COALESCE(v_avg, 0.0),
        total_reviews  = COALESCE(v_count, 0)
    WHERE id = v_shop_id;
  END IF;

  -- 3. Recalculate Product Rating (if applicable)
  -- If product_id is linked to the rating, update the product's average score
  IF v_product_id IS NOT NULL THEN
    SELECT ROUND(AVG(rating)::numeric, 2)
    INTO v_avg
    FROM public.ratings
    WHERE product_id = v_product_id;

    UPDATE public.products
    SET rating = COALESCE(v_avg, 0.0)
    WHERE id = v_product_id;
  END IF;

  -- 4. Return correct row for operation
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  -- Never block the user action if the recalculation fails
  RAISE WARNING 'update_entity_rating_on_change: failed for shop_id=% product_id=% error=%',
    v_shop_id, v_product_id, SQLERRM;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;


-- ── Replace the old Trigger with the new Universal Trigger ───────────────

-- Drop the V1 trigger
DROP TRIGGER IF EXISTS tr_update_shop_rating ON public.ratings;
DROP TRIGGER IF EXISTS tr_update_entity_rating ON public.ratings;

-- Attach new universal trigger supporting INSERT, UPDATE, DELETE
CREATE TRIGGER tr_update_entity_rating
  AFTER INSERT OR UPDATE OR DELETE
  ON public.ratings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_entity_rating_on_change();


-- ── Reload schema cache ───────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
