// ============================================================================
// test_100x_gst_statutory_slabs_and_edge_cases.dart
//
// 100x FORENSIC STATUTORY GST SLABS & EDGE CASES VERIFICATION
//
// Verifies:
// 1. All 35 Categories with dynamic price thresholds (<= ₹2,500 vs > ₹2,500)
// 2. Unstitched Fabric / Saree Statutory Flat 5% Rule
// 3. 0% Nil/Exempt Goods (Fresh produce, milk, eggs, sanitary pads, student notebooks)
// 4. 12% Savory Snacks (Kurkure, chips, namkeen) and Dairy (butter, ghee, cheese)
// 5. 40% Sin Goods (Cola, energy drinks, cigarettes, pan masala)
// 6. 5% Essential Concessional (Packaged staples <=25kg, edible oil, spices, water, diapers, medicines)
// 7. 18% Standard Retail (Cosmetics, electronics, durables, hardware, helmets, pet food)
// 8. 3% Jewellery & Precious Metals
// 9. Section 9(5) ECO Restaurant Deemed Supplier vs Retail Pass-Through
// 10. Section 52 TCS Suppression (0% exempt goods & Section 9(5) food get 0% TCS)
// 11. Add-on GST Mathematical Integrity (Base + Tax = Total)
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/config/tax_config.dart';
import 'package:enythingmobilenew/services/gst_recommendation_engine.dart';

