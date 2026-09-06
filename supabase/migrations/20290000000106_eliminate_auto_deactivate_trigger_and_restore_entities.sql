-- ============================================================================
-- Migration: 20290000000106_eliminate_auto_deactivate_trigger_and_restore_entities.sql
-- Description: Permanently eliminate silent shop/rider suspensions by dropping
--   the rogue trigger on device_tokens and restoring legitimate entities.
-- Constraints: Zero Flutter code changes, zero new triggers, purely surgical.
-- ============================================================================

BEGIN;

-- 1. DROP THE SINGLE ROGUE TRIGGER AND FUNCTION
-- This trigger erroneously marked shops and riders is_active = false whenever FCM tokens cleared or rotated.
DROP TRIGGER IF EXISTS tr_auto_deactivate_shop_on_no_devices ON public.device_tokens;
DROP FUNCTION IF EXISTS public.auto_deactivate_shop_on_no_devices();

-- 2. RESTORE ALL LEGITIMATE VERIFIED SHOPS
UPDATE public.shops
SET 
    is_active = true,
    is_open = true,
    is_accepting_orders = true,
    verification_status = 'verified'
WHERE id IN (
    'e2e0d5ba-94b6-4f02-ac29-2b3a299df4ce', -- Kamrans Restaurant
    '6efc28aa-d475-45d0-aa0c-8f37a26f2bcc', -- Musadiq clothes Store
    'a1cb8f85-9c53-4f73-ad6c-aea457aec27d', -- Mubashir Medical Shop
    '04d8c6b9-b5bb-49ab-9a81-a5116984c798', -- Valley Choice
    'da7c5b00-1c7d-4737-b7f1-59af89556f3d', -- Haji Super Mart
    'ccb3efb5-aa14-4df5-94f9-90b6f6cdedaf', -- Mirhart Studio
    '026e8cad-9c84-46c1-8b79-588a446b88a3'  -- Raashids shop
);

-- 3. RESTORE ALL LEGITIMATE DELIVERY PARTNERS
UPDATE public.delivery_partners
SET 
    is_active = true,
    is_available = true,
    is_accepting_orders = true,
    verification_status = 'verified'
WHERE id IN (
    '99da01b7-4f89-445d-b8a5-48a8b59cbcc6', -- Muhtashim KAMRAN
    '1ad97706-0830-48c0-a001-785a5bc6a076', -- Tasneema
    '821a4442-34da-4032-b31c-bc5a8d0fa06f'  -- Apple Reviewer
) OR verification_status = 'verified';

-- 4. RE-SYNC OPERATING HOURS
SELECT public.sync_shop_accepting_orders_by_hours();

-- 5. RECORD MIGRATION IN REGISTRY
INSERT INTO supabase_migrations.schema_migrations (version, statements)
VALUES ('20290000000106', ARRAY['eliminate_auto_deactivate_trigger_and_restore_entities'])
ON CONFLICT (version) DO NOTHING;

COMMIT;
