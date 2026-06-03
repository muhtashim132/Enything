-- Migration: add_support_ticket_enhancements.sql
-- Description: Enhances the support_tickets table with user_name, user_role, and admin_reply columns

BEGIN;

-- Add user_name column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='support_tickets' AND column_name='user_name') THEN
        ALTER TABLE public.support_tickets ADD COLUMN user_name TEXT;
    END IF;
END $$;

-- Add user_role column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='support_tickets' AND column_name='user_role') THEN
        ALTER TABLE public.support_tickets ADD COLUMN user_role TEXT;
    END IF;
END $$;

-- Add admin_reply column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='support_tickets' AND column_name='admin_reply') THEN
        ALTER TABLE public.support_tickets ADD COLUMN admin_reply TEXT;
    END IF;
END $$;

-- Add admin_id column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='support_tickets' AND column_name='admin_id') THEN
        ALTER TABLE public.support_tickets ADD COLUMN admin_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
    END IF;
END $$;

COMMIT;
