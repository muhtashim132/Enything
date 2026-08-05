import re

with open('/Users/muhtaashimnazki/Downloads/Enything/supabase/migrations/20271125000013_100x_checkout_atomic_swap_fix.sql', 'r') as f:
    text13 = f.read()

# Remove the broken place_orders_transaction from 13
text13_parts = text13.split('-- 4. Restore the atomic cancellation block inside place_orders_transaction')
text13_valid = text13_parts[0]

with open('/Users/muhtaashimnazki/Downloads/Enything/supabase/migrations/20271125000012_100x_checkout_coupon_increment_fix.sql', 'r') as f:
    text12 = f.read()

# Extract place_orders_transaction from 12
match = re.search(r'(CREATE OR REPLACE FUNCTION public\.place_orders_transaction.*?\$function\$;)', text12, re.DOTALL)
place_orders = match.group(1)

# Inject the cancellation block
cancel_block = """    UPDATE orders SET 
      status = 'cancelled', 
      cancelled_reason = 'customer_replaced',
      refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END
    WHERE id = p_order_id_to_cancel 
      AND customer_id = auth.uid() 
      AND status IN ('seller_rejected', 'rider_rejected');

    PERFORM reallocate_cancelled_delivery_fees(p_cart_group_id);"""

place_orders_patched = place_orders.replace('    PERFORM reallocate_cancelled_delivery_fees(p_cart_group_id);', cancel_block)

final_text = text13_valid + "-- 4. Restore the atomic cancellation block inside place_orders_transaction\n" + place_orders_patched + "\n"

with open('/Users/muhtaashimnazki/Downloads/Enything/supabase/migrations/20271125000013_100x_checkout_atomic_swap_fix.sql', 'w') as f:
    f.write(final_text)

print("Migration built successfully!")
