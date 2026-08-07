-- Restore Kamrans Restaurant (suspended shop)
-- This is purely additive: sets is_active = true for the specific shop.
-- Reversible: UPDATE shops SET is_active = false WHERE id = 'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce';
UPDATE shops SET is_active = true WHERE id = 'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce';
