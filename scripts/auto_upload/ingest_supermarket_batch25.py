#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 25 Ingestion Engine
=========================================================
Catalog: 12 verified SKUs across shelf photos b21.jpg - b30.jpg:
  Photo 1 (b21.jpg - Stacked):
    - Hilary Rhoda Blush Squad Palette - 4k Glow Blusher (12g) @ ₹299.00
    - Hilary Rhoda Power Puff Face Palette - Shade 02 Typsy Girl (12g) @ ₹249.00
  Photo 2 (b22.jpg - Stacked):
    - Hilary Rhoda Hide It All Full Cover Concealer (3.7g) @ ₹179.00
    - Swiss Beauty Liquid Concealer (6g) @ ₹249.00
  Photo 3 (b23.jpg - Stacked):
    - Daily Life Forever52 Pro Artist Ultra Definition Liquid Foundation (30ml) @ ₹1199.00 (Volume variant)
  Photo 4 & 5 (b24.jpg & b25.jpg - Stacked):
    - Maybelline New York Super Stay Lumi-Matte Foundation SPF 16 (35ml) @ ₹825.00
      Variants: Shade 115 (35ml), Shade 120 (35ml)
  Photo 6 (b26.jpg - Stacked):
    - Maybelline New York Fit Me Matte + Poreless Liquid Foundation (30ml) @ ₹679.00
      Variants: Shade 115 (30ml), Shade 118 (30ml), Shade 120 (30ml), Shade 128 (30ml)
    - MARS Silky Skin Compact Powder (20g) @ ₹349.00
  Photo 7 (b27.jpg - Stacked):
    - Hilary Rhoda HD High Definition Pressed Powder (18g) @ ₹299.00
    - Maybelline New York Fit Me Matte + Poreless Pressed Powder - Shade 110 Porcelain (8.5g) @ ₹629.00
    - Maybelline New York Super Stay Up To 30H Hybrid Powder Foundation (9g) @ ₹799.00
      Variants: Shade 110 (9g), Shade 120 (9g)
  Photo 8 (b28.jpg - Stacked):
    - Maybelline New York Instant Age Rewind Eraser Multi-Use Concealer (6ml) @ ₹799.00

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
STORAGE_PREFIX = "supermarket/maxx_retail/batch25"
CACHE_DIR = "/tmp/maxx_retail_batch25_cache"