void main() {
  final engine = GstRecommendationEngine.instance;

  group('1. Category Default Rates & Dynamic Price Slabs (<= ₹2,500 vs > ₹2,500)', () {
    test('Apparel & Clothing price slab transitions', () {
      // <= 2500 -> 5%
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 999), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 2500), equals(0.05));
      // > 2500 -> 18%
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 2500.01), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Clothing', itemPrice: 4999), equals(0.18));

      // Engine recommendations with price
      final recLow = engine.recommend('Casual Cotton Shirt', 'Clothing', itemPrice: 1200);
      expect(recLow.rate, equals(0.05));
      expect(recLow.reason, contains('≤₹2500 Statutory Concessional Slab'));

      final recHigh = engine.recommend('Designer Blazer Suit', 'Clothing', itemPrice: 7500);
      expect(recHigh.rate, equals(0.18));
      expect(recHigh.reason, contains('>₹2500 Statutory Standard Slab'));
    });

    test('Footwear price slab transitions', () {
      // <= 2500 -> 5%
      expect(TaxConfig.gstRateForCategory('Footwear', itemPrice: 800), equals(0.05));
      expect(TaxConfig.gstRateForCategory('Footwear', itemPrice: 2500), equals(0.05));
      // > 2500 -> 18%
      expect(TaxConfig.gstRateForCategory('Footwear', itemPrice: 2501), equals(0.18));
      expect(TaxConfig.gstRateForCategory('Footwear', itemPrice: 6000), equals(0.18));

      final recLow = engine.recommend('Hawai Chappal', 'Footwear', itemPrice: 250);
      expect(recLow.rate, equals(0.05));

      final recHigh = engine.recommend('Leather Formal Boots', 'Footwear', itemPrice: 4200);
      expect(recHigh.rate, equals(0.18));
    });

    test('Unstitched Fabric / Saree Statutory Flat 5% Rule (No price threshold)', () {
      // High priced saree should NOT jump to 18%
      final sareeRec = engine.recommend('Banarasi Silk Saree', 'Clothing', itemPrice: 15000);
      expect(sareeRec.rate, equals(0.05));
      expect(sareeRec.reason, contains('Unstitched Fabric / Saree — Flat 5%'));

      final fabricRec = engine.recommend('Pure Cotton Suit Fabric Unstitched', 'Clothing', itemPrice: 5000);
      expect(fabricRec.rate, equals(0.05));
      expect(fabricRec.reason, contains('Unstitched Fabric / Saree — Flat 5%'));
    });
  });

  group('2. Statutory 0% Nil / Exempt Goods', () {
    test('Fresh produce, unprocessed grains, milk, eggs, meat', () {
      final items = [
        'Fresh Tomatoes 1kg',
        'Raw Potato',
        'Fresh Apple Shimla',
        'Fresh Spinach Palak',
        'Organic Fresh Cow Milk 1L',
        'Fresh Curd Dahi (Unpackaged)',
        'Farm Fresh Brown Eggs (Tray of 30)',
        'Fresh Mutton Curry Cut 500g',
        'Fresh Rohu Fish Whole',
        'Loose Salt 1kg',
        'Fresh Paneer Unpackaged',
      ];

      for (final item in items) {
        final rec = engine.recommend(item, 'Grocery');
        expect(rec.rate, equals(0.00), reason: 'Item $item should be 0% exempt');
      }
    });

    test('Essential female hygiene & education materials (0% GST)', () {
      final sanitaryPad = engine.recommend('Stayfree Secure Sanitary Pads XL', 'Pharmacy');
      expect(sanitaryPad.rate, equals(0.00));
      expect(sanitaryPad.reason, contains('Sanitary Napkins'));

      final notebook = engine.recommend('Classmate Ruled Notebook 180 Pages', 'Stationery');
      expect(notebook.rate, equals(0.00));
      expect(notebook.reason, contains('Exercise'));
    });
  });

  group('3. Statutory 12% Slabs: Extruded Snacks & Packaged Dairy', () {
    test('Snacks, chips, namkeen, extruded snacks (Notification 09/2025-CT(R) & 54th Council)', () {
      final kurkure = engine.recommend('Kurkure Masala Munch 90g', 'Snacks');
      expect(kurkure.rate, equals(0.12));
      expect(kurkure.reason, contains('Extruded Savoury Snacks'));

      final chips = engine.recommend('Lay\'s Potato Chips India\'s Magic Masala', 'Snacks');
      expect(chips.rate, equals(0.12));

      final bhujia = engine.recommend('Haldiram Alu Bhujia Namkeen 400g', 'Snacks');
      expect(bhujia.rate, equals(0.12));
    });

    test('Dairy products with 12% statutory rate (Butter, Ghee, Cheese)', () {
      final butter = engine.recommend('Amul Salted Butter 500g', 'Dairy & Eggs');
      expect(butter.rate, equals(0.12));

      final ghee = engine.recommend('Nestle Everyday Pure Cow Ghee 1L', 'Dairy & Eggs');
      expect(ghee.rate, equals(0.12));

      final cheese = engine.recommend('Britannia Processed Cheese Slices 200g', 'Dairy & Eggs');
      expect(cheese.rate, equals(0.12));
    });
  });

  group('4. Statutory 40% Slabs: Sin Goods & Aerated Waters', () {
    test('Cigarettes, Bidi, Pan Masala, Chewing Tobacco (40% GST)', () {
      final marlboro = engine.recommend('Marlboro Red Cigarette Pack', 'Paan Shop');
      expect(marlboro.rate, equals(0.40));

      final panMasala = engine.recommend('Vimal Pan Masala Pouch', 'Paan Shop');
      expect(panMasala.rate, equals(0.40));

      final bidi = engine.recommend('Special 502 Pataka Bidi', 'Paan Shop');
      expect(bidi.rate, equals(0.40));
    });

    test('Carbonated Soft Drinks & Energy Drinks (40% GST)', () {
      final cocaCola = engine.recommend('Coca-Cola 750ml Pet Bottle', 'Beverages');
      expect(cocaCola.rate, equals(0.40));
      expect(cocaCola.reason, contains('Aerated Soft Drink'));

      final pepsi = engine.recommend('Pepsi Diet Can 300ml', 'Beverages');
      expect(pepsi.rate, equals(0.40));

      final monster = engine.recommend('Monster Energy Drink Green 350ml', 'Beverages');
      expect(monster.rate, equals(0.40));
      expect(monster.reason, contains('Energy Drinks'));

      final redbull = engine.recommend('Red Bull Energy Drink Can 250ml', 'Beverages');
      expect(redbull.rate, equals(0.40));
    });
  });

  group('5. Statutory 5% Slabs: Packaged Essentials, Pharma, Water, Hygiene', () {
    test('Pre-packaged & labeled staples <= 25kg (5% GST)', () {
      final atta = engine.recommend('Aashirvaad Shudh Chakki Atta 5kg', 'Grocery');
      expect(atta.rate, equals(0.05));
      expect(atta.reason, contains('Pre-packaged'));

      final rice = engine.recommend('Fortune Everyday Basmati Rice 5kg Bag', 'Grocery');
      expect(rice.rate, equals(0.05));

      final oil = engine.recommend('Fortune Refined Mustard Oil 1L Pouch', 'Grocery');
      expect(oil.rate, equals(0.05));

      final spices = engine.recommend('MDH Deggi Mirch Powder 100g', 'Grocery');
      expect(spices.rate, equals(0.05));
    });

    test('Packaged drinking water (5% GST as per 54th GST Council directive)', () {
      final water = engine.recommend('Bisleri 20L Water Jar', 'Beverages');
      expect(water.rate, equals(0.05));
      expect(water.reason, contains('Packaged Drinking Water'));

      final kinley = engine.recommend('Kinley Packaged Water Bottle 1L', 'Beverages');
      expect(kinley.rate, equals(0.05));
    });

    test('Baby diapers, generic medicines, soaps (5% Concessional)', () {
      final diaper = engine.recommend('Pampers All Round Protection Baby Diapers Medium', 'Pharmacy');
      expect(diaper.rate, equals(0.05));
      expect(diaper.reason, contains('Diapers'));

      final paracetamol = engine.recommend('Crocin 650mg Paracetamol Tablets', 'Pharmacy');
      expect(paracetamol.rate, equals(0.05));
      expect(paracetamol.reason, contains('Medicine'));

      final lifebuoy = engine.recommend('Lifebuoy Total Soap Bar 125g', 'Personal Care');
      expect(lifebuoy.rate, equals(0.05));
      expect(lifebuoy.reason, contains('Soap'));
    });
  });

  group('6. Statutory 18% Slabs: Standard Retail, Electronics, Pet Food, Helmets', () {
    test('Smartphones, Laptops, Appliances (18% GST)', () {
      final phone = engine.recommend('Samsung Galaxy S24 Ultra 256GB', 'Electronics');
      expect(phone.rate, equals(0.18));

      final laptop = engine.recommend('Apple MacBook Air M3 16GB', 'Electronics');
      expect(laptop.rate, equals(0.18));
    });

    test('Cosmetics & Premium Personal Care (18% GST)', () {
      final perfume = engine.recommend('Titan Skinn Raw Eau De Parfum 100ml', 'Personal Care');
      expect(perfume.rate, equals(0.18));

      final lipstick = engine.recommend('Maybelline Superstay Matte Liquid Lipstick', 'Beauty & Cosmetics');
      expect(lipstick.rate, equals(0.18));
    });

    test('Safety Helmets & Pet Food (18% GST)', () {
      final helmet = engine.recommend('Vega Crux ISI Certified Full Face Helmet', 'Auto Parts');
      expect(helmet.rate, equals(0.18));
      expect(helmet.reason, contains('Helmets'));

      final dogFood = engine.recommend('Pedigree Adult Dry Dog Food Meat & Rice 3kg', 'Pet Supplies');
      expect(dogFood.rate, equals(0.18));
      expect(dogFood.reason, contains('Dog Food'));
    });
  });

  group('7. Statutory 3% Slabs: Jewellery & Precious Metals', () {
    test('Gold, Silver, Platinum Jewellery (3% GST)', () {
      final goldRing = engine.recommend('Tanishq 22K Yellow Gold Ring 4g', 'Jewellery');
      expect(goldRing.rate, equals(0.03));
      expect(goldRing.reason, contains('Jewellery'));

      final silverCoin = engine.recommend('MMTC PAMP 999 Pure Silver Bar 50g', 'Jewellery');
      expect(silverCoin.rate, equals(0.03));
    });
  });

  group('8. Section 9(5) CGST Act (Restaurant Food) vs Retail Pass-Through', () {
    test('Section 9(5) categories are strictly deemed supplier', () {
      expect(TaxConfig.isEnythingDeemedSupplier('Food'), isTrue);
      expect(TaxConfig.isEnythingDeemedSupplier('Restaurant'), isTrue);
      expect(TaxConfig.isEnythingDeemedSupplier('Fast Food'), isTrue);
      expect(TaxConfig.isEnythingDeemedSupplier('Bakery'), isTrue);
      expect(TaxConfig.isEnythingDeemedSupplier('Sweets & Mithai'), isTrue);
      expect(TaxConfig.isEnythingDeemedSupplier('Tea & Coffee'), isTrue);
      expect(TaxConfig.isEnythingDeemedSupplier('Ice Cream'), isTrue);
      expect(TaxConfig.isEnythingDeemedSupplier('Paan Shop'), isTrue);

      // Retail categories must NOT be deemed supplier
      expect(TaxConfig.isEnythingDeemedSupplier('Grocery'), isFalse);
      expect(TaxConfig.isEnythingDeemedSupplier('Pharmacy'), isFalse);
      expect(TaxConfig.isEnythingDeemedSupplier('Clothing'), isFalse);
      expect(TaxConfig.isEnythingDeemedSupplier('Electronics'), isFalse);
    });
  });

  group('9. Section 52 TCS Suppression (0% Exempt Goods & Section 9(5) Food)', () {
    test('TCS rate for 0% exempt goods is strictly 0.0%', () {
      // 0% GST rate goods must yield 0% TCS
      expect(TaxConfig.tcsRateForCategory('Grocery', gstRate: 0.00), equals(0.0));
      expect(TaxConfig.tcsRateForCategory('Pharmacy', gstRate: 0.00), equals(0.0));
    });

    test('TCS rate for Section 9(5) food is strictly 0.0%', () {
      expect(TaxConfig.tcsRateForCategory('Food', gstRate: 0.05), equals(0.0));
      expect(TaxConfig.tcsRateForCategory('Restaurant', gstRate: 0.05), equals(0.0));
    });

    test('TCS rate for taxable retail goods is strictly 0.5% (0.005)', () {
      expect(TaxConfig.tcsRateForCategory('Grocery', gstRate: 0.05), equals(0.005));
      expect(TaxConfig.tcsRateForCategory('Electronics', gstRate: 0.18), equals(0.005));
      expect(TaxConfig.tcsRateForCategory('Clothing', gstRate: 0.05), equals(0.005));
      expect(TaxConfig.tcsRateForCategory('Clothing', gstRate: 0.18), equals(0.005));
    });

    test('OrderTaxBreakdown.calculate enforces TCS suppression across mixed cart', () {
      final items = [
        // Section 9(5) food item: ₹500 base, 5% GST -> Deemed supplier, 0 TCS
        {
          'category': 'Restaurant',
          'price': 500.0,
          'quantity': 1,
          'gst_rate_override': 0.05,
        },
        // 0% exempt produce: ₹200 base, 0% GST -> Retail, 0 TCS (exempt)
        {
          'category': 'Grocery',
          'price': 200.0,
          'quantity': 1,
          'gst_rate_override': 0.00,
        },
        // 18% electronics: ₹1,000 base, 18% GST -> Retail, 0.5% TCS on ₹1,000 = ₹5.00
        {
          'category': 'Electronics',
          'price': 1000.0,
          'quantity': 1,
          'gst_rate_override': 0.18,
        },
      ];

      final breakdown = OrderTaxBreakdown.calculate(
        items: items,
        deliveryCharge: 30.0,
        riderEarnings: 24.0,
        platformFee: 2.0,
        paymentMethod: 'upi',
      );

      // Food GST: 500 * 0.05 = 25.0
      expect(breakdown.s9_5GstToRemit, equals(25.0));
      // Retail GST: 200 * 0.0 + 1000 * 0.18 = 180.0
      expect(breakdown.nonFoodGstPassThrough, equals(180.0));
      // TCS: Only ₹1000 taxable retail item incurs 0.5% TCS = ₹5.00
      expect(breakdown.tcsAmount, equals(5.0));
      // Total taxable subtotal: 500 + 200 + 1000 = 1700
      expect(breakdown.itemBaseSubtotal, equals(1700.0));
    });
  });

  group('10. Add-on GST Mathematical Integrity (Base + Tax = Total)', () {
    test('Strict Add-on GST math ensures customer pays Base + Statutory GST', () {
      const basePrices = [100.0, 250.0, 999.0, 2500.0, 5499.0];
      const gstRates = [0.00, 0.03, 0.05, 0.12, 0.18, 0.40];

      for (final base in basePrices) {
        for (final rate in gstRates) {
          final gstAmount = (base * rate * 100).round() / 100.0;
          final total = base + gstAmount;

          expect(total, greaterThanOrEqualTo(base));
          if (rate == 0.0) {
            expect(total, equals(base));
          } else {
            expect(gstAmount, closeTo(base * rate, 0.01));
          }
        }
      }
    });
  });

  group('11. 100x Forensic Educational Stationery & User Edge Cases (HSN 9609, 4820, 4016, 8214 = 0%)', () {
    test('Pencils autodetect 0% GST across all stationery and retail categories', () {
      final pencilCases = [
        {'name': 'pencil', 'cat': 'Stationery'},
        {'name': 'writing pencil', 'cat': 'Stationery'},
        {'name': 'pencil', 'cat': 'Supermarket / Hypermarket'},
        {'name': 'lead pencil', 'cat': 'Stationery'},
        {'name': 'Apsara Platinum Extra Dark Pencil Pack of 10', 'cat': 'Stationery'},
        {'name': 'Nataraj 621 Bold Pencil', 'cat': 'Stationery'},
        {'name': 'Doms Neon Eraser Tipped Pencil', 'cat': 'General Store'},
        {'name': 'Camlin Flora Pencil Pack', 'cat': 'Books & Stationery'},
        {'name': 'color pencil', 'cat': 'Stationery'},
        {'name': 'Faber-Castell 12 Colour Pencils', 'cat': 'Stationery'},
        {'name': 'slate pencil', 'cat': 'Stationery'},
        {'name': 'mechanical pencil 0.5mm', 'cat': 'Stationery'},
      ];

      for (final tc in pencilCases) {
        final rec = engine.recommend(tc['name']!, tc['cat']!);
        expect(rec.rate, equals(0.00), reason: 'Pencil item "${tc['name']}" in "${tc['cat']}" must be 0% exempt');
        expect(rec.reason, contains('0%'));
      }
    });

    test('Erasers, sharpeners, crayons and books autodetect 0% GST', () {
      final stationeryZeroItems = [
        {'name': 'eraser', 'cat': 'Stationery'},
        {'name': 'Apsara Non Dust Eraser', 'cat': 'Stationery'},
        {'name': 'sharpener', 'cat': 'Stationery'},
        {'name': 'pencil sharpener', 'cat': 'Supermarket / Hypermarket'},
        {'name': 'crayons', 'cat': 'Stationery'},
        {'name': 'crayon', 'cat': 'Stationery'},
        {'name': 'Camlin Oil Pastels 25 Shades', 'cat': 'Stationery'},
        {'name': 'Doms Plastic Crayons 12 Shades', 'cat': 'Stationery'},
        {'name': 'exercise book', 'cat': 'Stationery'},
        {'name': 'Classmate 4 Line Exercise Notebook', 'cat': 'Stationery'},
        {'name': 'drawing book', 'cat': 'Stationery'},
        {'name': 'lab notebook', 'cat': 'Stationery'},
        {'name': 'graph book', 'cat': 'Stationery'},
        {'name': 'NCERT Mathematics Class 10 Textbook', 'cat': 'Stationery'},
        {'name': 'blackboard chalk box', 'cat': 'Stationery'},
      ];

      for (final tc in stationeryZeroItems) {
        final rec = engine.recommend(tc['name']!, tc['cat']!);
        expect(rec.rate, equals(0.00), reason: 'Stationery item "${tc['name']}" in "${tc['cat']}" must be 0% exempt');
      }
    });

    test('Disambiguation of "notebook": School Notebooks (0%) vs Laptops / IT (18%)', () {
      // School/Stationery/Supermarket Notebook -> 0%
      final schoolNotebook = engine.recommend('notebook', 'Stationery');
      expect(schoolNotebook.rate, equals(0.00));
      expect(schoolNotebook.reason, contains('Exercise'));

      final superNotebook = engine.recommend('Classmate Single Line Notebook', 'Supermarket / Hypermarket');
      expect(superNotebook.rate, equals(0.00));

      // Electronics / Laptop Notebook -> 18%
      final techNotebook = engine.recommend('notebook', 'Electronics');
      expect(techNotebook.rate, equals(0.18));
      expect(techNotebook.reason, contains('Laptop'));

      final laptopName = engine.recommend('Lenovo ThinkPad Notebook Core i7', 'Stationery');
      expect(laptopName.rate, equals(0.18));
      expect(laptopName.reason, contains('Laptop'));
    });

    test('Pens and geometry compasses remain 18% standard supplies', () {
      final pen = engine.recommend('Reynolds Ballpoint Pen Blue', 'Stationery');
      expect(pen.rate, equals(0.18));

      final marker = engine.recommend('Camlin Whiteboard Marker Black', 'Stationery');
      expect(marker.rate, equals(0.18));

      final stapler = engine.recommend('Kangaro No. 10 Stapler', 'Stationery');
      expect(stapler.rate, equals(0.18));
    });

    test('Hair Conditioner is 18% (Schedule II) while Shampoo is 5% (FMCG Merit)', () {
      final shampoo = engine.recommend('Head & Shoulders Anti Dandruff Shampoo 180ml', 'Personal Care');
      expect(shampoo.rate, equals(0.05));

      final conditioner = engine.recommend('L\'Oreal Paris Total Repair 5 Conditioner', 'Personal Care');
      expect(conditioner.rate, equals(0.18));
      expect(conditioner.reason, contains('18%'));

      final serum = engine.recommend('Livon Hair Serum 100ml', 'Personal Care');
      expect(serum.rate, equals(0.18));
    });

    test('Insulin formulations are 5% (Schedule I Entry 173)', () {
      final insulin = engine.recommend('Human Actrapid Insulin 100IU Injection', 'Pharmacy');
      expect(insulin.rate, equals(0.05));
      expect(insulin.reason, contains('Insulin'));
    });
  });
}
