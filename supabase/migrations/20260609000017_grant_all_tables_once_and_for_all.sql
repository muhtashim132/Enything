-- ============================================================================
-- Migration: 20260609000017_grant_all_tables_once_and_for_all.sql
-- Description: Restores standard Supabase table-level privileges.
--              Column-level privileges break `supabase.from('table').select()` 
--              (which acts as SELECT *) in the Flutter app.
--              This script grants ALL table-level permissions to authenticated 
--              and anon roles for EVERY table in the public schema, 
--              relying strictly on Row Level Security (RLS) to secure data.
-- ============================================================================

DO $$
DECLARE
    r RECORD;
BEGIN
    -- Loop through all tables in the public schema
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        -- Grant standard Supabase table-level privileges
        EXECUTE format('GRANT ALL ON TABLE public.%I TO postgres, anon, authenticated, service_role;', r.tablename);
    END LOOP;
    
    -- Also loop through all sequences and grant usage (for auto-increment IDs)
    FOR r IN (SELECT sequencename FROM pg_sequences WHERE schemaname = 'public') LOOP
        EXECUTE format('GRANT ALL ON SEQUENCE public.%I TO postgres, anon, authenticated, service_role;', r.sequencename);
    END LOOP;
END;
$$;
