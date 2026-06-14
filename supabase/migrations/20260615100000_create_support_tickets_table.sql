-- ================================================================
-- Migration: create_support_tickets_table (idempotent / safe to re-run)
-- Creates the support_tickets table used by FaqSupportPage.
-- Uses IF NOT EXISTS and DROP ... IF EXISTS to be fully re-runnable.
-- ================================================================

CREATE TABLE IF NOT EXISTS public.support_tickets (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_name   TEXT        NOT NULL DEFAULT '',
  user_role   TEXT        NOT NULL DEFAULT 'customer',
  subject     TEXT        NOT NULL,
  body        TEXT        NOT NULL,
  priority    TEXT        NOT NULL DEFAULT 'normal'
                CHECK (priority IN ('normal', 'high', 'urgent')),
  status      TEXT        NOT NULL DEFAULT 'open'
                CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
  admin_reply TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Indexes ──────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_support_tickets_user_id
  ON public.support_tickets (user_id);

CREATE INDEX IF NOT EXISTS idx_support_tickets_status
  ON public.support_tickets (status);

-- ── Row-Level Security ───────────────────────────────────────────
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- Drop existing policies first so re-running is always safe
DROP POLICY IF EXISTS "support_tickets_insert_own" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_select_own" ON public.support_tickets;

-- Authenticated users can insert their own tickets
CREATE POLICY "support_tickets_insert_own"
  ON public.support_tickets
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Authenticated users can select only their own tickets
CREATE POLICY "support_tickets_select_own"
  ON public.support_tickets
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- ── Grants ───────────────────────────────────────────────────────
GRANT SELECT, INSERT ON public.support_tickets TO authenticated;
GRANT ALL             ON public.support_tickets TO service_role;
