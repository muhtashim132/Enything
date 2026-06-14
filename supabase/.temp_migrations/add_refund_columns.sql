-- Add Payment and Refund columns for Razorpay integration
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS razorpay_payment_id TEXT,
  ADD COLUMN IF NOT EXISTS refund_id TEXT,
  ADD COLUMN IF NOT EXISTS refund_status TEXT;
