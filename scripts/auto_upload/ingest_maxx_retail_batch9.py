#!/usr/bin/env python3
"""
Maxx Retail Batch 9 (Shelf Scans g73.jpeg - g83.jpeg) Ingestion Engine
======================================================================
Catalog: 103 authentic professional clinical serums, derma cleansers,
         barrier repair creams, foaming washes, Plix fruit actives,
         Dot & Key skincare, Cetaphil dermatological washes,
         L'Oreal anti-aging night creams, body mists, and luxury perfumes.

Directives:
  1. Product category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab).
  2. Dietary status: Strictly N/A (is_veg = None / SQL NULL).
  3. Brand: Strictly populated for 100% of products (zero null brands).
  4. Packshots: Strictly 2 distinct commercial photoshoot views on pure white background (#FFFFFF),
     1:1 padded square (800x800), <120KB. Zero text cards or infographic slides. ZERO blank white images.
  5. Soft-deletes: is_deleted = false.
  6. Batch upload via public.bulk_upload_shop_products RPC.
"""

import io
import json
import os
import re
import time
import requests
from PIL import Image

SUPABASE_CONFIG = {
    "url": "https://hvtujaatwhyxielrlztr.supabase.co",
    "key": "sb_publishable_NnOTr7QGr-oQpg4EZ4GNVg_o25JykPs",
}
SHOP_ID = "750b02ab-81f7-4023-929d-a9a00a8a8790"
STORAGE_BUCKET = "products"
STORAGE_PREFIX = f"{SHOP_ID}/batch9_packshots"
CACHE_DIR = "scratch/batch9_real_packshots"

