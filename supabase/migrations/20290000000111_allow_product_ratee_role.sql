-- =============================================================================
-- Migration: 20290000000111_allow_product_ratee_role.sql
-- Description: Allow 'product' and 'delivery_partner' in ratings_ratee_role_check constraint.
--              In the Flutter customer review flow, products are rated with ratee_role = 'product'.
-- =============================================================================

ALTER TABLE public.ratings 
DROP CONSTRAINT IF EXISTS ratings_ratee_role_check;

ALTER TABLE public.ratings 
ADD CONSTRAINT ratings_ratee_role_check 
CHECK (ratee_role = ANY (ARRAY['customer'::text, 'seller'::text, 'delivery'::text, 'delivery_partner'::text, 'product'::text]));
