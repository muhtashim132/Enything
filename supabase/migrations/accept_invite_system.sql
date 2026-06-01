-- Migration: accept_invite_system.sql
-- Description: RPCs for processing and accepting admin invitations

BEGIN;

-- 1. Get invitation details securely
CREATE OR REPLACE FUNCTION get_invitation_details(p_token TEXT)
RETURNS TABLE (email TEXT, role_name TEXT) AS $$
BEGIN
  RETURN QUERY 
  SELECT i.email, r.name 
  FROM admin_invitations i
  JOIN roles r ON r.id = i.role_id
  WHERE i.token = p_token AND i.status = 'pending' AND i.expires_at > NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_invitation_details(TEXT) TO anon, authenticated;


-- 2. Accept invitation
CREATE OR REPLACE FUNCTION accept_admin_invitation(
  p_token TEXT,
  p_auth_user_id UUID,
  p_full_name TEXT,
  p_admin_password TEXT
) RETURNS BOOLEAN AS $$
DECLARE
  v_invitation RECORD;
BEGIN
  SELECT * INTO v_invitation FROM admin_invitations 
  WHERE token = p_token AND status = 'pending' AND expires_at > NOW();
  
  IF v_invitation IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired invitation token.';
  END IF;

  -- Create admin_users record
  INSERT INTO admin_users (id, email, full_name, role_id, admin_level, admin_password, is_active)
  VALUES (p_auth_user_id, v_invitation.email, p_full_name, v_invitation.role_id, 'admin', p_admin_password, true)
  ON CONFLICT (id) DO UPDATE 
  SET email = EXCLUDED.email, 
      full_name = EXCLUDED.full_name, 
      role_id = EXCLUDED.role_id, 
      admin_password = EXCLUDED.admin_password,
      is_active = true;

  -- Create profile record (so they don't get errors elsewhere)
  -- The app handles phone elsewhere, or falls back. We just ensure the id exists.
  INSERT INTO profiles (id, role, full_name)
  VALUES (p_auth_user_id, 'admin', p_full_name)
  ON CONFLICT (id) DO UPDATE SET role = 'admin', full_name = EXCLUDED.full_name;

  -- Update invite status
  UPDATE admin_invitations 
  SET status = 'accepted', accepted_at = NOW() 
  WHERE id = v_invitation.id;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION accept_admin_invitation(TEXT, UUID, TEXT, TEXT) TO anon, authenticated;

COMMIT;
