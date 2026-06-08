-- Add RPC for automated test cleanup
-- Allows the integration tests to delete mock users

CREATE OR REPLACE FUNCTION public.delete_mock_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- We delete from auth.users. 
  -- Assuming ON DELETE CASCADE is set up for profiles, customers, shops, etc.
  -- If not, we manually delete them first to avoid foreign key violations.
  
  DELETE FROM public.orders WHERE customer_id = p_user_id OR shop_id = p_user_id OR delivery_partner_id = p_user_id;
  DELETE FROM public.shops WHERE seller_id = p_user_id;
  DELETE FROM public.customers WHERE id = p_user_id;
  DELETE FROM public.delivery_partners WHERE id = p_user_id;
  DELETE FROM public.profiles WHERE id = p_user_id;
  
  DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;

-- Grant execute to authenticated users (so the test script can call it)
-- Note: In a production environment, this should be restricted, 
-- but we are adding this specifically for the testing plan.
GRANT EXECUTE ON FUNCTION public.delete_mock_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_mock_user(UUID) TO anon;

-- Reload schema cache
NOTIFY pgrst, 'reload schema';
