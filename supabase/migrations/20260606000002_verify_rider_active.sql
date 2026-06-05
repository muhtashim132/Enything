-- Verify: check delivery_partners is_active status after migration
SELECT id, is_active, is_available, verification_status FROM public.delivery_partners;
