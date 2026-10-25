# Automated Product Shelf Scan & Ingestion Engine

## Trigger Phrases
When the user asks to:
- `"Upload products from [image] to [shop]"`
- `"Scan shelf [image] and upload medicines to [shop]"`
- `"Auto upload medicines from [image]"`
- `"Upload shelf image [image]"`

The agent must immediately execute the established 100% free, end-to-end automated pipeline without asking unnecessary questions or making architectural changes.

---

## Architecture & Step-by-Step Protocol

### 1. Identify Target Shop
- Default target for pharmacy/medicines if unspecified: **Noor Medicate** (`ID: 56883899-c115-42d9-82a9-90a9e59d21ec`, Category: `Medical Store`).
- If another shop name or ID is provided, query `public.shops` where `is_deleted = false` to resolve `shop_id` and `category`.

### 2. OCR Extraction (100% Free & Native)
- Use `scripts/auto_upload/native_ocr` (compiled Apple Silicon Vision binary) via `scripts/auto_upload/vision.py`.
- Apply spatial bounding box clustering, deduplication, and filter out batch/expiry noise (e.g., `AUG.2028`, `10x10 Tablets`, manufacturer lines).

### 3. Verification & Clinical Research (100% Free APIs)
- Use `scripts/auto_upload/scraper.py` with the PharmEasy Catalog Search API (`https://pharmeasy.in/api/search/search/?intent=all&q=...`) to collect:
  - Exact Indian Market MRP (`price` in ₹, with pure MRP model where `original_price = null`).
  - Active composition / salts (stored in `description`, e.g. `Rosuvastatin(20.0 Mg)`).
  - Accurate therapeutic menu category (`Heart & BP`, `Pain Relief & Fever`, `Digestive Health`, etc.).
  - Schedule prescription status (`requires_prescription = true/false`).
  - Form & Packaging (`unit_type = 'pieces'`, variants e.g. `1 Strip (10 tabs)`).

### 4. Image Pipeline & Supabase Storage Hosting (Zero 503 Errors)
- Never hotlink directly to external CDNs (`cdn01.pharmeasy.in` returns HTTP 503 in mobile apps).
- Download source packaging images, format to **1:1 square canvas (800x800)** with white border padding (`#FFFFFF`) using Lanczos resampling so that tablet counts, strip edges, and dosage strengths are preserved.
- If official images are scarce, generate studio-grade clinical presentation cards (Product Card + Formulation Card).
- Upload images directly to Supabase Storage bucket `products` at path:
  `{shop_id}/{timestamp}_{index}.jpg`
- Set `images` in `public.products` to the public Supabase Storage URL:
  `https://<project-ref>.supabase.co/storage/v1/object/public/products/{shop_id}/{timestamp}_{index}.jpg`

### 5. Ingestion & Schema Rules
- Use `public.bulk_upload_shop_products(p_shop_id UUID, p_products JSONB)` RPC or `scripts/auto_upload/uploader.py`.
- **Soft Deletes**: Always enforce `is_deleted = false`.
- **Unit Type Normalization**: `unit_type` must strictly be `'pieces'` (plural) to match Flutter's `_availableUnitTypes` dropdown.
- **100% Prepaid Model**: Pure standard MRP pricing, zero COD.
- **Testing Discipline**: Purge all mock/test records immediately.

---

## Execution Command
```bash
python3 scripts/auto_upload/engine.py --image <image_path> --shop-id <shop_id>
```
