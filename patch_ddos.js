const fs = require('fs');

function processFile(path, funcName, patchStr) {
    try {
        let data = fs.readFileSync(path, 'utf16le');
        let j = JSON.parse(data);
        let sql = j.rows[0].pg_get_functiondef;
        sql = sql.replace(/CREATE FUNCTION/i, 'CREATE OR REPLACE FUNCTION');
        sql = sql.replace(/\bBEGIN\b/i, "BEGIN\n" + patchStr);
        return sql + ";\n\n";
    } catch(e) {
        console.error("Error with " + path + ": " + e);
        return "";
    }
}

let p1 = `  -- 100x FIX: Unauthenticated Ghost Order DDOS Patch
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Unauthenticated checkouts are currently disabled to prevent Ghost Order DDOS.';
  END IF;
`;
let p2 = `  -- 100x FIX: Unauthenticated Payment Spoofing Guard
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Payment confirmation requires an active session.';
  END IF;
`;
let p3 = `  -- 100x FIX: Global Order Hijacking Guard
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_rider_id THEN
    RAISE EXCEPTION 'Unauthorized: You cannot claim orders on behalf of another rider.';
  END IF;
`;

let sql1 = processFile('p2.txt', 'place_orders_transaction', p1);
let sql2 = processFile('p3.txt', 'client_confirm_payment', p2);
let sql3 = processFile('p4.txt', 'claim_order_as_rider', p3);

let out = "-- Migration 20260896000000_100x_unauthenticated_ghost_order_ddos.sql\n\n" + sql1 + sql2 + sql3;
fs.writeFileSync('supabase/migrations/20260896000000_100x_unauthenticated_ghost_order_ddos.sql', out, 'utf8');
console.log("Migration generated successfully!");
