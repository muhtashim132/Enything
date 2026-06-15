-- ============================================================================
-- One-time migration: Copy existing address_home / address_work JSONB
-- from the customers table into the new saved_addresses table.
--
-- Migrated rows will have latitude=0, longitude=0 since the old schema
-- did not store GPS coordinates. Users will update them next time they
-- tap the GPS button in the address form.
-- ============================================================================

-- Migrate Home addresses
INSERT INTO public.saved_addresses (user_id, label, flat_number, address, landmark, pincode, latitude, longitude, is_default)
SELECT
  c.id,
  'Home',
  (c.address_home->>'flat'),
  COALESCE(c.address_home->>'address', c.default_address, ''),
  COALESCE(c.address_home->>'landmark', c.landmark, ''),
  COALESCE(c.address_home->>'pincode', c.pincode, ''),
  0, 0, true
FROM public.customers c
JOIN auth.users u ON c.id = u.id
WHERE c.address_home IS NOT NULL
  AND (c.address_home->>'address') IS NOT NULL
  AND (c.address_home->>'address') != ''
ON CONFLICT DO NOTHING;

-- Migrate Work addresses
INSERT INTO public.saved_addresses (user_id, label, flat_number, address, landmark, pincode, latitude, longitude, is_default)
SELECT
  c.id,
  'Office',
  (c.address_work->>'flat'),
  (c.address_work->>'address'),
  (c.address_work->>'landmark'),
  (c.address_work->>'pincode'),
  0, 0, false
FROM public.customers c
JOIN auth.users u ON c.id = u.id
WHERE c.address_work IS NOT NULL
  AND (c.address_work->>'address') IS NOT NULL
  AND (c.address_work->>'address') != ''
ON CONFLICT DO NOTHING;
