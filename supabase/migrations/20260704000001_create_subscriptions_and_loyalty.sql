-- ============================================================================
-- Migration: create_subscriptions_and_loyalty.sql
-- Description: Enything Pass subscription plans + loyalty points engine.
--
-- Tables created:
--   • subscription_plans   — admin-managed plan catalog (Lite/Pro/Ultra)
--   • subscriptions        — per-user active subscription
--   • loyalty_points       — running balance per user
--   • loyalty_transactions — every earn/redeem event (immutable ledger)
--
-- Business rules encoded:
--   • A user can have only one ACTIVE subscription at a time.
--   • Loyalty balance can never go negative (CHECK constraint).
--   • All monetary values in INR paise (integer) for precision — no floats.
-- ============================================================================

-- ===========================================================================
-- 1. SUBSCRIPTION PLANS TABLE (admin-managed catalog)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.subscription_plans (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  name            text          NOT NULL,                -- 'Lite' | 'Pro' | 'Ultra'
  price_inr       integer       NOT NULL,                -- monthly price in INR (e.g. 99)
  delivery_free_threshold integer NOT NULL DEFAULT 0,   -- min order value for free delivery (0 = always free)
  cashback_percent numeric(5,2) NOT NULL DEFAULT 0,     -- cashback % on each order
  max_accounts    integer       NOT NULL DEFAULT 1,      -- family sharing: max linked accounts
  is_active       boolean       NOT NULL DEFAULT true,
  badge_label     text,                                  -- e.g. 'PASS PRO'
  badge_color     text          DEFAULT '#1E3FD8',       -- hex color for badge
  created_at      timestamptz   NOT NULL DEFAULT now(),
  updated_at      timestamptz   NOT NULL DEFAULT now()
);

-- Seed the 3 Enything Pass tiers
INSERT INTO public.subscription_plans
  (name, price_inr, delivery_free_threshold, cashback_percent, max_accounts, badge_label, badge_color)
VALUES
  ('Lite',  49,  199, 0.00, 1, 'PASS LITE',  '#6B7280'),
  ('Pro',   99,    0, 5.00, 1, 'PASS PRO',   '#1E3FD8'),
  ('Ultra', 199,   0, 10.00, 3, 'PASS ULTRA', '#D4A017')
ON CONFLICT DO NOTHING;

-- ===========================================================================
-- 2. SUBSCRIPTIONS TABLE (per-user active subscription)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id         uuid          NOT NULL REFERENCES public.subscription_plans(id),
  status          text          NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active', 'expired', 'cancelled', 'trial')),
  started_at      timestamptz   NOT NULL DEFAULT now(),
  expires_at      timestamptz   NOT NULL,                -- when the current billing period ends
  cancelled_at    timestamptz,                           -- NULL = not cancelled
  razorpay_sub_id text,                                  -- Razorpay subscription ID for recurring billing
  payment_method  text          DEFAULT 'manual',        -- 'razorpay' | 'manual' (admin override)
  created_at      timestamptz   NOT NULL DEFAULT now()
);

-- Only one ACTIVE subscription per user at a time
CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_active_user_unique
  ON public.subscriptions (user_id)
  WHERE status = 'active';

-- ===========================================================================
-- 3. LOYALTY POINTS TABLE (running balance per user)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.loyalty_points (
  user_id         uuid          PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  balance         integer       NOT NULL DEFAULT 0 CHECK (balance >= 0),  -- current point balance
  lifetime_earned integer       NOT NULL DEFAULT 0,                       -- total ever earned
  lifetime_redeemed integer     NOT NULL DEFAULT 0,                       -- total ever redeemed
  updated_at      timestamptz   NOT NULL DEFAULT now()
);

