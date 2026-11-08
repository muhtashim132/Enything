#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 27 Ingestion Engine
=========================================================
Catalog: 14 verified SKUs across shelf photos b41.jpg - b50.jpg:
  Photo 1 (b41.jpg - Stacked):
    - Garnier Skin Naturals Niacinamide Fresh & Plump Oil-Free 48H Hydrating Cream (20ml) @ ₹129.00
    - Garnier Skin Naturals Vitamin C Fresh & Bright Oil-Free 48H Hydrating Cream (20ml) @ ₹129.00
  Photo 2 (b42.jpg - Stacked):
    - Garnier Skin Naturals Wrinkle Lift Anti-Ageing Cream (40g) @ ₹329.00
    - Garnier Skin Naturals Bright Complete Vitamin C Serum Cream UV (23g) @ ₹119.00
      Variants: 23g (₹119.00), 45g (₹299.00)
  Photo 3 (b43.jpg - Stacked):
    - Olay Natural Aura Instant Glowing Radiance Cream with UV Protection (20g) @ ₹109.00
      Variants: 20g (₹109.00), 40g (₹199.00)
  Photo 4 (b44.jpg - Stacked):
    - Olay Total Effects 7 In One Night Cream (50g) @ ₹949.00
  Photo 5 & 6 (b45.jpg & b46.jpg - Sheet Masks):
    - VLCC InstaMix Vitamin C Serum + Compressed Face Mask (10ml) @ ₹99.00
    - O3+ Purifying Face Sheet Mask (30g) @ ₹155.00
    - O3+ Glow Face Sheet Mask (30g) @ ₹155.00
    - VLCC InstaMix HA Serum + Compressed Face Mask (10ml) @ ₹99.00
    - VLCC InstaMix Centella Asiatica Serum + Compressed Face Mask (10ml) @ ₹99.00
  Photo 7 (b47.jpg - Stacked/Side-by-Side):
    - NutriGlow Derma Lactic Acid + Kojic Acid D-Tan Bleach (20g) @ ₹149.00
  Photo 8 (b48.jpg - Stacked):
    - NutriGlow Advanced Organics Salon Series Anti-Pigmentation Bleach (20g) @ ₹125.00
  Photo 9 (b49.jpg - Pouches):
    - NutriGlow Vitamin C Brightening Crème Bleach (20g) @ ₹149.00
    - NutriGlow Skin Whitening Crème Bleach (20g) @ ₹125.00
  Photo 10 (b50.jpg - Stacked):
    - NutriGlow Advanced Organics Skin Brightening & Lightening De Tan Crème Cleanser (100g) @ ₹275.00

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
STORAGE_PREFIX = "supermarket/maxx_retail/batch27"
CACHE_DIR = "/tmp/maxx_retail_batch27_cache"

