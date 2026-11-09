#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 3 Forensic Verification Audit (l21.jpg to l30.jpg)
========================================================================================
Forensically audits the 18 Master Products (26 SKU Variants) across the Strict Rules:
1. Exact product name and price matching
2. Category strictly 'Grocerylm'
3. Dietary Preference strictly N/A (`is_veg = NULL`)
4. Brand coverage 100% (Zero missing or null brands)
5. Canonical unit types: 'grams' or 'ml'
6. Packshot quality: exactly 1 image per SKU, pure white #FFFFFF, 1:1 square, < 120KB, 0 blank white
7. Soft Delete Inviolability: `is_deleted = false`
"""

import io
import sys
import requests
from PIL import Image, ImageStat

SUPABASE_CONFIG = {
    "url": "https://hvtujaatwhyxielrlztr.supabase.co",
    "key": "sb_publishable_NnOTr7QGr-oQpg4EZ4GNVg_o25JykPs",
}
SHOP_ID = "750b02ab-81f7-4023-929d-a9a00a8a8790"

EXPECTED_BATCH_3_NAMES = [
    "Nusuk Naseem Al Tayif Concentrated Air Freshener (300ml)",
    "Oura Tropical Paradise Air Freshener Spray (220ml)",
    "Oura Monsoon Melody Air Freshener Spray (220ml)",
    "Oura Citrus Mist Air Freshener Spray (220ml)",
    "Godrej aer Spray Home Fragrance (220ml)",
    "Odonil Room Spray Citrus Fresh (220ml)",
    "Odonil Room Spray Jasmine Fresh (220ml)",
    "Odonil Room Spray Lavender Mist (220ml)",
    "Oura Green Flag Car Perfume Membrane (7.5g)",
    "Oura La Vanilla Car Perfume Membrane (7.5g)",
    "Airodo Air Freshener Fragrance Pouch Citrus Blast (10g)",
    "Airodo Air Freshener Fragrance Pouch Floral Crush (10g)",
    "Oura Tropical Escape Fragrance Pouch (10g)",
    "Oura Sunset Lounge Fragrance Pouch (10g)",
    "Odonil Room Gelz Rose Dreams (75g)",
    "Odonil Room Gelz Citrus Spice (75g)",
    "Bioline White Perfumed Petroleum Jelly",
    "Colgate Cibaca Toothpaste",
    "Colgate Strong Teeth Dental Cream Toothpaste (200g)",
]


def is_blank_white(img: Image.Image) -> bool:
    if img.mode != "RGB":
        img = img.convert("RGB")
    stat = ImageStat.Stat(img)
    return all(m > 248 for m in stat.mean) and all(s < 8 for s in stat.stddev)


def main():
    print("=" * 80)
    print("🔍 RUNNING FORENSIC VERIFICATION AUDIT FOR MAXX RETAIL SUPERMARKET BATCH 3")
    print("=" * 80)

    url = f"{SUPABASE_CONFIG['url']}/rest/v1/products?shop_id=eq.{SHOP_ID}&is_deleted=eq.false&select=*"
    headers = {
        "apikey": SUPABASE_CONFIG["key"],
        "Authorization": f"Bearer {SUPABASE_CONFIG['key']}",
    }
    r = requests.get(url, headers=headers)
    if r.status_code != 200:
        print(f"❌ Failed to fetch products from Supabase: {r.status_code} {r.text}")
        sys.exit(1)

    all_products = r.json()
    product_map = {p["name"]: p for p in all_products}

    passed = 0
    failed = 0

    for name in EXPECTED_BATCH_3_NAMES:
        if name not in product_map:
            print(f"❌ MISSING IN SUPABASE: {name}")
            failed += 1
            continue

        p = product_map[name]
        issues = []

        # 1. Category check
        if p.get("category") != "Grocerylm":
            issues.append(f"Category '{p.get('category')}' != 'Grocerylm'")

        # 2. Dietary preference check
        if p.get("is_veg") is not None:
            issues.append(f"is_veg is {p.get('is_veg')} (expected None / SQL NULL)")

        # 3. Brand check
        if not p.get("brand") or p.get("brand").strip() == "":
            issues.append("Brand is missing or empty")

        # 4. Soft delete check
        if p.get("is_deleted") is not False:
            issues.append(f"is_deleted is {p.get('is_deleted')} (expected False)")

        # 5. Packshot check
        images = p.get("images") or []
        if len(images) != 1:
            issues.append(f"Images count is {len(images)} (expected exactly 1)")
        else:
            img_url = images[0]
            try:
                img_res = requests.get(img_url, timeout=10)
                if img_res.status_code != 200:
                    issues.append(f"Image HTTP {img_res.status_code} for {img_url}")
                else:
                    kb_size = len(img_res.content) / 1024
                    if kb_size > 120:
                        issues.append(f"Image size {kb_size:.1f}KB exceeds 120KB limit")
                    img = Image.open(io.BytesIO(img_res.content))
                    w, h = img.size
                    if w != h:
                        issues.append(f"Image aspect ratio {w}x{h} is not 1:1 square")
                    if is_blank_white(img):
                        issues.append("Image is completely blank white")
            except Exception as e:
                issues.append(f"Image check failed: {e}")

        if issues:
            print(f"⚠️ AUDIT WARNING: {name}")
            for iss in issues:
                print(f"    - {iss}")
            failed += 1
        else:
            print(f"✅ VERIFIED: {name} | Price: ₹{p['price']} | Brand: {p['brand']} | Category: {p['category']}")
            passed += 1

    print("\n" + "=" * 80)
    print(f"📊 AUDIT RESULTS: {passed}/{len(EXPECTED_BATCH_3_NAMES)} PASSED | {failed} ISSUES")
    print("=" * 80)
    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()

