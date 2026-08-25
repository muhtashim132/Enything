-- ============================================================================
-- 100x Migration: Cleanup Temporary Test Entities Created by Automated Tests
-- ============================================================================

DO $$
BEGIN
    -- Delete any test order items
    DELETE FROM public.order_items
    WHERE order_id IN (
        SELECT id FROM public.orders 
        WHERE shop_id IN (
            SELECT id FROM public.shops 
            WHERE name ILIKE '%CustomerTestShop%' 
               OR name ILIKE '%TestShop%' 
               OR name ILIKE '%Shop_+%'
        )
    );

    -- Delete any test orders
    DELETE FROM public.orders
    WHERE shop_id IN (
        SELECT id FROM public.shops 
        WHERE name ILIKE '%CustomerTestShop%' 
           OR name ILIKE '%TestShop%' 
           OR name ILIKE '%Shop_+%'
    );

    -- Delete any test products
    DELETE FROM public.products
    WHERE name ILIKE '%CustomerTestProduct%'
       OR name ILIKE '%TestProduct%'
       OR shop_id IN (
            SELECT id FROM public.shops 
            WHERE name ILIKE '%CustomerTestShop%' 
               OR name ILIKE '%TestShop%' 
               OR name ILIKE '%Shop_+%'
       );

    -- Delete any test shops
    DELETE FROM public.shops
    WHERE name ILIKE '%CustomerTestShop%' 
       OR name ILIKE '%TestShop%' 
       OR name ILIKE '%Shop_+%';

    -- Delete any test delivery partner records
    DELETE FROM public.delivery_partners
    WHERE id IN (
        SELECT id FROM public.profiles
        WHERE phone ILIKE '%9822222%' OR phone ILIKE '%9722222%' OR phone ILIKE '%9622222%' OR phone ILIKE '%9422222%' OR phone ILIKE '%9744444%' OR phone ILIKE '%9644444%'
    );

    -- Delete any test profiles
    DELETE FROM public.profiles
    WHERE phone ILIKE '%9822222%' OR phone ILIKE '%9722222%' OR phone ILIKE '%9622222%' OR phone ILIKE '%9422222%' OR phone ILIKE '%9744444%' OR phone ILIKE '%9644444%';

END $$;
