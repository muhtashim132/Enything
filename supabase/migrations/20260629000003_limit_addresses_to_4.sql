-- Update trigger function to limit saved addresses to 4
CREATE OR REPLACE FUNCTION check_max_saved_addresses()
RETURNS TRIGGER AS $$
BEGIN
  IF (SELECT count(*) FROM saved_addresses WHERE user_id = NEW.user_id) >= 4 THEN
    RAISE EXCEPTION 'Maximum of 4 saved addresses allowed per user.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
