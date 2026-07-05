-- Migration to add transaction_id column to withdrawals table for tracking admin processing receipts
ALTER TABLE public.withdrawals ADD COLUMN IF NOT EXISTS transaction_id text;

-- Since the table is already granted correctly, this column will automatically be included in SELECT and UPDATE queries for the authenticated roles that already have access.
