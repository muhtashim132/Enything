import re

with open('/Users/muhtaashimnazki/Downloads/Enything/supabase/migrations/20271242000000_100x_checkout_atomic_swap_fix.sql', 'r') as f:
    text = f.read()

# Extract get_nearby_unassigned_orders
match1 = re.search(r'(CREATE OR REPLACE FUNCTION public\.get_nearby_unassigned_orders.*?\$function\$;)', text, re.DOTALL)
func1 = match1.group(1)
# Add 'rider_rejected' to the NOT IN list
func1 = func1.replace("'seller_rejected', 'partner_rejected', 'shop_dispute_cancel'", "'seller_rejected', 'partner_rejected', 'rider_rejected', 'shop_dispute_cancel'")

# Extract reallocate_cancelled_delivery_fees
match2 = re.search(r'(CREATE OR REPLACE FUNCTION public\.reallocate_cancelled_delivery_fees.*?\$\$;)', text, re.DOTALL)
func2 = match2.group(1)
# Remove + rec.gst_platform
func2 = func2.replace('+ rec.gst_platform', '')

# Extract rebalance_active_delivery_fees
match3 = re.search(r'(CREATE OR REPLACE FUNCTION public\.rebalance_active_delivery_fees.*?\$\$;)', text, re.DOTALL)
func3 = match3.group(1)
# Remove + rec.gst_platform
func3 = func3.replace('+ rec.gst_platform', '')

new_migration_content = f"""-- =============================================================================
-- Migration: 20271243000000_100x_affinity_and_tax_edge_cases.sql
-- Description: ADDITIVE ONLY - CREATE OR REPLACE FUNCTION only.
--              Fixes the "Ghost Lock" rider affinity bug by adding rider_rejected
--              Fixes the double-charging of gst_platform in grand_total_collected
-- =============================================================================

{func1}

GRANT EXECUTE ON FUNCTION get_nearby_unassigned_orders(double precision, double precision, double precision) TO authenticated;

{func2}

{func3}
"""

with open('/Users/muhtaashimnazki/Downloads/Enything/supabase/migrations/20271243000000_100x_affinity_and_tax_edge_cases.sql', 'w') as f:
    f.write(new_migration_content)

print("Migration built successfully!")
