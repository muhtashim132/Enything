-- =============================================================================
-- Migration: 20290000000142_manual_quote_system.sql
-- Description: Phase 0 Schema for Manual Quotation System (100x Offline Fortress)
-- =============================================================================

-- 1. Ensure orders table allows 'manual_quote' in order_type CHECK constraint
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_order_type_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_order_type_check
  CHECK (order_type IN ('instant', 'bulk', 'manual_quote'));

-- 2. Ensure backward compatibility view for admin_team_members if missing
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

-- 3. Create bulk_quote_requests table
CREATE TABLE IF NOT EXISTS public.bulk_quote_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Customer Info
  customer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  customer_name TEXT,
  customer_phone TEXT NOT NULL,

  -- Event Details (free-text)
  event_name TEXT NOT NULL,
  event_type TEXT NOT NULL DEFAULT 'custom'
    CHECK (event_type IN (
      'birthday', 'wedding', 'corporate', 'house_party',
      'religious', 'school_event', 'custom'
    )),
  event_date DATE NOT NULL,
  estimated_guest_count INTEGER NOT NULL CHECK (estimated_guest_count > 0),
  dietary_preferences TEXT,
  requirements_description TEXT NOT NULL,

  -- Venue & Delivery
  venue_address TEXT,
  venue_lat DOUBLE PRECISION,
  venue_lng DOUBLE PRECISION,
  venue_delivery_notes TEXT,
  preferred_delivery_time TEXT,
  contact_person_name TEXT NOT NULL,
  contact_person_phone TEXT NOT NULL,
  secondary_contact_phone TEXT,
  gate_pass_instructions TEXT,

  -- Optional Preferred Shop
  preferred_shop_id UUID REFERENCES public.shops(id) ON DELETE SET NULL,
  preferred_shop_name TEXT,

  -- Lifecycle Status
  quote_status TEXT NOT NULL DEFAULT 'pending_review'
    CHECK (quote_status IN (
      'pending_review',
      'quoted',
      'customer_accepted',
      'customer_rejected',
      'payment_received',
      'order_placed',
      'expired',
      'cancelled'
    )),

  -- Admin Review
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,

  -- Quoted Financials (Offline model — simple flat amount, zero platform GST)
  quoted_amount NUMERIC(10,2) CHECK (quoted_amount IS NULL OR quoted_amount > 0),
  quoted_notes TEXT,
  quoted_valid_until TIMESTAMPTZ,
  quoted_line_items JSONB DEFAULT '[]'::jsonb,

  -- Customer Response
  customer_response_at TIMESTAMPTZ,
  customer_rejection_reason TEXT,

  -- Offline Payment Tracking
  payment_method TEXT CHECK (payment_method IS NULL OR payment_method IN ('upi', 'bank_transfer', 'cash', 'offline')),
  payment_reference TEXT,
  payment_received_at TIMESTAMPTZ,
  payment_confirmed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,

  -- Resulting Order
  resulting_order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Indexes for high-performance querying
CREATE INDEX IF NOT EXISTS idx_bqr_customer ON public.bulk_quote_requests(customer_id);
CREATE INDEX IF NOT EXISTS idx_bqr_status ON public.bulk_quote_requests(quote_status);
CREATE INDEX IF NOT EXISTS idx_bqr_event_date ON public.bulk_quote_requests(event_date);
CREATE INDEX IF NOT EXISTS idx_bqr_created_at ON public.bulk_quote_requests(created_at DESC);

-- 5. Row Level Security (RLS)
ALTER TABLE public.bulk_quote_requests ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  -- Customer can read own quote requests
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_quote_requests' AND policyname = 'bqr_customer_select') THEN
    CREATE POLICY bqr_customer_select ON public.bulk_quote_requests
      FOR SELECT USING (customer_id = auth.uid());
  END IF;

  -- Customer can insert own quote requests
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_quote_requests' AND policyname = 'bqr_customer_insert') THEN
    CREATE POLICY bqr_customer_insert ON public.bulk_quote_requests
      FOR INSERT WITH CHECK (customer_id = auth.uid());
  END IF;

  -- Customer can update own quote requests (for client cancellations or status responses if directly allowed)
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_quote_requests' AND policyname = 'bqr_customer_update') THEN
    CREATE POLICY bqr_customer_update ON public.bulk_quote_requests
      FOR UPDATE USING (customer_id = auth.uid()) WITH CHECK (customer_id = auth.uid());
  END IF;

  -- Admin team has unrestricted access
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bulk_quote_requests' AND policyname = 'bqr_admin_all') THEN
    CREATE POLICY bqr_admin_all ON public.bulk_quote_requests
      FOR ALL USING (
        EXISTS (
          SELECT 1 FROM public.admin_users
          WHERE id = auth.uid() AND is_active = true AND (is_suspended IS DISTINCT FROM true)
        ) OR public.is_super_admin(auth.uid())
      );
  END IF;
END $$;

GRANT ALL ON public.bulk_quote_requests TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.bulk_quote_requests TO authenticated;

-- 6. Trigger for updated_at
CREATE OR REPLACE FUNCTION public.handle_bqr_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_bqr_updated_at ON public.bulk_quote_requests;
CREATE TRIGGER trg_bqr_updated_at
  BEFORE UPDATE ON public.bulk_quote_requests
  FOR EACH ROW EXECUTE FUNCTION public.handle_bqr_updated_at();
