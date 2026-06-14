-- Migration: Add Accept-First, Pay-Second order flow
-- Acceptance window: 1 minute (both seller & rider notified in parallel)
-- Payment window: 10 minutes after both accept

-- Step 1: Add new deadline columns
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS acceptance_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_deadline     TIMESTAMPTZ;

-- Step 2: Drop and recreate the status check constraint with new statuses
ALTER TABLE public.orders 
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders 
  ADD CONSTRAINT orders_status_check CHECK (status IN (
    'awaiting_acceptance',
    'awaiting_payment',
    'pending',
    'confirmed',
    'preparing',
    'ready_for_pickup',
    'picked_up',
    'out_for_delivery',
    'delivered',
    'cancelled',
    'seller_rejected',
    'partner_rejected'
  ));