-- ===========================================================================
-- 4. LOYALTY TRANSACTIONS TABLE (immutable event ledger)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.loyalty_transactions (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id        uuid          REFERENCES public.orders(id) ON DELETE SET NULL,
  type            text          NOT NULL
                                CHECK (type IN ('earn_order', 'earn_referral', 'earn_signup',
                                               'earn_review', 'redeem', 'expire', 'admin_adjust')),
  points          integer       NOT NULL,                -- positive = earn, negative = redeem/expire
  description     text          NOT NULL,                -- human-readable e.g. "Earned from Order #1234"
  balance_after   integer       NOT NULL,                -- snapshot of balance after this transaction
  created_at      timestamptz   NOT NULL DEFAULT now()
);

-- ===========================================================================
-- 5. REFERRAL CODES TABLE
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.referral_codes (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid          NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  code            text          NOT NULL UNIQUE,         -- e.g. 'RAHUL50'
  used_count      integer       NOT NULL DEFAULT 0,
  created_at      timestamptz   NOT NULL DEFAULT now()
);

-- ===========================================================================
-- 6. REFERRALS TABLE (tracks who invited whom)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.referrals (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id     uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  referred_id     uuid          NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  referral_code   text          NOT NULL,
  bonus_paid      boolean       NOT NULL DEFAULT false,  -- true once the referred user places first order
  created_at      timestamptz   NOT NULL DEFAULT now()
);

-- ===========================================================================
-- 7. INDEXES
-- ===========================================================================
CREATE INDEX IF NOT EXISTS idx_subscriptions_user   ON public.subscriptions (user_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_tx_user      ON public.loyalty_transactions (user_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_tx_order     ON public.loyalty_transactions (order_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referrer   ON public.referrals (referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_code       ON public.referrals (referral_code);

-- ===========================================================================
-- 8. RLS — ENABLE
-- ===========================================================================
ALTER TABLE public.subscription_plans    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_points        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_transactions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referral_codes        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals             ENABLE ROW LEVEL SECURITY;

-- ===========================================================================
-- 9. RLS POLICIES
-- ===========================================================================

-- subscription_plans: everyone can read; only admins write
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='subscription_plans' AND policyname='Plans readable by all') THEN
    CREATE POLICY "Plans readable by all" ON public.subscription_plans
      FOR SELECT USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='subscription_plans' AND policyname='Admins manage plans') THEN
    CREATE POLICY "Admins manage plans" ON public.subscription_plans
      FOR ALL TO authenticated
      USING (public.is_active_admin(auth.uid()))
      WITH CHECK (public.is_active_admin(auth.uid()));
  END IF;
END $$;

-- subscriptions: user sees own; admins see all
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='subscriptions' AND policyname='User reads own subscription') THEN
    CREATE POLICY "User reads own subscription" ON public.subscriptions
      FOR SELECT TO authenticated
      USING (user_id = auth.uid() OR public.is_active_admin(auth.uid()));
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='subscriptions' AND policyname='User inserts own subscription') THEN
    CREATE POLICY "User inserts own subscription" ON public.subscriptions
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='subscriptions' AND policyname='User updates own subscription') THEN
    CREATE POLICY "User updates own subscription" ON public.subscriptions
      FOR UPDATE TO authenticated
      USING (user_id = auth.uid() OR public.is_active_admin(auth.uid()));
  END IF;
END $$;

-- loyalty_points: user sees own
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='loyalty_points' AND policyname='User reads own loyalty') THEN
    CREATE POLICY "User reads own loyalty" ON public.loyalty_points
      FOR SELECT TO authenticated
      USING (user_id = auth.uid() OR public.is_active_admin(auth.uid()));
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='loyalty_points' AND policyname='User upserts own loyalty') THEN
    CREATE POLICY "User upserts own loyalty" ON public.loyalty_points
      FOR ALL TO authenticated
      USING (user_id = auth.uid() OR public.is_active_admin(auth.uid()))
      WITH CHECK (user_id = auth.uid() OR public.is_active_admin(auth.uid()));
  END IF;
END $$;

