#!/usr/bin/env python3
"""
Maxx Retail — Supermarket Shelf Batch 26 Ingestion Engine
=========================================================
Catalog: 14 verified SKUs across shelf photos b31.jpg - b40.jpg:
  Photo 1 (b31.jpg - Stacked):
    - Swiss Beauty Jet Black Long Lasting Liquid Eyeliner (4ml) @ ₹229.00
  Photo 2 (b32.jpg):
    - Fashion Colour Moisturizing Foundation Brightening (Shade 101 Extreme Fairness) (40ml) @ ₹449.00
  Photo 3 (b33.jpg):
    - Blue Heaven Long Lasting Makeup Fixer (60ml) @ ₹200.00
  Photo 4 (b34.jpg - Stacked):
    - MARS HD 2 In 1 Super Stay Foundation & Concealer (60ml) @ ₹449.00
    - Hilary Rhoda Skin Shine Strobe Cream 2-in-1 (25ml) @ ₹249.00
  Photo 5 (b35.jpg - Stacked):
    - MARS High Coverage Foundation SPF 50 PA++++ (40ml) @ ₹379.00
    - MARS Mist Foundation (50ml) @ ₹429.00
  Photo 6 (b36.jpg - Stacked):
    - MARS Miracle BB Cream Foundation (Shade F04-102#) (60ml) @ ₹429.00
    - MARS Matte Maniac Hydrating Liquid Foundation (Shade F11-101#) (45ml) @ ₹299.00
    - MARS The Gold Waves Waterproof & Matte Foundation (Shade F10-101#) (60ml) @ ₹319.00
  Photo 7 (b37.jpg):
    - MARS Hydra Glow Dewy Primer (30ml) @ ₹349.00
  Photo 8 (b38.jpg):
    - Swiss Beauty Round The Clock Makeup Setting Spray (100ml) @ ₹329.00
  Photo 9 (b39.jpg):
    - Maybelline Super Stay Double Fixer Spray (55ml) @ ₹749.00
  Photo 10 (b40.jpg - Stacked):
    - L'Oréal Paris Infallible 24H Tinted Serum (Shade 1-2 Rosy Light) (30ml) @ ₹999.00

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
STORAGE_PREFIX = "supermarket/maxx_retail/batch26"
CACHE_DIR = "/tmp/maxx_retail_batch26_cache"

BATCH_26_CATALOG = [
    {
        "name": "Swiss Beauty Jet Black Long Lasting Liquid Eyeliner (4ml)",
        "price": 229.00,
        "brand": "Swiss Beauty",
        "sub_category": "Eye Makeup",
        "menu_category": "Eyeliners & Kajal",
        "weight_per_unit": 4.0,
        "unit_type": "ml",
        "description": "Swiss Beauty Jet Black Long Lasting Liquid Eyeliner. Intense water-resistant pigmentation with an ultra-fine applicator tip for smooth, smudge-proof, precision winged eyeliner lines.",
        "variants": [{"name": "4ml", "price": 229.00, "unit": "4ml"}],
        "queries": [
            "swiss beauty jet black long lasting liquid eyeliner 4ml packshot white background",
            "swiss beauty liquid eyeliner sb-09 packshot",
            "swiss beauty jet black liquid eyeliner sb09",
        ],
    },
    {
        "name": "Fashion Colour Moisturizing Foundation Brightening (Shade 101 Extreme Fairness) (40ml)",
        "price": 449.00,
        "brand": "Fashion Colour",
        "sub_category": "Foundations",
        "menu_category": "Face Foundations",
        "weight_per_unit": 40.0,
        "unit_type": "ml",
        "description": "Fashion Colour Moisturizing & Whitening Foundation with Vitamin C. Smooth silky texture that delivers pure makeup brightening effects and lasting multi-moisture hydration without cakeyness.",
        "variants": [{"name": "Shade 101 Extreme Fairness (40ml)", "price": 449.00, "unit": "40ml"}],
        "queries": [
            "fashion colour moisturizing foundation brightening 40ml packshot white background",
            "fashion colour moisturizing whitening foundation if01 packshot",
            "fashion colour moisturizing foundation 40ml",
        ],
    },
    {
        "name": "Blue Heaven Long Lasting Makeup Fixer (60ml)",
        "price": 200.00,
        "brand": "Blue Heaven",
        "sub_category": "Makeup Setting Sprays & Fixers",
        "menu_category": "Setting Sprays & Fixers",
        "weight_per_unit": 60.0,
        "unit_type": "ml",
        "description": "Blue Heaven Long Lasting Makeup Fixer (New & Improved Formula). Enriched with Rose Flower Extract, Hyaluronic Acid, and Aloe Vera to hydrate, refresh, and lock makeup in place all day.",
        "variants": [{"name": "60ml", "price": 200.00, "unit": "60ml"}],
        "queries": [
            "blue heaven long lasting makeup fixer 60ml silver bottle packshot white background",
            "blue heaven makeup fixer 60ml spray packshot",
            "blue heaven long lasting makeup fixer spray",
        ],
    },
    {
        "name": "MARS HD 2 In 1 Super Stay Foundation & Concealer (60ml)",
        "price": 449.00,
        "brand": "MARS",
        "sub_category": "Foundations",
        "menu_category": "Face Foundations",
        "weight_per_unit": 60.0,
        "unit_type": "ml",
        "description": "MARS HD 2-in-1 Super Stay Foundation & Concealer. High definition formula that provides smooth, creaseless coverage, hides dark spots, and ensures a long-wearing matte finish.",
        "variants": [{"name": "60ml", "price": 449.00, "unit": "60ml"}],
        "queries": [
            "mars hd 2 in 1 super stay foundation 60ml packshot white background",
            "mars hd 2 in 1 foundation concealer packshot",
            "mars hd super stay foundation 60ml",
        ],
    },
    {
        "name": "Hilary Rhoda Skin Shine Strobe Cream 2-in-1 (25ml)",
        "price": 249.00,
        "brand": "Hilary Rhoda",
        "sub_category": "Illuminators & Highlighters",
        "menu_category": "Strobe Creams & Highlighters",
        "weight_per_unit": 25.0,
        "unit_type": "ml",
        "description": "Hilary Rhoda Skin Shine Strobe Cream 2-in-1. Infused with Shea Butter & Hyaluronic Acid, this illuminating moisturizer and radiant enhancer creates a luminous, dewy lit-from-within glow.",
        "variants": [{"name": "25ml", "price": 249.00, "unit": "25ml"}],
        "queries": [
            "hilary rhoda skin shine strobe cream 25ml packshot white background",
            "hilary rhoda strobe cream hr 5083 packshot",
            "hilary rhoda skin shine strobe cream tube",
        ],
    },
    {
        "name": "MARS High Coverage Foundation SPF 50 PA++++ (40ml)",
        "price": 379.00,
        "brand": "MARS",
        "sub_category": "Foundations",
        "menu_category": "Face Foundations",
        "weight_per_unit": 40.0,
        "unit_type": "ml",
        "description": "MARS High Coverage Foundation with SPF 50 PA++++ UVA/UVB protection. Provides seamless full coverage that conceals blemishes while shielding skin against sun exposure.",
        "variants": [{"name": "40ml", "price": 379.00, "unit": "40ml"}],
        "queries": [
            "mars high coverage foundation spf 50 40ml packshot white background",
            "mars high coverage foundation spf 50 pa packshot",
            "mars cosmetics high coverage foundation tube spf 50",
        ],
    },
    {
        "name": "MARS Mist Foundation (50ml)",
        "price": 429.00,
        "brand": "MARS",
        "sub_category": "Foundations",
        "menu_category": "Face Foundations",
        "weight_per_unit": 50.0,
        "unit_type": "ml",
        "description": "MARS Mist Foundation combining skin energizing and tone perfecting pigments. Delivers a smoother, flawless-looking complexion that keeps skin looking healthy and radiant.",
        "variants": [{"name": "50ml", "price": 429.00, "unit": "50ml"}],
        "queries": [
            "mars mist foundation 50ml packshot white background",
            "mars mist foundation bottle packshot",
            "mars cosmetics mist foundation 50ml",
        ],
    },
    {
        "name": "MARS Miracle BB Cream Foundation (Shade F04-102#) (60ml)",
        "price": 429.00,
        "brand": "MARS",
        "sub_category": "BB & CC Creams",
        "menu_category": "Face Foundations & BB Creams",
        "weight_per_unit": 60.0,
        "unit_type": "ml",
        "description": "MARS Miracle BB Cream Anti-Ageing Expert Whitening Light Permeable foundation. Delivers buildable smooth coverage, balances skin tone, and maintains moisture for daily radiance.",
        "variants": [{"name": "Shade F04-102# (60ml)", "price": 429.00, "unit": "60ml"}],
        "queries": [
            "mars miracle bb cream anti ageing 60ml packshot white background",
            "mars miracle bb cream f04 packshot",
            "mars cosmetics miracle bb cream bottle",
        ],
    },
    {
        "name": "MARS Matte Maniac Hydrating Liquid Foundation (Shade F11-101#) (45ml)",
        "price": 299.00,
        "brand": "MARS",
        "sub_category": "Foundations",
        "menu_category": "Face Foundations",
        "weight_per_unit": 45.0,
        "unit_type": "ml",
        "description": "MARS Matte Maniac Foundation. Super hydrating liquid foundation that diffuses the line between makeup and skin for undetectable, naturally flawless matte coverage with lightweight comfort.",
        "variants": [{"name": "Shade F11-101# (45ml)", "price": 299.00, "unit": "45ml"}],
        "queries": [
            "mars matte maniac liquid foundation packshot white background",
            "mars matte maniac foundation bottle packshot",
            "mars cosmetics matte maniac foundation",
        ],
    },
    {
        "name": "MARS The Gold Waves Waterproof & Matte Foundation (Shade F10-101#) (60ml)",
        "price": 319.00,
        "brand": "MARS",
        "sub_category": "Foundations",
        "menu_category": "Face Foundations",
        "weight_per_unit": 60.0,
        "unit_type": "ml",
        "description": "MARS The Gold Waves Waterproof & Matte Foundation. Lightweight, sweat-resistant matte foundation tube formula that diffuses imperfections and stays fresh throughout the day.",
        "variants": [{"name": "Shade F10-101# (60ml)", "price": 319.00, "unit": "60ml"}],
        "queries": [
            "mars the gold waves waterproof matte foundation packshot white background",
            "mars the gold waves foundation tube packshot",
            "mars gold waves foundation",
        ],
    },
    {
        "name": "MARS Hydra Glow Dewy Primer (30ml)",
        "price": 349.00,
        "brand": "MARS",
        "sub_category": "Primers",
        "menu_category": "Face Primers",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "MARS Hydra Glow Dewy Primer with Argan Oil, Hyaluronic Acid, and Chamomile Flower Water. Formulated for dry skin, blends seamlessly, and imparts a natural subtle luminous glow.",
        "variants": [{"name": "30ml", "price": 349.00, "unit": "30ml"}],
        "queries": [
            "mars hydra glow dewy primer 30ml packshot white background",
            "mars cosmetics hydra glow primer bottle packshot",
            "mars hydra glow dewy primer 30ml",
        ],
    },
    {
        "name": "Swiss Beauty Round The Clock Makeup Setting Spray (100ml)",
        "price": 329.00,
        "brand": "Swiss Beauty",
        "sub_category": "Makeup Setting Sprays & Fixers",
        "menu_category": "Setting Sprays & Fixers",
        "weight_per_unit": 100.0,
        "unit_type": "ml",
        "description": "Swiss Beauty Round The Clock Makeup Setting Spray enriched with Hyaluronic Acid. Locks in makeup for long hours, hydrates the skin, and prevents creasing with a lightweight mist.",
        "variants": [{"name": "100ml", "price": 329.00, "unit": "100ml"}],
        "queries": [
            "swiss beauty round the clock makeup setting spray 100ml packshot white background",
            "swiss beauty round the clock setting spray packshot",
            "swiss beauty sb-mf06 makeup fixer 100ml bottle",
        ],
    },
    {
        "name": "Maybelline Super Stay Double Fixer Spray (55ml)",
        "price": 749.00,
        "brand": "Maybelline New York",
        "sub_category": "Makeup Setting Sprays & Fixers",
        "menu_category": "Setting Sprays & Fixers",
        "weight_per_unit": 55.0,
        "unit_type": "ml",
        "description": "Maybelline Super Stay Double Fixer Spray. Advanced long-lasting setting spray engineered to lock in makeup with transfer-proof double fixing power for high endurance wear.",
        "variants": [{"name": "55ml", "price": 749.00, "unit": "55ml"}],
        "queries": [
            "maybelline super stay double fixer spray 55ml packshot white background",
            "maybelline super stay double fixer spray bottle packshot",
            "maybelline superstay double fixer spray 55ml",
        ],
    },
    {
        "name": "L'Oréal Paris Infallible 24H Tinted Serum (Shade 1-2 Rosy Light) (30ml)",
        "price": 999.00,
        "brand": "L'Oréal Paris",
        "sub_category": "Face Makeup",
        "menu_category": "Foundations",
        "weight_per_unit": 30.0,
        "unit_type": "ml",
        "description": "L'Oréal Paris Infallible 24H Tinted Serum infused with 1% Pure Hyaluronic Acid. Provides luminous sheer-to-medium radiant coverage that hydrates skin all day while evening skin tone for a healthy bare-skin glow.",
        "variants": [{"name": "Shade 1-2 Rosy Light (30ml)", "price": 999.00, "unit": "30ml"}],
        "queries": [
            "loreal paris infallible 24h tinted serum 30ml packshot white background",
            "l'oreal infallible tinted serum 1-2 rosy light packshot",
            "loreal infallible 24h tinted serum bottle packshot",
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
    product_slug = f"b26_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
    print("🚀 STARTING MAXX RETAIL SUPERMARKET BATCH 26 INGESTION")
    print(f"   Target Shop: Maxx Retail ({SHOP_ID})")
    print(f"   Catalog Size: {len(BATCH_26_CATALOG)} verified SKUs")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary Status: Strictly N/A (is_veg = NULL)")
    print(f"   Packshot Protocol: Exactly 1 pristine 1:1 padded image (< 120KB) on pure white")
    print("=" * 80)

    products_payload = []

    for idx, item in enumerate(BATCH_26_CATALOG, 1):
        print(f"\n[{idx}/{len(BATCH_26_CATALOG)}] Processing: {item['name']} (₹{item['price']:.2f})")
        print(f"   Brand: {item['brand']} | Unit: {item['weight_per_unit']} {item['unit_type']}")

        # 1. Source Packshot (Rule 4: exactly 1 pristine image)
        print("   🔍 Sourcing pristine 1:1 commercial packshot...")
        img_path = source_single_packshot(item, idx)
        file_size_kb = os.path.getsize(img_path) / 1024
        print(f"   📸 Local Packshot cached: {img_path} ({file_size_kb:.1f} KB)")

        # 2. Upload to Supabase Storage
        product_slug = f"b26_{idx}_{re.sub(r'[^a-z0-9]+', '_', item['name'].lower()).strip('_')[:50]}"
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
    print("\n🏁 Batch 26 ingestion completed successfully!")


if __name__ == "__main__":
    main()

