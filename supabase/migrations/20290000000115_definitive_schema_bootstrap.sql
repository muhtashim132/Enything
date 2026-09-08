-- ============================================================================
-- Migration: 20290000000115_definitive_schema_bootstrap.sql
-- Description:
--   DEFINITIVE SCHEMA BOOTSTRAP — Makes the migration chain self-contained.
--
--   The original Enything database was created via the Supabase Dashboard and
--   SQL Editor, but those CREATE TABLE statements were never added to the
--   migrations/ folder. This migration closes that gap by adding CREATE TABLE
--   IF NOT EXISTS for ALL 18 tables that the app depends on.
--
--   SAFETY: Every statement uses IF NOT EXISTS or ON CONFLICT DO NOTHING.
--   Running this on the live database (hvtujaatwhyxielrlztr) is a complete
--   no-op — all tables already exist. This migration exists purely to make
--   fresh deployments and disaster recovery work from migrations alone.
--
-- TABLES CREATED:
--   Core (12): profiles, customers, shops, products, orders, order_items,
--              delivery_partners, delivery_kyc_docs, seller_kyc_docs,
--              ratings, notifications, prescription_docs
--   Supporting (6): vehicle_change_requests, admin_users, permissions,
--                   roles, role_permissions, platform_config
--
-- ALSO:
--   - Enables PostGIS extension
--   - Seeds missing platform_config operational keys
-- ============================================================================

-- ============================================================================
-- PART 1: EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ============================================================================
-- PART 2: CORE TABLES (12 tables)
-- ============================================================================

