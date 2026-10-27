# 100x Omni-Channel Auto Product & Menu Upload Engine

## Trigger Phrases & Master Prompts
When the user requests any of the following:
- `"Upload products from this [menu/shelf image] to [shop name or UUID]"`
- `"Ingest restaurant menu from [image] for [restaurant name]"`
- `"Scan pharmacy/medical shelf [image] and upload medicines to [shop name]"`
- `"Scan grocery/supermart shelf [image] and upload products to [shop name]"`
- Or uses the **Universal Auto-Upload Master Prompt**:
  ```text
  Auto-upload products from the attached images to shop "[SHOP_NAME]".
  Shop UUID: [OPTIONAL_UUID]
  Mode: [auto / restaurant / pharmacy / grocery]
  ```

The AI agent MUST immediately execute the automated ingestion pipeline via `scripts/auto_upload/engine.py` or `scripts/upload_restaurant_menu.py` without asking repetitive questions, without modifying core logic, and without making any paid API calls.

---

## 3 Core Store Archetypes & Execution Rules

### 1. Restaurant / Cafe / Fast Food Outlets
- **Input Source**: Multi-page menu booklets, single page photos, laminated leaflets, or dish lists.
- **Section Headings (`menu_category`)**:
  - MUST preserve the EXACT printed heading from the menu in clean Title Case (e.g. `Rice Dishes`, `Indian Non Veg`, `Tandoori Special`, `Breads`, `Beverages`).
  - **CRITICAL**: NEVER rewrite, invent, rephrase, or generalize headings (e.g. NEVER convert `Rice Dishes` to `Biryani & Rice` or generic `Main Course`).
- **Variants & Pricing**:
  - Accurately parse multi-column variants (e.g. `Half: ₹160`, `Full: ₹300` or `Regular: ₹199`, `Medium: ₹349`, `Large: ₹499`).
  - If a dish has only one size printed (e.g. only in Full column), create strictly a single variant `[{"name": "Full", "price": 250.0}]` (never invent a fake "Half" variant).
  - Base `price` is set to the minimum variant price.
- **Dietary Badge (`is_veg`)**:
  - Strictly boolean (`true` or `false`).
  - Set `true` for paneer, dal, veg, mushroom, corn dishes or green dot symbols.
  - Set `false` for chicken, mutton, fish, egg, seafood, meat or red/brown triangle symbols.
- **Inventory / Quantity**:
  - `total_quantity`: MUST remain blank (`NULL` in Supabase) to indicate unlimited kitchen inventory.
- **Images**:
  - Strictly **1 single 1:1 photorealistic studio food image** (800×800, JPEG quality 80, ultra-compressed `< 120KB`).
  - Uploaded to Supabase Storage bucket `products` under `{shop_id}/{timestamp}_{index}_studio_hero.jpg`.
- **Execution Command**:
  ```bash
  python3 scripts/upload_restaurant_menu.py \
    --menu "<image_path(s)>" \
    --shop-name "<shop_name>" \
    --overwrite
  ```

---

### 2. Pharmacy / Medical Stores / Chemists
- **Input Source**: Shelf photos of medicine boxes, tablet strips, ointments, syrups.
- **Product Name & Strength**:
  - Extract brand/trade name with strength and formulation (e.g. `Dolo 650 Tablet`, `Augmentin 625 Duo`, `Azithral 500`).
- **Salts & Active Ingredients (`description`)**:
  - Verified active chemical composition (e.g. `Paracetamol (650mg)`, `Amoxicillin (500mg) + Clavulanic Acid (125mg)`).
- **Therapeutic Section (`menu_category`)**:
  - Verified clinical category (e.g. `Pain Relief & Fever`, `Antibiotics`, `Cardiac Care`, `Digestive Health`).
- **Statutory Prescription (`requires_prescription`)**:
  - `true` for Schedule H/H1/X drugs; `false` for OTC items.
  - `medicine_type`: strictly `"General"` per project rules.
  - `is_veg`: strictly `NULL` (dietary flags do not apply to allopathic medicines).
- **Images**:
  - Exactly **2 pristine 1:1 images** (800×800, `< 120KB` each) with clean white padded canvas preserving strip edges and tablet counts.
- **Execution Command**:
  ```bash
  python3 scripts/auto_upload/engine.py \
    --image "<image_path(s)>" \
    --shop-name "<shop_name>" \
    --mode pharmacy
  ```

---

### 3. Supermarket / Hypermart / Kirana / Grocery
- **Input Source**: Shelf photos of packaged goods, FMCG, snacks, beverages, staples.
- **Brand & Product Name**:
  - Extract brand name + full product name + pack weight/volume (e.g. `Tata Salt Iodized 1kg`, `Amul Butter 500g`, `Maggi 2-Minute Noodles Masala 70g`).
- **Omnibus Department Classification**:
  - Automatically categorize into proper statutory tax & commission departments: `Dairy & Eggs` (5% GST), `Fruits & Vegs` (0% GST), `Bakery`, `Beverages`, `Cosmetics & Beauty` (18% GST), or `Grocery`.
- **Dietary Badge (`is_veg`)**:
  - Boolean `true` or `false` based on FMCG green/brown dot or ingredients.
- **Images**:
  - Exactly **2 pristine 1:1 images** (800×800, `< 120KB` each) centered on white canvas.
- **Execution Command**:
  ```bash
  python3 scripts/auto_upload/engine.py \
    --image "<image_path(s)>" \
    --shop-name "<shop_name>" \
    --mode grocery
  ```

---

## Universal Verification & Database Standards
1. **Soft Delete Rule**: All queries, duplicate checks, and upserts MUST include `is_deleted = false`.
2. **100% Prepaid Model**: Strictly zero Cash on Delivery (COD). Pure standard price without artificial markups or fake discount tags (`original_price = null`).
3. **Unit Type**: Strictly `'pieces'` (plural).
4. **Zero Leftover Test Entities**: If running integration tests, all test items MUST be purged immediately using `bulk_delete_shop_products`.
5. **Post-Upload Verification**: After uploading, the agent MUST query Supabase for the uploaded items in that shop and present an executive summary table showing Dish/Product Name, Category/Section, Price, Variants, Image URLs, and Unlimited Stock status.
