-- Fix: Add missing UPDATE policy so that upsert() from the Flutter app works
-- Without this policy, the app silently fails to save the FCM token
-- which means the Edge Function finds no tokens and never calls Firebase

CREATE POLICY "Users update own tokens"
  ON public.device_tokens FOR UPDATE
  USING (auth.uid() = user_id);

-- Also grant service_role full access so the Edge Function can always read tokens
-- even if RLS blocks the anon key
CREATE POLICY "Service role full access"
  ON public.device_tokens FOR ALL
  USING (auth.role() = 'service_role');
