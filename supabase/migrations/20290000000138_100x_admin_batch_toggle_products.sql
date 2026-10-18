-- Migration: 20290000000138_100x_admin_batch_toggle_products.sql
-- Description: 100% Additive RPC allowing Platform Admins and Super Admins to batch toggle
-- all products for a shop between Available and Hidden/Out of Stock with zero impact on in-flight orders
-- and strictly adhering to the soft-delete rule (never modifying is_deleted = true rows).

CREATE OR REPLACE FUNCTION public.admin_batch_toggle_products(
  p_shop_id UUID,
  p_is_available BOOLEAN
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated_count int;
BEGIN
  -- 1. Strict Authorization Barrier: Admin check
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- 2. Validate shop existence
  IF NOT EXISTS (SELECT 1 FROM public.shops WHERE id = p_shop_id) THEN
    RAISE EXCEPTION 'Shop with ID % not found', p_shop_id;
  END IF;

  -- 3. Comply strictly with Soft Delete Rule: only update products where is_deleted = false
  UPDATE public.products
  SET is_available = p_is_available,
      updated_at = NOW()
  WHERE shop_id = p_shop_id
    AND is_deleted = false;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  RETURN v_updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_batch_toggle_products(UUID, BOOLEAN) TO authenticated, service_role;
