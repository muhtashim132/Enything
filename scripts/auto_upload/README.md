# 🚀 Enything Auto Product & Restaurant Menu Upload Engine v2.0

> **100x Forensic Engineering Direct Challenge with Claude Code**  
> An automated, high-precision product & restaurant menu ingestion engine that reads shelf photos, brand names, or multi-page restaurant menu booklets, extracts Section Headings (`menu_category`), parses variants/portions, classifies Veg/Non-Veg, fetches real food/pharma photos via free public APIs, formats exactly 2 studio-grade 1:1 images, and uploads directly to Supabase with $0 paid APIs.

---

## 💎 Key Breakthroughs & Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│               ENYTHING AUTO UPLOAD PIPELINE v2.0                      │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  STEP 1: MULTI-TIER VISION & OCR (100% Free)                           │
│  ├── Native Apple Silicon Neural OCR (Compiled Swift + Vision OS)     │
│  │   ├── 2D Horizontal Row Clustering: Pairs dishes on left with       │
│  │   │   prices & variants on right across menu sheets                 │
│  │   └── Section Hierarchy: Extracts "PIZZAS", "BURGERS", "STARTERS",   │
│  │       "MAIN COURSE", etc. as `menu_category`                        │
│  └── Cloud Fallback: Gemini 2.0 Flash Vision (Free Tier AI Studio)     │
│      └── Structured schema extraction for complex stylized menus       │
│                                                                        │
│  STEP 2: VERIFIED WEB ENRICHMENT & CLASSIFICATION (100% Free)          │
│  ├── Restaurant: Wikipedia PageImages API + TheMealDB Open Recipe DB   │
│  ├── Pharmacy: PharmEasy Public Catalog API (Verified MRP, Salts, Rx)  │
│  ├── Grocery: OpenFoodFacts India Catalog & FMCG Datasets              │
│  └── Auto Veg/Non-Veg & Culinary Flavor Profile Generation             │
│                                                                        │
│  STEP 3: 1:1 IMAGE FORMATTING & STUDIO CARDS                           │
│  ├── Preserves full food presentation & packages (never awkward crops) │
│  ├── Exactly 2 Images Guaranteed (800x800, JPEG 85, < 400KB)           │
│  └── Culinary Studio Cards:                                            │
│      ├── Card 1: Dish Spotlight (Emblem, Category Pill, FSSAI Mark)    │
│      └── Card 2: Chef's Taste Profile (Flavor Notes, Serving Specs)    │
│                                                                        │
│  STEP 4: SUPABASE INGESTION & FORTRESS COMPLIANCE                      │
│  ├── Soft-Delete Rule: Strict `is_deleted = false` duplicate checks    │
│  ├── Schema Parity: Matches `add_product_page.dart` Flutter model      │
│  └── Zero Leftovers: Test purge utility for test safety                │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🛡️ Edge Cases Solved Once and For All

1. **Multi-Page Restaurant Menus (Page 1, Page 2, Page 3...)**:
   - Provide multiple photos comma-separated or as a glob: `--menu "page1.jpg,page2.jpg,page3.jpg"` or `--menu "menu/*.jpg"`.
   - Tracks active section headings across page breaks so items continuing on Page 2 stay under their proper category without orphan fallbacks.

2. **Menu Categories & Section Headings**:
   - Headings like "PIZZAS", "BURGERS", "STARTERS", "MAIN COURSE", "BEVERAGES" automatically map to `menu_category`.
   - In Flutter `RestaurantDashboardPage`, categories appear as dedicated Swiggy/Zomato-style filter tabs.

3. **Veg vs Non-Veg Dietary Integrity (`is_veg`)**:
   - Accurately classifies Indian vegetarian vs non-vegetarian dishes based on menu symbols, section headings, and comprehensive culinary ingredient dictionaries.
   - Strictly boolean (`true` or `false`) for restaurant food items, rendering official FSSAI green dot / red triangle marks on cards.

4. **Multi-Variant Pricing (Half/Full, Sizes, Portions)**:
   - Parses multi-column price matrices (e.g. `Half: ₹140 | Full: ₹250` or `Small: ₹199 | Medium: ₹349 | Large: ₹499`).
   - Base `price` is set to the minimum variant price, and `variants` array contains all sizes and prices.

