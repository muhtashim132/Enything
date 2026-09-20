-- ============================================================================
-- Migration: 100x_referral_fortress
-- Description: Surgically fixes all referral system edge cases without
--              touching any other backend logic.
--
-- Fixes:
--   1. Referral coupons now have min_order_amount, expiry, and usage_limit
--   2. Coupon discount_value uses platform_config referral_bonus_amount
--   3. Self-referral blocked at DB level (CHECK constraint)
--   4. used_count on referral_codes incremented via trigger
--   5. Referred user ALSO receives a coupon (UI promises "You Both Earn")
--   6. Existing used_count backfilled from actual referrals data
--
-- Edge Cases Covered:
--   * Coupon code collision (retry loop with clock_timestamp entropy)
--   * NULL bonus_amount fallback to 25
--   * Self-referral via modified client (DB constraint)
--   * Triple-role stacking (unchanged - acceptable risk, but idempotent
--     bonus_paid flag prevents double-pay per referral row)
--   * Sybil attack mitigation (usage_limit=1 per coupon)
--   * No expiry -> now 90-day expiry
--   * No min_order -> now 199 minimum
--   * NULL delivery_partner_id guard on rider check
--
-- Tables touched: referrals (CHECK), referral_codes (trigger + backfill),
--                 coupons (via referral trigger INSERT only)
-- Functions: process_referral_on_first_order (CREATE OR REPLACE)
-- ============================================================================

-- =====================================================================
-- 1. SELF-REFERRAL PROTECTION: DB-level CHECK constraint
-- =====================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'chk_referrals_no_self_refer'
      AND table_name = 'referrals'
  ) THEN
    ALTER TABLE public.referrals
      ADD CONSTRAINT chk_referrals_no_self_refer
      CHECK (referrer_id != referred_id) NOT VALID;
  END IF;
END $$;

-- =====================================================================
-- 2. AUTO-INCREMENT used_count ON referral_codes when referral is created
-- =====================================================================
CREATE OR REPLACE FUNCTION public.increment_referral_used_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.referral_codes
    SET used_count = used_count + 1
  WHERE code = NEW.referral_code;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_increment_referral_used_count ON public.referrals;
CREATE TRIGGER trg_increment_referral_used_count
  AFTER INSERT ON public.referrals
  FOR EACH ROW
  EXECUTE FUNCTION public.increment_referral_used_count();

-- =====================================================================
-- 3. BACKFILL used_count from existing referrals data
-- =====================================================================
UPDATE public.referral_codes rc
SET used_count = COALESCE(sub.cnt, 0)
FROM (
  SELECT referral_code, COUNT(*) AS cnt
  FROM public.referrals
  GROUP BY referral_code
) sub
WHERE rc.code = sub.referral_code
  AND rc.used_count != sub.cnt;

-- =====================================================================
-- 4. FIXED process_referral_on_first_order trigger function
-- =====================================================================
CREATE OR REPLACE FUNCTION public.process_referral_on_first_order()
RETURNS TRIGGER AS $$
DECLARE
  v_referral_record RECORD;
  v_referrer_id UUID;
  v_bonus_amount NUMERIC;
  v_coupon_code TEXT;
  v_coupon_inserted BOOLEAN;
  v_attempts INTEGER;
  v_coupon_prefix TEXT;
  v_referred_coupon_code TEXT;
  v_referred_coupon_inserted BOOLEAN;
  v_seller_id UUID;
