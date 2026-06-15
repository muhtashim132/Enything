-- ============================================================================
-- Create webhook trigger for background removal Edge Function
-- ============================================================================

-- Drop the trigger if it exists
DROP TRIGGER IF EXISTS trigger_remove_background ON storage.objects;

-- Create the trigger using supabase_functions.http_request
CREATE TRIGGER trigger_remove_background
  AFTER INSERT ON storage.objects
  FOR EACH ROW
  EXECUTE FUNCTION supabase_functions.http_request(
    'https://mmdrgcuaetwohflcvzou.supabase.co/functions/v1/remove-background',
    'POST',
    '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1tZHJnY3VhZXR3b2hmbGN2em91Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Nzk5NzUxMCwiZXhwIjoyMDkzNTczNTEwfQ.rzX0mupREQDLgTgZLISBocfdtWH-IPVE0bsz7oc_Z8c"}',
    '{}',
    '5000'
  );
