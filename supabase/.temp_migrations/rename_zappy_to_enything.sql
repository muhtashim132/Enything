-- Migration: rename_zappy_to_enything.sql
-- Description: Renames zappy_commission to enything_commission in the orders table

BEGIN;

-- Rename the column in the orders table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'orders' AND column_name = 'zappy_commission'
  ) THEN
    ALTER TABLE orders RENAME COLUMN zappy_commission TO enything_commission;
  END IF;
END $$;

COMMIT;
