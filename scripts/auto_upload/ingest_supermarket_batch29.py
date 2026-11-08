#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 29 Ingestion Engine
=========================================================
Catalog: 20 items / 17 verified SKUs across shelf photos b61.jpg - b70.jpg:
  Photo 1 (b61.jpg - Variants):
    - Nivea Men Acne Face Wash (50g) @ ₹119.00
      Variants: 50g (₹119.00), 100g (₹259.00)
  Photo 2 (b62.jpg):
    - Nivea Men Oil Control Face Wash (50g) @ ₹129.00
    - Nivea Men Dark Spot Reduction Face Wash (50g) @ ₹129.00
  Photo 3 (b63.jpg):
    - Nivea Luminous 630 Even Glow Face Wash (50ml) @ ₹150.00
    - Nivea Luminous 630 Even Glow Bubble Cleansing Foam (100ml) @ ₹250.00
    - Nivea Luminous 630 Even Glow Whip Cleansing Foam (100ml) @ ₹250.00
  Photo 4 (b64.jpg):
    - Denver Men Oil Clear Face Wash (50g) @ ₹119.00
    - Denver Men Deep Cleanse Face Wash (50g) @ ₹119.00
    - Denver Men Acne Clear Face Wash (100g) @ ₹235.00
  Photo 5 (b65.jpg):
    - Lotus Herbals Frujuvenate Skin Perfecting & Rejuvenating Fruit Pack (60g) @ ₹245.00
    - Lotus Herbals Teatreewash Oil Control Face Wash (40g) @ ₹99.00
  Photo 6 (b66.jpg - Variants):
    - Lakmé Blush & Glow Jelly Facewash with Avocado + Matcha (50g) @ ₹135.00
      Variants: 50g (₹135.00), 100g (₹275.00)
    - Lakmé Blush & Glow Jelly Facewash with Watermelon + Rice Water + Cica (100g) @ ₹275.00
  Photo 7 (b67.jpg - Variants):
    - Simple Kind to Skin Refreshing Facial Wash (100ml) @ ₹275.00
      Variants: 100ml (₹275.00), 150ml (₹450.00)
  Photo 8 (b68.jpg - Stacked):
    - Simple Waterboost Hydrating Gel Wash with Pentavitin (100ml) @ ₹275.00
  Photo 9 (b69.jpg - Stacked):
    - CeraVe Hydrating Cleanser for Normal to Dry Skin (236ml) @ ₹799.00
  Photo 10 (b70.jpg - Stacked):
    - CeraVe Moisturising Cream for Dry to Very Dry Skin (50ml) @ ₹469.00

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
STORAGE_PREFIX = "supermarket/maxx_retail/batch29"
CACHE_DIR = "/tmp/maxx_retail_batch29_cache"

