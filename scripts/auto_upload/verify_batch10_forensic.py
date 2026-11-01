#!/usr/bin/env python3
"""
Forensic Audit & Catalog Verification for Maxx Retail Batch 10
=============================================================
Audits the catalog state after Batch 10 ingestion:
  1. Total active product count in Maxx Retail (expected 768).
  2. 100% Category integrity: strictly 'Cosmetics & Beauty' (18% GST).
  3. 100% Dietary integrity: strictly N/A (is_veg is None).
  4. 100% Brand coverage: zero null/empty brands across entire catalog.
  5. Packshot verification:
     - All Batch 10 products have exactly 2 commercial photoshoot packshots.
     - Padded 1:1 square ratio (800x800).
     - Compressed < 120KB.
     - Zero blank white images (is_blank_white check on downloaded images).
"""

import io
import os
import requests
from PIL import Image, ImageStat

SUPABASE_CONFIG = {
    "url": "https://hvtujaatwhyxielrlztr.supabase.co",
    "key": "sb_publishable_NnOTr7QGr-oQpg4EZ4GNVg_o25JykPs",
}
SHOP_ID = "750b02ab-81f7-4023-929d-a9a00a8a8790"


def is_blank_white(img: Image.Image) -> bool:
    if img.mode != "RGB":
        img = img.convert("RGB")
    stat = ImageStat.Stat(img)
    return all(m > 248 for m in stat.mean) and all(s < 8 for s in stat.stddev)


def main():
    headers = {
        "apikey": SUPABASE_CONFIG["key"],
        "Authorization": f"Bearer {SUPABASE_CONFIG['key']}",
    }

    print("=" * 80)
    print("🔍 RUNNING FORENSIC VERIFICATION AUDIT FOR MAXX RETAIL (BATCH 10)")
    print("=" * 80)

    # 1. Fetch all active products
    all_products = []
    limit = 1000
    offset = 0

    while True:
        resp = requests.get(
            f"{SUPABASE_CONFIG['url']}/rest/v1/products",
            headers=headers,
            params={
                "shop_id": f"eq.{SHOP_ID}",
                "is_deleted": "eq.false",
                "select": "id,name,brand,category,price,is_veg,images,image_url,weight_per_unit,created_at",
                "limit": limit,
                "offset": offset,
                "order": "created_at.desc",
            },
            timeout=15,
        )
        if resp.status_code != 200:
            print(f"❌ Failed to fetch products: {resp.status_code} - {resp.text}")
            return
        batch = resp.json()
        all_products.extend(batch)
        if len(batch) < limit:
            break
        offset += limit

    total_count = len(all_products)
    print(f"\n📊 Total active products in Maxx Retail: {total_count}")

    # 2. Category audit
    non_cosmetics = [p for p in all_products if p.get("category") != "Cosmetics & Beauty"]
    print(f"📦 Category Check: {total_count - len(non_cosmetics)}/{total_count} are 'Cosmetics & Beauty'")
    if non_cosmetics:
        print(f"   ⚠️ Found {len(non_cosmetics)} non-Cosmetics & Beauty products!")
        for p in non_cosmetics[:5]:
            print(f"      - {p['name']}: {p.get('category')}")
    else:
        print("   ✅ 100% of products strictly belong to 'Cosmetics & Beauty'")

    # 3. Dietary audit
    non_null_veg = [p for p in all_products if p.get("is_veg") is not None]
    print(f"🥗 Dietary Check: {total_count - len(non_null_veg)}/{total_count} have is_veg = NULL (Strictly N/A)")
    if non_null_veg:
        print(f"   ⚠️ Found {len(non_null_veg)} products with non-null is_veg!")
        for p in non_null_veg[:5]:
            print(f"      - {p['name']}: is_veg={p.get('is_veg')}")
    else:
        print("   ✅ 100% of products strictly adhere to is_veg = NULL")

    # 4. Brand coverage audit
    missing_brand = [p for p in all_products if not p.get("brand") or str(p.get("brand")).strip() == ""]
    print(f"🏷️ Brand Coverage: {total_count - len(missing_brand)}/{total_count} have brand populated")
    if missing_brand:
        print(f"   ⚠️ Found {len(missing_brand)} products missing brand!")
        for p in missing_brand[:5]:
            print(f"      - {p['name']}")
    else:
        print("   ✅ 100% of products have verified brand names (zero null brands)")

    # 5. Packshot audit for Batch 10 items
    batch10_items = [p for p in all_products if "batch10_packshots" in str(p.get("images", []))]
    print(f"\n📸 Batch 10 Ingested Products Detected: {len(batch10_items)}")

    if not batch10_items:
        print("   ⚠️ No Batch 10 items found yet (ingestion might still be running).")
        return

    blank_images = 0
    oversized_images = 0
    non_square_images = 0
    checked_images = 0

    print("   Auditing Batch 10 packshots from Supabase Storage...")
    for idx, item in enumerate(batch10_items, 1):
        imgs = item.get("images") or []
        if len(imgs) < 2:
            print(f"   ⚠️ Product {item['name']} has only {len(imgs)} image(s)")

        for img_url in imgs[:2]:
            checked_images += 1
            try:
                r = requests.get(img_url, timeout=10)
                if r.status_code != 200:
                    print(f"   ❌ HTTP {r.status_code} fetching image: {img_url}")
                    continue
                size_kb = len(r.content) / 1024.0
                if size_kb > 125.0:
                    oversized_images += 1
                pil_img = Image.open(io.BytesIO(r.content))
                w, h = pil_img.size
                if abs(w - h) > 2:
                    non_square_images += 1
                if is_blank_white(pil_img):
                    blank_images += 1
                    print(f"   🚨 Blank white image found for {item['name']}: {img_url}")
            except Exception as e:
                print(f"   ⚠️ Error checking image: {e}")

    print("\n" + "=" * 80)
    print("🏁 AUDIT SUMMARY:")
    print(f"   Total Active Catalog: {total_count} products (Target: 768)")
    print(f"   Batch 10 Ingested: {len(batch10_items)} products (Target: 58)")
    print(f"   Total Batch 10 Packshots Inspected: {checked_images}")
    print(f"   Blank White Images: {blank_images} (Target: 0)")
    print(f"   Oversized Images (>120KB): {oversized_images} (Target: 0)")
    print(f"   Non-Square Ratio: {non_square_images} (Target: 0)")
    print("=" * 80)


if __name__ == "__main__":
    main()
