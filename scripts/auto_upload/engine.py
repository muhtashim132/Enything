#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════════════╗
║            ENYTHING — AUTO MEDICINE & PRODUCT UPLOAD ENGINE v2.0            ║
║                                                                              ║
║  100x Automated Product Ingestion System:                                    ║
║  1. Scans shelf / medicine box photos (Native Apple Vision Neural OCR or     ║
║     Gemini 2.0 Flash Vision free tier)                                       ║
║  2. Searches Indian pharmacy databases (PharmEasy, Tata 1mg, DDG Lite)       ║
║     for verified MRP, salts/composition, pack info, Rx requirement           ║
║  3. Formats exactly 2 distinct 1:1 (800x800) images with clean white canvas  ║
║     padding (or studio-grade formulation cards)                              ║
║  4. Uploads to Supabase products table enforcing soft-delete & schema rules  ║
║                                                                              ║
║  Cost: $0 — 100% Free APIs & Local Apple Silicon Acceleration                ║
╚══════════════════════════════════════════════════════════════════════════════╝

Usage:
    # 1. From a Shelf Photo (Native OCR on Mac or Gemini Vision):
    python3 engine.py --image shelf.jpg --shop-id UUID --mode pharmacy

    # 2. From Brand Names directly:
    python3 engine.py --products "Dolo 650, Azithral 500, Augmentin 625 Duo" --shop-id UUID

    # 3. Dry Run (Full simulation without DB write):
    python3 engine.py --image shelf.jpg --shop-id UUID --dry-run