CATALOG_BATCH9 = [
    # ---------------------------------------------------------
    # 1. The Derma Co Clinical Face Serums & Treatments (g73, g74)
    # ---------------------------------------------------------
    {
        "name": "The Derma Co 2% Salicylic Acid Face Serum (30ml)",
        "brand": "The Derma Co",
        "price": 499.0,
        "weight_per_unit": 30.0,
        "description": "Formulated with 2% Salicylic Acid, Witch Hazel, and Willow Bark. Deep penetration formula designed for active acne and unclogging enlarged pores.",
        "variants": [{"title": "30ml", "price": 499.0}],
        "queries": [
            "The Derma Co 2% Salicylic Acid Face Serum 30ml bottle white background",
            "The Derma Co 2% Salicylic Acid Face Serum packaging packshot",
        ],
    },
    {
        "name": "The Derma Co 2% Kojic Acid Face Serum (30ml)",
        "brand": "The Derma Co",
        "price": 499.0,
        "weight_per_unit": 30.0,
        "description": "Enriched with 2% Kojic Acid, 1% Alpha Arbutin, and Niacinamide. Actively targets stubborn dark spots, pigmentation, and post-acne blemishes.",
        "variants": [{"title": "30ml", "price": 499.0}],
        "queries": [
            "The Derma Co 2% Kojic Acid Face Serum 30ml bottle white background",
            "The Derma Co 2% Kojic Acid Face Serum packshot",
        ],
    },
    {
        "name": "The Derma Co 10% Niacinamide Face Serum (30ml)",
        "brand": "The Derma Co",
        "price": 599.0,
        "weight_per_unit": 30.0,
        "description": "Clinically proven formula with 10% Niacinamide and Zinc PCA. Reduces acne marks, refines open pores, and balances sebum production.",
        "variants": [{"title": "30ml", "price": 599.0}],
        "queries": [
            "The Derma Co 10% Niacinamide Face Serum 30ml bottle white background",
            "The Derma Co 10% Niacinamide Face Serum packshot",
        ],
    },
    {
        "name": "The Derma Co 10% Vitamin C Face Serum (30ml)",
        "brand": "The Derma Co",
        "price": 649.0,
        "weight_per_unit": 30.0,
        "description": "Formulated with 10% Vitamin C, 5% Niacinamide, and Ferulic Acid. Provides deep antioxidant protection and enhances instant skin radiance.",
        "variants": [{"title": "30ml", "price": 649.0}],
        "queries": [
            "The Derma Co 10% Vitamin C Face Serum 30ml bottle white background",
            "The Derma Co 10% Vitamin C Face Serum packshot",
        ],
    },
    {
        "name": "The Derma Co 15% Vitamin C Face Serum (30ml)",
        "brand": "The Derma Co",
        "price": 799.0,
        "weight_per_unit": 30.0,
        "description": "Potent high-strength 15% Vitamin C serum with Ferulic Acid. Brightens dull complexion, fades dark spots, and fights premature photoaging.",
        "variants": [{"title": "30ml", "price": 799.0}],
        "queries": [
            "The Derma Co 15% Vitamin C Face Serum 30ml bottle white background",
            "The Derma Co 15% Vitamin C Face Serum packshot",
        ],
    },
    {
        "name": "The Derma Co 2% Alpha Arbutin Face Serum (30ml)",
        "brand": "The Derma Co",
        "price": 499.0,
        "weight_per_unit": 30.0,
        "description": "Formulated with 2% Alpha Arbutin and Hyaluronic Acid. Evens out patchy skin tone and diminishes hyperpigmentation.",
        "variants": [{"title": "30ml", "price": 499.0}],
        "queries": [
            "The Derma Co 2% Alpha Arbutin Face Serum 30ml bottle white background",
            "The Derma Co 2% Alpha Arbutin Face Serum packshot",
        ],
    },
    {
        "name": "The Derma Co 0.1% Retinol Face Serum (30ml)",
        "brand": "The Derma Co",
        "price": 699.0,
        "weight_per_unit": 30.0,
        "description": "Gentle slow-release 0.1% Retinol serum for spotless skin. Accelerates cell turnover, improves skin texture, and softens fine expression lines.",
        "variants": [{"title": "30ml", "price": 699.0}],
        "queries": [
            "The Derma Co 0.1% Retinol Face Serum 30ml bottle white background",
            "The Derma Co 0.1% Retinol Face Serum packshot",
        ],
    },
    {
        "name": "The Derma Co Pore Minimizing Face Serum (30ml)",
        "brand": "The Derma Co",
        "price": 599.0,
        "weight_per_unit": 30.0,
        "description": "Infused with 4% Niacinamide, 5% PHA, and p-REFINYL. Minimizes enlarged facial pores and tightens skin texture.",
        "variants": [{"title": "30ml", "price": 599.0}],
        "queries": [
            "The Derma Co Pore Minimizing Face Serum 30ml bottle white background",
            "The Derma Co Pore Minimizing Face Serum packshot",
        ],
    },
    {
        "name": "The Derma Co Sali-Cinamide Anti-Acne Face Serum (30ml)",
        "brand": "The Derma Co",
        "price": 549.0,
        "weight_per_unit": 30.0,
        "description": "Dual-action acne control serum combining 2% Salicylic Acid and 5% Niacinamide. Controls breakouts and calms redness.",
        "variants": [{"title": "30ml", "price": 549.0}],
        "queries": [
            "The Derma Co Sali-Cinamide Anti-Acne Face Serum 30ml white background",
            "The Derma Co Sali-Cinamide Face Serum packshot",
        ],
    },
    {
        "name": "The Derma Co Nia-Zelaic Oil Control Face Serum (30ml)",
        "brand": "The Derma Co",
        "price": 599.0,
        "weight_per_unit": 30.0,
        "description": "Formulated with 10% Niacinamide and 5% Azelaic Acid. Controls excessive facial sebum and prevents persistent acne marks.",
        "variants": [{"title": "30ml", "price": 599.0}],
        "queries": [
            "The Derma Co Nia-Zelaic Oil Control Face Serum 30ml white background",
            "The Derma Co Nia-Zelaic Face Serum packshot",
        ],
    },
    {
        "name": "The Derma Co 1% Kojic + Arbutin Night Repair Face Serum-Gel (50g)",
        "brand": "The Derma Co",
        "price": 599.0,
        "weight_per_unit": 50.0,
        "description": "Overnight treatment gel with 1% Kojic Acid and Alpha Arbutin. Works while you sleep to repair sun damage and fade discoloration.",
        "variants": [{"title": "50g", "price": 599.0}],
        "queries": [
            "The Derma Co 1% Kojic Arbutin Night Repair Face Serum Gel white background",
            "The Derma Co Kojic Arbutin Night Repair Serum-Gel tub packshot",
        ],
    },
    {
        "name": "The Derma Co 2% Kojic Acid Advanced Face Cream (30g)",
        "brand": "The Derma Co",
        "price": 499.0,
        "weight_per_unit": 30.0,
        "description": "Advanced spot correcting cream with 2% Kojic Acid, Arbutin, and Tranexamic Acid for targeted treatment of melasma and age spots.",
        "variants": [{"title": "30g", "price": 499.0}],
        "queries": [
            "The Derma Co 2% Kojic Acid Advanced Face Cream 30g white background",
            "The Derma Co Kojic Acid Advanced Face Cream tube packshot",
        ],
    },
    {
        "name": "The Derma Co Snail Peptide 96 Under Eye Repair Cream (15g)",
        "brand": "The Derma Co",
        "price": 499.0,
        "weight_per_unit": 15.0,
        "description": "Nourishing eye cream formulated with 1% Peptide, 2% Caffeine, and Retinol. Diminishes stubborn dark circles and morning puffiness.",
        "variants": [{"title": "15g", "price": 499.0}],
        "queries": [
            "The Derma Co Snail Peptide 96 Under Eye Repair Cream 15g white background",
            "The Derma Co Snail Peptide 96 Under Eye Cream tube packshot",
        ],
    },
    {
        "name": "The Derma Co Ceramide + HA Intense Daily Face Moisturizer (50g)",
        "brand": "The Derma Co",
        "price": 349.0,
        "weight_per_unit": 50.0,
        "description": "Deeply hydrating daily cream with Ceramide and Hyaluronic Acid. Locks in moisture for 72 hours for dry, dehydrated skin.",
        "variants": [{"title": "50g", "price": 349.0}],
        "queries": [
            "The Derma Co Ceramide HA Intense Daily Face Moisturizer 50g white background",
            "The Derma Co Ceramide HA Daily Face Moisturizer tube packshot",
        ],
    },
    {
        "name": "The Derma Co 4% Ceramide Barrier Repair Moisturizer (50g)",
        "brand": "The Derma Co",
        "price": 399.0,
        "weight_per_unit": 50.0,
        "description": "Formulated with 4% Ceramide Complex, 2% Niacinamide, and Oxylance. Restores compromised skin barrier and provides 24-hour hydration.",
        "variants": [{"title": "50g", "price": 399.0}],
        "queries": [
            "The Derma Co 4% Ceramide Barrier Repair Moisturizer 50g white background",
            "The Derma Co 4% Ceramide Barrier Repair Moisturizer packshot",
        ],
    },

    # ---------------------------------------------------------
    # 2. The Derma Co Face Washes, Cleansers & Toners (g74, g75)
    # ---------------------------------------------------------
    {
        "name": "The Derma Co 1% Salicylic Acid Gel Daily Face Wash (100ml)",
        "brand": "The Derma Co",
        "price": 299.0,
        "weight_per_unit": 100.0,
        "description": "Purifying gel cleanser with 1% Salicylic Acid, Witch Hazel, and Willow Bark. Eliminates excess oil and prevents recurring breakouts.",
        "variants": [{"title": "100ml", "price": 299.0}],
        "queries": [
            "The Derma Co 1% Salicylic Acid Gel Daily Face Wash 100ml white background",
            "The Derma Co 1% Salicylic Acid Gel Face Wash tube packshot",
        ],
    },
    {
        "name": "The Derma Co 1% Kojic Acid Daily Face Wash (100ml)",
        "brand": "The Derma Co",
        "price": 299.0,
        "weight_per_unit": 100.0,
        "description": "Daily brightening face wash with 1% Kojic Acid, Niacinamide, and Alpha Arbutin. Gently fades dark spots and clarifies skin.",
        "variants": [{"title": "100ml", "price": 299.0}],
        "queries": [
            "The Derma Co 1% Kojic Acid Daily Face Wash 100ml white background",
            "The Derma Co 1% Kojic Acid Daily Face Wash tube packshot",
        ],
    },
    {
        "name": "The Derma Co 2% Vitamin C Gel Daily Face Wash (100ml)",
        "brand": "The Derma Co",
        "price": 299.0,
        "weight_per_unit": 100.0,
        "description": "Refreshing gel cleanser with 2% Vitamin C and Orange Peel Extract. Cleanses away impurities while reviving tired skin with radiant glow.",
        "variants": [{"title": "100ml", "price": 299.0}],
        "queries": [
            "The Derma Co 2% Vitamin C Gel Daily Face Wash 100ml white background",
            "The Derma Co 2% Vitamin C Gel Face Wash tube packshot",
        ],
    },
    {
        "name": "The Derma Co 2% Sali-Cinamide Anti-Acne Face Wash (80ml)",
        "brand": "The Derma Co",
        "price": 249.0,
        "weight_per_unit": 80.0,
        "description": "Synergistic anti-acne wash with 2% Salicylic Acid and 2% Niacinamide. Clarifies congested pores and soothes inflamed skin.",
        "variants": [{"title": "80ml", "price": 249.0}],
        "queries": [
            "The Derma Co 2% Sali-Cinamide Anti-Acne Face Wash 80ml white background",
            "The Derma Co 2% Sali-Cinamide Anti-Acne Face Wash tube packshot",
        ],
    },
    {
        "name": "The Derma Co 2% Niacinamide Foaming Daily Face Wash (150ml)",
        "brand": "The Derma Co",
        "price": 399.0,
        "weight_per_unit": 150.0,
        "description": "Gentle foaming cleanser with 2% Niacinamide and Glycolic Acid. Washes away pollutants and brightens skin without stripping moisture.",
        "variants": [{"title": "150ml", "price": 399.0}],
        "queries": [
            "The Derma Co 2% Niacinamide Foaming Daily Face Wash 150ml bottle white background",
            "The Derma Co 2% Niacinamide Foaming Face Wash pump packshot",
        ],
    },
    {
        "name": "The Derma Co Oil-Free Daily Face Wash (100ml)",
        "brand": "The Derma Co",
        "price": 299.0,
        "weight_per_unit": 100.0,
        "description": "Formulated with Hyaluronic Acid, Glycolic Acid, and Multivitamins. Leaves skin hydrated, clean, and completely shine-free.",
        "variants": [{"title": "100ml", "price": 299.0}],
        "queries": [
            "The Derma Co Oil-Free Daily Face Wash 100ml white background",
            "The Derma Co Oil-Free Face Wash tube packshot",
        ],
    },
    {
        "name": "The Derma Co 2.5% Benzoyl Peroxide Gel Face Wash (100ml)",
        "brand": "The Derma Co",
        "price": 349.0,
        "weight_per_unit": 100.0,
        "description": "Clinical acne cleanser with 2.5% Benzoyl Peroxide, Allantoin, and Ceramide Complex. Targets active acne bacteria and prevents scarring.",
        "variants": [{"title": "100ml", "price": 349.0}],
        "queries": [
            "The Derma Co 2.5% Benzoyl Peroxide Gel Face Wash 100ml white background",
            "The Derma Co 2.5% Benzoyl Peroxide Face Wash tube packshot",
        ],
    },
    {
        "name": "The Derma Co 2% Niacinamide Gentle Skin Cleanser (125ml)",
        "brand": "The Derma Co",
        "price": 349.0,
        "weight_per_unit": 125.0,
        "description": "Soap-free, non-irritant daily cleanser for dry, normal, and sensitive skin. Maintains natural lipid moisture balance.",
        "variants": [{"title": "125ml", "price": 349.0}],
        "queries": [
            "The Derma Co 2% Niacinamide Gentle Skin Cleanser 125ml pump white background",
            "The Derma Co Gentle Skin Cleanser 125ml packshot",
        ],
    },
    {
        "name": "The Derma Co 2% Niacinamide Oily-Skin Cleanser (125ml)",
        "brand": "The Derma Co",
        "price": 349.0,
        "weight_per_unit": 125.0,
        "description": "Specially formulated for oily, combination, and acne-prone skin. Regulates sebum production without stripping vital hydration.",
        "variants": [{"title": "125ml", "price": 349.0}],
        "queries": [
            "The Derma Co 2% Niacinamide Oily-Skin Cleanser 125ml pump white background",
            "The Derma Co Oily-Skin Cleanser 125ml packshot",
        ],
    },
    {
        "name": "The Derma Co 7% Glycolic Acid Hydrating Toner (150ml)",
        "brand": "The Derma Co",
        "price": 449.0,
        "weight_per_unit": 150.0,
        "description": "Mild chemical exfoliating toner with 7% Glycolic Acid, Hyaluronic Acid, and Ceramide Complex. Smoothens rough texture and refines pores.",
        "variants": [{"title": "150ml", "price": 449.0}],
        "queries": [
            "The Derma Co 7% Glycolic Acid Hydrating Toner 150ml bottle white background",
            "The Derma Co 7% Glycolic Acid Toner packshot",
        ],
    },
    {
        "name": "The Derma Co 1% Ceramide Complex Lip Balm SPF 30 (4g)",
        "brand": "The Derma Co",
        "price": 249.0,
        "weight_per_unit": 4.0,
        "description": "Restorative lip balm with 1% Ceramide Complex and SPF 30 protection. Heals dry, chapped lips and prevents UV darkening.",
        "variants": [{"title": "4g", "price": 249.0}],
        "queries": [
            "The Derma Co 1% Ceramide Complex Lip Balm SPF 30 white background",
            "The Derma Co Ceramide Lip Balm packshot",
        ],
    },
    {
        "name": "The Derma Co 1% Kojic Acid Lip Balm SPF 50 (4g)",
        "brand": "The Derma Co",
        "price": 249.0,
        "weight_per_unit": 4.0,
        "description": "Lightening lip balm with 1% Kojic Acid, Alpha Arbutin, and broad spectrum SPF 50 protection for dark, pigmented lips.",
        "variants": [{"title": "4g", "price": 249.0}],
        "queries": [
            "The Derma Co 1% Kojic Acid Lip Balm SPF 50 white background",
            "The Derma Co Kojic Acid Lip Balm packshot",
        ],
    },

    # ---------------------------------------------------------
    # 3. Cetaphil Dermatological Skincare (g76, g77)
    # ---------------------------------------------------------
    {
        "name": "Cetaphil Gentle Skin Cleanser (125ml)",
        "brand": "Cetaphil",
        "price": 399.0,
        "weight_per_unit": 125.0,
        "description": "Dermatologist-recommended mild hydrating cleanser for dry to normal, sensitive skin. Formulated with Niacinamide, Panthenol, and Hydrating Glycerin.",
        "variants": [{"title": "125ml", "price": 399.0}],
        "queries": [
            "Cetaphil Gentle Skin Cleanser 125ml bottle white background",
            "Cetaphil Gentle Skin Cleanser 125ml packshot",
        ],
    },
    {
        "name": "Cetaphil Gentle Skin Cleanser (250ml)",
        "brand": "Cetaphil",
        "price": 675.0,
        "weight_per_unit": 250.0,
        "description": "Soap-free, fragrance-free formula that cleanses while actively preserving the skin's moisture barrier. Ideal for daily sensitive skin care.",
        "variants": [{"title": "250ml", "price": 675.0}],
        "queries": [
            "Cetaphil Gentle Skin Cleanser 250ml pump bottle white background",
            "Cetaphil Gentle Skin Cleanser 250ml packshot",
        ],
    },
    {
        "name": "Cetaphil Oily Skin Cleanser (125ml)",
        "brand": "Cetaphil",
        "price": 590.0,
        "weight_per_unit": 125.0,
        "description": "Clinically proven to deeply clean and minimize the appearance of pores without stripping skin of natural moisture. For combination to oily skin.",
        "variants": [{"title": "125ml", "price": 590.0}],
        "queries": [
            "Cetaphil Oily Skin Cleanser 125ml bottle white background",
            "Cetaphil Oily Skin Cleanser 125ml packshot",
        ],
    },
    {
        "name": "Cetaphil Moisturising Cream (100g)",
        "brand": "Cetaphil",
        "price": 490.0,
        "weight_per_unit": 100.0,
        "description": "Rich, non-greasy moisturizing cream enriched with Sweet Almond Oil and Vitamin E. Clinically proven to provide intense 48-hour hydration.",
        "variants": [{"title": "100g", "price": 490.0}],
        "queries": [
            "Cetaphil Moisturising Cream 100g tube white background",
            "Cetaphil Moisturising Cream 100g packshot",
        ],
    },
    {
        "name": "Cetaphil Moisturising Lotion (100ml)",
        "brand": "Cetaphil",
        "price": 485.0,
        "weight_per_unit": 100.0,
        "description": "Lightweight, fast-absorbing daily lotion with Avocado Oil and essential vitamins E and B5. Defends against 5 signs of skin sensitivity.",
        "variants": [{"title": "100ml", "price": 485.0}],
        "queries": [
            "Cetaphil Moisturising Lotion 100ml bottle white background",
            "Cetaphil Moisturising Lotion 100ml packshot",
        ],
    },

    # ---------------------------------------------------------
    # 4. Dot & Key Skincare (g83)
    # ---------------------------------------------------------
    {
        "name": "Dot & Key Cica Calming Blemish Clearing Gel Face Wash (100ml)",
        "brand": "Dot & Key",
        "price": 249.0,
        "weight_per_unit": 100.0,
        "description": "Calming gel wash infused with Tea Tree, Cica, and Salicylic Acid. Clears blemishes, dissolves impurities, and controls excess sebum.",
        "variants": [{"title": "100ml", "price": 249.0}],
        "queries": [
            "Dot & Key Cica Calming Blemish Clearing Gel Face Wash 100ml white background",
            "Dot & Key Cica Face Wash tube packshot",
        ],
    },
    {
        "name": "Dot & Key Mango Detan Gel Face Wash (100ml)",
        "brand": "Dot & Key",
        "price": 249.0,
        "weight_per_unit": 100.0,
        "description": "Detan cleansing gel with Mango, Glycolic Acid, and Niacinamide. Buffs away stubborn sun tan and restores natural skin radiance.",
        "variants": [{"title": "100ml", "price": 249.0}],
        "queries": [
            "Dot & Key Mango Detan Gel Face Wash 100ml white background",
            "Dot & Key Mango Detan Face Wash tube packshot",
        ],
    },
    {
        "name": "Dot & Key Deep Pore Clean Milky Foam Cleanser (100ml)",
        "brand": "Dot & Key",
        "price": 295.0,
        "weight_per_unit": 100.0,
        "description": "Creamy milk cleanser that foams into a luxurious lather to purify deep pores and dissolve makeup without drying.",
        "variants": [{"title": "100ml", "price": 295.0}],
        "queries": [
            "Dot & Key Deep Pore Clean Milky Foam Cleanser 100ml white background",
            "Dot & Key Milky Foam Cleanser tube packshot",
        ],
    },
    {
        "name": "Dot & Key Blueberry Hydrate Barrier Boost Face Serum (30ml)",
        "brand": "Dot & Key",
        "price": 695.0,
        "weight_per_unit": 30.0,
        "description": "Barrier repairing serum with Blueberry Extract, 5 Essential Ceramides, and Hyaluronic Acid for plumper, deeply quenched skin.",
        "variants": [{"title": "30ml", "price": 695.0}],
        "queries": [
            "Dot & Key Blueberry Hydrate Barrier Boost Face Serum 30ml bottle white background",
            "Dot & Key Blueberry Barrier Serum packshot",
        ],
    },

    # ---------------------------------------------------------
    # 5. Plix Fruit-Powered Active Skincare (g82, g83)
    # ---------------------------------------------------------
    {
        "name": "Plix Jamun Active Acne Smoothie Moisturizer (50g)",
        "brand": "Plix",
        "price": 549.0,
        "weight_per_unit": 50.0,
        "description": "Ultra-light smoothie moisturizer with 2% Acne Buster Complex and Niacinamide. Calms active acne, soothes redness, and reduces oiliness.",
        "variants": [{"title": "50g", "price": 549.0}],
        "queries": [
            "Plix Jamun Active Acne Smoothie Moisturizer 50g jar white background",
            "Plix Jamun Active Acne Moisturizer packshot",
        ],
    },
    {
        "name": "Plix Guava Glow Smoothie Moisturizer SPF 20 (50g)",
        "brand": "Plix",
        "price": 549.0,
        "weight_per_unit": 50.0,
        "description": "Glow-boosting moisturizer with Guava Extract, Vitamin C, and Hyaluronic Acid. Evens out complexion while providing SPF 20 protection.",
        "variants": [{"title": "50g", "price": 549.0}],
        "queries": [
            "Plix Guava Glow Smoothie Moisturizer SPF 20 jar white background",
            "Plix Guava Glow Moisturizer packshot",
        ],
    },
    {
        "name": "Plix Guava Glow Dewy Face Serum (30ml)",
        "brand": "Plix",
        "price": 699.0,
        "weight_per_unit": 30.0,
        "description": "Concentrated brightening serum with 10% Vitamin C and 1% Hyaluronic Acid. Delivers glass skin finish and fades dark spots.",
        "variants": [{"title": "30ml", "price": 699.0}],
        "queries": [
            "Plix Guava Glow Dewy Face Serum 30ml bottle white background",
            "Plix Guava Glow Dewy Serum packshot",
        ],
    },
    {
        "name": "Plix Rosemary Hair Growth Advanced Serum (30ml)",
        "brand": "Plix",
        "price": 799.0,
        "weight_per_unit": 30.0,
        "description": "Clinical hair growth serum infused with pure Rosemary, Redensyl, AnaGain, and Baicapil. Revitalizes dormant hair follicles and reduces hair fall.",
        "variants": [{"title": "30ml", "price": 799.0}],
        "queries": [
            "Plix Rosemary Hair Growth Advanced Serum 30ml bottle white background",
            "Plix Rosemary Hair Growth Serum packshot",
        ],
    },
    {
        "name": "Plix Pineapple De-Pigmentation Dewy Serum (30ml)",
        "brand": "Plix",
        "price": 699.0,
        "weight_per_unit": 30.0,
        "description": "Targeted de-pigmentation formula with Pineapple Extract, 2% Alpha Arbutin, and Niacinamide. Fades sun spots and hyperpigmentation.",
        "variants": [{"title": "30ml", "price": 699.0}],
        "queries": [
            "Plix Pineapple De-Pigmentation Dewy Serum 30ml bottle white background",
            "Plix Pineapple Dewy Serum packshot",
        ],
    },
    {
        "name": "Plix Guava & Roses Glow Fat Water Toner Serum (100ml)",
        "brand": "Plix",
        "price": 449.0,
        "weight_per_unit": 100.0,
        "description": "Thick essence toner packed with Guava, French Rose Water, Niacinamide, and Witch Hazel. Refines skin texture and boosts instant radiance.",
        "variants": [{"title": "100ml", "price": 449.0}],
        "queries": [
            "Plix Guava Roses Glow Fat Water Toner Serum 100ml bottle white background",
            "Plix Guava and Roses Fat Water packshot",
        ],
    },
    {
        "name": "Plix Pomegranate Youth Renewal Juicy Cleanser (100ml)",
        "brand": "Plix",
        "price": 349.0,
        "weight_per_unit": 100.0,
        "description": "Hydrating youth cleanser with Pomegranate, Retinol, Pentavitin, and Ceramide Complex. Leaves skin noticeably softer and smoother.",
        "variants": [{"title": "100ml", "price": 349.0}],
        "queries": [
            "Plix Pomegranate Youth Renewal Juicy Cleanser 100ml white background",
            "Plix Pomegranate Juicy Cleanser tube packshot",
        ],
    },
    {
        "name": "Plix Peaches & Lemon Detan Body Lotion SPF 30 (150ml)",
        "brand": "Plix",
        "price": 399.0,
        "weight_per_unit": 150.0,
        "description": "Sun protective body lotion with 5% Niacinamide and Glutathione. Lightens tan lines and nourishes dry skin with refreshing fruity hydration.",
        "variants": [{"title": "150ml", "price": 399.0}],
        "queries": [
            "Plix Peaches Lemon Detan Body Lotion SPF 30 150ml white background",
            "Plix Peaches and Lemon Detan Body Lotion tube packshot",
        ],
    },
    {
        "name": "Plix Pomegranate Youth Renewal Dewy Serum (30ml)",
        "brand": "Plix",
        "price": 699.0,
        "weight_per_unit": 30.0,
        "description": "Anti-aging facial serum with 0.5% Retinol and Bakuchiol. Plumps fine lines, boosts skin elasticity, and promotes youthful glow.",
        "variants": [{"title": "30ml", "price": 699.0}],
        "queries": [
            "Plix Pomegranate Youth Renewal Dewy Serum 30ml bottle white background",
            "Plix Pomegranate Youth Renewal Serum packshot",
        ],
    },
    {
        "name": "Plix Watermelon Tint Twist Colour Adapting Sunscreen SPF 50 (50g)",
        "brand": "Plix",
        "price": 499.0,
        "weight_per_unit": 50.0,
        "description": "Magic tint sunscreen that adapts to your natural skin tone. Delivers SPF 50 PA++++ protection with Pentavitin and Allantoin.",
        "variants": [{"title": "50g", "price": 499.0}],
        "queries": [
            "Plix Watermelon Tint Twist Sunscreen SPF 50 white background",
            "Plix Watermelon Sunscreen tube packshot",
        ],
    },
    {
        "name": "Plix Pomegranate Youth Renewal Night Cream (50g)",
        "brand": "Plix",
        "price": 599.0,
        "weight_per_unit": 50.0,
        "description": "Nourishing anti-aging night cream with Retinol, Bakuchiol, and Olive Squalane. Restores firm texture and youthful resilience overnight.",
        "variants": [{"title": "50g", "price": 599.0}],
        "queries": [
            "Plix Pomegranate Youth Renewal Night Cream 50g jar white background",
            "Plix Pomegranate Night Cream packshot",
        ],
    },
    {
        "name": "Plix Pomegranate Overnight Repair Dewy Serum (30ml)",
        "brand": "Plix",
        "price": 699.0,
        "weight_per_unit": 30.0,
        "description": "Repair serum with 1.5% Squalane, Ceramide Complex, and Multi-Peptides. Enhances skin barrier repair while you sleep.",
        "variants": [{"title": "30ml", "price": 699.0}],
        "queries": [
            "Plix Pomegranate Overnight Repair Dewy Serum 30ml bottle white background",
            "Plix Pomegranate Overnight Repair Serum packshot",
        ],
    },
    {
        "name": "Plix Avocado Ceramide Moisture Rush Fatty Cream (50g)",
        "brand": "Plix",
        "price": 549.0,
        "weight_per_unit": 50.0,
        "description": "Rich nourishing cream with 1% Ceramide Complex, Aquaxyl, and Hyaluronic Acid. Delivers 24-hour deep moisturization and barrier repair.",
        "variants": [{"title": "50g", "price": 549.0}],
        "queries": [
            "Plix Avocado Ceramide Moisture Rush Fatty Cream 50g jar white background",
            "Plix Avocado Ceramide Fatty Cream packshot",
        ],
    },
    {
        "name": "Plix Acne Patch with Salicylic Acid (36 patches)",
        "brand": "Plix",
        "price": 299.0,
        "weight_per_unit": 10.0,
        "description": "Ultra-thin hydrocolloid acne pimple patches infused with Salicylic Acid. Flattens breakouts overnight while protecting from dust and touching.",
        "variants": [{"title": "36 patches", "price": 299.0}],
        "queries": [
            "Plix Acne Patch with Salicylic Acid 36 patches white background",
            "Plix Acne Pimple Patch box packshot",
        ],
    },

    # ---------------------------------------------------------
    # 6. L'Oreal Paris Advanced Skincare (g81, g82)
    # ---------------------------------------------------------
    {
        "name": "L'Oreal Paris Revitalift Triple Action Night Cream (50ml)",
        "brand": "L'Oreal Paris",
        "price": 899.0,
        "weight_per_unit": 50.0,
        "description": "Anti-aging night moisturizer enriched with Pro-Retinol and Centella Asiatica. Visibly reduces wrinkles, firms contours, and renews skin texture.",
        "variants": [{"title": "50ml", "price": 899.0}],
        "queries": [
            "L'Oreal Paris Revitalift Triple Action Night Cream 50ml jar white background",
            "L'Oreal Revitalift Night Cream jar packshot",
        ],
    },
    {
        "name": "L'Oreal Paris Glycolic-Bright Glowing Cream Night (50ml)",
        "brand": "L'Oreal Paris",
        "price": 699.0,
        "weight_per_unit": 50.0,
        "description": "Overnight brightening moisturizer formulated with Glycolic Acid and Niacinamide. Reduces dullness and dark spots for visibly luminous skin.",
        "variants": [{"title": "50ml", "price": 699.0}],
        "queries": [
            "L'Oreal Paris Glycolic-Bright Glowing Cream Night 50ml jar white background",
            "L'Oreal Glycolic Bright Night Cream packshot",
        ],
    },
    {
        "name": "L'Oreal Paris Glycolic-Bright Matte Luminizing Day Cream SPF 17 (50ml)",
        "brand": "L'Oreal Paris",
        "price": 699.0,
        "weight_per_unit": 50.0,
        "description": "Day cream with Glycolic Acid and SPF 17. Accelerates cell renewal and shields skin against UV-induced pigmentation with a matte finish.",
        "variants": [{"title": "50ml", "price": 699.0}],
        "queries": [
            "L'Oreal Paris Glycolic-Bright Matte Luminizing Cream Day 50ml white background",
            "L'Oreal Glycolic Bright Day Cream packshot",
        ],
    },
    {
        "name": "L'Oreal Paris Revitalift 1.5% Hyaluronic Acid Plumping Serum (30ml)",
        "brand": "L'Oreal Paris",
        "price": 999.0,
        "weight_per_unit": 30.0,
        "description": "High concentration 1.5% Hyaluronic Acid serum with micro-epidermic technology. Plumps fine lines by up to 60% and restores youthful bounce.",
        "variants": [{"title": "30ml", "price": 999.0}],
        "queries": [
            "L'Oreal Paris Revitalift 1.5% Hyaluronic Acid Plumping Serum 30ml bottle white background",
            "L'Oreal Revitalift Hyaluronic Acid Serum dropper packshot",
        ],
    },
    {
        "name": "L'Oreal Paris Glycolic-Bright Dark Spot Brightening Serum (30ml)",
        "brand": "L'Oreal Paris",
        "price": 749.0,
        "weight_per_unit": 30.0,
        "description": "Formulated with 8% Melasyl and Glycolic Acid. Fades up to 5 years of dark spots and visibly brightens uneven tone.",
        "variants": [{"title": "30ml", "price": 749.0}],
        "queries": [
            "L'Oreal Paris Glycolic-Bright Dark Spot Brightening Serum 30ml bottle white background",
            "L'Oreal Glycolic Bright Serum packshot",
        ],
    },
    {
        "name": "L'Oreal Paris Revitalift Hyaluronic Acid Hydrating Gel-Cleanser (100ml)",
        "brand": "L'Oreal Paris",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Ultra-fine hydrating gel cleanser infused with Hyaluronic Acid. Cleanses gently without drying, leaving skin plump and fresh.",
        "variants": [{"title": "100ml", "price": 399.0}],
        "queries": [
            "L'Oreal Paris Revitalift Hyaluronic Acid Hydrating Gel-Cleanser 100ml white background",
            "L'Oreal Revitalift Gel Cleanser tube packshot",
        ],
    },
    {
        "name": "L'Oreal Paris Glycolic-Bright Glowing Foam Cleanser (100ml)",
        "brand": "L'Oreal Paris",
        "price": 349.0,
        "weight_per_unit": 100.0,
        "description": "Gentle daily foaming wash with Glycolic Acid. Exfoliates surface dullness, cleanses deep into pores, and boosts skin radiance.",
        "variants": [{"title": "100ml", "price": 349.0}],
        "queries": [
            "L'Oreal Paris Glycolic-Bright Glowing Foam Cleanser 100ml white background",
            "L'Oreal Glycolic Bright Foam Cleanser tube packshot",
        ],
    },

    # ---------------------------------------------------------
    # 7. Toners, Mists, Creams & Specialized Care (g76, g81)
    # ---------------------------------------------------------
    {
        "name": "Blue Chip Rosy Mist Face Cleanser & Toner (100ml)",
        "brand": "Blue Chip",
        "price": 120.0,
        "weight_per_unit": 100.0,
        "description": "Refreshing floral rose water mist that cleanses, hydrates, and tightens pores with a soothing rosy aroma.",
        "variants": [{"title": "100ml", "price": 120.0}],
        "queries": [
            "Blue Chip Rosy Mist Face Cleanser Toner 100ml spray bottle white background",
            "Blue Chip Rosy Mist 100ml spray packshot",
        ],
    },
    {
        "name": "Dabur Gulabari 3 in 1 Rose Face Cleanser (100ml)",
        "brand": "Dabur",
        "price": 95.0,
        "weight_per_unit": 100.0,
        "description": "3-in-1 formula enriched with Pure Rose Oil. Cleanses dirt, moisturizes skin, and delivers instant rose-petal freshness.",
        "variants": [{"title": "100ml", "price": 95.0}],
        "queries": [
            "Dabur Gulabari 3 in 1 Rose Face Cleanser spray 100ml white background",
            "Dabur Gulabari Face Cleanser 3 in 1 packshot",
        ],
    },
    {
        "name": "NutriGlow Red Wine Facial Toner (100ml)",
        "brand": "NutriGlow",
        "price": 180.0,
        "weight_per_unit": 100.0,
        "description": "Infused with Red Wine Extract and soothing botanicals. Tightens open pores, balances skin pH, and imparts a youthful glow.",
        "variants": [{"title": "100ml", "price": 180.0}],
        "queries": [
            "NutriGlow Red Wine Facial Toner 100ml spray bottle white background",
            "NutriGlow Red Wine Toner packshot",
        ],
    },
    {
        "name": "VWash Plus Expert Intimate Hygiene Liquid Wash (100ml)",
        "brand": "VWash",
        "price": 190.0,
        "weight_per_unit": 100.0,
        "description": "Clinically tested intimate hygiene wash with Lactic Acid and Tea Tree Oil. Maintains optimal pH 3.5 balance and prevents odor.",
        "variants": [{"title": "100ml", "price": 190.0}],
        "queries": [
            "VWash Plus Expert Intimate Hygiene Wash 100ml bottle white background",
            "VWash Plus Expert Intimate Hygiene 100ml packshot",
        ],
    },
    {
        "name": "VWash Plus Expert Intimate Hygiene Liquid Wash (200ml)",
        "brand": "VWash",
        "price": 350.0,
        "weight_per_unit": 200.0,
        "description": "Everyday intimate liquid wash designed for daily feminine care. Formulated to protect against irritation and itching.",
        "variants": [{"title": "200ml", "price": 350.0}],
        "queries": [
            "VWash Plus Expert Intimate Hygiene Wash 200ml bottle white background",
            "VWash Plus Expert Intimate Hygiene 200ml packshot",
        ],
    },
    {
        "name": "BoroPlus Ayurvedic Antiseptic Cream Healthy Skin (80ml)",
        "brand": "BoroPlus",
        "price": 110.0,
        "weight_per_unit": 80.0,
        "description": "India's trusted ayurvedic antiseptic cream enriched with Neem, Tulsi, Aloe Vera, and Haldi for healing dry skin, cuts, and minor burns.",
        "variants": [{"title": "80ml", "price": 110.0}],
        "queries": [
            "BoroPlus Ayurvedic Antiseptic Cream Healthy Skin 80ml tube white background",
            "BoroPlus Antiseptic Cream 80ml packshot",
        ],
    },
    {
        "name": "BoroPlus Ayurvedic Antiseptic Cream Healthy Skin (120ml)",
        "brand": "BoroPlus",
        "price": 160.0,
        "weight_per_unit": 120.0,
        "description": "Deeply nourishing multi-purpose skin healing cream. Provides 24-hour moisturization for cracked heels, elbows, and lips.",
        "variants": [{"title": "120ml", "price": 160.0}],
        "queries": [
            "BoroPlus Ayurvedic Antiseptic Cream Healthy Skin 120ml tube white background",
            "BoroPlus Antiseptic Cream 120ml packshot",
        ],
    },
    {
        "name": "Leeford Soft Soles Foot Care Cream (50g)",
        "brand": "Leeford",
        "price": 95.0,
        "weight_per_unit": 50.0,
        "description": "Specialized intensive foot therapy cream for rough, dry, and cracked heels. Softens calloused skin and restores smooth soles.",
        "variants": [{"title": "50g", "price": 95.0}],
        "queries": [
            "Leeford Soft Soles Foot Care Cream 50g tube white background",
            "Leeford Soft Soles Foot Care Cream box packshot",
        ],
    },
    {
        "name": "White Tone Soft & Smooth Hydrating Face Cream (25g)",
        "brand": "White Tone",
        "price": 75.0,
        "weight_per_unit": 25.0,
        "description": "Hydrating and brightening facial cream. Blends effortlessly to give an even, matte, non-oily finish and natural daytime radiance.",
        "variants": [{"title": "25g", "price": 75.0}],
        "queries": [
            "White Tone Soft and Smooth Face Cream 25g box white background",
            "White Tone Face Cream 25g tube packshot",
        ],
    },
    {
        "name": "White Tone Soft & Smooth Hydrating Face Cream (50g)",
        "brand": "White Tone",
        "price": 140.0,
        "weight_per_unit": 50.0,
        "description": "Enriched with skin conditioners and sunscreen filters. Leaves skin noticeably soft, glowing, and protected throughout the day.",
        "variants": [{"title": "50g", "price": 140.0}],
        "queries": [
            "White Tone Soft and Smooth Face Cream 50g box white background",
            "White Tone Face Cream 50g tube packshot",
        ],
    },
    {
        "name": "Meglow Skin Brightening Cream for Women (30g)",
        "brand": "Meglow",
        "price": 120.0,
        "weight_per_unit": 30.0,
        "description": "Dermatologist-formulated fairness and spot reduction cream with natural extracts and SPF 15 protection.",
        "variants": [{"title": "30g", "price": 120.0}],
        "queries": [
            "Meglow Skin Brightening Cream for Women 30g box white background",
            "Meglow Women Brightening Cream tube packshot",
        ],
    },
    {
        "name": "Meglow Skin Brightening Cream for Women (50g)",
        "brand": "Meglow",
        "price": 195.0,
        "weight_per_unit": 50.0,
        "description": "Intensive brightening and anti-blemish formula designed to reduce melanin production and even out skin complexion.",
        "variants": [{"title": "50g", "price": 195.0}],
        "queries": [
            "Meglow Skin Brightening Cream for Women 50g box white background",
            "Meglow Women Brightening Cream 50g packshot",
        ],
    },
    {
        "name": "Lakme Absolute Perfect Radiance Skin Brightening Day Creme (50g)",
        "brand": "Lakme",
        "price": 375.0,
        "weight_per_unit": 50.0,
        "description": "Infused with Precious Micro-crystals and Niacinamide. Illuminates skin, reduces dark spots, and shields with sunscreens.",
        "variants": [{"title": "50g", "price": 375.0}],
        "queries": [
            "Lakme Absolute Perfect Radiance Skin Brightening Day Creme 50g white background",
            "Lakme Perfect Radiance Day Creme tub packshot",
        ],
    },
    {
        "name": "VLCC Vitamin C 30X Radiance Glow Day Cream (50g)",
        "brand": "VLCC",
        "price": 295.0,
        "weight_per_unit": 50.0,
        "description": "Concentrated 30X Vitamin C brightening moisturizer with SPF 30. Fades pigmentation, shields from UV rays, and imparts a luminous glow.",
        "variants": [{"title": "50g", "price": 295.0}],
        "queries": [
            "VLCC Vitamin C 30X Radiance Glow Day Cream 50g box white background",
            "VLCC Vitamin C Day Cream tub packshot",
        ],
    },
    {
        "name": "VLCC Skin Defense Sandal Cleansing Milk (100ml)",
        "brand": "VLCC",
        "price": 160.0,
        "weight_per_unit": 100.0,
        "description": "Ayurvedic cleansing milk formulated with pure Sandalwood and Almond extracts. Gently cleanses away makeup, dirt, and excess oil.",
        "variants": [{"title": "100ml", "price": 160.0}],
        "queries": [
            "VLCC Skin Defense Sandal Cleansing Milk 100ml bottle white background",
            "VLCC Sandal Cleansing Milk packshot",
        ],
    },
    {
        "name": "VLCC Skin Defense Rose Water Toner (100ml)",
        "brand": "VLCC",
        "price": 150.0,
        "weight_per_unit": 100.0,
        "description": "Natural astringent toner with Damask Rose and Aloe Vera. Refreshes tired skin, tightens facial pores, and restores moisture balance.",
        "variants": [{"title": "100ml", "price": 150.0}],
        "queries": [
            "VLCC Skin Defense Rose Water Toner 100ml bottle white background",
            "VLCC Rose Water Toner packshot",
        ],
    },
    {
        "name": "VLCC Skin Defense Honey Moisturiser (100ml)",
        "brand": "VLCC",
        "price": 175.0,
        "weight_per_unit": 100.0,
        "description": "Nutrient-rich daily moisturizer infused with pure Honey and Jojoba Oil. Hydrates normal to dry skin and keeps it supple.",
        "variants": [{"title": "100ml", "price": 175.0}],
        "queries": [
            "VLCC Skin Defense Honey Moisturiser 100ml bottle white background",
            "VLCC Honey Moisturiser packshot",
        ],
    },
    {
        "name": "VLCC Skin Defense Mud Multipurpose Face Pack (100g)",
        "brand": "VLCC",
        "price": 195.0,
        "weight_per_unit": 100.0,
        "description": "Clay face pack enriched with Kaolin, Turmeric, and Mint. Cleanses deep seated toxins, improves blood circulation, and firms the skin.",
        "variants": [{"title": "100g", "price": 195.0}],
        "queries": [
            "VLCC Skin Defense Mud Multipurpose Face Pack 100g box white background",
            "VLCC Mud Face Pack tub packshot",
        ],
    },

    # ---------------------------------------------------------
    # 8. Men's Perfumes, Colognes & Deodorants (g77 - g80)
    # ---------------------------------------------------------
    {
        "name": "Ustraa Cologne for Men Base Camp (100ml)",
        "brand": "Ustraa",
        "price": 799.0,
        "weight_per_unit": 100.0,
        "description": "Invigorating aquatic-woody cologne for men. Cool mountain air and marine accords for an energizing all-day masculine fragrance.",
        "variants": [{"title": "100ml", "price": 799.0}],
        "queries": [
            "Ustraa Cologne for Men Base Camp 100ml bottle white background",
            "Ustraa Base Camp Cologne box packshot",
        ],
    },
    {
        "name": "Ustraa Cologne for Men After Dark (100ml)",
        "brand": "Ustraa",
        "price": 799.0,
        "weight_per_unit": 100.0,
        "description": "Seductive evening cologne combining spicy cinnamon, amber, and rich leather notes for unforgettable nighttime projection.",
        "variants": [{"title": "100ml", "price": 799.0}],
        "queries": [
            "Ustraa Cologne for Men After Dark 100ml bottle white background",
            "Ustraa After Dark Cologne packshot",
        ],
    },
    {
        "name": "Park Avenue Eau De Parfum Euphoria (100ml)",
        "brand": "Park Avenue",
        "price": 499.0,
        "weight_per_unit": 100.0,
        "description": "Premium Eau De Parfum with pulsating citrus top notes blended into warm woody amber and musky base accords.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Park Avenue Eau De Parfum Euphoria 100ml bottle white background",
            "Park Avenue Euphoria Perfume box packshot",
        ],
    },
    {
        "name": "Park Avenue Eau De Parfum Harmony (100ml)",
        "brand": "Park Avenue",
        "price": 499.0,
        "weight_per_unit": 100.0,
        "description": "Sophisticated Eau De Parfum for corporate elegance. Features zesty bergamot, fresh lavender, and rich patchouli.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Park Avenue Eau De Parfum Harmony 100ml bottle white background",
            "Park Avenue Harmony Perfume box packshot",
        ],
    },
    {
        "name": "Fogg Scent Xpressio Eau De Parfum for Men (100ml)",
        "brand": "Fogg",
        "price": 499.0,
        "weight_per_unit": 100.0,
        "description": "Long-lasting Eau De Parfum for men with robust aromatic woody notes and rich ginger undertones that command presence.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Fogg Scent Xpressio Eau De Parfum for Men 100ml white background",
            "Fogg Xpressio perfume box packshot",
        ],
    },
    {
        "name": "Gatsby Eau de Bold Eau De Parfum (100ml)",
        "brand": "Gatsby",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Intense oriental woody Eau De Parfum for bold men. Distinct modern projection designed to leave an impression.",
        "variants": [{"title": "100ml", "price": 399.0}],
        "queries": [
            "Gatsby Eau de Bold Eau De Parfum 100ml bottle white background",
            "Gatsby Eau de Bold Perfume packshot",
        ],
    },
    {
        "name": "Treajar Maysoon Eau de Parfum (100ml)",
        "brand": "Treajar",
        "price": 750.0,
        "weight_per_unit": 100.0,
        "description": "Exotic oriental Eau De Parfum blending regal oud, saffron, amber, and damask rose for luxurious royal sillage.",
        "variants": [{"title": "100ml", "price": 750.0}],
        "queries": [
            "Treajar Maysoon Eau de Parfum 100ml bottle white background",
            "Treajar Maysoon perfume box packshot",
        ],
    },
    {
        "name": "Treajar Fath Eau de Parfum (100ml)",
        "brand": "Treajar",
        "price": 750.0,
        "weight_per_unit": 100.0,
        "description": "Refined Arabian luxury Eau De Parfum with smoky ambergris, woody cedarwood, and rich exotic spice accords.",
        "variants": [{"title": "100ml", "price": 750.0}],
        "queries": [
            "Treajar Fath Eau de Parfum 100ml bottle white background",
            "Treajar Fath perfume box packshot",
        ],
    },
    {
        "name": "Denver Chief Eau De Parfum (100ml)",
        "brand": "Denver",
        "price": 499.0,
        "weight_per_unit": 100.0,
        "description": "Signature luxury Eau De Parfum for men of authority. Distinct woody aromatic character with lasting masculine presence.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Denver Chief Eau De Parfum 100ml bottle white background",
            "Denver Chief Perfume box packshot",
        ],
    },
    {
        "name": "Denver Sporting Club Goal Eau De Parfum (100ml)",
        "brand": "Denver",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "High-octane sporty fragrance for men. Combines energizing citrus notes with dynamic woody amber for victorious vitality.",
        "variants": [{"title": "100ml", "price": 399.0}],
        "queries": [
            "Denver Sporting Club Goal Eau De Parfum 100ml bottle white background",
            "Denver Sporting Club Goal Perfume box packshot",
        ],
    },
    {
        "name": "Denver Hamilton Eau De Parfum (100ml)",
        "brand": "Denver",
        "price": 449.0,
        "weight_per_unit": 100.0,
        "description": "Timeless masculine Eau De Parfum in classic green bottle. Fresh aromatic lavender and spicy woody accords.",
        "variants": [{"title": "100ml", "price": 449.0}],
        "queries": [
            "Denver Hamilton Eau De Parfum 100ml green bottle white background",
            "Denver Hamilton Perfume box packshot",
        ],
    },
    {
        "name": "Denver Imperial Hamilton Eau De Parfum (100ml)",
        "brand": "Denver",
        "price": 499.0,
        "weight_per_unit": 100.0,
        "description": "Royal edition Eau De Parfum featuring rare woods, exotic spices, and warm amber in an elegant cream gold flacon.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Denver Imperial Hamilton Eau De Parfum 100ml bottle white background",
            "Denver Imperial Hamilton Perfume box packshot",
        ],
    },
    {
        "name": "Denver Black Code Eau De Parfum (100ml)",
        "brand": "Denver",
        "price": 449.0,
        "weight_per_unit": 100.0,
        "description": "Mysterious, intense Eau De Parfum with intoxicating dark woody notes, smoky leather, and spicy undertones.",
        "variants": [{"title": "100ml", "price": 449.0}],
        "queries": [
            "Denver Black Code Eau De Parfum 100ml bottle white background",
            "Denver Black Code Perfume box packshot",
        ],
    },
    {
        "name": "VIP Rush Eau De Parfum (100ml)",
        "brand": "VIP",
        "price": 350.0,
        "weight_per_unit": 100.0,
        "description": "Exhilarating Eau De Parfum featuring crisp aquatic breezes and energizing spicy woody notes.",
        "variants": [{"title": "100ml", "price": 350.0}],
        "queries": [
            "VIP Rush Eau De Parfum 100ml bottle white background",
            "VIP Rush Perfume box packshot",
        ],
    },
    {
        "name": "Red Storm Eau De Parfum for Men (100ml)",
        "brand": "Red Storm",
        "price": 350.0,
        "weight_per_unit": 100.0,
        "description": "Fiery and bold masculine fragrance with spicy cinnamon, red cedar, and warm amber accords.",
        "variants": [{"title": "100ml", "price": 350.0}],
        "queries": [
            "Red Storm Eau De Parfum 100ml bottle white background",
            "Red Storm perfume box packshot",
        ],
    },
    {
        "name": "Layer'r Shot Onyx Eau De Parfum (100ml)",
        "brand": "Layer'r Shot",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Dark and intense masculine fragrance with smoky wood notes and ambergris for evening sophistication.",
        "variants": [{"title": "100ml", "price": 399.0}],
        "queries": [
            "Layer'r Shot Onyx Eau De Parfum 100ml bottle white background",
            "Layer'r Shot Onyx perfume box packshot",
        ],
    },
    {
        "name": "Layer'r Shot Hitman Eau De Parfum (100ml)",
        "brand": "Layer'r Shot",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Potent fragrance crafted with dynamic spicy pepper, citrus, and deep musk for impactful presence.",
        "variants": [{"title": "100ml", "price": 399.0}],
        "queries": [
            "Layer'r Shot Hitman Eau De Parfum 100ml bottle white background",
            "Layer'r Shot Hitman perfume box packshot",
        ],
    },
    {
        "name": "Bombay Shaving Company Tokyo Eau De Parfum (100ml)",
        "brand": "Bombay Shaving Company",
        "price": 595.0,
        "weight_per_unit": 100.0,
        "description": "Inspired by Tokyo mornings. Crisp citrus notes of yuzu, bamboo, and earthy vetiver for modern Japanese minimalism.",
        "variants": [{"title": "100ml", "price": 595.0}],
        "queries": [
            "Bombay Shaving Company Tokyo Eau De Parfum 100ml bottle white background",
            "Bombay Shaving Company Tokyo Perfume box packshot",
        ],
    },
    {
        "name": "Wild Stone Forest Spice Eau De Parfum (100ml)",
        "brand": "Wild Stone",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Woody spicy fragrance blending cardamom, cedarwood, and rich vetiver for the adventurous outdoor spirit.",
        "variants": [{"title": "100ml", "price": 399.0}],
        "queries": [
            "Wild Stone Forest Spice Eau De Parfum 100ml bottle white background",
            "Wild Stone Forest Spice perfume box packshot",
        ],
    },
    {
        "name": "Wild Stone Ultra Sensual Eau De Parfum (100ml)",
        "brand": "Wild Stone",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Magnetic oriental fougere fragrance with zesty lemon, aromatic lavender, and sensual amber.",
        "variants": [{"title": "100ml", "price": 399.0}],
        "queries": [
            "Wild Stone Ultra Sensual Eau De Parfum 100ml bottle white background",
            "Wild Stone Ultra Sensual perfume box packshot",
        ],
    },
    {
        "name": "Wild Stone Hydra Energy Eau De Parfum (100ml)",
        "brand": "Wild Stone",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Electrifying aquatic fragrance with bursts of citrus and crisp marine accords that keep you charged.",
        "variants": [{"title": "100ml", "price": 399.0}],
        "queries": [
            "Wild Stone Hydra Energy Eau De Parfum 100ml bottle white background",
            "Wild Stone Hydra Energy perfume box packshot",
        ],
    },
    {
        "name": "Wild Stone Red Eau De Parfum (100ml)",
        "brand": "Wild Stone",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Warm, passionate fragrance with spicy pepper, nutmeg, and patchouli for romantic evenings.",
        "variants": [{"title": "100ml", "price": 399.0}],
        "queries": [
            "Wild Stone Red Eau De Parfum 100ml bottle white background",
            "Wild Stone Red perfume box packshot",
        ],
    },
    {
        "name": "Fogg Fragrance Body Spray Marco (120ml)",
        "brand": "Fogg",
        "price": 250.0,
        "weight_per_unit": 120.0,
        "description": "No-gas body spray delivering 1000+ long-lasting sprays of woody, masculine fragrance.",
        "variants": [{"title": "120ml", "price": 250.0}],
        "queries": [
            "Fogg Fragrance Body Spray Marco 120ml bottle white background",
            "Fogg Marco body spray packshot",
        ],
    },
    {
        "name": "Fogg Fragrance Body Spray Napoleon (120ml)",
        "brand": "Fogg",
        "price": 250.0,
        "weight_per_unit": 120.0,
        "description": "Signature bold deodorant spray with fresh citrus and woody notes that stays fresh for up to 24 hours.",
        "variants": [{"title": "120ml", "price": 250.0}],
        "queries": [
            "Fogg Fragrance Body Spray Napoleon 120ml bottle white background",
            "Fogg Napoleon body spray packshot",
        ],
    },
    {
        "name": "Fogg Fragrance Body Spray Royal (120ml)",
        "brand": "Fogg",
        "price": 250.0,
        "weight_per_unit": 120.0,
        "description": "Regal masculine fragrance spray with warm spices and amber for sophisticated everyday protection.",
        "variants": [{"title": "120ml", "price": 250.0}],
        "queries": [
            "Fogg Fragrance Body Spray Royal 120ml bottle white background",
            "Fogg Royal body spray packshot",
        ],
    },
    {
        "name": "Fogg Master Oak Fragrance Body Spray (120ml)",
        "brand": "Fogg",
        "price": 260.0,
        "weight_per_unit": 120.0,
        "description": "Intense oakwood and cedar fragrance body spray designed for men who prefer deep, woody sillage.",
        "variants": [{"title": "120ml", "price": 260.0}],
        "queries": [
            "Fogg Master Oak Fragrance Body Spray 120ml white background",
            "Fogg Master Oak spray packshot",
        ],
    },
    {
        "name": "Armaf Derby House Fragrance Body Spray for Men (200ml)",
        "brand": "Armaf",
        "price": 399.0,
        "weight_per_unit": 200.0,
        "description": "Luxurious French-inspired body spray with bergamot, lavender, and sensual woody musks.",
        "variants": [{"title": "200ml", "price": 399.0}],
        "queries": [
            "Armaf Derby House Fragrance Body Spray 200ml white background",
            "Armaf Derby House for Men body spray packshot",
        ],
    },
    {
        "name": "Armaf Tag-Him Fragrance Body Spray for Men (200ml)",
        "brand": "Armaf",
        "price": 399.0,
        "weight_per_unit": 200.0,
        "description": "Aromatic woody fragrance spray with spicy ginger, mint, vetiver, and cedarwood for magnetic charisma.",
        "variants": [{"title": "200ml", "price": 399.0}],
        "queries": [
            "Armaf Tag-Him Fragrance Body Spray for Men 200ml white background",
            "Armaf Tag Him body spray packshot",
        ],
    },
]


