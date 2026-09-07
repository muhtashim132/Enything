-- =============================================================================
-- Phase 113: Fix Ratings Foreign Keys on Account Deletion
-- =============================================================================

-- Allow user deletion without foreign key restriction violations on ratings
ALTER TABLE public.ratings DROP CONSTRAINT IF EXISTS ratings_ratee_id_fkey;
ALTER TABLE public.ratings ADD CONSTRAINT ratings_ratee_id_fkey 
  FOREIGN KEY (ratee_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.ratings DROP CONSTRAINT IF EXISTS ratings_rater_id_fkey;
ALTER TABLE public.ratings ADD CONSTRAINT ratings_rater_id_fkey 
  FOREIGN KEY (rater_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Also ensure customer_id and delivery_partner_id cascade or set null
ALTER TABLE public.ratings DROP CONSTRAINT IF EXISTS ratings_customer_id_fkey;
ALTER TABLE public.ratings ADD CONSTRAINT ratings_customer_id_fkey 
  FOREIGN KEY (customer_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE public.ratings DROP CONSTRAINT IF EXISTS ratings_delivery_partner_id_fkey;
ALTER TABLE public.ratings ADD CONSTRAINT ratings_delivery_partner_id_fkey 
  FOREIGN KEY (delivery_partner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
