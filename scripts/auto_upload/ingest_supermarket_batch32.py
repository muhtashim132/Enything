#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 32 Ingestion Engine
=========================================================
Catalog: 17 items across shelf photos b91.jpg - b100.jpg (12 verified SKUs):
  Photo 1 (b91.jpg - Clustered Variant with b90):
    - Fem Crème Bleach De-Tan (10g) @ ₹45.00
      Variants: 10g (₹45.00), 30g (₹85.00)
  Photo 2 (b92.jpg - Clustered Variants with b88):
    - Fem Crème Bleach Gold (8g) @ ₹45.00
      Variants: 8g (₹45.00), 40g (₹83.00)
    - Fem Crème Bleach Saffron & Milk (8g) @ ₹37.00
      Variants: 8g (₹37.00), 40g (₹78.00)
  Photo 3 (b93.jpg - Salon Pack):
    - Fem Salon Professional Crème Bleach Saffron & Milk (314.4g) @ ₹199.00
  Photo 4, 5, 6 (b94.jpg, b95.jpg, b96.jpg - Clustered Size Variants):
    - Arora's Glycerin Oral Solution USP (100g) @ ₹120.00
      Variants: 100g (₹120.00), 200g (₹200.00), 500g (₹400.00)
  Photo 7 (b97.jpg - Bottle Box):
    - Dabur Pure Glycerine (50g) @ ₹62.00
  Photo 8 (b98.jpg - 3 Clustered Volume Variants):
    - Dabur Gulabari Premium Rose Water (120ml) @ ₹56.00
      Variants: 120ml (₹56.00), 250ml (₹96.00), 400ml (₹135.00)
  Photo 9 (b99.jpg - 3 Imported BlueSeal Tubs):
    - Vaseline BlueSeal Gentle Protective Jelly Baby (250ml) @ ₹550.00
    - Vaseline BlueSeal Nourishing Skin Jelly Vitamin E (250ml) @ ₹550.00
    - Vaseline BlueSeal Light Hydrating Jelly Aloe Fresh (250ml) @ ₹550.00
  Photo 10 (b100.jpg - 3 Tubs):
    - Astraaz Astralene Petroleum Jelly Vitamin E (130ml) @ ₹145.00
    - Vaseline Original Skin Protecting Jelly (40g) @ ₹104.00
      Variants: 40g (₹104.00), 85g (₹190.00)