"""

import argparse
import json
import os
import re
import sys
import time
import traceback
from pathlib import Path

# Add script directory to module path
SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

from vision import analyze_shelf_image, analyze_shelf_image_from_names
from scraper import research_pharmacy_product, research_grocery_product
from image_pipeline import download_and_prepare_images, upload_images_to_supabase
from uploader import (
    init_supabase,
    check_duplicate_product,
    insert_product,
    get_supabase_config,
    get_shop_info,
    get_shop_by_name,
)

DATA_DIR = SCRIPT_DIR / "data"
DATA_DIR.mkdir(exist_ok=True)


VALID_APP_CATEGORIES = {
    "Supermarket / Hypermarket", "Grocery", "Restaurant", "Fast Food", "Bakery",
    "Butcher", "Fish & Seafood", "Dairy & Eggs", "Fruits & Vegs", "Sweets & Mithai",
    "Beverages", "Pharmacy", "Medical Store", "Electronics", "Mobile & Repair",
    "Clothing", "Footwear", "Jewellery", "Hardware Store", "Stationery",
    "Toys & Games", "Sports", "Pet Supplies", "Cosmetics & Beauty", "Salon & Beauty",
    "Flowers", "Home Decor", "Furniture", "Auto Parts", "Paan Shop",
    "Tea & Coffee", "Ice Cream", "Organic", "Other"
}


def classify_department_category(product_name: str, given_category: str = None) -> str:
    """
    100x Omnibus Department Classification:
    Accurately classifies a product into its true AppCategories department
    so statutory GST slabs (0%, 5%, 18%) and item commissions calculate with precision.
    """
    if given_category and given_category in VALID_APP_CATEGORIES and given_category not in ("Supermarket / Hypermarket", "Other"):
        return given_category

    name_lower = (product_name or "").lower()

    # Dairy & Eggs (5% GST)
    if any(k in name_lower for k in ["milk", "butter", "cheese", "paneer", "curd", "dahi", "yogurt", "egg", "eggs", "amul butter", "amul milk"]):
        return "Dairy & Eggs"

    # Fresh Produce (0% GST - Exempt)
    if any(k in name_lower for k in ["apple", "banana", "orange", "mango", "potato", "onion", "tomato", "ginger", "garlic", "lemon", "vegetable", "fruit", "chilli", "palak", "spinach", "coriander"]):
        return "Fruits & Vegs"

    # Cosmetics & Personal Care (18% GST)
    if any(k in name_lower for k in ["shampoo", "conditioner", "face wash", "lotion", "cream", "moisturizer", "soap", "deodorant", "perfume", "lipstick", "serum", "sunscreen", "body wash", "toothpaste"]):
        return "Cosmetics & Beauty"

    # Beverages
    if any(k in name_lower for k in ["juice", "soda", "cold drink", "cola", "pepsi", "coke", "sprite", "fanta", "maaza", "red bull", "energy drink"]):
        return "Beverages"

    # Bakery
    if any(k in name_lower for k in ["bread", "bun", "pav", "cake", "croissant", "rusk", "muffin", "toast"]):
        return "Bakery"

    # Electronics
    if any(k in name_lower for k in ["charger", "cable", "earphone", "headphone", "battery", "bulb", "adapter", "usb", "plug"]):
        return "Electronics"

    # Pharmacy & OTC
    if any(k in name_lower for k in ["paracetamol", "dolo", "bandage", "dettol", "savlon", "aspirin", "tablet", "capsule", "syrup", "antiseptic", "ointment", "crocin", "vicks"]):
        return "Pharmacy"

    # Butcher / Meat
    if any(k in name_lower for k in ["chicken", "mutton", "fish", "prawn", "meat", "seafood"]):
        return "Butcher"

    return "Grocery"


def build_product_payload(product_data: dict, shop_id: str, mode: str, shop_category: str = None) -> dict:
    """
    Build the exact Supabase `products` table payload matching Flutter's
    `lib/pages/seller/add_product_page.dart` (_saveProduct).
    """
    is_pharmacy = mode == "pharmacy"

    # 100x Omnibus & Department-Aware Category Determination
    is_omnibus_shop = shop_category in (
        "Supermarket / Hypermarket",
        "General Store",
        "Departmental Store",
        "Supermart",
        "Hypermart",
        "Kirana",
    )

    prod_cat = product_data.get("category")
    if is_pharmacy:
        category = "Pharmacy"
    elif prod_cat and prod_cat in VALID_APP_CATEGORIES and prod_cat != "Supermarket / Hypermarket":
        category = prod_cat
    elif is_omnibus_shop:
        category = classify_department_category(product_data.get("name", ""), prod_cat)
    elif shop_category and shop_category in VALID_APP_CATEGORIES:
        category = shop_category
    else:
        category = "Grocery"

    # Pure MRP (float)
    price = product_data.get("price", 0.0)
    if price <= 0:
        return None

    # Variants: list of variant objects
    variants = []
    for v in product_data.get("variants", []):
        variants.append({
            "id": v.get("id", f"v_{int(time.time() * 1000)}_{len(variants)}"),
            "name": v.get("name", "Standard Pack"),
            "price": float(v.get("price", price)),
            "original_price": None,
            "is_available": True,
        })

    if not variants:
        variants.append({
            "id": f"v_{int(time.time() * 1000)}_0",
            "name": product_data.get("pack_info") or "Standard Pack",
            "price": float(price),
            "original_price": None,
            "is_available": True,
        })

    # Description: Salts / composition ONLY for medicines
    raw_desc = product_data.get("description", "")
    description = raw_desc.strip() if raw_desc and raw_desc.strip() else None

    # Menu category (therapeutic class for pharmacy, aisle for grocery)
    menu_category = product_data.get("menu_category") or ("Pain Relief & Fever" if is_pharmacy else "General")

    # Veg / Non-veg: strictly null for pharmacy
    is_veg = None if is_pharmacy else product_data.get("is_veg", True)

    # Brand / Manufacturer
    brand = (product_data.get("brand") or product_data.get("brand_name") or "").strip() or None

    payload = {
        "shop_id": shop_id,
        "name": product_data.get("name", "Unknown Product").strip(),
        "brand": brand,
        "price": float(price),
        "original_price": None,  # 100% pure MRP
        "description": description,
        "category": category,
        "menu_category": menu_category,
        "is_veg": is_veg,
        "is_available": True,
        "weight_per_unit": product_data.get("weight_per_unit"),
        "unit_type": "pieces",  # Strictly pieces per user requirement
        "total_quantity": None,
        "images": product_data.get("image_urls", []),
        "requires_prescription": bool(product_data.get("requires_prescription", False)) if is_pharmacy else False,
        "medicine_type": "General",  # Always General per user rules
        "variants": variants,
        "gst_rate_override": None,
        "bulk_eligible": False,
        "min_bulk_quantity": 10,
        "bulk_price_tiers": [],
        "special_tags": [],
        "is_deleted": False,  # Soft delete default
    }

    return payload


def run_engine(args):
    """Master engine execution pipeline."""
    config = get_supabase_config()

    if not config.get("url") or not config.get("key"):
        print("❌ ERROR: SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env")
        sys.exit(1)

    print("=" * 70)
    print("🚀  ENYTHING AUTO PRODUCT UPLOAD ENGINE v2.0")
    print("=" * 70)
    print(f"  Mode:       {args.mode.upper()}")
    print(f"  Shop ID:    {args.shop_id}")
    print(f"  Dry Run:    {args.dry_run}")
    print(f"  Supabase:   {config['url'][:45]}...")
    print("=" * 70)
    print()

    # Verify Shop Exists (by ID or Name fallback)
    shop_info = get_shop_info(config, args.shop_id) if args.shop_id else {}
    if not shop_info and hasattr(args, "shop_name") and args.shop_name:
        shop_info = get_shop_by_name(config, args.shop_name)
    if not shop_info and args.shop_id and not re.match(r"^[0-9a-fA-F-]{36}$", args.shop_id):
        shop_info = get_shop_by_name(config, args.shop_id)

    if shop_info:
        args.shop_id = shop_info["id"]
        shop_category = shop_info.get("category")
        print(f"  🏪 Verified Shop: {shop_info.get('name', 'Shop')} (ID: {args.shop_id}, Category: {shop_category})")
    else:
        shop_category = None
        print(f"  ⚠️  Shop {args.shop_id} not found in database or permission limited. Continuing...")

    # ── STEP 1: Identification & Extraction ───────────────────────────────────
    products_to_research = []

    if args.products:
        # Check if argument is a JSON file path or a comma-separated list
        if os.path.exists(args.products):
            print(f"📋 Reading products from file: {args.products}")
            with open(args.products) as f:
                data = json.load(f)
                products_to_research = analyze_shelf_image_from_names(data)
        else:
            names = [n.strip() for n in args.products.split(",") if n.strip()]
            print(f"📋 Processing {len(names)} direct product names...")
            products_to_research = analyze_shelf_image_from_names(names)

    elif args.image:
        import glob
        image_inputs = [img.strip() for img in args.image.split(",") if img.strip()]
        resolved_images = []
        for inp in image_inputs:
            matches = glob.glob(inp)
            if matches:
                resolved_images.extend(matches)
            elif os.path.exists(inp):
                resolved_images.append(inp)

        if not resolved_images:
            resolved_images = image_inputs

        gemini_key = os.environ.get("GEMINI_API_KEY", "")
        seen_product_names = set()

        for idx, img_path in enumerate(resolved_images, 1):
            print(f"🔍 Analyzing image [{idx}/{len(resolved_images)}] with Vision Engine: {img_path}")
            items = analyze_shelf_image(img_path, api_key=gemini_key, mode=args.mode)
            for it in items:
                norm_name = it["name"].strip().lower()
                if norm_name not in seen_product_names:
                    seen_product_names.add(norm_name)
                    products_to_research.append(it)

    if not products_to_research:
        print("❌ No products found to process. Exiting.")
        sys.exit(0)

    if args.limit and args.limit > 0:
        products_to_research = products_to_research[:args.limit]
        print(f"  (Processing limited to first {args.limit} products)")

    print(f"\n📦 Identified {len(products_to_research)} products to research:")
    for idx, p in enumerate(products_to_research, 1):
        print(f"   {idx}. {p['name']} ({p.get('pack_info') or 'Standard'})")

    # ── STEP 2: Research & Verification ───────────────────────────────────────
    print(f"\n🔬 Step 2: Researching products across verified databases...")
    enriched_products = []
    skipped_duplicates = []
    failed_products = []

    research_fn = research_pharmacy_product if args.mode == "pharmacy" else research_grocery_product

    for i, item in enumerate(products_to_research, 1):
        name = item["name"]
        print(f"\n  [{i}/{len(products_to_research)}] Researching: {name}")

        try:
            # Check duplicate in shop (Soft-delete rule: is_deleted = false)
            if not args.dry_run and check_duplicate_product(config, args.shop_id, name):
                print(f"    ⏭️  DUPLICATE: Already exists in shop (is_deleted=false). Skipping.")
                skipped_duplicates.append(name)
                continue

            # Query online medical database
            enriched = research_fn(name)

            if enriched and enriched.get("price", 0) > 0:
                # Merge any pack info from vision if missing
                if not enriched.get("pack_info") and item.get("pack_info"):
                    enriched["pack_info"] = item["pack_info"]

                enriched_products.append(enriched)
                print(f"    ✅ Verified: {enriched['name']}")
                print(f"       MRP: ₹{enriched['price']} | Category: {enriched['menu_category']} | Rx: {enriched['requires_prescription']}")
                if enriched.get("description"):
                    print(f"       Salts: {enriched['description'][:75]}...")
            else:
                print(f"    ⚠️  Could not find verified MRP. Queued for manual review.")
                failed_products.append({"name": name, "reason": "No verified Indian MRP found"})

            time.sleep(0.4)  # Respectful API pacing
        except Exception as e:
            print(f"    ❌ Error: {e}")
            failed_products.append({"name": name, "reason": str(e)})

    if not enriched_products:
        print("\n⚠️  No products were enriched. Exiting.")
        sys.exit(0)

    # ── STEP 3: 1:1 Image Pipeline (2 Images Guaranteed) ──────────────────────
    print(f"\n🖼️  Step 3: Preparing 2 high-resolution 1:1 (800x800) images per product...")
    image_dir = DATA_DIR / "product_images"
    image_dir.mkdir(exist_ok=True)

    for i, product in enumerate(enriched_products, 1):
        name = product["name"]
        print(f"  [{i}/{len(enriched_products)}] Generating 1:1 images for: {name[:40]}")

        try:
            local_paths = download_and_prepare_images(
                product_name=name,
                image_urls=product.get("source_image_urls", []),
                output_dir=str(image_dir),
                index=i,
                salts=product.get("description", ""),
                pack_info=product.get("pack_info", ""),
                is_rx=product.get("requires_prescription", False),
            )
            product["local_image_paths"] = local_paths
            print(f"    ✅ 2 pristine 1:1 images ready")
        except Exception as e:
            print(f"    ⚠️  Image pipeline fallback: {e}")
            product["local_image_paths"] = []

        time.sleep(0.2)

    # ── STEP 4: Supabase Upload ───────────────────────────────────────────────
    if args.dry_run:
        print("\n" + "=" * 70)
        print("🏁  DRY RUN COMPLETED — NO DATABASE CHANGES MADE")
        print("=" * 70)
        print("Ready for upload payload preview:\n")
        for idx, p in enumerate(enriched_products, 1):
            payload = build_product_payload(p, args.shop_id, args.mode, shop_category=shop_category)
            print(f"  {idx}. {payload['name']}")
            print(f"     Price: ₹{payload['price']} | Category: {payload['category']} > {payload['menu_category']}")
            print(f"     Rx Required: {payload['requires_prescription']} | Medicine Type: {payload['medicine_type']}")
            print(f"     Salts / Desc: {payload['description']}")
            print(f"     Images: {len(p.get('local_image_paths', []))} prepared (1:1 800x800)")
            print(f"     Variants: {payload['variants']}")
            print()
    else:
        print(f"\n📤 Step 4: Uploading {len(enriched_products)} products to Supabase...")
        uploaded_count = 0
        failed_upload = 0

        for i, product in enumerate(enriched_products, 1):
            name = product["name"]
            print(f"\n  [{i}/{len(enriched_products)}] Uploading: {name}")

            try:
                # Upload images to Supabase Storage
                image_urls = []
                if product.get("local_image_paths"):
                    image_urls = upload_images_to_supabase(
                        config=config,
                        shop_id=args.shop_id,
                        image_paths=product["local_image_paths"],
                        product_index=i,
                        fallback_cdn_urls=product.get("source_image_urls", []),
                    )

                product["image_urls"] = image_urls

                # Build and insert payload
                payload = build_product_payload(product, args.shop_id, args.mode, shop_category=shop_category)
                if payload:
                    payload["images"] = image_urls
                    result = insert_product(config, payload)
                    if result:
                        uploaded_count += 1
                        print(f"    ✨ SUCCESS: {name} (₹{payload['price']}) added to shop!")
                    else:
                        failed_upload += 1
                        print(f"    ❌ DB insert failed for: {name}")
                else:
                    failed_upload += 1
                    print(f"    ❌ Invalid payload for: {name}")

                time.sleep(0.3)
            except Exception as e:
                failed_upload += 1
                print(f"    ❌ Upload exception: {e}")

        # Summary
        print("\n" + "=" * 70)
        print("📊  AUTO UPLOAD EXECUTIVE REPORT")
        print("=" * 70)
        print(f"  ✅ Uploaded to Shop:    {uploaded_count}")
        print(f"  ⏭️  Skipped Duplicates: {len(skipped_duplicates)}")
        print(f"  ⚠️  Failed / Need Review: {len(failed_products) + failed_upload}")
        print(f"  📦 Total Processed:      {len(products_to_research)}")
        print("=" * 70)

    # Save execution audit report
    report_file = DATA_DIR / f"upload_report_{int(time.time())}.json"
    report_data = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "mode": args.mode,
        "shop_id": args.shop_id,
        "dry_run": args.dry_run,
        "total_detected": len(products_to_research),
        "enriched_count": len(enriched_products),
        "skipped_duplicates": skipped_duplicates,
        "failed_items": failed_products,
    }
    with open(report_file, "w") as f:
        json.dump(report_data, f, indent=2)
    print(f"\n📄 Saved execution audit report: {report_file}")


def main():
    parser = argparse.ArgumentParser(
        description="Enything Auto Medicine & Product Upload Engine v2.0",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--image", type=str, help="Path to shelf or medicine photo (or comma-separated paths / glob)")
    parser.add_argument("--products", type=str, help="Comma-separated product names or JSON file path")
    parser.add_argument("--shop-id", type=str, default="56883899-c115-42d9-82a9-90a9e59d21ec", help="Target shop UUID (defaults to Noor Medicate)")
    parser.add_argument("--shop-name", type=str, default="Noor Medicate", help="Target shop name (used if shop-id is not provided)")
    parser.add_argument("--mode", choices=["pharmacy", "grocery"], default="pharmacy", help="Upload mode")
    parser.add_argument("--dry-run", action="store_true", help="Simulate without writing to DB")
    parser.add_argument("--limit", type=int, default=0, help="Max number of items to process")

    args = parser.parse_args()

    if not args.image and not args.products:
        parser.error("Must provide either --image or --products")

    run_engine(args)


if __name__ == "__main__":
    main()
