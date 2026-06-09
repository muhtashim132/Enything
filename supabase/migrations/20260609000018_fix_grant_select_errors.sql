-- Migration: 20260609000018_fix_grant_select_errors.sql
-- Description: Fixes "missing rows and columns" and "Grant SELECT" errors caused by column-level privileges.
--              This ensures that the Flutter app can execute `.select()` without permission denied errors,
--              relying on existing Row Level Security (RLS) instead of column-level restrictions.

DO $$
BEGIN
    -- Explicitly restore standard table-level SELECT, INSERT, UPDATE, DELETE 
    -- to authenticated users so they don't encounter Grant SELECT errors.
    
    -- Fix shops
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.shops TO authenticated;
    
    -- Fix delivery_partners
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.delivery_partners TO authenticated;
    
    -- Fix orders
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.orders TO authenticated;
    
    -- Fix order_items
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.order_items TO authenticated;
    
    -- Fix notifications
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
    
    -- Fix profiles
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
    
    -- Fix products
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.products TO authenticated;
END;
$$;