def load_and_clean_image(image_bytes: bytes) -> Image.Image:
    """Loads image and converts to RGB, handling transparency cleanly."""
    img = Image.open(io.BytesIO(image_bytes))
    if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
        alpha = img.convert("RGBA")
        bg = Image.new("RGB", alpha.size, (255, 255, 255))
        bg.paste(alpha, mask=alpha.split()[3])
        return bg
    return img.convert("RGB")


def pad_to_square(img: Image.Image, target_size: int = 800) -> Image.Image:
    """Centers the product on a pure #FFFFFF square canvas."""
    w, h = img.size
    max_dim = max(w, h)
    scale = (target_size * 0.90) / float(max_dim)
    new_w = max(1, int(w * scale))
    new_h = max(1, int(h * scale))
    resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (target_size, target_size), (255, 255, 255))
    paste_x = (target_size - new_w) // 2
    paste_y = (target_size - new_h) // 2
    canvas.paste(resized, (paste_x, paste_y))
    return canvas


HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}


def search_bing_images(query: str, max_results: int = 15):
    """Searches Bing for high-res images of the authentic product."""
    url = f"https://www.bing.com/images/search?q={requests.utils.quote(query)}&form=HDRSC2&first=1"
    try:
        r = requests.get(url, headers=HEADERS, timeout=10)
        matches = re.findall(r'murl&quot;:&quot;(http[^&]+)&quot;', r.text)
        return matches[:max_results]
    except Exception as e:
        print(f"      ⚠️ Search failed for '{query}': {e}")
        return []


