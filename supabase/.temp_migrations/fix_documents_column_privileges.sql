-- ============================================================================
-- Migration: fix_documents_column_privileges.sql
-- Description: Grants SELECT privileges for aadhar_number to allow 
--              the delivery partner to view their Aadhaar on the Documents page.
-- ============================================================================

DO $$
BEGIN
  GRANT SELECT (aadhar_number) ON public.delivery_partners TO authenticated;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error granting permissions: %', SQLERRM;
END;
$$;
