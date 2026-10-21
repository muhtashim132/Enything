-- =============================================================================
-- Migration: 20290000000140_bulk_event_catering_schema.sql
-- Description: Phase 0 Schema for Bulk & Event Catering System (100x Fortress)
-- =============================================================================

-- 0. Ensure backward compatibility view for admin_team_members if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'admin_team_members'
  ) AND NOT EXISTS (
    SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'admin_team_members'
  ) THEN
    CREATE OR REPLACE VIEW public.admin_team_members AS
      SELECT id AS user_id, full_name, phone, is_active, created_at
      FROM public.admin_users;
  END IF;
END $$;

-- 1. Add order_type discriminator to public.orders
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_type TEXT NOT NULL DEFAULT 'instant'
  CHECK (order_type IN ('instant', 'bulk'));

CREATE INDEX IF NOT EXISTS idx_orders_order_type ON public.orders(order_type);

-- 2. Add bulk configuration columns to public.products
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS bulk_eligible BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS min_bulk_quantity INTEGER DEFAULT 20,
  ADD COLUMN IF NOT EXISTS bulk_price_tiers JSONB DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_products_bulk_eligible
  ON public.products(bulk_eligible) WHERE is_deleted = false;

-- 3. Add bulk capacity configuration columns to public.shops
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS accepts_bulk_orders BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS max_bulk_items_per_slot INTEGER DEFAULT 200,
  ADD COLUMN IF NOT EXISTS min_bulk_lead_time_hours INTEGER DEFAULT 6,
  ADD COLUMN IF NOT EXISTS max_bulk_lead_time_hours INTEGER DEFAULT 72,
  ADD COLUMN IF NOT EXISTS bulk_slot_duration_minutes INTEGER DEFAULT 60;

-- 4. Create bulk_orders metadata extension table
CREATE TABLE IF NOT EXISTS public.bulk_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,

  -- Event metadata
  event_name TEXT,
  event_date DATE NOT NULL,
  delivery_time_slot_start TIMESTAMPTZ NOT NULL,
  delivery_time_slot_end TIMESTAMPTZ NOT NULL,
  venue_address TEXT,
  venue_delivery_notes TEXT,
  contact_person_name TEXT NOT NULL,
  contact_person_phone TEXT NOT NULL,
  secondary_contact_phone TEXT,
  gate_pass_instructions TEXT,

  -- Logistics
  bulk_dispatch_group_id UUID,
  delivery_method TEXT NOT NULL DEFAULT 'platform_fleet'
    CHECK (delivery_method IN ('platform_fleet', 'merchant_delivery', 'customer_pickup')),
  total_packages_estimate INTEGER DEFAULT 1,
  vehicle_type_required TEXT DEFAULT 'any'
    CHECK (vehicle_type_required IN ('any', '2_wheeler', '3_wheeler', '4_wheeler', 'van', 'truck')),

  -- Seller response
  seller_response_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (seller_response_status IN ('pending', 'accepted', 'declined', 'modification_proposed')),
  seller_response_at TIMESTAMPTZ,
  seller_notes TEXT,
  seller_modification_proposal JSONB,

  -- Customer response to modification
  customer_modification_response TEXT
    CHECK (customer_modification_response IN ('accepted', 'rejected', NULL)),

  -- Cancellation policy
  cancellation_tier TEXT
    CHECK (cancellation_tier IN ('full_refund', 'half_refund', 'no_refund', NULL)),

  -- Kitchen prep & batch packaging tracking
  total_batches INTEGER DEFAULT 1,
  batches_packed INTEGER DEFAULT 0,
  prep_started_at TIMESTAMPTZ,
  all_batches_packed_at TIMESTAMPTZ,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bulk_orders_event_date ON public.bulk_orders(event_date);
CREATE INDEX IF NOT EXISTS idx_bulk_orders_dispatch_group ON public.bulk_orders(bulk_dispatch_group_id);
CREATE INDEX IF NOT EXISTS idx_bulk_orders_seller_status ON public.bulk_orders(seller_response_status);

ALTER TABLE public.bulk_orders ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_orders' AND policyname = 'bulk_orders_customer_select') THEN
    CREATE POLICY bulk_orders_customer_select ON public.bulk_orders
      FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.orders o WHERE o.id = bulk_orders.order_id AND o.customer_id = auth.uid())
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_orders' AND policyname = 'bulk_orders_seller_select') THEN
    CREATE POLICY bulk_orders_seller_select ON public.bulk_orders
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.shops s ON o.shop_id = s.id
          WHERE o.id = bulk_orders.order_id AND s.seller_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_orders' AND policyname = 'bulk_orders_admin_select') THEN
    CREATE POLICY bulk_orders_admin_select ON public.bulk_orders
      FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.admin_team_members WHERE user_id = auth.uid())
      );
  END IF;
