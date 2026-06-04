CREATE POLICY "Users update own tokens"
ON public.device_tokens FOR UPDATE
USING (auth.uid() = user_id);
