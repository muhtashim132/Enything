-- 20260609000002_add_missing_indexes.sql
CREATE INDEX IF NOT EXISTS idx_orders_cart_group_id ON public.orders(cart_group_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_status ON public.orders(customer_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_shop_status ON public.orders(shop_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_rider_status ON public.orders(delivery_partner_id, status);
