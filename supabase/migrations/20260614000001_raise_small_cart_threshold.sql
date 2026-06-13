-- Raise small_cart_threshold from ₹99 to ₹149
-- Small orders below this value will be charged the small_cart_fee.
-- This stops loss-making sub-₹99 orders from being subsidised by Enything.
INSERT INTO platform_config (key, value, updated_at)
VALUES ('small_cart_threshold', '149', NOW())
ON CONFLICT (key) DO UPDATE
  SET value      = '149',
      updated_at = NOW();
