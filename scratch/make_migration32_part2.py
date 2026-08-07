import re

# Read Migration 32 so far
with open('supabase/migrations/20290000000032_100x_jsonb_numeric_cast_and_signature_fix.sql', 'r') as f:
    sql32 = f.read()

# Read Migration 27
with open('supabase/migrations/20290000000027_100x_ultimate_dynamic_reallocation_fix.sql', 'r') as f:
    sql27 = f.read()

# Extract reallocate_cancelled_delivery_fees from Migration 27
match = re.search(r'CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees.*?END;\n\$\$;', sql27, flags=re.DOTALL)
if match:
    reallocate_sql = match.group(0)
    # Replace value::numeric with (value#>>'{}')::numeric
    reallocate_sql = reallocate_sql.replace('value::numeric', "(value#>>'{}')::numeric")
    
    # Append to Migration 32
    with open('supabase/migrations/20290000000032_100x_jsonb_numeric_cast_and_signature_fix.sql', 'a') as f:
        f.write('\n\n' + reallocate_sql + '\n')
    print("Appended reallocate_cancelled_delivery_fees")
else:
    print("Failed to find reallocate_cancelled_delivery_fees")