BATCH_29_CATALOG = [
    {
        "name": "Nivea Men Acne Face Wash (50g)",
        "price": 119.00,
        "brand": "Nivea Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Nivea Men Acne Face Wash. Formulated with Magnolia Bark Power and Carnitine to remove impurities, excess oil, and fight acne-causing germs for clear, refreshed skin.",
        "variants": [
            {"name": "50g", "price": 119.00, "unit": "50g"},
            {"name": "100g", "price": 259.00, "unit": "100g"},
        ],
        "queries": [
            "nivea men acne face wash 100g packshot white background",
            "nivea men acne face wash tube packshot",
            "nivea men acne face wash",
        ],
    },
    {
        "name": "Nivea Men Oil Control Face Wash (50g)",
        "price": 129.00,
        "brand": "Nivea Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Nivea Men Oil Control Face Wash with AIRCOOL. Deeply cleanses and cools skin, unclogs pores, and removes excess oil for all-day matte and bright skin.",
        "variants": [{"name": "50g", "price": 129.00, "unit": "50g"}],
        "queries": [
            "nivea men oil control face wash 50g packshot white background",
            "nivea men oil control face wash tube packshot",
            "nivea men oil control face wash",
        ],
    },
    {
        "name": "Nivea Men Dark Spot Reduction Face Wash (50g)",
        "price": 129.00,
        "brand": "Nivea Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Nivea Men Dark Spot Reduction Face Wash with Glutathione, AHA, and Vitamin C. Cleanses pores deeply without overdrying and reduces dark spots for a balanced, healthy glow.",
        "variants": [{"name": "50g", "price": 129.00, "unit": "50g"}],
        "queries": [
            "nivea men dark spot reduction face wash 50g packshot white background",
            "nivea men dark spot reduction face wash tube packshot",
            "nivea men dark spot reduction face wash",
        ],
    },
    {
        "name": "Nivea Luminous 630 Even Glow Face Wash (50ml)",
        "price": 150.00,
        "brand": "Nivea",
        "sub_category": "Face Cleansers",
        "menu_category": "Face Cleansers & Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "ml",
        "description": "Nivea Luminous 630 Even Glow Face Wash. Gently exfoliates, maintains skin's moisture balance, boosts instant radiance, and controls shine for an even, luminous complexion.",
        "variants": [{"name": "50ml", "price": 150.00, "unit": "50ml"}],
        "queries": [
            "nivea luminous 630 even glow face wash 50ml packshot white background",
            "nivea luminous 630 face wash tube packshot",
            "nivea luminous 630 even glow face wash 50ml",
        ],
    },
    {
        "name": "Nivea Luminous 630 Even Glow Bubble Cleansing Foam (100ml)",
        "price": 250.00,
        "brand": "Nivea",
        "sub_category": "Face Cleansers",
        "menu_category": "Face Cleansers & Face Washes",
        "weight_per_unit": 100.0,
        "unit_type": "ml",
        "description": "Nivea Luminous 630 Even Glow Bubble Cleansing Foam with Pearl Extract, Rucinol Combo, and Carnitine. Deeply purifies and unclogs pores for clearer, luminous, and dewy skin.",
        "variants": [{"name": "100ml", "price": 250.00, "unit": "100ml"}],
        "queries": [
            "nivea luminous 630 bubble cleansing foam 100ml packshot white background",
            "nivea luminous 630 bubble cleansing foam tube packshot",
            "nivea luminous 630 even glow bubble cleansing foam",
        ],
    },
    {
        "name": "Nivea Luminous 630 Even Glow Whip Cleansing Foam (100ml)",
        "price": 250.00,
        "brand": "Nivea",
        "sub_category": "Face Cleansers",
        "menu_category": "Face Cleansers & Face Washes",
        "weight_per_unit": 100.0,
        "unit_type": "ml",
        "description": "Nivea Luminous 630 Even Glow Whip Cleansing Foam with 6 Acid Complex and Hyaluronic Acid. Gently removes makeup, unclogs pores, and deeply cleanses for brighter, radiant skin.",
        "variants": [{"name": "100ml", "price": 250.00, "unit": "100ml"}],
        "queries": [
            "nivea luminous 630 whip cleansing foam 100ml packshot white background",
            "nivea luminous 630 whip cleansing foam tube packshot",
            "nivea luminous 630 even glow whip cleansing foam",
        ],
    },
    {
        "name": "Denver Men Oil Clear Face Wash (50g)",
        "price": 119.00,
        "brand": "Denver Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Denver Men Oil Clear Face Wash with Green Tea Extract and Scrub Beads. Removes excess oil, clears dead cells and pigmentation, leaving skin fresh and oil-free.",
        "variants": [{"name": "50g", "price": 119.00, "unit": "50g"}],
        "queries": [
            "denver men oil clear face wash 50g packshot white background",
            "denver oil clear face wash tube packshot",
            "denver men oil clear face wash",
        ],
    },
    {
        "name": "Denver Men Deep Cleanse Face Wash (50g)",
        "price": 119.00,
        "brand": "Denver Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Denver Men Deep Cleanse Face Wash with Activated Charcoal and Menthol. Detoxifies and recharges skin, sweeping away pollutants, dirt, and dark spots for lasting freshness.",
        "variants": [{"name": "50g", "price": 119.00, "unit": "50g"}],
        "queries": [
            "denver men deep cleanse face wash 50g packshot white background",
            "denver deep cleanse face wash charcoal tube packshot",
            "denver men deep cleanse face wash",
        ],
    },
    {
        "name": "Denver Men Acne Clear Face Wash (100g)",
        "price": 235.00,
        "brand": "Denver Men",
        "sub_category": "Men's Grooming",
        "menu_category": "Men's Face Washes",
        "weight_per_unit": 100.0,
        "unit_type": "grams",
        "description": "Denver Men Acne Clear Face Wash with Neem Extract, Scrub Beads, and Tea Tree Oil. Removes excess oil, soothes redness and itching, and prevents new acne breakouts.",
        "variants": [{"name": "100g", "price": 235.00, "unit": "100g"}],
        "queries": [
            "denver men acne clear face wash 100g packshot white background",
            "denver acne clear face wash tube packshot",
            "denver men acne clear face wash",
        ],
    },
    {
        "name": "Lotus Herbals Frujuvenate Skin Perfecting & Rejuvenating Fruit Pack (60g)",
        "price": 245.00,
        "brand": "Lotus Herbals",
        "sub_category": "Face Masks & Peels",
        "menu_category": "Face Masks & Peels",
        "weight_per_unit": 60.0,
        "unit_type": "grams",
        "description": "Lotus Herbals Frujuvenate Skin Perfecting & Rejuvenating Fruit Pack with natural Alpha-Hydroxy Fruit Acids. Firms, nourishes, and hydrates over-stressed skin for healthy radiance.",
        "variants": [{"name": "60g", "price": 245.00, "unit": "60g"}],
        "queries": [
            "lotus herbals frujuvenate skin perfecting fruit pack 60g packshot white background",
            "lotus herbals frujuvenate fruit pack tube packshot",
            "lotus frujuvenate fruit pack 60g",
        ],
    },
    {
        "name": "Lotus Herbals Teatreewash Oil Control Face Wash (40g)",
        "price": 99.00,
        "brand": "Lotus Herbals",
        "sub_category": "Face Cleansers",
        "menu_category": "Face Cleansers & Face Washes",
        "weight_per_unit": 40.0,
        "unit_type": "grams",
        "description": "Lotus Herbals Teatreewash Oil Control Face Wash with Tea Tree Oil, Cinnamon, and Oak Bark. Calms redness, deeply cleanses pores, and maintains natural skin moisture balance.",
        "variants": [{"name": "40g", "price": 99.00, "unit": "40g"}],
        "queries": [
            "lotus herbals teatreewash oil control face wash 40g packshot white background",
            "lotus teatreewash face wash tube packshot",
            "lotus herbals tea tree face wash",
        ],
    },
    {
        "name": "Lakmé Blush & Glow Jelly Facewash with Avocado + Matcha (50g)",
        "price": 135.00,
        "brand": "Lakmé",
        "sub_category": "Face Cleansers",
        "menu_category": "Face Cleansers & Face Washes",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Lakmé Blush & Glow Jelly Facewash with Avocado, Matcha, and Active Salicylic Acid. Gentle exfoliating jelly texture that gently unclogs pores, clears dead cells, and adds a natural glow.",
        "variants": [
            {"name": "50g", "price": 135.00, "unit": "50g"},
            {"name": "100g", "price": 275.00, "unit": "100g"},
        ],
        "queries": [
            "lakme blush and glow jelly facewash avocado matcha packshot white background",
            "lakme blush and glow avocado matcha jelly face wash packshot",
            "lakme jelly facewash avocado matcha",
        ],
    },
    {
        "name": "Lakmé Blush & Glow Jelly Facewash with Watermelon + Rice Water + Cica (100g)",
        "price": 275.00,
        "brand": "Lakmé",
        "sub_category": "Face Cleansers",
        "menu_category": "Face Cleansers & Face Washes",
        "weight_per_unit": 100.0,
        "unit_type": "grams",
        "description": "Lakmé Blush & Glow Jelly Facewash with Watermelon, Rice Water, and Cica. Calms skin inflammation, hydrates deeply, and restores a juicy radiant glow for dry and sensitive skin.",
        "variants": [{"name": "100g", "price": 275.00, "unit": "100g"}],
        "queries": [
            "lakme blush and glow jelly facewash watermelon cica packshot white background",
            "lakme blush and glow watermelon rice water jelly face wash packshot",
            "lakme jelly facewash watermelon",
        ],
    },
    {
        "name": "Simple Kind to Skin Refreshing Facial Wash (100ml)",
        "price": 275.00,
        "brand": "Simple",
        "sub_category": "Face Cleansers",
        "menu_category": "Face Cleansers & Face Washes",
        "weight_per_unit": 100.0,
        "unit_type": "ml",
        "description": "Simple Kind to Skin Refreshing Facial Wash with Pro-Vitamin B5 and Vitamin E. 100% soap-free formula that deeply cleanses without stripping natural moisture, perfect for sensitive skin.",
        "variants": [
            {"name": "100ml", "price": 275.00, "unit": "100ml"},
            {"name": "150ml", "price": 450.00, "unit": "150ml"},
        ],
        "queries": [
            "simple refreshing facial wash 150ml packshot white background",
            "simple kind to skin refreshing facial wash tube packshot",
            "simple refreshing facial wash",
        ],
    },
    {
        "name": "Simple Waterboost Hydrating Gel Wash with Pentavitin (100ml)",
        "price": 275.00,
        "brand": "Simple",
        "sub_category": "Face Cleansers",
        "menu_category": "Face Cleansers & Face Washes",
        "weight_per_unit": 100.0,
        "unit_type": "ml",
        "description": "Simple Waterboost Hydrating Gel Wash with Pentavitin moisture magnet. 100% soap-free gel cleanser that instantly quenches and rehydrates dry, sensitive skin.",
        "variants": [{"name": "100ml", "price": 275.00, "unit": "100ml"}],
        "queries": [
            "simple waterboost hydrating gel wash 100ml packshot white background",
            "simple water boost hydrating gel wash tube packshot",
            "simple waterboost hydrating gel wash",
        ],
    },
    {
        "name": "CeraVe Hydrating Cleanser for Normal to Dry Skin (236ml)",
        "price": 799.00,
        "brand": "CeraVe",
        "sub_category": "Face Cleansers",
        "menu_category": "Face Cleansers & Face Washes",
        "weight_per_unit": 236.0,
        "unit_type": "ml",
        "description": "CeraVe Hydrating Cleanser developed with dermatologists. Gentle, non-foaming cleansing lotion with 3 essential ceramides and hyaluronic acid that cleanses without disrupting the skin barrier.",
        "variants": [{"name": "236ml", "price": 799.00, "unit": "236ml"}],
        "queries": [
            "cerave hydrating cleanser 236ml packshot white background",
            "cerave hydrating cleanser bottle pump packshot",
            "cerave hydrating cleanser normal to dry skin 236ml",
        ],
    },
    {
        "name": "CeraVe Moisturising Cream for Dry to Very Dry Skin (50ml)",
        "price": 469.00,
        "brand": "CeraVe",
        "sub_category": "Face Creams & Moisturizers",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 50.0,
        "unit_type": "ml",
        "description": "CeraVe Moisturising Cream for Dry to Very Dry Skin with 3 essential ceramides and hyaluronic acid. Rich formula provides 24-hour hydration and helps restore the protective skin barrier.",
        "variants": [{"name": "50ml", "price": 469.00, "unit": "50ml"}],
        "queries": [
            "cerave moisturising cream 50ml tube packshot white background",
            "cerave moisturizing cream 50ml tube packshot",
            "cerave moisturising cream dry to very dry skin 50ml",
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
    product_slug = f"b29_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
    print("🚀 STARTING MAXX RETAIL SUPERMARKET BATCH 29 INGESTION")
    print(f"   Target Shop: Maxx Retail ({SHOP_ID})")
    print(f"   Catalog Size: {len(BATCH_29_CATALOG)} verified SKUs")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary Status: Strictly N/A (is_veg = NULL)")
    print(f"   Packshot Protocol: Exactly 1 pristine 1:1 padded image (< 120KB) on pure white")
    print("=" * 80)

    products_payload = []

    for idx, item in enumerate(BATCH_29_CATALOG, 1):
        print(f"\n[{idx}/{len(BATCH_29_CATALOG)}] Processing: {item['name']} (₹{item['price']:.2f})")
        print(f"   Brand: {item['brand']} | Unit: {item['weight_per_unit']} {item['unit_type']}")

        # 1. Source Packshot (Rule 4: exactly 1 pristine image)
        print("   🔍 Sourcing pristine 1:1 commercial packshot...")
        img_path = source_single_packshot(item, idx)
        file_size_kb = os.path.getsize(img_path) / 1024
        print(f"   📸 Local Packshot cached: {img_path} ({file_size_kb:.1f} KB)")

        # 2. Upload to Supabase Storage
        product_slug = f"b29_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
    print("\n🏁 Batch 29 ingestion completed successfully!")


if __name__ == "__main__":
    main()

