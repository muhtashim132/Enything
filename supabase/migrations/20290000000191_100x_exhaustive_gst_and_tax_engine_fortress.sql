-- ============================================================================
-- 20290000000191_100x_exhaustive_gst_and_tax_engine_fortress.sql
-- 100x Forensic Indian GST Statutory Tax Slab & Accounting Fortress
-- ============================================================================
--
-- ── REGULATORY FOUNDATION ─────────────────────────────────────────────────────
--   1. Central Goods and Services Tax (CGST) Act, 2017 (§9(5), §52, §2(30), §2(74))
--   2. Integrated Goods and Services Tax (IGST) Act, 2017
--   3. Legal Metrology Act 2009 & Packaged Commodities Rules 2011 (≤25 kg rule)
--   4. CBIC Notification No. 01/2017-CT(R) & 02/2017-CT(R) (Master Rate Schedules)
--   5. CBIC Notification No. 06/2022-CT(R) & 07/2022-CT(R) (Pre-packaged & Labelled)
--   6. CBIC Notification No. 17/2021-CT(R) (Section 9(5) E-Commerce Operator)
--   7. CBIC Notification No. 09/2025-CT(R) (GST 2.0 Rationalization — Sept 22, 2025)
--   8. 54th GST Council Directives (Extruded Savory Snacks 12%, Water 5%)
--   9. CBIC Circulars: 163 (Flavoured Milk), 164 (Cloud Kitchens), 167 (TCS Carve-out),
--      177 (Ice Cream Parlours 18% Goods), 179 (Bulk Grains >25 kg Exemption).
--
-- ── CRITICAL ARCHITECTURAL RECTIFICATIONS ─────────────────────────────────────
--   P0: Fix place_orders_transaction: match items by order_id or shop_id,
--       read products.gst_rate_override, compute Add-On GST (line * rate),
--       include v_non_food_gst in expected grand total, and suppress TCS for 0% goods.
--   P0: Fix decline_order_items_seller & customer_swap_order_item: replace blunt
--       is_food ? 0.05 : 0.18 overwrite with per-item statutory rate resolution
--       from order_items.gst_rate, products.gst_rate_override, and tax_config.
--   P1: Seed product_gst_overrides table with all 300+ statutory product rules.
--   P1: Add gst_rate and gst_amount columns to order_items for immutable audit trail.
--   P2: Fix platform_fee_gst_rate key lookup in rebalance_active_delivery_fees.
--
-- ============================================================================

-- ── 1. Order Items Schema Fortification ───────────────────────────────────────
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS gst_rate NUMERIC(5,4);
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS gst_amount NUMERIC(10,2);
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS hsn_code TEXT;

-- ── 2. Cleanse Stale / Obsolete Rows & Seed 350+ Statutory Rules ────────────
-- Fix ambiguous 'notebook' with NULL category to 'Electronics' (Laptop)
UPDATE public.product_gst_overrides
SET category_hint = 'Electronics',
    reason = 'Laptop / Notebook Computer — 18% (HSN 8471)',
    gst_rate = 0.1800,
    updated_at = now()
WHERE keyword = 'notebook' AND category_hint IS NULL;

-- Cleanse Educational Student Stationery (0% Statutory Exemption HSN 9609, 4820, 4016, 8214)
UPDATE public.product_gst_overrides
SET gst_rate = 0.0000, reason = 'Pencils — 0% (Exempt HSN 9609)', updated_at = now()
WHERE keyword = 'pencil' AND (category_hint = 'Stationery' OR category_hint IS NULL);

UPDATE public.product_gst_overrides
SET gst_rate = 0.0000, reason = 'Exercise Notebooks — 0% (Exempt HSN 4820)', updated_at = now()
WHERE keyword = 'notebook' AND category_hint = 'Stationery';

UPDATE public.product_gst_overrides
SET gst_rate = 0.0000, reason = 'Erasers — 0% (Exempt HSN 4016)', updated_at = now()
WHERE keyword = 'eraser' AND (category_hint = 'Stationery' OR category_hint IS NULL);

UPDATE public.product_gst_overrides
SET gst_rate = 0.0000, reason = 'Student Color Pencils — 0% (Exempt HSN 9609)', updated_at = now()
WHERE keyword = 'color pencil' AND (category_hint = 'Stationery' OR category_hint IS NULL);

UPDATE public.product_gst_overrides
SET gst_rate = 0.0000, reason = 'Student Crayons — 0% (Exempt HSN 9609)', updated_at = now()
WHERE keyword = 'crayon' AND (category_hint = 'Stationery' OR category_hint IS NULL);

-- Cleanse Female Sanitary Hygiene (0% Statutory Exemption HSN 9619)
UPDATE public.product_gst_overrides
SET gst_rate = 0.0000, reason = 'Sanitary Napkins — 0% (Universal Exemption HSN 9619)', updated_at = now()
WHERE keyword IN ('sanitary pad', 'sanitary napkin', 'whisper', 'stayfree', 'sofy');

-- Cleanse Fresh Cut Flowers & Fresh Garlands (0% Statutory Exemption HSN 0603)
UPDATE public.product_gst_overrides
SET gst_rate = 0.0000, reason = 'Fresh Cut Flowers & Garlands — 0% (Exempt HSN 0603)', updated_at = now()
WHERE keyword IN ('rose', 'marigold', 'jasmine', 'bouquet', 'garland') AND category_hint = 'Flowers';

-- Cleanse Dairy Products: Butter, Ghee & Cheese (12% Schedule II HSN 0405/0406)
UPDATE public.product_gst_overrides
SET gst_rate = 0.1200, reason = 'Desi Ghee — 12% (HSN 0405 90)', updated_at = now()
WHERE keyword = 'ghee';

UPDATE public.product_gst_overrides
SET gst_rate = 0.1200, reason = 'Butter & Dairy Spreads — 12% (HSN 0405 10)', updated_at = now()
WHERE keyword = 'butter';

UPDATE public.product_gst_overrides
SET gst_rate = 0.1200, reason = 'Processed Cheese / Mozzarella — 12% (HSN 0406)', updated_at = now()
WHERE keyword = 'cheese';

-- Cleanse Packaged Drinking Water (5% Concessional Rate — 54th GST Council)
UPDATE public.product_gst_overrides
SET gst_rate = 0.0500, reason = 'Packaged Drinking Water — 5% (54th GST Council)', updated_at = now()
WHERE keyword IN ('packaged water', 'mineral water') AND category_hint = 'Beverages';

-- Cleanse Packaged Fruit Juices (12% Schedule II Rate HSN 2009)
UPDATE public.product_gst_overrides
SET gst_rate = 0.1200, reason = 'Packaged Fruit Juice — 12% (HSN 2009)', updated_at = now()
WHERE keyword IN ('juice', 'fruit juice', 'real juice', 'tropicana') AND category_hint = 'Beverages';

-- Cleanse Extruded Snacks, Chips & Namkeen (12% Schedule II Rate)
UPDATE public.product_gst_overrides
SET gst_rate = 0.1200, reason = 'Extruded Savoury Snacks — 12% (54th GST Council)', updated_at = now()
WHERE keyword = 'kurkure';

UPDATE public.product_gst_overrides
SET gst_rate = 0.1200, reason = 'Savory Potato Chips — 12% (HSN 2005 20)', updated_at = now()
WHERE keyword IN ('chips', 'lays');

UPDATE public.product_gst_overrides
SET gst_rate = 0.1200, reason = 'Pre-packaged Namkeen — 12% (HSN 2106 90)', updated_at = now()
WHERE keyword = 'namkeen';

-- Cleanse Chocolates, Instant Noodles & Pasta (5% GST 2.0 Merit FMCG Rate)
UPDATE public.product_gst_overrides
SET gst_rate = 0.0500, reason = 'Chocolates & Cocoa Bars — 5% (Notif 9/2025 HSN 1806)', updated_at = now()
WHERE keyword IN ('chocolate', 'cadbury', 'dairy milk', 'kitkat');

UPDATE public.product_gst_overrides
SET gst_rate = 0.0500, reason = 'Instant Convenience Noodles & Pasta — 5% (HSN 1902)', updated_at = now()
WHERE keyword IN ('noodles', 'maggi', 'pasta');

-- Cleanse Retail Ice Cream Goods (18% Goods Rate — Circular 177 HSN 2105)
UPDATE public.product_gst_overrides
SET gst_rate = 0.1800, reason = 'Ice Cream Retail Goods — 18% (Circular 177 HSN 2105)', updated_at = now()
WHERE keyword = 'ice cream';

-- Cleanse Grooming, Deodorants, Shaving & Cleansers (18% Standard Rate)
UPDATE public.product_gst_overrides
SET gst_rate = 0.1800, reason = 'Deodorants & Body Sprays — 18% (HSN 3307)', updated_at = now()
WHERE keyword IN ('deodorant', 'deo spray', 'axe', 'nivea deo', 'fogg');

UPDATE public.product_gst_overrides
SET gst_rate = 0.1800, reason = 'Shaving Preparations — 18% (HSN 3307)', updated_at = now()
WHERE keyword IN ('shaving cream', 'shaving gel', 'aftershave', 'gillette foam');

UPDATE public.product_gst_overrides
SET gst_rate = 0.1800, reason = 'Safety Razors & Blades — 18% (HSN 8212)', updated_at = now()
WHERE keyword IN ('razor', 'gillette');

UPDATE public.product_gst_overrides
SET gst_rate = 0.1800, reason = 'Depilatory Creams — 18% (HSN 3307)', updated_at = now()
WHERE keyword IN ('veet', 'hair removal');

UPDATE public.product_gst_overrides
SET gst_rate = 0.1800, reason = 'Liquid Cleansers & Sanitizers — 18% (HSN 3402/3808)', updated_at = now()
WHERE keyword IN ('body wash', 'face wash', 'hand wash', 'dettol handwash', 'savlon handwash', 'sanitizer', 'hand sanitizer');

UPDATE public.product_gst_overrides
SET gst_rate = 0.1800, reason = 'Cosmetic Skin Lotions & Creams — 18% (HSN 3304)', updated_at = now()
WHERE keyword IN ('moisturiser', 'moisturizer', 'fairness cream', 'sunscreen', 'cold cream');

UPDATE public.product_gst_overrides
SET gst_rate = 0.1800, reason = 'Cotton Swabs & Cleansing Wipes — 18% (HSN 5601/3307)', updated_at = now()
WHERE keyword IN ('cotton buds', 'cotton balls', 'baby wipes', 'wet wipes');

-- Cleanse Sports, Toys & Merit Hardware (5% Merit Goods Rate)
UPDATE public.product_gst_overrides
SET gst_rate = 0.0500, reason = 'Outdoor Sports Equipment — 5% (HSN 9506)', updated_at = now()
WHERE keyword IN ('cricket bat', 'cricket ball', 'football', 'badminton') AND category_hint = 'Sports';

UPDATE public.product_gst_overrides
SET gst_rate = 0.0500, reason = 'Traditional Board Games — 5% (HSN 9504)', updated_at = now()
WHERE keyword = 'board game' AND category_hint = 'Toys & Games';

UPDATE public.product_gst_overrides
SET gst_rate = 0.0500, reason = 'LED Lamp / Bulb — 5% Merit Rate (HSN 8539 50)', updated_at = now()
WHERE keyword = 'led bulb';

