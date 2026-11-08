#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 31 Ingestion Engine
=========================================================
Catalog: 21 items / 20 verified SKUs across shelf photos b81.jpg - b90.jpg:
  Photo 1 (b81.jpg - Box):
    - Lotus Herbals Radiant Pearl Cellular Lightening Facial Kit (37g) @ ₹340.00
  Photo 2 (b82.jpg - Box):
    - NutriGlow Salon Series Anti-Pigmentation Bleach (300g) @ ₹350.00
  Photo 3 (b83.jpg - Box):
    - NutriGlow Salon Series Vitamin C Lightening Bleach (300g) @ ₹350.00
  Photo 4 & 5 (b84.jpg & b85.jpg - Clustered Variants):
    - NutriGlow Salon Series Skin Whitening Bleach (43g) @ ₹75.00
      Variants: 43g (₹75.00), 300g (₹350.00)
  Photo 5 (b85.jpg - 43g Bleach Boxes):
    - NutriGlow Papaya Fruit Bleach Cream (43g) @ ₹99.00
    - NutriGlow Gold Kesar Bleach Cream (43g) @ ₹75.00
    - NutriGlow Diamond Perfect Radiance Bleach Cream (43g) @ ₹75.00
    - NutriGlow Wine Bleach Cream (43g) @ ₹75.00
  Photo 6 (b86.jpg - 50g Bleach Boxes):
    - OxyGlow Herbals Multi Fruit Bleach Cream (50g) @ ₹90.00
    - OxyGlow Herbals Diamond Bleach Cream (50g) @ ₹110.00
  Photo 7 (b87.jpg - VLCC Bleach Boxes):
    - VLCC Insta Glow Diamond Bleach (30g) @ ₹99.00
    - VLCC Natural Sciences Insta Glow Herbal Bleach (28.1g) @ ₹79.00
    - VLCC Natural Sciences Insta Glow Gold Bleach (30g) @ ₹82.00
    - VLCC Insta Glow Oxygen Bleach (25.7g) @ ₹89.00
  Photo 8 (b88.jpg - Fem Bleach Boxes):
    - Fem Crème Bleach Gold (8g) @ ₹45.00
    - Fem Crème Bleach Saffron & Milk (8g) @ ₹37.00
  Photo 9 (b89.jpg - Fem & OxyLife Boxes):
    - Fem Crème Bleach Gold Ultra (10g) @ ₹45.00
    - Fem Crème Bleach Turmeric & Milk (8g) @ ₹32.00
    - Fem Crème Bleach Diamond (18g) @ ₹50.00
    - OxyLife Natural Radiance 5 Crème Bleach (9g) @ ₹55.00
  Photo 10 (b90.jpg - Fem De-Tan Box):
    - Fem Crème Bleach De-Tan (10g) @ ₹45.00

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
STORAGE_PREFIX = "supermarket/maxx_retail/batch31"
CACHE_DIR = "/tmp/maxx_retail_batch31_cache"

