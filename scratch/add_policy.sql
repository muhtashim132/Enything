-- Add policy to allow anyone to read platform_config
BEGIN;
  DO $$ 
  BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'platform_config' AND policyname = 'Enable read access for all users on platform_config'
    ) THEN
        CREATE POLICY "Enable read access for all users on platform_config" ON platform_config FOR SELECT USING (true);
    END IF;
  END $$;
  
  ALTER TABLE platform_config ENABLE ROW LEVEL SECURITY;
COMMIT;
