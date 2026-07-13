-- ============================================================================
-- Migration: 20260713164000_enable_realtime_for_platform_config.sql
-- Description: Enables Supabase Realtime for `platform_config` and `tax_config`
--              so that customer and admin apps instantly sync fee changes.
-- ============================================================================

BEGIN;

-- Add 'platform_config' to realtime publication if not already present AND if table exists
DO $$
BEGIN
    IF EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'platform_config'
    ) AND NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'platform_config'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.platform_config;
    END IF;
END $$;

-- Add 'tax_config' to realtime publication if not already present AND if table exists
DO $$
BEGIN
    IF EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'tax_config'
    ) AND NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'tax_config'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.tax_config;
    END IF;
END $$;

COMMIT;
