-- =============================================================================
-- Migration: Cleanup Platform Config Orphans
-- Description:
--   Removes abandoned 'delivery_discount_threshold' and 
--   'delivery_discount_amount' keys from platform_config table.
-- =============================================================================

DELETE FROM platform_config WHERE key IN ('delivery_discount_threshold', 'delivery_discount_amount');
