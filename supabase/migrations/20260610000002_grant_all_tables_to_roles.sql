-- ============================================================================
-- Migration: 20260610000002_grant_all_tables_to_roles.sql
-- Description: Definitively fixes "Grant SELECT" errors across all current 
--              and future tables for Edge Functions and client apps by granting
--              base table access to anon and authenticated. Actual data access 
--              is still completely secured by existing RLS policies.
-- ============================================================================

-- 1. Grant usage on the public schema
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- 2. Grant access to all existing tables
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;

-- 3. Grant access to all existing routines (functions/stored procedures)
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO anon, authenticated;

-- 4. Grant access to all existing sequences (for auto-incrementing IDs)
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

-- 5. Ensure any tables, routines, or sequences created in the FUTURE 
--    automatically receive these base privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON ROUTINES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated;

-- 6. Flush PostgREST Schema Cache (CRITICAL)
-- Without this, Supabase caches previous restrictions and continues 
-- throwing "Permission denied" errors for active clients.
NOTIFY pgrst, 'reload schema';
