-- ============================================================================
-- Migration: 20260705000001_category_commission_rates.sql
-- Description: Seeds category-specific commission rates into platform_config.
--
-- STRATEGY:
--   The platform_config table stores key-value pairs.
--   PlatformConfigProvider.getCommissionRateForCategory(category) reads keys
--   matching 'commission_percent_{Category}' and returns that value / 100.
--   The DEFAULT (5%) remains in 'commission_percent' as the fallback.
--
-- RATIONALE (see profitability_analysis.md):
--   • Restaurant/Food: 15% — Enything bears S9(5) GST obligation (5% remitted
--     to govt from every food order). A 15% commission means Enything nets 10%
--     real margin after GST. Still 50% cheaper than Zomato (30%).
--   • Grocery/Organic: 8% — High frequency, low AOV. Competitive vs Swiggy
--     Instamart (12–18%).
--   • Pharmacy: 6% — Regulated margins, price-sensitive. Value-add via
--     prescription verification offsets lower %.
--   • Electronics/Mobile: 10% — High basket size, high support overhead.
--   • Clothing/Footwear: 10% — Returns risk, seasonal demand.
--   • Jewellery: 12% — High value, delivery risk, insurance overhead.
--   • Beverages: 10% — 18% GST category, fast-moving.
--   • Salon/Beauty/Cosmetics: 12% — Swiggy charges 20-28%. Still 40% cheaper.
--   • Bakery/Sweets/Ice Cream/Tea: 12% — Food category, GST burden applies.
--   • Fresh produce (Fruits/Vegs, Butcher, Fish, Dairy): 6-7% — Zero GST,
--     low margins at seller end. Be competitive to win early sellers.
--   • Pet Supplies/Toys/Sports/Stationery: 10% — Non-essential, high margin.
--   • Home Decor/Hardware/Auto Parts/Furniture: 8% — Infrequent large orders.
--   • Flowers: 8% — Seasonal, perishable.
--
-- ALL RATES REMAIN BELOW COMPETITORS. This is the "Enything Advantage".
-- ============================================================================

-- ── Food/Restaurant categories (you remit S9(5) GST — need higher commission)
INSERT INTO public.platform_config (key, value, label, description, updated_at)
VALUES
  ('commission_percent_Restaurant',      '15', 'Commission % — Restaurant',      'Restaurant orders: Enything remits S9(5) GST; 15% covers GST + nets 10% real margin. Zomato charges 30%.', NOW()),
  ('commission_percent_Fast Food',       '15', 'Commission % — Fast Food',        'Fast Food: Same S9(5) GST deemed-supplier obligation as Restaurant.', NOW()),
  ('commission_percent_Bakery',          '12', 'Commission % — Bakery',           'Bakery: Deemed supplier, 5% GST. 12% commission nets 7% after GST. Swiggy charges 18-25%.', NOW()),
  ('commission_percent_Sweets & Mithai', '12', 'Commission % — Sweets & Mithai',  'Sweets: Deemed supplier category. 12% commission.', NOW()),
  ('commission_percent_Tea & Coffee',    '12', 'Commission % — Tea & Coffee',     'Tea & Coffee outlets: Deemed supplier, 12% commission.', NOW()),
  ('commission_percent_Ice Cream',       '12', 'Commission % — Ice Cream',        'Ice Cream: Deemed supplier, 12% commission.', NOW()),
  ('commission_percent_Paan Shop',       '10', 'Commission % — Paan Shop',        'Paan shops: Blended category (tobacco excluded). 10% commission.', NOW())
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      label      = EXCLUDED.label,
      description = EXCLUDED.description,
      updated_at = NOW();

-- ── Grocery & Fresh Produce (high frequency, price-sensitive)
INSERT INTO public.platform_config (key, value, label, description, updated_at)
VALUES
  ('commission_percent_Grocery',                   '8',  'Commission % — Grocery',                  'Grocery: 8% vs Swiggy Instamart 12-18%. Volume compensates lower %.', NOW()),
  ('commission_percent_Organic',                   '8',  'Commission % — Organic',                  'Organic: Same as Grocery. Premium category = slightly higher willingness to pay.', NOW()),
  ('commission_percent_Supermarket / Hypermarket', '8',  'Commission % — Supermarket',              'Supermarket/Hypermarket: Bulk orders, 8% commission.', NOW()),
  ('commission_percent_Fruits & Vegs',             '7',  'Commission % — Fruits & Vegs',            'Fresh produce: 0% GST, ultra-competitive category. 7% keeps sellers happy.', NOW()),
  ('commission_percent_Butcher',                   '7',  'Commission % — Butcher',                  'Butcher/Meat: 0% GST, perishable. 7% commission.', NOW()),
  ('commission_percent_Fish & Seafood',            '7',  'Commission % — Fish & Seafood',           'Fish: 0% GST, highly perishable. 7% to stay competitive.', NOW()),
  ('commission_percent_Dairy & Eggs',              '6',  'Commission % — Dairy & Eggs',             'Dairy: Low margins at seller end. 6% keeps dairies on platform.', NOW())
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      label      = EXCLUDED.label,
      description = EXCLUDED.description,
      updated_at = NOW();

