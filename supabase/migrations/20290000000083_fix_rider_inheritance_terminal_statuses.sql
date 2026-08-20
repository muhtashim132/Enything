-- Bug 4.4: Fix place_orders_transaction rider inheritance to exclude ALL terminal statuses
-- Previously only excluded ('cancelled', 'seller_rejected', 'partner_rejected'),
-- missing 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel'.
-- This caused a rejected rider to be re-assigned to the replacement order.
--
-- This migration patches ONLY the rider inheritance query within place_orders_transaction.
-- The full function is carried forward from 20290000000082_100x_universal_weight_and_heavy_fee_fix.sql
-- with the single fix applied to the status NOT IN clause for rider inheritance.

-- We use a targeted UPDATE approach via ALTER to avoid rewriting the entire 600+ line function.
-- Instead, we drop and recreate just the function with the corrected status filter.

-- Since the full function body is too large to duplicate safely in a patch migration,
-- we apply the fix by updating the existing function's rider inheritance logic.
-- The key change: line ~169 in the function changes from:
--   AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected')
-- to:
--   AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected',
--       'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')

-- Implementation: We use pg_catalog to find and replace the function body text.
DO $$
DECLARE
  v_func_oid oid;
  v_old_body text;
  v_new_body text;
BEGIN
  -- Find the function OID
  SELECT p.oid INTO v_func_oid
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.proname = 'place_orders_transaction'
    AND n.nspname = 'public'
  ORDER BY p.oid DESC
  LIMIT 1;

  IF v_func_oid IS NULL THEN
    RAISE NOTICE 'place_orders_transaction function not found, skipping';
    RETURN;
  END IF;

  -- Get current function body
  SELECT prosrc INTO v_old_body FROM pg_proc WHERE oid = v_func_oid;

  -- Check if already patched
  IF v_old_body LIKE '%rider_rejected%verification_failed%timeout%payment_failed%shop_dispute_cancel%' THEN
    RAISE NOTICE 'place_orders_transaction already patched with full terminal statuses';
    RETURN;
  END IF;

  -- Apply the fix: replace the incomplete status NOT IN with the complete one
  v_new_body := replace(
    v_old_body,
    E'AND status NOT IN (\'cancelled\', \'seller_rejected\', \'partner_rejected\')',
    E'AND status NOT IN (\'cancelled\', \'seller_rejected\', \'partner_rejected\', \'rider_rejected\', \'verification_failed\', \'timeout\', \'payment_failed\', \'shop_dispute_cancel\')'
  );

  -- Verify the replacement actually happened
  IF v_new_body = v_old_body THEN
    RAISE NOTICE 'Could not find the target string to replace. The function body may have a different format.';
    RETURN;
  END IF;

  -- Execute the replacement by recreating the function with the patched body
  EXECUTE format(
    'CREATE OR REPLACE FUNCTION place_orders_transaction(p_orders jsonb, p_cart_group_id text DEFAULT NULL, p_order_id_to_cancel text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$%s$fn$',
    v_new_body
  );

  RAISE NOTICE 'Successfully patched place_orders_transaction rider inheritance status filter';
END $$;
