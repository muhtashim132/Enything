-- Migration: add_otp_tokens_table
-- Creates the otp_tokens table used by the send-otp and verify-otp Edge Functions.
-- OTPs are stored as SHA-256 hashes with phone, expiry, and attempt count.

CREATE TABLE IF NOT EXISTS public.otp_tokens (
  id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  phone       TEXT        NOT NULL,
  otp_hash    TEXT        NOT NULL,
  expires_at  TIMESTAMPTZ NOT NULL,
  attempts    INT         NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast phone lookups
CREATE INDEX IF NOT EXISTS idx_otp_tokens_phone ON public.otp_tokens(phone);

-- ─── Row Level Security ────────────────────────────────────────────────────
-- Only Edge Functions (service role) should access this table.
-- No access for anon or authenticated users via the client.
ALTER TABLE public.otp_tokens ENABLE ROW LEVEL SECURITY;

-- Deny all direct client access (Edge Functions use service role, bypassing RLS)
CREATE POLICY "No direct client access" ON public.otp_tokens
  FOR ALL USING (false);

-- ─── Auto-cleanup of expired tokens ───────────────────────────────────────
-- Scheduled cleanup: run a cron job or rely on Edge Function cleanup.
-- This function can be called by pg_cron if enabled on your Supabase project.
CREATE OR REPLACE FUNCTION public.cleanup_expired_otp_tokens()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
  DELETE FROM public.otp_tokens WHERE expires_at < NOW();
$$;