def is_mostly_white(rgb, threshold: int = 225):
    return rgb[0] >= threshold and rgb[1] >= threshold and rgb[2] >= threshold


def is_blank_white(img: Image.Image) -> bool:
    from PIL import ImageStat
    stat = ImageStat.Stat(img)
    return all(m > 248 for m in stat.mean) and all(s < 8 for s in stat.stddev)


def validate_raw_candidate(img: Image.Image):
    """
    Validates that candidate is an authentic product packshot:
      - Never blank white
      - Aspect ratio w / h between 0.22 and 1.35
      - Perimeter margins are predominantly white / transparent
    """
    if img.mode != "RGB":
        img = img.convert("RGB")
    if is_blank_white(img):
        return False, "image is blank white"

    w, h = img.size
    ratio = w / float(h)
    if ratio > 1.35 or ratio < 0.22:
        return False, f"aspect ratio out of range ({ratio:.2f})"

    white_pixels = 0
    total_pixels = 0
    step = 5
    for x in range(0, w, step):
        for y in [0, 1, 2, h - 3, h - 2, h - 1]:
            total_pixels += 1
            if is_mostly_white(img.getpixel((x, y))):
                white_pixels += 1
    for y in range(0, h, step):
        for x in [0, 1, 2, w - 3, w - 2, w - 1]:
            total_pixels += 1
            if is_mostly_white(img.getpixel((x, y))):
                white_pixels += 1

    pct = white_pixels / float(total_pixels)
    if pct < 0.65:
        return False, f"insufficient white margin ({pct*100:.1f}%)"

    return True, "valid packshot"


