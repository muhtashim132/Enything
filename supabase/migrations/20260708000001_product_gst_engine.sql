-- ============================================================================
-- Migration: 20260708000001_product_gst_engine.sql
-- Description: Product-Level GST Engine — Purely Additive
--
-- ADDS (no existing SQL altered, no columns dropped, no RLS changed):
--
--  1. public.product_gst_overrides table
--       Stores keyword → GST rate rules, seeded with 250+ India 2026 rules.
--       Admin can add/edit/delete from Admin → Tax Settings panel.
--       Sellers benefit automatically when adding products by name.
--
--  2. products.gst_rate_override NUMERIC(5,4) column (nullable)
--       If NOT NULL → this product uses this GST rate instead of the category rate.
--       If NULL → existing category-level rate logic applies (unchanged).
--
--  3. Full RLS: admins can manage keyword rules; authenticated users can read.
--
--  4. GRANT statements to prevent PostgREST "permission denied" errors.
--
-- SAFETY GUARANTEES:
--   * CREATE TABLE IF NOT EXISTS — fully idempotent.
--   * ALTER TABLE ADD COLUMN IF NOT EXISTS — fully idempotent.
--   * ON CONFLICT DO UPDATE — safe upsert for seed data.
--   * No existing column altered or dropped.
--   * No existing RLS policy modified.
--   * No existing function or trigger changed.
-- ============================================================================

-- ============================================================================
-- 1. CREATE product_gst_overrides TABLE
-- ============================================================================
-- Stores keyword-to-GST-rate mappings.
-- `keyword` is a lowercase word/phrase that, if found in the product name,
-- triggers a specific GST rate recommendation.
-- `category_hint` is optional — if set, the rule only fires when the product
-- is in that category (prevents "flowers" matching "flower vase" in Home Decor).

CREATE TABLE IF NOT EXISTS public.product_gst_overrides (
  id            uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  keyword       text          NOT NULL,             -- lowercase, matched case-insensitively
  category_hint text,                               -- NULL = match in any category
  gst_rate      numeric(5,4)  NOT NULL,             -- e.g. 0.4000 = 40%
  reason        text          NOT NULL DEFAULT '',  -- human-readable label shown to seller
  is_active     boolean       NOT NULL DEFAULT true,
  created_by    uuid          REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by    uuid          REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    timestamptz   NOT NULL DEFAULT now(),
  updated_at    timestamptz   NOT NULL DEFAULT now()
);

-- Unique keyword + category_hint pair
CREATE UNIQUE INDEX IF NOT EXISTS product_gst_overrides_keyword_cat_idx
  ON public.product_gst_overrides (keyword, COALESCE(category_hint, ''));

-- ============================================================================
-- 2. SEED product_gst_overrides WITH 2026 GST RATES
-- ============================================================================
-- Sources:
--  * CBIC Notification 9/2025-Central Tax Rate (Sep 22, 2025 — GST 2.0)
--  * Union Budget 2026 (Feb 1, 2026) — tobacco flat 40% + cess abolition
--  * GST Council decisions through June 2026
--
-- Active slabs as of July 2026: 0%, 5%, 18%, 40%
-- (12% and 28% removed for most goods under GST 2.0)
-- ============================================================================

INSERT INTO public.product_gst_overrides
  (keyword, category_hint, gst_rate, reason)
