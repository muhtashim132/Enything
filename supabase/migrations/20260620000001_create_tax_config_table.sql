-- =============================================================================
-- Migration: Create tax_config table with September 2025 GST Reform rates
-- =============================================================================
-- India's GST Simplification Reform (Notification 9/2025-Central Tax Rate,
-- effective September 22, 2025) removed the 12% and 28% slabs for most goods,
-- consolidating into 0%, 5%, 18%, and 40%.
--
-- Key changes:
--   • Clothing & Footwear: threshold raised ₹1,000 → ₹2,500 (per item/pair)
--                          upper slab: 12% → 18%
--   • Beverages, Stationery, Toys & Games, Sports: 12% → 18%
--   • New categories added: Cosmetics & Beauty, Supermarket / Hypermarket
-- =============================================================================

-- 1. Create the table (idempotent)
CREATE TABLE IF NOT EXISTS public.tax_config (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  category            text        UNIQUE NOT NULL,
  gst_rate            numeric(5,4) NOT NULL,       -- e.g. 0.0500 = 5% (base or low-slab rate)
  slab_threshold      numeric(10,2),               -- NULL = flat rate; 2500.00 for Clothing/Footwear
  slab_high_rate      numeric(5,4),                -- GST rate for items priced ABOVE slab_threshold
  is_deemed_supplier  boolean     NOT NULL DEFAULT false,
  is_custom           boolean     NOT NULL DEFAULT false,
  updated_by          uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- 2. Add slab columns if table already existed without them (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'tax_config'
      AND column_name  = 'slab_threshold'
  ) THEN
    ALTER TABLE public.tax_config ADD COLUMN slab_threshold numeric(10,2);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'tax_config'
      AND column_name  = 'slab_high_rate'
  ) THEN
    ALTER TABLE public.tax_config ADD COLUMN slab_high_rate numeric(5,4);
  END IF;
END $$;

-- 3. Seed / upsert all categories with correct September 2025 GST rates
-- Format: (category, gst_rate, slab_threshold, slab_high_rate, is_deemed_supplier)

INSERT INTO public.tax_config
  (category, gst_rate, slab_threshold, slab_high_rate, is_deemed_supplier, is_custom)
