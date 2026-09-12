-- =============================================================================
-- Migration: 20290000000125_100x_profile_active_and_dashboard_sync.sql
-- =============================================================================
-- Description: Strictly additive. Ensures profiles has is_active boolean column
-- with DEFAULT true so customer suspension guards and admin_toggle_active work
-- reliably without impacting any existing accounts.
-- =============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
