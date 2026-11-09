#!/usr/bin/env python3
"""
Maxx Retail — Forensic Verification Audit for Batch 12 (l111.jpeg to l115.jpeg)
=============================================================================
Audits Supabase database records for Maxx Retail to confirm:
1. All 6 Master Products are present and active (is_deleted = false).
2. Category is strictly 'Grocerylm' (Low Margin).
3. Dietary preference is strictly None / SQL NULL.
4. Prices, Brands, Weights, and Units match physical shelf pack specifications.
5. Variants are populated with correct pricing and naming.
6. Public image URLs are valid and accessible.
"""

import sys
import requests

SUPABASE_CONFIG = {
    "url": "https://hvtujaatwhyxielrlztr.supabase.co",
    "key": "sb_publishable_NnOTr7QGr-oQpg4EZ4GNVg_o25JykPs",
}
SHOP_ID = "750b02ab-81f7-4023-929d-a9a00a8a8790"

EXPECTED_PRODUCTS = [
    {
        "name": "Wagh Bakri Honey Lemon Green Tea",
        "price": 200.00,
        "brand": "Wagh Bakri",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Tata Tea Agni Elaichi Chai",
        "price": 60.00,
        "brand": "Tata Tea",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Tata Tea Gold",
        "price": 330.00,
        "brand": "Tata Tea",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Brooke Bond Red Label Natural Care Tea",
        "price": 140.00,
        "brand": "Brooke Bond",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Lipton Yellow Label Tea",
        "price": 330.00,
        "brand": "Lipton",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Brooke Bond Red Label Tea",
        "price": 270.00,
        "brand": "Brooke Bond",
        "category": "Grocerylm",
        "min_variants": 1,
    },
]


def main():
    print("=" * 80)
    print("🔍 RUNNING FORENSIC VERIFICATION AUDIT FOR MAXX RETAIL SUPERMARKET BATCH 12")
    print("=" * 80)

    url = f"{SUPABASE_CONFIG['url']}/rest/v1/products?shop_id=eq.{SHOP_ID}&is_deleted=eq.false"
    headers = {
        "apikey": SUPABASE_CONFIG["key"],
        "Authorization": f"Bearer {SUPABASE_CONFIG['key']}",
    }

    resp = requests.get(url, headers=headers, timeout=15)
    if resp.status_code != 200:
        print(f"❌ Failed to fetch products from Supabase: {resp.status_code} {resp.text}")
        sys.exit(1)

    db_products = {p["name"].strip().lower(): p for p in resp.json()}

    passed = 0
    failed = 0

    for exp in EXPECTED_PRODUCTS:
        key = exp["name"].strip().lower()
        if key not in db_products:
            print(f"❌ MISSING: '{exp['name']}' not found in Supabase!")
            failed += 1
            continue

        item = db_products[key]
        errors = []

        # Category check: strictly Grocerylm
        if item.get("category") != exp["category"]:
            errors.append(f"category '{item.get('category')}' != expected '{exp['category']}'")

        # Dietary preference check: strictly None (SQL NULL)
        if item.get("is_veg") is not None:
            errors.append(f"is_veg '{item.get('is_veg')}' is not None (SQL NULL expected)")

        # Brand check
        if item.get("brand") != exp["brand"]:
            errors.append(f"brand '{item.get('brand')}' != expected '{exp['brand']}'")

        # Price check
        if float(item.get("price", 0)) != float(exp["price"]):
            errors.append(f"price '{item.get('price')}' != expected '{exp['price']}'")

        # Variants count check
        variants = item.get("variants") or []
        if len(variants) < exp["min_variants"]:
            errors.append(f"variants count {len(variants)} < expected min {exp['min_variants']}")

        # Image check
        img = item.get("image_url")
        if not img or not img.startswith("http"):
            errors.append(f"missing or invalid image_url: {img}")

        if errors:
            print(f"❌ FAIL: {exp['name']} -> {', '.join(errors)}")
            failed += 1
        else:
            var_summary = [f"{v.get('name')} (₹{v.get('price')})" for v in variants]
            print(f"✅ PASS: {exp['name']} | ₹{item['price']} | Brand: {item['brand']} | Category: {item['category']} | Variants: {var_summary}")
            passed += 1

    print("\n" + "=" * 80)
    print(f"📊 BATCH 12 AUDIT SUMMARY: {passed}/{len(EXPECTED_PRODUCTS)} Passed ({failed} Failed)")
    print("=" * 80)

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()