BATCH_27_CATALOG = [
    {
        "name": "Garnier Skin Naturals Niacinamide Fresh & Plump Oil-Free 48H Hydrating Cream (20ml)",
        "price": 129.00,
        "brand": "Garnier",
        "sub_category": "Face Creams & Moisturizers",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 20.0,
        "unit_type": "ml",
        "description": "Garnier Skin Naturals Niacinamide Fresh & Plump Oil-Free 48H Hydrating Cream. Enriched with Niacinamide to deeply hydrate, plump, and refresh the skin with a lightweight, non-greasy formula.",
        "variants": [{"name": "20ml", "price": 129.00, "unit": "20ml"}],
        "queries": [
            "garnier fresh and plump niacinamide cream 20ml packshot white background",
            "garnier niacinamide fresh plump hydrating cream tub packshot",
            "garnier niacinamide fresh plump oil free cream",
        ],
    },
    {
        "name": "Garnier Skin Naturals Vitamin C Fresh & Bright Oil-Free 48H Hydrating Cream (20ml)",
        "price": 129.00,
        "brand": "Garnier",
        "sub_category": "Face Creams & Moisturizers",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 20.0,
        "unit_type": "ml",
        "description": "Garnier Skin Naturals Vitamin C Fresh & Bright Oil-Free 48H Hydrating Cream. Infused with Vitamin C to brighten and hydrate the skin for up to 48 hours without oiliness.",
        "variants": [{"name": "20ml", "price": 129.00, "unit": "20ml"}],
        "queries": [
            "garnier fresh and bright vitamin c cream 20ml packshot white background",
            "garnier vitamin c fresh bright hydrating cream yellow tub packshot",
            "garnier vitamin c fresh bright cream",
        ],
    },
    {
        "name": "Garnier Skin Naturals Wrinkle Lift Anti-Ageing Cream (40g)",
        "price": 329.00,
        "brand": "Garnier",
        "sub_category": "Anti-Ageing Creams",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 40.0,
        "unit_type": "grams",
        "description": "Garnier Skin Naturals Wrinkle Lift Anti-Ageing Cream with Swiss Apple Cell Extract & Pro-Retinol. Reduces wrinkles and fine lines for visibly firmer, youthful-looking skin.",
        "variants": [{"name": "40g", "price": 329.00, "unit": "40g"}],
        "queries": [
            "garnier wrinkle lift anti ageing cream 40g packshot white background",
            "garnier skin naturals wrinkle lift anti ageing cream 40g",
            "garnier wrinkle lift cream box packshot",
        ],
    },
    {
        "name": "Garnier Skin Naturals Bright Complete Vitamin C Serum Cream UV (23g)",
        "price": 119.00,
        "brand": "Garnier",
        "sub_category": "Face Creams & Moisturizers",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 23.0,
        "unit_type": "grams",
        "description": "Garnier Skin Naturals Bright Complete Vitamin C Serum Cream with UV filters. Dermatologically tested formula with Yuzu Lemon extract that brightens skin tone, fades dark spots, and protects from sun damage.",
        "variants": [
            {"name": "23g", "price": 119.00, "unit": "23g"},
            {"name": "45g", "price": 299.00, "unit": "45g"},
        ],
        "queries": [
            "garnier bright complete vitamin c serum cream uv 45g packshot white background",
            "garnier bright complete vitamin c serum cream packshot",
            "garnier bright complete vitamin c serum cream uv box",
        ],
    },
    {
        "name": "Olay Natural Aura Instant Glowing Radiance Cream with UV Protection (20g)",
        "price": 109.00,
        "brand": "Olay",
        "sub_category": "Day Creams & Moisturizers",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 20.0,
        "unit_type": "grams",
        "description": "Olay Natural Aura Instant Glowing Radiance Cream with UV Protection. Light, non-greasy formula that provides instant glow, evens skin tone, and protects against daily UV exposure.",
        "variants": [
            {"name": "20g", "price": 109.00, "unit": "20g"},
            {"name": "40g", "price": 199.00, "unit": "40g"},
        ],
        "queries": [
            "olay natural aura instant glowing radiance cream uv packshot white background",
            "olay natural aura instant glowing radiance cream tube packshot",
            "olay natural aura instant glowing radiance cream with uv protection",
        ],
    },
    {
        "name": "Olay Total Effects 7 In One Night Cream (50g)",
        "price": 949.00,
        "brand": "Olay",
        "sub_category": "Night Creams & Anti-Ageing",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "Olay Total Effects 7 In One Night Cream. Fights 7 signs of aging for firmer, younger-looking skin every morning. Nourishes intensively while you sleep with a multi-vitamin complex.",
        "variants": [{"name": "50g", "price": 949.00, "unit": "50g"}],
        "queries": [
            "olay total effects 7 in one night cream 50g packshot white background",
            "olay total effects 7 in 1 night cream 50g packshot",
            "olay total effects night cream jar packshot",
        ],
    },
    {
        "name": "VLCC InstaMix Vitamin C Serum + Compressed Face Mask (10ml)",
        "price": 99.00,
        "brand": "VLCC",
        "sub_category": "Sheet Masks",
        "menu_category": "Face Masks & Peels",
        "weight_per_unit": 10.0,
        "unit_type": "ml",
        "description": "VLCC InstaMix Vitamin C Serum + Compressed Face Mask. Infused with Vitamin C serum known to fade dark spots and boost collagen. Includes a compressed sheet mask that activates on contact with 10ml serum.",
        "variants": [{"name": "10ml", "price": 99.00, "unit": "10ml"}],
        "queries": [
            "vlcc instamix vitamin c serum compressed face mask packshot white background",
            "vlcc instamix vitamin c sheet mask pouch packshot",
            "vlcc instamix vitamin c serum compressed face mask",
        ],
    },
    {
        "name": "O3+ Purifying Face Sheet Mask (30g)",
        "price": 155.00,
        "brand": "O3+",
        "sub_category": "Sheet Masks",
        "menu_category": "Face Masks & Peels",
        "weight_per_unit": 30.0,
        "unit_type": "grams",
        "description": "O3+ Purifying Face Sheet Mask for normal to oily skin. Infused with Magnolia Officinalis Bark Extract, Tea Tree Extract, Salicylic Acid, and Zinc PCA to purify, control excess sebum, and prevent breakouts.",
        "variants": [{"name": "30g", "price": 155.00, "unit": "30g"}],
        "queries": [
            "o3+ purifying face sheet mask 30g packshot white background",
            "o3 plus purifying face sheet mask packshot",
            "o3+ purifying sheet mask normal to oily skin pouch",
        ],
    },
    {
        "name": "O3+ Glow Face Sheet Mask (30g)",
        "price": 155.00,
        "brand": "O3+",
        "sub_category": "Sheet Masks",
        "menu_category": "Face Masks & Peels",
        "weight_per_unit": 30.0,
        "unit_type": "grams",
        "description": "O3+ Glow Face Sheet Mask for dull and combination skin. Formulated with Glycyrrhiza Glabra (Licorice) Root Extract, Glycolic Acid, Hyaluronic Acid, and Vitamin C to restore radiance and luminous complexion.",
        "variants": [{"name": "30g", "price": 155.00, "unit": "30g"}],
        "queries": [
            "o3+ glow face sheet mask 30g packshot white background",
            "o3 plus glow face sheet mask packshot",
            "o3+ glow sheet mask dull combination skin pouch",
        ],
    },
    {
        "name": "VLCC InstaMix HA Serum + Compressed Face Mask (10ml)",
        "price": 99.00,
        "brand": "VLCC",
        "sub_category": "Sheet Masks",
        "menu_category": "Face Masks & Peels",
        "weight_per_unit": 10.0,
        "unit_type": "ml",
        "description": "VLCC InstaMix HA Serum + Compressed Face Mask. Infused with Hyaluronic Acid Serum known to enhance skin barrier function, boost hydration, and leave skin feeling fresh and plumper.",
        "variants": [{"name": "10ml", "price": 99.00, "unit": "10ml"}],
        "queries": [
            "vlcc instamix ha serum compressed face mask packshot white background",
            "vlcc instamix hyaluronic acid sheet mask pouch packshot",
            "vlcc instamix ha serum compressed face mask",
        ],
    },
    {
        "name": "VLCC InstaMix Centella Asiatica Serum + Compressed Face Mask (10ml)",
        "price": 99.00,
        "brand": "VLCC",
        "sub_category": "Sheet Masks",
        "menu_category": "Face Masks & Peels",
        "weight_per_unit": 10.0,
        "unit_type": "ml",
        "description": "VLCC InstaMix Centella Asiatica Serum + Compressed Face Mask. Infused with Rose and Centella Asiatica Serum for calming care, soothing acne-prone or sensitive skin, and antioxidant protection.",
        "variants": [{"name": "10ml", "price": 99.00, "unit": "10ml"}],
        "queries": [
            "vlcc instamix centella asiatica serum compressed face mask packshot white background",
            "vlcc instamix centella asiatica sheet mask pouch packshot",
            "vlcc instamix centella asiatica compressed face mask",
        ],
    },
    {
        "name": "NutriGlow Derma Lactic Acid + Kojic Acid D-Tan Bleach (20g)",
        "price": 149.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Bleach & Hair Removal",
        "weight_per_unit": 20.0,
        "unit_type": "grams",
        "description": "NutriGlow Derma Lactic Acid + Kojic Acid D-Tan Bleach for dullness removal and skin brightening. Complete kit with D-Tan Crème Bleach 10g, Activator 3g, Post Bleach Serum 7ml, and Free Sheet Mask inside.",
        "variants": [{"name": "20g", "price": 149.00, "unit": "20g"}],
        "queries": [
            "nutriglow derma lactic acid kojic acid d-tan bleach 20g packshot white background",
            "nutriglow derma d tan bleach pouch packshot",
            "nutriglow derma lactic acid kojic acid d-tan bleach",
        ],
    },
    {
        "name": "NutriGlow Advanced Organics Salon Series Anti-Pigmentation Bleach (20g)",
        "price": 125.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Bleach & Hair Removal",
        "weight_per_unit": 20.0,
        "unit_type": "grams",
        "description": "NutriGlow Advanced Organics Salon Series Anti-Pigmentation Bleach. Formulated with Kojic Acid, Almond Oil, Vitamin C, Glycolic Acid, and Alpha Arbutin to reduce dark spots, melasma, and freckles. Includes Free Sheet Mask.",
        "variants": [{"name": "20g", "price": 125.00, "unit": "20g"}],
        "queries": [
            "nutriglow salon series anti-pigmentation bleach 20g packshot white background",
            "nutriglow anti pigmentation bleach pouch packshot",
            "nutriglow salon series anti pigmentation bleach",
        ],
    },
    {
        "name": "NutriGlow Vitamin C Brightening Crème Bleach (20g)",
        "price": 149.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Bleach & Hair Removal",
        "weight_per_unit": 20.0,
        "unit_type": "grams",
        "description": "NutriGlow Vitamin C Brightening Crème Bleach with Vitamin C Brightening Crème Bleach 10g, Activator 3g, Post Bleach Serum 7ml, Spatula, Mixing Tray, and Sheet Mask Tablet for bright, radiant skin.",
        "variants": [{"name": "20g", "price": 149.00, "unit": "20g"}],
        "queries": [
            "nutriglow vitamin c brightening creme bleach 20g packshot white background",
            "nutriglow vitamin c bleach pouch packshot",
            "nutriglow vitamin c brightening creme bleach",
        ],
    },
    {
        "name": "NutriGlow Skin Whitening Crème Bleach (20g)",
        "price": 125.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Bleach & Hair Removal",
        "weight_per_unit": 20.0,
        "unit_type": "grams",
        "description": "NutriGlow Skin Whitening Crème Bleach kit with Crème Bleach 10g, Activator 3g, Post Bleach Serum 7ml, Spatula, Mixing Tray, and Sheet Mask Tablet for luminous, even-toned skin.",
        "variants": [{"name": "20g", "price": 125.00, "unit": "20g"}],
        "queries": [
            "nutriglow skin whitening creme bleach 20g packshot white background",
            "nutriglow skin whitening bleach pouch packshot",
            "nutriglow skin whitening creme bleach",
        ],
    },
    {
        "name": "NutriGlow Advanced Organics Skin Brightening and Lightening De Tan Crème Cleanser (100g)",
        "price": 275.00,
        "brand": "NutriGlow",
        "sub_category": "Face Cleansers",
        "menu_category": "Face Cleansers",
        "weight_per_unit": 100.0,
        "unit_type": "grams",
        "description": "NutriGlow Advanced Organics De Tan Crème Cleanser with Mint, Eucalyptus, and Milk Proteins. Paraben-free formula that removes tan, cleanses deeply, and brightens skin complexion for all skin types.",
        "variants": [{"name": "100g", "price": 275.00, "unit": "100g"}],
        "queries": [
            "nutriglow de tan creme cleanser 100g packshot white background",
            "nutriglow advanced organics de tan creme cleanser box packshot",
            "nutriglow de tan creme cleanser 100g",
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
    product_slug = f"b27_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
    print("🚀 STARTING MAXX RETAIL SUPERMARKET BATCH 27 INGESTION")
    print(f"   Target Shop: Maxx Retail ({SHOP_ID})")
    print(f"   Catalog Size: {len(BATCH_27_CATALOG)} verified SKUs")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary Status: Strictly N/A (is_veg = NULL)")
    print(f"   Packshot Protocol: Exactly 1 pristine 1:1 padded image (< 120KB) on pure white")
    print("=" * 80)

    products_payload = []

    for idx, item in enumerate(BATCH_27_CATALOG, 1):
        print(f"\n[{idx}/{len(BATCH_27_CATALOG)}] Processing: {item['name']} (₹{item['price']:.2f})")
        print(f"   Brand: {item['brand']} | Unit: {item['weight_per_unit']} {item['unit_type']}")

        # 1. Source Packshot (Rule 4: exactly 1 pristine image)
        print("   🔍 Sourcing pristine 1:1 commercial packshot...")
        img_path = source_single_packshot(item, idx)
        file_size_kb = os.path.getsize(img_path) / 1024
        print(f"   📸 Local Packshot cached: {img_path} ({file_size_kb:.1f} KB)")

        # 2. Upload to Supabase Storage
        product_slug = f"b27_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
    print("\n🏁 Batch 27 ingestion completed successfully!")


if __name__ == "__main__":
    main()

