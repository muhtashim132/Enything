-- =============================================================================
-- Phase 37: Absolute Core Ledger Items Fortress (Phase 5)
-- Description:
--   Injects safe, non-blocking length constraints into order_items, orders,
--   ratings, and shops to prevent authenticated pixel overloading from users
--   submitting massive strings in checkout payloads or reviews.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ORDER_ITEMS (Checkout payload exploits)
-- -----------------------------------------------------------------------------
ALTER TABLE public.order_items
  ADD CONSTRAINT chk_order_items_product_name_len CHECK (length(product_name) <= 255) NOT VALID,
  ADD CONSTRAINT chk_order_items_variant_name_len CHECK (length(variant_name) <= 255) NOT VALID,
  ADD CONSTRAINT chk_order_items_size_len CHECK (length(size) <= 255) NOT VALID,
  ADD CONSTRAINT chk_order_items_spec_inst_len CHECK (length(special_instructions) <= 1000) NOT VALID;

-- -----------------------------------------------------------------------------
-- 2. ORDERS (Prescription JSON Bomb)
-- -----------------------------------------------------------------------------
ALTER TABLE public.orders
  ADD CONSTRAINT chk_orders_prescription_urls_size CHECK (pg_column_size(prescription_urls) <= 51200) NOT VALID;

-- -----------------------------------------------------------------------------
-- 3. RATINGS (Review Bloat)
-- -----------------------------------------------------------------------------
ALTER TABLE public.ratings
  ADD CONSTRAINT chk_ratings_review_len CHECK (length(review) <= 1000) NOT VALID;

-- -----------------------------------------------------------------------------
-- 4. SHOPS (Missed Edge Case Meta Fields)
-- -----------------------------------------------------------------------------
ALTER TABLE public.shops
  ADD CONSTRAINT chk_shops_category_len CHECK (length(category) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_cuisine_type_len CHECK (length(cuisine_type) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_food_type_len CHECK (length(food_type) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_pharmacist_name_len CHECK (length(pharmacist_name) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_trade_license_len CHECK (length(trade_license) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_drug_license_len CHECK (length(drug_license_number) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_pincode_len CHECK (length(pincode) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_verification_status_len CHECK (length(verification_status) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_return_policy_len CHECK (length(return_policy) <= 255) NOT VALID,
  ADD CONSTRAINT chk_shops_opening_hours_len CHECK (length(opening_hours) <= 255) NOT VALID,
  ADD CONSTRAINT chk_shops_open_time_len CHECK (length(open_time) <= 50) NOT VALID,
  ADD CONSTRAINT chk_shops_close_time_len CHECK (length(close_time) <= 50) NOT VALID,
  ADD CONSTRAINT chk_shops_opening_time_len CHECK (length(opening_time) <= 50) NOT VALID,
  ADD CONSTRAINT chk_shops_closing_time_len CHECK (length(closing_time) <= 50) NOT VALID,
  ADD CONSTRAINT chk_shops_order_cutoff_len CHECK (length(order_cutoff) <= 50) NOT VALID;

-- =============================================================================
-- Validation
-- NOTE: We are NOT validating existing rows to prevent the migration from failing
-- if legacy dirty data exists. The NOT VALID flag ensures the constraint is enforced 
-- for all NEW inserts and updates, which completely neutralizes future attacks.
-- =============================================================================
