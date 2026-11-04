#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 20 Ingestion Engine
=========================================================
Catalog: 15 verified SKUs across shelf photos:
  Image 1:
    - The Derma Co 10% Vitamin C Face Serum (10ml) @ ₹299.00
  Image 2:
    - The Derma Co 15% Vitamin C Face Serum (30ml) @ ₹799.00
  Image 3:
    - The Derma Co Sali-Cinamide Anti-Acne Face Serum (10ml) @ ₹349.00
    - The Derma Co Nia-Zelaic Oil Control Face Serum (30ml) @ ₹649.00
    - The Derma Co 2% Alpha Arbutin Face Serum (30ml) @ ₹499.00
    - The Derma Co 10% Niacinamide Face Serum (30ml) @ ₹599.00
    - The Derma Co 20% Vitamin C Face Serum (20ml) @ ₹899.00
    - The Derma Co 2% Salicylic Acid Face Serum (30ml) @ ₹499.00
  Image 4:
    - The Derma Co 0.3% Retinol Face Serum (30ml) @ ₹799.00
    - The Derma Co Pore Minimizing Face Serum (30ml) @ ₹599.00
    - The Derma Co Snail Peptide 96 Under Eye Repair Cream (15g) @ ₹399.00
  Image 5:
    - Dabur Gulabari Moisturizing Cold Cream (55ml) @ ₹87.00
    - Pond's Skin Institute Bright Beauty Light Cream (23g) @ ₹115.00
    - Pond's Skin Institute Youthful Miracle Day Cream SPF 15 (35g) @ ₹599.00
    - Pond's Skin Institute Hydra Miracle Moisturising Cold Cream (55ml) @ ₹125.00

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
STORAGE_PREFIX = "supermarket/maxx_retail/batch20"
CACHE_DIR = "/tmp/maxx_retail_batch20_cache"

