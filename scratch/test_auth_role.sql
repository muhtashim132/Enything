-- test script to see what auth.role() returns in normal pg query vs rest
CREATE OR REPLACE FUNCTION test_auth_role()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN COALESCE(current_setting('request.jwt.claims', true), 'NO_CLAIMS') || ' | Role: ' || COALESCE(current_user, 'NO_USER');
END;
$$;
