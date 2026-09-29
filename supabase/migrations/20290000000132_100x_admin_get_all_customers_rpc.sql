-- Migration: 20290000000132_100x_admin_get_all_customers_rpc.sql
-- Description: 100x Dedicated Admin Customer RPC with Strict Role Separation
-- Ensures the Customers tab in Admin Panel exclusively returns pure customers,
-- completely excluding sellers, delivery partners (riders), and admins.

DROP FUNCTION IF EXISTS public.admin_get_all_customers();

CREATE OR REPLACE FUNCTION public.admin_get_all_customers()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- 1. Strict Authorization Barrier: caller must be an active admin
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- 2. Aggregate customer profiles with order counts and active status
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'full_name', COALESCE(NULLIF(p.full_name, ''), NULLIF(p.name, ''), 'Customer'),
      'phone', COALESCE(p.phone, ''),
      'email', COALESCE(p.email, ''),
      'role', 'customer',
      'avatar_url', p.avatar_url,
      'created_at', p.created_at,
      'is_active', COALESCE(p.is_active, true),
      'total_orders', COALESCE(
        (SELECT COUNT(*) FROM public.orders o WHERE o.customer_id = p.id), 0
      )
    )
    ORDER BY p.created_at DESC
  ) INTO v_result
  FROM public.profiles p
  WHERE (p.role = 'customer' OR p.role IS NULL)
    AND p.id NOT IN (SELECT seller_id FROM public.shops WHERE seller_id IS NOT NULL)
    AND p.id NOT IN (SELECT id FROM public.delivery_partners WHERE id IS NOT NULL)
    AND p.id NOT IN (SELECT id FROM public.admin_users WHERE id IS NOT NULL);

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- Grant execution to authenticated users and service_role
GRANT EXECUTE ON FUNCTION public.admin_get_all_customers() TO authenticated, service_role;
