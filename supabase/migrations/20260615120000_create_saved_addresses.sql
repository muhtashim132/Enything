-- ============================================================================
-- saved_addresses: Stores user's labeled delivery addresses (Home, Office, etc.)
-- with GPS coordinates for proximity-based auto-detection (Swiggy/Zomato style).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.saved_addresses (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label         TEXT NOT NULL DEFAULT 'Home',
  custom_label  TEXT,
  flat_number   TEXT,
  address       TEXT NOT NULL,
  landmark      TEXT,
  pincode       TEXT,
  latitude      DOUBLE PRECISION NOT NULL DEFAULT 0,
  longitude     DOUBLE PRECISION NOT NULL DEFAULT 0,
  is_default    BOOLEAN DEFAULT false,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now()
);

-- RLS ────────────────────────────────────────────────────────────────────────
ALTER TABLE public.saved_addresses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "sa_select_own" ON public.saved_addresses;
DROP POLICY IF EXISTS "sa_insert_own" ON public.saved_addresses;
DROP POLICY IF EXISTS "sa_update_own" ON public.saved_addresses;
DROP POLICY IF EXISTS "sa_delete_own" ON public.saved_addresses;

CREATE POLICY "sa_select_own"
  ON public.saved_addresses FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "sa_insert_own"
  ON public.saved_addresses FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "sa_update_own"
  ON public.saved_addresses FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "sa_delete_own"
  ON public.saved_addresses FOR DELETE
  USING (auth.uid() = user_id);

-- Admin full access
DROP POLICY IF EXISTS "sa_admin_all" ON public.saved_addresses;
CREATE POLICY "sa_admin_all"
  ON public.saved_addresses FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE id = auth.uid() AND is_active = true
    )
  );

-- Grants ─────────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_addresses TO authenticated;
REVOKE ALL ON public.saved_addresses FROM anon;

-- Index ──────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_saved_addresses_user ON public.saved_addresses(user_id);

-- Limit to 10 addresses per user ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_max_saved_addresses()
RETURNS TRIGGER AS $$
BEGIN
  IF (SELECT COUNT(*) FROM public.saved_addresses WHERE user_id = NEW.user_id) >= 10 THEN
    RAISE EXCEPTION 'Maximum of 10 saved addresses allowed per user.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_max_saved_addresses ON public.saved_addresses;
CREATE TRIGGER trg_max_saved_addresses
  BEFORE INSERT ON public.saved_addresses
  FOR EACH ROW EXECUTE FUNCTION check_max_saved_addresses();