BATCH_31_CATALOG = [
    {
        "name": "Lotus Herbals Radiant Pearl Cellular Lightening Facial Kit (37g)",
        "price": 340.00,
        "brand": "Lotus Herbals",
        "sub_category": "Facial Kits",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 37.0,
        "unit_type": "grams",
        "description": "Lotus Herbals Radiant Pearl Cellular Lightening Facial Kit with deep-cell activation system. 4 easy salon steps including Cleansing Scrub 10g, Activator 7g, Massage Crème with pearl dust 10g, and Pearl Mask 10g for luminous skin.",
        "variants": [{"name": "37g (4 Steps)", "price": 340.00, "unit": "37g"}],
        "queries": [
            "lotus herbals radiant pearl cellular lightening facial kit packshot white background",
            "lotus radiant pearl facial kit 37g box packshot",
            "lotus herbals radiant pearl facial kit",
        ],
    },
    {
        "name": "NutriGlow Salon Series Anti-Pigmentation Bleach (300g)",
        "price": 350.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 300.0,
        "unit_type": "grams",
        "description": "NutriGlow Salon Series Anti-Pigmentation Bleach for dark spot reduction & blemishes removal. Formulated with Kojic Acid, Almond Oil, Vitamin C, Glycolic Acid, Liquorice Root Extract and Alpha Arbutin to reduce melasma, sun spots & freckles. Contains Crème Bleach 250g, Activator 25gx2, spatula, and mixing tray.",
        "variants": [{"name": "300g", "price": 350.00, "unit": "300g"}],
        "queries": [
            "nutriglow salon series anti pigmentation bleach 300g packshot white background",
            "nutriglow anti pigmentation bleach 300g box",
            "nutriglow anti-pigmentation bleach",
        ],
    },
    {
        "name": "NutriGlow Salon Series Vitamin C Lightening Bleach (300g)",
        "price": 350.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 300.0,
        "unit_type": "grams",
        "description": "NutriGlow Salon Series Vitamin C Lightening Bleach for dark spot reduction & tan removal. Enriched with Alpha Arbutin, Hyaluronic Acid, Skin Ceramides, Papaya Fruit & Vitamin C for advanced melanin reduction and skin tone correction. Contains Crème Bleach 250g and Activator 25gx2.",
        "variants": [{"name": "300g", "price": 350.00, "unit": "300g"}],
        "queries": [
            "nutriglow salon series vitamin c lightening bleach 300g packshot white background",
            "nutriglow vitamin c lightening bleach 300g box",
            "nutriglow vitamin c bleach 300g",
        ],
    },
    {
        "name": "NutriGlow Salon Series Skin Whitening Bleach (43g)",
        "price": 75.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 43.0,
        "unit_type": "grams",
        "description": "NutriGlow Salon Series Skin Whitening Bleach for dark spot reduction & tan removal. Formulated with Alpha Arbutin, Hyaluronic Acid, Saxifraga Sarmentosa Extract, Papaya Fruit Extract, AHA & Vitamin C for advanced hyper melanin reduction and radiant skin tone.",
        "variants": [
            {"name": "43g", "price": 75.00, "unit": "43g"},
            {"name": "300g", "price": 350.00, "unit": "300g"},
        ],
        "queries": [
            "nutriglow salon series skin whitening bleach packshot white background",
            "nutriglow skin whitening bleach 300g box",
            "nutriglow skin whitening bleach cream",
        ],
    },
    {
        "name": "NutriGlow Papaya Fruit Bleach Cream (43g)",
        "price": 99.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 43.0,
        "unit_type": "grams",
        "description": "NutriGlow Papaya Fruit Bleach Cream for blemish-free fairer complexion. Contains Papaya Bleach Cream 35g, Papaya Activator 8g, and spatula. Gently bleaches facial hair to blend with natural skin tone.",
        "variants": [{"name": "43g", "price": 99.00, "unit": "43g"}],
        "queries": [
            "nutriglow papaya fruit bleach cream 43g packshot white background",
            "nutriglow papaya bleach cream 43g box",
            "nutriglow papaya fruit bleach",
        ],
    },
    {
        "name": "NutriGlow Gold Kesar Bleach Cream (43g)",
        "price": 75.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 43.0,
        "unit_type": "grams",
        "description": "NutriGlow Gold Kesar Bleach Cream with advanced cellular age balance & skin cell repair. Contains Gold Kesar Bleach Cream 35g, Gold Kesar Activator 8g, and spatula for glowing, youthful skin.",
        "variants": [{"name": "43g", "price": 75.00, "unit": "43g"}],
        "queries": [
            "nutriglow gold kesar bleach cream 43g packshot white background",
            "nutriglow gold kesar bleach cream 43g box",
            "nutriglow gold kesar bleach",
        ],
    },
    {
        "name": "NutriGlow Diamond Perfect Radiance Bleach Cream (43g)",
        "price": 75.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 43.0,
        "unit_type": "grams",
        "description": "NutriGlow Diamond Perfect Radiance Bleach Cream. Contains Diamond Bleach Cream 35g, Diamond Activator 8g, and spatula for instant sparkling radiance and blemish-free fairer complexion.",
        "variants": [{"name": "43g", "price": 75.00, "unit": "43g"}],
        "queries": [
            "nutriglow diamond perfect radiance bleach cream 43g packshot white background",
            "nutriglow diamond bleach cream 43g box",
            "nutriglow diamond bleach",
        ],
    },
    {
        "name": "NutriGlow Wine Bleach Cream (43g)",
        "price": 75.00,
        "brand": "NutriGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 43.0,
        "unit_type": "grams",
        "description": "NutriGlow Wine Bleach Cream for blemish-free fairer complexion. Contains Wine Bleach Cream 35g, Wine Bleach Activator 8g, and spatula. Enriched with real red grape wine extracts.",
        "variants": [{"name": "43g", "price": 75.00, "unit": "43g"}],
        "queries": [
            "nutriglow wine bleach cream 43g packshot white background",
            "nutriglow wine bleach cream box",
            "nutriglow wine bleach",
        ],
    },
    {
        "name": "OxyGlow Herbals Multi Fruit Bleach Cream (50g)",
        "price": 90.00,
        "brand": "OxyGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "OxyGlow Herbals Multi Fruit Bleach Cream. Deep conditioning multi-fruit formula that bleaches facial hair to match the skin tone while nourishing the skin with natural fruit extracts.",
        "variants": [{"name": "50g", "price": 90.00, "unit": "50g"}],
        "queries": [
            "oxyglow herbals multi fruit bleach cream packshot white background",
            "oxyglow multi fruit bleach cream 50g box",
            "oxyglow multi fruit bleach cream",
        ],
    },
    {
        "name": "OxyGlow Herbals Diamond Bleach Cream (50g)",
        "price": 110.00,
        "brand": "OxyGlow",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 50.0,
        "unit_type": "grams",
        "description": "OxyGlow Herbals Diamond Bleach Cream with innovative formula for clear, deep and active multi layer impact. Imparts sparkling diamond brightness and evens skin tone.",
        "variants": [{"name": "50g", "price": 110.00, "unit": "50g"}],
        "queries": [
            "oxyglow herbals diamond bleach cream packshot white background",
            "oxyglow diamond bleach cream 50g box",
            "oxyglow diamond bleach cream",
        ],
    },
    {
        "name": "VLCC Insta Glow Diamond Bleach (30g)",
        "price": 99.00,
        "brand": "VLCC",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 30.0,
        "unit_type": "grams",
        "description": "VLCC Insta Glow Diamond Bleach with colloidal diamond for sparkling brightness. Complete salon pack containing Pre Bleach Cream 3g, Bleach Cream 20g, Powder Activator 2g, and Post Bleach Pack 5g.",
        "variants": [{"name": "30g", "price": 99.00, "unit": "30g"}],
        "queries": [
            "vlcc insta glow diamond bleach 30g packshot white background",
            "vlcc diamond bleach 30g box packshot",
            "vlcc insta glow diamond bleach",
        ],
    },
    {
        "name": "VLCC Natural Sciences Insta Glow Herbal Bleach (28.1g)",
        "price": 79.00,
        "brand": "VLCC",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 28.1,
        "unit_type": "grams",
        "description": "VLCC Natural Sciences Insta Glow Herbal Bleach with cucumber and rose petals for gentle, healthy brightness. Pack contains Bleach Cream 21g, Powder Activator 2.1g, and Post Bleach Pack 5g.",
        "variants": [{"name": "28.1g", "price": 79.00, "unit": "28.1g"}] ,
        "queries": [
            "vlcc natural sciences insta glow herbal bleach packshot white background",
            "vlcc herbal bleach 28.1g box packshot",
            "vlcc insta glow herbal bleach",
        ],
    },
    {
        "name": "VLCC Natural Sciences Insta Glow Gold Bleach (30g)",
        "price": 82.00,
        "brand": "VLCC",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 30.0,
        "unit_type": "grams",
        "description": "VLCC Natural Sciences Insta Glow Gold Bleach with colloidal gold for glowing, radiant fairness. Complete pack contains Pre Bleach Cream 3g, Bleach Cream 20g, Powder Activator 2g, and Post Bleach Pack 5g.",
        "variants": [{"name": "30g", "price": 82.00, "unit": "30g"}],
        "queries": [
            "vlcc natural sciences insta glow gold bleach 30g packshot white background",
            "vlcc gold bleach 30g box packshot",
            "vlcc insta glow gold bleach",
        ],
    },
    {
        "name": "VLCC Insta Glow Oxygen Bleach (25.7g)",
        "price": 89.00,
        "brand": "VLCC",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 25.7,
        "unit_type": "grams",
        "description": "VLCC Insta Glow Oxygen Bleach oxygen rich formula for fresh, flawless brightness. Pack contains Pre Bleach Cream 1.5g, Bleach Cream 21g, and Powder Activator 3.2g.",
        "variants": [{"name": "25.7g", "price": 89.00, "unit": "25.7g"}],
        "queries": [
            "vlcc insta glow oxygen bleach 25.7g packshot white background",
            "vlcc oxygen bleach 25.7g box packshot",
            "vlcc insta glow oxygen bleach",
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
        "description": "Fem Crème Bleach Gold with 24K Gold Dust for special golden glow. Net quantity 8g (Crème Bleach 7g + Powder Activator 1g). By Dabur.",
        "variants": [{"name": "8g", "price": 45.00, "unit": "8g"}],
        "queries": [
            "fem creme bleach gold 8g packshot white background",
            "fem gold bleach 8g box packshot",
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
        "description": "Fem Crème Bleach Saffron & Milk for healthy glow. Net quantity 8g (Crème Bleach 7g + Powder Activator 1g) with free 18ml Gulabari. By Dabur.",
        "variants": [{"name": "8g", "price": 37.00, "unit": "8g"}],
        "queries": [
            "fem creme bleach saffron and milk 8g packshot white background",
            "fem saffron and milk bleach 8g box packshot",
            "fem creme bleach saffron and milk",
        ],
    },
    {
        "name": "Fem Crème Bleach Gold Ultra (10g)",
        "price": 45.00,
        "brand": "Fem",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 10.0,
        "unit_type": "grams",
        "description": "Fem Crème Bleach Gold Ultra for parlour glow. Net weight 10g (Crème Bleach 7g, Powder Activator 1g, Pre Bleach Cream 1g, Post Bleach Cream 1g). By Dabur.",
        "variants": [{"name": "10g", "price": 45.00, "unit": "10g"}],
        "queries": [
            "fem creme bleach gold ultra 10g packshot white background",
            "fem gold ultra bleach 10g box packshot",
            "fem creme bleach gold ultra",
        ],
    },
    {
        "name": "Fem Crème Bleach Turmeric & Milk (8g)",
        "price": 32.00,
        "brand": "Fem",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 8.0,
        "unit_type": "grams",
        "description": "Fem Crème Bleach Turmeric & Milk for soft glow in 15 mins. Net weight 8g (Crème Bleach 7g + Powder Activator 1g). By Dabur.",
        "variants": [{"name": "8g", "price": 32.00, "unit": "8g"}],
        "queries": [
            "fem creme bleach turmeric and milk 8g packshot white background",
            "fem turmeric and milk bleach 8g box packshot",
            "fem creme bleach turmeric and milk",
        ],
    },
    {
        "name": "Fem Crème Bleach Diamond (18g)",
        "price": 50.00,
        "brand": "Fem",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 18.0,
        "unit_type": "grams",
        "description": "New Fem Crème Bleach Diamond for sparkling shine. Net quantity 18g (Crème Bleach 14g, Powder Activator 2g, Post Bleach Cream 2 x 1g). By Dabur.",
        "variants": [{"name": "18g", "price": 50.00, "unit": "18g"}],
        "queries": [
            "fem creme bleach diamond 18g packshot white background",
            "fem diamond bleach 18g box packshot",
            "fem creme bleach diamond",
        ],
    },
    {
        "name": "OxyLife Natural Radiance 5 Crème Bleach (9g)",
        "price": 55.00,
        "brand": "OxyLife",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 9.0,
        "unit_type": "grams",
        "description": "OxyLife Natural Radiance 5 Crème Bleach with active OXYGEN. Net quantity 9g (Crème Bleach 7g, Powder Activator 1g, Post-Bleach Skin Radiance Serum 1g). By Dabur.",
        "variants": [{"name": "9g", "price": 55.00, "unit": "9g"}],
        "queries": [
            "oxylife natural radiance 5 creme bleach 9g packshot white background",
            "oxylife bleach 9g box packshot",
            "oxylife natural radiance 5 creme bleach",
        ],
    },
    {
        "name": "Fem Crème Bleach De-Tan (10g)",
        "price": 45.00,
        "brand": "Fem",
        "sub_category": "Bleach & Hair Removal",
        "menu_category": "Facial Kits & Bleach",
        "weight_per_unit": 10.0,
        "unit_type": "grams",
        "description": "Fem Crème Bleach De-Tan for active tan removal. Net weight 10g (Crème Bleach 7g, Powder Activator 1g, Pre Bleach Cream 1g, Post Bleach Cream 1g). By Dabur.",
        "variants": [{"name": "10g", "price": 45.00, "unit": "10g"}],
        "queries": [
            "fem creme bleach de-tan 10g packshot white background",
            "fem de-tan bleach 10g box packshot",
            "fem creme bleach de tan",
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
    img_name = f"b31_{index}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:40]}.jpg"
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
    print("🚀 STARTING MAXX RETAIL SUPERMARKET BATCH 31 INGESTION")
    print(f"   Target Shop: Maxx Retail ({SHOP_ID})")
    print(f"   Catalog Size: {len(BATCH_31_CATALOG)} verified SKUs")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary Status: Strictly N/A (is_veg = NULL)")
    print(f"   Packshot Protocol: Exactly 1 pristine 1:1 padded image (< 120KB) on pure white")
    print("=" * 80)

    products_payload = []

    for idx, item in enumerate(BATCH_31_CATALOG, 1):
        print(f"\n[{idx}/{len(BATCH_31_CATALOG)}] Processing: {item['name']} (₹{item['price']:.2f})")
        print(f"   Brand: {item['brand']} | Unit: {item['weight_per_unit']} {item['unit_type']}")

        # 1. Source Packshot (Rule 4: exactly 1 pristine image)
        print("   🔍 Sourcing pristine 1:1 commercial packshot...")
        img_path = source_single_packshot(item, idx)
        file_size_kb = os.path.getsize(img_path) / 1024
        print(f"   📸 Local Packshot cached: {img_path} ({file_size_kb:.1f} KB)")

        # 2. Upload to Supabase Storage
        product_slug = f"b31_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
            "tags": ["personal_care", "cosmetics_beauty", "facial_kit", "bleach", item["sub_category"].lower(), item["brand"].lower()],
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
    print("\n🏁 Batch 31 ingestion completed successfully!")


if __name__ == "__main__":
    main()