VALUES

  -- ══════════════════════════════════════════════════════════════════
  -- TOBACCO & SIN GOODS — 40% (Budget 2026; flat rate, cess abolished)
  -- ══════════════════════════════════════════════════════════════════
  ('cigarette',       NULL,                  0.4000, 'Tobacco Products — 40% (Budget 2026)'),
  ('cigarettes',      NULL,                  0.4000, 'Tobacco Products — 40% (Budget 2026)'),
  ('marlboro',        NULL,                  0.4000, 'Cigarettes — 40% (Budget 2026)'),
  ('classic milds',   NULL,                  0.4000, 'Cigarettes — 40% (Budget 2026)'),
  ('gold flake',      NULL,                  0.4000, 'Cigarettes — 40% (Budget 2026)'),
  ('wills navy',      NULL,                  0.4000, 'Cigarettes — 40% (Budget 2026)'),
  ('four square',     NULL,                  0.4000, 'Cigarettes — 40% (Budget 2026)'),
  ('berkeley',        NULL,                  0.4000, 'Cigarettes — 40% (Budget 2026)'),
  ('dunhill',         NULL,                  0.4000, 'Cigarettes — 40% (Budget 2026)'),
  ('red & white',     NULL,                  0.4000, 'Cigarettes — 40% (Budget 2026)'),
  ('capstan',         NULL,                  0.4000, 'Cigarettes — 40% (Budget 2026)'),
  ('bristol',         NULL,                  0.4000, 'Cigarettes — 40% (Budget 2026)'),
  ('cigar',           NULL,                  0.4000, 'Cigars — 40% (Budget 2026)'),
  ('cheroot',         NULL,                  0.4000, 'Cheroots — 40% (Budget 2026)'),
  ('bidi',            NULL,                  0.4000, 'Bidis — 40% (Budget 2026)'),
  ('tobacco',         NULL,                  0.4000, 'Tobacco — 40% (Budget 2026)'),
  ('gutka',           NULL,                  0.4000, 'Gutka — 40% (Budget 2026)'),
  ('pan masala',      NULL,                  0.4000, 'Pan Masala — 40% (Budget 2026)'),
  ('khaini',          NULL,                  0.4000, 'Tobacco Products — 40% (Budget 2026)'),
  ('zarda',           NULL,                  0.4000, 'Zarda — 40% (Budget 2026)'),
  ('hookah',          NULL,                  0.4000, 'Hookah Tobacco — 40% (Budget 2026)'),
  ('shisha',          NULL,                  0.4000, 'Shisha — 40% (Budget 2026)'),
  ('snuff',           NULL,                  0.4000, 'Tobacco Snuff — 40% (Budget 2026)'),
  ('aerated drink',   'Beverages',           0.4000, 'Aerated Drinks — 40% (Sin Goods)'),
  ('carbonated',      'Beverages',           0.4000, 'Carbonated Drinks — 40%'),
  ('cola',            'Beverages',           0.4000, 'Cola Drinks — 40%'),
  ('energy drink',    'Beverages',           0.4000, 'Energy Drinks — 40%'),
  ('red bull',        'Beverages',           0.4000, 'Energy Drinks — 40%'),
  ('monster energy',  'Beverages',           0.4000, 'Energy Drinks — 40%'),
  ('thums up',        'Beverages',           0.4000, 'Aerated Drink — 40%'),
  ('pepsi',           'Beverages',           0.4000, 'Aerated Drink — 40%'),
  ('sprite',          'Beverages',           0.4000, 'Aerated Drink — 40%'),
  ('fanta',           'Beverages',           0.4000, 'Aerated Drink — 40%'),
  ('limca',           'Beverages',           0.4000, 'Aerated Drink — 40%'),
  ('7up',             'Beverages',           0.4000, 'Aerated Drink — 40%'),
  ('mountain dew',    'Beverages',           0.4000, 'Aerated Drink — 40%'),
  ('coca cola',       'Beverages',           0.4000, 'Aerated Drink — 40%'),

  -- ══════════════════════════════════════════════════════════════════
  -- SHAMPOO & HAIR CARE — 5% (GST 2.0 FMCG merit rate; was 18%)
  -- HSN Chapter 33 — hair preparations
  -- ══════════════════════════════════════════════════════════════════
  ('shampoo',                  NULL,          0.0500, 'Shampoo — 5% FMCG Merit Rate (GST 2.0)'),
  ('head and shoulders',       NULL,          0.0500, 'Shampoo — 5% FMCG Merit Rate'),
  ('head & shoulders',         NULL,          0.0500, 'Shampoo — 5% FMCG Merit Rate'),
  ('pantene',                  NULL,          0.0500, 'Hair Care — 5% FMCG Merit Rate'),
  ('dove shampoo',             NULL,          0.0500, 'Shampoo — 5% FMCG Merit Rate'),
  ('sunsilk',                  NULL,          0.0500, 'Shampoo — 5% FMCG Merit Rate'),
  ('tresemme',                 NULL,          0.0500, 'Shampoo — 5% FMCG Merit Rate'),
  ('clinic plus',              NULL,          0.0500, 'Shampoo — 5% FMCG Merit Rate'),
  ('clear shampoo',            NULL,          0.0500, 'Shampoo — 5% FMCG Merit Rate'),
  ('kerastase',                NULL,          0.0500, 'Premium Shampoo — 5% Merit Rate'),
  ('hair oil',                 NULL,          0.0500, 'Hair Oil — 5% FMCG Merit Rate'),
  ('coconut oil',              NULL,          0.0500, 'Hair/Cooking Oil — 5%'),
  ('parachute',                NULL,          0.0500, 'Hair Oil — 5% FMCG Merit Rate'),
  ('dabur amla',               NULL,          0.0500, 'Hair Oil — 5% FMCG Merit Rate'),
  ('vatika',                   NULL,          0.0500, 'Hair Oil — 5% FMCG Merit Rate'),
  ('bajaj almond',             NULL,          0.0500, 'Hair Oil — 5% FMCG Merit Rate'),
  ('hair conditioner',         NULL,          0.0500, 'Hair Conditioner — 5% Merit Rate'),
  ('conditioner',              NULL,          0.0500, 'Hair Conditioner — 5% Merit Rate'),
  ('hair serum',               NULL,          0.0500, 'Hair Serum — 5% Merit Rate'),
  ('hair mask',                NULL,          0.0500, 'Hair Mask — 5% Merit Rate'),
  ('hair cream',               NULL,          0.0500, 'Hair Cream — 5% Merit Rate'),
  ('hair colour',              NULL,          0.0500, 'Hair Colour — 5% Merit Rate'),
  ('hair color',               NULL,          0.0500, 'Hair Colour — 5% Merit Rate'),
  ('hair dye',                 NULL,          0.0500, 'Hair Dye — 5% Merit Rate'),
  ('mehendi',                  NULL,          0.0500, 'Mehendi/Henna — 5%'),
  ('henna',                    NULL,          0.0500, 'Henna — 5%'),
  ('toothpaste',               NULL,          0.0500, 'Toothpaste — 5% FMCG Merit Rate'),
  ('colgate',                  NULL,          0.0500, 'Toothpaste — 5% FMCG Merit Rate'),
  ('pepsodent',                NULL,          0.0500, 'Toothpaste — 5% FMCG Merit Rate'),
  ('oral b',                   NULL,          0.0500, 'Toothpaste — 5% FMCG Merit Rate'),
  ('sensodyne',                NULL,          0.0500, 'Toothpaste — 5% FMCG Merit Rate'),
  ('toothbrush',               NULL,          0.0500, 'Toothbrush — 5% FMCG Merit Rate'),
  ('dental floss',             NULL,          0.0500, 'Dental Floss — 5%'),
  ('mouthwash',                NULL,          0.0500, 'Mouthwash — 5%'),
  ('listerine',                NULL,          0.0500, 'Mouthwash — 5%'),
  ('soap',                     NULL,          0.0500, 'Soap — 5% FMCG Merit Rate'),
  ('bathing soap',             NULL,          0.0500, 'Soap — 5% FMCG Merit Rate'),
  ('lux',                      NULL,          0.0500, 'Soap — 5% FMCG Merit Rate'),
  ('lifebuoy',                 NULL,          0.0500, 'Soap — 5% FMCG Merit Rate'),
  ('dettol soap',              NULL,          0.0500, 'Soap — 5% FMCG Merit Rate'),
  ('dove soap',                NULL,          0.0500, 'Soap — 5% FMCG Merit Rate'),
  ('pears soap',               NULL,          0.0500, 'Soap — 5% FMCG Merit Rate'),
  ('body wash',                NULL,          0.0500, 'Body Wash — 5% Merit Rate'),
  ('face wash',                NULL,          0.0500, 'Face Wash — 5% Merit Rate'),
  ('hand wash',                NULL,          0.0500, 'Hand Wash — 5% Merit Rate'),
  ('dettol handwash',          NULL,          0.0500, 'Hand Wash — 5% Merit Rate'),
  ('savlon handwash',          NULL,          0.0500, 'Hand Wash — 5% Merit Rate'),
  ('sanitizer',                NULL,          0.0500, 'Sanitizer — 5% Merit Rate'),
  ('hand sanitizer',           NULL,          0.0500, 'Hand Sanitizer — 5%'),
  ('moisturiser',              NULL,          0.0500, 'Moisturiser — 5% Merit Rate'),
  ('moisturizer',              NULL,          0.0500, 'Moisturiser — 5% Merit Rate'),
  ('fairness cream',           NULL,          0.0500, 'Skin Cream — 5% Merit Rate'),
  ('sunscreen',                NULL,          0.0500, 'Sunscreen — 5% Merit Rate'),
  ('cold cream',               NULL,          0.0500, 'Cold Cream — 5% Merit Rate'),
  ('vaseline',                 NULL,          0.0500, 'Skin Care — 5% Merit Rate'),
  ('petroleum jelly',          NULL,          0.0500, 'Petroleum Jelly — 5%'),
  ('talcum powder',            NULL,          0.0500, 'Talcum Powder — 5% Merit Rate'),
  ('baby powder',              NULL,          0.0500, 'Baby Powder — 5%'),
  ('johnson baby',             NULL,          0.0500, 'Baby Product — 5%'),
  ('deodorant',                NULL,          0.0500, 'Deodorant — 5% Merit Rate'),
  ('deo spray',                NULL,          0.0500, 'Deodorant — 5% Merit Rate'),
  ('axe',                      NULL,          0.0500, 'Deodorant — 5% Merit Rate'),
  ('nivea deo',                NULL,          0.0500, 'Deodorant — 5% Merit Rate'),
  ('fogg',                     NULL,          0.0500, 'Deodorant — 5% Merit Rate'),
  ('shaving cream',            NULL,          0.0500, 'Shaving Cream — 5% Merit Rate'),
  ('shaving gel',              NULL,          0.0500, 'Shaving Gel — 5% Merit Rate'),
  ('aftershave',               NULL,          0.0500, 'Aftershave — 5% Merit Rate'),
  ('gillette foam',            NULL,          0.0500, 'Shaving Foam — 5%'),
  ('razor',                    NULL,          0.0500, 'Razor — 5% Merit Rate'),
  ('gillette',                 NULL,          0.0500, 'Razor/Shaving — 5% Merit Rate'),
  ('veet',                     NULL,          0.0500, 'Hair Removal Cream — 5%'),
  ('hair removal',             NULL,          0.0500, 'Hair Removal — 5%'),
  ('cotton buds',              NULL,          0.0500, 'Cotton Buds — 5%'),
  ('cotton balls',             NULL,          0.0500, 'Cotton Balls — 5%'),
  ('baby wipes',               NULL,          0.0500, 'Baby Wipes — 5%'),
  ('wet wipes',                NULL,          0.0500, 'Wet Wipes — 5%'),
  ('sanitary pad',             NULL,          0.0500, 'Sanitary Napkins — 5%'),
  ('sanitary napkin',          NULL,          0.0500, 'Sanitary Napkins — 5%'),
  ('whisper',                  NULL,          0.0500, 'Sanitary Napkins — 5%'),
  ('stayfree',                 NULL,          0.0500, 'Sanitary Napkins — 5%'),
  ('sofy',                     NULL,          0.0500, 'Sanitary Napkins — 5%'),
  ('diaper',                   NULL,          0.0500, 'Diapers — 5%'),
  ('pampers',                  NULL,          0.0500, 'Diapers — 5%'),
  ('huggies',                  NULL,          0.0500, 'Diapers — 5%'),

  -- ══════════════════════════════════════════════════════════════════
  -- COSMETICS / MAKEUP — 18% (Standard slab; HSN Chapter 33)
  -- ══════════════════════════════════════════════════════════════════
  ('lipstick',                 NULL,          0.1800, 'Lipstick — 18% Standard Rate'),
  ('lip gloss',                NULL,          0.1800, 'Lip Gloss — 18%'),
  ('foundation',               NULL,          0.1800, 'Foundation — 18%'),
  ('compact powder',           NULL,          0.1800, 'Compact Powder — 18%'),
  ('kajal',                    NULL,          0.1800, 'Kajal/Kohl — 18%'),
  ('eyeliner',                 NULL,          0.1800, 'Eyeliner — 18%'),
  ('mascara',                  NULL,          0.1800, 'Mascara — 18%'),
  ('eyeshadow',                NULL,          0.1800, 'Eye Shadow — 18%'),
  ('blush',                    NULL,          0.1800, 'Blush — 18%'),
  ('concealer',                NULL,          0.1800, 'Concealer — 18%'),
  ('highlighter',              NULL,          0.1800, 'Highlighter — 18%'),
  ('contour',                  NULL,          0.1800, 'Contour — 18%'),
  ('primer',                   NULL,          0.1800, 'Makeup Primer — 18%'),
  ('bb cream',                 NULL,          0.1800, 'BB Cream — 18%'),
  ('cc cream',                 NULL,          0.1800, 'CC Cream — 18%'),
  ('setting spray',            NULL,          0.1800, 'Setting Spray — 18%'),
  ('nail polish',              NULL,          0.1800, 'Nail Polish — 18%'),
  ('nail paint',               NULL,          0.1800, 'Nail Paint — 18%'),
  ('nail remover',             NULL,          0.1800, 'Nail Remover — 18%'),
  ('nail art',                 NULL,          0.1800, 'Nail Art — 18%'),
  ('perfume',                  NULL,          0.1800, 'Perfume — 18%'),
  ('cologne',                  NULL,          0.1800, 'Cologne — 18%'),
  ('eau de parfum',            NULL,          0.1800, 'Perfume — 18%'),
  ('body spray',               NULL,          0.1800, 'Body Spray — 18%'),
  ('attar',                    NULL,          0.1800, 'Attar/Ittar — 18%'),
  ('ittar',                    NULL,          0.1800, 'Attar/Ittar — 18%'),
  ('face pack',                NULL,          0.1800, 'Face Pack — 18%'),
  ('face mask',                NULL,          0.1800, 'Face Mask — 18%'),
  ('scrub',                    NULL,          0.1800, 'Skin Scrub — 18%'),
  ('peel off',                 NULL,          0.1800, 'Peel-off Mask — 18%'),
  ('toner',                    NULL,          0.1800, 'Face Toner — 18%'),
  ('serum',                    NULL,          0.1800, 'Face Serum — 18%'),
  ('eye cream',                NULL,          0.1800, 'Eye Cream — 18%'),
  ('retinol',                  NULL,          0.1800, 'Retinol Serum — 18%'),
  ('vitamin c serum',          NULL,          0.1800, 'Vitamin C Serum — 18%'),
  ('hyaluronic acid',          NULL,          0.1800, 'Skin Care — 18%'),
  ('niacinamide',              NULL,          0.1800, 'Skin Care — 18%'),
  ('sunscreen spf',            NULL,          0.1800, 'Sunscreen SPF — 18%'),
  ('makeup remover',           NULL,          0.1800, 'Makeup Remover — 18%'),
  ('micellar water',           NULL,          0.1800, 'Micellar Water — 18%'),
  ('lip balm',                 NULL,          0.1800, 'Lip Balm — 18%'),
  ('chapstick',                NULL,          0.1800, 'Lip Balm — 18%'),
  ('bronzer',                  NULL,          0.1800, 'Bronzer — 18%'),
  ('makeup brush',             NULL,          0.1800, 'Makeup Brush — 18%'),
  ('beauty blender',           NULL,          0.1800, 'Makeup Sponge — 18%'),
  ('false lashes',             NULL,          0.1800, 'False Lashes — 18%'),
  ('lash serum',               NULL,          0.1800, 'Lash Serum — 18%'),

  -- ══════════════════════════════════════════════════════════════════
  -- PHARMACY / MEDICINES — 5% general; 0% life-saving
  -- ══════════════════════════════════════════════════════════════════
  ('paracetamol',              'Pharmacy',    0.0500, 'OTC Medicine — 5%'),
  ('paracetamol',              'Medical Store', 0.0500, 'OTC Medicine — 5%'),
  ('crocin',                   NULL,          0.0500, 'Paracetamol — 5%'),
  ('dolo',                     NULL,          0.0500, 'Paracetamol — 5%'),
  ('combiflam',                NULL,          0.0500, 'OTC Medicine — 5%'),
  ('ibuprofen',                NULL,          0.0500, 'OTC Medicine — 5%'),
  ('aspirin',                  NULL,          0.0500, 'OTC Medicine — 5%'),
  ('antacid',                  NULL,          0.0500, 'Antacid — 5%'),
  ('eno',                      NULL,          0.0500, 'Antacid — 5%'),
  ('gelusil',                  NULL,          0.0500, 'Antacid — 5%'),
  ('digene',                   NULL,          0.0500, 'Antacid — 5%'),
  ('omeprazole',               NULL,          0.0500, 'Medicine — 5%'),
  ('pantoprazole',             NULL,          0.0500, 'Medicine — 5%'),
  ('antibiotic',               NULL,          0.0500, 'Prescription Medicine — 5%'),
  ('amoxicillin',              NULL,          0.0500, 'Antibiotic — 5%'),
  ('azithromycin',             NULL,          0.0500, 'Antibiotic — 5%'),
  ('cetirizine',               NULL,          0.0500, 'Antihistamine — 5%'),
  ('loratadine',               NULL,          0.0500, 'Antihistamine — 5%'),
  ('cough syrup',              NULL,          0.0500, 'Cough Syrup — 5%'),
  ('benadryl',                 NULL,          0.0500, 'Cough Syrup — 5%'),
  ('vicks',                    NULL,          0.0500, 'OTC Medicine — 5%'),
  ('otrivin',                  NULL,          0.0500, 'Nasal Spray — 5%'),
  ('nasal spray',              NULL,          0.0500, 'Nasal Spray — 5%'),
  ('eye drop',                 NULL,          0.0500, 'Eye Drops — 5%'),
  ('eyedrop',                  NULL,          0.0500, 'Eye Drops — 5%'),
  ('ear drop',                 NULL,          0.0500, 'Ear Drops — 5%'),
  ('bandage',                  NULL,          0.0500, 'Bandage — 5%'),
  ('band-aid',                 NULL,          0.0500, 'Band-Aid — 5%'),
  ('antiseptic',               NULL,          0.0500, 'Antiseptic — 5%'),
  ('dettol liquid',            NULL,          0.0500, 'Antiseptic — 5%'),
  ('savlon',                   NULL,          0.0500, 'Antiseptic — 5%'),
  ('thermometer',              NULL,          0.0500, 'Medical Device — 5%'),
  ('glucose',                  'Pharmacy',    0.0500, 'Glucose — 5%'),
  ('ors',                      NULL,          0.0500, 'ORS/Electrolytes — 5%'),
  ('electrolyte',              NULL,          0.0500, 'Electrolyte — 5%'),
  ('multivitamin',             NULL,          0.0500, 'Multivitamin — 5%'),
  ('vitamin tablet',           NULL,          0.0500, 'Vitamins — 5%'),
  ('calcium',                  'Pharmacy',    0.0500, 'Calcium Supplement — 5%'),
  ('iron tablet',              NULL,          0.0500, 'Iron Supplement — 5%'),
  ('protein powder',           'Pharmacy',    0.0500, 'Protein Supplement — 5%'),
  ('insulin',                  NULL,          0.0000, 'Life-Saving Drug — 0% (Exempt)'),
  ('cancer medicine',          NULL,          0.0000, 'Life-Saving Drug — 0% (Exempt)'),
  ('dialysis',                 NULL,          0.0000, 'Life-Saving Equipment — 0% (Exempt)'),
  ('ayurvedic',                NULL,          0.0500, 'Ayurvedic Medicine — 5%'),
  ('homeopathic',              NULL,          0.0500, 'Homeopathic Medicine — 5%'),
  ('chyawanprash',             NULL,          0.0500, 'Ayurvedic — 5%'),
  ('dabur',                    'Pharmacy',    0.0500, 'Ayurvedic Product — 5%'),
  ('himalaya',                 'Pharmacy',    0.0500, 'Ayurvedic Medicine — 5%'),
  ('patanjali',                'Pharmacy',    0.0500, 'Ayurvedic — 5%'),

  -- ══════════════════════════════════════════════════════════════════
  -- ELECTRONICS — 18%
  -- ══════════════════════════════════════════════════════════════════
  ('mobile phone',             NULL,          0.1800, 'Mobile Phone — 18%'),
  ('smartphone',               NULL,          0.1800, 'Smartphone — 18%'),
  ('iphone',                   NULL,          0.1800, 'Smartphone — 18%'),
  ('samsung phone',            NULL,          0.1800, 'Smartphone — 18%'),
  ('oneplus',                  NULL,          0.1800, 'Smartphone — 18%'),
  ('laptop',                   NULL,          0.1800, 'Laptop — 18%'),
  ('notebook',                 NULL,          0.1800, 'Laptop — 18%'),
  ('tablet',                   'Electronics', 0.1800, 'Tablet — 18%'),
  ('ipad',                     NULL,          0.1800, 'Tablet — 18%'),
  ('earphone',                 NULL,          0.1800, 'Earphone — 18%'),
  ('earphones',                NULL,          0.1800, 'Earphones — 18%'),
  ('earbuds',                  NULL,          0.1800, 'Earbuds — 18%'),
  ('airpods',                  NULL,          0.1800, 'Earbuds — 18%'),
  ('headphone',                NULL,          0.1800, 'Headphone — 18%'),
  ('headphones',               NULL,          0.1800, 'Headphones — 18%'),
  ('bluetooth speaker',        NULL,          0.1800, 'Bluetooth Speaker — 18%'),
  ('power bank',               NULL,          0.1800, 'Power Bank — 18%'),
  ('charger',                  'Electronics', 0.1800, 'Charger — 18%'),
  ('mobile charger',           NULL,          0.1800, 'Mobile Charger — 18%'),
  ('usb cable',                NULL,          0.1800, 'USB Cable — 18%'),
  ('screen guard',             NULL,          0.1800, 'Screen Guard — 18%'),
  ('tempered glass',           NULL,          0.1800, 'Screen Protector — 18%'),
  ('phone case',               NULL,          0.1800, 'Phone Case — 18%'),
  ('mobile cover',             NULL,          0.1800, 'Mobile Cover — 18%'),
  ('back cover',               NULL,          0.1800, 'Back Cover — 18%'),
  ('camera',                   'Electronics', 0.1800, 'Camera — 18%'),
  ('dslr',                     NULL,          0.1800, 'DSLR Camera — 18%'),
  ('led tv',                   NULL,          0.1800, 'LED TV — 18%'),
  ('smart tv',                 NULL,          0.1800, 'Smart TV — 18%'),
  ('speaker',                  'Electronics', 0.1800, 'Speaker — 18%'),
  ('wireless mouse',           NULL,          0.1800, 'Computer Peripheral — 18%'),
  ('keyboard',                 'Electronics', 0.1800, 'Keyboard — 18%'),
  ('pendrive',                 NULL,          0.1800, 'Pen Drive — 18%'),
  ('sd card',                  NULL,          0.1800, 'Memory Card — 18%'),
  ('memory card',              NULL,          0.1800, 'Memory Card — 18%'),
  ('hard disk',                NULL,          0.1800, 'Hard Disk — 18%'),
  ('ssd',                      'Electronics', 0.1800, 'SSD — 18%'),
  ('router',                   NULL,          0.1800, 'Router — 18%'),
  ('wifi router',              NULL,          0.1800, 'Wi-Fi Router — 18%'),
  ('smart watch',              NULL,          0.1800, 'Smartwatch — 18%'),
  ('fitness band',             NULL,          0.1800, 'Fitness Band — 18%'),

  -- ══════════════════════════════════════════════════════════════════
  -- GROCERY / FOOD — mostly 0% or 5%
  -- ══════════════════════════════════════════════════════════════════
  ('rice',                     'Grocery',     0.0000, 'Staple Food — 0% (Exempt)'),
  ('wheat',                    'Grocery',     0.0000, 'Staple Food — 0% (Exempt)'),
  ('atta',                     'Grocery',     0.0000, 'Wheat Flour — 0% (Exempt)'),
  ('maida',                    'Grocery',     0.0000, 'Flour — 0% (Exempt)'),
  ('dal',                      'Grocery',     0.0000, 'Lentils — 0% (Exempt)'),
  ('lentils',                  'Grocery',     0.0000, 'Lentils — 0% (Exempt)'),
  ('sugar',                    'Grocery',     0.0500, 'Sugar — 5%'),
  ('salt',                     'Grocery',     0.0000, 'Salt — 0% (Exempt)'),
  ('oil',                      'Grocery',     0.0500, 'Edible Oil — 5%'),
  ('sunflower oil',            'Grocery',     0.0500, 'Edible Oil — 5%'),
  ('mustard oil',              'Grocery',     0.0500, 'Edible Oil — 5%'),
  ('ghee',                     'Grocery',     0.0500, 'Ghee — 5%'),
  ('butter',                   'Dairy & Eggs', 0.0500, 'Butter — 5%'),
  ('cheese',                   'Dairy & Eggs', 0.0500, 'Cheese — 5%'),
  ('paneer',                   'Dairy & Eggs', 0.0500, 'Paneer — 5%'),
  ('milk',                     'Dairy & Eggs', 0.0000, 'Loose Milk — 0% (Exempt)'),
  ('yogurt',                   'Dairy & Eggs', 0.0500, 'Curd/Yogurt — 5%'),
  ('curd',                     'Dairy & Eggs', 0.0000, 'Loose Curd — 0%'),
  ('spices',                   'Grocery',     0.0500, 'Spices — 5%'),
  ('masala',                   'Grocery',     0.0500, 'Masala — 5%'),
  ('biscuit',                  'Grocery',     0.0500, 'Biscuit — 5%'),
  ('biscuits',                 'Grocery',     0.0500, 'Biscuits — 5%'),
  ('parle g',                  'Grocery',     0.0500, 'Biscuits — 5%'),
  ('britannia',                'Grocery',     0.0500, 'Biscuits/Bread — 5%'),
  ('bread',                    'Grocery',     0.0000, 'Bread — 0% (Exempt)'),
  ('packaged water',           'Beverages',   0.1800, 'Packaged Water — 18%'),
  ('mineral water',            'Beverages',   0.1800, 'Packaged Water — 18%'),
  ('juice',                    'Beverages',   0.1800, 'Packaged Juice — 18%'),
  ('fruit juice',              'Beverages',   0.1800, 'Fruit Juice — 18%'),
  ('real juice',               'Beverages',   0.1800, 'Packaged Juice — 18%'),
  ('tropicana',                'Beverages',   0.1800, 'Packaged Juice — 18%'),
  ('tea',                      'Tea & Coffee', 0.0500, 'Tea — 5%'),
  ('coffee',                   'Tea & Coffee', 0.0500, 'Coffee — 5%'),
  ('nescafe',                  NULL,          0.0500, 'Coffee — 5%'),
  ('tata tea',                 NULL,          0.0500, 'Tea — 5%'),
  ('chocolate',                'Grocery',     0.1800, 'Chocolate — 18%'),
  ('cadbury',                  'Grocery',     0.1800, 'Chocolate — 18%'),
  ('dairy milk',               'Grocery',     0.1800, 'Chocolate — 18%'),
  ('kitkat',                   'Grocery',     0.1800, 'Chocolate — 18%'),
  ('chips',                    'Grocery',     0.1800, 'Snacks — 18%'),
  ('lays',                     'Grocery',     0.1800, 'Chips — 18%'),
  ('kurkure',                  'Grocery',     0.1800, 'Snacks — 18%'),
  ('namkeen',                  'Grocery',     0.1800, 'Namkeen — 18%'),
  ('noodles',                  'Grocery',     0.1800, 'Noodles — 18%'),
  ('maggi',                    'Grocery',     0.1800, 'Instant Noodles — 18%'),
  ('pasta',                    'Grocery',     0.1800, 'Pasta — 18%'),
  ('ice cream',                'Ice Cream',   0.0500, 'Ice Cream — 5%'),

  -- ══════════════════════════════════════════════════════════════════
  -- CLOTHING — 5% (≤₹2,500) / 18% (>₹2,500) — slab via category logic
  -- ══════════════════════════════════════════════════════════════════
  ('t-shirt',                  'Clothing',    0.0500, 'T-Shirt — 5% (if ≤₹2,500) or 18%'),
  ('tshirt',                   'Clothing',    0.0500, 'T-Shirt — 5% (if ≤₹2,500) or 18%'),
  ('shirt',                    'Clothing',    0.0500, 'Shirt — 5% (if ≤₹2,500) or 18%'),
  ('saree',                    'Clothing',    0.0500, 'Saree — 5% (if ≤₹2,500) or 18%'),
  ('kurta',                    'Clothing',    0.0500, 'Kurta — 5% (if ≤₹2,500) or 18%'),
  ('salwar',                   'Clothing',    0.0500, 'Salwar Suit — 5% (if ≤₹2,500) or 18%'),
  ('jeans',                    'Clothing',    0.0500, 'Jeans — 5% (if ≤₹2,500) or 18%'),
  ('trouser',                  'Clothing',    0.0500, 'Trousers — 5% (if ≤₹2,500) or 18%'),
  ('leggings',                 'Clothing',    0.0500, 'Leggings — 5% (if ≤₹2,500) or 18%'),
  ('dress',                    'Clothing',    0.0500, 'Dress — 5% (if ≤₹2,500) or 18%'),
  ('kurti',                    'Clothing',    0.0500, 'Kurti — 5% (if ≤₹2,500) or 18%'),
  ('dupatta',                  'Clothing',    0.0500, 'Dupatta — 5% (if ≤₹2,500) or 18%'),
  ('underwear',                'Clothing',    0.0500, 'Innerwear — 5%'),
  ('innerwear',                'Clothing',    0.0500, 'Innerwear — 5%'),
  ('socks',                    'Clothing',    0.0500, 'Socks — 5%'),

  -- ══════════════════════════════════════════════════════════════════
  -- FOOTWEAR — 5% (≤₹2,500) / 18% (>₹2,500) — slab via category logic
  -- ══════════════════════════════════════════════════════════════════
  ('shoes',                    'Footwear',    0.0500, 'Shoes — 5% (if ≤₹2,500) or 18%'),
  ('sandal',                   'Footwear',    0.0500, 'Sandals — 5% (if ≤₹2,500) or 18%'),
  ('chappal',                  'Footwear',    0.0500, 'Chappals — 5% (if ≤₹2,500) or 18%'),
  ('sneaker',                  'Footwear',    0.0500, 'Sneakers — 5% (if ≤₹2,500) or 18%'),
  ('boot',                     'Footwear',    0.0500, 'Boots — 5% (if ≤₹2,500) or 18%'),
  ('slipper',                  'Footwear',    0.0500, 'Slippers — 5% (if ≤₹2,500) or 18%'),
  ('heels',                    'Footwear',    0.0500, 'Heels — 5% (if ≤₹2,500) or 18%'),
  ('sports shoes',             'Footwear',    0.0500, 'Sports Shoes — 5% (if ≤₹2,500) or 18%'),
  ('running shoes',            'Footwear',    0.0500, 'Running Shoes — 5% (if ≤₹2,500) or 18%'),

  -- ══════════════════════════════════════════════════════════════════
  -- STATIONERY — 18%
  -- ══════════════════════════════════════════════════════════════════
  ('pen',                      'Stationery',  0.1800, 'Pen — 18%'),
  ('pencil',                   'Stationery',  0.1800, 'Pencil — 18%'),
  ('notebook',                 'Stationery',  0.1800, 'Notebook — 18%'),
  ('eraser',                   'Stationery',  0.1800, 'Eraser — 18%'),
  ('scale ruler',              'Stationery',  0.1800, 'Ruler — 18%'),
  ('stapler',                  'Stationery',  0.1800, 'Stapler — 18%'),
  ('glue stick',               NULL,          0.1800, 'Glue — 18%'),
  ('scotch tape',              NULL,          0.1800, 'Tape — 18%'),
  ('highlighter pen',          NULL,          0.1800, 'Highlighter — 18%'),
  ('marker',                   'Stationery',  0.1800, 'Marker — 18%'),
  ('color pencil',             'Stationery',  0.1800, 'Color Pencil — 18%'),
  ('crayon',                   'Stationery',  0.1800, 'Crayons — 18%'),

  -- ══════════════════════════════════════════════════════════════════
  -- SPORTS — 18%
  -- ══════════════════════════════════════════════════════════════════
  ('cricket bat',              'Sports',      0.1800, 'Cricket Bat — 18%'),
  ('cricket ball',             'Sports',      0.1800, 'Cricket Ball — 18%'),
  ('football',                 'Sports',      0.1800, 'Football — 18%'),
  ('badminton',                'Sports',      0.1800, 'Badminton — 18%'),
  ('yoga mat',                 'Sports',      0.1800, 'Yoga Mat — 18%'),
  ('dumbbell',                 'Sports',      0.1800, 'Dumbbell — 18%'),
  ('gym gloves',               'Sports',      0.1800, 'Gym Accessories — 18%'),
  ('protein bar',              'Sports',      0.1800, 'Sports Nutrition — 18%'),
  ('whey protein',             'Sports',      0.1800, 'Protein Supplement — 18%'),
  ('cycling',                  'Sports',      0.1800, 'Cycling Equipment — 18%'),
  ('bicycle',                  'Sports',      0.1800, 'Bicycle — 18%'),
  ('gym equipment',            'Sports',      0.1800, 'Gym Equipment — 18%'),

  -- ══════════════════════════════════════════════════════════════════
  -- HOME DECOR / FURNITURE — 18%
  -- ══════════════════════════════════════════════════════════════════
  ('lamp',                     'Home Decor',  0.1800, 'Lamp — 18%'),
  ('curtain',                  'Home Decor',  0.1800, 'Curtain — 18%'),
  ('cushion',                  'Home Decor',  0.1800, 'Cushion — 18%'),
  ('photo frame',              'Home Decor',  0.1800, 'Photo Frame — 18%'),
  ('mirror',                   'Home Decor',  0.1800, 'Mirror — 18%'),
  ('sofa',                     'Furniture',   0.1800, 'Sofa — 18%'),
  ('chair',                    'Furniture',   0.1800, 'Chair — 18%'),
  ('table',                    'Furniture',   0.1800, 'Table — 18%'),
  ('bed',                      'Furniture',   0.1800, 'Bed — 18%'),
  ('mattress',                 'Furniture',   0.1800, 'Mattress — 18%'),
  ('wardrobe',                 'Furniture',   0.1800, 'Wardrobe — 18%'),
  ('shelf',                    'Furniture',   0.1800, 'Shelf — 18%'),
  ('bookshelf',                'Furniture',   0.1800, 'Bookshelf — 18%'),

  -- ══════════════════════════════════════════════════════════════════
  -- AUTO PARTS — 18%
  -- ══════════════════════════════════════════════════════════════════
  ('engine oil',               'Auto Parts',  0.1800, 'Engine Oil — 18%'),
  ('car battery',              'Auto Parts',  0.1800, 'Car Battery — 18%'),
  ('tyre',                     'Auto Parts',  0.1800, 'Tyres — 18%'),
  ('brake pad',                'Auto Parts',  0.1800, 'Brake Pad — 18%'),
  ('air filter',               'Auto Parts',  0.1800, 'Air Filter — 18%'),
  ('wiper blade',              'Auto Parts',  0.1800, 'Wiper Blade — 18%'),

  -- ══════════════════════════════════════════════════════════════════
  -- JEWELLERY — 3% (GST on gold/gem value; unchanged)
  -- ══════════════════════════════════════════════════════════════════
  ('gold ring',                'Jewellery',   0.0300, 'Gold Jewellery — 3%'),
  ('gold necklace',            'Jewellery',   0.0300, 'Gold Jewellery — 3%'),
  ('gold bracelet',            'Jewellery',   0.0300, 'Gold Jewellery — 3%'),
  ('gold chain',               'Jewellery',   0.0300, 'Gold Jewellery — 3%'),
  ('gold earring',             'Jewellery',   0.0300, 'Gold Jewellery — 3%'),
  ('diamond ring',             'Jewellery',   0.0300, 'Diamond Jewellery — 3%'),
  ('silver ring',              'Jewellery',   0.0300, 'Silver Jewellery — 3%'),
  ('silver chain',             'Jewellery',   0.0300, 'Silver Jewellery — 3%'),
  ('artificial jewellery',     'Jewellery',   0.0300, 'Artificial Jewellery — 3%'),
  ('imitation jewellery',      'Jewellery',   0.0300, 'Imitation Jewellery — 3%'),

  -- ══════════════════════════════════════════════════════════════════
  -- PET SUPPLIES — 18%
  -- ══════════════════════════════════════════════════════════════════
  ('dog food',                 'Pet Supplies', 0.1800, 'Pet Food — 18%'),
  ('cat food',                 'Pet Supplies', 0.1800, 'Pet Food — 18%'),
  ('pet food',                 'Pet Supplies', 0.1800, 'Pet Food — 18%'),
  ('pedigree',                 'Pet Supplies', 0.1800, 'Pet Food — 18%'),
  ('royal canin',              'Pet Supplies', 0.1800, 'Premium Pet Food — 18%'),
  ('drools',                   'Pet Supplies', 0.1800, 'Pet Food — 18%'),
  ('pet shampoo',              'Pet Supplies', 0.1800, 'Pet Shampoo — 18%'),
  ('cat litter',               'Pet Supplies', 0.1800, 'Cat Litter — 18%'),
  ('dog leash',                'Pet Supplies', 0.1800, 'Pet Accessories — 18%'),
  ('dog collar',               'Pet Supplies', 0.1800, 'Pet Accessories — 18%'),

  -- ══════════════════════════════════════════════════════════════════
  -- FLOWERS — 5%
  -- ══════════════════════════════════════════════════════════════════
  ('rose',                     'Flowers',     0.0500, 'Cut Flowers — 5%'),
  ('marigold',                 'Flowers',     0.0500, 'Cut Flowers — 5%'),
  ('jasmine',                  'Flowers',     0.0500, 'Cut Flowers — 5%'),
  ('bouquet',                  'Flowers',     0.0500, 'Flower Bouquet — 5%'),
  ('garland',                  'Flowers',     0.0500, 'Flower Garland — 5%'),

  -- ══════════════════════════════════════════════════════════════════
  -- HARDWARE — 18%
  -- ══════════════════════════════════════════════════════════════════
  ('hammer',                   'Hardware Store', 0.1800, 'Tool — 18%'),
  ('drill',                    'Hardware Store', 0.1800, 'Drill — 18%'),
  ('screwdriver',              'Hardware Store', 0.1800, 'Tool — 18%'),
  ('paint',                    'Hardware Store', 0.1800, 'Paint — 18%'),
  ('wire',                     'Hardware Store', 0.1800, 'Wire — 18%'),
  ('switch',                   'Hardware Store', 0.1800, 'Electrical Switch — 18%'),
  ('bulb',                     'Hardware Store', 0.1800, 'Light Bulb — 18%'),
  ('led bulb',                 NULL,          0.1800, 'LED Bulb — 18%'),

  -- ══════════════════════════════════════════════════════════════════
  -- TOYS & GAMES — 18%
  -- ══════════════════════════════════════════════════════════════════
  ('toy car',                  'Toys & Games', 0.1800, 'Toy — 18%'),
  ('doll',                     'Toys & Games', 0.1800, 'Toy — 18%'),
  ('board game',               'Toys & Games', 0.1800, 'Board Game — 18%'),
  ('lego',                     'Toys & Games', 0.1800, 'Construction Toy — 18%'),
  ('action figure',            'Toys & Games', 0.1800, 'Toy — 18%'),
  ('video game',               'Toys & Games', 0.1800, 'Video Game — 18%'),
  ('controller',               'Toys & Games', 0.1800, 'Game Controller — 18%'),
  ('puzzle',                   'Toys & Games', 0.1800, 'Puzzle — 18%')

