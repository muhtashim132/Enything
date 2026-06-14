-- ============================================================================
-- Migration: fix_delivery_partner_column_privileges.sql
-- Description: Grants SELECT privileges to authenticated users for columns
--              added to the delivery_partners table AFTER the initial RLS 
--              script was run. This allows riders to view their own vehicle
--              and KYC documents.
-- ============================================================================

DO $$
BEGIN
  -- Grant SELECT on the newly added vehicle and document columns.
  -- These columns are protected by Row Level Security (RLS) so users
  -- can still only see their own row.
  GRANT SELECT (vehicle_type, vehicle_reg_number, driving_license, pan_number) 
  ON public.delivery_partners TO authenticated;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error granting permissions: %', SQLERRM;
END;
$$;
