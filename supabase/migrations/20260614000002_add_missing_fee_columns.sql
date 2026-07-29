-- 20260614000002_add_missing_fee_columns.sql
-- Adds missing fee tracking columns to the orders table for accurate profitability analysis.

ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS small_cart_fee NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS heavy_order_fee NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS delivery_discount NUMERIC(10, 2) NOT NULL DEFAULT 0.00;

COMMENT ON COLUMN public.orders.small_cart_fee IS 'Penalty fee applied for orders below the minimum cart threshold.';
COMMENT ON COLUMN public.orders.heavy_order_fee IS 'Surcharge applied for orders exceeding the maximum base weight limit.';
COMMENT ON COLUMN public.orders.delivery_discount IS 'Promotional delivery discount applied (absorbed by the platform).';