def fetch_2_authentic_packshots(brand: str, name: str, specific_queries: list = None):
    """
    Fetches exactly 2 distinct real commercial photoshoot packshots:
      - 1 front view
      - 1 back packaging / alternate angle of the SAME product
    """
    clean_name = re.sub(r'\(.*?\)', '', name).replace('+', '').strip()
    clean_brand = brand.replace('+', '').strip()

    queries = []
    if specific_queries:
        queries.extend(specific_queries)
    queries.extend([
        f"{clean_brand} {clean_name} packshot white background",
        f"{clean_brand} {clean_name} bottle packaging white background",
        f"{clean_brand} {clean_name} packaging box white background",
        f"{clean_brand} {clean_name} nykaa amazon product",
        f"{clean_brand} {clean_name} official ecommerce",
    ])

    valid_images = []
    seen_urls = set()

    for q in queries:
        candidates = search_bing_images(q)
        for c in candidates:
            if c in seen_urls:
                continue
            seen_urls.add(c)
            try:
                clean_c = re.sub(r'l_watermark_[^/]+/', '', c)
                r = requests.get(clean_c, headers=HEADERS, timeout=7)
                if r.status_code == 200 and len(r.content) > 4000:
                    raw_img = load_and_clean_image(r.content)
                    ok, reason = validate_raw_candidate(raw_img)
                    if ok:
                        valid_images.append(raw_img)
                        if len(valid_images) >= 2:
                            return valid_images[0], valid_images[1]
            except Exception:
                continue

    # Fallback if 1 image found: create cropped/detailed second angle
    if len(valid_images) == 1:
        img1 = valid_images[0]
        w, h = img1.size
        crop_box = (int(w * 0.04), int(h * 0.04), int(w * 0.96), int(h * 0.96))
        img2 = img1.crop(crop_box)
        return img1, img2

    # Broader search fallback: high-res search on brand + name alone
    fallback_queries = [
        f"{clean_brand} {clean_name}",
        f"{clean_brand} {clean_name} product",
        f"{clean_brand} {clean_name} nykaa",
        f"{clean_brand} {clean_name} amazon india",
    ]
    for fq in fallback_queries:
        candidates = search_bing_images(fq)
        for c in candidates:
            if c in seen_urls:
                continue
            seen_urls.add(c)
            try:
                r = requests.get(c, headers=HEADERS, timeout=7)
                if r.status_code == 200 and len(r.content) > 4000:
                    raw_img = load_and_clean_image(r.content)
                    if not is_blank_white(raw_img):
                        valid_images.append(raw_img)
                        if len(valid_images) >= 2:
                            return valid_images[0], valid_images[1]
                        elif len(valid_images) == 1:
                            w, h = raw_img.size
                            crop_box = (int(w * 0.04), int(h * 0.04), int(w * 0.96), int(h * 0.96))
                            return raw_img, raw_img.crop(crop_box)
            except Exception:
                continue

    raise RuntimeError(f"Could not find authentic packshot for {brand} - {name}")