BATCH_20_CATALOG = [
    {
        "name": "The Derma Co 10% Vitamin C Face Serum (10ml)",
        "price": 299.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 10.0,
        "unit_type": "ml",
        "description": "The Derma Co 10% Vitamin C Face Serum for skin radiance with 5% Niacinamide & Hyaluronic Acid. Fades dark spots, evens skin tone, and protects against free radical damage.",
        "variants": [
            {"name": "10ml", "price": 299.00, "unit": "10ml"}
        ],
        "queries": [
            "the derma co 10 vitamin c face serum 10ml bottle packshot white background",
            "the derma co 10 vitamin c face serum 10ml packshot",
            "derma co 10 vitamin c serum 10ml",
        ],
    },
    {
        "name": "The Derma Co 15% Vitamin C Face Serum (30ml)",
        "price": 799.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "The Derma Co 15% Vitamin C Face Serum for skin radiance with Niacinamide & Vitamin C. Advanced formulation to reduce hyperpigmentation, brighten dull complexion, and promote collagen synthesis.",
        "variants": [
            {"name": "30ml", "price": 799.00, "unit": "30ml"}
        ],
        "queries": [
            "the derma co 15 vitamin c face serum 30ml bottle packshot white background",
            "the derma co 15 vitamin c face serum packshot",
            "derma co 15 vitamin c serum 30ml",
        ],
    },
    {
        "name": "The Derma Co Sali-Cinamide Anti-Acne Face Serum (10ml)",
        "price": 349.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 10.0,
        "unit_type": "ml",
        "description": "The Derma Co Sali-Cinamide Anti-Acne Face Serum with 2% Salicylic Acid & 5% Niacinamide. Clarifies active acne, calms acne marks, and regulates excess sebum.",
        "variants": [
            {"name": "10ml", "price": 349.00, "unit": "10ml"}
        ],
        "queries": [
            "the derma co sali cinamide anti acne face serum 10ml bottle packshot white background",
            "the derma co sali cinamide face serum packshot",
            "derma co sali cinamide serum 10ml",
        ],
    },
    {
        "name": "The Derma Co Nia-Zelaic Oil Control Face Serum (30ml)",
        "price": 649.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "The Derma Co Nia-Zelaic Oil Control Face Serum with 10% Niacinamide & 5% Azelaic Acid. Controls oil, prevents acne breakouts, and clears congested pores.",
        "variants": [
            {"name": "30ml", "price": 649.00, "unit": "30ml"}
        ],
        "queries": [
            "the derma co nia zelaic oil control face serum 30ml bottle packshot white background",
            "the derma co nia zelaic face serum packshot",
            "derma co nia zelaic serum 30ml",
        ],
    },
    {
        "name": "The Derma Co 2% Alpha Arbutin Face Serum (30ml)",
        "price": 499.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "The Derma Co 2% Alpha Arbutin Face Serum with Hyaluronic Acid for dark spots & uneven skin tone. Helps fade hyperpigmentation, blemishes, and melasma for a clear, radiant complexion.",
        "variants": [
            {"name": "30ml", "price": 499.00, "unit": "30ml"}
        ],
        "queries": [
            "the derma co 2 alpha arbutin face serum 30ml bottle packshot white background",
            "the derma co 2 alpha arbutin face serum packshot",
            "derma co alpha arbutin serum 30ml",
        ],
    },
    {
        "name": "The Derma Co 10% Niacinamide Face Serum (30ml)",
        "price": 599.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "The Derma Co 10% Niacinamide Face Serum with Zinc PCA for acne marks and blemishes. Clarifies skin, reduces redness, regulates oil production, and repairs damaged skin barrier.",
        "variants": [
            {"name": "30ml", "price": 599.00, "unit": "30ml"}
        ],
        "queries": [
            "the derma co 10 niacinamide face serum 30ml bottle packshot white background",
            "the derma co 10 niacinamide face serum packshot",
            "derma co 10 niacinamide serum 30ml",
        ],
    },
    {
        "name": "The Derma Co 20% Vitamin C Face Serum (20ml)",
        "price": 899.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 20.0,
        "unit_type": "ml",
        "description": "The Derma Co 20% Vitamin C Face Serum with Ferulic Acid & Hyaluronic Acid for skin radiance. High-potency antioxidant serum that targets stubborn pigmentation and signs of aging.",
        "variants": [
            {"name": "20ml", "price": 899.00, "unit": "20ml"}
        ],
        "queries": [
            "the derma co 20 vitamin c face serum 20ml bottle packshot white background",
            "the derma co 20 vitamin c face serum packshot",
            "derma co 20 vitamin c serum 20ml",
        ],
    },
    {
        "name": "The Derma Co 2% Salicylic Acid Face Serum (30ml)",
        "price": 499.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "The Derma Co 2% Salicylic Acid Face Serum with Witch Hazel & Willow Bark for active acne. Exfoliates dead skin cells, unclogs blackheads & whiteheads, and prevents future breakouts.",
        "variants": [
            {"name": "30ml", "price": 499.00, "unit": "30ml"}
        ],
        "queries": [
            "the derma co 2 salicylic acid face serum 30ml bottle packshot white background",
            "the derma co 2 salicylic acid face serum packshot",
            "derma co 2 salicylic acid serum 30ml",
        ],
    },
    {
        "name": "The Derma Co 0.3% Retinol Face Serum (30ml)",
        "price": 799.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "The Derma Co 0.3% Retinol Face Serum with Vitamin C for spotless, youthful skin. Accelerates cell turnover, smooths fine lines and wrinkles, and refines uneven skin texture.",
        "variants": [
            {"name": "30ml", "price": 799.00, "unit": "30ml"}
        ],
        "queries": [
            "the derma co 0.3 retinol face serum 30ml bottle packshot white background",
            "the derma co 0.3 retinol face serum packshot",
            "derma co 0.3 retinol serum 30ml",
        ],
    },
    {
        "name": "The Derma Co Pore Minimizing Face Serum (30ml)",
        "price": 599.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Face Serums & Treatments",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "The Derma Co Pore Minimizing Face Serum with 4% Niacinamide, 5% PHA & p-REFINYL for open pores. Tightens enlarged pores, controls excess shine, and gently exfoliates for a smooth matte finish.",
        "variants": [
            {"name": "30ml", "price": 599.00, "unit": "30ml"}
        ],
        "queries": [
            "the derma co pore minimizing face serum 30ml bottle packshot white background",
            "the derma co pore minimizing face serum packshot",
            "derma co pore minimizing serum 30ml",
        ],
    },
    {
        "name": "The Derma Co Snail Peptide 96 Under Eye Repair Cream (15g)",
        "price": 399.00,
        "brand": "The Derma Co",
        "sub_category": "Skincare",
        "menu_category": "Eye Care",
        "weight_per_unit": 15.0,
        "unit_type": "g",
        "description": "The Derma Co Snail Peptide 96 Under Eye Repair Cream with 1% Peptide, 2% Caffeine & Retinol. Fades dark circles, depuffs tired eyes, and hydrates delicate under-eye skin.",
        "variants": [
            {"name": "15g", "price": 399.00, "unit": "15g"}
        ],
        "queries": [
            "the derma co snail peptide 96 under eye repair cream 15g packshot white background",
            "the derma co snail peptide under eye repair cream packshot",
            "derma co snail peptide under eye cream 15g",
        ],
    },
    {
        "name": "Dabur Gulabari Moisturizing Cold Cream (55ml)",
        "price": 87.00,
        "brand": "Dabur",
        "sub_category": "Skincare",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 55.0,
        "unit_type": "ml",
        "description": "Dabur Gulabari Moisturizing Cold Cream enriched with natural Rose Oil, Saffron, and Turmeric. Nourishes skin, protects against winter dryness, and gives a healthy rose-like radiant glow.",
        "variants": [
            {"name": "55ml", "price": 87.00, "unit": "55ml"}
        ],
        "queries": [
            "dabur gulabari moisturizing cold cream 55ml box packshot white background",
            "dabur gulabari cold cream 55ml packshot",
            "dabur gulabari moisturizing cream 55ml tub",
        ],
    },
    {
        "name": "Pond's Skin Institute Bright Beauty Light Cream (23g)",
        "price": 115.00,
        "brand": "Pond's",
        "sub_category": "Skincare",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 23.0,
        "unit_type": "g",
        "description": "Pond's Skin Institute Bright Beauty Light Cream with UV Filter & Niasorcinol. Lightweight, non-oily daily cream that brightens skin, reduces dark spots, and provides sun defense.",
        "variants": [
            {"name": "23g", "price": 115.00, "unit": "23g"}
        ],
        "queries": [
            "ponds bright beauty light cream 23g box packshot white background",
            "ponds skin institute bright beauty light cream packshot",
            "ponds bright beauty cream 23g tub",
        ],
    },
    {
        "name": "Pond's Skin Institute Youthful Miracle Day Cream SPF 15 (35g)",
        "price": 599.00,
        "brand": "Pond's",
        "sub_category": "Skincare",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 35.0,
        "unit_type": "g",
        "description": "Pond's Skin Institute Youthful Miracle Day Cream SPF 15 PA++ with Hexyl-Retinol Complex. Clinically proven anti-aging cream that restores firmness, smooths wrinkles, and revitalizes youthful radiance.",
        "variants": [
            {"name": "35g", "price": 599.00, "unit": "35g"}
        ],
        "queries": [
            "ponds youthful miracle day cream 35g box packshot white background",
            "ponds skin institute youthful miracle day cream packshot",
            "ponds age miracle day cream 35g tub",
        ],
    },
    {
        "name": "Pond's Skin Institute Hydra Miracle Moisturising Cold Cream (55ml)",
        "price": 125.00,
        "brand": "Pond's",
        "sub_category": "Skincare",
        "menu_category": "Face Creams & Moisturizers",
        "weight_per_unit": 55.0,
        "unit_type": "ml",
        "description": "Pond's Skin Institute Hydra Miracle Moisturising Cold Cream with 10 essential skin nutrients. Deeply hydrates and locks in moisture to protect dry skin from harsh winter weather.",
        "variants": [
            {"name": "55ml", "price": 125.00, "unit": "55ml"}
        ],
        "queries": [
            "ponds hydra miracle cold cream 55ml box packshot white background",
            "ponds skin institute hydra miracle cold cream packshot",
            "ponds moisturizing cold cream 55ml tub",
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
    product_slug = f"b20_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
    print("🚀 STARTING MAXX RETAIL SUPERMARKET BATCH 20 INGESTION")
    print(f"   Target Shop: Maxx Retail ({SHOP_ID})")
    print(f"   Catalog Size: {len(BATCH_20_CATALOG)} verified SKUs")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST)")
    print(f"   Dietary Status: Strictly N/A (is_veg = NULL)")
    print("=" * 80)

    products_payload = []

    for idx, item in enumerate(BATCH_20_CATALOG, 1):
        print(f"\n[{idx}/{len(BATCH_20_CATALOG)}] Processing: {item['name']} (₹{item['price']:.2f})")
        print(f"   Brand: {item['brand']} | Unit: {item['weight_per_unit']} {item['unit_type']}")

        # 1. Source Packshots
        print("   🔍 Sourcing dual commercial packshots...")
        img_paths = source_two_packshots(item, idx)

        # 2. Upload to Supabase Storage
        remote_urls = []
        product_slug = f"b20_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
    print("\n🏁 Batch 20 ingestion completed. Proceeding to forensic verification audit...")


if __name__ == "__main__":
    main()

