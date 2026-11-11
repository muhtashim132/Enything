-- Migration: 20290000000192_100x_master_audit_remediation_fortress.sql
-- Description: 100x Master Forensic Remediation Fortress:
--   1. place_orders_transaction: Eliminate double-addition of surcharges in v_expected_grand_total & enforce 3-shop cap.
--   2. validate_order_status_transition: Permit transitions to 'preparing' and 'no_rider' from 'awaiting_acceptance'/'pending'.
--   3. decline_order_items_seller: Restore exact grand_total recalculation, pending_refund_amount, and delivery fee rebalancing.
--   4. admin_get_dispatch_feed: Include in-flight dropped orders (confirmed, preparing, ready_for_pickup) lacking an assigned rider.
--   5. admin_proxy_accept_rider: Fix column name alignment for self-delivery mode on delivery_partners table.
--   6. reject_order_rider: Unify advisory locking on single-store orders using COALESCE(cart_group_id, p_order_id).
--   7. request_seller_withdrawal: Add advisory lock to prevent double-spend withdrawal race conditions.
--   8. shops table: Restrict anonymous SELECT to public catalog columns to protect seller KYC and banking PII.

-- =============================================================================
-- 1. FORTIFY place_orders_transaction
-- =============================================================================

CREATE OR REPLACE FUNCTION public.place_orders_transaction(
  p_orders jsonb,
  p_items jsonb,
  p_cart_group_id uuid,
  p_coupon_id uuid DEFAULT NULL::uuid,
  p_idempotency_key text DEFAULT NULL::text,
  p_order_id_to_cancel uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid;
  v_inserted_ids uuid[] := '{}';
  v_order jsonb;
  v_item jsonb;
  v_prod record;
  v_order_id uuid;
  v_expected_total_amount numeric;
  v_client_total_amount numeric;
  v_expected_grand_total numeric;
  v_client_grand_total numeric;
  v_item_price numeric;
  v_variant_price numeric;
  v_expected_discount numeric := 0;
  v_num_orders int;
  v_order_seq int := 0;
  v_is_replacement boolean := false;
  v_acceptance_deadline timestamptz;

  v_platform_fee_config numeric := 2.0;
  v_platform_gst_rate numeric := 0.18;
  v_server_gst_platform numeric;
  v_delivery_gst_rate numeric := 0.18;
  v_server_gst_delivery numeric;
  v_rider_commission_percent numeric := 80.0;
  v_server_rider_earnings numeric;
  v_server_seller_payout numeric;
  v_server_enything_commission numeric;

  v_tcs_rate numeric := 0.005;
  v_tds_rate numeric := 0.001;
  v_tcs_amount numeric := 0.0;
  v_tds_amount numeric := 0.0;
  v_gw_deduct numeric := 0.0;
  v_seller_gw_share numeric := 0.0;
  v_item_weight_kg numeric;
  v_clean_unit text;
  v_order_total_weight_kg numeric;
  v_group_total_weight_kg numeric := 0.0;
  v_existing_group_weight numeric := 0.0;

  v_s9_5_gst numeric := 0.0;
  v_non_food_gst numeric := 0.0;
  v_pure_commission numeric := 0.0;
  v_item_subtotal numeric := 0.0;
  v_item_gst numeric := 0.0;
  v_item_commission numeric := 0.0;
  v_item_is_food boolean := false;
  v_item_gst_rate numeric := 0.0;
  v_item_comm_rate numeric := 5.0;

  v_slab_threshold numeric := 2500.0;
  v_slab_high_rate numeric := 0.18;

  v_shop_cat text;
  v_comm_key text;
  v_comm_val numeric;

  v_existing_rider_id uuid;
  v_existing_rider_phone text;
  v_existing_partner_accepted boolean;
  v_secure_order jsonb;
  v_active_cart_groups_count int;
  v_rider_cap int := 3;

  v_shop_lat double precision;
  v_shop_lng double precision;
BEGIN
  v_customer_id := auth.uid();
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place orders';
  END IF;

  IF p_orders IS NULL OR jsonb_array_length(p_orders) = 0 THEN
    RAISE EXCEPTION 'Orders list cannot be empty';
  END IF;

  v_num_orders := jsonb_array_length(p_orders);

  -- 100x Strict Enforcement: Limit multi-shop cart to maximum 3 stores per checkout
  IF v_num_orders > 3 THEN
    RAISE EXCEPTION 'Cannot order from more than 3 shops in a single checkout';
  END IF;

  -- Platform Service Tax Configurations
  BEGIN
    SELECT (value#>>'{}')::numeric INTO v_platform_fee_config FROM platform_config WHERE key = 'platform_fee';
    IF v_platform_fee_config IS NULL THEN v_platform_fee_config := 2.0; END IF;

    SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate' OR key = 'platform_gst_rate' LIMIT 1;
    IF v_platform_gst_rate IS NULL THEN v_platform_gst_rate := 0.18; END IF;

    SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate';
    IF v_delivery_gst_rate IS NULL THEN v_delivery_gst_rate := 0.18; END IF;

    SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent';
    IF v_rider_commission_percent IS NULL THEN v_rider_commission_percent := 80.0; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_platform_fee_config := 2.0;
    v_platform_gst_rate := 0.18;
    v_delivery_gst_rate := 0.18;
    v_rider_commission_percent := 80.0;
  END;

  -- Replacement Order Validation
  IF p_order_id_to_cancel IS NOT NULL THEN
    v_is_replacement := true;
    SELECT delivery_partner_id, rider_phone, partner_accepted
    INTO v_existing_rider_id, v_existing_rider_phone, v_existing_partner_accepted
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND id != p_order_id_to_cancel
      AND delivery_partner_id IS NOT NULL
      AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'failed', 'returned')
    LIMIT 1;

    -- Tally existing physical weight from active sibling orders
    SELECT COALESCE(SUM(oi.weight_kg * oi.quantity), 0.0)
    INTO v_existing_group_weight
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    WHERE o.cart_group_id = p_cart_group_id
      AND o.id != p_order_id_to_cancel
      AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'failed', 'returned')
      AND oi.status = 'active';

    v_group_total_weight_kg := v_existing_group_weight;
  END IF;

  -- Loop through each shop order
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders)
  LOOP
    v_order_seq := v_order_seq + 1;
    v_order_id := (v_order->>'id')::uuid;
    v_expected_total_amount := 0.0;
    v_client_total_amount := COALESCE((v_order->>'total_amount')::numeric, 0.0);
    v_client_grand_total := COALESCE((v_order->>'grand_total_collected')::numeric, 0.0);
    v_order_total_weight_kg := 0.0;

    v_s9_5_gst := 0.0;
    v_non_food_gst := 0.0;
    v_pure_commission := 0.0;
    v_tcs_amount := 0.0;
    v_tds_amount := 0.0;

    IF v_is_replacement THEN
      v_acceptance_deadline := NOW() + interval '5 minutes';
    ELSE
      v_acceptance_deadline := NOW() + interval '2 minutes';
    END IF;

    SELECT category INTO v_shop_cat FROM shops WHERE id = (v_order->>'shop_id')::uuid;

    -- Validate and process items for this specific shop order
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      IF ((v_item->>'order_id') IS NOT NULL AND (v_item->>'order_id')::uuid = v_order_id)
         OR ((v_item->>'order_id') IS NULL AND (v_item->>'shop_id')::uuid = (v_order->>'shop_id')::uuid) THEN

        SELECT * INTO v_prod FROM products 
        WHERE id = (v_item->>'product_id')::uuid 
          AND is_available = true 
          AND is_deleted = false
        FOR UPDATE;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'Product % is unavailable or deleted', (v_item->>'product_id');
        END IF;

        IF v_prod.total_quantity IS NOT NULL AND v_prod.total_quantity < (v_item->>'quantity')::int THEN
          RAISE EXCEPTION 'Insufficient stock for product % (Available: %, Requested: %)', 
            v_prod.name, v_prod.total_quantity, (v_item->>'quantity')::int;
        END IF;

        -- Unit Weight Calculation
        v_item_weight_kg := COALESCE(v_prod.weight_per_unit, 0.5);
        v_clean_unit := lower(trim(COALESCE(v_prod.unit, '')));
        IF v_clean_unit != '' THEN
          IF v_clean_unit ~ '^\d+(\.\d+)?\s*(g|gm|gms|gram|grams)$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
          ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*kg$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
          ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*m[lL]$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
          ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*(l|lt|ltr|ltrs|liter|liters|litre|litres)$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
          END IF;
        END IF;

        IF v_item_weight_kg <= 0 THEN v_item_weight_kg := 0.5; END IF;
        v_order_total_weight_kg := v_order_total_weight_kg + (v_item_weight_kg * (v_item->>'quantity')::int);

        -- Price verification (variant vs base product)
        v_item_price := v_prod.price;
        IF (v_item->>'variant_name') IS NOT NULL AND v_prod.variants IS NOT NULL THEN
          SELECT (elem->>'price')::numeric INTO v_variant_price
          FROM jsonb_array_elements(v_prod.variants) AS elem
          WHERE elem->>'name' = (v_item->>'variant_name');
          IF v_variant_price IS NOT NULL AND v_variant_price > 0 THEN
            v_item_price := v_variant_price;
          END IF;
        END IF;

        v_item_subtotal := v_item_price * (v_item->>'quantity')::int;
        v_expected_total_amount := v_expected_total_amount + v_item_subtotal;

        -- Section 9(5) deemed supplier check
        v_item_is_food := COALESCE(v_prod.is_food, (lower(COALESCE(v_shop_cat, '')) IN (
          'restaurant', 'food', 'bakery', 'cafe', 'fast_food', 'sweet_shop',
          'sweets & mithai', 'tea & coffee', 'ice cream', 'paan shop'
        )));

        -- Priority hierarchy for GST rate resolution
        IF v_prod.gst_rate_override IS NOT NULL THEN
          v_item_gst_rate := v_prod.gst_rate_override;
        ELSIF (v_item->>'gst_rate') IS NOT NULL AND (v_item->>'gst_rate')::numeric >= 0.0 THEN
          v_item_gst_rate := (v_item->>'gst_rate')::numeric;
        ELSIF COALESCE(v_prod.category, v_shop_cat) IN ('Clothing', 'Footwear') THEN
          SELECT COALESCE(slab_threshold, 2500.0), COALESCE(slab_high_rate, 0.18)
          INTO v_slab_threshold, v_slab_high_rate
          FROM tax_config WHERE category = COALESCE(v_prod.category, v_shop_cat);
          IF v_slab_threshold IS NULL THEN v_slab_threshold := 2500.0; END IF;
          IF v_slab_high_rate IS NULL THEN v_slab_high_rate := 0.18; END IF;
          IF v_item_price > v_slab_threshold THEN
            v_item_gst_rate := v_slab_high_rate;
          ELSE
            v_item_gst_rate := 0.05;
          END IF;
        ELSE
          SELECT gst_rate INTO v_item_gst_rate FROM tax_config WHERE category = COALESCE(v_prod.category, v_shop_cat);
          IF v_item_gst_rate IS NULL THEN
            v_item_gst_rate := CASE WHEN v_item_is_food THEN 0.05 ELSE 0.18 END;
          END IF;
        END IF;

        -- Add-on GST: computed on top of seller base subtotal
        v_item_gst := ROUND((v_item_subtotal * v_item_gst_rate)::numeric, 2);
        IF v_item_is_food THEN
          v_s9_5_gst := v_s9_5_gst + v_item_gst;
        ELSE
          v_non_food_gst := v_non_food_gst + v_item_gst;
        END IF;

        -- Category-specific platform commission lookup
        v_comm_key := 'commission_' || lower(COALESCE(v_prod.category, 'grocery'));
        BEGIN
          SELECT (value#>>'{}')::numeric INTO v_comm_val FROM platform_config WHERE key = v_comm_key;
        EXCEPTION WHEN OTHERS THEN v_comm_val := NULL; END;
        IF v_comm_val IS NOT NULL THEN
          v_item_comm_rate := v_comm_val;
        ELSE
          v_item_comm_rate := 5.0;
        END IF;

        v_item_commission := ROUND((v_item_subtotal * (v_item_comm_rate / 100.0))::numeric, 2);
        v_pure_commission := v_pure_commission + v_item_commission;

        -- Section 52 GST TCS (0.5% strictly on net taxable supplies; 0% on food & exempt goods)
        IF NOT v_item_is_food AND v_item_gst_rate > 0.0 AND lower(COALESCE(v_prod.category, v_shop_cat)) NOT IN ('fruits & vegs', 'butcher', 'fish & seafood') THEN
          v_tcs_amount := v_tcs_amount + ROUND((v_item_subtotal * v_tcs_rate)::numeric, 2);
        END IF;

        -- Section 194-O Income Tax TDS (0.1% on gross base consideration)
        v_tds_amount := v_tds_amount + ROUND((v_item_subtotal * v_tds_rate)::numeric, 2);

        -- Insert into order_items with immutable statutory GST snapshot
        INSERT INTO order_items (
          order_id,
          product_id,
          name,
          price,
          quantity,
          variant_name,
          weight_kg,
          status,
          gst_rate,
          gst_amount,
          is_food,
          commission_rate,
          commission_amount,
          tcs_amount,
          tds_amount,
          created_at,
          updated_at
        ) VALUES (
          v_order_id,
          v_prod.id,
          v_prod.name,
          v_item_price,
          (v_item->>'quantity')::int,
          v_item->>'variant_name',
          v_item_weight_kg,
          'active',
          v_item_gst_rate,
          v_item_gst,
          v_item_is_food,
          v_item_comm_rate,
          v_item_commission,
          CASE WHEN NOT v_item_is_food AND v_item_gst_rate > 0.0 THEN ROUND((v_item_subtotal * v_tcs_rate)::numeric, 2) ELSE 0.0 END,
          ROUND((v_item_subtotal * v_tds_rate)::numeric, 2),
          NOW(),
          NOW()
        );

        -- Decrement stock atomically
        IF v_prod.total_quantity IS NOT NULL THEN
          UPDATE products 
          SET total_quantity = total_quantity - (v_item->>'quantity')::int,
              updated_at = NOW()
          WHERE id = v_prod.id;
        END IF;
      END IF;
    END LOOP;

    v_group_total_weight_kg := v_group_total_weight_kg + v_order_total_weight_kg;

    -- Subtotal verification
    IF ABS(v_expected_total_amount - v_client_total_amount) > 0.05 THEN
      RAISE EXCEPTION 'Item price/subtotal mismatch for shop %. Expected %, got %',
        (v_order->>'shop_id'), v_expected_total_amount, v_client_total_amount;
    END IF;

    -- ── 100x Corrected Grand Total Resolution ──────────────────────────────
    -- delivery_charges payload already encapsulates base fee, surcharges, and delivery GST.
    -- Surcharges MUST NOT be re-added on top of delivery_charges.
    v_expected_grand_total := v_expected_total_amount 
      + v_s9_5_gst 
      + v_non_food_gst
      + COALESCE((v_order->>'delivery_charges')::numeric, 0)
      + COALESCE((v_order->>'platform_fee')::numeric, 0)
      - COALESCE((v_order->>'coupon_discount')::numeric, 0);

    IF ABS(v_expected_grand_total - v_client_grand_total) > 0.05 THEN
      RAISE EXCEPTION 'Grand total mismatch for shop %. Expected %, got %',
        (v_order->>'shop_id'), v_expected_grand_total, v_client_grand_total;
    END IF;

    -- Statutory Deductions & Payouts
    v_server_gst_platform := COALESCE((v_order->>'platform_fee')::numeric, 0) - (COALESCE((v_order->>'platform_fee')::numeric, 0) / (1.0 + v_platform_gst_rate));
    v_server_gst_delivery := COALESCE((v_order->>'delivery_charges')::numeric, 0) - (COALESCE((v_order->>'delivery_charges')::numeric, 0) / (1.0 + v_delivery_gst_rate));
    v_server_rider_earnings := GREATEST(0, (COALESCE((v_order->>'delivery_charges')::numeric, 0) - v_server_gst_delivery - COALESCE((v_order->>'small_cart_fee')::numeric, 0)) * (v_rider_commission_percent / 100.0));
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_pure_commission - v_tcs_amount - v_tds_amount;
    v_gw_deduct := (v_expected_grand_total * 0.02) * (1.0 + 0.18);

    -- Prepare sanitized order record
    v_secure_order := v_order || jsonb_build_object(
      'id', v_order_id,
      'customer_id', v_customer_id,
      'cart_group_id', p_cart_group_id,
      'status', 'awaiting_acceptance',
      'payment_status', 'pending',
      'total_amount', v_expected_total_amount,
      'grand_total', v_expected_grand_total,
      'grand_total_collected', v_expected_grand_total,
      's9_5_gst_amount', v_s9_5_gst,
      'non_food_gst_amount', v_non_food_gst,
      'gst_item_total', (v_s9_5_gst + v_non_food_gst),
      'enything_commission', v_pure_commission,
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'seller_payout', v_server_seller_payout,
      'gst_platform', v_server_gst_platform,
      'gst_delivery', v_server_gst_delivery,
      'rider_earnings', v_server_rider_earnings,
      'gateway_deduction', v_gw_deduct,
      'acceptance_deadline', v_acceptance_deadline,
      'created_at', NOW(),
      'updated_at', NOW()
    );

    IF v_existing_rider_id IS NOT NULL THEN
      v_secure_order := v_secure_order || jsonb_build_object(
        'delivery_partner_id', v_existing_rider_id,
        'rider_phone', v_existing_rider_phone,
        'partner_accepted', v_existing_partner_accepted
      );
    END IF;

    -- Dynamically resolve missing shop coordinates
    IF (v_secure_order->>'shop_lat' IS NULL OR (v_secure_order->>'shop_lat')::numeric = 0.0) THEN
      SELECT ST_Y(location::geometry), ST_X(location::geometry)
      INTO v_shop_lat, v_shop_lng
      FROM shops WHERE id = (v_order->>'shop_id')::uuid;

      IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
        v_secure_order := v_secure_order || jsonb_build_object(
          'shop_lat', v_shop_lat,
          'shop_lng', v_shop_lng
        );
      END IF;
    END IF;

    INSERT INTO orders SELECT * FROM jsonb_populate_record(null::orders, v_secure_order);
    v_inserted_ids := array_append(v_inserted_ids, v_order_id);
  END LOOP;

  -- Cancel Previous Order if Replacement
  IF p_order_id_to_cancel IS NOT NULL THEN
    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'customer_replaced',
        updated_at = NOW()
    WHERE id = p_order_id_to_cancel
      AND customer_id = v_customer_id;
  END IF;

  -- Disarm Rejection Timers and Rebalance Delivery Fees
  IF v_is_replacement THEN
    PERFORM public.acknowledge_partial_rejection(p_cart_group_id, 'replaced');
    PERFORM public.rebalance_active_delivery_fees(p_cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_ids', to_jsonb(v_inserted_ids),
    'cart_group_id', p_cart_group_id,
    'total_weight_kg', v_group_total_weight_kg,
    'is_replacement', v_is_replacement,
    'assigned_rider_id', v_existing_rider_id
  );
END;
$function$;


-- =============================================================================
-- 2. FORTIFY validate_order_status_transition
-- =============================================================================

CREATE OR REPLACE FUNCTION public.validate_order_status_transition()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        RETURN NEW;
    END IF;

    -- Only validate if status is actually changing
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    CASE OLD.status
        WHEN 'awaiting_payment' THEN
            IF NEW.status NOT IN ('awaiting_acceptance', 'cancelled', 'pending', 'confirmed', 'payment_failed', 'verification_failed', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'awaiting_acceptance' THEN
            -- Allow transitions directly to preparing (when payment captured upon reassignment) and no_rider (when matching times out)
            IF NEW.status NOT IN ('pending', 'awaiting_payment', 'confirmed', 'preparing', 'no_rider', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'pending' THEN
            -- Allow transitions directly to preparing and no_rider
            IF NEW.status NOT IN ('confirmed', 'preparing', 'no_rider', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'awaiting_acceptance', 'awaiting_payment') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'confirmed' THEN
            -- Allow transition to no_rider if rider search exhausts
            IF NEW.status NOT IN ('preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'awaiting_acceptance', 'no_rider') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'preparing' THEN
            IF NEW.status NOT IN ('ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'awaiting_acceptance', 'no_rider') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'ready_for_pickup' THEN
            -- Cannot regress to awaiting_acceptance once food is cooked and ready
            IF NEW.status NOT IN ('picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'no_rider') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'picked_up' THEN
            IF NEW.status NOT IN ('out_for_delivery', 'delivered', 'cancelled', 'shop_dispute', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'out_for_delivery' THEN
            IF NEW.status NOT IN ('delivered', 'cancelled', 'shop_dispute', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'shop_dispute' THEN
            IF NEW.status NOT IN ('cancelled', 'delivered', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_pending' THEN
            IF NEW.status NOT IN ('bulk_confirmed', 'bulk_preparing', 'bulk_ready', 'bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_confirmed' THEN
            IF NEW.status NOT IN ('bulk_preparing', 'bulk_ready', 'bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_preparing' THEN
            IF NEW.status NOT IN ('bulk_ready', 'bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_ready' THEN
            IF NEW.status NOT IN ('bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_dispatched' THEN
            IF NEW.status NOT IN ('delivered', 'cancelled', 'shop_dispute', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'no_rider' THEN
            -- Allow re-assigning or cancelling from no_rider state
            IF NEW.status NOT IN ('awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'delivered' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from delivered to %', NEW.status;

        WHEN 'cancelled' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from cancelled to %', NEW.status;

        WHEN 'seller_rejected' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from seller_rejected to %', NEW.status;

        WHEN 'partner_rejected' THEN
            IF NEW.status NOT IN ('awaiting_acceptance', 'pending', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'rider_rejected' THEN
            IF NEW.status NOT IN ('awaiting_acceptance', 'pending', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'verification_failed' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from verification_failed to %', NEW.status;

        WHEN 'timeout' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from timeout to %', NEW.status;

        WHEN 'payment_failed' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from payment_failed to %', NEW.status;

        WHEN 'shop_dispute_cancel' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from shop_dispute_cancel to %', NEW.status;

        ELSE
            -- Default fallback
            NULL;
    END CASE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 3. FORTIFY decline_order_items_seller
-- =============================================================================

CREATE OR REPLACE FUNCTION public.decline_order_items_seller(
  p_order_id UUID,
  p_declined_item_ids UUID[],
  p_reason TEXT,
  p_message TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_shop_cat TEXT;
  v_is_food BOOLEAN;
  v_effective_gst_rate NUMERIC;
  v_comm_rate NUMERIC := 5.0;
  v_comm_key TEXT;
  v_comm_val NUMERIC;
  v_slab_threshold NUMERIC := 2500.0;
  v_slab_high_rate NUMERIC := 0.18;

  v_new_active_subtotal NUMERIC := 0.0;
  v_new_s9_5 NUMERIC := 0.0;
  v_new_non_food_gst NUMERIC := 0.0;
  v_new_gst_item_total NUMERIC := 0.0;
  v_new_enything_commission NUMERIC := 0.0;
  v_new_tcs NUMERIC := 0.0;
  v_new_tds NUMERIC := 0.0;
  v_new_seller_payout NUMERIC := 0.0;
  v_new_grand_total NUMERIC := 0.0;
  v_refund_delta NUMERIC := 0.0;

  v_item RECORD;
  v_item_subtotal NUMERIC;
  v_item_gst NUMERIC;
  v_item_comm NUMERIC;
  v_item_tcs NUMERIC;
  v_active_count INT;
  v_declined_prod_ids UUID[];
  v_affected_count INT := 0;
BEGIN
  -- 100x Concurrency Shield: Acquire transaction advisory lock
  SELECT * INTO v_order
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND');
  END IF;

  IF v_order.status NOT IN ('pending', 'awaiting_acceptance', 'confirmed', 'preparing', 'awaiting_payment') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_ORDER_STATE', 'current_status', v_order.status);
  END IF;

  IF p_declined_item_ids IS NULL OR array_length(p_declined_item_ids, 1) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_ITEMS_SPECIFIED');
  END IF;

  -- Collect product IDs for stock sync
  SELECT array_agg(product_id) INTO v_declined_prod_ids
  FROM order_items
  WHERE id = ANY(p_declined_item_ids) AND order_id = p_order_id AND status = 'active';

  -- Mark declined items
  UPDATE order_items
  SET 
    status = 'declined',
    decline_reason = COALESCE(p_message, p_reason),
    declined_at = NOW()
  WHERE id = ANY(p_declined_item_ids)
    AND order_id = p_order_id
    AND status = 'active';

  GET DIAGNOSTICS v_affected_count = ROW_COUNT;

  -- Stock sync: mark declined items out of stock
  IF v_declined_prod_ids IS NOT NULL AND array_length(v_declined_prod_ids, 1) > 0 THEN
    UPDATE products
    SET 
      is_available = false,
      total_quantity = 0,
      updated_at = NOW()
    WHERE id = ANY(v_declined_prod_ids)
      AND is_deleted = false;
  END IF;

  -- Determine shop category & Section 9(5) food status
  SELECT category INTO v_shop_cat FROM shops WHERE id = v_order.shop_id;
  v_is_food := (lower(COALESCE(v_shop_cat, '')) IN (
    'restaurant', 'food', 'bakery', 'cafe', 'fast_food', 'sweet_shop',
    'sweets & mithai', 'tea & coffee', 'ice cream', 'paan shop'
  ));

  v_comm_key := 'commission_percent_' || COALESCE(v_shop_cat, 'default');
  BEGIN
    SELECT value::numeric INTO v_comm_val FROM platform_config WHERE key = v_comm_key;
    IF v_comm_val IS NOT NULL THEN v_comm_rate := v_comm_val; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_comm_rate := 5.0;
  END;

  -- ── Recalculation Loop for Surviving Active Items ──────────────────────────
  FOR v_item IN
    SELECT oi.price, oi.quantity, oi.product_id, oi.gst_rate AS item_gst_rate,
           p.category AS prod_cat, p.gst_rate_override
    FROM order_items oi
    LEFT JOIN products p ON oi.product_id = p.id
    WHERE oi.order_id = p_order_id AND oi.status = 'active'
  LOOP
    v_item_subtotal := v_item.price * v_item.quantity;
    v_new_active_subtotal := v_new_active_subtotal + v_item_subtotal;

    -- Resolve statutory item GST rate with priority
    IF v_item.item_gst_rate IS NOT NULL THEN
      v_effective_gst_rate := v_item.item_gst_rate;
    ELSIF v_item.gst_rate_override IS NOT NULL THEN
      v_effective_gst_rate := v_item.gst_rate_override;
    ELSIF COALESCE(v_item.prod_cat, v_shop_cat) IN ('Clothing', 'Footwear') THEN
      SELECT COALESCE(slab_threshold, 2500.0), COALESCE(slab_high_rate, 0.18)
      INTO v_slab_threshold, v_slab_high_rate
      FROM tax_config WHERE category = COALESCE(v_item.prod_cat, v_shop_cat);
      IF v_slab_threshold IS NULL THEN v_slab_threshold := 2500.0; END IF;
      IF v_slab_high_rate IS NULL THEN v_slab_high_rate := 0.18; END IF;
      IF v_item.price > v_slab_threshold THEN
        v_effective_gst_rate := v_slab_high_rate;
      ELSE
        v_effective_gst_rate := 0.05;
      END IF;
    ELSE
      SELECT gst_rate INTO v_effective_gst_rate FROM tax_config WHERE category = COALESCE(v_item.prod_cat, v_shop_cat);
      IF v_effective_gst_rate IS NULL THEN
        v_effective_gst_rate := CASE WHEN v_is_food THEN 0.05 ELSE 0.18 END;
      END IF;
    END IF;

    -- Add-On GST math
    v_item_gst := ROUND((v_item_subtotal * v_effective_gst_rate)::numeric, 2);
    IF v_is_food THEN
      v_new_s9_5 := v_new_s9_5 + v_item_gst;
    ELSE
      v_new_non_food_gst := v_new_non_food_gst + v_item_gst;
    END IF;

    v_item_comm := ROUND((v_item_subtotal * (v_comm_rate / 100.0))::numeric, 2);
    v_new_enything_commission := v_new_enything_commission + v_item_comm;

    -- Zero TCS for exempt items or Section 9(5) food
    IF NOT v_is_food AND v_effective_gst_rate > 0.0 AND lower(COALESCE(v_item.prod_cat, v_shop_cat)) NOT IN ('fruits & vegs', 'butcher', 'fish & seafood') THEN
      v_item_tcs := ROUND((v_item_subtotal * 0.005)::numeric, 2);
    ELSE
      v_item_tcs := 0.0;
    END IF;
    v_new_tcs := v_new_tcs + v_item_tcs;
    v_new_tds := v_new_tds + ROUND((v_item_subtotal * 0.001)::numeric, 2);
  END LOOP;

  v_new_gst_item_total := v_new_s9_5 + v_new_non_food_gst;
  v_new_seller_payout := v_new_active_subtotal + v_new_non_food_gst - v_new_enything_commission - v_new_tcs - v_new_tds;

  SELECT COUNT(*) INTO v_active_count FROM order_items WHERE order_id = p_order_id AND status = 'active';

  IF v_active_count = 0 THEN
    -- All items declined -> cancel store's order
    UPDATE orders
    SET 
      status = 'seller_rejected',
      cancelled_reason = 'all_items_declined: ' || COALESCE(p_message, p_reason),
      total_amount = 0,
      grand_total = 0,
      seller_payout = 0,
      pending_refund_amount = CASE 
        WHEN payment_status = 'captured' THEN COALESCE(grand_total_collected, grand_total, 0)
        ELSE 0.0
      END,
      refund_status = CASE 
        WHEN payment_status = 'captured' THEN 'processing'
        ELSE 'none'
      END,
      updated_at = NOW()
    WHERE id = p_order_id;

    -- Rebalance delivery fees across surviving sibling stores in cart group
    IF v_order.cart_group_id IS NOT NULL THEN
      BEGIN
        PERFORM public.rebalance_active_delivery_fees(v_order.cart_group_id);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  ELSE
    -- Partial rejection: update subtotal, statutory GST, commissions, payout, and grand_total
    v_new_grand_total := v_new_active_subtotal + v_new_gst_item_total
      + COALESCE(v_order.delivery_charges, 0)
      + COALESCE(v_order.platform_fee, 0)
      - COALESCE(v_order.coupon_discount, 0);

    v_refund_delta := GREATEST(0.0, COALESCE(v_order.grand_total_collected, v_order.grand_total, 0) - v_new_grand_total);

    UPDATE orders
    SET 
      total_amount = v_new_active_subtotal,
      grand_total = v_new_grand_total,
      s9_5_gst_amount = v_new_s9_5,
      non_food_gst_amount = v_new_non_food_gst,
      gst_item_total = v_new_gst_item_total,
      enything_commission = v_new_enything_commission,
      tcs_amount = v_new_tcs,
      tds_amount = v_new_tds,
      seller_payout = v_new_seller_payout,
      pending_refund_amount = CASE
        WHEN payment_status = 'captured' AND v_refund_delta > 0.01 
          THEN COALESCE(pending_refund_amount, 0) + v_refund_delta
        ELSE pending_refund_amount
      END,
      refund_status = CASE
        WHEN payment_status = 'captured' AND v_refund_delta > 0.01 
          THEN 'processing'
        ELSE refund_status
      END,
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'declined_count', v_affected_count,
    'remaining_active_count', v_active_count,
    'new_subtotal', v_new_active_subtotal,
    'new_grand_total', v_new_grand_total,
    'new_gst_item_total', v_new_gst_item_total,
    'new_seller_payout', v_new_seller_payout,
    'refund_delta', v_refund_delta
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.decline_order_items_seller(UUID, UUID[], TEXT, TEXT) TO authenticated, service_role;


-- =============================================================================
-- 4. FORTIFY admin_get_dispatch_feed
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_get_dispatch_feed(
  p_admin_lat DOUBLE PRECISION DEFAULT NULL,
  p_admin_lng DOUBLE PRECISION DEFAULT NULL,
  p_radius_km DOUBLE PRECISION DEFAULT NULL, -- NULL = Unlimited
  p_include_riders BOOLEAN DEFAULT TRUE,
  p_include_sellers BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
  order_id UUID,
  cart_group_id UUID,
  status TEXT,
  seller_accepted BOOLEAN,
  partner_accepted BOOLEAN,
  delivery_partner_id UUID,
  payment_status TEXT,
  total_amount NUMERIC,
  customer_id UUID,
  customer_name TEXT,
  customer_phone TEXT,
  shop_id UUID,
  shop_name TEXT,
  shop_lat DOUBLE PRECISION,
  shop_lng DOUBLE PRECISION,
  distance_km DOUBLE PRECISION,
  created_at TIMESTAMPTZ,
  acceptance_deadline TIMESTAMPTZ,
  item_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
BEGIN
  -- Strict Admin Authorization Check
  IF v_caller_id IS NULL OR NOT (
    public.is_super_admin(v_caller_id) 
    OR public.is_active_admin(v_caller_id) 
    OR public.has_permission(v_caller_id, 'dispatch.view_feed')
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Dispatch feed is restricted to authorized platform administrators.';
  END IF;

  RETURN QUERY
  SELECT 
    o.id AS order_id,
    o.cart_group_id,
    o.status,
    COALESCE(o.seller_accepted, false) AS seller_accepted,
    COALESCE(o.partner_accepted, false) AS partner_accepted,
    o.delivery_partner_id,
    o.payment_status,
    o.total_amount,
    o.customer_id,
    COALESCE(p.full_name, 'Customer') AS customer_name,
    COALESCE(p.phone, '') AS customer_phone,
    o.shop_id,
    COALESCE(s.name, 'Shop') AS shop_name,
    COALESCE(o.shop_lat::double precision, ST_Y(s.location::geometry)) AS shop_lat,
    COALESCE(o.shop_lng::double precision, ST_X(s.location::geometry)) AS shop_lng,
    CASE 
      WHEN p_admin_lat IS NOT NULL AND p_admin_lng IS NOT NULL AND s.location IS NOT NULL THEN
        ST_Distance(s.location::geography, ST_SetSRID(ST_MakePoint(p_admin_lng, p_admin_lat), 4326)::geography) / 1000.0
      ELSE 0.0
    END AS distance_km,
    o.created_at,
    o.acceptance_deadline,
    (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
  FROM orders o
  JOIN shops s ON o.shop_id = s.id
  LEFT JOIN profiles p ON o.customer_id = p.id
  WHERE (
    o.status IN ('awaiting_acceptance', 'pending')
    OR (
      o.status IN ('awaiting_payment', 'confirmed', 'preparing', 'ready_for_pickup')
      AND (o.delivery_partner_id IS NULL OR NOT COALESCE(o.partner_accepted, false))
    )
  )
  AND (
    (p_include_sellers AND NOT COALESCE(o.seller_accepted, false) AND o.status IN ('awaiting_acceptance', 'pending'))
    OR
    (p_include_riders AND (NOT COALESCE(o.partner_accepted, false) OR o.delivery_partner_id IS NULL))
  )
  AND (
    p_radius_km IS NULL 
    OR p_admin_lat IS NULL 
    OR p_admin_lng IS NULL 
    OR s.location IS NULL
    OR ST_DWithin(s.location::geography, ST_SetSRID(ST_MakePoint(p_admin_lng, p_admin_lat), 4326)::geography, p_radius_km * 1000.0)
  )
  ORDER BY o.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_dispatch_feed(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN, BOOLEAN) TO authenticated;


-- =============================================================================
-- 5. FORTIFY admin_proxy_accept_rider (Self-Delivery Column Parity)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_proxy_accept_rider(
  p_order_id UUID,
  p_rider_id UUID DEFAULT NULL,
  p_rider_phone TEXT DEFAULT NULL,
  p_shop_lat DOUBLE PRECISION DEFAULT NULL,
  p_shop_lng DOUBLE PRECISION DEFAULT NULL,
  p_force_reassign BOOLEAN DEFAULT FALSE
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_status TEXT;
  v_seller_accepted BOOLEAN;
  v_partner_accepted BOOLEAN;
  v_payment_status TEXT;
  v_cart_group_id UUID;
  v_target_rider_id UUID;
  v_target_name TEXT;
  v_target_phone TEXT;
  v_is_admin_delivery BOOLEAN := FALSE;
  v_admin_name TEXT;
  v_admin_phone TEXT;
  v_existing_rider_id UUID;
  v_existing_rider_name TEXT;
  v_new_status TEXT;
  v_order_record RECORD;
  v_return_both_accepted BOOLEAN := FALSE;
  v_all_group_shops_accepted BOOLEAN := TRUE;
  v_resolved_shop_lat DOUBLE PRECISION;
  v_resolved_shop_lng DOUBLE PRECISION;
BEGIN
  -- 1. Authorization Barrier
  IF NOT (
    public.is_super_admin(v_caller_id) 
    OR public.is_active_admin(v_caller_id) 
    OR public.has_permission(v_caller_id, 'dispatch.proxy_rider_accept')
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not have permission to proxy-accept orders for riders.';
  END IF;

  -- 2. Target Rider Resolution
  IF p_rider_id IS NOT NULL THEN
    v_target_rider_id := p_rider_id;
    SELECT COALESCE(p.full_name, 'Rider'), COALESCE(p.phone, '')
    INTO v_target_name, v_target_phone
    FROM profiles p
    WHERE p.id = v_target_rider_id;

    IF v_target_name IS NULL THEN
      RAISE EXCEPTION 'RIDER_NOT_FOUND: The specified delivery partner does not exist.';
    END IF;
  ELSE
    -- Self-delivery mode
    v_target_rider_id := v_caller_id;
    v_is_admin_delivery := TRUE;

    SELECT COALESCE(p.full_name, 'Admin'), COALESCE(p.phone, '')
    INTO v_admin_name, v_admin_phone
    FROM profiles p
    WHERE p.id = v_caller_id;

    v_target_name := 'Admin ' || COALESCE(v_admin_name, 'Delivery');
    v_target_phone := COALESCE(v_admin_phone, '');

    -- Aligned with exact delivery_partners table schema
    INSERT INTO delivery_partners (
      id, name, phone, vehicle_type, is_active, is_available, is_accepting_orders, verification_status
    ) VALUES (
      v_caller_id, v_target_name, v_target_phone, 'motorcycle', true, true, true, 'verified'
    )
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      phone = EXCLUDED.phone,
      is_active = true,
      is_available = true,
      is_accepting_orders = true,
      verification_status = 'verified';
  END IF;

  -- 3. Row & State Fetch
  SELECT status, seller_accepted, partner_accepted, payment_status, cart_group_id, delivery_partner_id, rider_name
  INTO v_status, v_seller_accepted, v_partner_accepted, v_payment_status, v_cart_group_id, v_existing_rider_id, v_existing_rider_name
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  IF v_status = 'seller_rejected' THEN
    RAISE EXCEPTION 'ORDER_ALREADY_REJECTED';
  END IF;

  IF v_partner_accepted = true AND v_existing_rider_id IS NOT NULL AND v_existing_rider_id != v_target_rider_id AND NOT p_force_reassign THEN
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER: Order was already accepted by %', v_existing_rider_name;
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'awaiting_payment', 'confirmed', 'preparing', 'ready_for_pickup') THEN
    RAISE EXCEPTION 'INVALID_STATE_TRANSITION: Order is in status %', v_status;
  END IF;

  -- 4. Cart Group Advisory Lock
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || COALESCE(v_cart_group_id, p_order_id)::text));

  -- Check if all shops in the cart group have accepted
  IF v_cart_group_id IS NOT NULL THEN
    SELECT bool_and(COALESCE(o.seller_accepted, false))
    INTO v_all_group_shops_accepted
    FROM orders o
    WHERE o.cart_group_id = v_cart_group_id
      AND o.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected');
    v_all_group_shops_accepted := COALESCE(v_all_group_shops_accepted, true);
  ELSE
    v_all_group_shops_accepted := COALESCE(v_seller_accepted, false);
  END IF;

  -- 5. Atomic Cart Group Assignment Loop
  FOR v_order_record IN 
    SELECT o.id, o.status, o.seller_accepted, o.payment_status, o.payment_deadline, o.order_ready_time, o.shop_id, o.shop_lat, o.shop_lng
    FROM orders o
    WHERE COALESCE(o.cart_group_id, o.id) = COALESCE(v_cart_group_id, p_order_id)
      AND o.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed')
    ORDER BY o.id
    FOR UPDATE
  LOOP
    IF v_order_record.status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN
      v_new_status := v_order_record.status;
      v_return_both_accepted := TRUE;
    ELSIF v_all_group_shops_accepted = true THEN
      IF v_order_record.payment_status = 'captured' THEN
        IF v_order_record.order_ready_time IS NOT NULL THEN
          v_new_status := 'ready_for_pickup';
        ELSE
          v_new_status := 'preparing';
        END IF;
      ELSE
        v_new_status := 'awaiting_payment';
      END IF;
      v_return_both_accepted := TRUE;
    ELSE
      v_new_status := v_order_record.status;
    END IF;

    IF v_order_record.id = p_order_id AND p_shop_lat IS NOT NULL AND p_shop_lat != 0 THEN
      v_resolved_shop_lat := p_shop_lat;
      v_resolved_shop_lng := p_shop_lng;
    ELSIF v_order_record.shop_lat IS NOT NULL AND v_order_record.shop_lat != 0 THEN
      v_resolved_shop_lat := v_order_record.shop_lat;
      v_resolved_shop_lng := v_order_record.shop_lng;
    ELSE
      SELECT ST_Y(location::geometry), ST_X(location::geometry)
      INTO v_resolved_shop_lat, v_resolved_shop_lng
      FROM shops WHERE id = v_order_record.shop_id;
    END IF;

    UPDATE orders
    SET 
      partner_accepted = true,
      delivery_partner_id = v_target_rider_id,
      rider_name = v_target_name,
      rider_phone = COALESCE(v_target_phone, rider_phone),
      is_admin_delivery = v_is_admin_delivery,
      status = v_new_status,
      payment_deadline = CASE 
        WHEN v_order_record.seller_accepted = true AND v_order_record.payment_status != 'captured' 
        THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' 
        ELSE v_order_record.payment_deadline 
      END,
      shop_lat = COALESCE(v_resolved_shop_lat, v_order_record.shop_lat),
      shop_lng = COALESCE(v_resolved_shop_lng, v_order_record.shop_lng),
      updated_at = NOW()
    WHERE id = v_order_record.id;
  END LOOP;

  -- 6. Audit Logging
  INSERT INTO audit_logs (
    actor_id,
    actor_role,
    action,
    target_resource,
    target_id,
    metadata
  ) VALUES (
    v_caller_id,
    'admin',
    CASE WHEN v_is_admin_delivery THEN 'admin_self_assign_delivery' ELSE 'admin_proxy_accept_rider' END,
    'orders',
    p_order_id,
    jsonb_build_object(
      'rider_id', v_target_rider_id,
      'rider_name', v_target_name,
      'cart_group_id', v_cart_group_id,
      'is_admin_delivery', v_is_admin_delivery,
      'both_accepted', v_return_both_accepted
    )
  );

  RETURN v_return_both_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_rider(UUID, UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN) TO authenticated;


-- =============================================================================
-- 6. FORTIFY reject_order_rider (Consistent Single-Store Locking)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reject_order_rider(
  p_order_id UUID, 
  p_reason TEXT DEFAULT NULL,
  p_disputed BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_delivery_partner_id uuid;
  v_shop_id uuid;
  v_status text;
  v_cart_group_id uuid;
BEGIN
  SELECT delivery_partner_id, shop_id, status, cart_group_id 
  INTO v_delivery_partner_id, v_shop_id, v_status, v_cart_group_id
  FROM orders 
  WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Transaction-level Advisory Lock (unified for cart groups and single-shop orders)
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || COALESCE(v_cart_group_id, p_order_id)::text));

  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  -- Re-fetch critical fields post-lock
  SELECT delivery_partner_id, status 
  INTO v_delivery_partner_id, v_status
  FROM orders 
  WHERE id = p_order_id;

  IF v_delivery_partner_id IS NULL OR (v_delivery_partner_id IS DISTINCT FROM auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: You are not assigned to this order.';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup', 'awaiting_payment') THEN
    RAISE EXCEPTION 'CRITICAL: Cannot drop an order after it has been picked up or delivered (Status: %). Contact platform support.', v_status;
  END IF;

  -- Atomic Cart Group Drop: Preserve awaiting_payment and preparation statuses
  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      partner_accepted = false,
      delivery_partner_id = NULL,
      rider_phone = NULL,
      rider_name = NULL,
      status = CASE 
        WHEN status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN status
        WHEN status = 'awaiting_payment' THEN 'awaiting_payment'
        ELSE 'awaiting_acceptance' 
      END,
      acceptance_deadline = NOW() + interval '5 minutes',
      updated_at = NOW()
    WHERE cart_group_id = v_cart_group_id
      AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel');
  ELSE
    UPDATE orders
    SET 
      partner_accepted = false,
      delivery_partner_id = NULL,
      rider_phone = NULL,
      rider_name = NULL,
      status = CASE 
        WHEN status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN status
        WHEN status = 'awaiting_payment' THEN 'awaiting_payment'
        ELSE 'awaiting_acceptance' 
      END,
      acceptance_deadline = NOW() + interval '5 minutes',
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;

  -- Audit log rider drop
  INSERT INTO audit_logs (
    actor_id,
    actor_role,
    action,
    target_resource,
    target_id,
    metadata
  ) VALUES (
    auth.uid(),
    'rider',
    'rider_drop_order',
    'orders',
    p_order_id,
    jsonb_build_object(
      'reason', p_reason,
      'cart_group_id', v_cart_group_id,
      'disputed', p_disputed,
      'prior_status', v_status
    )
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reject_order_rider(UUID, TEXT, BOOLEAN) TO authenticated, service_role;


-- =============================================================================
-- 7. FORTIFY request_seller_withdrawal (Advisory Lock Double-Spend Shield)
-- =============================================================================

CREATE OR REPLACE FUNCTION request_seller_withdrawal(
  p_amount NUMERIC,
  p_upi_id TEXT DEFAULT NULL,
  p_bank_account_number TEXT DEFAULT NULL,
  p_bank_ifsc TEXT DEFAULT NULL,
  p_bank_account_holder TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  v_seller_id UUID := auth.uid();
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
  v_withdrawal_id UUID;
BEGIN
  IF v_seller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Must be logged in to request withdrawal.';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Invalid withdrawal amount: Must be greater than 0.';
  END IF;

  -- Advisory lock to prevent concurrent double-spend requests
  PERFORM pg_advisory_xact_lock(hashtext('seller_withdrawal_' || v_seller_id::text));

  SELECT COALESCE(SUM(
    CASE 
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') 
           AND (COALESCE(total_refunded, 0) >= COALESCE(grand_total, 0) OR COALESCE(grand_total, 0) = 0) THEN 0 
      ELSE COALESCE(seller_payout, 0) 
    END 
    - COALESCE(wait_time_penalty, 0)
  ), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND shop_id IN (SELECT id FROM shops WHERE seller_id = v_seller_id);

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = v_seller_id
  AND user_role = 'seller'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  IF p_amount > v_available_balance THEN
    RAISE EXCEPTION 'Insufficient balance: Available balance is %, requested %', v_available_balance, p_amount;
  END IF;

  INSERT INTO withdrawals (
    user_id,
    user_role,
    amount,
    upi_id,
    bank_account_number,
    bank_ifsc,
    bank_account_holder,
    status,
    created_at,
    updated_at
  ) VALUES (
    v_seller_id,
    'seller',
    p_amount,
    p_upi_id,
    p_bank_account_number,
    p_bank_ifsc,
    p_bank_account_holder,
    'pending',
    NOW(),
    NOW()
  ) RETURNING id INTO v_withdrawal_id;

  RETURN json_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id,
    'amount', p_amount,
    'remaining_balance', v_available_balance - p_amount
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.request_seller_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;


-- =============================================================================
-- 8. SECURE shops TABLE PII FROM PUBLIC ANONYMOUS SCRAPING
-- =============================================================================

-- Revoke blanket table access from anon
REVOKE ALL ON public.shops FROM anon;

-- Grant SELECT only on public catalog columns to anon:
GRANT SELECT (
  id, seller_id, name, shop_type, category, categories, cuisine_type, fssai_number,
  address, location, prep_time_minutes, is_veg_only, opening_hours, open_time, close_time,
  is_active, is_accepting_orders, banner_url, average_rating, total_reviews, total_orders,
  verification_status, house_number, pincode, metadata, created_at, updated_at
) ON public.shops TO anon;

