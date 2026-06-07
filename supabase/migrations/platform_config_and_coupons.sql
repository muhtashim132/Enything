-- Migration: platform_config_and_coupons.sql
-- Description: Creates tables for live platform configuration and coupon management

BEGIN;

-- 1. Platform Config Table
CREATE TABLE IF NOT EXISTS platform_config (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  label TEXT,
  description TEXT,
  updated_by UUID REFERENCES admin_users(id),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed initial default values (matching hardcoded values in the app)
INSERT INTO platform_config (key, value, label, description) VALUES
  ('commission_percent', '5', 'Commission %', 'Platform commission on base item subtotal'),
  ('platform_fee', '15', 'Platform Fee (₹)', 'Flat handling fee per order'),
  ('small_cart_fee', '15', 'Small Cart Fee (₹)', 'Fee for orders below the small cart threshold'),
  ('small_cart_threshold', '99', 'Small Cart Threshold (₹)', 'Orders below this amount attract the small cart fee'),
  ('heavy_order_fee', '20', 'Heavy Order Fee (₹)', 'Extra charge for heavy orders'),
  ('heavy_order_threshold_kg', '10', 'Heavy Order Threshold (kg)', 'Weight above which the heavy order fee applies'),
  ('delivery_discount_threshold', '999', 'Delivery Discount Threshold (₹)', 'Orders above this get a delivery discount'),
  ('delivery_discount_amount', '15', 'Delivery Discount Amount (₹)', 'Discount applied on qualifying orders'),
  ('max_delivery_radius_km', '15', 'Max Delivery Radius (km)', 'Maximum delivery range from shop'),
  ('referral_bonus_amount', '50', 'Referral Bonus (₹)', 'Wallet credit given to both referrer and referee')
ON CONFLICT (key) DO NOTHING;

-- Enable RLS on platform_config
ALTER TABLE platform_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "config_read_all" ON platform_config
  FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "config_write_superadmin" ON platform_config
  FOR ALL TO authenticated 
  USING (is_super_admin(auth.uid()))
  WITH CHECK (is_super_admin(auth.uid()));

-- 2. Coupons Table
CREATE TABLE IF NOT EXISTS coupons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  description TEXT,
  discount_type TEXT NOT NULL CHECK (discount_type IN ('flat', 'percent')),
  discount_value NUMERIC NOT NULL,
  min_order_value NUMERIC DEFAULT 0,
  max_discount_cap NUMERIC,          -- For percent coupons
  usage_limit INT,                   -- NULL = unlimited
  usage_count INT DEFAULT 0,
  valid_from TIMESTAMPTZ DEFAULT NOW(),
  valid_until TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT TRUE,
  created_by UUID REFERENCES admin_users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on coupons
ALTER TABLE coupons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coupons_read_all" ON coupons
  FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "coupons_write_superadmin" ON coupons
  FOR ALL TO authenticated 
  USING (is_super_admin(auth.uid()))
  WITH CHECK (is_super_admin(auth.uid()));

-- 3. Audit Log integration (Optional trigger for platform_config)
-- (We'll log changes from the Dart client side for simplicity, but we could add a trigger here)

COMMIT;
