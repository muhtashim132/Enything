-- Migration: add_rider_payout_distance_columns.sql
-- Description: Adds estimated_distance_km and shop_prep_time_snapshot to orders
--              for calculating rider payout based on distance and wait time.

BEGIN;

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS estimated_distance_km NUMERIC(10,2) DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS shop_prep_time_snapshot INTEGER DEFAULT 30;

COMMIT;