ON CONFLICT (keyword, COALESCE(category_hint, '')) DO UPDATE SET
  gst_rate   = EXCLUDED.gst_rate,
  reason     = EXCLUDED.reason,
  updated_at = now();

-- ============================================================================
-- 3. ADD gst_rate_override COLUMN TO products TABLE
-- ============================================================================
-- Nullable — NULL means "use category-level rate" (existing logic, unchanged).
-- A non-null value is set by seller acceptance of a GST recommendation.
-- Admin can also set this per-product from the Tax Settings panel.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS gst_rate_override numeric(5,4);

COMMENT ON COLUMN public.products.gst_rate_override IS
  'Product-level GST override (e.g. 0.05 = 5%). NULL = use category rate from tax_config.';

-- ============================================================================
-- 4. ENABLE RLS ON product_gst_overrides
-- ============================================================================

ALTER TABLE public.product_gst_overrides ENABLE ROW LEVEL SECURITY;

-- ── RLS Policies (idempotent) ────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'product_gst_overrides'
      AND policyname = 'Anyone authenticated can read product_gst_overrides'
  ) THEN
    CREATE POLICY "Anyone authenticated can read product_gst_overrides"
      ON public.product_gst_overrides FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;

-- Anonymous can also read (needed for product add page before login is verified)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'product_gst_overrides'
      AND policyname = 'Anon can read product_gst_overrides'
  ) THEN
    CREATE POLICY "Anon can read product_gst_overrides"
      ON public.product_gst_overrides FOR SELECT
      TO anon
      USING (true);
  END IF;
END $$;

-- Only admins can insert/update/delete
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'product_gst_overrides'
      AND policyname = 'Admin users can manage product_gst_overrides'
  ) THEN
    CREATE POLICY "Admin users can manage product_gst_overrides"
      ON public.product_gst_overrides FOR ALL
      TO authenticated
      USING (
        public.is_active_admin(auth.uid())
      )
      WITH CHECK (
        public.is_active_admin(auth.uid())
      );
  END IF;
END $$;

-- ============================================================================
-- 5. GRANT PERMISSIONS
-- ============================================================================

-- product_gst_overrides
GRANT SELECT ON public.product_gst_overrides TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.product_gst_overrides TO authenticated;

-- products.gst_rate_override column
GRANT SELECT (gst_rate_override) ON public.products TO anon, authenticated;
GRANT UPDATE (gst_rate_override) ON public.products TO authenticated;

-- ============================================================================
-- 6. NOTIFY PostgREST to reload schema cache
-- ============================================================================

NOTIFY pgrst, 'reload schema';
