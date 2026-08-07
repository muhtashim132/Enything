#!/bin/bash
echo "=== TEST 1: Admin sets max radius to 15 ==="
supabase db query --linked "UPDATE public.platform_config SET value = '15.0'::jsonb WHERE key = 'max_delivery_radius_km';" > /dev/null
echo "Radius set to 15 in database."

echo "Customer in Bangalore searching with 5000km radius..."
dart scratch/test_radius.dart

echo ""
echo "=== TEST 2: Admin sets max radius to 5000 ==="
supabase db query --linked "UPDATE public.platform_config SET value = '5000.0'::jsonb WHERE key = 'max_delivery_radius_km';" > /dev/null
echo "Radius set to 5000 in database."

echo "Customer in Bangalore searching with 5000km radius again..."
dart scratch/test_radius.dart
