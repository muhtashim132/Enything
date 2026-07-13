-- Migration: Additive sync of heavy order fee key
-- Reason: The backend calculates the heavy order fee using a strict per-kg multiplier and expects the key 'heavy_order_fee_per_kg'. 
-- The legacy UI was using the key 'heavy_order_fee'. This additive migration renames any existing legacy key to the strict key 
-- to ensure the backend multiplier logic correctly utilizes the admin's configured value.

UPDATE platform_config 
SET key = 'heavy_order_fee_per_kg' 
WHERE key = 'heavy_order_fee';
