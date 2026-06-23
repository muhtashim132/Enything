-- ============================================================================
-- Migration: 20260629000004_10x_ratings_display_fix.sql
-- Description: Adds total_reviews to products and fixes Grant SELECT errors
-- ============================================================================

-- 1. Add total_reviews to products
ALTER TABLE public.products 
  ADD COLUMN IF NOT EXISTS total_reviews INTEGER NOT NULL DEFAULT 0;

-- 2. Update the trigger function to include total_reviews for products
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
  IF v_product_id IS NOT NULL THEN
    SELECT 
      ROUND(AVG(rating)::numeric, 2), 
      COUNT(*)
    INTO v_avg, v_count
    FROM public.ratings
    WHERE product_id = v_product_id;

    UPDATE public.products
    SET rating = COALESCE(v_avg, 0.0),
        total_reviews = COALESCE(v_count, 0)
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

-- 3. Fix "Grant SELECT Error" by explicitly granting SELECT on tables
GRANT SELECT ON public.shops TO authenticated, anon;
GRANT SELECT ON public.products TO authenticated, anon;

-- Ensure columns are explicitly available too (belt and suspenders)
GRANT SELECT (average_rating, total_reviews) ON public.shops TO authenticated, anon;
GRANT SELECT (rating, total_reviews) ON public.products TO authenticated, anon;

-- 4. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
