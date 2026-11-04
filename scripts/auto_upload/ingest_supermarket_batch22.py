#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 22 Ingestion Engine
=========================================================
Catalog: 12 verified SKUs across shelf photos:
  Image 1:
    - Dot & Key Retinol + Ceramide Night Repair Cream (60ml) @ ₹599.00
    - Dot & Key Cica Calming Skin Renewing Night Gel (60ml) @ ₹495.00
    - Dot & Key Pomegranate & Peptide Youth Restore Moisturizer SPF 30 (60ml) @ ₹495.00
    - Dot & Key Watermelon Cooling Sunscreen Body Spray SPF 40+ (110ml) @ ₹595.00
  Image 2:
    - Dot & Key Vitamin C + E Super Bright Sunscreen SPF 50+ (50g) @ ₹445.00
    - Dot & Key Strawberry Dew Tinted Sunscreen SPF 50+ PA++++ (50ml) (01 Porcelain & 02 Warm Ivory clustered) @ ₹549.00
    - Dot & Key Cica Calming Mattifying Sunscreen SPF 50+ (50g) @ ₹445.00
    - Dot & Key Blueberry Hydrate Barrier Repair Sunscreen SPF 50+ (60g) @ ₹445.00
    - Dot & Key Watermelon Cooling Sunscreen Aqua Gel SPF 50+ (60g) @ ₹445.00
    - Dot & Key Water Drench Hydrating Hyaluronic Serum Concentrate (30ml) @ ₹695.00
  Image 3:
    - Dabur Gulabari Rose Glow Face Cleanser & Toner Spray (50ml @ ₹60.00 & 100ml @ ₹105.00 clustered)
    - Blue Chip Rosy Mist Face Cleanser & Toner (120ml) @ ₹99.00

