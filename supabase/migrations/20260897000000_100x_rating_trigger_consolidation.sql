-- Migration 20260897000000_100x_rating_trigger_consolidation.sql

-- 100x STRESS TEST FIX: Prevent Trigger Cascade Loop & Double-Evaluation Deadlocks
-- Currently, 3 separate triggers fire on ratings INSERT/UPDATE, evaluating the same rows and updating the same tables, causing lock contention and duplicated table scans.

DROP TRIGGER IF EXISTS trigger_update_user_rating ON public.ratings;
DROP TRIGGER IF EXISTS trg_update_shop_rating ON public.ratings;
DROP TRIGGER IF EXISTS tr_update_entity_rating ON public.ratings;

DROP FUNCTION IF EXISTS update_entity_rating_on_change();
DROP FUNCTION IF EXISTS update_shop_rating();
DROP FUNCTION IF EXISTS update_shop_rating_on_new_rating();
DROP FUNCTION IF EXISTS update_user_rating();

CREATE OR REPLACE FUNCTION public.update_entity_ratings_consolidated()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ratee_role text;
  v_shop_id uuid;
  v_product_id uuid;
  v_ratee_id uuid;
  v_avg numeric(3,2);
  v_count integer;
BEGIN
  -- Determine context (Handle INSERT, UPDATE, DELETE)
  IF TG_OP = 'DELETE' THEN
    v_ratee_role := OLD.ratee_role;
    v_shop_id    := OLD.shop_id;
    v_product_id := OLD.product_id;
    v_ratee_id   := OLD.ratee_id;
  ELSE
    v_ratee_role := NEW.ratee_role;
    v_shop_id    := NEW.shop_id;
    v_product_id := NEW.product_id;
    v_ratee_id   := NEW.ratee_id;
  END IF;

  -- 1. Resolve shop_id for delivery -> seller ratings
  IF v_shop_id IS NULL AND v_ratee_role = 'seller' AND v_ratee_id IS NOT NULL THEN
    SELECT id INTO v_shop_id FROM shops WHERE seller_id = v_ratee_id LIMIT 1;
  END IF;

  -- 2. Update Shop Rating
  IF v_shop_id IS NOT NULL AND v_ratee_role = 'seller' THEN
    SELECT ROUND(AVG(rating)::numeric, 2), COUNT(*)
    INTO v_avg, v_count
    FROM public.ratings
    WHERE (shop_id = v_shop_id OR (ratee_id = (SELECT seller_id FROM shops WHERE id = v_shop_id)))
      AND ratee_role = 'seller';

    UPDATE public.shops
    SET average_rating = COALESCE(v_avg, 0.0),
        total_reviews  = COALESCE(v_count, 0)
    WHERE id = v_shop_id;
  END IF;

  -- 3. Update Product Rating
  IF v_product_id IS NOT NULL THEN
    SELECT ROUND(AVG(rating)::numeric, 2), COUNT(*)
    INTO v_avg, v_count
    FROM public.ratings
    WHERE product_id = v_product_id;

    UPDATE public.products
    SET rating = COALESCE(v_avg, 0.0),
        total_reviews = COALESCE(v_count, 0)
    WHERE id = v_product_id;
  END IF;

  -- 4. Update Profile Rating (Rider or Customer)
  IF v_ratee_id IS NOT NULL AND v_ratee_role IN ('delivery_partner', 'customer') THEN
    SELECT ROUND(AVG(rating)::numeric, 2), COUNT(*)
    INTO v_avg, v_count
    FROM public.ratings
    WHERE ratee_id = v_ratee_id;

    UPDATE public.profiles
    SET average_rating = COALESCE(v_avg, 0.0),
        total_reviews = COALESCE(v_count, 0)
    WHERE id = v_ratee_id;
  END IF;

  RETURN NULL; -- AFTER trigger
END;
$function$;

CREATE TRIGGER trg_100x_update_entity_ratings
 AFTER INSERT OR UPDATE OR DELETE ON public.ratings
 FOR EACH ROW
 EXECUTE FUNCTION update_entity_ratings_consolidated();
