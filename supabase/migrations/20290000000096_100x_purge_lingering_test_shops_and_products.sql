-- 100x Purge Lingering Test Shops and Mock Products

-- 1. Delete reviews
DELETE FROM public.reviews
WHERE shop_id IN (
  SELECT id FROM public.shops
  WHERE name ILIKE '%6194642%'
     OR name ILIKE 'Fresh Mart%'
     OR name ILIKE 'MedPlus Pharmacy%'
     OR name ILIKE 'Apollo Pharmacy%'
     OR name ILIKE 'Kamrans Meat Shop.%'
     OR name ILIKE 'Kamraans Shop%'
     OR name ILIKE 'Kamrans shop%'
     OR name ILIKE 'Kayooms Grocery%'
     OR name ILIKE 'Kamrans Butcher shop%'
);

-- 2. Delete order items
DELETE FROM public.order_items
WHERE product_id IN (
  SELECT id FROM public.products
  WHERE shop_id IN (
    SELECT id FROM public.shops
    WHERE name ILIKE '%6194642%'
       OR name ILIKE 'Fresh Mart%'
       OR name ILIKE 'MedPlus Pharmacy%'
       OR name ILIKE 'Apollo Pharmacy%'
       OR name ILIKE 'Kamrans Meat Shop.%'
       OR name ILIKE 'Kamraans Shop%'
       OR name ILIKE 'Kamrans shop%'
       OR name ILIKE 'Kayooms Grocery%'
       OR name ILIKE 'Kamrans Butcher shop%'
  ) OR name IN ('Salbutamol Inhaler', 'Fresh Red Apples 1kg', 'Amoxicillin 500mg (Antibiotic)')
) OR order_id IN (
  SELECT id FROM public.orders
  WHERE shop_id IN (
    SELECT id FROM public.shops
    WHERE name ILIKE '%6194642%'
       OR name ILIKE 'Fresh Mart%'
       OR name ILIKE 'MedPlus Pharmacy%'
       OR name ILIKE 'Apollo Pharmacy%'
       OR name ILIKE 'Kamrans Meat Shop.%'
       OR name ILIKE 'Kamraans Shop%'
       OR name ILIKE 'Kamrans shop%'
       OR name ILIKE 'Kayooms Grocery%'
       OR name ILIKE 'Kamrans Butcher shop%'
  )
) OR product_name IN ('Salbutamol Inhaler', 'Fresh Red Apples 1kg', 'Amoxicillin 500mg (Antibiotic)');

-- 3. Delete orders
DELETE FROM public.orders
WHERE shop_id IN (
  SELECT id FROM public.shops
  WHERE name ILIKE '%6194642%'
     OR name ILIKE 'Fresh Mart%'
     OR name ILIKE 'MedPlus Pharmacy%'
     OR name ILIKE 'Apollo Pharmacy%'
     OR name ILIKE 'Kamrans Meat Shop.%'
     OR name ILIKE 'Kamraans Shop%'
     OR name ILIKE 'Kamrans shop%'
     OR name ILIKE 'Kayooms Grocery%'
     OR name ILIKE 'Kamrans Butcher shop%'
);

-- 4. Delete products
DELETE FROM public.products
WHERE name IN ('Salbutamol Inhaler', 'Fresh Red Apples 1kg', 'Amoxicillin 500mg (Antibiotic)')
   OR shop_id IN (
      SELECT id FROM public.shops
      WHERE name ILIKE '%6194642%'
         OR name ILIKE 'Fresh Mart%'
         OR name ILIKE 'MedPlus Pharmacy%'
         OR name ILIKE 'Apollo Pharmacy%'
         OR name ILIKE 'Kamrans Meat Shop.%'
         OR name ILIKE 'Kamraans Shop%'
         OR name ILIKE 'Kamrans shop%'
         OR name ILIKE 'Kayooms Grocery%'
         OR name ILIKE 'Kamrans Butcher shop%'
   );

-- 5. Delete shops
DELETE FROM public.shops
WHERE name ILIKE '%6194642%'
   OR name ILIKE 'Fresh Mart%'
   OR name ILIKE 'MedPlus Pharmacy%'
   OR name ILIKE 'Apollo Pharmacy%'
   OR name ILIKE 'Kamrans Meat Shop.%'
   OR name ILIKE 'Kamraans Shop%'
   OR name ILIKE 'Kamrans shop%'
   OR name ILIKE 'Kayooms Grocery%'
   OR name ILIKE 'Kamrans Butcher shop%';