5. **Appetizing Real Food Photography (100% Free)**:
   - Queries Wikipedia PageImages API and TheMealDB open database for unwatermarked, high-res food dish photography.
   - If web photos exist, formats them onto 1:1 800x800 square canvases. If missing, generates studio culinary cards with chef flavor profiles.

6. **Soft Delete & Testing Discipline Rule**:
   - Duplicate checks strictly include `&is_deleted=eq.false`.
   - Built-in test purge guarantees zero leftover test products in the production database.

---

## 🛠️ CLI Usage Guide

### 1. Restaurant Menu from Multi-Page Photos
```bash
# Using dedicated restaurant wrapper:
python3 scripts/upload_restaurant_menu.py \
  --menu "page1.jpg,page2.jpg,page3.jpg" \
  --shop-name "Kamrans Restaurant"

# Or using unified engine:
python3 scripts/auto_upload/engine.py \
  --mode restaurant \
  --image "page1.jpg,page2.jpg,page3.jpg" \
  --shop-name "Kamrans Restaurant"
```

### 2. Restaurant Menu Dry-Run (Preview with Zero DB Write)
```bash
python3 scripts/upload_restaurant_menu.py \
  --menu "page1.jpg,page2.jpg" \
  --shop-name "Kamrans Restaurant" \
  --dry-run
```

### 3. Upload from Dish Names Directly (With Categories & Prices)
```bash
python3 scripts/upload_restaurant_menu.py \
  --products "Pizzas > Margherita Pizza: 199, Burgers > Crispy Veg Burger: 120, Main Course > Butter Chicken: 240, Beverages > Cold Coffee: 150" \
  --shop-name "Kamrans Restaurant"
```

### 4. Pharmacy Mode (Shelf Photos or Medicines)
```bash
python3 scripts/auto_upload/engine.py \
  --image shelf_photo.jpg \
  --shop-id "YOUR-TARGET-SHOP-UUID" \
  --mode pharmacy
```

### 5. Grocery Mode (FMCG / Supermarket)
```bash
python3 scripts/auto_upload/engine.py \
  --products "Maggi 2-Minute Noodles 70g, Amul Butter 500g, Tata Salt 1kg" \
  --shop-id "YOUR-TARGET-SHOP-UUID" \
  --mode grocery
```

### 6. Curated High-Res Studio Food Photography (< 100KB)
Replaces generic/shared pictures with 100% UNIQUE, crystal-clear gourmet studio food photographs:
```bash
# Run for Foodies (default) or any shop ID:
python3 scripts/auto_upload/curate_studio_food_photos.py \
  --shop-id "c75542ec-63ca-4843-8ebc-eb285fa66fda" \
  --max-size-kb 98

# What it guarantees:
# 1. 100% Unique Photos: Zero duplicate images across dishes.
# 2. Aspect Ratio: Exact 1:1 square (800x800) center-cropped to highlight the dish.
# 3. File Size Ceiling: Strictly under 100 KB (65 - 95 KB) via iterative Lanczos compression.
# 4. Storage & DB: Uploads to Supabase Storage and updates live DB via bulk_upload_shop_products.
# 5. Inventory & Deletes: Preserves total_quantity = NULL and is_deleted = false.
```

---

## 📋 Product Schema Alignment

Matches `lib/pages/seller/add_product_page.dart` line-by-line:

| Field | Restaurant Value | Pharmacy Value | Notes |
|---|---|---|---|
| `shop_id` | UUID | UUID | Target merchant shop |
| `name` | string | string | Dish / Medicine name |
| `price` | double | double | Pure MRP / menu price (100% prepaid model) |
| `original_price` | null | null | No fake discounts |
| `description` | string | string | Culinary notes for food; Salts for pharma |
| `category` | `"Restaurant"` | `"Pharmacy"` | Matches AppCategories group |
| `menu_category` | string (e.g. "Pizzas") | string (e.g. "Pain Relief") | Section heading tab in app |
| `is_veg` | `true` / `false` | `null` | Boolean for food; null for pharma |
| `requires_prescription`| `false` | bool | True for Schedule H/H1/X; False for food |
| `medicine_type` | `"General"` | `"General"` | Always General per user rules |
| `images` | string[2] | string[2] | Array of 2 verified 1:1 image URLs (800x800) |
| `variants` | json[] | json[] | `[{id: "...", name: "Regular", price: ...}]` |
| `unit_type` | `"pieces"` | `"pieces"` | Strictly pieces per user requirement |
| `is_deleted` | `false` | `false` | Soft-delete default |


