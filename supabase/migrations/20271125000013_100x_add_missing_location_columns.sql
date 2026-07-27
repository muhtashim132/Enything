-- Migration 20271125000008_100x_add_missing_location_columns.sql
-- Adds the missing 'last_location_lat' and 'last_location_lng' columns
-- to the delivery_partners table. 
-- This fixes the RPC error in update_rider_location_bg.

ALTER TABLE public.delivery_partners 
ADD COLUMN IF NOT EXISTS last_location_lat NUMERIC,
ADD COLUMN IF NOT EXISTS last_location_lng NUMERIC;