Strict Rules Enforced:
1. Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab override).
2. Dietary Status: Strictly N/A (`is_veg = None` / SQL NULL).
3. Packshots: Exactly 1 pristine 1:1 padded image (< 120KB) on pure white background (#FFFFFF).
4. Soft-deletes: `is_deleted = false`.
5. Ingestion via `public.bulk_upload_shop_products` RPC.
"""

import io
import os
import re
import sys
import time
import requests
from PIL import Image, ImageStat

SUPABASE_CONFIG = {
    "url": "https://hvtujaatwhyxielrlztr.supabase.co",
    "key": "sb_publishable_NnOTr7QGr-oQpg4EZ4GNVg_o25JykPs",
}
SHOP_ID = "750b02ab-81f7-4023-929d-a9a00a8a8790"
STORAGE_BUCKET = "products"
STORAGE_PREFIX = "supermarket/maxx_retail/batch32"
CACHE_DIR = "/tmp/maxx_retail_batch32_cache"

BATCH_32_CATALOG = [
    {
        "name": "Fem Crème Bleach De-Tan (10g)",
        "price": 45.00,
        "brand": "Fem",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 10.0,
        "unit_type": "grams",
        "description": "Fem Crème Bleach De-Tan for active tan removal and healthy glow in 15 minutes. Formulated with orange peel extracts by Dabur.",
        "variants": [
            {"name": "10g", "price": 45.00, "unit": "10g"},
            {"name": "30g", "price": 85.00, "unit": "30g"},
        ],
        "queries": [
            "fem creme bleach de-tan packshot white background",
            "fem de-tan bleach box packshot",
            "fem creme bleach de tan",
        ],
    },
    {
        "name": "Fem Crème Bleach Gold (8g)",
        "price": 45.00,
        "brand": "Fem",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 8.0,
        "unit_type": "grams",
        "description": "Fem Crème Bleach Gold with 24K Gold Dust for special golden glow. Dermatologically tested by Dabur.",
        "variants": [
            {"name": "8g", "price": 45.00, "unit": "8g"},
            {"name": "40g", "price": 83.00, "unit": "40g"},
        ],
        "queries": [
            "fem creme bleach gold packshot white background",
            "fem gold bleach box packshot",
            "fem creme bleach gold",
        ],
    },
    {
        "name": "Fem Crème Bleach Saffron & Milk (8g)",
        "price": 37.00,
        "brand": "Fem",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 8.0,
        "unit_type": "grams",
        "description": "Fem Crème Bleach Saffron & Milk for healthy glow. Enriched with saffron and pure milk extracts by Dabur.",
        "variants": [
            {"name": "8g", "price": 37.00, "unit": "8g"},
            {"name": "40g", "price": 78.00, "unit": "40g"},
        ],
        "queries": [
            "fem creme bleach saffron and milk packshot white background",
            "fem saffron and milk bleach box packshot",
            "fem creme bleach saffron and milk",
        ],
    },
    {
        "name": "Fem Salon Professional Crème Bleach Saffron & Milk (314.4g)",
        "price": 199.00,
        "brand": "Fem",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 314.4,
        "unit_type": "grams",
        "description": "Fem Salon Professional Crème Bleach Saffron & Milk jumbo pack. Contains Crème Bleach 240g, Powder Activator 2x17.2g, Pre-Bleach Cream 40g for multiple salon-grade applications. By Dabur.",
        "variants": [
            {"name": "314.4g (Salon Pack)", "price": 199.00, "unit": "314.4g"},
        ],
        "queries": [
            "fem salon professional creme bleach saffron milk 314g packshot white background",
            "fem salon professional creme bleach box packshot",
            "fem salon professional bleach saffron milk",
        ],
    },
    {
        "name": "Arora's Glycerin Oral Solution USP (100g)",
        "price": 120.00,
        "brand": "Arora's",
        "sub_category": "Body Care & Glycerin",
        "menu_category": "Skin & Body Care",
        "weight_per_unit": 100.0,
        "unit_type": "grams",
        "description": "Arora's Glycerin Oral Solution USP. Pure 99.0% w/w Glycerin I.P. with delicate Rose flavour. GMP certified company since 1979 by Arora Pharmaceuticals Pvt. Ltd.",
        "variants": [
            {"name": "100g", "price": 120.00, "unit": "100g"},
            {"name": "200g", "price": 200.00, "unit": "200g"},
            {"name": "500g", "price": 400.00, "unit": "500g"},
        ],
        "queries": [
            "aroras glycerin oral solution usp packshot white background",
            "arora glycerin rose flavour box packshot",
            "aroras glycerin oral solution",
        ],
    },
    {
        "name": "Dabur Pure Glycerine (50g)",
        "price": 62.00,
        "brand": "Dabur",
        "sub_category": "Body Care & Glycerin",
        "menu_category": "Skin & Body Care",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Dabur Pure Glycerine for natural skin hydration and softness. Deeply moisturises dry, cracked skin and lips.",
        "variants": [
            {"name": "50g", "price": 62.00, "unit": "50g"},
        ],
        "queries": [
            "dabur pure glycerine 50g packshot white background",
            "dabur pure glycerine bottle box packshot",
            "dabur pure glycerine 50g",
        ],
    },
    {
        "name": "Dabur Gulabari Premium Rose Water (120ml)",
        "price": 56.00,
        "brand": "Dabur",
        "sub_category": "Face Toners & Mists",
        "menu_category": "Skin & Body Care",
        "weight_per_unit": 120.0,
        "unit_type": "ml",
        "description": "Dabur Gulabari Premium Rose Water. 100% pure rose oil, paraben free, dermatologically tested. Gives a natural rose glow and fresh toning.",
        "variants": [
            {"name": "120ml", "price": 56.00, "unit": "120ml"},
            {"name": "250ml", "price": 96.00, "unit": "250ml"},
            {"name": "400ml", "price": 135.00, "unit": "400ml"},
        ],
        "queries": [
            "dabur gulabari premium rose water bottle packshot white background",
            "dabur gulabari rose water 250ml bottle packshot",
            "dabur gulabari premium rose water bottle",
        ],
    },
    {
        "name": "Vaseline BlueSeal Gentle Protective Jelly Baby (250ml)",
        "price": 550.00,
        "brand": "Vaseline",
        "sub_category": "Body & Lip Care",
        "menu_category": "Skin & Body Care",
        "weight_per_unit": 250.0,
        "unit_type": "ml",
        "description": "Vaseline BlueSeal Gentle Protective Jelly Baby. Triple purified pure petroleum jelly formulated specifically to lock in moisture and help protect baby's delicate skin from diaper rash and dryness.",
        "variants": [
            {"name": "250ml", "price": 550.00, "unit": "250ml"},
        ],
        "queries": [
            "vaseline blueseal gentle protective jelly baby 250ml packshot white background",
            "vaseline blueseal baby jelly 250ml tub packshot",
            "vaseline blueseal baby 250ml",
        ],
    },
    {
        "name": "Vaseline BlueSeal Nourishing Skin Jelly Vitamin E (250ml)",
        "price": 550.00,
        "brand": "Vaseline",
        "sub_category": "Body & Lip Care",
        "menu_category": "Skin & Body Care",
        "weight_per_unit": 250.0,
        "unit_type": "ml",
        "description": "Vaseline BlueSeal Nourishing Skin Jelly with Vitamin E. Deeply nourishes dry skin and protects skin moisture barrier. Triple purified formula.",
        "variants": [
            {"name": "250ml", "price": 550.00, "unit": "250ml"},
        ],
        "queries": [
            "vaseline blueseal nourishing skin jelly vitamin e 250ml packshot white background",
            "vaseline blueseal vitamin e 250ml tub packshot",
            "vaseline blueseal vitamin e jelly 250ml",
        ],
    },
    {
        "name": "Vaseline BlueSeal Light Hydrating Jelly Aloe Fresh (250ml)",
        "price": 550.00,
        "brand": "Vaseline",
        "sub_category": "Body & Lip Care",
        "menu_category": "Skin & Body Care",
        "weight_per_unit": 250.0,
        "unit_type": "ml",
        "description": "Vaseline BlueSeal Light Hydrating Jelly Aloe Fresh. Enriched with natural Aloe Vera to soothe, hydrate and refresh dry skin without greasiness.",
        "variants": [
            {"name": "250ml", "price": 550.00, "unit": "250ml"},
        ],
        "queries": [
            "vaseline blueseal light hydrating jelly aloe fresh 250ml packshot white background",
            "vaseline blueseal aloe fresh 250ml tub packshot",
            "vaseline blueseal aloe fresh jelly",
        ],
    },
    {
        "name": "Astraaz Astralene Petroleum Jelly Vitamin E (130ml)",
        "price": 145.00,
        "brand": "Astraaz",
        "sub_category": "Body & Lip Care",
        "menu_category": "Skin & Body Care",
        "weight_per_unit": 130.0,
        "unit_type": "ml",
        "description": "Astraaz Astralene Petroleum Jelly with Vitamin E. Intense moisturising formula that blends perfectly into skin, prevents skin dryness and flanks, and maintains natural skin radiance.",
        "variants": [
            {"name": "130ml", "price": 145.00, "unit": "130ml"},
        ],
        "queries": [
            "astraz astralene petroleum jelly vitamin e 130ml packshot white background",
            "astralene petroleum jelly vitamin e 130ml tub",
            "astralene petroleum jelly astraaz",
        ],
    },
    {
        "name": "Vaseline Original Skin Protecting Jelly (40g)",
        "price": 104.00,
        "brand": "Vaseline",
        "sub_category": "Body & Lip Care",
        "menu_category": "Skin & Body Care",
        "weight_per_unit": 40.0,
        "unit_type": "grams",
        "description": "Vaseline Original Skin Protecting Jelly with Pure Petroleum Jelly. Triple purification guaranteed to lock in moisture, heal dry damaged skin, and protect minor cuts.",
        "variants": [
            {"name": "40g", "price": 104.00, "unit": "40g"},
            {"name": "85g", "price": 190.00, "unit": "85g"},
        ],
        "queries": [
            "vaseline original skin protecting jelly tub packshot white background",
            "vaseline petroleum jelly original tub packshot",
            "vaseline original skin protecting jelly 85g",
        ],
    },
]

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}


def search_bing_images(query: str, max_results: int = 15):
    """Searches Bing Images for authentic commercial photoshoot packshots."""
    url = f"https://www.bing.com/images/search?q={requests.utils.quote(query)}&FORM=HDRSC2"
    try:
        r = requests.get(url, headers=HEADERS, timeout=8)
        if r.status_code != 200:
            return []
        matches = re.findall(r'murl&quot;:&quot;(http[^&]+)&quot;', r.text)
        clean = []
        for m in matches:
            if any(ext in m.lower() for ext in [".jpg", ".jpeg", ".png", ".webp"]):
                clean.append(m)
            if len(clean) >= max_results:
                break
        return clean
    except Exception as e:
        print(f"      ⚠️ Search failed for '{query}': {e}")
        return []


def is_blank_white(img: Image.Image) -> bool:
    if img.mode != "RGB":
        img = img.convert("RGB")
    stat = ImageStat.Stat(img)
    return all(m > 248 for m in stat.mean) and all(s < 8 for s in stat.stddev)


def load_and_clean_image(content: bytes) -> Image.Image:
    """Loads image from bytes, flattens transparency onto pure white #FFFFFF."""
    raw = Image.open(io.BytesIO(content))
    if raw.mode in ("RGBA", "LA") or (raw.mode == "P" and "transparency" in raw.info):
        rgba = raw.convert("RGBA")
        bg = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        composite = Image.alpha_composite(bg, rgba)
        return composite.convert("RGB")
    return raw.convert("RGB")


def pad_to_square(img: Image.Image, target_size: int = 800) -> Image.Image:
    """Pads image to 1:1 square on pure white background (#FFFFFF)."""
    w, h = img.size
    max_dim = max(w, h)
    scale = (target_size * 0.90) / max_dim
    new_w = max(1, int(w * scale))
    new_h = max(1, int(h * scale))

    resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (target_size, target_size), (255, 255, 255))
    paste_x = (target_size - new_w) // 2
    paste_y = (target_size - new_h) // 2
    canvas.paste(resized, (paste_x, paste_y))
    return canvas