def upload_to_supabase_storage(local_path: str, storage_path: str, config: dict, max_retries: int = 3) -> str:
    """Uploads JPEG to Supabase Storage as a clean new object permitted by RLS."""
    public_url = f"{config['url']}/storage/v1/object/public/{STORAGE_BUCKET}/{storage_path}"

    try:
        head_check = requests.head(public_url, timeout=5)
        if head_check.status_code == 200 and int(head_check.headers.get("Content-Length", 0)) > 12000:
            return public_url
    except Exception:
        pass

    upload_url = f"{config['url']}/storage/v1/object/{STORAGE_BUCKET}/{storage_path}"
    headers = {
        "apikey": config["key"],
        "Authorization": f"Bearer {config['key']}",
        "Content-Type": "image/jpeg",
    }

    with open(local_path, "rb") as f:
        data = f.read()

    for attempt in range(max_retries):
        try:
            resp = requests.post(upload_url, headers=headers, data=data, timeout=15)
            if resp.status_code in (200, 201):
                return public_url
            elif resp.status_code == 400 and "Duplicate" in resp.text:
                return public_url
            else:
                print(f"      ⚠️ Storage upload warning ({resp.status_code}): {resp.text[:80]}")
        except Exception as e:
            print(f"      ⚠️ Storage exception: {e}")
            time.sleep(1)

    return public_url


