-- =============================================================================
-- Migration: Secure Payment RPC
-- Description: Revokes execute permission on client_confirm_payment from 
-- authenticated users. The RPC will now only be callable by the service_role
-- via the verify-razorpay-payment edge function.
-- =============================================================================

REVOKE EXECUTE ON FUNCTION client_confirm_payment(UUID, UUID, text, text) FROM authenticated;
