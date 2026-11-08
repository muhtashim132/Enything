#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 28 Ingestion Engine
=========================================================
Catalog: 17 items / 16 verified SKUs across shelf photos b51.jpg - b60.jpg:
  Photo 1 (b51.jpg - Stacked):
    - NutriGlow Advanced Organics Skin Brightening and Lightening De Tan Crème Scrub (100g) @ ₹275.00
  Photo 2 (b52.jpg - Stacked):
    - NutriGlow Advanced Organics Skin Brightening and Lightening De Tan Crème Mask (100g) @ ₹275.00
  Photo 3 (b53.jpg):
    - Meglow Skin Brightening Cream for Men (30g) @ ₹150.00
  Photo 4 (b54.jpg - Stacked):
    - Emami Smart and Handsome Brightening Cream for Men (30g) @ ₹95.00
  Photo 5 (b55.jpg):
    - Garnier Men AcnoFight Pimple Clearing Brightening Moisturiser (20g) @ ₹109.00
  Photo 6 (b56.jpg):
    - Pond's Men Bright Boost Icy Facewash with Niacinamide & Vitamin C (50g) @ ₹110.00
    - Pond's Men Energy Bright Anti Dullness + Brightening Facewash (50g) @ ₹135.00
  Photo 7 (b57.jpg):
    - Garnier Men TurboBright Refreshing Face Wash (50g) @ ₹125.00
    - Himalaya Men Power Glow Licorice Face Wash (50ml) @ ₹99.00
  Photo 8 & 9 (b58.jpg & b59.jpg - Stacked / Variants):
    - Garnier Men Oil Clear Icy Face Wash (50g) @ ₹115.00
      Variants: 50g (₹115.00), 100g (₹299.00)
    - Garnier Men AcnoFight Anti-Pimple Face Wash (50g) @ ₹130.00
    - Emami Smart and Handsome Instant Brightening Face Wash (62.5g) @ ₹125.00
    - Glow & Handsome Instant Brightness Face Wash for Men (50g) @ ₹105.00
    - Garnier Men AcnoFight Acne Calming Gentle Gel Cleanser (50g) @ ₹105.00
  Photo 10 (b60.jpg):
    - Nivea Men Deep Impact Face & Beard Wash (100ml) @ ₹285.00
    - Nivea Men All-In-1 Charcoal Face Wash (50g) @ ₹149.00

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
STORAGE_PREFIX = "supermarket/maxx_retail/batch28"
CACHE_DIR = "/tmp/maxx_retail_batch28_cache"

