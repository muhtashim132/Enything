-- =============================================================================
-- Migration: 20290000000090_100x_flawless_ratings_and_reviews_fortress.sql
-- Description:
--   1. Fortifies user_can_rate_order() to support all persona aliases
--      ('customer', 'seller', 'shop', 'rider', 'delivery', 'delivery_partner')
--      and allows admin bypass.
--   2. Fixes IDOR authorization in set_customer_rated, set_seller_rated, and
--      set_delivery_rated so that sellers and delivery partners can flag orders.
--   3. Upgrades update_entity_ratings_consolidated() trigger to handle both OLD
--      and NEW IDs across INSERT, UPDATE, and DELETE, recalculating shop,
--      product, and profile (rider/customer) ratings accurately.
--   4. Configures clean RLS policies and grants on public.ratings for public
--      viewing and admin moderation.
-- =============================================================================

-- ── 1. Fortify user_can_rate_order ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.user_can_rate_order(
  p_user_id UUID,
  p_order_id UUID,
  p_role TEXT
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL OR p_order_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Active or Super Admin bypass
  IF public.is_active_admin(p_user_id) OR public.is_super_admin(p_user_id) THEN
    RETURN TRUE;
  END IF;

  IF p_role = 'customer' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.orders 
      WHERE id = p_order_id 
        AND customer_id = p_user_id 
        AND status = 'delivered'
    );
  ELSIF p_role IN ('seller', 'shop') THEN
    RETURN EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.shops s ON o.shop_id = s.id
      WHERE o.id = p_order_id 
        AND s.seller_id = p_user_id 
        AND o.status = 'delivered'
    );
  ELSIF p_role IN ('rider', 'delivery', 'delivery_partner') THEN
    RETURN EXISTS (
      SELECT 1 FROM public.orders 
      WHERE id = p_order_id 
        AND delivery_partner_id = p_user_id 
        AND status = 'delivered'
    );
  END IF;

  RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.user_can_rate_order(UUID, UUID, TEXT) TO authenticated, service_role;


