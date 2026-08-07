BEGIN;

INSERT INTO orders (id, customer_id, shop_id, cart_group_id, payment_method, payment_status, status, total_amount, gst_item_total, platform_fee, delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee, grand_total_collected, razorpay_payment_id)
VALUES 
(gen_random_uuid(), 'd29f8f4a-8d7d-4195-a22b-5b583f7b8cb2', gen_random_uuid(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'online', 'awaiting_payment', 'seller_rejected', 100, 5, 0.91, 20, 1, 0, 0, 126.91, NULL),
(gen_random_uuid(), 'd29f8f4a-8d7d-4195-a22b-5b583f7b8cb2', gen_random_uuid(), 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'online', 'awaiting_payment', 'awaiting_payment', 100, 5, 0.91, 20, 1, 0, 0, 126.91, NULL);

SELECT reallocate_cancelled_delivery_fees('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT status, platform_fee, multi_shop_surcharge, grand_total_collected FROM orders WHERE cart_group_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

ROLLBACK;