BEGIN
  -- We only care when an order status transitions to a completed state
  IF NEW.status NOT IN ('delivered', 'completed') THEN
    RETURN NEW;
  END IF;
  IF OLD.status IS NOT NULL AND OLD.status IN ('delivered', 'completed') THEN
    RETURN NEW;
  END IF;

  -- Fetch configurable bonus amount (default 25)
  SELECT value::numeric INTO v_bonus_amount
    FROM public.platform_config
   WHERE key = 'referral_bonus_amount';
  IF v_bonus_amount IS NULL OR v_bonus_amount <= 0 THEN
    v_bonus_amount := 25.0;
  END IF;

  -- Dynamic coupon code prefix based on bonus amount
  v_coupon_prefix := 'REF' || v_bonus_amount::int::text || '-';

  -- -----------------------------------------------------------------
  -- 1. CUSTOMER first completed order
  -- -----------------------------------------------------------------
  IF (SELECT count(*) FROM public.orders
      WHERE customer_id = NEW.customer_id
        AND status IN ('delivered', 'completed')) = 1 THEN

    SELECT * INTO v_referral_record
      FROM public.referrals
     WHERE referred_id = NEW.customer_id
       AND bonus_paid = false;

    IF FOUND THEN
      UPDATE public.referrals SET bonus_paid = true WHERE id = v_referral_record.id;
      v_referrer_id := v_referral_record.referrer_id;

      -- Generate coupon for REFERRER (with safety constraints)
      v_coupon_inserted := false;
      v_attempts := 0;
      WHILE NOT v_coupon_inserted AND v_attempts < 10 LOOP
        v_coupon_code := v_coupon_prefix || upper(substr(
          md5(random()::text || clock_timestamp()::text || v_attempts::text), 1, 6));
        IF NOT EXISTS (SELECT 1 FROM public.coupons WHERE code = v_coupon_code) THEN
          INSERT INTO public.coupons (
            code, discount_type, discount_value, is_active,
            valid_from, valid_until, min_order_amount, usage_limit, usage_count
          ) VALUES (
            v_coupon_code,
            'flat',
            v_bonus_amount,
            true,
            now(),
            now() + interval '90 days',
            199,
            1,
            0
          );
          v_coupon_inserted := true;
        END IF;
        v_attempts := v_attempts + 1;
      END LOOP;

      -- Notify referrer
      IF v_coupon_inserted THEN
        INSERT INTO public.notifications (user_id, title, body, notif_key)
        VALUES (
          v_referrer_id,
          'Referral Bonus!',
          'Your referred friend completed their first order! You got a ' || v_bonus_amount::int || ' rs coupon: ' || v_coupon_code || ' (valid 90 days, min order 199)',
          'ref_bonus_' || v_referral_record.id
        );
      END IF;

      -- Generate coupon for REFERRED USER ("You Both Earn")
      v_referred_coupon_inserted := false;
      v_attempts := 0;
      WHILE NOT v_referred_coupon_inserted AND v_attempts < 10 LOOP
        v_referred_coupon_code := v_coupon_prefix || 'W-' || upper(substr(
          md5(random()::text || clock_timestamp()::text || 'ref' || v_attempts::text), 1, 5));
        IF NOT EXISTS (SELECT 1 FROM public.coupons WHERE code = v_referred_coupon_code) THEN
          INSERT INTO public.coupons (
            code, discount_type, discount_value, is_active,
            valid_from, valid_until, min_order_amount, usage_limit, usage_count
          ) VALUES (
            v_referred_coupon_code,
            'flat',
            v_bonus_amount,
            true,
            now(),
            now() + interval '90 days',
            199,
            1,
            0
          );
          v_referred_coupon_inserted := true;
        END IF;
        v_attempts := v_attempts + 1;
      END LOOP;

      IF v_referred_coupon_inserted THEN
        INSERT INTO public.notifications (user_id, title, body, notif_key)
        VALUES (
          NEW.customer_id,
          'Welcome Reward!',
          'Thanks for joining via referral! Here is your ' || v_bonus_amount::int || ' rs coupon: ' || v_referred_coupon_code || ' (valid 90 days, min order 199)',
          'ref_welcome_' || v_referral_record.id
        );
      END IF;

    END IF;
  END IF;

  -- -----------------------------------------------------------------
  -- 2. SELLER first completed order (for the shop)
  -- -----------------------------------------------------------------
  IF (SELECT count(*) FROM public.orders
      WHERE shop_id = NEW.shop_id
        AND status IN ('delivered', 'completed')) = 1 THEN

    BEGIN
      SELECT s.seller_id INTO v_seller_id FROM public.shops s WHERE s.id = NEW.shop_id;

      IF v_seller_id IS NOT NULL THEN
        SELECT * INTO v_referral_record
          FROM public.referrals
         WHERE referred_id = v_seller_id
           AND bonus_paid = false;

        IF FOUND THEN
          UPDATE public.referrals SET bonus_paid = true WHERE id = v_referral_record.id;
          v_referrer_id := v_referral_record.referrer_id;

          -- Referrer coupon
          v_coupon_inserted := false;
          v_attempts := 0;
          WHILE NOT v_coupon_inserted AND v_attempts < 10 LOOP
            v_coupon_code := v_coupon_prefix || upper(substr(
              md5(random()::text || clock_timestamp()::text || v_attempts::text), 1, 6));
            IF NOT EXISTS (SELECT 1 FROM public.coupons WHERE code = v_coupon_code) THEN
              INSERT INTO public.coupons (
                code, discount_type, discount_value, is_active,
                valid_from, valid_until, min_order_amount, usage_limit, usage_count
              ) VALUES (
                v_coupon_code, 'flat', v_bonus_amount, true,
                now(), now() + interval '90 days', 199, 1, 0
              );
              v_coupon_inserted := true;
            END IF;
            v_attempts := v_attempts + 1;
          END LOOP;

          IF v_coupon_inserted THEN
            INSERT INTO public.notifications (user_id, title, body, notif_key)
            VALUES (
              v_referrer_id,
              'Referral Bonus!',
              'Your referred seller completed their first order! You got a ' || v_bonus_amount::int || ' rs coupon: ' || v_coupon_code || ' (valid 90 days, min order 199)',
              'ref_bonus_' || v_referral_record.id
            );
          END IF;
        END IF;
      END IF;
    END;
  END IF;

  -- -----------------------------------------------------------------
  -- 3. RIDER first completed order
  -- -----------------------------------------------------------------
  IF NEW.delivery_partner_id IS NOT NULL AND
     (SELECT count(*) FROM public.orders
       WHERE delivery_partner_id = NEW.delivery_partner_id
         AND status IN ('delivered', 'completed')) = 1 THEN

    SELECT * INTO v_referral_record
      FROM public.referrals
     WHERE referred_id = NEW.delivery_partner_id
       AND bonus_paid = false;

    IF FOUND THEN
      UPDATE public.referrals SET bonus_paid = true WHERE id = v_referral_record.id;
      v_referrer_id := v_referral_record.referrer_id;

      v_coupon_inserted := false;
      v_attempts := 0;
      WHILE NOT v_coupon_inserted AND v_attempts < 10 LOOP
        v_coupon_code := v_coupon_prefix || upper(substr(
          md5(random()::text || clock_timestamp()::text || v_attempts::text), 1, 6));
        IF NOT EXISTS (SELECT 1 FROM public.coupons WHERE code = v_coupon_code) THEN
          INSERT INTO public.coupons (
            code, discount_type, discount_value, is_active,
            valid_from, valid_until, min_order_amount, usage_limit, usage_count
          ) VALUES (
            v_coupon_code, 'flat', v_bonus_amount, true,
            now(), now() + interval '90 days', 199, 1, 0
          );
          v_coupon_inserted := true;
        END IF;
        v_attempts := v_attempts + 1;
      END LOOP;

      IF v_coupon_inserted THEN
        INSERT INTO public.notifications (user_id, title, body, notif_key)
        VALUES (
          v_referrer_id,
          'Referral Bonus!',
          'Your referred rider completed their first order! You got a ' || v_bonus_amount::int || ' rs coupon: ' || v_coupon_code || ' (valid 90 days, min order 199)',
          'ref_bonus_' || v_referral_record.id
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure the trigger exists (idempotent)
DROP TRIGGER IF EXISTS trg_process_referral_on_first_order ON public.orders;
CREATE TRIGGER trg_process_referral_on_first_order
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.process_referral_on_first_order();

-- Schema reload
NOTIFY pgrst, 'reload schema';