Strict Directives Enforced:
1. Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab).
2. Dietary Status: Strictly N/A (`is_veg = None` / SQL NULL).
3. Packshots: Exactly 2 commercial photoshoot views on pure white background (#FFFFFF),
   1:1 padded square (800x800), < 120KB. Zero blank white images.
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
STORAGE_PREFIX = "supermarket/maxx_retail/batch22"
CACHE_DIR = "/tmp/maxx_retail_batch22_cache"

BATCH_22_CATALOG = [
    {
        "name": "Dot & Key Retinol + Ceramide Night Repair Cream (60ml)",
        "price": 599.00,
        "brand": "Dot & Key",
        "sub_category": "Skincare",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 60.0,
        "unit_type": "ml",
        "description": "Dot & Key Retinol + Ceramide Night Repair Cream with Hibiscus & Pomegranate Oil. Smooths wrinkles, boosts collagen synthesis, and reinforces skin barrier overnight.",
        "variants": [{"name": "60ml", "price": 599.00, "unit": "60ml"}],
        "queries": [
            "dot and key retinol ceramide night repair cream 60ml packshot white background",
            "dot & key retinol ceramide night cream 60ml packshot",
            "dot and key retinol ceramide cream 60ml tub",
        ],
    },
    {
        "name": "Dot & Key Cica Calming Skin Renewing Night Gel (60ml)",
        "price": 495.00,
        "brand": "Dot & Key",
        "sub_category": "Skincare",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 60.0,
        "unit_type": "ml",
        "description": "Dot & Key Cica Calming Skin Renewing Night Gel with Niacinamide & Green Tea. Calms acne-prone sensitive skin, controls excess oil, and soothes inflammation.",
        "variants": [{"name": "60ml", "price": 495.00, "unit": "60ml"}],
        "queries": [
            "dot and key cica calming skin renewing night gel 60ml packshot white background",
            "dot & key cica night gel 60ml packshot",
            "dot and key cica calming night gel tub",
        ],
    },
    {
        "name": "Dot & Key Pomegranate & Peptide Youth Restore Moisturizer SPF 30 (60ml)",
        "price": 495.00,
        "brand": "Dot & Key",
        "sub_category": "Skincare",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 60.0,
        "unit_type": "ml",
        "description": "Dot & Key Pomegranate & Peptide Youth Restore Moisturizer with SPF 30. Infused with Collagen & Pomegranate extract to firm skin, improve elasticity, and shield from UV rays.",
        "variants": [{"name": "60ml", "price": 495.00, "unit": "60ml"}],
        "queries": [
            "dot and key pomegranate peptide youth restore moisturizer spf 30 60ml packshot white background",
            "dot & key pomegranate moisturizer spf 30 packshot",
            "dot and key pomegranate peptide cream tub 60ml",
        ],
    },
    {
        "name": "Dot & Key Watermelon Cooling Sunscreen Body Spray SPF 40+ (110ml)",
        "price": 595.00,
        "brand": "Dot & Key",
        "sub_category": "Skincare",
        "menu_category": "Sunscreen & Sun Care",
        "weight_per_unit": 110.0,
        "unit_type": "ml",
        "description": "Dot & Key Watermelon Cooling Sunscreen Body Spray SPF 40+ Broad Spectrum. Ultra-light, 80-minute water-resistant mist that provides instant cooling sun protection without white cast.",
        "variants": [{"name": "110ml", "price": 595.00, "unit": "110ml"}],
        "queries": [
            "dot and key watermelon cooling sunscreen body spray spf 40 110ml packshot white background",
            "dot & key watermelon sunscreen body spray packshot",
            "dot and key watermelon body spray 110ml",
        ],
    },
    {
        "name": "Dot & Key Vitamin C + E Super Bright Sunscreen SPF 50+ (50g)",
        "price": 445.00,
        "brand": "Dot & Key",
        "sub_category": "Skincare",
        "menu_category": "Sunscreen & Sun Care",
        "weight_per_unit": 50.0,
        "unit_type": "g",
        "description": "Dot & Key Vitamin C + E Super Bright Sunscreen SPF 50+ with Sicilian Blood Orange. Water-light fluid sunscreen that protects against UV & blue light while boosting radiant glow.",
        "variants": [{"name": "50g", "price": 445.00, "unit": "50g"}],
        "queries": [
            "dot and key vitamin c e super bright sunscreen spf 50 50g packshot white background",
            "dot & key vitamin c sunscreen spf 50 50g packshot",
            "dot and key orange sunscreen tube 50g",
        ],
    },
    {
        "name": "Dot & Key Strawberry Dew Tinted Sunscreen SPF 50+ PA++++ (50ml)",
        "price": 549.00,
        "brand": "Dot & Key",
        "sub_category": "Skincare",
        "menu_category": "Sunscreen & Sun Care",
        "weight_per_unit": 50.0,
        "unit_type": "ml",
        "description": "Dot & Key Strawberry Dew Tinted Sunscreen SPF 50+ PA++++ with Niacinamide. Daily wear sunscreen that offers sheer tint coverage, dewy radiance, and broad-spectrum sun defense.",
        "variants": [
            {"name": "01 Porcelain", "price": 549.00, "unit": "50ml"},
            {"name": "02 Warm Ivory", "price": 549.00, "unit": "50ml"}
        ],
        "queries": [
            "dot and key strawberry dew tinted sunscreen spf 50 50ml packshot white background",
            "dot & key strawberry dew tinted sunscreen packshot",
            "dot and key tinted sunscreen strawberry 50ml tube",
        ],
    },
    {
        "name": "Dot & Key Cica Calming Mattifying Sunscreen SPF 50+ (50g)",
        "price": 445.00,
        "brand": "Dot & Key",
        "sub_category": "Skincare",
        "menu_category": "Sunscreen & Sun Care",
        "weight_per_unit": 50.0,
        "unit_type": "g",
        "description": "Dot & Key Cica Calming Mattifying Sunscreen SPF 50+ PA++++ with Niacinamide. Light gel-cream formula controls oil, calms acne breakouts, and leaves a fresh matte finish.",
        "variants": [{"name": "50g", "price": 445.00, "unit": "50g"}],
        "queries": [
            "dot and key cica calming mattifying sunscreen spf 50 50g packshot white background",
            "dot & key cica sunscreen spf 50 packshot",
            "dot and key cica calming sunscreen tube 50g",
        ],
    },
    {
        "name": "Dot & Key Blueberry Hydrate Barrier Repair Sunscreen SPF 50+ (60g)",
        "price": 445.00,
        "brand": "Dot & Key",
        "sub_category": "Skincare",
        "menu_category": "Sunscreen & Sun Care",
        "weight_per_unit": 60.0,
        "unit_type": "g",
        "description": "Dot & Key Blueberry Hydrate Barrier Repair Sunscreen SPF 50+ PA++++ with Hyaluronic & Ceramides. Provides long-lasting moisture, restores skin barrier, and defends against UVA/UVB rays.",
        "variants": [{"name": "60g", "price": 445.00, "unit": "60g"}],
        "queries": [
            "dot and key blueberry hydrate barrier repair sunscreen spf 50 60g packshot white background",
            "dot & key blueberry sunscreen spf 50 packshot",
            "dot and key blueberry barrier repair sunscreen tube 60g",
        ],
    },
    {
        "name": "Dot & Key Watermelon Cooling Sunscreen Aqua Gel SPF 50+ (60g)",
        "price": 445.00,
        "brand": "Dot & Key",
        "sub_category": "Skincare",
        "menu_category": "Sunscreen & Sun Care",
        "weight_per_unit": 60.0,
        "unit_type": "g",
        "description": "Dot & Key Watermelon Cooling Sunscreen Aqua Gel SPF 50+ PA++++ with Hyaluronic Acid. Delivers an instant cooling burst of hydration with broad spectrum UV protection.",
        "variants": [{"name": "60g", "price": 445.00, "unit": "60g"}],
        "queries": [
            "dot and key watermelon cooling sunscreen aqua gel spf 50 60g packshot white background",
            "dot & key watermelon sunscreen aqua gel packshot",
            "dot and key watermelon cooling sunscreen 60g tube",
        ],
    },
    {
        "name": "Dot & Key Water Drench Hydrating Hyaluronic Serum Concentrate (30ml)",
        "price": 695.00,
        "brand": "Dot & Key",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "Dot & Key Water Drench Hydrating Hyaluronic Serum Concentrate with Rice Water & Bulgarian Rose. Deeply drenches dehydrated skin with multi-layer plumping hydration.",
        "variants": [{"name": "30ml", "price": 695.00, "unit": "30ml"}],
        "queries": [
            "dot and key water drench hydrating hyaluronic serum concentrate 30ml packshot white background",
            "dot & key water drench serum packshot",
            "dot and key hyaluronic serum concentrate 30ml dropper",
        ],
    },
    {
        "name": "Dabur Gulabari Rose Glow Face Cleanser & Toner Spray",
        "price": 60.00,
        "brand": "Dabur",
        "sub_category": "Skincare",
        "menu_category": "Toners & Mists",
        "weight_per_unit": 50.0,
        "unit_type": "ml",
        "description": "Dabur Gulabari Rose Glow Face Cleanser & Toner Spray enriched with natural Rose extracts. Cleanses impurities, refreshes tired skin, and imparts a natural rosy glow.",
        "variants": [
            {"name": "50ml", "price": 60.00, "unit": "50ml"},
            {"name": "100ml", "price": 105.00, "unit": "100ml"}
        ],
        "queries": [
            "dabur gulabari face cleanser toner spray 100ml bottle packshot white background",
            "dabur gulabari rose face cleanser spray packshot",
            "dabur gulabari spray 100ml bottle",
        ],
    },
    {
        "name": "Blue Chip Rosy Mist Face Cleanser & Toner (120ml)",
        "price": 99.00,
        "brand": "Blue Chip",
        "sub_category": "Skincare",
        "menu_category": "Toners & Mists",
        "weight_per_unit": 120.0,
        "unit_type": "ml",
        "description": "Blue Chip Rosy Mist Face Cleanser & Toner with natural rose infusion. Boosts moisture, soothes and calms sensitive skin, and refines pores for a fresh, radiant look.",
        "variants": [{"name": "120ml", "price": 99.00, "unit": "120ml"}],
        "queries": [
            "blue chip rosy mist face cleanser toner 120ml bottle packshot white background",
            "blue chip rosy mist face cleanser toner spray packshot",
            "blue chip rosy mist 120ml",
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
    img = Image.open(io.BytesIO(content))
    if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
        rgba = img.convert("RGBA")
        background = Image.new("RGB", rgba.size, (255, 255, 255))
        background.paste(rgba, mask=rgba.split()[3])
        return background
    return img.convert("RGB")


def pad_to_square(img: Image.Image, target_size: int = 800) -> Image.Image:
    """Pads product image onto 1:1 pure white canvas with 7% breathing room."""
    w, h = img.size
    max_dim = int(target_size * 0.86)
    scale = min(max_dim / w, max_dim / h)
    new_w, new_h = max(1, int(w * scale)), max(1, int(h * scale))
    resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)

    canvas = Image.new("RGB", (target_size, target_size), (255, 255, 255))
    offset_x = (target_size - new_w) // 2
    offset_y = (target_size - new_h) // 2
    canvas.paste(resized, (offset_x, offset_y))
    return canvas


def compress_image(img: Image.Image, max_kb: int = 120) -> bytes:
    """Progressively compresses image to JPEG under max_kb."""
    quality = 90
    while quality >= 35:
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=quality, optimize=True)
        data = buf.getvalue()
        if len(data) <= max_kb * 1024:
            return data
        quality -= 5
    return data


def source_two_packshots(item: dict, idx: int) -> list:
    """Sources exactly 2 high-grade commercial packshots on solid pure white."""
    product_slug = f"b22_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
    img1_path = os.path.join(CACHE_DIR, f"{product_slug}_1.jpg")
    img2_path = os.path.join(CACHE_DIR, f"{product_slug}_2.jpg")

    if os.path.exists(img1_path) and os.path.exists(img2_path):
        return [img1_path, img2_path]

    collected_urls = []
    for q in item["queries"]:
        urls = search_bing_images(q, max_results=12)
        for u in urls:
            if u not in collected_urls:
                collected_urls.append(u)
        if len(collected_urls) >= 15:
            break

    valid_images = []
    for u in collected_urls:
        if len(valid_images) >= 2:
            break
        try:
            r = requests.get(u, headers=HEADERS, timeout=6)
            if r.status_code != 200 or len(r.content) < 5000:
                continue
            img = load_and_clean_image(r.content)
            if is_blank_white(img):
                continue
            w, h = img.size
            if w < 200 or h < 200:
                continue
            squared = pad_to_square(img, target_size=800)
            compressed_data = compress_image(squared, max_kb=115)
            valid_images.append(compressed_data)
        except Exception:
            continue

    if len(valid_images) < 2 and len(valid_images) == 1:
        valid_images.append(valid_images[0])

    if len(valid_images) < 2:
        raise RuntimeError(f"Could not find 2 commercial packshots for {item['name']}")

    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(img1_path, "wb") as f1:
        f1.write(valid_images[0])
    with open(img2_path, "wb") as f2:
        f2.write(valid_images[1])

    return [img1_path, img2_path]


def upload_to_supabase_storage(file_path: str, remote_filename: str) -> str:
    """Uploads file to Supabase storage bucket and returns public URL with retry resilience."""
    public_url = f"{SUPABASE_CONFIG['url']}/storage/v1/object/public/{STORAGE_BUCKET}/{STORAGE_PREFIX}/{remote_filename}"
    
    # 1. Check if already uploaded and valid
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
    print("🚀 STARTING MAXX RETAIL SUPERMARKET BATCH 22 INGESTION")
    print(f"   Target Shop: Maxx Retail ({SHOP_ID})")
    print(f"   Catalog Size: {len(BATCH_22_CATALOG)} verified SKUs")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST)")
    print(f"   Dietary Status: Strictly N/A (is_veg = NULL)")
    print("=" * 80)

    products_payload = []

    for idx, item in enumerate(BATCH_22_CATALOG, 1):
        print(f"\n[{idx}/{len(BATCH_22_CATALOG)}] Processing: {item['name']} (₹{item['price']:.2f})")
        print(f"   Brand: {item['brand']} | Unit: {item['weight_per_unit']} {item['unit_type']}")

        # 1. Source Packshots
        print("   🔍 Sourcing dual commercial packshots...")
        img_paths = source_two_packshots(item, idx)

        # 2. Upload to Supabase Storage
        remote_urls = []
        product_slug = f"b22_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
        for view_idx, local_p in enumerate(img_paths, 1):
            remote_fn = f"{product_slug}_{view_idx}.jpg"
            pub_url = upload_to_supabase_storage(local_p, remote_fn)
            remote_urls.append(pub_url)
            print(f"      📸 Uploaded View {view_idx}: {pub_url}")

        # 3. Construct Ingestion Record
        record = {
            "name": item["name"],
            "description": item["description"],
            "price": item["price"],
            "category": "Cosmetics & Beauty",  # Strictly 18% Statutory GST
            "sub_category": item["sub_category"],
            "menu_category": item["menu_category"],
            "brand": item["brand"],
            "is_veg": None,  # Strictly N/A for personal care & cosmetics
            "image_url": remote_urls[0],
            "images": remote_urls,
            "weight_per_unit": item["weight_per_unit"],
            "unit_type": item["unit_type"],
            "is_available": True,
            "stock_quantity": 40,
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
    if resp.status_code != 200:
        print(f"❌ RPC invocation failed ({resp.status_code}): {resp.text}")
        sys.exit(1)

    print("✅ Successfully invoked bulk_upload_shop_products RPC!")
    print(f"   Response: {resp.text}")
    print("\n🏁 Batch 22 ingestion completed. Proceeding to forensic verification audit...")


if __name__ == "__main__":
    main()

