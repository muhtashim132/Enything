-- Add product inventory and unit details for weight/volume calculations

ALTER TABLE products
ADD COLUMN IF NOT EXISTS weight_per_unit numeric DEFAULT 0.5,
ADD COLUMN IF NOT EXISTS unit_type text DEFAULT 'pieces',
ADD COLUMN IF NOT EXISTS total_quantity integer DEFAULT NULL;