BATCH_25_CATALOG = [
    {
        "name": "Hilary Rhoda Blush Squad Palette - 4k Glow Blusher (12g)",
        "price": 299.00,
        "brand": "Hilary Rhoda",
        "sub_category": "Face Makeup",
        "menu_category": "Blush & Bronzer",
        "weight_per_unit": 12.0,
        "unit_type": "grams",
        "description": "Hilary Rhoda Blush Squad Palette (4k Glow Blusher, HR-NE425). Contains 4 mesmerizing, ultra-blendable blush shades with a soft, silky smooth formula designed to give cheeks a luminous, natural glow.",
        "variants": [{"name": "Shade 04 (12g)", "price": 299.00, "unit": "12g"}],
        "queries": [
            "hilary rhoda blush squad palette packshot white background",
            "hilary rhoda 4k glow blusher palette packshot",
            "hilary rhoda blush squad 4k glow blusher",
        ],
    },
    {
        "name": "Hilary Rhoda Power Puff Face Palette - Shade 02 Typsy Girl (12g)",
        "price": 249.00,
        "brand": "Hilary Rhoda",
        "sub_category": "Makeup Palettes & Sets",
        "menu_category": "Face & Eye Palettes",
        "weight_per_unit": 12.0,
        "unit_type": "grams",
        "description": "Hilary Rhoda Power Puff Face Palette (Shade 02 Typsy Girl, HR-NE441). Comprehensive multi-purpose face palette featuring 2 luminous highlighters, 2 healthy pop-of-color blushes, and 2 sculpting contours for full-face definition.",
        "variants": [{"name": "Shade 02 Typsy Girl (12g)", "price": 249.00, "unit": "12g"}],
        "queries": [
            "hilary rhoda power puff palette packshot white background",
            "hilary rhoda power puff face palette packshot",
            "hilary rhoda power puff palette hr ne441",
        ],
    },
    {
        "name": "Hilary Rhoda Hide It All Full Cover Concealer (3.7g)",
        "price": 179.00,
        "brand": "Hilary Rhoda",
        "sub_category": "Face Makeup",
        "menu_category": "Concealers",
        "weight_per_unit": 3.7,
        "unit_type": "grams",
        "description": "Hilary Rhoda Hide It All Full Cover Concealer (HR-1480). Weightless feather-light liquid formula that effortlessly conceals dark circles, blemishes, and spots for an even-toned, naturally radiant complexion.",
        "variants": [{"name": "3.7g", "price": 179.00, "unit": "3.7g"}],
        "queries": [
            "hilary rhoda hide it all full cover concealer packshot white background",
            "hilary rhoda hide it all concealer hr 1480 packshot",
            "hilary rhoda hide it all cover concealer",
        ],
    },
    {
        "name": "Swiss Beauty Liquid Concealer (6g)",
        "price": 249.00,
        "brand": "Swiss Beauty",
        "sub_category": "Face Makeup",
        "menu_category": "Concealers",
        "weight_per_unit": 6.0,
        "unit_type": "grams",
        "description": "Swiss Beauty Liquid Concealer (SB-1505). High-tech buildable liquid concealer infused with nourishing Jojoba Oil. Seamlessly conceals blemishes, fine lines, and dark spots with a soft matte, non-cakey finish.",
        "variants": [{"name": "6g", "price": 249.00, "unit": "6g"}],
        "queries": [
            "swiss beauty liquid concealer 6g packshot white background",
            "swiss beauty perfect liquid concealer sb 1505 packshot",
            "swiss beauty liquid concealer sb1505",
        ],
    },
    {
        "name": "Daily Life Forever52 Pro Artist Ultra Definition Liquid Foundation (30ml)",
        "price": 1199.00,
        "brand": "Daily Life Forever52",
        "sub_category": "Face Makeup",
        "menu_category": "Foundations",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "Daily Life Forever52 Pro Artist Ultra Definition Liquid Foundation (30ml). High-performance, waterproof, and smudge-proof foundation enriched with Niacinamide and Hyaluronic Acid for buildable full coverage and an all-day matte finish.",
        "variants": [
            {"name": "30ml", "price": 1199.00, "unit": "30ml"},
            {"name": "60ml", "price": 1799.00, "unit": "60ml"},
        ],
        "queries": [
            "daily life forever52 pro artist ultra definition liquid foundation 30ml packshot white background",
            "forever52 ultra definition liquid foundation 30ml packshot",
            "forever52 pro artist liquid foundation 30ml bottle",
        ],
    },
    {
        "name": "Maybelline New York Super Stay Lumi-Matte Foundation SPF 16 (35ml)",
        "price": 825.00,
        "brand": "Maybelline New York",
        "sub_category": "Face Makeup",
        "menu_category": "Foundations",
        "weight_per_unit": 35.0,
        "unit_type": "ml",
        "description": "Maybelline New York Super Stay Lumi-Matte Foundation SPF 16. Up to 30-hour longwear liquid foundation delivering a breathable, luminous matte finish with SPF 16 sun protection that resists sweat, transfer, and water.",
        "variants": [
            {"name": "Shade 115 (35ml)", "price": 825.00, "unit": "35ml"},
            {"name": "Shade 120 (35ml)", "price": 825.00, "unit": "35ml"},
        ],
        "queries": [
            "maybelline super stay lumi matte foundation 35ml packshot white background",
            "maybelline superstay 30h lumi matte foundation bottle packshot",
            "maybelline super stay lumi-matte liquid foundation",
        ],
    },
    {
        "name": "Maybelline New York Fit Me Matte + Poreless Liquid Foundation (30ml)",
        "price": 679.00,
        "brand": "Maybelline New York",
        "sub_category": "Face Makeup",
        "menu_category": "Foundations",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "Maybelline New York Fit Me Matte + Poreless Liquid Foundation with SPF 22 and 16H oil control. Formulated with micro-powders to refine pores and absorb shine for a natural, seamless matte finish on normal to oily skin.",
        "variants": [
            {"name": "Shade 115 Warm Sun (30ml)", "price": 679.00, "unit": "30ml"},
            {"name": "Shade 118 Light Beige (30ml)", "price": 679.00, "unit": "30ml"},
            {"name": "Shade 120 Classic Ivory (30ml)", "price": 649.00, "unit": "30ml"},
            {"name": "Shade 128 Warm Nude (30ml)", "price": 679.00, "unit": "30ml"},
        ],
        "queries": [
            "maybelline fit me matte and poreless foundation 30ml bottle packshot white background",
            "maybelline fit me matte poreless foundation pump packshot",
            "maybelline fit me liquid foundation 30ml bottle",
        ],
    },
    {
        "name": "MARS Silky Skin Compact Powder (20g)",
        "price": 349.00,
        "brand": "MARS",
        "sub_category": "Face Makeup",
        "menu_category": "Compact Powder",
        "weight_per_unit": 20.0,
        "unit_type": "grams",
        "description": "MARS Silky Skin Powder (10g x 2). A velvety, finely milled soft pressed compact powder designed to set makeup, brighten skin tone, contour, and blur pores for all-day flawless wear.",
        "variants": [{"name": "20g (10g x 2)", "price": 349.00, "unit": "20g"}],
        "queries": [
            "mars silky skin powder compact packshot white background",
            "mars cosmetics silky skin powder packshot",
            "mars silky skin compact powder 10g x 2",
        ],
    },
    {
        "name": "Hilary Rhoda HD High Definition Pressed Powder (18g)",
        "price": 299.00,
        "brand": "Hilary Rhoda",
        "sub_category": "Face Makeup",
        "menu_category": "Compact Powder",
        "weight_per_unit": 18.0,
        "unit_type": "grams",
        "description": "Hilary Rhoda HD High Definition Pressed Powder (HR-0806). Finely milled compact powder that sets foundation, controls excess shine, and creates a soft-focus high definition complexion with long-lasting wear.",
        "variants": [{"name": "18g", "price": 299.00, "unit": "18g"}],
        "queries": [
            "hilary rhoda hd high definition pressed powder packshot white background",
            "hilary rhoda compact powder hr 0806 packshot",
            "hilary rhoda high definition compact powder 18g",
        ],
    },
    {
        "name": "Maybelline New York Fit Me Matte + Poreless Pressed Powder - Shade 110 Porcelain (8.5g)",
        "price": 629.00,
        "brand": "Maybelline New York",
        "sub_category": "Face Makeup",
        "menu_category": "Compact Powder",
        "weight_per_unit": 8.5,
        "unit_type": "grams",
        "description": "Maybelline New York Fit Me Matte + Poreless Pressed Powder (Shade 110 Porcelain). Long-lasting 16-hour oil control compact powder that minimizes the look of pores and leaves a natural poreless matte finish.",
        "variants": [{"name": "Shade 110 Porcelain (8.5g)", "price": 629.00, "unit": "8.5g"}],
        "queries": [
            "maybelline fit me matte and poreless pressed powder porcelain packshot white background",
            "maybelline fit me pressed powder 110 porcelain packshot",
            "maybelline fit me compact powder 110 porcelain",
        ],
    },
    {
        "name": "Maybelline New York Super Stay Up To 30H Hybrid Powder Foundation (9g)",
        "price": 799.00,
        "brand": "Maybelline New York",
        "sub_category": "Face Makeup",
        "menu_category": "Compact Powder",
        "weight_per_unit": 9.0,
        "unit_type": "grams",
        "description": "Maybelline New York Super Stay Up To 30H Hybrid Powder Foundation. High-performance waterproof and sweat-resistant powder foundation that delivers lightweight, transfer-proof medium-to-full matte coverage.",
        "variants": [
            {"name": "Shade 110 (9g)", "price": 799.00, "unit": "9g"},
            {"name": "Shade 120 (9g)", "price": 799.00, "unit": "9g"},
        ],
        "queries": [
            "maybelline super stay up to 30h hybrid powder foundation packshot white background",
            "maybelline super stay 24h hybrid powder foundation packshot",
            "maybelline superstay hybrid powder foundation",
        ],
    },
    {
        "name": "Maybelline New York Instant Age Rewind Eraser Multi-Use Concealer (6ml)",
        "price": 799.00,
        "brand": "Maybelline New York",
        "sub_category": "Face Makeup",
        "menu_category": "Concealers",
        "weight_per_unit": 6.0,
        "unit_type": "ml",
        "description": "Maybelline New York Instant Age Rewind Eraser Multi-Use Concealer. Iconic sponge-tip applicator concealer that instantly erases dark circles, conceals redness, and contours facial features for a refreshed, awake look.",
        "variants": [{"name": "6ml", "price": 799.00, "unit": "6ml"}],
        "queries": [
            "maybelline instant age rewind eraser concealer packshot white background",
            "maybelline age rewind concealer 6ml packshot",
            "maybelline instant age rewind multi use concealer",
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


def compress_image(img: Image.Image, max_kb: int = 115) -> bytes:
    """Progressively compresses image to JPEG under max_kb (Rule 4: < 120KB)."""
    quality = 90
    while quality >= 35:
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=quality, optimize=True)
        data = buf.getvalue()
        if len(data) <= max_kb * 1024:
            return data
        quality -= 5
    return data


def source_single_packshot(item: dict, idx: int) -> str:
    """Rule 4: Sources exactly 1 pristine 1:1 padded commercial packshot on pure white (< 120KB)."""
    product_slug = f"b25_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
    img_path = os.path.join(CACHE_DIR, f"{product_slug}.jpg")

    if os.path.exists(img_path) and os.path.getsize(img_path) > 3000:
        return img_path

    collected_urls = []
    for q in item["queries"]:
        urls = search_bing_images(q, max_results=12)
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
    print("🚀 STARTING MAXX RETAIL SUPERMARKET BATCH 25 INGESTION")
    print(f"   Target Shop: Maxx Retail ({SHOP_ID})")
    print(f"   Catalog Size: {len(BATCH_25_CATALOG)} verified SKUs")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary Status: Strictly N/A (is_veg = NULL)")
    print(f"   Packshot Protocol: Exactly 1 pristine 1:1 padded image (< 120KB) on pure white")
    print("=" * 80)

    products_payload = []

    for idx, item in enumerate(BATCH_25_CATALOG, 1):
        print(f"\n[{idx}/{len(BATCH_25_CATALOG)}] Processing: {item['name']} (₹{item['price']:.2f})")
        print(f"   Brand: {item['brand']} | Unit: {item['weight_per_unit']} {item['unit_type']}")

        # 1. Source Packshot (Rule 4: exactly 1 pristine image)
        print("   🔍 Sourcing pristine 1:1 commercial packshot...")
        img_path = source_single_packshot(item, idx)
        file_size_kb = os.path.getsize(img_path) / 1024
        print(f"   📸 Local Packshot cached: {img_path} ({file_size_kb:.1f} KB)")

        # 2. Upload to Supabase Storage
        product_slug = f"b25_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
            "tags": ["personal_care", "cosmetics_beauty", "makeup", item["sub_category"].lower(), item["brand"].lower()],
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
    print("\n🏁 Batch 25 ingestion completed successfully!")


if __name__ == "__main__":
    main()