-- ── Pharmacy & Medical (regulated, price-sensitive)
INSERT INTO public.platform_config (key, value, label, description, updated_at)
VALUES
  ('commission_percent_Pharmacy',      '6', 'Commission % — Pharmacy',      'Pharmacy: Regulated margins. 6% + prescription handling fee = effective 8%.', NOW()),
  ('commission_percent_Medical Store', '6', 'Commission % — Medical Store',  'Medical Store: Same as Pharmacy. Competitive vs 15-22% elsewhere.', NOW())
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      label      = EXCLUDED.label,
      description = EXCLUDED.description,
      updated_at = NOW();

-- ── Electronics & High-Value (higher overhead, high AOV)
INSERT INTO public.platform_config (key, value, label, description, updated_at)
VALUES
  ('commission_percent_Electronics',    '10', 'Commission % — Electronics',    'Electronics: 18% GST category, high AOV. 10% = ₹100+ per order.', NOW()),
  ('commission_percent_Mobile & Repair','10', 'Commission % — Mobile & Repair','Mobile/Repair: High AOV, 10% commission.', NOW())
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      label      = EXCLUDED.label,
      description = EXCLUDED.description,
      updated_at = NOW();

-- ── Fashion & Accessories (returns risk)
INSERT INTO public.platform_config (key, value, label, description, updated_at)
VALUES
  ('commission_percent_Clothing', '10', 'Commission % — Clothing', 'Clothing: Price-slab GST. Returns risk justifies 10%. Competitors charge 20%+.', NOW()),
  ('commission_percent_Footwear', '10', 'Commission % — Footwear', 'Footwear: Same as Clothing. 10% commission.', NOW()),
  ('commission_percent_Jewellery','12', 'Commission % — Jewellery', 'Jewellery: High value, theft/damage risk, insurance overhead. 12% commission.', NOW())
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      label      = EXCLUDED.label,
      description = EXCLUDED.description,
      updated_at = NOW();

-- ── Beverages & Lifestyle (18% GST, higher margin)
INSERT INTO public.platform_config (key, value, label, description, updated_at)
VALUES
  ('commission_percent_Beverages',         '10', 'Commission % — Beverages',         'Beverages: 18% GST (post Sept 2025 reform). Fast-moving. 10% commission.', NOW()),
  ('commission_percent_Salon & Beauty',    '12', 'Commission % — Salon & Beauty',    'Salon/Beauty: Premium category. Swiggy charges 20-28%. 12% is strong value.', NOW()),
  ('commission_percent_Cosmetics & Beauty','12', 'Commission % — Cosmetics & Beauty','Cosmetics: Same as Salon. 12% commission.', NOW()),
  ('commission_percent_Flowers',           '8',  'Commission % — Flowers',           'Flowers: Seasonal, perishable. 8% commission to attract florists.', NOW())
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      label      = EXCLUDED.label,
      description = EXCLUDED.description,
      updated_at = NOW();

-- ── Lifestyle & General Retail (non-essential, higher margin products)
INSERT INTO public.platform_config (key, value, label, description, updated_at)
VALUES
  ('commission_percent_Pet Supplies', '10', 'Commission % — Pet Supplies', 'Pet Supplies: 18% GST, infrequent high-AOV orders. 10% commission.', NOW()),
  ('commission_percent_Toys & Games', '10', 'Commission % — Toys & Games',  'Toys: 18% GST. Non-essential high margin. 10% commission.', NOW()),
  ('commission_percent_Sports',       '10', 'Commission % — Sports',        'Sports equipment: 18% GST. 10% commission.', NOW()),
  ('commission_percent_Stationery',   '8',  'Commission % — Stationery',    'Stationery: 18% GST but low AOV. 8% commission.', NOW())
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      label      = EXCLUDED.label,
      description = EXCLUDED.description,
      updated_at = NOW();

-- ── Home & Infrastructure (infrequent large orders)
INSERT INTO public.platform_config (key, value, label, description, updated_at)
VALUES
  ('commission_percent_Home Decor',    '8', 'Commission % — Home Decor',    'Home Decor: Infrequent but larger orders. 8% commission.', NOW()),
  ('commission_percent_Furniture',     '8', 'Commission % — Furniture',     'Furniture: High AOV, delivery-intensive. 8% commission.', NOW()),
  ('commission_percent_Hardware Store','7', 'Commission % — Hardware Store','Hardware: B2B mix, price sensitive. 7% commission.', NOW()),
  ('commission_percent_Auto Parts',    '8', 'Commission % — Auto Parts',    'Auto Parts: 18% GST, niche. 8% commission.', NOW()),
  ('commission_percent_Other',         '8', 'Commission % — Other (default)','Catch-all: 8% for unlisted categories.', NOW())
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      label      = EXCLUDED.label,
      description = EXCLUDED.description,
      updated_at = NOW();

-- ── ALSO: Update Enything Pass Lite pricing to be sustainable
-- Lite was ₹49 — too cheap: 4 free deliveries/month costs ₹80+ in rider subsidy.
-- Raising Lite to ₹79 with a higher free-delivery threshold (₹249 vs ₹199).
-- Only update if it hasn't already been changed from the original seeded value.
UPDATE public.subscription_plans
SET price_inr              = 79,
    delivery_free_threshold = 249,
    updated_at             = NOW()
WHERE name = 'Lite'
  AND price_inr = 49;  -- only if still at the original seeded price

-- ── GRANT (ensure anon can read commission config at app startup)
GRANT SELECT ON public.platform_config TO anon, authenticated;

-- ── Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