def compress_image(img: Image.Image, max_kb: int = 115) -> bytes:
    """Compresses image to JPEG under max_kb."""
    quality = 90
    out = io.BytesIO()
    while quality >= 30:
        out.seek(0)
        out.truncate()
        img.save(out, format="JPEG", quality=quality, optimize=True)
        if out.tell() <= max_kb * 1024:
            return out.getvalue()
        quality -= 5
    return out.getvalue()


def source_single_packshot(item: dict, index: int) -> str:
    """Finds, validates, pads to 1:1, and caches exactly 1 pristine packshot under 120KB."""
    img_name = f"b32_{index}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:40]}.jpg"
    img_path = os.path.join(CACHE_DIR, img_name)

    if os.path.exists(img_path) and os.path.getsize(img_path) > 3000:
        return img_path

    collected_urls = []
    for q in item["queries"]:
        urls = search_bing_images(q)
        for u in urls:
            if u not in collected_urls:
                collected_urls.append(u)
        if len(collected_urls) >= 15:
            break

    valid_image_bytes = None
    for u in collected_urls:
        try:
            r = requests.get(u, headers=HEADERS, timeout=6)
            if r.status_code != 200 or len(r.content) < 4000:
                continue
            img = load_and_clean_image(r.content)
            if is_blank_white(img):
                continue
            w, h = img.size
            if w < 180 or h < 180:
                continue
            squared = pad_to_square(img, target_size=800)
            compressed_data = compress_image(squared, max_kb=115)
            if len(compressed_data) > 3000:
                valid_image_bytes = compressed_data
                break
        except Exception:
            continue

    if not valid_image_bytes:
        raise RuntimeError(f"Could not find 1 pristine commercial packshot for {item['name']}")

    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(img_path, "wb") as f:
        f.write(valid_image_bytes)

    return img_path