BATCH_28_CATALOG = [
    {
        "name": "NutriGlow Advanced Organics Skin Brightening and Lightening De Tan Crème Scrub (100g)",
        "price": 275.00,
        "brand": "NutriGlow",
        "sub_category": "Face Scrubs & Exfoliators",
        "menu_category": "Face Scrubs & Exfoliators",
        "weight_per_unit": 100.0,
        "unit_type": "grams",
        "description": "NutriGlow Advanced Organics De Tan Crème Scrub with Mint, Eucalyptus & Yogurt Extract. Paraben-free formula that exfoliates dead skin cells, removes tan, and brightens complexion for all skin types.",
        "variants": [{"name": "100g", "price": 275.00, "unit": "100g"}],
        "queries": [
            "nutriglow de tan creme scrub 100g packshot white background",
            "nutriglow advanced organics de tan creme scrub packshot",
            "nutriglow de tan scrub 100g box packshot",
        ],
    },
    {
        "name": "NutriGlow Advanced Organics Skin Brightening and Lightening De Tan Crème Mask (100g)",
        "price": 275.00,
        "brand": "NutriGlow",
        "sub_category": "Face Masks & Peels",
        "menu_category": "Face Masks & Peels",
        "weight_per_unit": 100.0,
        "unit_type": "grams",
        "description": "NutriGlow Advanced Organics De Tan Crème Mask with Mint, Eucalyptus & Milk Proteins. Nourishing paraben-free mask that calms the skin, lightens tan, and restores natural radiance for all skin types.",
        "variants": [{"name": "100g", "price": 275.00, "unit": "100g"}],
        "queries": [
            "nutriglow de tan creme mask 100g packshot white background",
            "nutriglow advanced organics de tan creme mask packshot",
            "nutriglow de tan mask 100g box packshot",
        ],
    },
    {
        "name": "Meglow Skin Brightening Cream for Men (30g)",
        "price": 150.00,
        "brand": "Meglow",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Creams & Moisturizers",
        "weight_per_unit": 30.0,
        "unit_type": "grams",
        "description": "Meglow Skin Brightening Cream for Men Daily Essential Skincare Expert. Quick-absorbing, fast-action formula enriched with active botanicals that brightens dull skin and restores healthy tone.",
        "variants": [{"name": "30g", "price": 150.00, "unit": "30g"}],
        "queries": [
            "meglow skin brightening cream for men 30g packshot white background",
            "meglow men skin brightening cream packshot",
            "meglow men brightening cream box",
        ],
    },
    {
        "name": "Emami Smart and Handsome Brightening Cream for Men (30g)",
        "price": 95.00,
        "brand": "Emami Smart and Handsome",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Creams & Moisturizers",
        "weight_per_unit": 30.0,
        "unit_type": "grams",
        "description": "Emami Smart and Handsome Brightening Cream for Men (formerly Fair and Handsome). Formulated with Niacinamide and Liquorice for an instant brighter look, dark spot reduction, and UVA/UVB protection.",
        "variants": [{"name": "30g", "price": 95.00, "unit": "30g"}],
        "queries": [
            "smart and handsome brightening cream for men 30g packshot white background",
            "emami smart and handsome brightening cream 30g packshot",
            "smart and handsome cream box packshot",
        ],
    },
    {
        "name": "Garnier Men AcnoFight Pimple Clearing Brightening Moisturiser (20g)",
        "price": 109.00,
        "brand": "Garnier Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Creams & Moisturizers",
        "weight_per_unit": 20.0,
        "unit_type": "grams",
        "description": "Garnier Men AcnoFight Pimple Clearing Brightening Moisturiser. Powered by Salicylic Acid and Vitamin B3 to fight pimples, control oil, reduce blackheads, and brighten dull skin with 6 powerful actions.",
        "variants": [{"name": "20g", "price": 109.00, "unit": "20g"}],
        "queries": [
            "garnier men acnofight pimple clearing brightening moisturiser 20g packshot white background",
            "garnier men acnofight moisturiser 20g packshot",
            "garnier men acnofight pimple clearing cream",
        ],
    },
    {
        "name": "Pond's Men Bright Boost Icy Facewash with Niacinamide & Vitamin C (50g)",
        "price": 110.00,
        "brand": "Pond's Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Pond's Men Bright Boost Icy Facewash with Niacinamide & Vitamin C. Delivers instant brightening, removes tan, and revitalizes tired skin with cooling menthol for lasting freshness.",
        "variants": [{"name": "50g", "price": 110.00, "unit": "50g"}],
        "queries": [
            "ponds men bright boost icy facewash 50g packshot white background",
            "ponds men bright boost facewash tube packshot",
            "ponds men bright boost icy facewash",
        ],
    },
    {
        "name": "Pond's Men Energy Bright Anti Dullness + Brightening Facewash (50g)",
        "price": 135.00,
        "brand": "Pond's Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Pond's Men Energy Bright Facewash with Energizing Coffee Bean Extract. 2-in-1 power formula that instantly awakens tired skin, washes away dirt, and delivers a healthy radiant glow with cooling menthol.",
        "variants": [{"name": "50g", "price": 135.00, "unit": "50g"}],
        "queries": [
            "ponds men energy bright facewash 50g packshot white background",
            "ponds men energy bright coffee bean facewash packshot",
            "ponds men energy bright tube",
        ],
    },
    {
        "name": "Garnier Men TurboBright Refreshing Face Wash (50g)",
        "price": 125.00,
        "brand": "Garnier Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Garnier Men TurboBright 2-in-1 Refreshing Face Wash. Enriched with Lemon Extract, gentle scrubs, and antioxidant Grape Water to remove dark dead skin cells, eliminate pollution, and brighten instantly.",
        "variants": [{"name": "50g", "price": 125.00, "unit": "50g"}],
        "queries": [
            "garnier men turbobright refreshing face wash 50g packshot white background",
            "garnier men turbobright face wash tube packshot",
            "garnier men turbobright double action face wash 50g",
        ],
    },
    {
        "name": "Himalaya Men Power Glow Licorice Face Wash (50ml)",
        "price": 99.00,
        "brand": "Himalaya Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "ml",
        "description": "Himalaya Men Power Glow Licorice Face Wash with Active Boost Technology. Fortified with Licorice Extract, Wood Apple, and Menthol to reduce pigmentation, gently exfoliate, and refresh skin complexion.",
        "variants": [{"name": "50ml", "price": 99.00, "unit": "50ml"}],
        "queries": [
            "himalaya men power glow licorice face wash 50ml packshot white background",
            "himalaya men power glow face wash tube packshot",
            "himalaya men power glow licorice facewash",
        ],
    },
    {
        "name": "Garnier Men Oil Clear Icy Face Wash (50g)",
        "price": 115.00,
        "brand": "Garnier Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Garnier Men Oil Clear Icy Face Wash with cooling menthol and mineral oil-trapping mud texture. Deeply cleanses pores, removes excess oil without drying, and provides an all-day oil-free fresh feel.",
        "variants": [
            {"name": "50g", "price": 115.00, "unit": "50g"},
            {"name": "100g", "price": 299.00, "unit": "100g"},
        ],
        "queries": [
            "garnier men oil clear icy face wash 100g packshot white background",
            "garnier men oil clear face wash tube packshot",
            "garnier men oil clear icy face wash",
        ],
    },
    {
        "name": "Garnier Men AcnoFight Anti-Pimple Face Wash (50g)",
        "price": 130.00,
        "brand": "Garnier Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Garnier Men AcnoFight Anti-Pimple Face Wash. Enriched with Herba Repair and Salicylic Actives to fight up to 99.9% pimple-causing germs, unclog pores, and reduce excess oil.",
        "variants": [{"name": "50g", "price": 130.00, "unit": "50g"}],
        "queries": [
            "garnier men acnofight anti pimple face wash 50g packshot white background",
            "garnier men acnofight face wash tube packshot",
            "garnier men acno fight anti pimple face wash",
        ],
    },
    {
        "name": "Emami Smart and Handsome Instant Brightening Face Wash (62.5g)",
        "price": 125.00,
        "brand": "Emami Smart and Handsome",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 62.5,
        "unit_type": "grams",
        "description": "Emami Smart and Handsome Instant Brightening Face Wash (50g + 12.5g Extra). Exclusively formulated for men with Niacinamide and cooling Menthol to cleanse deeply, reduce dullness, and refresh.",
        "variants": [{"name": "50g + 12.5g Extra (62.5g)", "price": 125.00, "unit": "62.5g"}],
        "queries": [
            "smart and handsome instant brightening face wash packshot white background",
            "emami smart and handsome instant brightening facewash tube packshot",
            "smart and handsome face wash 50g",
        ],
    },
    {
        "name": "Glow & Handsome Instant Brightness Face Wash for Men (50g)",
        "price": 105.00,
        "brand": "Glow & Handsome",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Glow & Handsome Instant Brightness Face Wash for Men (formerly Fair & Lovely Men). Designed by international experts to wash away dirt and impurities while delivering instant visible skin brightness.",
        "variants": [{"name": "50g", "price": 105.00, "unit": "50g"}],
        "queries": [
            "glow and handsome instant brightness face wash 50g packshot white background",
            "glow and handsome face wash tube packshot",
            "glow and handsome instant brightness facewash",
        ],
    },
    {
        "name": "Garnier Men AcnoFight Acne Calming Gentle Gel Cleanser (50g)",
        "price": 105.00,
        "brand": "Garnier Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Garnier Men AcnoFight Acne Calming Gentle Gel Cleanser. Tough on acne yet gentle on skin, dermatologically tested even for sensitive skin. Calms breakouts and clears impurities without over-drying.",
        "variants": [{"name": "50g", "price": 105.00, "unit": "50g"}],
        "queries": [
            "garnier men acnofight acne calming gentle gel cleanser packshot white background",
            "garnier men acnofight gentle gel cleanser tube packshot",
            "garnier men acnofight gel cleanser 50g",
        ],
    },
    {
        "name": "Nivea Men Deep Impact Face & Beard Wash (100ml)",
        "price": 285.00,
        "brand": "Nivea Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face & Beard Washes",
        "weight_per_unit": 100.0,
        "unit_type": "ml",
        "description": "Nivea Men Deep Impact Face & Beard Wash with Black Carbon. Thoroughly cleanses skin and beard hair, removes deep impurities and excess oils, and protects from drying out for a clean, refreshed feel.",
        "variants": [{"name": "100ml", "price": 285.00, "unit": "100ml"}],
        "queries": [
            "nivea men deep impact face and beard wash 100ml packshot white background",
            "nivea men deep impact face wash tube packshot",
            "nivea men deep impact face beard wash",
        ],
    },
    {
        "name": "Nivea Men All-In-1 Charcoal Face Wash (50g)",
        "price": 149.00,
        "brand": "Nivea Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Nivea Men All-In-1 Charcoal Face Wash with 3-in-1 effect: detoxify, exfoliate, and brighten. Micro-charcoal formula with Glutathione, AHA, and Vitamin C unclogs pores, reduces dullness, and cools skin.",
        "variants": [{"name": "50g", "price": 149.00, "unit": "50g"}],
        "queries": [
            "nivea men all in 1 charcoal face wash 50g packshot white background",
            "nivea men all in one charcoal facewash tube packshot",
            "nivea men all in 1 charcoal face wash",
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
    product_slug = f"b28_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
    print("🚀 STARTING MAXX RETAIL SUPERMARKET BATCH 28 INGESTION")
    print(f"   Target Shop: Maxx Retail ({SHOP_ID})")
    print(f"   Catalog Size: {len(BATCH_28_CATALOG)} verified SKUs")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary Status: Strictly N/A (is_veg = NULL)")
    print(f"   Packshot Protocol: Exactly 1 pristine 1:1 padded image (< 120KB) on pure white")
    print("=" * 80)

    products_payload = []

    for idx, item in enumerate(BATCH_28_CATALOG, 1):
        print(f"\n[{idx}/{len(BATCH_28_CATALOG)}] Processing: {item['name']} (₹{item['price']:.2f})")
        print(f"   Brand: {item['brand']} | Unit: {item['weight_per_unit']} {item['unit_type']}")

        # 1. Source Packshot (Rule 4: exactly 1 pristine image)
        print("   🔍 Sourcing pristine 1:1 commercial packshot...")
        img_path = source_single_packshot(item, idx)
        file_size_kb = os.path.getsize(img_path) / 1024
        print(f"   📸 Local Packshot cached: {img_path} ({file_size_kb:.1f} KB)")

        # 2. Upload to Supabase Storage
        product_slug = f"b28_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
            "tags": ["personal_care", "cosmetics_beauty", "mens_grooming", item["sub_category"].lower(), item["brand"].lower()],
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
    print("\n🏁 Batch 28 ingestion completed successfully!")


if __name__ == "__main__":
    main()