-- ── 2. Fix IDOR on set_customer_rated, set_seller_rated, set_delivery_rated ───
CREATE OR REPLACE FUNCTION public.set_customer_rated(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.orders 
    WHERE id = p_order_id 
      AND (customer_id = auth.uid() OR public.is_active_admin(auth.uid()))
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer or admin can mark customer rating';
  END IF;

  UPDATE public.orders SET has_customer_rated = TRUE, updated_at = NOW() WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_customer_rated(UUID) TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.set_delivery_rated(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.orders 
    WHERE id = p_order_id 
      AND (delivery_partner_id = auth.uid() OR customer_id = auth.uid() OR public.is_active_admin(auth.uid()))
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Only the assigned delivery partner or admin can mark delivery rating';
  END IF;

  UPDATE public.orders SET has_delivery_rated = TRUE, updated_at = NOW() WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_delivery_rated(UUID) TO authenticated, service_role;


CREATE OR REPLACE FUNCTION public.set_seller_rated(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.orders o
    LEFT JOIN public.shops s ON o.shop_id = s.id
    WHERE o.id = p_order_id 
      AND (s.seller_id = auth.uid() OR o.customer_id = auth.uid() OR public.is_active_admin(auth.uid()))
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Only the shop seller or admin can mark seller rating';
  END IF;

  UPDATE public.orders SET has_seller_rated = TRUE, updated_at = NOW() WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_seller_rated(UUID) TO authenticated, service_role;


-- ── 3. Upgrade update_entity_ratings_consolidated Trigger ──────────────────────
CREATE OR REPLACE FUNCTION public.update_entity_ratings_consolidated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_target_shop_ids UUID[] := ARRAY[]::UUID[];
  v_target_product_ids UUID[] := ARRAY[]::UUID[];
  v_target_profile_ids UUID[] := ARRAY[]::UUID[];
  v_shop_id UUID;
  v_product_id UUID;
  v_profile_id UUID;
  v_avg NUMERIC(3,2);
  v_count INTEGER;
BEGIN
  -- Collect all affected entities (both OLD and NEW to handle UPDATE/DELETE perfectly)
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    IF OLD.shop_id IS NOT NULL THEN
      v_target_shop_ids := array_append(v_target_shop_ids, OLD.shop_id);
    ELSIF OLD.ratee_role IN ('seller', 'shop') AND OLD.ratee_id IS NOT NULL THEN
      SELECT id INTO v_shop_id FROM public.shops WHERE seller_id = OLD.ratee_id LIMIT 1;
      IF v_shop_id IS NOT NULL THEN
        v_target_shop_ids := array_append(v_target_shop_ids, v_shop_id);
      END IF;
    END IF;

    IF OLD.product_id IS NOT NULL THEN
      v_target_product_ids := array_append(v_target_product_ids, OLD.product_id);
    END IF;

    IF OLD.ratee_id IS NOT NULL AND OLD.ratee_role IN ('delivery', 'delivery_partner', 'rider', 'customer') THEN
      v_target_profile_ids := array_append(v_target_profile_ids, OLD.ratee_id);
    END IF;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    IF NEW.shop_id IS NOT NULL THEN
      v_target_shop_ids := array_append(v_target_shop_ids, NEW.shop_id);
    ELSIF NEW.ratee_role IN ('seller', 'shop') AND NEW.ratee_id IS NOT NULL THEN
      SELECT id INTO v_shop_id FROM public.shops WHERE seller_id = NEW.ratee_id LIMIT 1;
      IF v_shop_id IS NOT NULL THEN
        v_target_shop_ids := array_append(v_target_shop_ids, v_shop_id);
      END IF;
    END IF;

    IF NEW.product_id IS NOT NULL THEN
      v_target_product_ids := array_append(v_target_product_ids, NEW.product_id);
    END IF;

    IF NEW.ratee_id IS NOT NULL AND NEW.ratee_role IN ('delivery', 'delivery_partner', 'rider', 'customer') THEN
      v_target_profile_ids := array_append(v_target_profile_ids, NEW.ratee_id);
    END IF;
  END IF;

  -- 1. Recalculate Shop Ratings
  FOREACH v_shop_id IN ARRAY (SELECT ARRAY(SELECT DISTINCT unnest(v_target_shop_ids))) LOOP
    IF v_shop_id IS NOT NULL THEN
      SELECT ROUND(AVG(rating)::numeric, 2), COUNT(*)
      INTO v_avg, v_count
      FROM public.ratings
      WHERE (shop_id = v_shop_id OR ratee_id = (SELECT seller_id FROM public.shops WHERE id = v_shop_id))
        AND ratee_role IN ('seller', 'shop');

      UPDATE public.shops
      SET average_rating = COALESCE(v_avg, 0.0),
          total_reviews  = COALESCE(v_count, 0)
      WHERE id = v_shop_id;
    END IF;
  END LOOP;

  -- 2. Recalculate Product Ratings
  FOREACH v_product_id IN ARRAY (SELECT ARRAY(SELECT DISTINCT unnest(v_target_product_ids))) LOOP
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
  END LOOP;

  -- 3. Recalculate Profile Ratings (Rider or Customer)
  FOREACH v_profile_id IN ARRAY (SELECT ARRAY(SELECT DISTINCT unnest(v_target_profile_ids))) LOOP
    IF v_profile_id IS NOT NULL THEN
      SELECT ROUND(AVG(rating)::numeric, 2), COUNT(*)
      INTO v_avg, v_count
      FROM public.ratings
      WHERE ratee_id = v_profile_id
        AND ratee_role IN ('delivery', 'delivery_partner', 'rider', 'customer');

      UPDATE public.profiles
      SET average_rating = COALESCE(v_avg, 0.0),
          total_reviews = COALESCE(v_count, 0)
      WHERE id = v_profile_id;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_100x_update_entity_ratings ON public.ratings;
CREATE TRIGGER trg_100x_update_entity_ratings
  AFTER INSERT OR UPDATE OR DELETE ON public.ratings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_entity_ratings_consolidated();


-- ── 4. Grants & RLS Policies on public.ratings ────────────────────────────────
ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.ratings TO authenticated;
GRANT ALL ON public.ratings TO service_role;
GRANT SELECT ON public.ratings TO anon;

DROP POLICY IF EXISTS "ratings_select_all" ON public.ratings;
CREATE POLICY "ratings_select_all"
  ON public.ratings FOR SELECT
  TO anon, authenticated
  USING (TRUE);

DROP POLICY IF EXISTS "ratings_insert_own" ON public.ratings;
CREATE POLICY "ratings_insert_own"
  ON public.ratings FOR INSERT
  TO authenticated
  WITH CHECK (
    rater_id = auth.uid() AND 
    public.user_can_rate_order(auth.uid(), order_id, rater_role)
  );

DROP POLICY IF EXISTS "ratings_admin_all" ON public.ratings;
CREATE POLICY "ratings_admin_all"
  ON public.ratings FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));

-- ── 5. Reload Schema Cache ───────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
