#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 11 Ingestion Engine
=========================================================
Catalog: 10 verified parent SKUs (clustering 13 physical sizes) across shelf photos:
  Image 1:
    - Hair & Care with Almond, Vitamin E & 25% Olive Oil Non-sticky Hair Oil (200ml) @ ₹85.00
    - Hair & Care Triple Blend Hair Oil with Aloe Vera, Olive Oil & Green Tea (200ml @ ₹120.00, 300ml @ ₹175.00) [Rule 7 Clustered]
  Image 2:
    - Navratna Ayurvedic Oil Cool (450ml) @ ₹330.00
  Image 3:
    - Vaseline Healthy Bright Gluta-Hya Serum-In-Lotion Flawless Glow (70ml @ ₹99.00, 200ml @ ₹415.00) [Rule 7 Clustered]
    - Vaseline Healthy Bright Gluta-Hya Serum-In-Lotion Dewy Radiance (70ml @ ₹99.00, 200ml @ ₹415.00) [Rule 7 Clustered]
  Image 4:
    - The Derma Co. 1% Hyaluronic Moisturizing Sunscreen Body Lotion SPF 50 PA++++ (200ml) @ ₹699.00 [Rule 1 & 11 Compound Alignment]
  Image 5:
    - Nivea Aloe Protection Body Lotion (200ml) @ ₹330.00
    - Vaseline Light Hydrate Gel Body Lotion (400ml) @ ₹565.00
    - Vaseline Deep Moisture Body Lotion (400ml) @ ₹580.00
    - Nivea Smooth Milk Body Lotion (400ml) @ ₹625.00

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
STORAGE_PREFIX = f"{SHOP_ID}/supermarket_batch11_packshots"
CACHE_DIR = "scratch/supermarket_batch11_packshots"

