-- Migration: enable_realtime_for_orders.sql
-- Description: Enables Supabase Realtime for the orders table to power live rider tracking for customers and sellers.

BEGIN;

-- Add 'orders' to realtime publication if not already present AND if table exists
DO $$
BEGIN
    IF EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'orders'
    ) AND NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'orders'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
    END IF;
END $$;

COMMIT;
