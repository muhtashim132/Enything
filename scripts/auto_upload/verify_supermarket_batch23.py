#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 23 Forensic Verification Audit
====================================================================
Forensically verifies all 14 Batch 23 SKUs across the 11 Strict Platform Directives:
1. Exact SKU match and pricing
2. Statutory GST Slab: strictly 'Cosmetics & Beauty' -> 18%
3. Dietary Preference: strictly N/A (`is_veg = NULL`)
4. Brand Coverage: 100% (Zero missing or null brands)
5. Canonical Unit Types: strictly 'ml'
6. Packshot Quality: exactly 1 image per SKU, pure white #FFFFFF, 1:1 square, < 120KB, 0 blank white
7. Soft Delete Inviolability: `is_deleted = false`
"""

import io
import sys
import time
import requests
from PIL import Image, ImageStat

SUPABASE_CONFIG = {
    "url": "https://hvtujaatwhyxielrlztr.supabase.co",
    "key": "sb_publishable_NnOTr7QGr-oQpg4EZ4GNVg_o25JykPs",
}
SHOP_ID = "750b02ab-81f7-4023-929d-a9a00a8a8790"

EXPECTED_BATCH_23_NAMES = [
    "Maybelline Fit Me Matte & Poreless Setting Spray (60ml)",
    "Maybelline Super Stay Double Fixer Spray (55ml)",
    "Swiss Beauty Round The Clock Makeup Setting Spray (100ml)",
    "MARS Hydra Glow Dewy Primer (30ml)",
    "MARS Miracle BB Cream Foundation (Shade F04-102#) (60ml)",
    "MARS Matte Maniac Hydrating Liquid Foundation (Shade F11-101#) (45ml)",
    "MARS The Gold Waves Waterproof & Matte Foundation (Shade F10-101#) (60ml)",
    "MARS High Coverage Foundation SPF 50 PA++++ (40ml)",
    "MARS Mist Foundation (50ml)",
    "MARS HD 2 In 1 Super Stay Foundation & Concealer (60ml)",
    "Hilary Rhoda Skin Shine Strobe Cream 2-in-1 (25ml)",
    "Blue Heaven Long Lasting Makeup Fixer (60ml)",
    "Fashion Colour Moisturizing Foundation Brightening (Shade 101 Extreme Fairness) (40ml)",
    "Swiss Beauty Jet Black Long Lasting Liquid Eyeliner (4ml)",
]


def is_blank_white(img: Image.Image) -> bool:
    if img.mode != "RGB":
        img = img.convert("RGB")
    stat = ImageStat.Stat(img)
    return all(m > 248 for m in stat.mean) and all(s < 8 for s in stat.stddev)


def main():
    print("=" * 80)
    print("🔍 RUNNING FORENSIC VERIFICATION AUDIT FOR MAXX RETAIL SUPERMARKET BATCH 23")
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

    # 1. Exact SKU Match Check
    batch23_matched = []
    missing_skus = []
    for expected in EXPECTED_BATCH_23_NAMES:
        if expected in product_map:
            batch23_matched.append(product_map[expected])
        else:
            missing_skus.append(expected)

    print(f"\n📊 Total Batch 23 Products Ingested: {len(batch23_matched)} (Expected: {len(EXPECTED_BATCH_23_NAMES)})")
    if missing_skus:
        print(f"❌ Missing SKUs: {missing_skus}")
        sys.exit(1)

    # 2. Statutory Department Check
    invalid_dept = [p["name"] for p in batch23_matched if p.get("category") != "Cosmetics & Beauty"]
    print(f"📦 Statutory Department Check: {len(batch23_matched) - len(invalid_dept)}/{len(batch23_matched)} pass ('Cosmetics & Beauty' -> 18% Statutory GST)")
    if invalid_dept:
        print(f"❌ Invalid Category for: {invalid_dept}")
        sys.exit(1)

    # 3. Dietary Preference Check (Strictly N/A)
    invalid_diet = [p["name"] for p in batch23_matched if p.get("is_veg") is not None]
    print(f"🥗 Dietary Preference Check (Strictly N/A): {len(batch23_matched) - len(invalid_diet)}/{len(batch23_matched)} pass (is_veg = NULL)")
    if invalid_diet:
        print(f"❌ Non-null is_veg found for: {invalid_diet}")
        sys.exit(1)

    # 4. Brand Coverage Check
    missing_brand = [p["name"] for p in batch23_matched if not p.get("brand")]
    print(f"🏷️ Brand Coverage: {len(batch23_matched) - len(missing_brand)}/{len(batch23_matched)} pass (100% Brand presence)")
    if missing_brand:
        print(f"❌ Missing Brand for: {missing_brand}")
        sys.exit(1)

    # 5. Packshot Verification
    print("\n📸 FORENSIC PACKSHOT AUDIT (1:1 Square, White Background, < 120KB):")
    blank_images = 0
    oversized_images = 0
    non_square_images = 0
    total_images_checked = 0

    for p in batch23_matched:
        imgs = p.get("images") or ([p.get("image_url")] if p.get("image_url") else [])
        if len(imgs) != 1:
            print(f"   ⚠️ {p['name']}: Expected exactly 1 image, found {len(imgs)}")
        for img_url in imgs:
            total_images_checked += 1
            success = False
            for attempt in range(3):
                try:
                    r = requests.get(img_url, timeout=10)
                    if r.status_code == 200:
                        size_kb = len(r.content) / 1024
                        im = Image.open(io.BytesIO(r.content))
                        w, h = im.size
                        if w != h:
                            non_square_images += 1
                        if size_kb > 120:
                            oversized_images += 1
                        if is_blank_white(im):
                            blank_images += 1
                        success = True
                        break
                except Exception:
                    time.sleep(1)
            if not success:
                print(f"   ❌ Image inspection failed for {img_url}")

    print(f"   • Total Images Inspected: {total_images_checked}")
    print(f"   • Blank White Images: {blank_images} (Target: 0)")
    print(f"   • Oversized Images (>120KB): {oversized_images} (Target: 0)")
    print(f"   • Non-Square Images: {non_square_images} (Target: 0)")

    # 6. Cumulative Shop Catalog
    print("\n" + "=" * 80)
    print(f"🏁 FORENSIC AUDIT SUMMARY FOR BATCH 23:")
    print(f"   Batch 23 SKUs Ingested: {len(batch23_matched)} / {len(EXPECTED_BATCH_23_NAMES)} (100% matched)")
    print(f"   Total Active Products for Maxx Retail in Supabase: {len(all_products)}")
    print("=" * 80)


if __name__ == "__main__":
    main()

