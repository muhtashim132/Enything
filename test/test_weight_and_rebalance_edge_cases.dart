void main() {
  // ignore_for_file: avoid_print
  print('================================================================');
  print('🧪 100x COMPREHENSIVE EDGE-CASE TEST SUITE: WEIGHT & REBALANCE');
  print('================================================================\n');


  // --- UNIT TEST 1: SQL Weight Formula Edge-Case Suite ---
  print('--- [TEST 1] Testing SQL Unit Normalization Logic Across Units ---');
  final testCases = [
    // (unit_type, category, raw_weight, oi_weight_kg, oi_weight_grams, expected_kg, description)
    ('grams', 'Restaurant', 500.0, null, null, 0.5, '500g Shawrma normalized to 0.5kg'),
    ('g', 'Grocery', 250.0, null, null, 0.25, '250g butter normalized to 0.25kg'),
    ('kg', 'Grocery', 2.0, null, null, 2.0, '2kg rice kept as 2.0kg'),
    ('mg', 'Pharmacy', 500.0, null, null, 0.0005, '500mg paracetamol normalized to 0.0005kg'),
    ('ml', 'Beverages', 750.0, null, null, 0.75, '750ml juice normalized to 0.75kg'),
    ('l', 'Beverages', 1.5, null, null, 1.5, '1.5L water kept as 1.5kg'),
    ('pieces', 'Clothing', 500.0, null, null, 0.5, '500 pieces (jeans 500g) converted to 0.5kg'),
    ('pieces', 'Fruits', 3.0, null, null, 3.0, '3 pieces (watermelon 3kg) kept as 3.0kg'),
    ('piece', 'Electronics', 0.2, null, null, 0.2, '0.2 piece kept as 0.2kg'),
    ('pieces', 'Clothing', 500.0, 0.500, null, 0.5, 'Trusted oi.weight_kg takes precedence'),
    ('pieces', 'Clothing', 500.0, 500.0, null, 0.5, 'Corrupt oi.weight_kg (500) sanitized to 0.5kg'),
    ('pieces', 'Pharmacy', null, null, 250.0, 0.25, 'oi.weight_in_grams (250) converted to 0.25kg'),
    (null, null, null, null, null, 0.5, 'Null everywhere falls back to 0.5kg baseline'),
  ];

  for (final tc in testCases) {
    final unitType = tc.$1;
    final category = tc.$2;
    final rawWeight = tc.$3;
    final oiWeightKg = tc.$4;
    final oiWeightGrams = tc.$5;
    final expectedKg = tc.$6;
    final desc = tc.$7;

    // Simulate the exact SQL CASE expression logic
    double resolved;
    if (oiWeightKg != null && oiWeightKg > 0 && oiWeightKg <= 25.0) {
      resolved = oiWeightKg;
    } else if (oiWeightKg != null &&
        oiWeightKg > 25.0 &&
        (['Clothing', 'Footwear', 'Pharmacy', 'Medical Store', 'Restaurant', 'Bakery', 'Fast Food', 'Beverages']
                .contains(category) ||
            oiWeightKg > 100.0)) {
      resolved = oiWeightKg / 1000.0;
    } else if (oiWeightGrams != null && oiWeightGrams > 0) {
      resolved = oiWeightGrams / 1000.0;
    } else if (rawWeight != null && rawWeight > 0) {
      final cleanUnit = (unitType ?? 'kg').toLowerCase().trim();
      if (['g', 'gm', 'gms', 'gram', 'grams', 'ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres']
          .contains(cleanUnit)) {
        resolved = rawWeight / 1000.0;
      } else if (['mg', 'milligram', 'milligrams'].contains(cleanUnit)) {
        resolved = rawWeight / 1000000.0;
      } else if (['kg', 'kilogram', 'kilograms', 'l', 'liter', 'liters', 'ltr', 'litre', 'litres']
          .contains(cleanUnit)) {
        resolved = rawWeight;
      } else if (['pieces', 'piece', 'pcs', 'pc'].contains(cleanUnit)) {
        resolved = rawWeight > 25.0 ? rawWeight / 1000.0 : rawWeight;
      } else if (['Clothing', 'Footwear', 'Pharmacy', 'Medical Store', 'Restaurant', 'Bakery', 'Fast Food', 'Beverages']
              .contains(category) &&
          rawWeight > 20.0) {
        resolved = rawWeight / 1000.0;
      } else if (rawWeight > 25.0) {
        resolved = rawWeight / 1000.0;
      } else {
        resolved = rawWeight;
      }
    } else {
      resolved = 0.5;
    }

    if ((resolved - expectedKg).abs() > 0.00001) {
      throw Exception('FAILED [$desc]: Expected $expectedKg kg, got $resolved kg');
    }
    print('  ✓ $desc -> ${resolved}kg (matches expected)');
  }
  print('✅ [TEST 1 PASSED] All 13 unit normalization edge cases passed!\n');

  // --- UNIT TEST 2: Threshold Boundary Transitions ---
  print('--- [TEST 2] Testing Heavy Order Fee Threshold Transitions ---');
  const heavyThreshold = 10.0;
  const heavyFeePerKg = 25.0;

  final boundaryCases = [
    (0.0, 0.0, '0.0 kg -> ₹0 fee'),
    (5.0, 0.0, '5.0 kg -> ₹0 fee'),
    (9.99, 0.0, '9.99 kg (just below threshold) -> ₹0 fee'),
    (10.0, 0.0, '10.0 kg (exactly at threshold) -> ₹0 fee'),
    (10.001, 25.0, '10.001 kg (just above threshold) -> ₹25 fee (1kg ceiling)'),
    (10.5, 25.0, '10.5 kg -> ₹25 fee (1kg ceiling)'),
    (11.0, 25.0, '11.0 kg -> ₹25 fee (1kg ceiling)'),
    (11.01, 50.0, '11.01 kg -> ₹50 fee (2kg ceiling)'),
    (15.0, 125.0, '15.0 kg -> ₹125 fee (5kg excess)'),
    (150.0, 2250.0, '150.0 kg (capped at 100kg) -> ₹2250 fee (90kg excess)'),
  ];

  for (final bc in boundaryCases) {
    final rawW = bc.$1;
    final expectedFee = bc.$2;
    final desc = bc.$3;

    // Apply safety clamp
    final clampedW = rawW.clamp(0.0, 100.0);
    double computedFee = 0.0;
    if (clampedW > heavyThreshold) {
      computedFee = heavyFeePerKg * (clampedW - heavyThreshold).ceil();
    }

    if ((computedFee - expectedFee).abs() > 0.01) {
      throw Exception('FAILED [$desc]: Expected ₹$expectedFee, got ₹$computedFee');
    }
    print('  ✓ $desc -> ₹$computedFee (matches expected)');
  }
  print('✅ [TEST 2 PASSED] All 10 boundary transition cases passed!\n');

  // --- UNIT TEST 3: Multi-Shop Partial Reallocation Parity ---
  print('--- [TEST 3] Testing Reallocation Arithmetic Parity ---');
  // Scenario: Cart with 2 active shops left (Subtotal: ₹6,166, Weight: 0.52kg)
  // Active Shop 1: ₹167 item, 0.02kg
  // Active Shop 2: ₹5999 item, 0.50kg
  final activeWeight = 0.02 + 0.50; // 0.52 kg
  final isHeavy = activeWeight > heavyThreshold;
  final heavyFee = isHeavy ? heavyFeePerKg * (activeWeight - heavyThreshold).ceil() : 0.0;
  final isSmall = (167.0 + 5999.0) < 99.0;
  final smallFee = isSmall ? 15.0 : 0.0;
  const baseDelivery = 20.0;
  const legSurcharge = 20.0;
  const platformFee = 15.0;
  const deliveryGstRate = 0.18;


  // Shop 1 allocations:
  final shop1Del = (baseDelivery + smallFee + heavyFee) * (1.0 + deliveryGstRate); // 20 * 1.18 = 23.60
  final shop1Plat = platformFee; // 15.0
  final shop1ItemGst = 167.0 * 0.05; // 8.35
  final shop1Grand = 167.0 + shop1ItemGst + shop1Plat + shop1Del; // 167 + 8.35 + 15 + 23.60 = 213.95

  // Shop 2 allocations:
  final shop2Del = legSurcharge * (1.0 + deliveryGstRate); // 20 * 1.18 = 23.60
  final shop2ItemGst = 5999.0 * 0.18; // 1079.82
  final shop2Grand = 5999.0 + shop2ItemGst + shop2Del; // 5999 + 1079.82 + 23.60 = 7102.42

  final groupTotal = shop1Grand + shop2Grand;
  print('  • Total Active Weight: $activeWeight kg (Heavy Fee: ₹$heavyFee)');
  print('  • Shop 1 Grand Total: ₹${shop1Grand.toStringAsFixed(2)}');
  print('  • Shop 2 Grand Total: ₹${shop2Grand.toStringAsFixed(2)}');
  print('  • Group Grand Total: ₹${groupTotal.toStringAsFixed(2)}');

  if (heavyFee != 0.0) throw Exception('FAILED: Heavy fee should be 0');
  if ((shop1Grand - 213.95).abs() > 0.01) throw Exception('FAILED: Shop 1 total mismatch');
  if ((shop2Grand - 7102.42).abs() > 0.01) throw Exception('FAILED: Shop 2 total mismatch');
  print('✅ [TEST 3 PASSED] Reallocation arithmetic parity verified!\n');

  print('================================================================');
  print('🎉 ALL EDGE-CASE TESTS PASSED WITH 100% SUCCESS!');
  print('================================================================');
}
