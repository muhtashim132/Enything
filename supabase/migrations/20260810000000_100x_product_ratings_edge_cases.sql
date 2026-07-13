-- Migration: 20260810000000_100x_product_ratings_edge_cases.sql
-- Description: Conditionally drops and creates unique indexes to allow multiple product ratings per order, 
-- while maintaining the review bombing protections for shop/rider ratings.
-- Additive operation. No data deletion or modification.

-- 1. Drop the overly restrictive index introduced by the review bombing fix.
DROP INDEX IF EXISTS public.ratings_order_rater_role_idx;

-- 2. Restore the review bombing fix ONLY for non-product ratings (Shop and Rider)
-- This ensures that a customer can only rate a shop once, or a rider once, per order.
CREATE UNIQUE INDEX IF NOT EXISTS ratings_order_rater_role_idx 
  ON public.ratings (order_id, rater_role, ratee_role) 
  WHERE product_id IS NULL;

-- 3. Create a specialized index for product ratings.
-- This guarantees that a customer can rate multiple items in an order, 
-- but prevents them from review-bombing the exact SAME item within the exact SAME order.
CREATE UNIQUE INDEX IF NOT EXISTS ratings_order_rater_role_product_idx 
  ON public.ratings (order_id, rater_role, ratee_role, product_id) 
  WHERE product_id IS NOT NULL;
