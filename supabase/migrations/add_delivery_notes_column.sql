-- Migration: Add delivery notes column to orders table

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS delivery_notes TEXT;
