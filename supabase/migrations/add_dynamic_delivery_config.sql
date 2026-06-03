-- Migration: Add dynamic delivery configuration keys to platform_config

-- Insert delivery rate per km (default 10 rupees)
INSERT INTO platform_config (key, value, description) 
VALUES ('delivery_rate_per_km', '10.0', 'Delivery charge per kilometer')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, description = EXCLUDED.description;

-- Update max delivery radius (15 km)
INSERT INTO platform_config (key, value, description) 
VALUES ('max_delivery_radius_km', '15.0', 'Maximum radius allowed for delivery in km')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, description = EXCLUDED.description;

-- Ensure threshold variables are seeded
INSERT INTO platform_config (key, value, description)
VALUES 
  ('small_cart_threshold', '99.0', 'Orders below this attract a fee'),
  ('heavy_order_threshold_kg', '10.0', 'Orders above this weight attract a fee')
ON CONFLICT (key) DO NOTHING;
