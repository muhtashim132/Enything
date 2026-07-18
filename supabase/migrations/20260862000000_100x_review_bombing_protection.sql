-- =============================================================================
-- Migration: 100x Review Bombing & Status Protection
-- Description:
--   1. Enforces that reviews can ONLY be submitted for 'delivered' orders.
--   2. Enforces that a user can only review an order once.
--   3. Enforces rating is between 1 and 5.
-- =============================================================================

CREATE OR REPLACE FUNCTION validate_review_insertion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_status text;
BEGIN
  -- 1. Ensure rating bounds
  IF NEW.rating < 1 OR NEW.rating > 5 THEN
    RAISE EXCEPTION 'Rating must be between 1 and 5';
  END IF;

  -- 2. Fetch the order status
  SELECT status INTO v_status FROM orders WHERE id = NEW.order_id;
  
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  
  IF v_status != 'delivered' THEN
    RAISE EXCEPTION 'Reviews can only be submitted for delivered orders (Current status: %)', v_status;
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_review ON reviews;
CREATE TRIGGER trg_validate_review
  BEFORE INSERT OR UPDATE ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION validate_review_insertion();

-- Add a unique constraint to prevent duplicate reviews on the same order by the same user
ALTER TABLE reviews DROP CONSTRAINT IF EXISTS reviews_order_user_key;
ALTER TABLE reviews ADD CONSTRAINT reviews_order_user_key UNIQUE (order_id, user_id);
