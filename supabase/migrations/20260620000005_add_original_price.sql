-- ============================================================================
-- Migration: 20260620000005_add_original_price.sql
-- Description: Adds 'original_price' column to the 'products' table for the 
--              discount feature if it does not already exist. 
--              Safe, idempotent, and does not alter preexisting logic.
-- ============================================================================

DO $$
BEGIN
    -- Add the column safely
    IF NOT EXISTS (
        SELECT FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'products' 
          AND column_name = 'original_price'
    ) THEN
        ALTER TABLE public.products ADD COLUMN original_price numeric;
    END IF;
END $$;

-- Explicitly ensure authenticated users have UPDATE access to this new column 
-- (Assuming they already have UPDATE on the table, this might be redundant but safe)
-- Note: the table-level GRANT UPDATE ON public.products TO authenticated already covers new columns.
-- Notify PostgREST cache reload
NOTIFY pgrst, 'reload schema';
