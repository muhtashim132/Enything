-- =============================================================================
-- Phase 35: Absolute Financial Constants & Auth Storage Fortress (Phase 3)
-- Description:
--   Injects safe, non-blocking mathematical and length constraints into coupons,
--   phone_otps, otp_tokens, and device_tokens to prevent unauthenticated pixel
--   overloading and mathematical coupon exploits.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. COUPONS (Mathematical and String Exploits)
-- -----------------------------------------------------------------------------
ALTER TABLE public.coupons
  -- Mathematical Bounds
  ADD CONSTRAINT chk_coupons_discount_value_positive CHECK (discount_value > 0) NOT VALID,
  ADD CONSTRAINT chk_coupons_max_discount_positive CHECK (max_discount_cap >= 0) NOT VALID,
  ADD CONSTRAINT chk_coupons_min_order_positive CHECK (min_order_amount >= 0) NOT VALID,
  ADD CONSTRAINT chk_coupons_usage_limit_positive CHECK (usage_limit > 0) NOT VALID,
  
  -- String Bounds
  ADD CONSTRAINT chk_coupons_code_len CHECK (length(code) <= 50) NOT VALID,
  ADD CONSTRAINT chk_coupons_description_len CHECK (length(description) <= 500) NOT VALID;

-- -----------------------------------------------------------------------------
-- 2. PHONE_OTPS (Unauthenticated Pixel Overloading)
-- -----------------------------------------------------------------------------
ALTER TABLE public.phone_otps
  ADD CONSTRAINT chk_phone_otps_phone_len CHECK (length(phone) <= 20) NOT VALID,
  ADD CONSTRAINT chk_phone_otps_otp_len CHECK (length(otp) <= 10) NOT VALID;

-- -----------------------------------------------------------------------------
-- 3. OTP_TOKENS (Unauthenticated Pixel Overloading)
-- -----------------------------------------------------------------------------
ALTER TABLE public.otp_tokens
  ADD CONSTRAINT chk_otp_tokens_phone_len CHECK (length(phone) <= 20) NOT VALID,
  ADD CONSTRAINT chk_otp_tokens_otp_hash_len CHECK (length(otp_hash) <= 255) NOT VALID;

-- -----------------------------------------------------------------------------
-- 4. DEVICE_TOKENS (Push Notification OOM Crash Prevention)
-- -----------------------------------------------------------------------------
ALTER TABLE public.device_tokens
  ADD CONSTRAINT chk_device_tokens_token_len CHECK (length(token) <= 1000) NOT VALID,
  ADD CONSTRAINT chk_device_tokens_device_id_len CHECK (length(device_id) <= 255) NOT VALID;

-- =============================================================================
-- Validation
-- NOTE: We are NOT validating existing rows to prevent the migration from failing
-- if legacy dirty data exists. The NOT VALID flag ensures the constraint is enforced 
-- for all NEW inserts and updates, which completely neutralizes future attacks.
-- =============================================================================
