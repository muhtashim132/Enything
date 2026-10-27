# 📋 Enything Auto-Upload Master Prompt Guide
> **100x Omni-Channel Catalog Ingestion Protocol for Gemini Flash, Claude Code & AI Assistants**

Save this document or copy any of the master prompts below. Whenever you upload images (menu photos, pharmacy shelf photos, or supermarket shelves) in the chat, send the corresponding prompt. The AI agent will immediately execute the ingestion pipeline without asking questions, making paid API calls, or altering section categories.

---

## 🌟 The Universal Master Prompt (Works for ANY Store)

Copy and paste this single prompt into the chat along with your photos:

```text
Run the auto-upload ingestion engine on the attached image(s) for the store below:

- Shop Name: [REPLACE_WITH_SHOP_NAME] (e.g. "Kamrans Restaurant" / "Noor Medicate" / "Reliance Fresh")
- Shop UUID (Optional): [OPTIONAL_SHOP_UUID]
- Store Type: [Restaurant / Pharmacy / Grocery / Supermarket]

Strict Execution Rules:
1. Category Preservation: Extract and use the EXACT printed section headings from the menu or shelf in clean Title Case (e.g. "Rice Dishes", "Indian Non Veg", "Tandoori Special", "Pain Relief & Fever"). NEVER alter, generalize, or replace printed headings with hardcoded defaults.
2. Restaurant Pricing & Variants: Accurately extract all printed portion sizes/rates (e.g. Half / Full, Regular / Medium / Large). Never invent a "Half" variant if no price was printed under Half. Base price = minimum variant price.
3. Inventory: For restaurants, leave total_quantity blank (NULL) so stock is unlimited.
4. Images: 
   - Restaurant: Generate strictly 1 studio culinary food photo (1:1 square 800x800, JPEG quality 80, < 120KB).
   - Pharmacy & Grocery: Prepare exactly 2 pristine padded 1:1 images (< 120KB each).
5. Payments & Compliance: 100% Prepaid Model (Zero COD), soft delete rule (is_deleted = false), and unit_type = 'pieces'.
6. Verification: Output an executive verification table showing the uploaded items, categories, prices, variants, image URLs, and unlimited stock status from the database.
```

---

## 🍽️ 1. Restaurant / Cafe Menu Master Prompt

Use this when uploading restaurant menu photos, booklets, leaflets, or PDFs:

```text
Run the restaurant menu digitization engine on the attached menu image(s):

- Restaurant Name: [REPLACE_WITH_RESTAURANT_NAME]
- Shop UUID (Optional): [OPTIONAL_UUID]
- Mode: restaurant
- Overwrite Existing: true

Strict Rules:
1. Preserve printed section headings verbatim in Title Case (e.g. "Rice Dishes", "Indian Non Veg", "Starters", "Breads"). Do NOT rename or generalize them.
2. Parse exact variant prices (Half / Full). Only create variants for prices actually printed on the menu.
3. total_quantity MUST be NULL (unlimited inventory).
4. Strictly 1 studio food hero photo per item (1:1 800x800, < 120KB compressed).
5. Accurate Veg / Non-Veg detection based on menu markers and ingredients.
```

---

## 💊 2. Pharmacy / Medical Store Shelf Master Prompt

Use this when uploading photos of pharmacy shelves, medicine boxes, tablet strips, or syrups:

```text
Run the pharmacy shelf scan ingestion engine on the attached shelf photo(s):

- Pharmacy Name: [REPLACE_WITH_PHARMACY_NAME] (default: "Noor Medicate")
- Shop UUID (Optional): [OPTIONAL_UUID]
- Mode: pharmacy

Strict Rules:
1. Extract brand name, dosage strength, and formulation (e.g. "Dolo 650 Tablet", "Augmentin 625 Duo").
2. Query verified Indian pharma database for MRP in ₹, active salt composition (in description), therapeutic category (in menu_category), and prescription requirement (requires_prescription: true/false).
3. medicine_type = "General", is_veg = null.
4. Prepare exactly 2 pristine white-padded 1:1 images (< 120KB each) preserving tablet strips and text edges.
5. Upload to Supabase Storage products bucket and verify database records.
```

---

## 🛒 3. Supermarket / Hypermart / Grocery Master Prompt

Use this when uploading photos of supermarket aisles, FMCG racks, snacks, beverages, or staples:

```text
Run the supermarket & grocery shelf scan ingestion engine on the attached shelf photo(s):

- Store Name: [REPLACE_WITH_STORE_NAME]
- Shop UUID (Optional): [OPTIONAL_UUID]
- Mode: grocery

Strict Rules:
1. Identify all visible packaged products with brand name, full title, and pack weight/volume (e.g. "Amul Butter 500g", "Tata Salt 1kg").
2. Auto-classify into statutory GST/commission departments: Dairy & Eggs (5%), Fruits & Vegs (0%), Bakery, Beverages, Cosmetics & Beauty (18%), or Grocery.
3. Detect Veg / Non-Veg status.
4. Prepare exactly 2 pristine 1:1 padded images (< 120KB each) on white background.
5. Ingest into Supabase with is_deleted = false and verify records.
```

---

## ⚙️ Direct Terminal Commands (For CLI Execution)

If running directly from terminal:

```bash
# 1. Restaurant Menu (Single/Multi-page or PDF):
python3 scripts/upload_restaurant_menu.py \
  --menu "menu_page1.jpg,menu_page2.jpg" \
  --shop-name "Kamrans Restaurant" \
  --overwrite

# 2. Pharmacy Shelf Photo:
python3 scripts/auto_upload/engine.py \
  --image "pharmacy_shelf.jpg" \
  --shop-name "Noor Medicate" \
  --mode pharmacy

# 3. Supermarket / Grocery Shelf Photo:
python3 scripts/auto_upload/engine.py \
  --image "grocery_shelf.jpg" \
  --shop-name "Reliance Fresh" \
  --mode grocery
```
