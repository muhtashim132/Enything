-- Migration: add_device_tokens_table
-- Stores FCM device tokens for push notification delivery.
-- Each user can have multiple tokens (multiple devices).

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id         UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token      TEXT        NOT NULL,
  platform   TEXT        NOT NULL DEFAULT 'android', -- 'android' | 'ios'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, token)
);

-- Index for fast user lookup
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON public.device_tokens(user_id);

-- RLS: Only the service role (Edge Functions) can write.
-- Users can read their own tokens via the client.
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own tokens"
  ON public.device_tokens FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users upsert own tokens"
  ON public.device_tokens FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users delete own tokens"
  ON public.device_tokens FOR DELETE
  USING (auth.uid() = user_id);