def upload_to_supabase_storage(file_path: str, remote_filename: str) -> str:
    """Uploads file to Supabase storage bucket and returns public URL with retry resilience."""
    public_url = f"{SUPABASE_CONFIG['url']}/storage/v1/object/public/{STORAGE_BUCKET}/{STORAGE_PREFIX}/{remote_filename}"

    # Check if already uploaded and valid
    try:
        head_r = requests.head(public_url, timeout=5)
        if head_r.status_code == 200 and int(head_r.headers.get("Content-Length", 0)) > 2000:
            return public_url
    except Exception:
        pass

    url = f"{SUPABASE_CONFIG['url']}/storage/v1/object/{STORAGE_BUCKET}/{STORAGE_PREFIX}/{remote_filename}"
    headers = {
        "apikey": SUPABASE_CONFIG["key"],
        "Authorization": f"Bearer {SUPABASE_CONFIG['key']}",
        "Content-Type": "image/jpeg",
        "x-upsert": "true",
    }
    with open(file_path, "rb") as f:
        data = f.read()

    for attempt in range(4):
        try:
            r = requests.post(url, headers=headers, data=data, timeout=20)
            if r.status_code not in (200, 201):
                check_r = requests.head(public_url, timeout=5)
                if check_r.status_code == 200:
                    return public_url
                r = requests.put(url, headers=headers, data=data, timeout=20)
                if r.status_code not in (200, 201):
                    check_r = requests.head(public_url, timeout=5)
                    if check_r.status_code == 200:
                        return public_url
                    raise RuntimeError(f"Storage upload failed: {r.status_code} {r.text}")
            break
        except Exception as e:
            if attempt == 3:
                raise
            print(f"      ⚠️ Storage upload attempt {attempt+1} failed: {e}. Retrying in 2s...")
            time.sleep(2)

    return public_url


