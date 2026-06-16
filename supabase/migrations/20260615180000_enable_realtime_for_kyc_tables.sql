-- ============================================================================
-- Migration: 20260615180000_enable_realtime_for_kyc_tables.sql
-- Description: Enables Supabase Realtime for the `shops` and `delivery_partners`
--              tables. Without this, the frontend cannot listen for KYC 
--              approval events via WebSockets. Also sets REPLICA IDENTITY FULL
--              so the complete row is broadcasted.
-- ============================================================================

BEGIN;

-- Add 'shops' to realtime publication if not already present AND if table exists
DO $$
BEGIN
    IF EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'shops'
    ) AND NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'shops'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.shops;
    END IF;
END $$;

-- Add 'delivery_partners' to realtime publication if not already present AND if table exists
DO $$
BEGIN
    IF EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'delivery_partners'
    ) AND NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'delivery_partners'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.delivery_partners;
    END IF;
END $$;

-- Ensure that UPDATE operations send the complete row in the payload, 
-- preventing null column bugs on the frontend.
ALTER TABLE public.shops REPLICA IDENTITY FULL;
ALTER TABLE public.delivery_partners REPLICA IDENTITY FULL;

COMMIT;
