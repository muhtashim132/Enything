-- ============================================================
-- Migration: fix_shop_rating_trigger + delivery_lat_lng_columns
-- Fixes Bug #17: add delivery_lat / delivery_lng to orders
-- Fixes Bug #18: update_shop_rating trigger — shop_id lookup
-- ============================================================

-- ── Bug #17: delivery coordinates ───────────────────────────────────────────
-- Add nullable float columns so checkout_page.dart can persist the
-- customer's GPS coordinates and track_order_page.dart can centre the map.
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS delivery_lat  DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS delivery_lng  DOUBLE PRECISION;

-- ── Bug #18: shop average rating trigger ─────────────────────────────────────
-- Problem: the old trigger checked NEW.shop_id IS NOT NULL, but customer
-- ratings store shop_id directly while ratee_id is NULL. The trigger
-- condition was correct, BUT the AVG query joined on ratee_id (the seller
-- user-id), not on shop_id. Since shop_id was always set for customer→seller
-- ratings, the join produced no rows and the update silently did nothing.
--
-- Fix: when shop_id IS NOT NULL, compute the average from ALL ratings rows
-- that reference that shop_id column directly (not through ratee_id).

-- Drop old trigger + function (CASCADE removes the dependent trigger automatically)
DROP TRIGGER IF EXISTS trg_update_shop_rating ON ratings;
DROP TRIGGER IF EXISTS trigger_update_shop_rating ON ratings;
DROP FUNCTION IF EXISTS update_shop_rating() CASCADE;

CREATE OR REPLACE FUNCTION update_shop_rating()
RETURNS TRIGGER AS $$
DECLARE
  v_shop_id  UUID;
  v_avg      NUMERIC;
BEGIN
  -- Determine which shop to update -----------------------------------------
  IF NEW.shop_id IS NOT NULL THEN
    -- Customer→seller rating: shop_id is stored directly on the ratings row
    v_shop_id := NEW.shop_id;
  ELSIF NEW.ratee_role = 'seller' AND NEW.ratee_id IS NOT NULL THEN
    -- Seller-rated-by-delivery path (ratee_id = seller user_id)
    SELECT id INTO v_shop_id
      FROM shops
     WHERE seller_id = NEW.ratee_id
     LIMIT 1;
  ELSE
    -- Delivery partner rating — nothing to update for shops
    RETURN NEW;
  END IF;

  IF v_shop_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Recalculate average using ALL rows that reference this shop_id ----------
  SELECT ROUND(AVG(rating)::NUMERIC, 2)
    INTO v_avg
    FROM ratings
   WHERE shop_id = v_shop_id
     AND ratee_role = 'seller';

  UPDATE shops
     SET average_rating = COALESCE(v_avg, 0)
   WHERE id = v_shop_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Re-attach trigger
CREATE TRIGGER trg_update_shop_rating
AFTER INSERT ON ratings
FOR EACH ROW
EXECUTE FUNCTION update_shop_rating();
