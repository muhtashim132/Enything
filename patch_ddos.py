import re
import json

def process_file(file_path, func_name, patch_str):
    with open(file_path, "r", encoding="utf-16le") as f:
        data = f.read()
    
    # Parse the json output from supabase db query
    try:
        j = json.loads(data)
        sql = j["rows"][0]["pg_get_functiondef"]
    except Exception as e:
        print(f"Error parsing {file_path}: {e}")
        return ""

    # Ensure it says CREATE OR REPLACE FUNCTION
    sql = sql.replace("CREATE FUNCTION", "CREATE OR REPLACE FUNCTION")

    # Inject after the first BEGIN
    # using regex, replace the first occurrence of \nBEGIN\n
    sql = re.sub(r'\bBEGIN\b', f'BEGIN\n{patch_str}', sql, count=1, flags=re.IGNORECASE)
    
    return sql

patch_checkout = """  -- 100x FIX: Unauthenticated Ghost Order DDOS Patch
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Unauthenticated checkouts are currently disabled to prevent Ghost Order DDOS.';
  END IF;
"""

patch_payment = """  -- 100x FIX: Unauthenticated Payment Spoofing Guard
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Payment confirmation requires an active session.';
  END IF;
  -- Ownership will be checked naturally or here
"""

patch_rider = """  -- 100x FIX: Global Order Hijacking Guard
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_rider_id THEN
    RAISE EXCEPTION 'Unauthorized: You cannot claim orders on behalf of another rider.';
  END IF;
"""

sql1 = process_file("p2.txt", "place_orders_transaction", patch_checkout)
sql2 = process_file("p3.txt", "client_confirm_payment", patch_payment)
sql3 = process_file("p4.txt", "claim_order_as_rider", patch_rider)

with open("supabase/migrations/20260896000000_100x_unauthenticated_ghost_order_ddos.sql", "w", encoding="utf-8") as out:
    out.write("-- Migration 20260896000000_100x_unauthenticated_ghost_order_ddos.sql\n")
    out.write("-- Phase 40: Unauthenticated Ghost Order DDOS & Payment Spoofing Patches\n\n")
    out.write(sql1 + ";\n\n")
    out.write(sql2 + ";\n\n")
    out.write(sql3 + ";\n\n")

print("Migration created.")
