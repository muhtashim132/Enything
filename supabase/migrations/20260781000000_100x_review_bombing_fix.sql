-- =============================================================================
-- Migration: 100x Review Bombing Fix
-- Description:
--   Fixes two catastrophic logic failures in the ratings system:
--   1. Unverified Review Bombing: Authenticated users could post reviews 
--      without ever buying the product (by sending NULL order_id).
--   2. Infinite Review Bombing: A user could submit 10,000 reviews for a single
--      order_id, instantly dropping a shop's rating to 1 star.
-- =============================================================================

-- 1. Remove all unverified spam reviews (if any exist)
DELETE FROM public.reviews WHERE order_id IS NULL;

-- 2. Make order_id strictly required
ALTER TABLE public.reviews ALTER COLUMN order_id SET NOT NULL;

-- 3. Prevent infinite reviews per order (1 order = 1 review)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reviews_order_id_unique'
  ) THEN
    ALTER TABLE public.reviews ADD CONSTRAINT reviews_order_id_unique UNIQUE (order_id);
  END IF;
END $$;

-- 4. Create a function to verify order ownership and completion
CREATE OR REPLACE FUNCTION user_can_review_shop(p_user_id UUID, p_shop_id UUID, p_order_id UUID)
RETURNS boolean AS $$
BEGIN
  -- User must own the order, the order must be for the target shop, and it MUST be delivered.
  RETURN EXISTS (
    SELECT 1 FROM public.orders 
    WHERE id = p_order_id 
      AND customer_id = p_user_id 
      AND shop_id = p_shop_id 
      AND status = 'delivered'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Hardcode the RLS constraint to enforce verified purchases
DROP POLICY IF EXISTS "Users insert own reviews" ON public.reviews;

CREATE POLICY "Users insert own reviews"
  ON public.reviews FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid() AND 
    user_can_review_shop(auth.uid(), shop_id, order_id)
  );

-- Note: We also need to restrict UPDATEs in case a user tries to edit a review they shouldn't
DROP POLICY IF EXISTS "Users update own reviews" ON public.reviews;
CREATE POLICY "Users update own reviews"
  ON public.reviews FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
