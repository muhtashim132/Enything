-- 100x Definitive Database Cleanup Migration: Test Sellers, Customers, Riders & Shops
-- Strictly preserves:
--   1. Magic Reviewer Accounts:
--      - Customer: Rajesh Kumar (+919999999996 / +919999949916)
--      - Seller: Amit Bandana (+919999999997 / +919999948435) -> "Amit Medical Store"
--      - Delivery Partner: Kishan Nadda (+919999999998 / +919999978234)
--   2. All Real Accounts & Real Shops (Muhtashim KAMRAN, Raashid Nazki, Kamran, Kayoom, Syed Ufaq, etc.)

DO $$
DECLARE
  v_whitelist_user_ids UUID[];
  v_whitelist_shop_ids UUID[];
BEGIN
  -- 1. Identify Whitelist User IDs
  SELECT ARRAY_AGG(id) INTO v_whitelist_user_ids
  FROM public.profiles
  WHERE phone IN (
    '+919999999996', '+919999999997', '+919999999998', 
    '9999999996', '9999999997', '9999999998',
    '+919999949916', '+919999948435', '+919999978234',
    '+917006464241', '917006464241',
    '+918377088295', '918377088295',
    '+919999999992', '919999999992',
    '+919999999993', '919999999993',
    '+919999999994', '919999999994',
    '+919999999995', '919999999995',
    '+917006464242', '917006464242',
    '+917889338097', '917889338097',
    '+917006601112', '917006601112',
    '+917780946285', '917780946285',
    '+917298209419', '917298209419',
    '+917889891841', '917889891841',
    '+916005051701', '916005051701',
    '+919999999999', '919999999999',
    '+917006897059', '917006897059',
    '+919315115466', '919315115466',
    '+916005593993', '916005593993',
    '+919906880445', '919906880445',
    '+917006029318', '917006029318',
    '+919999989628', '+919999932810', '+919999901566'
  )
  OR full_name IN (
    'Rajesh Kumar', 'Amit Bandana', 'Kishan Nadda',
    'Muhtashim KAMRAN', 'Raashid Nazki', 'Kamraan', 'Nazki', 'Kamran', 'Muhtashim', 
    'Kayoom', 'Syed Ufaq', 'Suhaib', 'Tasneema', 'Abdul', 'Mubashir', 
    'Danish Hussain', 'EISHAN', 'Mohsin Ali', 'Syed', 'Irfah Hujat', 'Musadiq Nazki'
  );

  -- 2. Identify Whitelist Shop IDs
  SELECT ARRAY_AGG(id) INTO v_whitelist_shop_ids
  FROM public.shops
  WHERE name IN (
    'Amit Medical Store',
    'Kamrans Meat Shop.',
    'Kamraans Shop',
    'Kamrans Butcher shop',
    'Kamrans Restaurant',
    'Kamrans shop',
    'Raashids shop',
    'Kayooms Grocery',
    'Mirhart Studio',
    'Haji Super Mart',
    'Valley Choice',
    'Mubashir Medical Shop',
    'Musadiq clothes Store'
  )
  OR seller_id = ANY(v_whitelist_user_ids);

  -- 3. Delete Dependent Records in Order
  -- Disputes
  DELETE FROM public.order_disputes 
  WHERE raised_by NOT = ANY(v_whitelist_user_ids)
     OR order_id IN (
        SELECT id FROM public.orders 
        WHERE customer_id NOT = ANY(v_whitelist_user_ids)
           OR shop_id NOT = ANY(v_whitelist_shop_ids)
           OR (delivery_partner_id IS NOT NULL AND delivery_partner_id NOT = ANY(v_whitelist_user_ids))
     );

  -- Reviews & Ratings
  DELETE FROM public.reviews 
  WHERE customer_id NOT = ANY(v_whitelist_user_ids)
     OR shop_id NOT = ANY(v_whitelist_shop_ids)
     OR (delivery_partner_id IS NOT NULL AND delivery_partner_id NOT = ANY(v_whitelist_user_ids))
     OR order_id IN (
        SELECT id FROM public.orders 
        WHERE customer_id NOT = ANY(v_whitelist_user_ids)
           OR shop_id NOT = ANY(v_whitelist_shop_ids)
           OR (delivery_partner_id IS NOT NULL AND delivery_partner_id NOT = ANY(v_whitelist_user_ids))
     );

  -- Order Items
  DELETE FROM public.order_items 
  WHERE product_id IN (
    SELECT id FROM public.products WHERE shop_id NOT = ANY(v_whitelist_shop_ids)
  )
  OR order_id IN (
    SELECT id FROM public.orders 
    WHERE customer_id NOT = ANY(v_whitelist_user_ids)
       OR shop_id NOT = ANY(v_whitelist_shop_ids)
       OR (delivery_partner_id IS NOT NULL AND delivery_partner_id NOT = ANY(v_whitelist_user_ids))
  );

  -- Orders
  DELETE FROM public.orders 
  WHERE customer_id NOT = ANY(v_whitelist_user_ids)
     OR shop_id NOT = ANY(v_whitelist_shop_ids)
     OR (delivery_partner_id IS NOT NULL AND delivery_partner_id NOT = ANY(v_whitelist_user_ids));

  -- Product GST Overrides & Products
  DELETE FROM public.product_gst_overrides 
  WHERE product_id IN (
    SELECT id FROM public.products WHERE shop_id NOT = ANY(v_whitelist_shop_ids)
  );

  DELETE FROM public.products 
  WHERE shop_id NOT = ANY(v_whitelist_shop_ids);

  -- User References: Saved Addresses, Device Tokens, App Logs, Support Tickets
  DELETE FROM public.saved_addresses WHERE user_id NOT = ANY(v_whitelist_user_ids);
  DELETE FROM public.device_tokens WHERE user_id NOT = ANY(v_whitelist_user_ids);
  DELETE FROM public.app_logs WHERE user_id NOT = ANY(v_whitelist_user_ids);
  DELETE FROM public.support_tickets WHERE user_id NOT = ANY(v_whitelist_user_ids);

  -- Rider & Seller Activity Records
  DELETE FROM public.rider_locations WHERE rider_id NOT = ANY(v_whitelist_user_ids);
  DELETE FROM public.rider_shifts WHERE rider_id NOT = ANY(v_whitelist_user_ids);
  DELETE FROM public.rider_payouts WHERE rider_id NOT = ANY(v_whitelist_user_ids);
  DELETE FROM public.seller_payouts WHERE seller_id NOT = ANY(v_whitelist_user_ids);
  DELETE FROM public.withdrawals WHERE user_id NOT = ANY(v_whitelist_user_ids);

  -- Admin & Audit Records
  DELETE FROM public.admin_sessions WHERE admin_id NOT = ANY(v_whitelist_user_ids);
  DELETE FROM public.admin_invitations WHERE created_by NOT = ANY(v_whitelist_user_ids);
  DELETE FROM public.audit_logs WHERE user_id NOT = ANY(v_whitelist_user_ids) OR admin_id NOT = ANY(v_whitelist_user_ids);
  DELETE FROM public.customer_favorites WHERE customer_id NOT = ANY(v_whitelist_user_ids) OR shop_id NOT = ANY(v_whitelist_shop_ids);
  DELETE FROM public.notifications WHERE user_id NOT = ANY(v_whitelist_user_ids);

  -- Shops & Delivery Partners
  DELETE FROM public.shops WHERE id NOT = ANY(v_whitelist_shop_ids);
  DELETE FROM public.delivery_partners WHERE id NOT = ANY(v_whitelist_user_ids);

  -- Profiles
  DELETE FROM public.profiles WHERE id NOT = ANY(v_whitelist_user_ids);

  RAISE NOTICE '100x test users and shops cleanup completed successfully.';
END $$;
