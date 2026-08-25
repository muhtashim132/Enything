-- 100x Definitive Database Cleanup: Force purge test shops, mock products, and reviewer accounts

-- 1. Drop magic reviewer auto-accept RPC function
DROP FUNCTION IF EXISTS public.magic_reviewer_auto_accept(uuid[]);
DROP FUNCTION IF EXISTS public.magic_reviewer_auto_accept(UUID[]);

-- 2. Clean reviews table for test shops
DELETE FROM public.reviews 
WHERE shop_id IN (
  SELECT id FROM public.shops 
  WHERE name ILIKE 'Amit Medical Store%'
     OR name ILIKE 'Test Shop%'
     OR name ILIKE 'CustomerTestShop_%'
     OR name ILIKE 'SellerShop_+919733333%'
     OR name ILIKE 'Shop_+919722222%'
     OR name ILIKE 'Shop_+919622222%'
     OR name ILIKE 'Shop_+919422222%'
     OR name ILIKE 'Shop +918888887%'
     OR name ILIKE 'Finance Test Shop%'
     OR name = 'bsbsnd'
) OR order_id IN (
  SELECT id FROM public.orders
  WHERE shop_id IN (
    SELECT id FROM public.shops 
    WHERE name ILIKE 'Amit Medical Store%'
       OR name ILIKE 'Test Shop%'
       OR name ILIKE 'CustomerTestShop_%'
       OR name ILIKE 'SellerShop_+919733333%'
       OR name ILIKE 'Shop_+919722222%'
       OR name ILIKE 'Shop_+919622222%'
       OR name ILIKE 'Shop_+919422222%'
       OR name ILIKE 'Shop +918888887%'
       OR name ILIKE 'Finance Test Shop%'
       OR name = 'bsbsnd'
  )
);

-- Clean ratings if table exists
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ratings') THEN
    DELETE FROM public.ratings
    WHERE shop_id IN (
      SELECT id FROM public.shops 
      WHERE name ILIKE 'Amit Medical Store%'
         OR name ILIKE 'Test Shop%'
         OR name ILIKE 'CustomerTestShop_%'
         OR name ILIKE 'SellerShop_+919733333%'
         OR name ILIKE 'Shop_+919722222%'
         OR name ILIKE 'Shop_+919622222%'
         OR name ILIKE 'Shop_+919422222%'
         OR name ILIKE 'Shop +918888887%'
         OR name ILIKE 'Finance Test Shop%'
         OR name = 'bsbsnd'
    );
  END IF;
END $$;

-- 3. Delete order items for test products or test shop orders
DELETE FROM public.order_items
WHERE product_id IN (
  SELECT id FROM public.products
  WHERE shop_id IN (
    SELECT id FROM public.shops 
    WHERE name ILIKE 'Amit Medical Store%'
       OR name ILIKE 'Test Shop%'
       OR name ILIKE 'CustomerTestShop_%'
       OR name ILIKE 'SellerShop_+919733333%'
       OR name ILIKE 'Shop_+919722222%'
       OR name ILIKE 'Shop_+919622222%'
       OR name ILIKE 'Shop_+919422222%'
       OR name ILIKE 'Shop +918888887%'
       OR name ILIKE 'Finance Test Shop%'
       OR name = 'bsbsnd'
  ) OR name ILIKE 'Test Item%'
    OR name ILIKE 'Test Item Shop%'
    OR name ILIKE 'Stock Test%'
    OR name ILIKE 'Refund Test Item%'
    OR name ILIKE 'Item S1%'
    OR name ILIKE 'Item S2%'
) OR order_id IN (
  SELECT id FROM public.orders
  WHERE shop_id IN (
    SELECT id FROM public.shops 
    WHERE name ILIKE 'Amit Medical Store%'
       OR name ILIKE 'Test Shop%'
       OR name ILIKE 'CustomerTestShop_%'
       OR name ILIKE 'SellerShop_+919733333%'
       OR name ILIKE 'Shop_+919722222%'
       OR name ILIKE 'Shop_+919622222%'
       OR name ILIKE 'Shop_+919422222%'
       OR name ILIKE 'Shop +918888887%'
       OR name ILIKE 'Finance Test Shop%'
       OR name = 'bsbsnd'
  )
);

-- 4. Delete orders for test shops
DELETE FROM public.orders
WHERE shop_id IN (
  SELECT id FROM public.shops 
  WHERE name ILIKE 'Amit Medical Store%'
     OR name ILIKE 'Test Shop%'
     OR name ILIKE 'CustomerTestShop_%'
     OR name ILIKE 'SellerShop_+919733333%'
     OR name ILIKE 'Shop_+919722222%'
     OR name ILIKE 'Shop_+919622222%'
     OR name ILIKE 'Shop_+919422222%'
     OR name ILIKE 'Shop +918888887%'
     OR name ILIKE 'Finance Test Shop%'
     OR name = 'bsbsnd'
);

-- 5. Delete all test products
DELETE FROM public.products
WHERE shop_id IN (
  SELECT id FROM public.shops 
  WHERE name ILIKE 'Amit Medical Store%'
     OR name ILIKE 'Test Shop%'
     OR name ILIKE 'CustomerTestShop_%'
     OR name ILIKE 'SellerShop_+919733333%'
     OR name ILIKE 'Shop_+919722222%'
     OR name ILIKE 'Shop_+919622222%'
     OR name ILIKE 'Shop_+919422222%'
     OR name ILIKE 'Shop +918888887%'
     OR name ILIKE 'Finance Test Shop%'
     OR name = 'bsbsnd'
) OR name ILIKE 'Test Item%'
  OR name ILIKE 'Test Item Shop%'
  OR name ILIKE 'Stock Test%'
  OR name ILIKE 'Refund Test Item%'
  OR name ILIKE 'Item S1%'
  OR name ILIKE 'Item S2%';

-- 6. Delete all test shops
DELETE FROM public.shops 
WHERE name ILIKE 'Amit Medical Store%'
   OR name ILIKE 'Test Shop%'
   OR name ILIKE 'CustomerTestShop_%'
   OR name ILIKE 'SellerShop_+919733333%'
   OR name ILIKE 'Shop_+919722222%'
   OR name ILIKE 'Shop_+919622222%'
   OR name ILIKE 'Shop_+919422222%'
   OR name ILIKE 'Shop +918888887%'
   OR name ILIKE 'Finance Test Shop%'
   OR name = 'bsbsnd';
