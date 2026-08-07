import re

with open('scratch/migration32_base.sql', 'r') as f:
    sql = f.read()

# 1. Replace ALL value::numeric with (value#>>'{}')::numeric
sql = sql.replace('value::numeric', "(value#>>'{}')::numeric")

# 2. Fix the missing fees in v_expected_grand_total
old_grand_total = """    -- 100x ARCHITECTURE STRESS-TEST FIX: Recalculate expected grand total meticulously
    v_expected_grand_total := GREATEST(0, v_expected_total_amount + v_s9_5_gst + v_non_food_gst + COALESCE((v_order->>'platform_fee')::numeric, 0) + COALESCE((v_order->>'delivery_charges')::numeric, 0) - COALESCE((v_order->>'coupon_discount')::numeric, 0));"""

new_grand_total = """    -- 100x ARCHITECTURE STRESS-TEST FIX: Include ALL missing fees in grand_total_collected!
    v_expected_grand_total := GREATEST(0, v_expected_total_amount 
      + v_s9_5_gst + v_non_food_gst 
      + COALESCE((v_order->>'platform_fee')::numeric, 0) 
      + COALESCE((v_order->>'delivery_charges')::numeric, 0)
      + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0)
      + COALESCE((v_order->>'small_cart_fee')::numeric, 0)
      + COALESCE((v_order->>'heavy_order_fee')::numeric, 0)
      - COALESCE((v_order->>'coupon_discount')::numeric, 0));"""

sql = sql.replace(old_grand_total, new_grand_total)

# 3. Add the DROP FUNCTION for the phantom Migration 27 function at the top
header = """-- =============================================================================
-- Migration: 100x JSONB Numeric Cast and Signature Fix
-- Description:
--   1. Drops the phantom `place_orders_transaction` (with 13 parameters) accidentally created in Migration 27.
--   2. Replaces `value::numeric` with `(value#>>'{}')::numeric` in `place_orders_transaction` to prevent JSONB cast crashes.
--   3. Integrates the `grand_total_collected` missing fees fix (multi_shop_surcharge, etc.) into the REAL `place_orders_transaction`.
--   4. Replaces `value::numeric` with `(value#>>'{}')::numeric` in `reallocate_cancelled_delivery_fees`.
-- =============================================================================

DROP FUNCTION IF EXISTS public.place_orders_transaction(uuid, uuid, text, text, text, double precision, double precision, text, text, jsonb, jsonb, text, uuid);

"""

# We need to prepend the header, but remove the old header
sql = re.sub(r'-- ===.*?-- ===.*?\n\n?', header, sql, flags=re.DOTALL)

with open('supabase/migrations/20290000000032_100x_jsonb_numeric_cast_and_signature_fix.sql', 'w') as f:
    f.write(sql)

