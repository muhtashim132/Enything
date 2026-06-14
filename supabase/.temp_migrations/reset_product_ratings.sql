-- Update the default rating for products to 0.0
ALTER TABLE public.products ALTER COLUMN rating SET DEFAULT 0.0;

-- Reset existing products that have the hardcoded 4.0 rating back to 0.0
-- (assuming they were just created with the default value)
UPDATE public.products SET rating = 0.0 WHERE rating = 4.0;
