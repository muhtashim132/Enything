-- ============================================================================
-- Migration: 20260810000001_100x_product_reviews_count_fix.sql
-- Description: Adds missing total_reviews column to products and updates 
-- the trigger to aggregate and sync both rating and count for products.
-- Additive operation. No data deletion or modification.
-- ============================================================================

-- 1. Safely add the missing total_reviews column to products table
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS total_reviews INTEGER NOT NULL DEFAULT 0;

-- 2. Update the universal entity rating trigger to calculate counts for products
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

  RETURN NULL;
END;
$$;