-- loyalty_transactions: user sees own
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='loyalty_transactions' AND policyname='User reads own transactions') THEN
    CREATE POLICY "User reads own transactions" ON public.loyalty_transactions
      FOR SELECT TO authenticated
      USING (user_id = auth.uid() OR public.is_active_admin(auth.uid()));
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='loyalty_transactions' AND policyname='User inserts own transactions') THEN
    CREATE POLICY "User inserts own transactions" ON public.loyalty_transactions
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid() OR public.is_active_admin(auth.uid()));
  END IF;
END $$;

-- referral_codes: user sees own code; everyone can read to validate
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='referral_codes' AND policyname='Anyone reads referral codes') THEN
    CREATE POLICY "Anyone reads referral codes" ON public.referral_codes
      FOR SELECT USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='referral_codes' AND policyname='User manages own code') THEN
    CREATE POLICY "User manages own code" ON public.referral_codes
      FOR ALL TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- referrals: user sees referrals they sent or received
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='referrals' AND policyname='User sees own referrals') THEN
    CREATE POLICY "User sees own referrals" ON public.referrals
      FOR SELECT TO authenticated
      USING (referrer_id = auth.uid() OR referred_id = auth.uid() OR public.is_active_admin(auth.uid()));
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='referrals' AND policyname='User inserts referral') THEN
    CREATE POLICY "User inserts referral" ON public.referrals
      FOR INSERT TO authenticated
      WITH CHECK (referred_id = auth.uid());
  END IF;
END $$;

-- ===========================================================================
-- 10. GRANTS
-- ===========================================================================
GRANT SELECT ON public.subscription_plans   TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.subscriptions        TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.loyalty_points       TO authenticated;
GRANT SELECT, INSERT ON public.loyalty_transactions         TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.referral_codes       TO authenticated;
GRANT SELECT, INSERT ON public.referrals                    TO authenticated;

-- ===========================================================================
-- 11. HELPER: Function to check if user has an active subscription
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.user_active_subscription(uid uuid)
RETURNS TABLE (
  plan_name text,
  delivery_free_threshold integer,
  cashback_percent numeric,
  max_accounts integer,
  expires_at timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT
    p.name,
    p.delivery_free_threshold,
    p.cashback_percent,
    p.max_accounts,
    s.expires_at
  FROM public.subscriptions s
  JOIN public.subscription_plans p ON s.plan_id = p.id
  WHERE s.user_id = uid
    AND s.status = 'active'
    AND s.expires_at > now()
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.user_active_subscription(uuid) TO authenticated;

-- ===========================================================================
-- 12. HELPER: Add loyalty points (upserts balance + inserts transaction)
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.add_loyalty_points(
  p_user_id uuid,
  p_points integer,
  p_type text,
  p_description text,
  p_order_id uuid DEFAULT NULL
)
RETURNS integer   -- returns new balance
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  new_balance integer;
BEGIN
  -- Upsert balance
  INSERT INTO public.loyalty_points (user_id, balance, lifetime_earned)
  VALUES (p_user_id, GREATEST(0, p_points), GREATEST(0, p_points))
  ON CONFLICT (user_id) DO UPDATE SET
    balance = CASE
      WHEN p_points > 0 THEN loyalty_points.balance + p_points
      ELSE GREATEST(0, loyalty_points.balance + p_points)
    END,
    lifetime_earned = CASE
      WHEN p_points > 0 THEN loyalty_points.lifetime_earned + p_points
      ELSE loyalty_points.lifetime_earned
    END,
    lifetime_redeemed = CASE
      WHEN p_points < 0 THEN loyalty_points.lifetime_redeemed + ABS(p_points)
      ELSE loyalty_points.lifetime_redeemed
    END,
    updated_at = now();

  SELECT balance INTO new_balance FROM public.loyalty_points WHERE user_id = p_user_id;

  -- Log transaction
  INSERT INTO public.loyalty_transactions (user_id, order_id, type, points, description, balance_after)
  VALUES (p_user_id, p_order_id, p_type, p_points, p_description, new_balance);

  RETURN new_balance;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_loyalty_points(uuid, integer, text, text, uuid) TO authenticated;

-- Reload schema cache
NOTIFY pgrst, 'reload schema';