VALUES
  -- ── Food: Enything is Deemed Supplier (Section 9(5)) ──────────────────────
  -- 5% flat, no slab, Enything deposits GST to govt
  ('Restaurant',        0.0500, NULL,    NULL,   true,  false),
  ('Fast Food',         0.0500, NULL,    NULL,   true,  false),
  ('Bakery',            0.0500, NULL,    NULL,   true,  false),
  ('Sweets & Mithai',   0.0500, NULL,    NULL,   true,  false),
  ('Tea & Coffee',      0.0500, NULL,    NULL,   true,  false),
  ('Ice Cream',         0.0500, NULL,    NULL,   true,  false),
  ('Paan Shop',         0.0500, NULL,    NULL,   true,  false),  -- blended avg; tobacco excluded

  -- ── Perishables / Raw (Seller is supplier) ─────────────────────────────────
  ('Fruits & Vegs',     0.0000, NULL,    NULL,   false, false),  -- 0% fresh produce
  ('Butcher',           0.0000, NULL,    NULL,   false, false),  -- 0% fresh meat
  ('Fish & Seafood',    0.0000, NULL,    NULL,   false, false),  -- 0% fresh fish
  ('Dairy & Eggs',      0.0500, NULL,    NULL,   false, false),  -- blended: butter 12% now 18%, eggs 0%, milk 0%

  -- ── Grocery / Organic ──────────────────────────────────────────────────────
  ('Grocery',           0.0500, NULL,    NULL,   false, false),  -- 5% blended
  ('Organic',           0.0500, NULL,    NULL,   false, false),  -- 5% blended
  ('Supermarket / Hypermarket', 0.0500, NULL, NULL, false, false), -- 5% grocery blended [NEW]

  -- ── Beverages (Sept 2025: 12% slab removed → 18%) ─────────────────────────
  ('Beverages',         0.1800, NULL,    NULL,   false, false),  -- 18% packaged drinks (was 12%)

  -- ── Pharmacy ───────────────────────────────────────────────────────────────
  ('Pharmacy',          0.0500, NULL,    NULL,   false, false),  -- 5% OTC/life-saving medicines
  ('Medical Store',     0.0500, NULL,    NULL,   false, false),

  -- ── Clothing: price-slab (Sept 2025: ₹2,500 threshold, 18% upper) ─────────
  -- slab_threshold = ₹2,500 per item; below = 5%, above = 18%
  ('Clothing',          0.0500, 2500.00, 0.1800, false, false),

  -- ── Footwear: price-slab (Sept 2025: ₹2,500 threshold, 18% upper) ─────────
  -- slab_threshold = ₹2,500 per pair; below = 5%, above = 18%
  ('Footwear',          0.0500, 2500.00, 0.1800, false, false),

  -- ── Electronics (18% standard) ─────────────────────────────────────────────
  ('Electronics',       0.1800, NULL,    NULL,   false, false),
  ('Mobile & Repair',   0.1800, NULL,    NULL,   false, false),

  -- ── Jewellery (3% — gold/gem value, unchanged) ─────────────────────────────
  ('Jewellery',         0.0300, NULL,    NULL,   false, false),

  -- ── General Retail (Sept 2025: 12% slab removed → 18%) ────────────────────
  ('Stationery',        0.1800, NULL,    NULL,   false, false),  -- was 12%
  ('Toys & Games',      0.1800, NULL,    NULL,   false, false),  -- was 12%
  ('Sports',            0.1800, NULL,    NULL,   false, false),  -- was 12%
  ('Pet Supplies',      0.1800, NULL,    NULL,   false, false),
  ('Salon & Beauty',    0.1800, NULL,    NULL,   false, false),
  ('Cosmetics & Beauty',0.1800, NULL,    NULL,   false, false),  -- [NEW] same as Salon
  ('Flowers',           0.0500, NULL,    NULL,   false, false),  -- 5% cut flowers
  ('Home Decor',        0.1800, NULL,    NULL,   false, false),
  ('Furniture',         0.1800, NULL,    NULL,   false, false),
  ('Hardware Store',    0.1800, NULL,    NULL,   false, false),
  ('Auto Parts',        0.1800, NULL,    NULL,   false, false),
  ('Other',             0.1800, NULL,    NULL,   false, false)   -- conservative default

ON CONFLICT (category) DO UPDATE SET
  -- Only update the rate/slab columns if NOT customized by admin
  gst_rate           = CASE WHEN public.tax_config.is_custom THEN public.tax_config.gst_rate
                            ELSE EXCLUDED.gst_rate END,
  slab_threshold     = CASE WHEN public.tax_config.is_custom THEN public.tax_config.slab_threshold
                            ELSE EXCLUDED.slab_threshold END,
  slab_high_rate     = CASE WHEN public.tax_config.is_custom THEN public.tax_config.slab_high_rate
                            ELSE EXCLUDED.slab_high_rate END,
  is_deemed_supplier = CASE WHEN public.tax_config.is_custom THEN public.tax_config.is_deemed_supplier
                            ELSE EXCLUDED.is_deemed_supplier END,
  updated_at         = now();

-- 4. Enable RLS
ALTER TABLE public.tax_config ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies (idempotent)

-- Anyone authenticated can read tax config (needed at checkout to calculate GST)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'tax_config'
      AND policyname = 'Authenticated users can read tax_config'
  ) THEN
    CREATE POLICY "Authenticated users can read tax_config"
      ON public.tax_config FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;

-- Only admins (admin_users table) can modify tax config
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'tax_config'
      AND policyname = 'Admin users can modify tax_config'
  ) THEN
    CREATE POLICY "Admin users can modify tax_config"
      ON public.tax_config FOR ALL
      TO authenticated
      USING (
        public.is_active_admin(auth.uid())
      )
      WITH CHECK (
        public.is_active_admin(auth.uid())
      );
  END IF;
END $$;

-- 6. GRANT permissions
GRANT SELECT ON public.tax_config TO anon, authenticated;
GRANT INSERT, UPDATE ON public.tax_config TO authenticated;

-- 7. Reload schema cache
NOTIFY pgrst, 'reload schema';
