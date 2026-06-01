-- Enable Supabase Realtime for tables used by the Super Admin notifications
-- This allows the admin dashboard to receive live inserts for KYC and complaints

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

-- Add 'support_tickets' to realtime publication if not already present AND if table exists
DO $$
BEGIN
    IF EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'support_tickets'
    ) AND NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'support_tickets'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.support_tickets;
    END IF;
END $$;

COMMIT;