-- ── Seed 350+ Statutory Product Rules into product_gst_overrides ──────────
INSERT INTO public.product_gst_overrides (keyword, category_hint, gst_rate, reason, is_active)
VALUES
  -- ── Sin Goods, Tobacco & Aerated / Energy Drinks (40% Peak Slabs) ──────────
  ('cigarette', NULL, 0.4000, 'Tobacco Products — 40% (Budget 2026)', true),
  ('cigarettes', NULL, 0.4000, 'Tobacco Products — 40% (Budget 2026)', true),
  ('marlboro', NULL, 0.4000, 'Cigarettes — 40% (Budget 2026)', true),
  ('gold flake', NULL, 0.4000, 'Cigarettes — 40% (Budget 2026)', true),
  ('classic milds', NULL, 0.4000, 'Cigarettes — 40% (Budget 2026)', true),
  ('wills navy', NULL, 0.4000, 'Cigarettes — 40% (Budget 2026)', true),
  ('dunhill', NULL, 0.4000, 'Cigarettes — 40% (Budget 2026)', true),
  ('cigar', NULL, 0.4000, 'Cigars — 40% (Budget 2026)', true),
  ('bidi', NULL, 0.4000, 'Bidis — 40% (Budget 2026)', true),
  ('tobacco', NULL, 0.4000, 'Tobacco — 40% (Budget 2026)', true),
  ('gutka', NULL, 0.4000, 'Gutka — 40% (Budget 2026)', true),
  ('pan masala', NULL, 0.4000, 'Pan Masala — 40% (Budget 2026)', true),
  ('rajnigandha', NULL, 0.4000, 'Pan Masala — 40%', true),
  ('vimal pan masala', NULL, 0.4000, 'Pan Masala — 40%', true),
  ('khaini', NULL, 0.4000, 'Tobacco Products — 40%', true),
  ('hookah', NULL, 0.4000, 'Hookah Tobacco — 40%', true),
  ('shisha', NULL, 0.4000, 'Shisha — 40%', true),
  ('zarda', NULL, 0.4000, 'Zarda — 40%', true),
  ('aerated drink', 'Beverages', 0.4000, 'Aerated Drinks — 40% Peak Slab', true),
  ('cola', 'Beverages', 0.4000, 'Cola Drinks — 40% Peak Slab', true),
  ('energy drink', 'Beverages', 0.4000, 'Energy Drinks — 40% Peak Slab', true),
  ('red bull', 'Beverages', 0.4000, 'Energy Drinks — 40% Peak Slab', true),
  ('monster energy', 'Beverages', 0.4000, 'Energy Drinks — 40% Peak Slab', true),
  ('sting energy', 'Beverages', 0.4000, 'Energy Drinks — 40% Peak Slab', true),
  ('pepsi', 'Beverages', 0.4000, 'Aerated Soft Drink — 40%', true),
  ('sprite', 'Beverages', 0.4000, 'Aerated Soft Drink — 40%', true),
  ('thums up', 'Beverages', 0.4000, 'Aerated Soft Drink — 40%', true),
  ('coca cola', 'Beverages', 0.4000, 'Aerated Soft Drink — 40%', true),
  ('coke', 'Beverages', 0.4000, 'Aerated Soft Drink — 40%', true),
  ('mountain dew', 'Beverages', 0.4000, 'Aerated Soft Drink — 40%', true),
  ('fanta', 'Beverages', 0.4000, 'Aerated Soft Drink — 40%', true),
  ('limca', 'Beverages', 0.4000, 'Aerated Soft Drink — 40%', true),
  ('7up', 'Beverages', 0.4000, 'Aerated Soft Drink — 40%', true),
  ('carbonated', 'Beverages', 0.4000, 'Carbonated Drinks — 40%', true),
  ('appy fizz', 'Beverages', 0.4000, 'Carbonated Fruit Drink — 40% (Notif 8/2021)', true),
  ('b-fizz', 'Beverages', 0.4000, 'Carbonated Fruit Drink — 40%', true),
  ('nimbooz masala soda', 'Beverages', 0.4000, 'Carbonated Fruit Drink — 40%', true),

  -- ── Fresh Produce & Raw Perishables (0% Universal Statutory Exemption) ─────
  ('onion', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt HSN 0703)', true),
  ('potato', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt HSN 0701)', true),
  ('tomato', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt HSN 0702)', true),
  ('spinach', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('palak', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('broccoli', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('cauliflower', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('gobi', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('cabbage', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('carrot', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('gajar', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('capsicum', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('cucumber', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('kheera', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('garlic', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('ginger', 'Fruits & Vegs', 0.0000, 'Fresh Produce — 0% (Exempt)', true),
  ('lemon', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt)', true),
  ('nimbu', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt)', true),
  ('green chilli', 'Fruits & Vegs', 0.0000, 'Fresh Vegetables — 0% (Exempt)', true),
  ('coriander', 'Fruits & Vegs', 0.0000, 'Fresh Herbs — 0% (Exempt)', true),
  ('mint', 'Fruits & Vegs', 0.0000, 'Fresh Herbs — 0% (Exempt)', true),
  ('apple', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt HSN 0808)', true),
  ('banana', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt HSN 0803)', true),
  ('mango', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt HSN 0804)', true),
  ('orange', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt HSN 0805)', true),
  ('papaya', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt)', true),
  ('grapes', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt)', true),
  ('pomegranate', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt)', true),
  ('watermelon', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt)', true),
  ('pineapple', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt)', true),
  ('guava', 'Fruits & Vegs', 0.0000, 'Fresh Fruits — 0% (Exempt)', true),
  ('coconut tender', 'Fruits & Vegs', 0.0000, 'Fresh Tender Coconut — 0% (Exempt)', true),
  ('fresh chicken', 'Butcher', 0.0000, 'Fresh Unprocessed Meat — 0% (Exempt HSN 0207)', true),
  ('raw chicken', 'Butcher', 0.0000, 'Fresh Unprocessed Meat — 0% (Exempt)', true),
  ('chicken curry cut', 'Butcher', 0.0000, 'Fresh Meat — 0% (Exempt)', true),
  ('chicken breast', 'Butcher', 0.0000, 'Fresh Meat — 0% (Exempt)', true),
  ('fresh mutton', 'Butcher', 0.0000, 'Fresh Meat — 0% (Exempt HSN 0204)', true),
  ('goat meat', 'Butcher', 0.0000, 'Fresh Meat — 0% (Exempt)', true),
  ('fresh fish', 'Fish & Seafood', 0.0000, 'Fresh Fish — 0% (Exempt Chapter 3)', true),
  ('pomfret', 'Fish & Seafood', 0.0000, 'Fresh Fish — 0% (Exempt)', true),
  ('surmai', 'Fish & Seafood', 0.0000, 'Fresh Fish — 0% (Exempt)', true),
  ('rohu', 'Fish & Seafood', 0.0000, 'Fresh Fish — 0% (Exempt)', true),
  ('fresh prawns', 'Fish & Seafood', 0.0000, 'Fresh Seafood — 0% (Exempt)', true),
  ('fresh egg', 'Dairy & Eggs', 0.0000, 'Fresh Eggs in Shell — 0% (Exempt HSN 0407)', true),
  ('farm eggs', 'Dairy & Eggs', 0.0000, 'Fresh Eggs in Shell — 0% (Exempt)', true),
  ('fresh milk', 'Dairy & Eggs', 0.0000, 'Fresh Milk — 0% (Exempt HSN 0401)', true),
  ('toned milk', 'Dairy & Eggs', 0.0000, 'Pasteurised Milk — 0% (Exempt)', true),
  ('cow milk', 'Dairy & Eggs', 0.0000, 'Fresh Milk — 0% (Exempt)', true),
  ('uht milk', 'Dairy & Eggs', 0.0000, 'UHT Milk — 0% (Exempt HSN 0401)', true),
  ('amul taaza', 'Dairy & Eggs', 0.0000, 'Fresh Milk — 0% (Exempt)', true),
  ('amul gold', 'Dairy & Eggs', 0.0000, 'Fresh Milk — 0% (Exempt)', true),
  ('mother dairy milk', 'Dairy & Eggs', 0.0000, 'Fresh Milk — 0% (Exempt)', true),

  -- ── Educational & Healthcare Universal Exemptions (0%) ─────────────────────
  ('notebook', 'Stationery', 0.0000, 'Exercise Notebooks — 0% (Exempt HSN 4820)', true),
  ('exercise book', 'Stationery', 0.0000, 'Exercise Books — 0% (Exempt)', true),
  ('classmate notebook', 'Stationery', 0.0000, 'Exercise Books — 0% (Exempt)', true),
  ('drawing book', 'Stationery', 0.0000, 'Drawing Books — 0% (Exempt)', true),
  ('pencil', 'Stationery', 0.0000, 'Pencils — 0% (Exempt HSN 9609)', true),
  ('apsara pencil', 'Stationery', 0.0000, 'Pencils — 0% (Exempt)', true),
  ('nataraj pencil', 'Stationery', 0.0000, 'Pencils — 0% (Exempt)', true),
  ('eraser', 'Stationery', 0.0000, 'Erasers — 0% (Exempt HSN 4016)', true),
  ('sharpener', 'Stationery', 0.0000, 'Sharpeners — 0% (Exempt HSN 8214)', true),
  ('textbook', 'Stationery', 0.0000, 'Printed Books — 0% (Exempt HSN 4901)', true),
  ('ncert', 'Stationery', 0.0000, 'Educational Books — 0% (Exempt)', true),
  ('crayons', 'Stationery', 0.0000, 'Crayons — 0% (Exempt)', true),
  ('sanitary pad', NULL, 0.0000, 'Sanitary Napkins — 0% (Universal Exemption HSN 9619)', true),
  ('sanitary napkin', NULL, 0.0000, 'Sanitary Napkins — 0% (Universal Exemption HSN 9619)', true),
  ('whisper', NULL, 0.0000, 'Sanitary Napkins — 0% (Exempt)', true),
  ('stayfree', NULL, 0.0000, 'Sanitary Napkins — 0% (Exempt)', true),
  ('sofy', NULL, 0.0000, 'Sanitary Napkins — 0% (Exempt)', true),
  ('tampon', NULL, 0.0000, 'Tampons — 0% (Exempt HSN 9619)', true),
  ('condom', NULL, 0.0000, 'Contraceptives — 0% (Exempt HSN 4014)', true),
  ('durex', NULL, 0.0000, 'Contraceptives — 0% (Exempt)', true),
  ('moods condom', NULL, 0.0000, 'Contraceptives — 0% (Exempt)', true),
  ('insulin', NULL, 0.0500, 'Insulin Formulations — 5% (HSN 3004 31 10)', true),
  ('trastuzumab', 'Pharmacy', 0.0000, 'Life-Saving Cancer Drug — 0% (GST 2.0)', true),
  ('osimertinib', 'Pharmacy', 0.0000, 'Life-Saving Cancer Drug — 0% (GST 2.0)', true),
  ('fresh cut flowers', 'Flowers', 0.0000, 'Natural Cut Flowers — 0% (Exempt HSN 0603)', true),
  ('rose garland', 'Flowers', 0.0000, 'Fresh Flower Garland — 0% (Exempt)', true),
  ('marigold garland', 'Flowers', 0.0000, 'Fresh Flower Garland — 0% (Exempt)', true),
  ('gajra', 'Flowers', 0.0000, 'Fresh Jasmine Gajra — 0% (Exempt)', true),
  ('betel leaf', 'Paan Shop', 0.0000, 'Fresh Betel Leaves — 0% (Exempt HSN 1404)', true),
  ('paan patta', 'Paan Shop', 0.0000, 'Fresh Betel Leaves — 0% (Exempt)', true),
  ('papad', NULL, 0.0000, 'Uncooked Dry Papad — 0% (Exempt HSN 1905)', true),
  ('lijjat papad', NULL, 0.0000, 'Uncooked Dry Papad — 0% (Exempt)', true),
  ('bread', 'Bakery', 0.0000, 'Plain Bread / Pav — 0% (Exempt HSN 1905)', true),
  ('white bread', 'Bakery', 0.0000, 'Plain Bread — 0% (Exempt)', true),
  ('brown bread', 'Bakery', 0.0000, 'Plain Bread — 0% (Exempt)', true),
  ('ladi pav', 'Bakery', 0.0000, 'Plain Pav — 0% (Exempt)', true),
  ('salt', 'Grocery', 0.0000, 'Salt — 0% (Exempt HSN 2501)', true),
  ('tata salt', 'Grocery', 0.0000, 'Salt — 0% (Exempt)', true),
  ('rock salt', 'Grocery', 0.0000, 'Rock Salt — 0% (Exempt)', true),

  -- ── Savory Snacks & Processed Foods — 12% (54th GST Council & Sched II) ────
  ('kurkure', NULL, 0.1200, 'Extruded Savoury Snacks — 12% (54th GST Council)', true),
  ('cheetos', NULL, 0.1200, 'Extruded Savoury Snacks — 12% (54th GST Council)', true),
  ('puffcorn', NULL, 0.1200, 'Extruded Savoury Snacks — 12% (54th GST Council)', true),
  ('fun flips', NULL, 0.1200, 'Extruded Savoury Snacks — 12% (54th GST Council)', true),
  ('namkeen', NULL, 0.1200, 'Pre-packaged Namkeen — 12% (HSN 2106 90)', true),
  ('bhujia', NULL, 0.1200, 'Pre-packaged Bhujia — 12% (HSN 2106 90)', true),
  ('aloo bhujia', NULL, 0.1200, 'Pre-packaged Bhujia — 12%', true),
  ('haldiram bhujia', NULL, 0.1200, 'Pre-packaged Bhujia — 12%', true),
  ('bikaji bhujia', NULL, 0.1200, 'Pre-packaged Bhujia — 12%', true),
  ('chivda', NULL, 0.1200, 'Pre-packaged Namkeen — 12%', true),
  ('khatta meetha', NULL, 0.1200, 'Pre-packaged Namkeen — 12%', true),
  ('potato chips', NULL, 0.1200, 'Savory Potato Chips — 12% (HSN 2005/2106)', true),
  ('chips', 'Grocery', 0.1200, 'Savory Potato Chips — 12%', true),
  ('lays', NULL, 0.1200, 'Potato Chips — 12% (HSN 2005 20)', true),
  ('uncle chipps', NULL, 0.1200, 'Potato Chips — 12%', true),
  ('bingo chips', NULL, 0.1200, 'Savory Chips — 12%', true),
  ('pringles', NULL, 0.1200, 'Savory Crisps — 12%', true),
  ('butter', 'Dairy & Eggs', 0.1200, 'Butter & Dairy Spreads — 12% (HSN 0405)', true),
  ('amul butter', 'Dairy & Eggs', 0.1200, 'Butter — 12% (HSN 0405 10)', true),
  ('ghee', 'Dairy & Eggs', 0.1200, 'Desi Ghee — 12% (HSN 0405 90)', true),
  ('cow ghee', 'Dairy & Eggs', 0.1200, 'Desi Ghee — 12%', true),
  ('cheese', 'Dairy & Eggs', 0.1200, 'Processed Cheese / Mozzarella — 12% (HSN 0406)', true),
  ('amul cheese', 'Dairy & Eggs', 0.1200, 'Processed Cheese — 12%', true),
  ('cheese slices', 'Dairy & Eggs', 0.1200, 'Processed Cheese — 12%', true),
  ('mozzarella', 'Dairy & Eggs', 0.1200, 'Cheese — 12%', true),
  ('condensed milk', 'Dairy & Eggs', 0.1200, 'Condensed Milk — 12% (HSN 0402 91)', true),
  ('milkmaid', 'Dairy & Eggs', 0.1200, 'Condensed Milk — 12%', true),
  ('flavoured milk', 'Dairy & Eggs', 0.1200, 'Flavoured Milk Beverage — 12% (Circular 163)', true),
  ('amul kool', 'Dairy & Eggs', 0.1200, 'Flavoured Milk — 12% (HSN 2202 99 30)', true),
  ('cavin milkshake', 'Dairy & Eggs', 0.1200, 'Flavoured Milk — 12%', true),
  ('badam milk', 'Dairy & Eggs', 0.1200, 'Flavoured Milk — 12%', true),
  ('fruit juice', 'Beverages', 0.1200, 'Packaged Fruit Juice — 12% (HSN 2009)', true),
  ('real juice', 'Beverages', 0.1200, 'Fruit Juice — 12%', true),
  ('tropicana', 'Beverages', 0.1200, 'Fruit Juice — 12%', true),
  ('frooti', 'Beverages', 0.1200, 'Fruit Pulp Drink — 12% (HSN 2202 99 20)', true),
  ('maaza', 'Beverages', 0.1200, 'Fruit Pulp Drink — 12%', true),
  ('slice', 'Beverages', 0.1200, 'Fruit Pulp Drink — 12%', true),
  ('sausage', 'Butcher', 0.1200, 'Processed Cured Meat — 12% (HSN 1601)', true),
  ('salami', 'Butcher', 0.1200, 'Processed Meat — 12%', true),
  ('bacon', 'Butcher', 0.1200, 'Processed Meat — 12%', true),
  ('canned tuna', 'Fish & Seafood', 0.1200, 'Preserved Fish — 12% (HSN 1604)', true),
  ('menstrual cup', 'Pharmacy', 0.1200, 'Menstrual Cups — 12% (HSN 9619)', true),

  -- ── Staples, Groceries & FMCG — 5% Merit Rate (GST 2.0 Rationalized) ────────
  ('rice', 'Grocery', 0.0500, 'Pre-packaged Basmati/Grain — 5% (HSN 1006)', true),
  ('basmati rice', 'Grocery', 0.0500, 'Pre-packaged Rice — 5%', true),
  ('daawat', 'Grocery', 0.0500, 'Pre-packaged Rice — 5%', true),
  ('india gate', 'Grocery', 0.0500, 'Pre-packaged Rice — 5%', true),
  ('atta', 'Grocery', 0.0500, 'Pre-packaged Wheat Flour — 5% (HSN 1101)', true),
  ('aashirvaad atta', 'Grocery', 0.0500, 'Pre-packaged Atta — 5%', true),
  ('maida', 'Grocery', 0.0500, 'Pre-packaged Flour — 5%', true),
  ('sooji', 'Grocery', 0.0500, 'Pre-packaged Sooji/Rava — 5%', true),
  ('besan', 'Grocery', 0.0500, 'Pre-packaged Besan — 5% (HSN 1106)', true),
  ('dal', 'Grocery', 0.0500, 'Pre-packaged Pulses — 5% (HSN 0713)', true),
  ('toor dal', 'Grocery', 0.0500, 'Pre-packaged Pulses — 5%', true),
  ('moong dal', 'Grocery', 0.0500, 'Pre-packaged Pulses — 5%', true),
  ('chana dal', 'Grocery', 0.0500, 'Pre-packaged Pulses — 5%', true),
  ('urad dal', 'Grocery', 0.0500, 'Pre-packaged Pulses — 5%', true),
  ('rajma', 'Grocery', 0.0500, 'Pre-packaged Kidney Beans — 5%', true),
  ('chhole', 'Grocery', 0.0500, 'Pre-packaged Chickpeas — 5%', true),
  ('cooking oil', 'Grocery', 0.0500, 'Edible Cooking Oil — 5% (HSN 1507-1515)', true),
  ('mustard oil', 'Grocery', 0.0500, 'Edible Mustard Oil — 5%', true),
  ('sunflower oil', 'Grocery', 0.0500, 'Edible Sunflower Oil — 5%', true),
  ('fortune oil', 'Grocery', 0.0500, 'Edible Cooking Oil — 5%', true),
  ('saffola', 'Grocery', 0.0500, 'Edible Cooking Oil — 5%', true),
  ('sugar', 'Grocery', 0.0500, 'Refined Sugar — 5% (HSN 1701)', true),
  ('jaggery', 'Grocery', 0.0500, 'Pre-packaged Gur/Jaggery — 5% (HSN 1701)', true),
  ('honey', 'Grocery', 0.0500, 'Natural Honey — 5% (HSN 0409)', true),
  ('dabur honey', 'Grocery', 0.0500, 'Honey — 5%', true),
  ('spices', 'Grocery', 0.0500, 'Spices & Condiments — 5% (Chapter 9)', true),
  ('masala', 'Grocery', 0.0500, 'Blended Masalas — 5% (HSN 0910 91)', true),
  ('garam masala', 'Grocery', 0.0500, 'Blended Masalas — 5%', true),
  ('sambar masala', 'Grocery', 0.0500, 'Blended Masalas — 5%', true),
  ('biryani masala', 'Grocery', 0.0500, 'Blended Masalas — 5%', true),
  ('haldi powder', 'Grocery', 0.0500, 'Turmeric Powder — 5%', true),
  ('red chilli powder', 'Grocery', 0.0500, 'Chilli Powder — 5%', true),
  ('ginger garlic paste', 'Grocery', 0.0500, 'Cooking Pastes — 5% (HSN 2103 90)', true),
  ('tomato ketchup', 'Grocery', 0.0500, 'Sauces & Ketchups — 5% (Notif 9/2025)', true),
  ('ketchup', 'Grocery', 0.0500, 'Sauces & Ketchups — 5%', true),
  ('sauce', 'Grocery', 0.0500, 'Table Sauces — 5% (HSN 2103)', true),
  ('mayonnaise', 'Grocery', 0.0500, 'Mayonnaise & Dressings — 5% (HSN 2103 90)', true),
  ('pickle', 'Grocery', 0.0500, 'Pickles / Achaar — 5% (Notif 9/2025 HSN 2001)', true),
  ('achaar', 'Grocery', 0.0500, 'Pickles / Achaar — 5%', true),
  ('almonds', 'Grocery', 0.0500, 'Edible Nuts — 5% (HSN 0802)', true),
  ('cashews', 'Grocery', 0.0500, 'Edible Cashews — 5% (HSN 0801)', true),
  ('kaju', 'Grocery', 0.0500, 'Edible Cashews — 5%', true),
  ('badam', 'Grocery', 0.0500, 'Edible Almonds — 5%', true),
  ('walnuts', 'Grocery', 0.0500, 'Edible Walnuts — 5%', true),
  ('raisins', 'Grocery', 0.0500, 'Dried Grapes / Kishmish — 5%', true),
  ('dates', 'Grocery', 0.0500, 'Edible Dates / Khajoor — 5%', true),
  ('packaged water', 'Beverages', 0.0500, 'Packaged Drinking Water — 5% (54th GST Council)', true),
  ('mineral water', 'Beverages', 0.0500, 'Packaged Drinking Water — 5% (HSN 2201)', true),
  ('bisleri', 'Beverages', 0.0500, 'Packaged Drinking Water — 5%', true),
  ('kinley', 'Beverages', 0.0500, 'Packaged Drinking Water — 5%', true),
  ('aquafina', 'Beverages', 0.0500, 'Packaged Drinking Water — 5%', true),
  ('water 20l', 'Beverages', 0.0500, '20 Litre Bulk Water Jar — 5% (54th Council)', true),
  ('tea', 'Beverages', 0.0500, 'Tea Leaves & Bags — 5% (HSN 0902)', true),
  ('chai', 'Beverages', 0.0500, 'Tea — 5%', true),
  ('green tea', 'Beverages', 0.0500, 'Green Tea — 5%', true),
  ('tata tea', 'Beverages', 0.0500, 'Tea — 5%', true),
  ('coffee', 'Beverages', 0.0500, 'Coffee — 5% (HSN 0901)', true),
  ('instant coffee', 'Beverages', 0.0500, 'Instant Coffee — 5% (Notif 9/2025 HSN 2101)', true),
  ('nescafe', 'Beverages', 0.0500, 'Instant Coffee — 5%', true),
  ('bru', 'Beverages', 0.0500, 'Instant Coffee — 5%', true),
  ('curd', 'Dairy & Eggs', 0.0500, 'Pre-packaged Curd / Dahi — 5% (HSN 0403)', true),
  ('dahi', 'Dairy & Eggs', 0.0500, 'Pre-packaged Dahi — 5%', true),
  ('amul masti dahi', 'Dairy & Eggs', 0.0500, 'Pre-packaged Dahi — 5%', true),
  ('lassi', 'Dairy & Eggs', 0.0500, 'Pre-packaged Lassi — 5% (HSN 0403)', true),
  ('buttermilk', 'Dairy & Eggs', 0.0500, 'Pre-packaged Buttermilk — 5%', true),
  ('chach', 'Dairy & Eggs', 0.0500, 'Pre-packaged Buttermilk — 5%', true),
  ('paneer', 'Dairy & Eggs', 0.0500, 'Pre-packaged Paneer — 5% (HSN 0406)', true),
  ('amul paneer', 'Dairy & Eggs', 0.0500, 'Pre-packaged Paneer — 5%', true),
  ('dairy whitener', 'Dairy & Eggs', 0.0500, 'Dairy Whitener — 5% (HSN 0402)', true),
  ('amulya', 'Dairy & Eggs', 0.0500, 'Dairy Whitener — 5%', true),
  ('milk powder', 'Dairy & Eggs', 0.0500, 'Milk Powder — 5% (HSN 0402)', true),
  ('infant milk food', 'Dairy & Eggs', 0.0500, 'Infant Baby Milk Formula — 5% (HSN 0402)', true),
  ('lactogen', 'Dairy & Eggs', 0.0500, 'Baby Formula — 5%', true),
  ('nan pro', 'Dairy & Eggs', 0.0500, 'Baby Formula — 5%', true),
  ('similac', 'Dairy & Eggs', 0.0500, 'Baby Formula — 5%', true),
  ('rusk', 'Bakery', 0.0500, 'Rusks & Toast — 5% (HSN 1905 40)', true),
  ('toast', 'Bakery', 0.0500, 'Rusks & Toast — 5%', true),
  ('pizza base', 'Bakery', 0.0500, 'Pizza Base — 5% (HSN 1905 90 80)', true),
  ('biscuit', 'Bakery', 0.0500, 'Packaged Biscuits — 5% (Notif 9/2025 HSN 1905)', true),
  ('cookies', 'Bakery', 0.0500, 'Cookies & Biscuits — 5%', true),
  ('parle g', 'Bakery', 0.0500, 'Biscuits — 5%', true),
  ('good day', 'Bakery', 0.0500, 'Biscuits — 5%', true),
  ('marie gold', 'Bakery', 0.0500, 'Biscuits — 5%', true),
  ('oreo', 'Bakery', 0.0500, 'Biscuits — 5%', true),
  ('cake', 'Bakery', 0.0500, 'Cakes & Pastries — 5% (Notif 9/2025 HSN 1905)', true),
  ('pastry', 'Bakery', 0.0500, 'Pastries — 5%', true),
  ('muffin', 'Bakery', 0.0500, 'Muffins — 5%', true),
  ('chocolate', NULL, 0.0500, 'Chocolates & Cocoa Bars — 5% (Notif 9/2025 HSN 1806)', true),
  ('cadbury', NULL, 0.0500, 'Chocolates — 5%', true),
  ('dairy milk', NULL, 0.0500, 'Chocolates — 5%', true),
  ('kitkat', NULL, 0.0500, 'Chocolates — 5%', true),
  ('5 star', NULL, 0.0500, 'Chocolates — 5%', true),
  ('snickers', NULL, 0.0500, 'Chocolates — 5%', true),
  ('mithai', 'Sweets & Mithai', 0.0500, 'Traditional Indian Sweets — 5% (HSN 2106)', true),
  ('kaju katli', 'Sweets & Mithai', 0.0500, 'Traditional Sweets — 5%', true),
  ('gulab jamun', 'Sweets & Mithai', 0.0500, 'Traditional Sweets — 5%', true),
  ('rasgulla', 'Sweets & Mithai', 0.0500, 'Traditional Sweets — 5%', true),
  ('laddu', 'Sweets & Mithai', 0.0500, 'Traditional Sweets — 5%', true),
  ('barfi', 'Sweets & Mithai', 0.0500, 'Traditional Sweets — 5%', true),
  ('soan papdi', 'Sweets & Mithai', 0.0500, 'Traditional Sweets — 5%', true),
  ('noodles', 'Grocery', 0.0500, 'Instant Convenience Noodles — 5% (HSN 1902)', true),
  ('maggi', NULL, 0.0500, 'Instant Noodles — 5% (HSN 1902 30)', true),
  ('yippee', NULL, 0.0500, 'Instant Noodles — 5%', true),
  ('pasta', 'Grocery', 0.0500, 'Dry Pasta / Macaroni — 5% (HSN 1902)', true),
  ('macaroni', 'Grocery', 0.0500, 'Dry Pasta — 5%', true),
  ('vermicelli', 'Grocery', 0.0500, 'Dry Vermicelli / Seviyan — 5% (HSN 1902)', true),
  ('supari', 'Paan Shop', 0.0500, 'Edible Betel Nut Products — 5% (HSN 2106 90 30)', true),
  ('snack pellets', 'Grocery', 0.0500, 'Un-fried Extruded Snack Pellets — 5%', true),
  ('raw fryums', 'Grocery', 0.0500, 'Un-fried Snack Pellets — 5%', true),
  ('diaper', NULL, 0.0500, 'Baby & Adult Diapers — 5% (Reduced from 12% HSN 9619)', true),
  ('pampers', NULL, 0.0500, 'Baby Diapers — 5% (GST 2.0)', true),
  ('huggies', NULL, 0.0500, 'Baby Diapers — 5% (GST 2.0)', true),
  ('mamypoko', NULL, 0.0500, 'Baby Diapers — 5% (GST 2.0)', true),
  ('adult diaper', NULL, 0.0500, 'Adult Diapers — 5% (GST 2.0)', true),
  ('friends adult', NULL, 0.0500, 'Adult Diapers — 5% (GST 2.0)', true),
  ('soap', NULL, 0.0500, 'Toilet Bathing Soap Bars — 5% FMCG Merit Rate', true),
  ('bathing soap', NULL, 0.0500, 'Toilet Soap — 5% FMCG Merit Rate', true),
  ('lux', NULL, 0.0500, 'Toilet Soap — 5% FMCG Merit Rate', true),
  ('lifebuoy', NULL, 0.0500, 'Toilet Soap — 5% FMCG Merit Rate', true),
  ('dettol soap', NULL, 0.0500, 'Toilet Soap — 5% FMCG Merit Rate', true),
  ('dove soap', NULL, 0.0500, 'Toilet Soap — 5% FMCG Merit Rate', true),
  ('shampoo', NULL, 0.0500, 'Shampoo — 5% FMCG Merit Rate (GST 2.0)', true),
  ('head and shoulders', NULL, 0.0500, 'Shampoo — 5% FMCG Merit Rate', true),
  ('head & shoulders', NULL, 0.0500, 'Shampoo — 5% FMCG Merit Rate', true),
  ('pantene', NULL, 0.0500, 'Shampoo — 5% FMCG Merit Rate', true),
  ('sunsilk', NULL, 0.0500, 'Shampoo — 5% FMCG Merit Rate', true),
  ('clinic plus', NULL, 0.0500, 'Shampoo — 5% FMCG Merit Rate', true),
  ('tresemme', NULL, 0.0500, 'Shampoo — 5% FMCG Merit Rate', true),
  ('dove shampoo', NULL, 0.0500, 'Shampoo — 5% FMCG Merit Rate', true),
  ('hair oil', NULL, 0.0500, 'Hair Oil — 5% FMCG Merit Rate', true),
  ('coconut oil', NULL, 0.0500, 'Hair/Cooking Oil — 5% (HSN 1513)', true),
  ('parachute', NULL, 0.0500, 'Hair/Edible Coconut Oil — 5%', true),
  ('dabur amla', NULL, 0.0500, 'Hair Oil — 5% FMCG Merit Rate', true),
  ('vatika', NULL, 0.0500, 'Hair Oil — 5% FMCG Merit Rate', true),
  ('hair conditioner', NULL, 0.1800, 'Hair Conditioner & Preparations — 18% (HSN 3305)', true),
  ('conditioner', NULL, 0.1800, 'Hair Conditioner — 18% (HSN 3305)', true),
  ('hair serum', NULL, 0.1800, 'Hair Serum — 18% (HSN 3305)', true),
  ('hair dye', NULL, 0.1800, 'Hair Dyes & Color — 18% (HSN 3305)', true),
  ('toothpaste', NULL, 0.0500, 'Toothpaste — 5% Dental Hygiene (GST 2.0)', true),
  ('colgate', NULL, 0.0500, 'Toothpaste — 5% Dental Hygiene', true),
  ('pepsodent', NULL, 0.0500, 'Toothpaste — 5% Dental Hygiene', true),
  ('sensodyne', NULL, 0.0500, 'Toothpaste — 5% Dental Hygiene', true),
  ('oral b', NULL, 0.0500, 'Toothpaste / Toothbrush — 5%', true),
  ('toothbrush', NULL, 0.0500, 'Manual Toothbrush — 5% (HSN 9603 21)', true),
  ('talcum powder', NULL, 0.0500, 'Talcum Powder — 5% Merit Rate', true),
  ('baby powder', NULL, 0.0500, 'Baby Talcum Powder — 5%', true),
  ('johnson baby', NULL, 0.0500, 'Baby Care Essentials — 5%', true),
  ('paracetamol', 'Pharmacy', 0.0500, 'Prescription & OTC Medicine — 5% (HSN 3004)', true),
  ('crocin', NULL, 0.0500, 'Paracetamol Formulations — 5%', true),
  ('dolo', NULL, 0.0500, 'Paracetamol Formulations — 5%', true),
  ('combiflam', NULL, 0.0500, 'Pain Relief Medicine — 5%', true),
  ('ibuprofen', NULL, 0.0500, 'Anti-inflammatory Medicine — 5%', true),
  ('aspirin', NULL, 0.0500, 'Analgesic Medicine — 5%', true),
  ('antacid', NULL, 0.0500, 'Antacid — 5%', true),
  ('eno', NULL, 0.0500, 'Antacid — 5%', true),
  ('gelusil', NULL, 0.0500, 'Antacid — 5%', true),
  ('cough syrup', NULL, 0.0500, 'Cough Syrup — 5%', true),
  ('benadryl', NULL, 0.0500, 'Cough Syrup — 5%', true),
  ('vicks', NULL, 0.0500, 'Vaporub / OTC Medicine — 5%', true),
  ('nasal spray', NULL, 0.0500, 'Nasal Decongestant — 5%', true),
  ('eye drop', NULL, 0.0500, 'Eye Drops — 5%', true),
  ('ear drop', NULL, 0.0500, 'Ear Drops — 5%', true),
  ('bandage', NULL, 0.0500, 'Medical Bandage — 5% (HSN 3005)', true),
  ('band-aid', NULL, 0.0500, 'First Aid Band-Aid — 5%', true),
  ('antiseptic', NULL, 0.0500, 'Antiseptic Liquid — 5%', true),
  ('dettol liquid', NULL, 0.0500, 'Antiseptic Liquid — 5%', true),
  ('thermometer', NULL, 0.0500, 'Clinical Thermometer — 5% (HSN 9025)', true),
  ('glucometer', NULL, 0.0500, 'Blood Glucose Monitor — 5% (HSN 9027)', true),
  ('accu chek', NULL, 0.0500, 'Blood Glucose Monitor & Strips — 5%', true),
  ('test strips', NULL, 0.0500, 'Diagnostic Test Strips — 5%', true),
  ('bp monitor', NULL, 0.0500, 'Blood Pressure Monitor — 5% (HSN 9018)', true),
  ('omron bp', NULL, 0.0500, 'Blood Pressure Monitor — 5%', true),
  ('surgical gloves', NULL, 0.0500, 'Medical Examination Gloves — 5% (HSN 4015)', true),
  ('surgical mask', NULL, 0.0500, 'Medical Masks — 5% (HSN 6307)', true),
  ('n95 mask', NULL, 0.0500, 'Protective Respiratory Masks — 5%', true),
  ('ors', NULL, 0.0500, 'Oral Rehydration Salts — 5%', true),
  ('electral', NULL, 0.0500, 'Oral Rehydration Salts — 5%', true),
  ('multivitamin', NULL, 0.0500, 'Therapeutic Multivitamin Formulations — 5%', true),
  ('ayurvedic', NULL, 0.0500, 'Ayurvedic Formulations — 5% (HSN 3004 90)', true),
  ('chyawanprash', NULL, 0.0500, 'Ayurvedic Formulations — 5%', true),
  ('zandu balm', NULL, 0.0500, 'Pain Relief Balm — 5%', true),
  ('tiger balm', NULL, 0.0500, 'Pain Relief Balm — 5%', true),
  ('moov', NULL, 0.0500, 'Pain Relief Ointment — 5%', true),
  ('volini', NULL, 0.0500, 'Pain Relief Spray / Gel — 5%', true),
  ('led bulb', 'Hardware Store', 0.0500, 'LED Lamp / Bulb — 5% Merit Rate (HSN 8539 50)', true),
  ('led tube light', 'Hardware Store', 0.0500, 'LED Tube Light — 5% Merit Rate', true),
  ('board game', 'Toys & Games', 0.0500, 'Traditional Board Games — 5% (HSN 9504)', true),
  ('chess', 'Toys & Games', 0.0500, 'Traditional Chess Board & Pieces — 5%', true),
  ('carrom', 'Toys & Games', 0.0500, 'Carrom Board & Coins — 5%', true),
  ('ludo', 'Toys & Games', 0.0500, 'Traditional Board Games — 5%', true),
  ('jigsaw puzzle', 'Toys & Games', 0.0500, 'Puzzles & Traditional Toys — 5% (HSN 9503)', true),
  ('wooden toys', 'Toys & Games', 0.0500, 'Non-electronic Traditional Toys — 5%', true),
  ('building blocks', 'Toys & Games', 0.0500, 'Non-electronic Construction Toys — 5%', true),
  ('teddy bear', 'Toys & Games', 0.0500, 'Soft Toys — 5% (HSN 9503)', true),
  ('cricket bat', 'Sports', 0.0500, 'Outdoor Sports Equipment — 5% (HSN 9506)', true),
  ('cricket ball', 'Sports', 0.0500, 'Sports Balls — 5%', true),
  ('football', 'Sports', 0.0500, 'Sports Balls — 5% (HSN 9506)', true),
  ('badminton racket', 'Sports', 0.0500, 'Sports Rackets — 5%', true),
  ('shuttlecock', 'Sports', 0.0500, 'Sports Requisites — 5%', true),

  -- ── Jewellery — 3% Statutory Slabs ─────────────────────────────────────────
  ('gold ring', 'Jewellery', 0.0300, 'Gold Jewellery — 3% Statutory Slab', true),
  ('gold necklace', 'Jewellery', 0.0300, 'Gold Jewellery — 3% Statutory Slab', true),
  ('gold chain', 'Jewellery', 0.0300, 'Gold Jewellery — 3% Statutory Slab', true),
  ('gold earring', 'Jewellery', 0.0300, 'Gold Jewellery — 3% Statutory Slab', true),
  ('gold coin', 'Jewellery', 0.0300, 'Gold Articles — 3% Statutory Slab', true),
  ('diamond ring', 'Jewellery', 0.0300, 'Diamond Jewellery — 3% Statutory Slab', true),
  ('diamond necklace', 'Jewellery', 0.0300, 'Diamond Jewellery — 3% Statutory Slab', true),
  ('silver ring', 'Jewellery', 0.0300, 'Silver Jewellery — 3% Statutory Slab', true),
  ('silver chain', 'Jewellery', 0.0300, 'Silver Jewellery — 3% Statutory Slab', true),
  ('silver coin', 'Jewellery', 0.0300, 'Silver Articles — 3% Statutory Slab', true),
  ('artificial jewellery', 'Jewellery', 0.0300, 'Imitation Jewellery — 3% Statutory Slab', true),
  ('imitation jewellery', 'Jewellery', 0.0300, 'Imitation Jewellery — 3% Statutory Slab', true)
ON CONFLICT (keyword, COALESCE(category_hint, '')) DO UPDATE SET
  gst_rate = EXCLUDED.gst_rate,
  reason = EXCLUDED.reason,
  is_active = true;

-- ── 3. Place Orders Transaction RPC Fortification ─────────────────────────────
CREATE OR REPLACE FUNCTION public.place_orders_transaction(
  p_orders jsonb,
  p_items jsonb,
  p_cart_group_id uuid,
  p_coupon_id uuid DEFAULT NULL::uuid,
  p_idempotency_key text DEFAULT NULL::text,
  p_order_id_to_cancel uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid;
  v_inserted_ids uuid[] := '{}';
  v_order jsonb;
  v_item jsonb;
  v_prod record;
  v_order_id uuid;
  v_expected_total_amount numeric;
  v_client_total_amount numeric;
  v_expected_grand_total numeric;
  v_client_grand_total numeric;
  v_item_price numeric;
  v_variant_price numeric;
  v_expected_discount numeric := 0;
  v_num_orders int;
  v_order_seq int := 0;
  v_is_replacement boolean := false;
  v_acceptance_deadline timestamptz;

  v_platform_fee_config numeric := 2.0;
  v_platform_gst_rate numeric := 0.18;
  v_server_gst_platform numeric;
  v_delivery_gst_rate numeric := 0.18;
  v_server_gst_delivery numeric;
  v_rider_commission_percent numeric := 80.0;
  v_server_rider_earnings numeric;
  v_server_seller_payout numeric;
  v_server_enything_commission numeric;

  v_tcs_rate numeric := 0.005;
  v_tds_rate numeric := 0.001;
  v_tcs_amount numeric := 0.0;
  v_tds_amount numeric := 0.0;
  v_gw_deduct numeric := 0.0;
  v_seller_gw_share numeric := 0.0;
  v_item_weight_kg numeric;
  v_clean_unit text;
  v_order_total_weight_kg numeric;
  v_group_total_weight_kg numeric := 0.0;
  v_existing_group_weight numeric := 0.0;

  v_s9_5_gst numeric := 0.0;
  v_non_food_gst numeric := 0.0;
  v_pure_commission numeric := 0.0;
  v_item_subtotal numeric := 0.0;
  v_item_gst numeric := 0.0;
  v_item_commission numeric := 0.0;
  v_item_is_food boolean := false;
  v_item_gst_rate numeric := 0.0;
  v_item_comm_rate numeric := 5.0;

  v_slab_threshold numeric := 2500.0;
  v_slab_high_rate numeric := 0.18;

  v_shop_cat text;
  v_comm_key text;
  v_comm_val numeric;

  v_existing_rider_id uuid;
  v_existing_rider_phone text;
  v_existing_partner_accepted boolean;
  v_secure_order jsonb;
  v_active_cart_groups_count int;
  v_rider_cap int := 3;

  v_shop_lat double precision;
  v_shop_lng double precision;
BEGIN
  v_customer_id := auth.uid();
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place orders';
  END IF;

  IF p_orders IS NULL OR jsonb_array_length(p_orders) = 0 THEN
    RAISE EXCEPTION 'Orders list cannot be empty';
  END IF;

  v_num_orders := jsonb_array_length(p_orders);

  -- Platform Service Tax Configurations
  BEGIN
    SELECT (value#>>'{}')::numeric INTO v_platform_fee_config FROM platform_config WHERE key = 'platform_fee';
    IF v_platform_fee_config IS NULL THEN v_platform_fee_config := 2.0; END IF;

    SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate' OR key = 'platform_gst_rate' LIMIT 1;
    IF v_platform_gst_rate IS NULL THEN v_platform_gst_rate := 0.18; END IF;

    SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate';
    IF v_delivery_gst_rate IS NULL THEN v_delivery_gst_rate := 0.18; END IF;

    SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent';
    IF v_rider_commission_percent IS NULL THEN v_rider_commission_percent := 80.0; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_platform_fee_config := 2.0;
    v_platform_gst_rate := 0.18;
    v_delivery_gst_rate := 0.18;
    v_rider_commission_percent := 80.0;
  END;

  -- Replacement Order Validation
  IF p_order_id_to_cancel IS NOT NULL THEN
    v_is_replacement := true;
    SELECT delivery_partner_id, rider_phone, partner_accepted
    INTO v_existing_rider_id, v_existing_rider_phone, v_existing_partner_accepted
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND id != p_order_id_to_cancel
      AND delivery_partner_id IS NOT NULL
      AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'failed', 'returned')
    LIMIT 1;

    -- Tally existing physical weight from active sibling orders
    SELECT COALESCE(SUM(oi.weight_kg * oi.quantity), 0.0)
    INTO v_existing_group_weight
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    WHERE o.cart_group_id = p_cart_group_id
      AND o.id != p_order_id_to_cancel
      AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'failed', 'returned')
      AND oi.status = 'active';

    v_group_total_weight_kg := v_existing_group_weight;
  END IF;

  -- Loop through each shop order
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders)
  LOOP
    v_order_seq := v_order_seq + 1;
    v_order_id := (v_order->>'id')::uuid;
    v_expected_total_amount := 0.0;
    v_client_total_amount := COALESCE((v_order->>'total_amount')::numeric, 0.0);
    v_client_grand_total := COALESCE((v_order->>'grand_total_collected')::numeric, 0.0);
    v_order_total_weight_kg := 0.0;

    v_s9_5_gst := 0.0;
    v_non_food_gst := 0.0;
    v_pure_commission := 0.0;
    v_tcs_amount := 0.0;
    v_tds_amount := 0.0;

    IF v_is_replacement THEN
      v_acceptance_deadline := NOW() + interval '5 minutes';
    ELSE
      v_acceptance_deadline := NOW() + interval '2 minutes';
    END IF;

    SELECT category INTO v_shop_cat FROM shops WHERE id = (v_order->>'shop_id')::uuid;

    -- Validate and process items for this specific shop order
    -- Robust match: check order_id (Dart standard) or shop_id fallback
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      IF ((v_item->>'order_id') IS NOT NULL AND (v_item->>'order_id')::uuid = v_order_id)
         OR ((v_item->>'order_id') IS NULL AND (v_item->>'shop_id')::uuid = (v_order->>'shop_id')::uuid) THEN

        SELECT * INTO v_prod FROM products 
        WHERE id = (v_item->>'product_id')::uuid 
          AND is_available = true 
          AND is_deleted = false
        FOR UPDATE;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'Product % is unavailable or deleted', (v_item->>'product_id');
        END IF;

        IF v_prod.total_quantity IS NOT NULL AND v_prod.total_quantity < (v_item->>'quantity')::int THEN
          RAISE EXCEPTION 'Insufficient stock for product % (Available: %, Requested: %)', 
            v_prod.name, v_prod.total_quantity, (v_item->>'quantity')::int;
        END IF;

        -- Unit Weight Calculation
        v_item_weight_kg := COALESCE(v_prod.weight_per_unit, 0.5);
        v_clean_unit := lower(trim(COALESCE(v_prod.unit, '')));
        IF v_clean_unit != '' THEN
          IF v_clean_unit ~ '^\d+(\.\d+)?\s*(g|gm|gms|gram|grams)$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
          ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*kg$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
          ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*m[lL]$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
          ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*(l|lt|ltr|ltrs|liter|liters|litre|litres)$' THEN
            v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
          END IF;
        END IF;

        IF v_item_weight_kg <= 0 THEN v_item_weight_kg := 0.5; END IF;
        v_order_total_weight_kg := v_order_total_weight_kg + (v_item_weight_kg * (v_item->>'quantity')::int);

        -- Price verification (variant vs base product)
        v_item_price := v_prod.price;
        IF (v_item->>'variant_name') IS NOT NULL AND v_prod.variants IS NOT NULL THEN
          SELECT (elem->>'price')::numeric INTO v_variant_price
          FROM jsonb_array_elements(v_prod.variants) AS elem
          WHERE elem->>'name' = (v_item->>'variant_name');
          IF v_variant_price IS NOT NULL AND v_variant_price > 0 THEN
            v_item_price := v_variant_price;
          END IF;
        END IF;

        v_item_subtotal := v_item_price * (v_item->>'quantity')::int;
        v_expected_total_amount := v_expected_total_amount + v_item_subtotal;

        -- ── 100x Forensic GST Resolution ──────────────────────────────────
        -- Section 9(5) deemed supplier check
        v_item_is_food := COALESCE(v_prod.is_food, (lower(COALESCE(v_shop_cat, '')) IN (
          'restaurant', 'food', 'bakery', 'cafe', 'fast_food', 'sweet_shop',
          'sweets & mithai', 'tea & coffee', 'ice cream', 'paan shop'
        )));

        -- Priority:
        -- 1. Product-level override from products table (gst_rate_override)
        -- 2. Client snapshot in v_item ('gst_rate')
        -- 3. Dynamic price-slab for Clothing / Footwear (≤2500 -> 5%, >2500 -> 18%)
        -- 4. Category rate from tax_config table
        -- 5. Fallback based on v_item_is_food
        IF v_prod.gst_rate_override IS NOT NULL THEN
          v_item_gst_rate := v_prod.gst_rate_override;
        ELSIF (v_item->>'gst_rate') IS NOT NULL AND (v_item->>'gst_rate')::numeric >= 0.0 THEN
          v_item_gst_rate := (v_item->>'gst_rate')::numeric;
        ELSIF COALESCE(v_prod.category, v_shop_cat) IN ('Clothing', 'Footwear') THEN
          SELECT COALESCE(slab_threshold, 2500.0), COALESCE(slab_high_rate, 0.18)
          INTO v_slab_threshold, v_slab_high_rate
          FROM tax_config WHERE category = COALESCE(v_prod.category, v_shop_cat);
          IF v_slab_threshold IS NULL THEN v_slab_threshold := 2500.0; END IF;
          IF v_slab_high_rate IS NULL THEN v_slab_high_rate := 0.18; END IF;
          IF v_item_price > v_slab_threshold THEN
            v_item_gst_rate := v_slab_high_rate;
          ELSE
            v_item_gst_rate := 0.05;
          END IF;
        ELSE
          SELECT gst_rate INTO v_item_gst_rate FROM tax_config WHERE category = COALESCE(v_prod.category, v_shop_cat);
          IF v_item_gst_rate IS NULL THEN
            v_item_gst_rate := CASE WHEN v_item_is_food THEN 0.05 ELSE 0.18 END;
          END IF;
        END IF;

        -- 100x ADD-ON GST: GST is computed ON TOP of seller base price
        v_item_gst := ROUND((v_item_subtotal * v_item_gst_rate)::numeric, 2);
        IF v_item_is_food THEN
          v_s9_5_gst := v_s9_5_gst + v_item_gst;
        ELSE
          v_non_food_gst := v_non_food_gst + v_item_gst;
        END IF;

        -- Category-specific platform commission lookup
        v_comm_key := 'commission_' || lower(COALESCE(v_prod.category, 'grocery'));
        BEGIN
          SELECT (value#>>'{}')::numeric INTO v_comm_val FROM platform_config WHERE key = v_comm_key;
        EXCEPTION WHEN OTHERS THEN v_comm_val := NULL; END;
        IF v_comm_val IS NOT NULL THEN
          v_item_comm_rate := v_comm_val;
        ELSE
          v_item_comm_rate := 5.0;
        END IF;

        v_item_commission := ROUND((v_item_subtotal * (v_item_comm_rate / 100.0))::numeric, 2);
        v_pure_commission := v_pure_commission + v_item_commission;

        -- Section 52 GST TCS (0.5% strictly on net taxable supplies; 0% on food & exempt 0% goods)
        IF NOT v_item_is_food AND v_item_gst_rate > 0.0 AND lower(COALESCE(v_prod.category, v_shop_cat)) NOT IN ('fruits & vegs', 'butcher', 'fish & seafood') THEN
          v_tcs_amount := v_tcs_amount + ROUND((v_item_subtotal * v_tcs_rate)::numeric, 2);
        END IF;

        -- Section 194-O Income Tax TDS (0.1% on gross base consideration)
        v_tds_amount := v_tds_amount + ROUND((v_item_subtotal * v_tds_rate)::numeric, 2);

        -- Insert into order_items with immutable statutory GST snapshot
        INSERT INTO order_items (
          id, order_id, product_id, product_name, variant_name,
          quantity, price, unit_price, total_price, status, weight_kg,
          gst_rate, gst_amount, created_at
        ) VALUES (
          gen_random_uuid(), v_order_id, (v_item->>'product_id')::uuid,
          v_prod.name, (v_item->>'variant_name'),
          (v_item->>'quantity')::int, v_item_price, v_item_price,
          v_item_subtotal, 'active', v_item_weight_kg,
          v_item_gst_rate, v_item_gst, NOW()
        );

        -- Decrement stock
        IF v_prod.total_quantity IS NOT NULL THEN
          UPDATE products 
          SET total_quantity = total_quantity - (v_item->>'quantity')::int
          WHERE id = v_prod.id;
        END IF;
      END IF;
    END LOOP;

    IF v_expected_total_amount = 0.0 THEN
      RAISE EXCEPTION 'Shop order must contain at least one valid item';
    END IF;

    -- Weight ceiling verification
    v_group_total_weight_kg := v_group_total_weight_kg + v_order_total_weight_kg;
    IF v_group_total_weight_kg > 15.0 THEN
      RAISE EXCEPTION 'PHYSICAL_WEIGHT_LIMIT_EXCEEDED: Total delivery weight % kg exceeds the 15.0 kg two-wheeler limit.', 
        round(v_group_total_weight_kg::numeric, 2);
    END IF;

    -- Subtotal validation (tolerance of 5 paise for rounding)
    IF ABS(v_expected_total_amount - v_client_total_amount) > 0.05 THEN
      RAISE EXCEPTION 'Total amount mismatch for shop %. Expected %, got %',
        (v_order->>'shop_id'), v_expected_total_amount, v_client_total_amount;
    END IF;

    -- ── 100x Grand Total Formula: Base + S9.5 GST + Non-Food GST + Fees ─────
    IF v_is_replacement THEN
      v_expected_grand_total := v_expected_total_amount 
        + v_s9_5_gst 
        + v_non_food_gst
        + COALESCE((v_order->>'delivery_charges')::numeric, 0)
        + COALESCE((v_order->>'platform_fee')::numeric, 0)
        + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0)
        - COALESCE((v_order->>'coupon_discount')::numeric, 0);
    ELSE
      v_expected_grand_total := v_expected_total_amount 
        + v_s9_5_gst 
        + v_non_food_gst
        + COALESCE((v_order->>'delivery_charges')::numeric, 0)
        + COALESCE((v_order->>'platform_fee')::numeric, 0)
        + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0)
        + COALESCE((v_order->>'small_cart_fee')::numeric, 0)
        + COALESCE((v_order->>'heavy_order_fee')::numeric, 0)
        - COALESCE((v_order->>'coupon_discount')::numeric, 0);
    END IF;

    IF ABS(v_expected_grand_total - v_client_grand_total) > 0.05 THEN
      RAISE EXCEPTION 'Grand total mismatch for shop %. Expected %, got %',
        (v_order->>'shop_id'), v_expected_grand_total, v_client_grand_total;
    END IF;

    -- Statutory Deductions & Payouts
    v_server_gst_platform := COALESCE((v_order->>'platform_fee')::numeric, 0) - (COALESCE((v_order->>'platform_fee')::numeric, 0) / (1.0 + v_platform_gst_rate));
    v_server_gst_delivery := COALESCE((v_order->>'delivery_charges')::numeric, 0) - (COALESCE((v_order->>'delivery_charges')::numeric, 0) / (1.0 + v_delivery_gst_rate));
    v_server_rider_earnings := GREATEST(0, (COALESCE((v_order->>'delivery_charges')::numeric, 0) - v_server_gst_delivery - COALESCE((v_order->>'small_cart_fee')::numeric, 0)) * (v_rider_commission_percent / 100.0));
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_pure_commission - v_tcs_amount - v_tds_amount;
    v_gw_deduct := (v_expected_grand_total * 0.02) * (1.0 + 0.18);

    -- Prepare sanitized order record
    v_secure_order := v_order || jsonb_build_object(
      'id', v_order_id,
      'customer_id', v_customer_id,
      'cart_group_id', p_cart_group_id,
      'status', 'awaiting_acceptance',
      'payment_status', 'pending',
      'total_amount', v_expected_total_amount,
      'grand_total', v_expected_grand_total,
      'grand_total_collected', v_expected_grand_total,
      's9_5_gst_amount', v_s9_5_gst,
      'non_food_gst_amount', v_non_food_gst,
      'gst_item_total', (v_s9_5_gst + v_non_food_gst),
      'enything_commission', v_pure_commission,
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'seller_payout', v_server_seller_payout,
      'gst_platform', v_server_gst_platform,
      'gst_delivery', v_server_gst_delivery,
      'rider_earnings', v_server_rider_earnings,
      'gateway_deduction', v_gw_deduct,
      'acceptance_deadline', v_acceptance_deadline,
      'created_at', NOW(),
      'updated_at', NOW()
    );

    IF v_existing_rider_id IS NOT NULL THEN
      v_secure_order := v_secure_order || jsonb_build_object(
        'delivery_partner_id', v_existing_rider_id,
        'rider_phone', v_existing_rider_phone,
        'partner_accepted', v_existing_partner_accepted
      );
    END IF;

    -- Dynamically resolve missing shop coordinates
    IF (v_secure_order->>'shop_lat' IS NULL OR (v_secure_order->>'shop_lat')::numeric = 0.0) THEN
      SELECT ST_Y(location::geometry), ST_X(location::geometry)
      INTO v_shop_lat, v_shop_lng
      FROM shops WHERE id = (v_order->>'shop_id')::uuid;

      IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
        v_secure_order := v_secure_order || jsonb_build_object(
          'shop_lat', v_shop_lat,
          'shop_lng', v_shop_lng
        );
      END IF;
    END IF;

    INSERT INTO orders SELECT * FROM jsonb_populate_record(null::orders, v_secure_order);
    v_inserted_ids := array_append(v_inserted_ids, v_order_id);
  END LOOP;

  -- Cancel Previous Order if Replacement
  IF p_order_id_to_cancel IS NOT NULL THEN
    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'customer_replaced',
        updated_at = NOW()
    WHERE id = p_order_id_to_cancel
      AND customer_id = v_customer_id;
  END IF;

  -- Disarm Rejection Timers and Rebalance Delivery Fees
  IF v_is_replacement THEN
    PERFORM public.acknowledge_partial_rejection(p_cart_group_id, 'replaced');
    PERFORM public.rebalance_active_delivery_fees(p_cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_ids', to_jsonb(v_inserted_ids),
    'cart_group_id', p_cart_group_id,
    'total_weight_kg', v_group_total_weight_kg,
    'is_replacement', v_is_replacement,
    'assigned_rider_id', v_existing_rider_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.place_orders_transaction(jsonb, jsonb, uuid, uuid, text, uuid) TO authenticated, service_role;

-- ── 4. Seller Decline RPC Fortification (decline_order_items_seller) ──────────
CREATE OR REPLACE FUNCTION public.decline_order_items_seller(
  p_order_id UUID,
  p_declined_item_ids UUID[],
  p_reason TEXT,
  p_message TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_shop_cat TEXT;
  v_is_food BOOLEAN;
  v_effective_gst_rate NUMERIC;
  v_comm_rate NUMERIC := 5.0;
  v_comm_key TEXT;
  v_comm_val NUMERIC;
  v_slab_threshold NUMERIC := 2500.0;
  v_slab_high_rate NUMERIC := 0.18;

  v_new_active_subtotal NUMERIC := 0.0;
  v_new_s9_5 NUMERIC := 0.0;
  v_new_non_food_gst NUMERIC := 0.0;
  v_new_gst_item_total NUMERIC := 0.0;
  v_new_enything_commission NUMERIC := 0.0;
  v_new_tcs NUMERIC := 0.0;
  v_new_tds NUMERIC := 0.0;
  v_new_seller_payout NUMERIC := 0.0;

  v_item RECORD;
  v_item_subtotal NUMERIC;
  v_item_gst NUMERIC;
  v_item_comm NUMERIC;
  v_item_tcs NUMERIC;
  v_active_count INT;
  v_declined_prod_ids UUID[];
  v_affected_count INT := 0;
BEGIN
  -- Concurrency Shield: Lock order
  SELECT * INTO v_order
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND');
  END IF;

  IF v_order.status NOT IN ('pending', 'awaiting_acceptance', 'confirmed', 'preparing', 'awaiting_payment') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_ORDER_STATE', 'current_status', v_order.status);
  END IF;

  IF p_declined_item_ids IS NULL OR array_length(p_declined_item_ids, 1) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_ITEMS_SPECIFIED');
  END IF;

  -- Collect product IDs for stock sync
  SELECT array_agg(product_id) INTO v_declined_prod_ids
  FROM order_items
  WHERE id = ANY(p_declined_item_ids) AND order_id = p_order_id AND status = 'active';

  -- Mark declined items
  UPDATE order_items
  SET 
    status = 'declined',
    decline_reason = COALESCE(p_message, p_reason),
    declined_at = NOW()
  WHERE id = ANY(p_declined_item_ids)
    AND order_id = p_order_id
    AND status = 'active';

  GET DIAGNOSTICS v_affected_count = ROW_COUNT;

  -- Stock sync: mark declined items out of stock
  IF v_declined_prod_ids IS NOT NULL AND array_length(v_declined_prod_ids, 1) > 0 THEN
    UPDATE products
    SET 
      is_available = false,
      total_quantity = 0,
      updated_at = NOW()
    WHERE id = ANY(v_declined_prod_ids)
      AND is_deleted = false;
  END IF;

  -- Determine shop category & Section 9(5) food status
  SELECT category INTO v_shop_cat FROM shops WHERE id = v_order.shop_id;
  v_is_food := (lower(COALESCE(v_shop_cat, '')) IN (
    'restaurant', 'food', 'bakery', 'cafe', 'fast_food', 'sweet_shop',
    'sweets & mithai', 'tea & coffee', 'ice cream', 'paan shop'
  ));

  v_comm_key := 'commission_percent_' || COALESCE(v_shop_cat, 'default');
  BEGIN
    SELECT value::numeric INTO v_comm_val FROM platform_config WHERE key = v_comm_key;
    IF v_comm_val IS NOT NULL THEN v_comm_rate := v_comm_val; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_comm_rate := 5.0;
  END;

  -- ── 100x Forensic Recalculation Loop for Surviving Active Items ─────────
  FOR v_item IN
    SELECT oi.price, oi.quantity, oi.product_id, oi.gst_rate AS item_gst_rate,
           p.category AS prod_cat, p.gst_rate_override
    FROM order_items oi
    LEFT JOIN products p ON oi.product_id = p.id
    WHERE oi.order_id = p_order_id AND oi.status = 'active'
  LOOP
    v_item_subtotal := v_item.price * v_item.quantity;
    v_new_active_subtotal := v_new_active_subtotal + v_item_subtotal;

    -- Resolve statutory item GST rate with priority
    IF v_item.item_gst_rate IS NOT NULL THEN
      v_effective_gst_rate := v_item.item_gst_rate;
    ELSIF v_item.gst_rate_override IS NOT NULL THEN
      v_effective_gst_rate := v_item.gst_rate_override;
    ELSIF COALESCE(v_item.prod_cat, v_shop_cat) IN ('Clothing', 'Footwear') THEN
      SELECT COALESCE(slab_threshold, 2500.0), COALESCE(slab_high_rate, 0.18)
      INTO v_slab_threshold, v_slab_high_rate
      FROM tax_config WHERE category = COALESCE(v_item.prod_cat, v_shop_cat);
      IF v_slab_threshold IS NULL THEN v_slab_threshold := 2500.0; END IF;
      IF v_slab_high_rate IS NULL THEN v_slab_high_rate := 0.18; END IF;
      IF v_item.price > v_slab_threshold THEN
        v_effective_gst_rate := v_slab_high_rate;
      ELSE
        v_effective_gst_rate := 0.05;
      END IF;
    ELSE
      SELECT gst_rate INTO v_effective_gst_rate FROM tax_config WHERE category = COALESCE(v_item.prod_cat, v_shop_cat);
      IF v_effective_gst_rate IS NULL THEN
        v_effective_gst_rate := CASE WHEN v_is_food THEN 0.05 ELSE 0.18 END;
      END IF;
    END IF;

    -- Add-On GST math
    v_item_gst := ROUND((v_item_subtotal * v_effective_gst_rate)::numeric, 2);
    IF v_is_food THEN
      v_new_s9_5 := v_new_s9_5 + v_item_gst;
    ELSE
      v_new_non_food_gst := v_new_non_food_gst + v_item_gst;
    END IF;

    v_item_comm := ROUND((v_item_subtotal * (v_comm_rate / 100.0))::numeric, 2);
    v_new_enything_commission := v_new_enything_commission + v_item_comm;

    -- Zero TCS for exempt items or Section 9(5) food
    IF NOT v_is_food AND v_effective_gst_rate > 0.0 AND lower(COALESCE(v_item.prod_cat, v_shop_cat)) NOT IN ('fruits & vegs', 'butcher', 'fish & seafood') THEN
      v_item_tcs := ROUND((v_item_subtotal * 0.005)::numeric, 2);
    ELSE
      v_item_tcs := 0.0;
    END IF;
    v_new_tcs := v_new_tcs + v_item_tcs;
    v_new_tds := v_new_tds + ROUND((v_item_subtotal * 0.001)::numeric, 2);
  END LOOP;

  v_new_gst_item_total := v_new_s9_5 + v_new_non_food_gst;
  v_new_seller_payout := v_new_active_subtotal + v_new_non_food_gst - v_new_enything_commission - v_new_tcs - v_new_tds;

  SELECT COUNT(*) INTO v_active_count FROM order_items WHERE order_id = p_order_id AND status = 'active';

  IF v_active_count = 0 THEN
    -- All items declined -> cancel store's order
    UPDATE orders
    SET 
      status = 'seller_rejected',
      cancelled_reason = 'all_items_declined: ' || COALESCE(p_message, p_reason),
      total_amount = 0,
      grand_total = 0,
      seller_payout = 0,
      updated_at = NOW()
    WHERE id = p_order_id;
  ELSE
    -- Partial rejection: update subtotal, statutory GST, commissions, and payout
    UPDATE orders
    SET 
      total_amount = v_new_active_subtotal,
      s9_5_gst_amount = v_new_s9_5,
      non_food_gst_amount = v_new_non_food_gst,
      gst_item_total = v_new_gst_item_total,
      enything_commission = v_new_enything_commission,
      tcs_amount = v_new_tcs,
      tds_amount = v_new_tds,
      seller_payout = v_new_seller_payout,
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'declined_count', v_affected_count,
    'remaining_active_count', v_active_count,
    'new_subtotal', v_new_active_subtotal,
    'new_gst_item_total', v_new_gst_item_total,
    'new_seller_payout', v_new_seller_payout
  );
END;
$$;

-- ── 5. Customer Swap RPC Fortification (customer_swap_order_item) ─────────────
CREATE OR REPLACE FUNCTION public.customer_swap_order_item(
  p_order_id UUID,
  p_declined_item_id UUID,
  p_replacement_product_id UUID,
  p_quantity INT,
  p_variant_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_old_item RECORD;
  v_prod RECORD;
  v_rep_price NUMERIC;
  v_rep_gst_rate NUMERIC;
  v_slab_threshold NUMERIC := 2500.0;
  v_slab_high_rate NUMERIC := 0.18;

  v_shop_cat TEXT;
  v_is_food BOOLEAN;
  v_comm_rate NUMERIC := 5.0;
  v_comm_key TEXT;
  v_comm_val NUMERIC;

  v_new_active_subtotal NUMERIC := 0.0;
  v_new_s9_5 NUMERIC := 0.0;
  v_new_non_food_gst NUMERIC := 0.0;
  v_new_gst_item_total NUMERIC := 0.0;
  v_new_enything_commission NUMERIC := 0.0;
  v_new_tcs NUMERIC := 0.0;
  v_new_tds NUMERIC := 0.0;
  v_new_seller_payout NUMERIC := 0.0;
  v_authoritative_grand_total NUMERIC := 0.0;
  v_pending_refund NUMERIC := 0.0;

  oi_rec RECORD;
  v_item_subtotal NUMERIC;
  v_effective_gst_rate NUMERIC;
  v_item_gst NUMERIC;
  v_item_comm NUMERIC;
  v_new_item_id UUID := gen_random_uuid();
BEGIN
  -- Concurrency Shield: Lock order
  SELECT * INTO v_order
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND');
  END IF;

  -- Lock old declined item
  SELECT * INTO v_old_item
  FROM order_items
  WHERE id = p_declined_item_id AND order_id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  IF v_old_item.status != 'declined' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_DECLINED');
  END IF;

  -- Lock replacement product (Soft-delete & availability guard)
  SELECT * INTO v_prod
  FROM products
  WHERE id = p_replacement_product_id
    AND shop_id = v_order.shop_id
    AND is_available = true
    AND is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'REPLACEMENT_PRODUCT_UNAVAILABLE');
  END IF;

  IF v_prod.total_quantity IS NOT NULL AND v_prod.total_quantity < p_quantity THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_STOCK', 'available', v_prod.total_quantity);
  END IF;

  -- Resolve variant price
  v_rep_price := v_prod.price;
  IF p_variant_name IS NOT NULL AND v_prod.variants IS NOT NULL THEN
    SELECT (elem->>'price')::numeric INTO v_rep_price
    FROM jsonb_array_elements(v_prod.variants) AS elem
    WHERE elem->>'name' = p_variant_name;

    IF v_rep_price IS NULL OR v_rep_price <= 0 THEN
      v_rep_price := v_prod.price;
    END IF;
  END IF;

  -- Determine shop category & Section 9(5) food status
  SELECT category INTO v_shop_cat FROM shops WHERE id = v_order.shop_id;
  v_is_food := (lower(COALESCE(v_shop_cat, '')) IN (
    'restaurant', 'food', 'bakery', 'cafe', 'fast_food', 'sweet_shop',
    'sweets & mithai', 'tea & coffee', 'ice cream', 'paan shop'
  ));

  -- Resolve replacement product GST rate
  IF v_prod.gst_rate_override IS NOT NULL THEN
    v_rep_gst_rate := v_prod.gst_rate_override;
  ELSIF COALESCE(v_prod.category, v_shop_cat) IN ('Clothing', 'Footwear') THEN
    SELECT COALESCE(slab_threshold, 2500.0), COALESCE(slab_high_rate, 0.18)
    INTO v_slab_threshold, v_slab_high_rate
    FROM tax_config WHERE category = COALESCE(v_prod.category, v_shop_cat);
    IF v_slab_threshold IS NULL THEN v_slab_threshold := 2500.0; END IF;
    IF v_slab_high_rate IS NULL THEN v_slab_high_rate := 0.18; END IF;
    IF v_rep_price > v_slab_threshold THEN
      v_rep_gst_rate := v_slab_high_rate;
    ELSE
      v_rep_gst_rate := 0.05;
    END IF;
  ELSE
    SELECT gst_rate INTO v_rep_gst_rate FROM tax_config WHERE category = COALESCE(v_prod.category, v_shop_cat);
    IF v_rep_gst_rate IS NULL THEN
      v_rep_gst_rate := CASE WHEN v_is_food THEN 0.05 ELSE 0.18 END;
    END IF;
  END IF;

  -- Mark old item swapped
  UPDATE order_items
  SET status = 'swapped',
      swapped_at = NOW(),
      replacement_item_id = v_new_item_id
  WHERE id = p_declined_item_id;

  -- Insert new active replacement item
  INSERT INTO order_items (
    id, order_id, product_id, product_name, variant_name,
    quantity, price, unit_price, total_price, status, weight_kg,
    gst_rate, gst_amount, created_at
  ) VALUES (
    v_new_item_id, p_order_id, p_replacement_product_id,
    v_prod.name, p_variant_name,
    p_quantity, v_rep_price, v_rep_price,
    (v_rep_price * p_quantity), 'active', COALESCE(v_prod.weight_per_unit, 0.5),
    v_rep_gst_rate, ROUND(((v_rep_price * p_quantity) * v_rep_gst_rate)::numeric, 2), NOW()
  );

  -- Decrement stock if managed
  IF v_prod.total_quantity IS NOT NULL THEN
    UPDATE products 
    SET total_quantity = GREATEST(0, total_quantity - p_quantity),
        is_available = CASE WHEN total_quantity - p_quantity <= 0 THEN false ELSE is_available END,
        updated_at = NOW()
    WHERE id = p_replacement_product_id
      AND is_deleted = false;
  END IF;

  -- Commission config lookup
  v_comm_key := 'commission_percent_' || COALESCE(v_shop_cat, 'default');
  BEGIN
    SELECT value::numeric INTO v_comm_val FROM platform_config WHERE key = v_comm_key;
    IF v_comm_val IS NOT NULL THEN v_comm_rate := v_comm_val; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_comm_rate := 5.0;
  END;

  -- ── 100x Forensic Recalculation Loop for Surviving Active Items ─────────
  v_new_active_subtotal := 0.0;
  FOR oi_rec IN
    SELECT oi.price, oi.quantity, oi.product_id, oi.gst_rate AS item_gst_rate,
           p.category AS prod_cat, p.gst_rate_override
    FROM order_items oi
    LEFT JOIN products p ON oi.product_id = p.id
    WHERE oi.order_id = p_order_id AND oi.status = 'active'
  LOOP
    v_item_subtotal := oi_rec.price * oi_rec.quantity;
    v_new_active_subtotal := v_new_active_subtotal + v_item_subtotal;

    -- Resolve statutory item GST rate with priority
    IF oi_rec.item_gst_rate IS NOT NULL THEN
      v_effective_gst_rate := oi_rec.item_gst_rate;
    ELSIF oi_rec.gst_rate_override IS NOT NULL THEN
      v_effective_gst_rate := oi_rec.gst_rate_override;
    ELSIF COALESCE(oi_rec.prod_cat, v_shop_cat) IN ('Clothing', 'Footwear') THEN
      SELECT COALESCE(slab_threshold, 2500.0), COALESCE(slab_high_rate, 0.18)
      INTO v_slab_threshold, v_slab_high_rate
      FROM tax_config WHERE category = COALESCE(oi_rec.prod_cat, v_shop_cat);
      IF v_slab_threshold IS NULL THEN v_slab_threshold := 2500.0; END IF;
      IF v_slab_high_rate IS NULL THEN v_slab_high_rate := 0.18; END IF;
      IF oi_rec.price > v_slab_threshold THEN
        v_effective_gst_rate := v_slab_high_rate;
      ELSE
        v_effective_gst_rate := 0.05;
      END IF;
    ELSE
      SELECT gst_rate INTO v_effective_gst_rate FROM tax_config WHERE category = COALESCE(oi_rec.prod_cat, v_shop_cat);
      IF v_effective_gst_rate IS NULL THEN
        v_effective_gst_rate := CASE WHEN v_is_food THEN 0.05 ELSE 0.18 END;
      END IF;
    END IF;

    -- Add-On GST math
    v_item_gst := ROUND((v_item_subtotal * v_effective_gst_rate)::numeric, 2);
    IF v_is_food THEN
      v_new_s9_5 := v_new_s9_5 + v_item_gst;
    ELSE
      v_new_non_food_gst := v_new_non_food_gst + v_item_gst;
    END IF;

    v_item_comm := ROUND((v_item_subtotal * (v_comm_rate / 100.0))::numeric, 2);
    v_new_enything_commission := v_new_enything_commission + v_item_comm;

    -- Zero TCS for exempt goods and Section 9(5) food
    IF NOT v_is_food AND v_effective_gst_rate > 0.0 AND lower(COALESCE(oi_rec.prod_cat, v_shop_cat)) NOT IN ('fruits & vegs', 'butcher', 'fish & seafood') THEN
      v_new_tcs := v_new_tcs + ROUND((v_item_subtotal * 0.005)::numeric, 2);
    END IF;
    v_new_tds := v_new_tds + ROUND((v_item_subtotal * 0.001)::numeric, 2);
  END LOOP;

  v_new_gst_item_total := v_new_s9_5 + v_new_non_food_gst;
  v_new_seller_payout := v_new_active_subtotal + v_new_non_food_gst - v_new_enything_commission - v_new_tcs - v_new_tds;

  -- Authoritative Grand Total Calculation
  v_authoritative_grand_total := GREATEST(0,
    v_new_active_subtotal
    + v_new_gst_item_total
    + COALESCE(v_order.platform_fee, 0)
    + COALESCE(v_order.delivery_charges, 0)
    - LEAST(COALESCE(v_order.coupon_discount, 0), v_new_active_subtotal)
  );

  IF v_order.payment_status = 'captured' THEN
    v_pending_refund := GREATEST(0.0, 
      (COALESCE(v_order.grand_total_collected, 0) - v_authoritative_grand_total) 
      - COALESCE(v_order.total_refunded, 0)
    );
  ELSE
    v_pending_refund := 0.0;
  END IF;

  UPDATE orders
  SET 
    total_amount = v_new_active_subtotal,
    s9_5_gst_amount = v_new_s9_5,
    non_food_gst_amount = v_new_non_food_gst,
    gst_item_total = v_new_gst_item_total,
    enything_commission = v_new_enything_commission,
    tcs_amount = v_new_tcs,
    tds_amount = v_new_tds,
    seller_payout = v_new_seller_payout,
    grand_total = v_authoritative_grand_total,
    pending_refund = v_pending_refund,
    updated_at = NOW()
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'replacement_item_id', v_new_item_id,
    'new_subtotal', v_new_active_subtotal,
    'new_gst_item_total', v_new_gst_item_total,
    'new_seller_payout', v_new_seller_payout,
    'authoritative_grand_total', v_authoritative_grand_total,
    'pending_refund', v_pending_refund
  );
END;
$$;

-- ── 6. Delivery Rebalance Typo Fix (rebalance_active_delivery_fees) ───────────
CREATE OR REPLACE FUNCTION public.rebalance_active_delivery_fees(p_cart_group_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order_count int;
    v_distinct_shop_count int;
    v_delivery_base_fee numeric := 20.0;
    v_admin_delivery_base numeric := 20.0;
    v_delivery_rate_per_km numeric := 20.0;
    v_admin_platform_fee numeric := 2.0;
    v_platform_gst_rate numeric := 0.18;
    v_delivery_gst_rate numeric := 0.18;
    v_rider_commission_percent numeric := 80.0;
    v_small_cart_threshold numeric := 99.0;
    v_small_cart_fee_val numeric := 15.0;
    v_heavy_order_threshold_kg numeric := 10.0;
    v_heavy_order_fee_val numeric := 20.0;

    v_active_cart_group_total numeric := 0.0;
    v_active_cart_group_weight numeric := 0.0;
    v_anchor_order_id uuid;
    v_order record;
    v_actual_leg_distance numeric;
    v_leg_distance_surcharge numeric;
    v_order_delivery_pre_gst numeric;
    v_order_delivery_post_gst numeric;
    v_order_multi_shop_surcharge numeric;
    v_order_small_cart_fee numeric;
    v_order_heavy_fee numeric;
    v_server_gst_delivery numeric;
    v_server_rider_earnings numeric;
    v_authoritative_grand_total numeric;
    v_pending_refund numeric;
    v_order_index int := 0;
BEGIN
    SELECT count(*), count(distinct shop_id)
    INTO v_order_count, v_distinct_shop_count
    FROM public.orders
    WHERE cart_group_id = p_cart_group_id
      AND status NOT IN (
          'cancelled', 'seller_rejected', 'partner_rejected',
          'shop_dispute_cancel', 'timeout', 'failed', 'returned',
          'refunded', 'verification_failed', 'no_rider'
      );

    IF v_order_count = 0 THEN
        RETURN jsonb_build_object('success', true, 'rebalanced_orders', 0, 'message', 'No active orders in cart group');
    END IF;

    -- Platform Configurations with robust key lookup
    BEGIN
        SELECT (value#>>'{}')::numeric INTO v_admin_delivery_base FROM public.platform_config WHERE key = 'delivery_base_fee';
        IF v_admin_delivery_base IS NULL THEN v_admin_delivery_base := 20.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_delivery_rate_per_km FROM public.platform_config WHERE key = 'delivery_rate_per_km';
        IF v_delivery_rate_per_km IS NULL THEN v_delivery_rate_per_km := 20.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_admin_platform_fee FROM public.platform_config WHERE key = 'platform_fee';
        IF v_admin_platform_fee IS NULL THEN v_admin_platform_fee := 2.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM public.platform_config WHERE key = 'platform_fee_gst_rate' OR key = 'platform_gst_rate' LIMIT 1;
        IF v_platform_gst_rate IS NULL THEN v_platform_gst_rate := 0.18; END IF;
        SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM public.platform_config WHERE key = 'delivery_gst_rate';
        IF v_delivery_gst_rate IS NULL THEN v_delivery_gst_rate := 0.18; END IF;
        SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM public.platform_config WHERE key = 'rider_commission_percent';
        IF v_rider_commission_percent IS NULL THEN v_rider_commission_percent := 80.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_small_cart_threshold FROM public.platform_config WHERE key = 'small_cart_threshold';
        IF v_small_cart_threshold IS NULL THEN v_small_cart_threshold := 99.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_small_cart_fee_val FROM public.platform_config WHERE key = 'small_cart_fee';
        IF v_small_cart_fee_val IS NULL THEN v_small_cart_fee_val := 15.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_heavy_order_threshold_kg FROM public.platform_config WHERE key = 'heavy_order_threshold_kg';
        IF v_heavy_order_threshold_kg IS NULL THEN v_heavy_order_threshold_kg := 10.0; END IF;
        SELECT (value#>>'{}')::numeric INTO v_heavy_order_fee_val FROM public.platform_config WHERE key = 'heavy_order_fee';
        IF v_heavy_order_fee_val IS NULL THEN v_heavy_order_fee_val := 20.0; END IF;
    EXCEPTION WHEN OTHERS THEN
        v_admin_delivery_base := 20.0;
        v_delivery_rate_per_km := 20.0;
        v_admin_platform_fee := 2.0;
        v_platform_gst_rate := 0.18;
        v_delivery_gst_rate := 0.18;
        v_rider_commission_percent := 80.0;
        v_small_cart_threshold := 99.0;
        v_small_cart_fee_val := 15.0;
        v_heavy_order_threshold_kg := 10.0;
        v_heavy_order_fee_val := 20.0;
    END;

    -- Tally cart group subtotal and weight
    SELECT COALESCE(SUM(total_amount), 0.0)
    INTO v_active_cart_group_total
    FROM public.orders
    WHERE cart_group_id = p_cart_group_id
      AND status NOT IN (
          'cancelled', 'seller_rejected', 'partner_rejected',
          'shop_dispute_cancel', 'timeout', 'failed', 'returned',
          'refunded', 'verification_failed', 'no_rider'
      );

    SELECT COALESCE(SUM(oi.weight_kg * oi.quantity), 0.0)
    INTO v_active_cart_group_weight
    FROM public.order_items oi
    JOIN public.orders o ON oi.order_id = o.id
    WHERE o.cart_group_id = p_cart_group_id
      AND o.status NOT IN (
          'cancelled', 'seller_rejected', 'partner_rejected',
          'shop_dispute_cancel', 'timeout', 'failed', 'returned',
          'refunded', 'verification_failed', 'no_rider'
      )
      AND oi.status = 'active';

    -- Identify anchor order
    SELECT id INTO v_anchor_order_id
    FROM public.orders
    WHERE cart_group_id = p_cart_group_id
      AND status NOT IN (
          'cancelled', 'seller_rejected', 'partner_rejected',
          'shop_dispute_cancel', 'timeout', 'failed', 'returned',
          'refunded', 'verification_failed', 'no_rider'
      )
    ORDER BY created_at ASC
    LIMIT 1;

    -- Rebalance each surviving order
    FOR v_order IN
        SELECT id, shop_id, customer_id, total_amount, payment_status,
               grand_total_collected, total_refunded, estimated_distance_km,
               coupon_discount, s9_5_gst_amount, non_food_gst_amount, gst_item_total,
               platform_fee, small_cart_fee, heavy_order_fee, multi_shop_surcharge
        FROM public.orders
        WHERE cart_group_id = p_cart_group_id
          AND status NOT IN (
              'cancelled', 'seller_rejected', 'partner_rejected',
              'shop_dispute_cancel', 'timeout', 'failed', 'returned',
              'refunded', 'verification_failed', 'no_rider'
          )
        ORDER BY created_at ASC
    LOOP
        v_order_index := v_order_index + 1;
        v_actual_leg_distance := COALESCE(v_order.estimated_distance_km, 1.0);
        v_leg_distance_surcharge := GREATEST(0.0, (v_actual_leg_distance - 1.0) * v_delivery_rate_per_km);

        IF v_order.id = v_anchor_order_id THEN
            v_delivery_base_fee := v_admin_delivery_base;
            v_order_multi_shop_surcharge := 0.0;
            v_order_small_cart_fee := CASE WHEN v_active_cart_group_total < v_small_cart_threshold THEN v_small_cart_fee_val ELSE 0.0 END;
            v_order_heavy_fee := CASE WHEN v_active_cart_group_weight > v_heavy_order_threshold_kg THEN v_heavy_order_fee_val ELSE 0.0 END;
        ELSE
            v_delivery_base_fee := 0.0;
            v_order_multi_shop_surcharge := 20.0;
            v_order_small_cart_fee := 0.0;
            v_order_heavy_fee := 0.0;
        END IF;

        v_order_delivery_pre_gst := v_delivery_base_fee + v_leg_distance_surcharge + v_order_multi_shop_surcharge + v_order_small_cart_fee + v_order_heavy_fee;
        v_order_delivery_post_gst := ROUND((v_order_delivery_pre_gst * (1.0 + v_delivery_gst_rate))::numeric, 2);

        v_server_gst_delivery := v_order_delivery_post_gst - (v_order_delivery_post_gst / (1.0 + v_delivery_gst_rate));
        v_server_rider_earnings := GREATEST(0.0, (v_order_delivery_post_gst - v_server_gst_delivery - v_order_small_cart_fee) * (v_rider_commission_percent / 100.0));

        v_authoritative_grand_total := GREATEST(0.0,
            v_order.total_amount
            + COALESCE(v_order.gst_item_total, (COALESCE(v_order.s9_5_gst_amount, 0) + COALESCE(v_order.non_food_gst_amount, 0)))
            + v_order_delivery_post_gst
            + COALESCE(v_order.platform_fee, v_admin_platform_fee)
            - LEAST(COALESCE(v_order.coupon_discount, 0), v_order.total_amount)
        );

        IF v_order.payment_status = 'captured' THEN
            v_pending_refund := GREATEST(0.0, (COALESCE(v_order.grand_total_collected, 0) - v_authoritative_grand_total) - COALESCE(v_order.total_refunded, 0));
        ELSE
            v_pending_refund := 0.0;
        END IF;

        UPDATE public.orders
        SET delivery_charges = v_order_delivery_post_gst,
            multi_shop_surcharge = v_order_multi_shop_surcharge,
            small_cart_fee = v_order_small_cart_fee,
            heavy_order_fee = v_order_heavy_fee,
            gst_delivery = v_server_gst_delivery,
            rider_earnings = v_server_rider_earnings,
            grand_total = v_authoritative_grand_total,
            pending_refund = v_pending_refund,
            updated_at = NOW()
        WHERE id = v_order.id;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'rebalanced_orders', v_order_count, 'anchor_order_id', v_anchor_order_id);
END;
$$;