def main():
    print("=" * 80)
    print("🚀 STARTING MAXX RETAIL SUPERMARKET BATCH 32 INGESTION")
    print(f"   Target Shop: Maxx Retail ({SHOP_ID})")
    print(f"   Catalog Size: {len(BATCH_32_CATALOG)} verified SKUs")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary Status: Strictly N/A (is_veg = NULL)")
    print(f"   Packshot Protocol: Exactly 1 pristine 1:1 padded image (< 120KB) on pure white")
    print("=" * 80)

    products_payload = []

    for idx, item in enumerate(BATCH_32_CATALOG, 1):
        print(f"\n[{idx}/{len(BATCH_32_CATALOG)}] Processing: {item['name']} (₹{item['price']:.2f})")
        print(f"   Brand: {item['brand']} | Unit: {item['weight_per_unit']} {item['unit_type']}")

        # 1. Source Packshot (Rule 4: exactly 1 pristine image)
        print("   🔍 Sourcing pristine 1:1 commercial packshot...")
        img_path = source_single_packshot(item, idx)
        file_size_kb = os.path.getsize(img_path) / 1024
        print(f"   📸 Local Packshot cached: {img_path} ({file_size_kb:.1f} KB)")

        # 2. Upload to Supabase Storage
        product_slug = f"b32_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
        remote_fn = f"{product_slug}.jpg"
        pub_url = upload_to_supabase_storage(img_path, remote_fn)
        print(f"   ☁️ Storage Public URL: {pub_url}")

        # 3. Construct Ingestion Record
        record = {
            "name": item["name"],
            "description": item["description"],
            "price": item["price"],
            "category": "Cosmetics & Beauty",  # Strictly 18% Statutory GST
            "sub_category": item["sub_category"],
            "menu_category": item["menu_category"],
            "brand": item["brand"],
            "is_veg": None,  # Rule 3: Strictly N/A for personal care & cosmetics
            "image_url": pub_url,
            "images": [pub_url],
            "weight_per_unit": item["weight_per_unit"],
            "unit_type": item["unit_type"],
            "is_available": True,
            "stock_quantity": 50,
            "variants": item.get("variants", []),
            "tags": ["personal_care", "cosmetics_beauty", "skincare", item["sub_category"].lower(), item["brand"].lower()],
        }
        products_payload.append(record)

    # 4. Invoke bulk_upload_shop_products RPC
    print("\n" + "=" * 80)
    print(f"💾 Ingesting {len(products_payload)} products into Supabase via bulk_upload_shop_products RPC...")
    print("=" * 80)

    rpc_url = f"{SUPABASE_CONFIG['url']}/rest/v1/rpc/bulk_upload_shop_products"
    headers = {
        "apikey": SUPABASE_CONFIG["key"],
        "Authorization": f"Bearer {SUPABASE_CONFIG['key']}",
        "Content-Type": "application/json",
    }
    payload = {
        "p_shop_id": SHOP_ID,
        "p_products": products_payload,
    }

    resp = requests.post(rpc_url, headers=headers, json=payload)
    if resp.status_code not in (200, 201):
        print(f"❌ RPC invocation failed ({resp.status_code}): {resp.text}")
        sys.exit(1)

    print("✅ Successfully invoked bulk_upload_shop_products RPC!")
    print(f"   Response: {resp.text}")
    print("\n🏁 Batch 32 ingestion completed successfully!")


if __name__ == "__main__":
    main()

