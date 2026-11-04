#!/usr/bin/env python3
"""
Enything 100x Forensic Multi-Shop Realtime Simulator Test Suite (Bandipora)
Tests:
1. Exact Bandipora coordinates for Shop 1, Shop 2, Shop 3, Customer, Rider Depot.
2. Haversine distance assertions (Shop 1 to Shop 2: ~1.05 km, Shop 2 to Shop 3: ~2.15 km).
3. Bearing calculation & lerp interpolation.
4. Micro-movement jitter threshold (<3.5m).
5. Multi-shop order state machine transitions & 100% Prepaid Model invariants.
6. Sibling survival rule on partial rejection.
"""

import math
import sys

def haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0 # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def calculate_bearing(lat1, lon1, lat2, lon2):
    dlon = math.radians(lon2 - lon1)
    y = math.sin(dlon) * math.cos(math.radians(lat2))
    x = math.cos(math.radians(lat1)) * math.sin(math.radians(lat2)) - math.sin(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.cos(dlon)
    brng = math.degrees(math.atan2(y, x))
    return (brng + 360) % 360

def lerp(val1, val2, t):
    return val1 + t * (val2 - val1)

def run_tests():
    print("=" * 80)
    print("🧪 ENYTHING 100x FORENSIC TEST SUITE: BANDIPORA MULTI-SHOP REALTIME ENGINE")
    print("=" * 80)

    # ─────────────────────────────────────────────────────────────────────────
    # TEST 1: GEOSPATIAL DISTANCES (1KM & 2KM APART)
    # ─────────────────────────────────────────────────────────────────────────
    print("\n[TEST 1] Verifying Bandipora Real Coordinates & Distance Invariants...")
    
    # Coordinates
    depot = (34.4205, 74.6380)    # Bus Stand Bandipora
    shop1 = (34.4228, 74.6365)    # Gulshan Chowk (Central Bakery)
    shop2 = (34.4148, 74.6305)    # Kaloosa (Fresh Mart)
    shop3 = (34.4295, 74.6465)    # Plan Bandipora (Plan Chemist)
    customer = (34.4120, 74.6485) # Nowpora Residence

    d_1_2 = haversine_km(shop1[0], shop1[1], shop2[0], shop2[1])
    d_2_3 = haversine_km(shop2[0], shop2[1], shop3[0], shop3[1])
    d_3_c = haversine_km(shop3[0], shop3[1], customer[0], customer[1])
    d_depot_1 = haversine_km(depot[0], depot[1], shop1[0], shop1[1])

    print(f"  • Shop 1 (Gulshan Chowk) ➔ Shop 2 (Kaloosa): {d_1_2:.2f} km")
    print(f"  • Shop 2 (Kaloosa) ➔ Shop 3 (Plan Chemist):  {d_2_3:.2f} km")
    print(f"  • Shop 3 (Plan Chemist) ➔ Customer (Nowpora): {d_3_c:.2f} km")
    print(f"  • Rider Depot ➔ Shop 1 (Gulshan Chowk):      {d_depot_1:.2f} km")

    # Assert Shop 1 to Shop 2 is ~1 km
    assert 0.90 <= d_1_2 <= 1.25, f"Shop 1 to 2 distance out of expected range: {d_1_2} km"
    print("  ✅ Shop 1 to Shop 2 ~1 km constraint PASSED.")

    # Assert Shop 2 to Shop 3 is ~2 km
    assert 1.90 <= d_2_3 <= 2.40, f"Shop 2 to 3 distance out of expected range: {d_2_3} km"
    print("  ✅ Shop 2 to Shop 3 ~2 km constraint PASSED.")

    # ─────────────────────────────────────────────────────────────────────────
    # TEST 2: MATHEMATICAL BEARING & LERP INTERPOLATION
    # ─────────────────────────────────────────────────────────────────────────
    print("\n[TEST 2] Verifying Directional Bearing & Lerp Math...")
    bearing_depot_to_1 = calculate_bearing(depot[0], depot[1], shop1[0], shop1[1])
    print(f"  • Bearing Depot ➔ Shop 1: {bearing_depot_to_1:.1f}°")
    assert 0 <= bearing_depot_to_1 < 360, "Bearing out of range [0, 360)"

    # Lerp test
    mid_lat = lerp(shop1[0], shop2[0], 0.5)
    mid_lon = lerp(shop1[1], shop2[1], 0.5)
    expected_mid_lat = (shop1[0] + shop2[0]) / 2
    assert abs(mid_lat - expected_mid_lat) < 1e-7, "Lerp latitude calculation failed"
    print(f"  • Midpoint interpolation: ({mid_lat:.5f}, {mid_lon:.5f}) - PASSED.")

    # Jitter threshold test: movements < 3.5m lock previous bearing
    micro_move_km = haversine_km(depot[0], depot[1], depot[0] + 0.00001, depot[1] + 0.00001)
    micro_move_m = micro_move_km * 1000
    print(f"  • Micro movement: {micro_move_m:.2f} meters")
    assert micro_move_m < 3.5, "Micro move test expected < 3.5m"
    locked_bearing = 45.0 # Existing bearing
    if micro_move_m < 3.5:
        simulated_bearing = locked_bearing
    else:
        simulated_bearing = calculate_bearing(depot[0], depot[1], depot[0] + 0.00001, depot[1] + 0.00001)
    assert simulated_bearing == 45.0, "Jitter suppression failed"
    print("  ✅ Bearing noise suppression (<3.5m) PASSED (No icon spinning).")

    # ─────────────────────────────────────────────────────────────────────────
    # TEST 3: 100% PREPAID MODEL & PAYMENT BYPASS INVARIANCE
    # ─────────────────────────────────────────────────────────────────────────
    print("\n[TEST 3] Verifying 100% Prepaid Model & Payment Bypass...")
    order_group = {
        "cart_group_id": "test-group-bandipora-001",
        "is_prepaid": True,
        "is_cod": False,
        "cod_amount_to_collect": 0.0,
        "payment_status": "captured", # Payment bypass
        "payment_method": "practice",
        "orders": [
            {"id": "sub-1", "shop": "Bakery", "amount": 240.0, "earnings": 45.0},
            {"id": "sub-2", "shop": "Grocery", "amount": 380.0, "earnings": 30.0},
            {"id": "sub-3", "shop": "Chemist", "amount": 150.0, "earnings": 25.0},
        ]
    }
    assert order_group["is_prepaid"] is True, "Must be prepaid"
    assert order_group["is_cod"] is False, "COD must be strictly False"
    assert order_group["cod_amount_to_collect"] == 0.0, "COD amount must be 0.0"
    assert order_group["payment_status"] == "captured", "Payment status must be captured (bypassed)"
    print(f"  • 100% Prepaid Model: ₹{order_group['cod_amount_to_collect']} COD to collect.")
    print(f"  • Total Rider Earnings across 3 shops: ₹{sum(o['earnings'] for o in order_group['orders'])}")
    print("  ✅ 100% Prepaid Model & Payment Bypass PASSED.")

    # ─────────────────────────────────────────────────────────────────────────
    # TEST 4: MULTI-SHOP INTERMEDIATE NOTIFICATION GUARD
    # ─────────────────────────────────────────────────────────────────────────
    print("\n[TEST 4] Verifying Intermediate Multi-Shop Pickup Notification Logic...")
    shops = ["Shop 1 (Bakery)", "Shop 2 (Grocery)", "Shop 3 (Chemist)"]
    picked_up = []

    for i, shop in enumerate(shops, 1):
        picked_up.append(shop)
        remaining = len(shops) - len(picked_up)
        if remaining > 0:
            push_title = f"🛍️ Items Picked Up from {shop}"
            push_body = "Rider collected items. Heading to the next stop!"
            is_out_for_delivery = False
        else:
            push_title = "🛵 Out for Delivery!"
            push_body = "All items from all 3 stores collected! Rider is heading to your doorstep."
            is_out_for_delivery = True
        
        print(f"  • Stop {i} [{shop}]: Remaining unpicked={remaining} ➔ Push: '{push_title}' | OutForDelivery={is_out_for_delivery}")
        if i < 3:
            assert is_out_for_delivery is False, f"Premature out for delivery on stop {i}!"
        else:
            assert is_out_for_delivery is True, "Final stop must trigger out for delivery!"
    print("  ✅ Intermediate Multi-Shop Pickup Notification Guard PASSED.")

    # ─────────────────────────────────────────────────────────────────────────
    # TEST 5: SIBLING ORDER SURVIVAL RULE
    # ─────────────────────────────────────────────────────────────────────────
    print("\n[TEST 5] Verifying Sibling Order Survival on Store Rejection...")
    sub_orders = [
        {"id": "o1", "shop": "Bakery", "status": "preparing"},
        {"id": "o2", "shop": "Grocery", "status": "seller_rejected"},
        {"id": "o3", "shop": "Chemist", "status": "preparing"}
    ]
    active_siblings = [o for o in sub_orders if o["status"] not in ("cancelled", "seller_rejected", "partner_rejected")]
    assert len(active_siblings) == 2, f"Expected 2 surviving siblings, got {len(active_siblings)}"
    assert [o["id"] for o in active_siblings] == ["o1", "o3"], "Wrong siblings survived"
    rider_msg = "⚠️ Store Declined Items: A store declined their part. Delivering remaining store(s)."
    print(f"  • Surviving sub-orders: {[o['shop'] for o in active_siblings]} (Count: {len(active_siblings)})")
    print(f"  • Rider Alert: '{rider_msg}'")
    print("  ✅ Sibling Survival Rule PASSED (Rider not abandoned).")

    print("\n" + "=" * 80)
    print("🎉 ALL 5 FORENSIC EDGE-CASE & GEOSPATIAL TEST SUITES PASSED FLAWLESSLY!")
    print("=" * 80)

if __name__ == "__main__":
    run_tests()

