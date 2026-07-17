$p1 = @"
  -- 100x FIX: Unauthenticated Ghost Order DDOS Patch
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Unauthenticated checkouts are currently disabled to prevent Ghost Order DDOS.';
  END IF;
"@

$p2 = @"
  -- 100x FIX: Unauthenticated Payment Spoofing Guard
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Payment confirmation requires an active session.';
  END IF;
"@

$p3 = @"
  -- 100x FIX: Global Order Hijacking Guard
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_rider_id THEN
    RAISE EXCEPTION 'Unauthorized: You cannot claim orders on behalf of another rider.';
  END IF;
"@

function ProcessFile($Path, $Patch) {
    $data = Get-Content -Path $Path -Encoding Unicode -Raw
    # Simple JSON extraction
    if ($data -match '"pg_get_functiondef":\s*"(.*?)"\s*\}') {
        $sql = $matches[1]
        
        # Unescape JSON string
        $sql = $sql -replace '\\n', "`n" -replace '\\r', "`r" -replace '\\t', "`t" -replace '\\"', "`""
        
        $sql = $sql -replace '(?i)CREATE FUNCTION', 'CREATE OR REPLACE FUNCTION'
        # Replace the very first BEGIN using regex object
        $regex = [regex] '(?i)\bBEGIN\b'
        $sql = $regex.Replace($sql, "BEGIN`n$Patch", 1)
        return $sql + ";`n`n"
    } else {
        Write-Host "Failed to match json in $Path"
        return ""
    }
}

$sql1 = ProcessFile "p_6args.txt" $p1
$sql2 = ProcessFile "p3.txt" $p2
$sql3 = ProcessFile "p4.txt" $p3

$drops = @"
-- Drop old overloads to prevent Legacy Endpoint Exploits
DROP FUNCTION IF EXISTS place_orders_transaction(jsonb, jsonb, uuid);
DROP FUNCTION IF EXISTS place_orders_transaction(jsonb, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS place_orders_transaction(jsonb, jsonb, uuid, uuid, text);
DROP FUNCTION IF EXISTS claim_order_as_rider(uuid, uuid);
"@

$final = "-- Migration 20260896000000_100x_unauthenticated_ghost_order_ddos.sql`n`n" + $drops + "`n`n" + $sql1 + $sql2 + $sql3
Set-Content -Path "supabase/migrations/20260896000000_100x_unauthenticated_ghost_order_ddos.sql" -Value $final -Encoding UTF8
Write-Host "Migration created successfully!"
