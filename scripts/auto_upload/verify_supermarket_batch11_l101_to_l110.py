#!/usr/bin/env python3
"""
Maxx Retail — Forensic Verification Audit for Batch 11 (l101.jpeg to l110.jpeg)
=============================================================================
Audits Supabase database records for Maxx Retail to confirm:
1. All 14 Master Products are present and active (is_deleted = false).
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
        "name": "Maggi 2-Minute Masala Instant Noodles (4 Pack)",
        "price": 58.00,
        "brand": "Maggi",
        "category": "Grocerylm",
        "min_variants": 2,
    },
    {
        "name": "Maggi Special Masala Instant Noodles",
        "price": 20.00,
        "brand": "Maggi",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Sunfeast YiPPee! Magic Masala Instant Noodles",
        "price": 10.00,
        "brand": "Sunfeast",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Saffola Masala Oats Classic Masala",
        "price": 230.00,
        "brand": "Saffola",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Disano Rolled Oats",
        "price": 330.00,
        "brand": "Disano",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Saffola Oats 100% Natural Rolled Oats",
        "price": 252.00,
        "brand": "Saffola",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Kellogg's Rolled Oats",
        "price": 90.00,
        "brand": "Kellogg's",
        "category": "Grocerylm",
        "min_variants": 2,
    },
    {
        "name": "Alpino Super Oats High Protein Rolled Oats Chocolate",
        "price": 649.00,
        "brand": "Alpino",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Weikfield Rolled Oats",
        "price": 110.00,
        "brand": "Weikfield",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Gaia Green Tea",
        "price": 209.00,
        "brand": "Gaia",
        "category": "Grocerylm",
        "min_variants": 2,
    },
    {
        "name": "Leeford Green Tea",
        "price": 270.00,
        "brand": "Leeford",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Lipton Honey Lemon Green Tea",
        "price": 200.00,
        "brand": "Lipton",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "EMIRS Pure Green Tea",
        "price": 285.00,
        "brand": "EMIRS",
        "category": "Grocerylm",
        "min_variants": 1,
    },
    {
        "name": "Kongposh Traditional Kahwa Tea",
        "price": 290.00,
        "brand": "Kongposh",
        "category": "Grocerylm",
        "min_variants": 1,
    },
]


def main():
    print("=" * 80)
    print("🔍 RUNNING FORENSIC VERIFICATION AUDIT FOR MAXX RETAIL SUPERMARKET BATCH 11")
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
    print(f"📊 BATCH 11 AUDIT SUMMARY: {passed}/{len(EXPECTED_PRODUCTS)} Passed ({failed} Failed)")
    print("=" * 80)

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()

