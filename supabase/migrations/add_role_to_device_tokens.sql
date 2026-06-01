-- Migration: add_role_to_device_tokens.sql
-- Description: Adds a role column to the device_tokens table to support role-based broadcast push notifications.

BEGIN;

ALTER TABLE device_tokens ADD COLUMN IF NOT EXISTS role TEXT;

-- Create an index to speed up broadcast queries by role
CREATE INDEX IF NOT EXISTS idx_device_tokens_role ON device_tokens(role);

COMMIT;