END $$;

GRANT ALL ON public.bulk_orders TO service_role;
GRANT SELECT ON public.bulk_orders TO authenticated;

-- 5. Create bulk_order_slots table for shop capacity management
CREATE TABLE IF NOT EXISTS public.bulk_order_slots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  slot_date DATE NOT NULL,
  slot_start TIME NOT NULL,
  slot_end TIME NOT NULL,
  total_items_booked INTEGER NOT NULL DEFAULT 0,
  max_items_capacity INTEGER NOT NULL DEFAULT 200,

  UNIQUE(shop_id, slot_date, slot_start)
);

CREATE INDEX IF NOT EXISTS idx_bulk_slots_shop_date ON public.bulk_order_slots(shop_id, slot_date);

ALTER TABLE public.bulk_order_slots ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_order_slots' AND policyname = 'bulk_slots_read') THEN
    CREATE POLICY bulk_slots_read ON public.bulk_order_slots
      FOR SELECT USING (true);
  END IF;
END $$;

GRANT SELECT ON public.bulk_order_slots TO authenticated;
GRANT ALL ON public.bulk_order_slots TO service_role;

-- 6. Create bulk_dispatch_groups table for multi-rider/vehicle fleet dispatch
CREATE TABLE IF NOT EXISTS public.bulk_dispatch_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  dispatch_type TEXT NOT NULL DEFAULT 'multi_rider'
    CHECK (dispatch_type IN ('multi_rider', 'single_vehicle', 'merchant_delivery')),
  total_riders_needed INTEGER DEFAULT 1,
  riders_assigned INTEGER DEFAULT 0,
  vehicle_type TEXT,
  vehicle_plate_number TEXT,
  driver_name TEXT,
  driver_phone TEXT,
  dispatch_status TEXT NOT NULL DEFAULT 'planning'
    CHECK (dispatch_status IN ('planning', 'riders_assigned', 'in_transit', 'delivered', 'cancelled')),
  dispatched_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. Create bulk_dispatch_riders table for rider fleet assignments
CREATE TABLE IF NOT EXISTS public.bulk_dispatch_riders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dispatch_group_id UUID NOT NULL REFERENCES public.bulk_dispatch_groups(id) ON DELETE CASCADE,
  rider_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  packages_assigned INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'assigned'
    CHECK (status IN ('assigned', 'picked_up', 'in_transit', 'delivered', 'dropped')),
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE(dispatch_group_id, rider_id)
);

CREATE INDEX IF NOT EXISTS idx_bdr_rider_id ON public.bulk_dispatch_riders(rider_id);
CREATE INDEX IF NOT EXISTS idx_bdr_dispatch_group ON public.bulk_dispatch_riders(dispatch_group_id);

ALTER TABLE public.bulk_dispatch_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bulk_dispatch_riders ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_dispatch_groups' AND policyname = 'bdg_admin') THEN
    CREATE POLICY bdg_admin ON public.bulk_dispatch_groups
      FOR ALL USING (EXISTS (SELECT 1 FROM public.admin_team_members WHERE user_id = auth.uid()));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_dispatch_riders' AND policyname = 'bdr_admin') THEN
    CREATE POLICY bdr_admin ON public.bulk_dispatch_riders
      FOR ALL USING (EXISTS (SELECT 1 FROM public.admin_team_members WHERE user_id = auth.uid()));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_dispatch_riders' AND policyname = 'bdr_rider_select') THEN
    CREATE POLICY bdr_rider_select ON public.bulk_dispatch_riders
      FOR SELECT USING (rider_id = auth.uid());
  END IF;
END $$;

GRANT ALL ON public.bulk_dispatch_groups TO service_role;
GRANT ALL ON public.bulk_dispatch_riders TO service_role;
GRANT SELECT ON public.bulk_dispatch_groups TO authenticated;
GRANT SELECT ON public.bulk_dispatch_riders TO authenticated;

-- 8. Updated at triggers
CREATE OR REPLACE FUNCTION public.bulk_orders_updated_at_trigger()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_bulk_orders_updated_at ON public.bulk_orders;
CREATE TRIGGER set_bulk_orders_updated_at
  BEFORE UPDATE ON public.bulk_orders
  FOR EACH ROW EXECUTE FUNCTION public.bulk_orders_updated_at_trigger();

DROP TRIGGER IF EXISTS set_bulk_dispatch_groups_updated_at ON public.bulk_dispatch_groups;
CREATE TRIGGER set_bulk_dispatch_groups_updated_at
  BEFORE UPDATE ON public.bulk_dispatch_groups
  FOR EACH ROW EXECUTE FUNCTION public.bulk_orders_updated_at_trigger();
