-- =============================================================================
-- Phase 33: Absolute Storage Integrity Fortress (Anti-Pixel Overloading)
-- Description:
--   Injects safe, non-blocking length constraints into every user-exposed
--   text and JSONB field across shops, products, profiles, reviews, and 
--   saved_addresses to prevent massive payload insertion attacks.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. SHOPS
-- -----------------------------------------------------------------------------
ALTER TABLE public.shops
  ADD CONSTRAINT chk_shops_name_len CHECK (length(name) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_desc_len CHECK (length(description) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_shops_image_len CHECK (length(image_url) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_shops_banner_img_len CHECK (length(banner_image) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_shops_banner_url_len CHECK (length(banner_url) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_shops_address_len CHECK (length(address) <= 255) NOT VALID,
  ADD CONSTRAINT chk_shops_landmark_len CHECK (length(landmark) <= 255) NOT VALID,
  ADD CONSTRAINT chk_shops_house_num_len CHECK (length(house_number) <= 255) NOT VALID,
  ADD CONSTRAINT chk_shops_gst_len CHECK (length(gst_number) <= 50) NOT VALID,
  ADD CONSTRAINT chk_shops_fssai_len CHECK (length(fssai_number) <= 50) NOT VALID,
  ADD CONSTRAINT chk_shops_aadhar_len CHECK (length(aadhar_number) <= 50) NOT VALID,
  ADD CONSTRAINT chk_shops_pan_len CHECK (length(pan_number) <= 50) NOT VALID,
  ADD CONSTRAINT chk_shops_bank_acc_len CHECK (length(bank_account_number) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_bank_ifsc_len CHECK (length(bank_ifsc) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_bank_holder_len CHECK (length(bank_account_holder) <= 100) NOT VALID,
  ADD CONSTRAINT chk_shops_categories_json_size CHECK (pg_column_size(categories) <= 102400) NOT VALID,
  ADD CONSTRAINT chk_shops_kyc_json_size CHECK (pg_column_size(kyc_documents) <= 102400) NOT VALID,
  ADD CONSTRAINT chk_shops_metadata_json_size CHECK (pg_column_size(metadata) <= 102400) NOT VALID;

-- -----------------------------------------------------------------------------
-- 2. PRODUCTS
-- -----------------------------------------------------------------------------
ALTER TABLE public.products
  ADD CONSTRAINT chk_products_name_len CHECK (length(name) <= 255) NOT VALID,
  ADD CONSTRAINT chk_products_brand_len CHECK (length(brand) <= 255) NOT VALID,
  ADD CONSTRAINT chk_products_desc_len CHECK (length(description) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_products_image_len CHECK (length(image_url) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_products_cat_len CHECK (length(category) <= 100) NOT VALID,
  ADD CONSTRAINT chk_products_subcat_len CHECK (length(sub_category) <= 100) NOT VALID,
  ADD CONSTRAINT chk_products_menucat_len CHECK (length(menu_category) <= 100) NOT VALID,
  ADD CONSTRAINT chk_products_images_json_size CHECK (pg_column_size(images) <= 51200) NOT VALID,
  ADD CONSTRAINT chk_products_tags_json_size CHECK (pg_column_size(special_tags) <= 51200) NOT VALID,
  ADD CONSTRAINT chk_products_variants_json_size CHECK (pg_column_size(variants) <= 51200) NOT VALID;

-- -----------------------------------------------------------------------------
-- 3. PROFILES
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD CONSTRAINT chk_profiles_full_name_len CHECK (length(full_name) <= 100) NOT VALID,
  ADD CONSTRAINT chk_profiles_name_len CHECK (length(name) <= 100) NOT VALID,
  ADD CONSTRAINT chk_profiles_phone_len CHECK (length(phone) <= 20) NOT VALID,
  ADD CONSTRAINT chk_profiles_avatar_len CHECK (length(avatar_url) <= 1000) NOT VALID;

-- -----------------------------------------------------------------------------
-- 4. REVIEWS
-- -----------------------------------------------------------------------------
ALTER TABLE public.reviews
  ADD CONSTRAINT chk_reviews_comment_len CHECK (length(comment) <= 1000) NOT VALID;

-- -----------------------------------------------------------------------------
-- 5. SAVED_ADDRESSES
-- -----------------------------------------------------------------------------
ALTER TABLE public.saved_addresses
  ADD CONSTRAINT chk_saved_add_label_len CHECK (length(label) <= 100) NOT VALID,
  ADD CONSTRAINT chk_saved_add_custom_label_len CHECK (length(custom_label) <= 100) NOT VALID,
  ADD CONSTRAINT chk_saved_add_flat_len CHECK (length(flat_number) <= 100) NOT VALID,
  ADD CONSTRAINT chk_saved_add_address_len CHECK (length(address) <= 255) NOT VALID,
  ADD CONSTRAINT chk_saved_add_landmark_len CHECK (length(landmark) <= 255) NOT VALID,
  ADD CONSTRAINT chk_saved_add_pincode_len CHECK (length(pincode) <= 20) NOT VALID;

-- =============================================================================
-- Validation
-- NOTE: We are NOT validating existing rows to prevent the migration from failing
-- if legacy dirty data exists. The NOT VALID flag ensures the constraint is enforced 
-- for all NEW inserts and updates, which completely neutralizes future attacks.
-- To validate existing rows in the future (after manual cleanup), one can run:
-- ALTER TABLE public.shops VALIDATE CONSTRAINT chk_shops_name_len;
-- =============================================================================
