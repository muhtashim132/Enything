-- Migration: 20260710000005_fix_delivery_partner_select.sql
-- Description: Fix "Grant SELECT error" on KYC columns for delivery partners. Purely additive.

-- Ensure table-level SELECT grants exist for authenticated users on delivery_partners
GRANT SELECT ON public.delivery_partners TO authenticated;
GRANT SELECT ON public.delivery_partners TO anon;

-- Provide additive RLS policy for delivery_partners to ensure they can select their own row
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'delivery_partners' AND policyname = 'delivery_partners_select_additive'
    ) THEN
        CREATE POLICY "delivery_partners_select_additive"
        ON public.delivery_partners FOR SELECT
        TO authenticated
        USING (id = auth.uid());
    END IF;
END
$$;
