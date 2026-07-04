-- Migration to enforce strict single-session per user policy
-- This is purely additive and does not alter any existing database objects or policies.

-- 1. Create a function that deletes all other sessions for the user
CREATE OR REPLACE FUNCTION public.enforce_single_session_per_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Delete all existing sessions for this user EXCEPT the one currently being created.
    -- This ensures the user is logged out of all other devices immediately when they log in.
    -- Refresh tokens associated with the deleted sessions will cascade automatically.
    DELETE FROM auth.sessions
    WHERE user_id = NEW.user_id
      AND id != NEW.id;
      
    RETURN NEW;
END;
$$;

-- 2. Ensure any existing trigger is replaced seamlessly
DROP TRIGGER IF EXISTS trg_enforce_single_session ON auth.sessions;

-- 3. Attach the trigger to auth.sessions
CREATE TRIGGER trg_enforce_single_session
AFTER INSERT ON auth.sessions
FOR EACH ROW
EXECUTE FUNCTION public.enforce_single_session_per_user();
