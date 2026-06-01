-- =============================================================================
-- add_razorpay_order_id.sql
-- Adds razorpay_order_id to orders table for proper payment tracking.
-- Also adds payment_status enum values: captured, cod, pending_payment,
-- payment_failed to replace the old 'paid' / 'pending_upi' values.
-- =============================================================================

-- 1. Add razorpay_order_id column (the server-created order ID, issued before
--    the Razorpay checkout sheet opens — required for production verification).
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS razorpay_order_id TEXT;

-- 2. Add index for fast webhook lookups by razorpay_order_id
CREATE INDEX IF NOT EXISTS idx_orders_razorpay_order_id
  ON public.orders (razorpay_order_id)
  WHERE razorpay_order_id IS NOT NULL;

-- 3. Add index for fast webhook lookups by razorpay_payment_id
CREATE INDEX IF NOT EXISTS idx_orders_razorpay_payment_id
  ON public.orders (razorpay_payment_id)
  WHERE razorpay_payment_id IS NOT NULL;

-- 4. Normalise any legacy payment_status values
UPDATE public.orders
  SET payment_status = 'captured'
  WHERE payment_status IN ('paid', 'success');

UPDATE public.orders
  SET payment_status = 'cod'
  WHERE payment_method = 'cod' AND (payment_status IS NULL OR payment_status = 'pending_upi');

-- =============================================================================
-- Withdrawals table — for seller & rider payout requests
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.withdrawals (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_role           TEXT NOT NULL CHECK (user_role IN ('seller', 'delivery_partner')),
  amount              NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
  -- Payout destination (one of upi_id or bank_account_number must be set)
  upi_id              TEXT,
  bank_account_number TEXT,
  bank_ifsc           TEXT,
  bank_account_holder TEXT,
  -- Status lifecycle: pending → approved → processed | rejected
  status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'approved', 'processed', 'rejected')),
  razorpay_payout_id  TEXT,     -- filled after Razorpay X payout is issued
  admin_note          TEXT,     -- rejection reason or admin comment
  requested_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at        TIMESTAMPTZ,
  CONSTRAINT withdrawal_payout_target CHECK (
    upi_id IS NOT NULL OR bank_account_number IS NOT NULL
  )
);

-- RLS
ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;

-- User can view and create their own withdrawal requests
CREATE POLICY "withdrawals_select_own"
  ON public.withdrawals FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "withdrawals_insert_own"
  ON public.withdrawals FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Admins can do everything
CREATE POLICY "withdrawals_admin_all"
  ON public.withdrawals FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));

-- Index for fast admin panel queries
CREATE INDEX IF NOT EXISTS idx_withdrawals_status
  ON public.withdrawals (status, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_withdrawals_user
  ON public.withdrawals (user_id);