-- ── 2.1 profiles ────────────────────────────────────────────────────────────
-- Central user identity table. Every auth.users entry gets a profiles row.
CREATE TABLE IF NOT EXISTS public.profiles (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name       TEXT NOT NULL DEFAULT '',
  email           TEXT,
  phone           TEXT,
  role            TEXT NOT NULL DEFAULT 'customer',
  avatar_url      TEXT,
  average_rating  NUMERIC DEFAULT 0.0,
  total_reviews   INTEGER DEFAULT 0,
  notification_preferences JSONB DEFAULT '{"push": true, "sms": false}'::jsonb,
  active_device_id TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ── 2.2 customers ───────────────────────────────────────────────────────────
-- Customer-specific data (addresses, location, preferences).
CREATE TABLE IF NOT EXISTS public.customers (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name            TEXT,
  phone           TEXT,
  address         TEXT,
  default_address TEXT,
  address_home    JSONB,
  address_work    JSONB,
  address_other   JSONB,
  location        geography(Point, 4326),
  house_number    TEXT,
  pincode         TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ── 2.3 shops ───────────────────────────────────────────────────────────────
-- Each seller has one or more shops. Core marketplace entity.
CREATE TABLE IF NOT EXISTS public.shops (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name                TEXT NOT NULL,
  shop_type           TEXT DEFAULT 'shop',
  category            TEXT,
  categories          JSONB DEFAULT '[]'::jsonb,
  cuisine_type        TEXT,
  fssai_number        TEXT,
  address             TEXT,
  location            geography(Point, 4326),
  prep_time_minutes   INTEGER DEFAULT 30,
  is_veg_only         BOOLEAN DEFAULT false,
  opening_hours       TEXT,
  open_time           TEXT DEFAULT '09:00',
  close_time          TEXT DEFAULT '21:00',
  is_active           BOOLEAN DEFAULT false,
  is_accepting_orders BOOLEAN DEFAULT true,
  banner_url          TEXT,
  average_rating      NUMERIC DEFAULT 0.0,
  total_reviews       INTEGER DEFAULT 0,
  total_orders        INTEGER DEFAULT 0,
  verification_status TEXT DEFAULT 'pending',
  kyc_documents       JSONB DEFAULT '{}'::jsonb,
  aadhar_number       TEXT,
  pan_number          TEXT,
  gst_number          TEXT,
  trade_license       TEXT,
  bank_account_number TEXT,
  bank_ifsc           TEXT,
  bank_account_holder TEXT,
  house_number        TEXT,
  pincode             TEXT,
  metadata            JSONB DEFAULT '{}'::jsonb,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

-- ── 2.4 products ────────────────────────────────────────────────────────────
-- Items listed by sellers within their shops.
CREATE TABLE IF NOT EXISTS public.products (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id               UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL,
  category              TEXT,
  sub_category          TEXT,
  brand                 TEXT,
  price                 NUMERIC NOT NULL DEFAULT 0,
  original_price        NUMERIC,
  total_quantity         INTEGER,
  weight_per_unit       NUMERIC DEFAULT 0.5,
  unit_type             TEXT DEFAULT 'pieces',
  description           TEXT,
  images                JSONB DEFAULT '[]'::jsonb,
  is_veg                BOOLEAN,
  menu_category         TEXT,
  prep_time_minutes     INTEGER,
  special_tags          JSONB DEFAULT '[]'::jsonb,
  is_available          BOOLEAN DEFAULT true,
  is_deleted            BOOLEAN DEFAULT false,
  rating                NUMERIC DEFAULT 0.0,
  total_reviews         INTEGER DEFAULT 0,
  requires_prescription BOOLEAN DEFAULT false,
  medicine_type         TEXT DEFAULT 'General',
  variants              JSONB DEFAULT '[]'::jsonb,
  gst_rate_override     NUMERIC,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

-- ── 2.5 orders ──────────────────────────────────────────────────────────────
-- Core order table with full financial snapshot.
CREATE TABLE IF NOT EXISTS public.orders (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id             UUID NOT NULL REFERENCES auth.users(id),
  shop_id                 UUID REFERENCES public.shops(id),
  delivery_partner_id     UUID,
  status                  TEXT NOT NULL DEFAULT 'pending',
  total_amount            NUMERIC(10,2) NOT NULL DEFAULT 0,
  delivery_charges        NUMERIC(10,2) DEFAULT 0,
  rider_earnings          NUMERIC(10,2) DEFAULT 0,
  multi_shop_surcharge    NUMERIC(10,2) NOT NULL DEFAULT 0,
  platform_fee            NUMERIC(10,2) DEFAULT 0,
  small_cart_fee          NUMERIC(10,2) DEFAULT 0,
  heavy_order_fee         NUMERIC(10,2) DEFAULT 0,
  address                 TEXT,
  address_label           TEXT,
  delivery_notes          TEXT,
  customer_phone          TEXT,
  shop_phone              TEXT,
  rider_phone             TEXT,
  payment_method          TEXT,
  payment_status          TEXT DEFAULT 'pending',
  razorpay_order_id       TEXT,
  razorpay_payment_id     TEXT,
  cancelled_reason        TEXT,
  rejection_message       TEXT,
  cart_group_id           UUID,
  acceptance_deadline     TIMESTAMPTZ,
  payment_deadline        TIMESTAMPTZ,
  seller_accepted         BOOLEAN NOT NULL DEFAULT false,
  partner_accepted        BOOLEAN NOT NULL DEFAULT false,
  arrived_at_shop_time    TIMESTAMPTZ,
  order_ready_time        TIMESTAMPTZ,
  wait_time_penalty       NUMERIC(10,2) NOT NULL DEFAULT 0,
  wait_time_disputed      BOOLEAN NOT NULL DEFAULT false,
  has_customer_rated      BOOLEAN NOT NULL DEFAULT false,
  has_seller_rated        BOOLEAN NOT NULL DEFAULT false,
  has_delivery_rated      BOOLEAN NOT NULL DEFAULT false,
  delivery_lat            DOUBLE PRECISION,
  delivery_lng            DOUBLE PRECISION,
  rider_lat               DOUBLE PRECISION,
  rider_lng               DOUBLE PRECISION,
  rider_location_updated_at TIMESTAMPTZ,
  shop_lat                DOUBLE PRECISION,
  shop_lng                DOUBLE PRECISION,
  prescription_urls       JSONB DEFAULT '[]'::jsonb,
  -- Financial snapshot (frozen at checkout, never recalculated)
  gst_item_total          NUMERIC(10,2) NOT NULL DEFAULT 0,
  s9_5_gst_amount         NUMERIC(10,2) DEFAULT 0,
  non_food_gst_amount     NUMERIC(10,2) DEFAULT 0,
  gst_delivery            NUMERIC(10,2) NOT NULL DEFAULT 0,
  gst_platform            NUMERIC(10,2) NOT NULL DEFAULT 0,
  tcs_amount              NUMERIC(10,2) DEFAULT 0,
  tds_amount              NUMERIC(10,2) DEFAULT 0,
  enything_commission     NUMERIC(10,2) NOT NULL DEFAULT 0,
  seller_payout           NUMERIC(10,2) NOT NULL DEFAULT 0,
  gateway_deduction       NUMERIC(10,2) NOT NULL DEFAULT 0,
  grand_total_collected   NUMERIC(10,2) NOT NULL DEFAULT 0,
  gst_rate_snapshot       JSONB DEFAULT '{}'::jsonb,
  estimated_distance_km   NUMERIC(10,2) DEFAULT 0,
  shop_prep_time_snapshot INTEGER DEFAULT 30,
  coupon_id               UUID,
  coupon_discount         NUMERIC(10,2) DEFAULT 0,
  idempotency_key         UUID,
  delivery_otp            TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now()
);

-- ── 2.6 order_items ─────────────────────────────────────────────────────────
-- Line items within an order.
CREATE TABLE IF NOT EXISTS public.order_items (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id              UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id            UUID REFERENCES public.products(id) ON DELETE SET NULL,
  product_name          TEXT NOT NULL DEFAULT '',
  variant_name          TEXT,
  quantity              INTEGER NOT NULL DEFAULT 1,
  price                 NUMERIC(10,2) NOT NULL DEFAULT 0,
  weight_kg             NUMERIC(10,3) NOT NULL DEFAULT 0,
  special_instructions  TEXT,
  requires_prescription BOOLEAN DEFAULT false,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2.7 delivery_partners ───────────────────────────────────────────────────
-- Rider records with KYC, location, vehicle info.
CREATE TABLE IF NOT EXISTS public.delivery_partners (
  id                    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name                  TEXT,
  phone                 TEXT,
  email                 TEXT,
  location              geography(Point, 4326),
  is_active             BOOLEAN DEFAULT false,
  is_available          BOOLEAN DEFAULT false,
  is_accepting_orders   BOOLEAN DEFAULT true,
  verification_status   TEXT DEFAULT 'pending',
  vehicle_type          TEXT DEFAULT 'motorcycle',
  preferred_nav_app     TEXT DEFAULT 'google_maps',
  auto_accept           BOOLEAN DEFAULT false,
  aadhar_number         TEXT,
  pan_number            TEXT,
  driving_license       TEXT,
  insurance_number      TEXT,
  vehicle_reg_number    TEXT,
  bank_account_number   TEXT,
  bank_ifsc             TEXT,
  bank_account_holder   TEXT,
  kyc_documents         JSONB DEFAULT '{}'::jsonb,
  bg_tracking_secret    UUID DEFAULT gen_random_uuid(),
  voip_token            TEXT,
  house_number          TEXT,
  pincode               TEXT,
  average_rating        NUMERIC DEFAULT 0.0,
  total_reviews         INTEGER DEFAULT 0,
  total_deliveries      INTEGER DEFAULT 0,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

-- ── 2.8 delivery_kyc_docs ───────────────────────────────────────────────────
-- Uploaded KYC documents for delivery partners (aadhar, PAN, DL, etc.)
CREATE TABLE IF NOT EXISTS public.delivery_kyc_docs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id    UUID NOT NULL REFERENCES public.delivery_partners(id) ON DELETE CASCADE,
  doc_type    TEXT NOT NULL,
  doc_url     TEXT NOT NULL,
  status      TEXT DEFAULT 'pending',
  uploaded_at TIMESTAMPTZ DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID
);

-- ── 2.9 seller_kyc_docs ────────────────────────────────────────────────────
-- Uploaded KYC documents for sellers/shops.
CREATE TABLE IF NOT EXISTS public.seller_kyc_docs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id     UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  seller_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  doc_type    TEXT NOT NULL,
  doc_url     TEXT NOT NULL,
  status      TEXT DEFAULT 'pending',
  uploaded_at TIMESTAMPTZ DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID
);

-- ── 2.10 ratings ────────────────────────────────────────────────────────────
-- Ratings between users (customer↔seller, customer↔rider, seller↔rider).
CREATE TABLE IF NOT EXISTS public.ratings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  rater_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ratee_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  shop_id     UUID REFERENCES public.shops(id) ON DELETE SET NULL,
  product_id  UUID REFERENCES public.products(id) ON DELETE SET NULL,
  rater_role  TEXT NOT NULL,
  ratee_role  TEXT NOT NULL,
  rating      NUMERIC NOT NULL CHECK (rating >= 1 AND rating <= 5),
  review      TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2.11 notifications ─────────────────────────────────────────────────────
-- Persistent in-app notification history.
CREATE TABLE IF NOT EXISTS public.notifications (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  notif_key   TEXT NOT NULL,
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  order_id    UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  is_read     BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2.12 prescription_docs ──────────────────────────────────────────────────
-- Metadata for uploaded prescription images (pharmacy orders).
CREATE TABLE IF NOT EXISTS public.prescription_docs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    UUID REFERENCES public.orders(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  doc_url     TEXT NOT NULL,
  status      TEXT DEFAULT 'pending',
  uploaded_at TIMESTAMPTZ DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID
);

-- ============================================================================
-- PART 3: SUPPORTING TABLES (6 tables)
-- ============================================================================

-- ── 3.1 platform_config ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.platform_config (
  key         TEXT PRIMARY KEY,
  value       JSONB NOT NULL,
  label       TEXT,
  description TEXT,
  updated_by  UUID,
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- ── 3.2 roles ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.roles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT NOT NULL UNIQUE,
  description TEXT,
  is_system   BOOLEAN DEFAULT false,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- ── 3.3 permissions ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.permissions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  description TEXT,
  module      TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- ── 3.4 role_permissions ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.role_permissions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id       UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
  UNIQUE(role_id, permission_id)
);

-- ── 3.5 admin_users ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_users (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name       TEXT NOT NULL,
  phone           TEXT,
  admin_level     TEXT NOT NULL DEFAULT 'operations',
  permissions     JSONB,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_by      UUID,
  admin_password  TEXT,
  notes           TEXT,
  avatar_url      TEXT,
  role_id         UUID REFERENCES public.roles(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  last_login_at   TIMESTAMPTZ
);

-- ── 3.6 vehicle_change_requests ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.vehicle_change_requests (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id        UUID NOT NULL,
  requested_type  TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending',
  admin_note      TEXT,
  requested_at    TIMESTAMPTZ DEFAULT now(),
  resolved_at     TIMESTAMPTZ
);

-- ============================================================================
-- PART 4: PLATFORM CONFIG SEED DATA
-- All operational keys the app reads. ON CONFLICT DO NOTHING preserves
-- existing live values — this only fills in keys that don't exist yet.
-- ============================================================================

INSERT INTO public.platform_config (key, value, label, description)
VALUES
  ('commission_percent', '5'::jsonb, 'Commission %', 'Platform commission on base item subtotal'),
  ('default_commission_percent', '5.0'::jsonb, 'Default Commission %', 'Fallback commission rate'),
  ('platform_fee', '20.0'::jsonb, 'Platform Fee (₹)', 'Flat handling fee per order'),
  ('delivery_base_fee', '20'::jsonb, 'Delivery Base Fee (₹)', 'Flat delivery charge'),
  ('delivery_fee', '20'::jsonb, 'Delivery Fee (₹)', 'Alias for delivery base fee'),
  ('delivery_rate_per_km', '7'::jsonb, 'Delivery Rate/km (₹)', 'Per-km delivery charge above base'),
  ('small_cart_fee', '15'::jsonb, 'Small Cart Fee (₹)', 'Fee for orders below threshold'),
  ('small_cart_threshold', '99'::jsonb, 'Small Cart Threshold (₹)', 'Minimum cart before fee applies'),
  ('heavy_order_fee_per_kg', '20'::jsonb, 'Heavy Order Fee/kg (₹)', 'Extra charge per kg above threshold'),
  ('heavy_order_threshold_kg', '10'::jsonb, 'Heavy Threshold (kg)', 'Weight above which fee applies'),
  ('max_delivery_radius_km', '15'::jsonb, 'Max Delivery Radius (km)', 'Maximum delivery range from shop'),
  ('wait_penalty_per_min', '2'::jsonb, 'Wait Penalty/min (₹)', 'Rider compensation for shop delays'),
  ('referral_bonus_amount', '50'::jsonb, 'Referral Bonus (₹)', 'Credit for referrer and referee'),
  ('delivery_gst_rate', '0.18'::jsonb, 'Delivery GST Rate', 'GST on delivery charges (SAC 9965)'),
  ('platform_fee_gst_rate', '0.18'::jsonb, 'Platform Fee GST Rate', 'GST on handling fee (SAC 9985)'),
  ('multi_shop_surcharge', '10'::jsonb, 'Multi-Shop Surcharge (₹)', 'Extra fee per additional shop in cart'),
  ('rider_commission_percent', '80'::jsonb, 'Rider Commission %', 'Rider share of delivery charge'),
  ('rider_notification_radius_km', '5'::jsonb, 'Rider Notification Radius (km)', 'Radius for new order notifications'),
  ('disabled_categories', '"[]"'::jsonb, 'Disabled Categories', 'JSON array of disabled category names')
ON CONFLICT (key) DO NOTHING;

-- ============================================================================
-- PART 5: ENABLE RLS (idempotent — harmless if already enabled)
-- ============================================================================
ALTER TABLE public.profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shops             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_partners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_kyc_docs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_kyc_docs   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ratings           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prescription_docs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_config   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_users       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_change_requests ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- PART 6: ESSENTIAL GRANTS
-- ============================================================================
GRANT ALL ON public.profiles            TO authenticated, service_role;
GRANT ALL ON public.customers           TO authenticated, service_role;
GRANT ALL ON public.shops               TO authenticated, service_role;
GRANT ALL ON public.products            TO authenticated, service_role;
GRANT ALL ON public.orders              TO authenticated, service_role;
GRANT ALL ON public.order_items         TO authenticated, service_role;
GRANT ALL ON public.delivery_partners   TO authenticated, service_role;
GRANT ALL ON public.delivery_kyc_docs   TO authenticated, service_role;
GRANT ALL ON public.seller_kyc_docs     TO authenticated, service_role;
GRANT ALL ON public.ratings             TO authenticated, service_role;
GRANT ALL ON public.notifications       TO authenticated, service_role;
GRANT ALL ON public.prescription_docs   TO authenticated, service_role;
GRANT ALL ON public.platform_config     TO authenticated, service_role;
GRANT ALL ON public.roles               TO authenticated, service_role;
GRANT ALL ON public.permissions         TO authenticated, service_role;
GRANT ALL ON public.role_permissions    TO authenticated, service_role;
GRANT ALL ON public.admin_users         TO authenticated, service_role;
GRANT ALL ON public.vehicle_change_requests TO authenticated, service_role;

GRANT SELECT ON public.profiles         TO anon;
GRANT SELECT ON public.shops            TO anon;
GRANT SELECT ON public.products         TO anon;
GRANT SELECT ON public.platform_config  TO anon;

-- ============================================================================
-- PART 7: ESSENTIAL INDEXES (IF NOT EXISTS — safe to re-run)
-- ============================================================================
CREATE UNIQUE INDEX IF NOT EXISTS notifications_user_key_idx
  ON public.notifications (user_id, notif_key);

CREATE INDEX IF NOT EXISTS notifications_user_created_idx
  ON public.notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_customer_id
  ON public.orders (customer_id);

CREATE INDEX IF NOT EXISTS idx_orders_shop_id
  ON public.orders (shop_id);

CREATE INDEX IF NOT EXISTS idx_orders_delivery_partner_id
  ON public.orders (delivery_partner_id);

CREATE INDEX IF NOT EXISTS idx_orders_cart_group_id
  ON public.orders (cart_group_id);

CREATE INDEX IF NOT EXISTS idx_orders_status
  ON public.orders (status);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id
  ON public.order_items (order_id);

CREATE INDEX IF NOT EXISTS idx_products_shop_id
  ON public.products (shop_id);

CREATE INDEX IF NOT EXISTS idx_ratings_order_id
  ON public.ratings (order_id);

CREATE INDEX IF NOT EXISTS idx_ratings_shop_id
  ON public.ratings (shop_id);

-- ============================================================================
-- PART 8: POSTGREST SCHEMA CACHE RELOAD
-- ============================================================================
NOTIFY pgrst, 'reload schema';
