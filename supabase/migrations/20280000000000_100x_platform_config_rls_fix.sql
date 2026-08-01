-- 100x FIX: Allow public read access to platform_config
-- If this policy is missing, PlatformConfigProvider receives an empty array and fails silently,
-- leaving the frontend with hardcoded defaults that drift from the backend over time.

DO $$ 
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM pg_policies 
      WHERE tablename = 'platform_config' AND policyname = 'Enable public read access on platform_config'
  ) THEN
      CREATE POLICY "Enable public read access on platform_config" 
      ON platform_config 
      FOR SELECT 
      USING (true);
  END IF;
END $$;

ALTER TABLE platform_config ENABLE ROW LEVEL SECURITY;
