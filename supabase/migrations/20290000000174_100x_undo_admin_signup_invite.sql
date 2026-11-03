-- ==============================================================================
-- 100x Forensic Migration: Drop Admin Signup With Invite Code RPC
-- Migration: 20290000000174_100x_undo_admin_signup_invite.sql
-- ==============================================================================

DROP FUNCTION IF EXISTS public.admin_signup_with_invite_code(TEXT, TEXT, TEXT);