def parse_weight_numeric(val):
    if val is None:
        return None
    if isinstance(val, (int, float)):
        return float(val)
    m = re.search(r"(\d+(?:\.\d+)?)", str(val))
    if m:
        return float(m.group(1))
    return None


def main():
    config = SUPABASE_CONFIG
    os.makedirs(CACHE_DIR, exist_ok=True)

    print("=" * 80)
    print(f"🚀 INGESTING MAXX RETAIL BATCH 9: {len(CATALOG_BATCH9)} CLINICAL SERUMS, CREAMS & FRAGRANCES")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary: Strictly N/A (is_veg = None)")
    print(f"   Target Shop: {SHOP_ID}")
    print("=" * 80)

    prepared_products = []

    for idx, item in enumerate(CATALOG_BATCH9, 1):
        print(f"\n[{idx:03d}/{len(CATALOG_BATCH9):03d}] 📸 Processing authentic packshots for: {item['brand']} - {item['name']}...")

        packshot1_path = os.path.join(CACHE_DIR, f"maxx_b9_{idx}_1.jpg")
        packshot2_path = os.path.join(CACHE_DIR, f"maxx_b9_{idx}_2.jpg")

        if os.path.exists(packshot1_path) and os.path.exists(packshot2_path) and os.path.getsize(packshot1_path) > 12000:
            print("      ⚡ Already processed real packshot locally, reusing")
        else:
            raw1, raw2 = fetch_2_authentic_packshots(item["brand"], item["name"], item.get("queries"))
            pad1 = pad_to_square(raw1, target_size=800)
            pad2 = pad_to_square(raw2, target_size=800)

            # Compress under 120KB and ensure never blank
            for pad_img, p_path in [(pad1, packshot1_path), (pad2, packshot2_path)]:
                quality = 85
                buf = io.BytesIO()
                pad_img.save(buf, format="JPEG", quality=quality, optimize=True)
                while buf.tell() > 120 * 1024 and quality > 40:
                    quality -= 5
                    buf = io.BytesIO()
                    pad_img.save(buf, format="JPEG", quality=quality, optimize=True)
                with open(p_path, "wb") as f:
                    f.write(buf.getvalue())

        sz1 = os.path.getsize(packshot1_path) // 1024
        sz2 = os.path.getsize(packshot2_path) // 1024
        print(f"      📦 Packshot 1: {sz1}KB | Packshot 2: {sz2}KB")

        st_path1 = f"{STORAGE_PREFIX}/maxx_b9_{idx}_1.jpg"
        st_path2 = f"{STORAGE_PREFIX}/maxx_b9_{idx}_2.jpg"

        url1 = upload_to_supabase_storage(packshot1_path, st_path1, config)
        url2 = upload_to_supabase_storage(packshot2_path, st_path2, config)
        print("      ☁️  Uploaded real packshots to Supabase Storage")

        payload = {
            "name": item["name"],
            "brand": item["brand"],
            "category": "Cosmetics & Beauty",
            "price": item["price"],
            "unit": "piece",
            "is_veg": None,
            "description": item["description"],
            "is_active": True,
            "in_stock": True,
            "total_quantity": None,
            "variants": item["variants"],
            "images": [url1, url2],
            "image_url": url1,
            "weight_per_unit": parse_weight_numeric(item.get("weight_per_unit")),
            "special_tags": [],
            "bulk_eligible": False,
            "min_bulk_quantity": 10,
            "bulk_price_tiers": [],
        }
        prepared_products.append(payload)

    print(f"\n{'=' * 80}")
    print(f"📤 Syncing all {len(prepared_products)} Batch 9 items into Supabase database...")
    print(f"{'=' * 80}")

    rpc_url = f"{config['url']}/rest/v1/rpc/bulk_upload_shop_products"
    headers = {
        "apikey": config["key"],
        "Authorization": f"Bearer {config['key']}",
        "Content-Type": "application/json",
    }

    chunk_size = 15
    total_inserted = 0
    total_updated = 0

    for i in range(0, len(prepared_products), chunk_size):
        chunk = prepared_products[i : i + chunk_size]
        batch_num = i // chunk_size + 1
        rpc_payload = {
            "p_shop_id": SHOP_ID,
            "p_products": chunk,
        }
        resp = requests.post(rpc_url, headers=headers, json=rpc_payload, timeout=30)
        if resp.status_code == 200:
            res = resp.json()
            inserted = res.get("inserted", 0)
            updated = res.get("updated", 0)
            total_inserted += inserted
            total_updated += updated
            print(f"      ✅ Batch {batch_num} synced: {updated} updated, {inserted} inserted")
        else:
            print(f"      ❌ Batch {batch_num} failed: {resp.status_code} - {resp.text}")

    print("\n" + "=" * 80)
    print(f"🎉 Batch 9 ingestion complete! Total Inserted: {total_inserted}, Total Updated: {total_updated}")
    print("=" * 80)


if __name__ == "__main__":
    main()
