-- =============================================================================
-- Bug Fix Migration: Security + Integrity Hardening
-- Date: 2026-06-25
-- Fixes:
--   O2: decrement_product_stock RPC — atomic stock decrement after order placement
--   O3: Retry order validation (client already handles this via stock check)
--   SE2: Block seller reject after payment (handled client-side; DB trigger for safety)
--   D1:  Atomic rider accept via RPC (optional — client guard is primary)
-- =============================================================================

-- ── O2: Atomic product stock decrement ───────────────────────────────────────
-- Called from Flutter after successful order_items insert.
-- Only decrements when total_quantity IS NOT NULL (i.e., inventory is tracked).
-- Uses GREATEST(0, ...) so stock never goes negative (safety net).
CREATE OR REPLACE FUNCTION decrement_product_stock(
  p_product_id  uuid,
  p_quantity    int
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER  -- Runs as owner so authenticated users can decrement
SET search_path = public
AS $$
BEGIN
  UPDATE products
  SET total_quantity = GREATEST(0, total_quantity - p_quantity)
  WHERE id = p_product_id
    AND total_quantity IS NOT NULL;  -- Only decrement tracked inventory
END;
$$;

-- Grant execute to authenticated users (customers placing orders)
GRANT EXECUTE ON FUNCTION decrement_product_stock(uuid, int) TO authenticated;

-- ── O2 (Restore): Increment stock back on order cancellation ─────────────────
-- Called by a DB trigger whenever an order is cancelled so stock is restored.
CREATE OR REPLACE FUNCTION restore_product_stock_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item_row RECORD;
BEGIN
  -- Only restore stock when transitioning INTO a cancelled state
  IF NEW.status IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider')
     AND OLD.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider') THEN

    FOR item_row IN
      SELECT product_id, quantity FROM order_items WHERE order_id = NEW.id
    LOOP
      UPDATE products
      SET total_quantity = total_quantity + item_row.quantity
      WHERE id = item_row.product_id
        AND total_quantity IS NOT NULL;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- Drop and recreate trigger cleanly
DROP TRIGGER IF EXISTS trg_restore_stock_on_cancel ON orders;
CREATE TRIGGER trg_restore_stock_on_cancel
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION restore_product_stock_on_cancel();

-- ── SE2 (Server Guard): Block status regression after payment captured ────────
-- Belt-and-suspenders: even if client-side check fails, the DB trigger blocks it.
CREATE OR REPLACE FUNCTION prevent_reject_after_payment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If trying to move into a rejection/cancellation state from a post-payment state
  IF NEW.status IN ('seller_rejected', 'partner_rejected', 'cancelled')
     AND OLD.status IN ('confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered') THEN
    RAISE EXCEPTION 'Cannot cancel order with id=% — payment is already confirmed (status was: %)',
      OLD.id, OLD.status;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_reject_after_payment ON orders;
CREATE TRIGGER trg_prevent_reject_after_payment
  BEFORE UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION prevent_reject_after_payment();

-- ── D1 (Atomic Rider Accept): RPC to atomically claim an order ───────────────
-- Returns TRUE if the rider successfully claimed the order, FALSE if already taken.
CREATE OR REPLACE FUNCTION claim_order_as_rider(
  p_order_id          uuid,
  p_rider_id          uuid,
  p_payment_deadline  timestamptz DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated int;
  v_seller_accepted boolean;
  v_status text;
BEGIN
  -- Read current state
  SELECT seller_accepted, status
  INTO v_seller_accepted, v_status
  FROM orders
  WHERE id = p_order_id;

  -- Only allow claiming orders in awaiting_acceptance
  IF v_status != 'awaiting_acceptance' THEN
    RETURN false;
  END IF;

  -- Atomic update: only succeeds if delivery_partner_id IS NULL (no other rider has it)
  UPDATE orders
  SET
    delivery_partner_id = p_rider_id,
    partner_accepted    = true,
    status = CASE
      WHEN seller_accepted THEN 'awaiting_payment'
      ELSE 'awaiting_acceptance'
    END,
    payment_deadline = CASE
      WHEN seller_accepted AND p_payment_deadline IS NOT NULL THEN p_payment_deadline
      ELSE payment_deadline
    END
  WHERE id              = p_order_id
    AND delivery_partner_id IS NULL   -- Atomic lock: fails if another rider took it
    AND status          = 'awaiting_acceptance';

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$$;

-- Grant execute to authenticated users (delivery partners)
GRANT EXECUTE ON FUNCTION claim_order_as_rider(uuid, uuid, timestamptz) TO authenticated;

-- ── O4+O5 (Server-side Timeout): Enhanced auto-cancel cron ───────────────────
-- Ensures hung orders are cancelled even when no client is watching.
-- This extends any existing cron job; the acceptance_deadline and
-- payment_deadline columns already exist from prior migrations.

-- Cancel orders stuck in awaiting_acceptance past deadline
CREATE OR REPLACE FUNCTION auto_cancel_timed_out_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Cancel awaiting_acceptance orders past their acceptance deadline
  UPDATE orders
  SET
    status           = 'cancelled',
    cancelled_reason = 'timeout'
  WHERE status            = 'awaiting_acceptance'
    AND acceptance_deadline IS NOT NULL
    AND acceptance_deadline < NOW();

  -- Cancel awaiting_payment orders past their payment deadline
  UPDATE orders
  SET
    status           = 'cancelled',
    cancelled_reason = 'timeout'
  WHERE status           = 'awaiting_payment'
    AND payment_deadline IS NOT NULL
    AND payment_deadline < NOW();
END;
$$;

-- Wire into pg_cron (if available — safe to run on fresh DBs with no existing job)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
  ) THEN
    -- Only unschedule if the job already exists (safe for first-time migration run)
    IF EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'auto_cancel_orders'
    ) THEN
      PERFORM cron.unschedule('auto_cancel_orders');
    END IF;

    PERFORM cron.schedule(
      'auto_cancel_orders',
      '* * * * *',   -- every minute
      'SELECT auto_cancel_timed_out_orders()'
    );
  END IF;
END $$;