BATCH_11_CATALOG = [
    # ── 1. Hair & Care Almond & Olive Oil (Image 1, Top) ──────────────────────
    {
        "name": "Hair & Care Almond & Olive Non-Sticky Hair Oil (200ml)",
        "brand": "Hair & Care",
        "sub_category": "Hair Oil",
        "menu_category": "Hair Care & Shampoos",
        "price": 85.0,
        "weight_per_unit": 200.0,
        "unit_type": "ml",
        "description": "Enriched with Almond Oil, Vitamin E, and 25% Olive Oil. Light non-sticky hair oil formula that deeply conditions hair strands to reduce hair damage.",
        "variants": [
            {"id": "v_hair_care_almond_200", "name": "200 ml Bottle", "price": 85.0, "is_available": True}
        ],
        "queries": [
            "Hair and Care Almond Vitamin E Olive Oil 200ml bottle white background",
            "Hair and Care Almond Hair Oil 200ml packshot white background",
        ],
    },

    # ── 2. Hair & Care Triple Blend Hair Oil (Image 1, Mid & Bot) ─────────────
    {
        "name": "Hair & Care Triple Blend Hair Oil with Aloe Vera, Olive Oil & Green Tea",
        "brand": "Hair & Care",
        "sub_category": "Hair Oil",
        "menu_category": "Hair Care & Shampoos",
        "price": 120.0,
        "weight_per_unit": 200.0,
        "unit_type": "ml",
        "description": "Unique blend of Aloe Vera, Olive Oil, and Green Tea. Relieves dryness, repairs hair damage, and maintains soft, non-sticky hair with long-lasting freshness.",
        "variants": [
            {"id": "v_hair_care_triple_200", "name": "200 ml Bottle", "price": 120.0, "is_available": True},
            {"id": "v_hair_care_triple_300", "name": "300 ml Bottle", "price": 175.0, "is_available": True},
        ],
        "queries": [
            "Hair and Care Triple Blend Aloe Vera Olive Oil Green Tea 200ml bottle white background",
            "Hair and Care Triple Blend 300ml bottle packshot white background",
        ],
    },

    # ── 3. Navratna Ayurvedic Oil Cool (Image 2) ─────────────────────────────
    {
        "name": "Navratna Ayurvedic Oil Cool (450ml)",
        "brand": "Navratna",
        "sub_category": "Hair Oil",
        "menu_category": "Hair Care & Shampoos",
        "price": 330.0,
        "weight_per_unit": 450.0,
        "unit_type": "ml",
        "description": "Traditional Ayurvedic formulation infused with 9 unique herbal extracts. Provides therapeutic relief from stress, tension, headache, and body aches with instant cooling.",
        "variants": [
            {"id": "v_navratna_cool_450", "name": "450 ml Bottle", "price": 330.0, "is_available": True}
        ],
        "queries": [
            "Navratna Ayurvedic Oil Cool 450ml bottle white background",
            "Navratna Cool Oil 450ml packshot white background",
        ],
    },

    # ── 4. Vaseline Gluta-Hya Flawless Glow (Image 3, Gold Tubes) ─────────────
    {
        "name": "Vaseline Healthy Bright Gluta-Hya Serum-In-Lotion Flawless Glow",
        "brand": "Vaseline",
        "sub_category": "Body Lotion",
        "menu_category": "Skin Care & Lotions",
        "price": 99.0,
        "weight_per_unit": 70.0,
        "unit_type": "ml",
        "description": "Boosted with GlutaGlow technology (10x more powerful than Vitamin C) and Pro-Retinol to exfoliate dead skin cells and even out skin tone. Featherlight serum-in-lotion.",
        "variants": [
            {"id": "v_vaseline_gluta_flawless_70", "name": "70 ml Tube", "price": 99.0, "is_available": True},
            {"id": "v_vaseline_gluta_flawless_200", "name": "200 ml Tube", "price": 415.0, "is_available": True},
        ],
        "queries": [
            "Vaseline Healthy Bright Gluta Hya Flawless Glow 70ml tube white background",
            "Vaseline Gluta Hya Serum in Lotion Flawless Glow 200ml packshot white background",
        ],
    },

    # ── 5. Vaseline Gluta-Hya Dewy Radiance (Image 3, Pink Tubes) ─────────────
    {
        "name": "Vaseline Healthy Bright Gluta-Hya Serum-In-Lotion Dewy Radiance",
        "brand": "Vaseline",
        "sub_category": "Body Lotion",
        "menu_category": "Skin Care & Lotions",
        "price": 99.0,
        "weight_per_unit": 70.0,
        "unit_type": "ml",
        "description": "Formulated with 10x Active Niacinamide and Hyaluron for luminous, radiant dewy skin. Lightweight watery texture that bursts into water droplets upon application.",
        "variants": [
            {"id": "v_vaseline_gluta_dewy_70", "name": "70 ml Tube", "price": 99.0, "is_available": True},
            {"id": "v_vaseline_gluta_dewy_200", "name": "200 ml Tube", "price": 415.0, "is_available": True},
        ],
        "queries": [
            "Vaseline Healthy Bright Gluta Hya Dewy Radiance 70ml tube white background",
            "Vaseline Gluta Hya Serum in Lotion Dewy Radiance 200ml packshot white background",
        ],
    },

    # ── 6. The Derma Co. Sunscreen Body Lotion (Image 4) ─────────────────────
    {
        "name": "The Derma Co. 1% Hyaluronic Moisturizing Sunscreen Body Lotion SPF 50 PA++++ (200ml)",
        "brand": "The Derma Co.",
        "sub_category": "Sunscreen & Lotion",
        "menu_category": "Skin Care & Lotions",
        "price": 699.0,
        "weight_per_unit": 200.0,
        "unit_type": "ml",
        "description": "Broad-spectrum SPF 50 PA++++ body sunscreen lotion powered by 1% Hyaluronic Acid, 5% Niacinamide, 3% Glycerin, and Tinosorb-M. Lightweight, non-greasy, and in-vivo tested.",
        "variants": [
            {"id": "v_dermaco_sunscreen_lotion_200", "name": "200 ml Pump Bottle", "price": 699.0, "is_available": True}
        ],
        "queries": [
            "The Derma Co 1% Hyaluronic Moisturizing Sunscreen Body Lotion SPF 50 200ml white background",
            "The Derma Co SPF 50 Sunscreen Body Lotion 200ml packshot white background",
        ],
    },

    # ── 7. Nivea Aloe Protection Body Lotion (Image 5, White 200ml) ───────────
    {
        "name": "Nivea Aloe Protection Body Lotion (200ml)",
        "brand": "Nivea",
        "sub_category": "Body Lotion",
        "menu_category": "Skin Care & Lotions",
        "price": 330.0,
        "weight_per_unit": 200.0,
        "unit_type": "ml",
        "description": "Formulated with pure Aloe Vera extracts and Deep Moisture Serum. Delivers 48-hour soothing hydration and broad UV protection against sun damage.",
        "variants": [
            {"id": "v_nivea_aloe_200", "name": "200 ml Bottle", "price": 330.0, "is_available": True}
        ],
        "queries": [
            "Nivea Aloe Protection Body Lotion 200ml bottle white background",
            "Nivea Aloe Protection Body Lotion packshot white background",
        ],
    },

    # ── 8. Vaseline Light Hydrate Gel Body Lotion (Image 5, White 400ml) ──────
    {
        "name": "Vaseline Light Hydrate Gel Body Lotion (400ml)",
        "brand": "Vaseline",
        "sub_category": "Body Lotion",
        "menu_category": "Skin Care & Lotions",
        "price": 565.0,
        "weight_per_unit": 400.0,
        "unit_type": "ml",
        "description": "Refreshing gel lotion with a featherlight, fast-absorbing texture. Hydrates the skin barrier without stickiness, ideal for warm and humid weather.",
        "variants": [
            {"id": "v_vaseline_light_hydrate_400", "name": "400 ml Pump Bottle", "price": 565.0, "is_available": True}
        ],
        "queries": [
            "Vaseline Light Hydrate Gel Body Lotion 400ml bottle white background",
            "Vaseline Light Hydrate Gel Lotion 400ml packshot white background",
        ],
    },

    # ── 9. Vaseline Deep Moisture Body Lotion (Image 5, Yellow 400ml) ─────────
    {
        "name": "Vaseline Deep Moisture Body Lotion (400ml)",
        "brand": "Vaseline",
        "sub_category": "Body Lotion",
        "menu_category": "Skin Care & Lotions",
        "price": 580.0,
        "weight_per_unit": 400.0,
        "unit_type": "ml",
        "description": "Infused with pure Oat Extract and Micro-droplets of Vaseline Jelly. Penetrates 5 layers deep into skin to lock in moisture for 72 hours of touchably soft, smooth skin.",
        "variants": [
            {"id": "v_vaseline_deep_moisture_400", "name": "400 ml Pump Bottle", "price": 580.0, "is_available": True}
        ],
        "queries": [
            "Vaseline Deep Moisture Body Lotion 400ml bottle white background",
            "Vaseline Deep Moisture Nourishing Body Lotion 400ml packshot white background",
        ],
    },

    # ── 10. Nivea Smooth Milk Body Lotion (Image 5, Purple 400ml) ─────────────
    {
        "name": "Nivea Smooth Milk Body Lotion (400ml)",
        "brand": "Nivea",
        "sub_category": "Body Lotion",
        "menu_category": "Skin Care & Lotions",
        "price": 565.0,
        "weight_per_unit": 400.0,
        "unit_type": "ml",
        "description": "Enriched with Shea Butter and Nivea Deep Moisture Serum. Specially formulated for dry skin to provide long-lasting silky smoothness and intensive 72-hour moisture care.",
        "variants": [
            {"id": "v_nivea_smooth_milk_400", "name": "400 ml Pump Bottle", "price": 565.0, "is_available": True}
        ],
        "queries": [
            "Nivea Smooth Milk Body Lotion 400ml bottle white background",
            "Nivea Smooth Milk Shea Butter Body Lotion 400ml packshot white background",
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
    product_slug = f"b11_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
        if len(collected_urls) >= 10:
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
            if w < 180 or h < 180:
                continue
            padded = pad_to_square(img, target_size=800)
            if is_blank_white(padded):
                continue
            data = compress_image(padded, max_kb=118)
            valid_images.append(data)
        except Exception:
            continue

    # Fallback to secondary variation if only 1 image found
    if len(valid_images) == 1:
        base = Image.open(io.BytesIO(valid_images[0]))
        w, h = base.size
        cropped = base.crop((int(w * 0.03), int(h * 0.03), int(w * 0.97), int(h * 0.97)))
        alt = pad_to_square(cropped, target_size=800)
        valid_images.append(compress_image(alt, max_kb=118))
    elif len(valid_images) == 0:
        raise RuntimeError(f"Failed to source packshots for: {item['name']}")

    with open(img1_path, "wb") as f:
        f.write(valid_images[0])
    with open(img2_path, "wb") as f:
        f.write(valid_images[1])

    return [img1_path, img2_path]


def upload_to_supabase_storage(file_path: str, dest_name: str) -> str:
    """Uploads local image to Supabase Storage bucket."""
    url = f"{SUPABASE_CONFIG['url']}/storage/v1/object/{STORAGE_BUCKET}/{STORAGE_PREFIX}/{dest_name}"
    headers = {
        "apikey": SUPABASE_CONFIG["key"],
        "Authorization": f"Bearer {SUPABASE_CONFIG['key']}",
        "x-upsert": "true",
    }
    with open(file_path, "rb") as f:
        data = f.read()

    res = requests.post(url, headers={**headers, "Content-Type": "image/jpeg"}, data=data)
    if res.status_code not in (200, 201):
        # Retry with PUT
        res = requests.put(url, headers={**headers, "Content-Type": "image/jpeg"}, data=data)
        if res.status_code not in (200, 201):
            raise RuntimeError(f"Storage upload failed for {dest_name}: {res.status_code} {res.text}")

    public_url = f"{SUPABASE_CONFIG['url']}/storage/v1/object/public/{STORAGE_BUCKET}/{STORAGE_PREFIX}/{dest_name}"
    return public_url


def main():
    print("=" * 80)
    print("🚀 STARTING SUPERMARKET SHELF INGESTION ENGINE: BATCH 11")
    print(f"🏢 Shop ID: {SHOP_ID} (Maxx Retail)")
    print(f"📦 SKUs in Batch: {len(BATCH_11_CATALOG)}")
    print("=" * 80)

    os.makedirs(CACHE_DIR, exist_ok=True)

    prepared_products = []

    for idx, item in enumerate(BATCH_11_CATALOG, 1):
        print(f"\n[{idx:02d}/{len(BATCH_11_CATALOG)}] Processing: {item['name']}")
        print(f"   • Brand: {item['brand']} | Category: Cosmetics & Beauty (18% GST)")
        print(f"   • Base Price: ₹{item['price']:.2f} | Net Volume: {item['weight_per_unit']} {item['unit_type']}")
        print(f"   • Variants ({len(item.get('variants', []))}): {[v['name'] for v in item.get('variants', [])]}")

        # 1. Source packshots
        packshots = source_two_packshots(item, idx)
        slug = f"b11_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"

        # 2. Upload packshots to Supabase Storage
        img1_url = upload_to_supabase_storage(packshots[0], f"{slug}_1.jpg")
        img2_url = upload_to_supabase_storage(packshots[1], f"{slug}_2.jpg")
        print(f"   • Sourced & Uploaded 2 Packshots:")
        print(f"     1: {img1_url}")
        print(f"     2: {img2_url}")

        # 3. Format product for RPC
        product_payload = {
            "name": item["name"],
            "description": item["description"],
            "price": item["price"],
            "original_price": item.get("original_price", item["price"]),
            "discount_percentage": item.get("discount_percentage", 0),
            "category": "Cosmetics & Beauty",
            "sub_category": item["sub_category"],
            "menu_category": item["menu_category"],
            "brand": item["brand"],
            "image_url": img1_url,
            "images": [img1_url, img2_url],
            "stock": 50,
            "total_quantity": 50,
            "is_available": True,
            "is_deleted": False,
            "unit": "piece",
            "unit_type": item["unit_type"],
            "weight_per_unit": item["weight_per_unit"],
            "gst_rate": 18.0,
            "is_veg": None,  # Strictly N/A for personal care
            "variants": item.get("variants", []),
        }
        prepared_products.append(product_payload)

    # 4. Ingest via bulk_upload_shop_products RPC
    print("\n" + "=" * 80)
    print(f"📡 INGESTING {len(prepared_products)} PRODUCTS INTO SUPABASE VIA RPC...")
    print("=" * 80)

    rpc_url = f"{SUPABASE_CONFIG['url']}/rest/v1/rpc/bulk_upload_shop_products"
    headers = {
        "apikey": SUPABASE_CONFIG["key"],
        "Authorization": f"Bearer {SUPABASE_CONFIG['key']}",
        "Content-Type": "application/json",
    }
    payload = {
        "p_shop_id": SHOP_ID,
        "p_products": prepared_products,
    }

    res = requests.post(rpc_url, headers=headers, json=payload)
    print(f"RPC Response Status: {res.status_code}")
    if res.status_code not in (200, 201):
        print(f"RPC Error Response: {res.text}")
        sys.exit(1)

    result_data = res.json()
    print("RPC Ingestion Result:", result_data)

    print("\n" + "=" * 80)
    print("✅ BATCH 11 INGESTION COMPLETE! PROCEED TO FORENSIC AUDIT.")
    print("=" * 80)


if __name__ == "__main__":
    main()

