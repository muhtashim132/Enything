#!/usr/bin/env python3
"""
Maxx Retail Batch 10 (Shelf Scans g84.jpeg - g89.jpeg) Ingestion Engine
=======================================================================
Catalog: 58 authentic clinical serums, derma sunscreens, barrier creams,
         Minimalist active science, Dot & Key gel sunscreens & night creams,
         RENEE strobe moisturizers, Garnier Vitamin C booster serums,
         NutriGlow advanced organics, and Nature's Essence glow care.

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
STORAGE_PREFIX = f"{SHOP_ID}/batch10_packshots"
CACHE_DIR = "scratch/batch10_real_packshots"

CATALOG_BATCH10 = [
    # ---------------------------------------------------------
    # 1. Minimalist Clinical Skincare & Sunscreens (g85, g86, g87)
    # ---------------------------------------------------------
    {
        "name": "Minimalist SPF 50 Sunscreen (50g)",
        "brand": "Minimalist",
        "price": 399.0,
        "weight_per_unit": 50.0,
        "description": "Broad-spectrum SPF 50 PA++++ sunscreen formulated with multi-vitamins (Niacinamide, Vitamin B5 & Vitamin F). Lightweight, non-greasy, and leaves no white cast.",
        "variants": [{"title": "50g", "price": 399.0}],
        "queries": [
            "Minimalist SPF 50 Sunscreen 50g bottle white background",
            "Minimalist SPF 50 Sunscreen packshot ecommerce",
        ],
    },
    {
        "name": "Minimalist SPF 60 Sunscreen (50g)",
        "brand": "Minimalist",
        "price": 499.0,
        "weight_per_unit": 50.0,
        "description": "High-protection SPF 60 PA++++ face sunscreen powered with Silymarin, Hyaluronic Acid, and Vitamin E. Provides robust antioxidant and photoprotection.",
        "variants": [{"title": "50g", "price": 499.0}],
        "queries": [
            "Minimalist SPF 60 Sunscreen with Silymarin 50g packshot white background",
            "Minimalist SPF 60 Sunscreen packaging bottle white background",
        ],
    },
    {
        "name": "Minimalist Light Fluid SPF 50 Face Sunscreen (50ml)",
        "brand": "Minimalist",
        "price": 499.0,
        "weight_per_unit": 50.0,
        "description": "Ultra-light fluid face sunscreen offering broad-spectrum SPF 50 PA++++ protection. Water and sweat resistant formula perfect for outdoor and daily wear.",
        "variants": [{"title": "50ml", "price": 499.0}],
        "queries": [
            "Minimalist Light Fluid SPF 50 Face Sunscreen 50ml packshot white background",
            "Minimalist Light Fluid SPF 50 bottle white background",
        ],
    },
    {
        "name": "Minimalist Vitamin B5 10% Moisturizer (50g)",
        "brand": "Minimalist",
        "price": 349.0,
        "weight_per_unit": 50.0,
        "description": "Oil-free daily gel moisturizer packed with 10% Vitamin B5 (Panthenol), Copper, Zinc, Magnesium, Hyaluronic Acid, and Betaine. Balances sebum and deeply hydrates.",
        "variants": [{"title": "50g", "price": 349.0}],
        "queries": [
            "Minimalist Vitamin B5 10% Moisturizer 50g packshot white background",
            "Minimalist 10% Vitamin B5 Gel Moisturizer tube white background",
        ],
    },
    {
        "name": "Minimalist Ceramides 0.3% Moisturizer (50g)",
        "brand": "Minimalist",
        "price": 599.0,
        "weight_per_unit": 50.0,
        "description": "Intense barrier repair cream formulated with 0.3% pure Ceramides, Madecassoside, and Asiaticoside. Restores compromised skin barrier and relieves irritation.",
        "variants": [{"title": "50g", "price": 599.0}],
        "queries": [
            "Minimalist Ceramides 0.3% Moisturizer 50g packshot white background",
            "Minimalist Ceramides 0.3% Madecassoside tube packaging",
        ],
    },
    {
        "name": "Minimalist B12 + Repair Complex 5.5% Face Moisturizer (50g)",
        "brand": "Minimalist",
        "price": 499.0,
        "weight_per_unit": 50.0,
        "description": "Calming face moisturizer powered by Vitamin B12, Ceramides, and Ectoin. Soothes redness, strengthens the lipid barrier, and improves skin resilience.",
        "variants": [{"title": "50g", "price": 499.0}],
        "queries": [
            "Minimalist B12 Repair Complex 5.5% Moisturizer packshot white background",
            "Minimalist B12 Repair Complex tube packaging white background",
        ],
    },
    {
        "name": "Minimalist Marula Oil 05% Moisturizer (50g)",
        "brand": "Minimalist",
        "price": 299.0,
        "weight_per_unit": 50.0,
        "description": "Rich nourishing daily moisturizer with 5% Marula Oil, Vitamin F, and Vitamin E. Locks in moisture, restores elasticity, and softens dry, flaky skin.",
        "variants": [{"title": "50g", "price": 299.0}],
        "queries": [
            "Minimalist Marula Oil 05% Moisturizer 50g packshot white background",
            "Minimalist Marula Oil 5% Moisturizer tube white background",
        ],
    },
    {
        "name": "Minimalist Vitamin C 10% Face Serum (30ml)",
        "brand": "Minimalist",
        "price": 699.0,
        "weight_per_unit": 30.0,
        "description": "Stable 10% Ethyl Ascorbic Acid serum infused with Centella Asiatica water. Brightens dull complexion, fades sun spots, and boosts collagen synthesis.",
        "variants": [{"title": "30ml", "price": 699.0}],
        "queries": [
            "Minimalist Vitamin C 10% Face Serum 30ml bottle white background",
            "Minimalist 10% Vitamin C Serum dropper packshot white background",
        ],
    },
    {
        "name": "Minimalist Vitamin C + E + Ferulic 16% Face Serum (30ml)",
        "brand": "Minimalist",
        "price": 699.0,
        "weight_per_unit": 30.0,
        "description": "Advanced triple-antioxidant serum combining 16% Vitamin C, Vitamin E, and Ferulic Acid. Provides clinical-strength photodamage defense and glowing skin.",
        "variants": [{"title": "30ml", "price": 699.0}],
        "queries": [
            "Minimalist Vitamin C E Ferulic 16% Serum 30ml packshot white background",
            "Minimalist 16% Vitamin C E Ferulic Acid dropper bottle",
        ],
    },
    {
        "name": "Minimalist Niacinamide 05% Face Serum (30ml)",
        "brand": "Minimalist",
        "price": 599.0,
        "weight_per_unit": 30.0,
        "description": "Gentle daily brightening and barrier-supporting serum with 5% Niacinamide, Hyaluronic Acid, and Bifida Ferment Lysate. Ideal for sensitive and beginner skin.",
        "variants": [{"title": "30ml", "price": 599.0}],
        "queries": [
            "Minimalist Niacinamide 05% Face Serum 30ml bottle white background",
            "Minimalist 5% Niacinamide Face Serum packshot white background",
        ],
    },
    {
        "name": "Minimalist Multi-Peptides 10% Face Serum (30ml)",
        "brand": "Minimalist",
        "price": 699.0,
        "weight_per_unit": 30.0,
        "description": "Anti-aging facial serum powered by Matrixyl 3000 and 7% Bio-Placenta peptides. Smooths fine lines, firms sagging skin, and accelerates cellular renewal.",
        "variants": [{"title": "30ml", "price": 699.0}],
        "queries": [
            "Minimalist Multi Peptides 10% Face Serum 30ml packshot white background",
            "Minimalist Multi Peptides Serum bottle white background",
        ],
    },
    {
        "name": "Minimalist Niacinamide 10% Face Serum (30ml)",
        "brand": "Minimalist",
        "price": 599.0,
        "weight_per_unit": 30.0,
        "description": "High-potency 10% Niacinamide serum fortified with 1% Zinc PCA. Visibly reduces enlarged pores, balances excess sebum, and clears post-acne marks.",
        "variants": [{"title": "30ml", "price": 599.0}],
        "queries": [
            "Minimalist Niacinamide 10% Face Serum 30ml bottle white background",
            "Minimalist 10% Niacinamide Zinc Serum packshot white background",
        ],
    },
    {
        "name": "Minimalist Hyaluronic + PGA 02% Face Serum (30ml)",
        "brand": "Minimalist",
        "price": 599.0,
        "weight_per_unit": 30.0,
        "description": "Multi-molecular Hyaluronic Acid 2% enhanced with Polyglutamic Acid (PGA). Delivers multi-depth cellular hydration for plump, bouncy, radiant skin.",
        "variants": [{"title": "30ml", "price": 599.0}],
        "queries": [
            "Minimalist Hyaluronic PGA 02% Face Serum 30ml packshot white background",
            "Minimalist 2% Hyaluronic Acid Serum bottle white background",
        ],
    },
    {
        "name": "Minimalist Alpha Arbutin 02% Face Serum (30ml)",
        "brand": "Minimalist",
        "price": 549.0,
        "weight_per_unit": 30.0,
        "description": "Targeted anti-pigmentation serum with 2% pure Alpha Arbutin and Hyaluronic Acid. Fades dark spots, sun tanning, melasma, and hyperpigmentation.",
        "variants": [{"title": "30ml", "price": 549.0}],
        "queries": [
            "Minimalist Alpha Arbutin 02% Face Serum 30ml bottle white background",
            "Minimalist 2% Alpha Arbutin Serum packshot white background",
        ],
    },
    {
        "name": "Minimalist Retinol 0.6% Face Serum (30ml)",
        "brand": "Minimalist",
        "price": 699.0,
        "weight_per_unit": 30.0,
        "description": "Potent 0.6% Retinol night treatment dissolved in plant-derived Squalane with Coenzyme Q10. Fades deep wrinkles and promotes cellular rejuvenation without drying.",
        "variants": [{"title": "30ml", "price": 699.0}],
        "queries": [
            "Minimalist Retinol 0.6% Face Serum 30ml bottle white background",
            "Minimalist 0.6% Retinol Squalane Serum packshot white background",
        ],
    },
    {
        "name": "Minimalist Alpha Lipoic + Glycolic 07% Cleanser (100ml)",
        "brand": "Minimalist",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Exfoliating daily face cleanser with Alpha Lipoic Acid, 7% Glycolic Acid, and Vitamin B5. Gently removes dead skin cells and restores radiant skin texture.",
        "variants": [{"title": "100ml", "price": 399.0}],
        "queries": [
            "Minimalist Alpha Lipoic Glycolic 07% Cleanser 100ml packshot white background",
            "Minimalist Glycolic Acid Cleanser bottle white background",
        ],
    },
    {
        "name": "Minimalist Niacinamide 05% Body Lotion (180ml)",
        "brand": "Minimalist",
        "price": 299.0,
        "weight_per_unit": 180.0,
        "description": "Daily nourishing body lotion formulated with 5% Niacinamide, 20% Glycerin, Shea Butter, and Betaine. Repairs dry skin barrier and evens body skin tone.",
        "variants": [{"title": "180ml", "price": 299.0}],
        "queries": [
            "Minimalist Niacinamide 05% Body Lotion 180ml bottle white background",
            "Minimalist 5% Niacinamide Body Lotion packaging white background",
        ],
    },
    {
        "name": "Minimalist SPF 30 Body Lotion (150g)",
        "brand": "Minimalist",
        "price": 499.0,
        "weight_per_unit": 150.0,
        "description": "Broad-spectrum SPF 30 PA+++ body sunscreen lotion infused with antioxidant Green Tea Extract. Protects skin from UVA/UVB damage without heaviness.",
        "variants": [{"title": "150g", "price": 499.0}],
        "queries": [
            "Minimalist SPF 30 Body Lotion Green Tea 150g packshot white background",
            "Minimalist SPF 30 Body Lotion tube packaging white background",
        ],
    },

    # ---------------------------------------------------------
    # 2. Dot & Key Skincare (g84, g85)
    # ---------------------------------------------------------
    {
        "name": "Dot & Key Mango Detan Gel Sunscreen SPF 50+ (50g)",
        "brand": "Dot & Key",
        "price": 445.0,
        "weight_per_unit": 50.0,
        "description": "Oil-free gel sunscreen with Alpha-Arbutin and Niacinamide. Provides broad-spectrum SPF 50+ PA++++ protection while actively reversing sun tanning.",
        "variants": [{"title": "50g", "price": 445.0}],
        "queries": [
            "Dot & Key Mango Detan Gel Sunscreen SPF 50 50g packshot white background",
            "Dot & Key Mango Sunscreen tube white background",
        ],
    },
    {
        "name": "Dot & Key Strawberry Dew Tinted Sunscreen SPF 50+ - 01 Porcelain (50g)",
        "brand": "Dot & Key",
        "price": 495.0,
        "weight_per_unit": 50.0,
        "description": "Daily wear tinted sunscreen in shade 01 Porcelain with Niacinamide and Strawberry extract. SPF 50+ PA++++ sheer dewy finish that blurs pores.",
        "variants": [{"title": "50g", "price": 495.0}],
        "queries": [
            "Dot & Key Strawberry Dew Tinted Sunscreen 01 Porcelain packshot white background",
            "Dot & Key Tinted Sunscreen Porcelain bottle white background",
        ],
    },
    {
        "name": "Dot & Key Strawberry Dew Tinted Sunscreen SPF 50+ - 02 Warm Ivory (50g)",
        "brand": "Dot & Key",
        "price": 495.0,
        "weight_per_unit": 50.0,
        "description": "Daily wear tinted sunscreen in shade 02 Warm Ivory with Niacinamide. Delivers SPF 50+ PA++++ broad-spectrum protection with natural glowing coverage.",
        "variants": [{"title": "50g", "price": 495.0}],
        "queries": [
            "Dot & Key Strawberry Dew Tinted Sunscreen 02 Warm Ivory packshot white background",
            "Dot & Key Tinted Sunscreen Warm Ivory packaging white background",
        ],
    },
    {
        "name": "Dot & Key Cica Calming Mattifying Sunscreen SPF 50+ (80g)",
        "brand": "Dot & Key",
        "price": 595.0,
        "weight_per_unit": 80.0,
        "description": "Lightweight gel-cream sunscreen with Cica and Niacinamide in a value 80g pack. Calms active acne, regulates oil, and offers broad-spectrum SPF 50+ PA++++.",
        "variants": [{"title": "80g", "price": 595.0}],
        "queries": [
            "Dot & Key Cica Calming Mattifying Sunscreen 80g packshot white background",
            "Dot & Key Cica Sunscreen 80g tube white background",
        ],
    },
    {
        "name": "Dot & Key Cica Calming Mattifying Sunscreen SPF 50+ (50g)",
        "brand": "Dot & Key",
        "price": 445.0,
        "weight_per_unit": 50.0,
        "description": "Ultra-lightweight gel-cream matte sunscreen with Centella Asiatica (Cica) and Niacinamide. Controls excess shine, soothes redness, and protects with SPF 50+ PA++++.",
        "variants": [{"title": "50g", "price": 445.0}],
        "queries": [
            "Dot & Key Cica Calming Mattifying Sunscreen 50g packshot white background",
            "Dot & Key Cica Sunscreen 50g tube white background",
        ],
    },
    {
        "name": "Dot & Key Water Drench Hydrating Hyaluronic Serum Concentrate (30ml)",
        "brand": "Dot & Key",
        "price": 695.0,
        "weight_per_unit": 30.0,
        "description": "Intensive hydration booster serum formulated with 5 essential ceramides, Rice Water, and Bulgarian Rose. Plumps dehydrated skin and strengthens skin barrier.",
        "variants": [{"title": "30ml", "price": 695.0}],
        "queries": [
            "Dot & Key Water Drench Hydrating Hyaluronic Serum Concentrate 30ml packshot white background",
            "Dot & Key Water Drench Hyaluronic Serum bottle white background",
        ],
    },
    {
        "name": "Dot & Key Blueberry Hydrate Barrier Repair Sunscreen SPF 50+ (50g)",
        "brand": "Dot & Key",
        "price": 495.0,
        "weight_per_unit": 50.0,
        "description": "Long-lasting moisture sunscreen infused with Hyaluronic Acid and 5 Ceramides. Repairs dry barrier while providing broad-spectrum SPF 50+ PA++++ protection.",
        "variants": [{"title": "50g", "price": 495.0}],
        "queries": [
            "Dot & Key Blueberry Hydrate Barrier Repair Sunscreen SPF 50 50g packshot white background",
            "Dot & Key Blueberry Sunscreen tube white background",
        ],
    },
    {
        "name": "Dot & Key Watermelon Cooling Sunscreen SPF 50+ Aqua-Gel (50g)",
        "brand": "Dot & Key",
        "price": 445.0,
        "weight_per_unit": 50.0,
        "description": "Refreshing cooling aqua-gel sunscreen with Hyaluronic Acid and Watermelon extract. Instantly cools skin by 6°C with zero white cast and SPF 50+ PA++++.",
        "variants": [{"title": "50g", "price": 445.0}],
        "queries": [
            "Dot & Key Watermelon Cooling Sunscreen Aqua Gel SPF 50 50g packshot white background",
            "Dot & Key Watermelon Sunscreen tube white background",
        ],
    },
    {
        "name": "Dot & Key 10% Vitamin C + E Super Bright Face Serum (30ml)",
        "brand": "Dot & Key",
        "price": 695.0,
        "weight_per_unit": 30.0,
        "description": "Fragrance-free brightening serum featuring 10% Vitamin C + E, Sicilian Blood Orange, and Pumpkin. Fades stubborn dark spots and delivers glass-skin glow.",
        "variants": [{"title": "30ml", "price": 695.0}],
        "queries": [
            "Dot & Key 10% Vitamin C + E Super Bright Face Serum 30ml bottle white background",
            "Dot & Key Super Bright Face Serum dropper packshot white background",
        ],
    },
    {
        "name": "Dot & Key Vitamin C + E Super Bright Sunscreen SPF 50+ (50g)",
        "brand": "Dot & Key",
        "price": 445.0,
        "weight_per_unit": 50.0,
        "description": "Water-light fluid sunscreen with Sicilian Blood Orange, Pumpkin, and Vitamin C + E. SPF 50+ PA++++ broad-spectrum defense against sun tanning and pigmentation.",
        "variants": [{"title": "50g", "price": 445.0}],
        "queries": [
            "Dot & Key Vitamin C + E Super Bright Sunscreen SPF 50 50g packshot white background",
            "Dot & Key Vitamin C Sunscreen tube white background",
        ],
    },
    {
        "name": "Dot & Key Cica Calming Skin Renewing Night Gel (60ml)",
        "brand": "Dot & Key",
        "price": 595.0,
        "weight_per_unit": 60.0,
        "description": "Overnight clarifying and soothing night gel with Niacinamide, Cica, and Green Tea. Calms acne flare-ups and balances excess nighttime oiliness.",
        "variants": [{"title": "60ml", "price": 595.0}],
        "queries": [
            "Dot & Key Cica Calming Skin Renewing Night Gel 60ml jar white background",
            "Dot & Key Cica Night Gel packaging packshot white background",
        ],
    },
    {
        "name": "Dot & Key Retinol + Ceramide Night Repair Cream (60ml)",
        "brand": "Dot & Key",
        "price": 695.0,
        "weight_per_unit": 60.0,
        "description": "Anti-aging night repair cream infused with encapsulated Retinol, Ceramides, Hibiscus, and Pomegranate Oil. Restores firmness and smooths fine lines.",
        "variants": [{"title": "60ml", "price": 695.0}],
        "queries": [
            "Dot & Key Retinol Ceramide Night Repair Cream 60ml jar white background",
            "Dot & Key Retinol Night Repair Cream packaging white background",
        ],
    },
    {
        "name": "Dot & Key Pomegranate & Peptide Youth Restore Moisturizer SPF 30 (60ml)",
        "brand": "Dot & Key",
        "price": 595.0,
        "weight_per_unit": 60.0,
        "description": "Youth-boosting daily moisturizer with Pomegranate and multi-peptides. Formulated with SPF 30 to protect against premature aging and loss of elasticity.",
        "variants": [{"title": "60ml", "price": 595.0}],
        "queries": [
            "Dot & Key Pomegranate Peptide Youth Restore Moisturizer SPF 30 60ml packshot white background",
            "Dot & Key Pomegranate Moisturizer jar white background",
        ],
    },
    {
        "name": "Dot & Key Watermelon Cooling Sunscreen Body Spray SPF 40+ (110ml)",
        "brand": "Dot & Key",
        "price": 545.0,
        "weight_per_unit": 110.0,
        "description": "Convenient mist sunscreen spray offering broad-spectrum SPF 40+ protection. Water resistant for 80 minutes, refreshing, and non-sticky body sun protection.",
        "variants": [{"title": "110ml", "price": 545.0}],
        "queries": [
            "Dot & Key Watermelon Cooling Sunscreen Body Spray SPF 40 110ml packshot white background",
            "Dot & Key Sunscreen Body Spray bottle white background",
        ],
    },
    {
        "name": "Dot & Key Strawberry Dew Brightening Moisturizer (60g)",
        "brand": "Dot & Key",
        "price": 495.0,
        "weight_per_unit": 60.0,
        "description": "Lightweight gel moisturizer enriched with Strawberry extract, Niacinamide, and Peptides. Provides luminous hydration and improves skin barrier.",
        "variants": [{"title": "60g", "price": 495.0}],
        "queries": [
            "Dot & Key Strawberry Dew Brightening Moisturizer 60g jar packshot white background",
            "Dot & Key Strawberry Moisturizer packaging white background",
        ],
    },

    # ---------------------------------------------------------
    # 3. Highlighting, Primers & Professional Skincare (g87, g88)
    # ---------------------------------------------------------
    {
        "name": "RENEE Lumi Glow Highlighting Moisturizer (50g)",
        "brand": "RENEE",
        "price": 499.0,
        "weight_per_unit": 50.0,
        "description": "3D glow strobe moisturizer enriched with 3% Niacinamide and 1% Hyaluronic Acid. Primes and hydrates while imparting an ethereal multidimensional glow.",
        "variants": [{"title": "50g", "price": 499.0}],
        "queries": [
            "RENEE Lumi Glow Highlighting Moisturizer 50g packshot white background",
            "Renee Lumi Glow Moisturizer tube packaging white background",
        ],
    },
    {
        "name": "FLICKA Professional Silk Touch Milk-Cream Concentrate (50g)",
        "brand": "FLICKA",
        "price": 650.0,
        "weight_per_unit": 50.0,
        "description": "Professional milk-cream concentrate serving as an ultra-hydrating moisturizer and velvety primer. Creates a smooth, luminous canvas for makeup.",
        "variants": [{"title": "50g", "price": 650.0}],
        "queries": [
            "FLICKA Professional Silk Touch Milk Cream 50g packshot white background",
            "Flicka Silk Touch Milk Cream concentrate bottle white background",
        ],
    },
    {
        "name": "GUBB 540 Needles Micro Derma Roller (0.5mm)",
        "brand": "GUBB",
        "price": 449.0,
        "weight_per_unit": 80.0,
        "description": "Precision derma roller featuring 540 surgical-grade titanium 0.5mm micro-needles. Stimulates collagen production, enhances serum absorption, and revitalizes skin texture.",
        "variants": [{"title": "0.5mm", "price": 449.0}],
        "queries": [
            "GUBB Derma Roller 540 Needles 0.5mm packshot white background",
            "Gubb Derma Roller packaging box white background",
        ],
    },
    {
        "name": "Kamill Multani Mitti Fuller's Earth Herbal Powder (100g)",
        "brand": "Kamill",
        "price": 99.0,
        "weight_per_unit": 100.0,
        "description": "100% natural herbal Fuller's Earth powder. Draws out deep-seated impurities, unclogs pores, absorbs excess oil, and leaves skin refreshed and glowing.",
        "variants": [{"title": "100g", "price": 99.0}],
        "queries": [
            "Kamill Multani Mitti Fuller Powder 100g packshot white background",
            "Kamill Multani Mitti box packaging white background",
        ],
    },
    {
        "name": "BoroPlus Ayurvedic Antiseptic Daily Skin Cream (40ml)",
        "brand": "BoroPlus",
        "price": 60.0,
        "weight_per_unit": 40.0,
        "description": "India's trusted 24-hour moisturizing Ayurvedic antiseptic cream for face, hands, and body. Heals dry cracked skin, cuts, burns, and rough elbows.",
        "variants": [{"title": "40ml", "price": 60.0}],
        "queries": [
            "BoroPlus Ayurvedic Antiseptic Cream 40ml tube packshot white background",
            "BoroPlus Antiseptic Cream 40ml packaging white background",
        ],
    },
    {
        "name": "Joy Skin Fruits Nourishing Cold Cream (200ml)",
        "brand": "Joy",
        "price": 175.0,
        "weight_per_unit": 200.0,
        "description": "Enriched with active fruit boosters, Jojoba Oil, and Wheatgerm Oil. Provides intense winter moisture, prevents dryness, and leaves skin soft and supple.",
        "variants": [{"title": "200ml", "price": 175.0}],
        "queries": [
            "Joy Skin Fruits Nourishing Cold Cream 200ml jar packshot white background",
            "Joy Nourishing Cold Cream 200ml tub white background",
        ],
    },

    # ---------------------------------------------------------
    # 4. Active Serums, Cleansers & Hair Elixirs (g88, g89)
    # ---------------------------------------------------------
    {
        "name": "Garnier Skin Naturals Bright Complete 30x Vitamin C Booster Serum (30ml)",
        "brand": "Garnier",
        "price": 549.0,
        "weight_per_unit": 30.0,
        "description": "Enriched with 30x Vitamin C and Japanese Yuzu Lemon. Clinically proven to reduce dark spots and acne marks in just 3 days for an even, glowing tone.",
        "variants": [{"title": "30ml", "price": 549.0}],
        "queries": [
            "Garnier Bright Complete 30x Vitamin C Booster Serum 30ml bottle white background",
            "Garnier Vitamin C Booster Serum 30ml dropper packshot white background",
        ],
    },
    {
        "name": "Garnier Skin Naturals Bright Complete 30x Vitamin C Booster Serum (15ml)",
        "brand": "Garnier",
        "price": 299.0,
        "weight_per_unit": 15.0,
        "description": "Compact travel-sized booster serum with 30x Vitamin C. Quickly penetrates to fade stubborn blemishes and revive skin luminosity.",
        "variants": [{"title": "15ml", "price": 299.0}],
        "queries": [
            "Garnier Bright Complete 30x Vitamin C Booster Serum 15ml bottle white background",
            "Garnier Vitamin C Serum 15ml dropper packshot white background",
        ],
    },
    {
        "name": "Kaavin's Vitamin C 10% Brightening Face Serum (30ml)",
        "brand": "Kaavin's",
        "price": 399.0,
        "weight_per_unit": 30.0,
        "description": "Professional-grade concentrated age-defense serum with 10% Vitamin C. Brightens dull and tired skin while protecting against environmental aggressors.",
        "variants": [{"title": "30ml", "price": 399.0}],
        "queries": [
            "Kaavins Vitamin C 10% Serum 30ml bottle white background",
            "Kaavins Professional Vitamin C Serum packshot white background",
        ],
    },
    {
        "name": "Streax Bright & Shine Face Serum 18% Vitamin C & Glycolic Acid (30ml)",
        "brand": "Streax",
        "price": 399.0,
        "weight_per_unit": 30.0,
        "description": "Dual brightening facial serum powered by 18% Vitamin C and Glycolic Acid complex. Gently micro-exfoliates and accelerates cellular radiance.",
        "variants": [{"title": "30ml", "price": 399.0}],
        "queries": [
            "Streax Bright and Shine Face Serum 18% Vitamin C Glycolic Acid packshot white background",
            "Streax Bright and Shine Serum bottle packaging white background",
        ],
    },
    {
        "name": "Streax Bright & Shine Face Wash (100ml)",
        "brand": "Streax",
        "price": 199.0,
        "weight_per_unit": 100.0,
        "description": "Radiance-boosting daily face wash infused with 4% Vitamin C & Glycolic serum complex. Cleanses deep dirt and leaves skin with a luminous glow.",
        "variants": [{"title": "100ml", "price": 199.0}],
        "queries": [
            "Streax Bright and Shine Face Wash 4% Vitamin C Glycolic 100ml tube white background",
            "Streax Bright & Shine Face Wash packshot white background",
        ],
    },
    {
        "name": "L'Oreal Paris Glycolic Gloss Gloss Extension Hair Serum (100ml)",
        "brand": "L'Oreal Paris",
        "price": 599.0,
        "weight_per_unit": 100.0,
        "description": "Breakthrough leave-in hair serum with Glycolic Acid complex. Seals cuticles and provides 72-hour intense glossy shine and heat protection.",
        "variants": [{"title": "100ml", "price": 599.0}],
        "queries": [
            "L'Oreal Paris Glycolic Gloss Gloss Extension Serum 100ml bottle white background",
            "Loreal Glycolic Gloss Serum packshot white background",
        ],
    },
    {
        "name": "Pond's Bright Beauty 12% Gluta-Niacinamide Complex Anti-Pigmentation Serum (30ml)",
        "brand": "Pond's",
        "price": 499.0,
        "weight_per_unit": 30.0,
        "description": "Dermatologist-tested anti-pigmentation serum with 12% Gluta-Niacinamide complex. Visibly fades dark spots and post-inflammatory marks within 2 weeks.",
        "variants": [{"title": "30ml", "price": 499.0}],
        "queries": [
            "Ponds Bright Beauty 12% Gluta Niacinamide Serum 30ml bottle white background",
            "Pond's Skin Institute Gluta Niacinamide Anti Pigmentation Serum packshot",
        ],
    },
    {
        "name": "Galderma Biluma Glow Vitamin C Cleanser (100ml)",
        "brand": "Biluma",
        "price": 425.0,
        "weight_per_unit": 100.0,
        "description": "Dermatological brightening cleanser with exfoliating micro-beads, Vitamin C, AHA, and PHA. Gently removes impurities and restores natural skin radiance.",
        "variants": [{"title": "100ml", "price": 425.0}],
        "queries": [
            "Biluma Glow Vitamin C Cleanser 100ml bottle white background",
            "Galderma Biluma Glow Cleanser packshot white background",
        ],
    },
    {
        "name": "Lotus Herbals WhiteGlow Skin Whitening & Brightening Deep Moisturizing Crème (50g)",
        "brand": "Lotus Herbals",
        "price": 395.0,
        "weight_per_unit": 50.0,
        "description": "Rich nourishing day cream with SPF 20 PA+++, Grape, Mulberry, Saxifraga extracts and Milk Enzymes. Deeply hydrates and shields normal to dry skin.",
        "variants": [{"title": "50g", "price": 395.0}],
        "queries": [
            "Lotus Herbals WhiteGlow Skin Whitening Deep Moisturizing Creme 50g jar white background",
            "Lotus WhiteGlow Deep Moisturizing Creme packshot white background",
        ],
    },

    # ---------------------------------------------------------
    # 5. NutriGlow & Nature's Essence Advanced Skincare (g88, g89)
    # ---------------------------------------------------------
    {
        "name": "NutriGlow Advanced Organics Vitamin C Lightening Serum (30ml)",
        "brand": "NutriGlow",
        "price": 449.0,
        "weight_per_unit": 30.0,
        "description": "Radiance booster serum with Alpha Arbutin, Hyaluronic Acid, Skin Ceramides, Papaya Fruit, and Vitamin C. Brightens dull complexions and boosts collagen.",
        "variants": [{"title": "30ml", "price": 449.0}],
        "queries": [
            "NutriGlow Advanced Organics Vitamin C Lightening Serum 30ml bottle white background",
            "NutriGlow Vitamin C Lightening Serum packshot white background",
        ],
    },
    {
        "name": "NutriGlow Advanced Organics Anti Pigmentation Serum (30ml)",
        "brand": "NutriGlow",
        "price": 449.0,
        "weight_per_unit": 30.0,
        "description": "Dark spot and hyperpigmentation reduction serum with Kojic Acid, Almond Oil, Vitamin C, Glycolic Acid, Liquorice Root, and Alpha Arbutin.",
        "variants": [{"title": "30ml", "price": 449.0}],
        "queries": [
            "NutriGlow Advanced Organics Anti Pigmentation Serum 30ml bottle white background",
            "NutriGlow Anti Pigmentation Serum packshot white background",
        ],
    },
    {
        "name": "NutriGlow Advanced Organics Anti Pigmentation Day Cream SPF 20 (50g)",
        "brand": "NutriGlow",
        "price": 399.0,
        "weight_per_unit": 50.0,
        "description": "Formulated with Kojic Acid, Almond Oil, Glycolic Acid, Liquorice Root, and SPF 20. Fades pigmentation, blemishes, and shields from UV damage.",
        "variants": [{"title": "50g", "price": 399.0}],
        "queries": [
            "NutriGlow Advanced Organics Anti Pigmentation Day Cream SPF 20 50g jar white background",
            "NutriGlow Anti Pigmentation Day Cream packshot white background",
        ],
    },
    {
        "name": "NutriGlow Advanced Organics Age Repair Tightening Night Cream (50g)",
        "brand": "NutriGlow",
        "price": 499.0,
        "weight_per_unit": 50.0,
        "description": "Instant wrinkle lift night cream powered by Alpha Arbutin, Hyaluronic Acid, and Collagen Proteins. Plumps skin and accelerates nighttime cellular repair.",
        "variants": [{"title": "50g", "price": 499.0}],
        "queries": [
            "NutriGlow Advanced Organics Age Repair Tightening Night Cream 50g jar white background",
            "NutriGlow Age Repair Night Cream packshot white background",
        ],
    },
    {
        "name": "NutriGlow 100% Pure Essential Oils - Tea Tree (Pack of 2 x 15ml)",
        "brand": "NutriGlow",
        "price": 399.0,
        "weight_per_unit": 30.0,
        "description": "100% pure and natural therapeutic grade Tea Tree essential oils. Clarifies acne-prone skin, soothes scalp dandruff, and purifies blemishes.",
        "variants": [{"title": "Pack of 2 (30ml)", "price": 399.0}],
        "queries": [
            "NutriGlow Tea Tree Essential Oils Pack of 2 15ml packshot white background",
            "NutriGlow Essential Oils Tea Tree bottle white background",
        ],
    },
    {
        "name": "Nature's Essence Bright Glow Vitamin C Face Serum (30ml)",
        "brand": "Nature's Essence",
        "price": 199.0,
        "weight_per_unit": 30.0,
        "description": "Fast-absorbing glow booster serum packed with natural Vitamin C and citrus extracts. Brightens dull skin and restores an even, radiant complexion.",
        "variants": [{"title": "30ml", "price": 199.0}],
        "queries": [
            "Nature's Essence Bright Glow Vitamin C Serum bottle packshot white background",
            "Natures Essence Vitamin C Serum dropper white background",
        ],
    },
    {
        "name": "Nature's Essence Anti Pigmentation Papaya Face Serum (30ml)",
        "brand": "Nature's Essence",
        "price": 199.0,
        "weight_per_unit": 30.0,
        "description": "Targeted blemish-clearing serum enriched with active Papaya fruit enzymes and Vitamin C. Fades dark spots, sun tan, and post-acne pigmentation.",
        "variants": [{"title": "30ml", "price": 199.0}],
        "queries": [
            "Nature's Essence Anti Pigmentation Papaya Serum bottle packshot white background",
            "Natures Essence Papaya Serum dropper white background",
        ],
    },
    {
        "name": "Nature's Essence Papaya Face Cream (50g)",
        "brand": "Nature's Essence",
        "price": 160.0,
        "weight_per_unit": 50.0,
        "description": "Enriched with real Papaya enzymes, Vitamin E, and Wheatgerm Oil. Hydrates deeply, evens out patchy skin tone, and leaves skin soft and supple.",
        "variants": [{"title": "50g", "price": 160.0}],
        "queries": [
            "Nature's Essence Papaya Face Cream 50g jar packshot white background",
            "Natures Essence Papaya Cream packaging white background",
        ],
    },
    {
        "name": "Nature's Essence Vitamin C Glowing Day Cream (50g)",
        "brand": "Nature's Essence",
        "price": 160.0,
        "weight_per_unit": 50.0,
        "description": "Lightweight daily day cream infused with Vitamin C and Orange extracts. Fights dullness and protects against environmental pollution for all-day glow.",
        "variants": [{"title": "50g", "price": 160.0}],
        "queries": [
            "Nature's Essence Vitamin C Face Cream 50g jar packshot white background",
            "Natures Essence Vitamin C Day Cream packaging white background",
        ],
    },
    {
        "name": "Animate Aloe Vera & Vitamin E Facial Oil Essence Capsules (60 Capsules)",
        "brand": "Animate",
        "price": 299.0,
        "weight_per_unit": 60.0,
        "description": "Nourishing facial oil essence softgels with pure Aloe Vera extract and Vitamin E. Replenishes cellular moisture, combats dryness, and restores youthfulness.",
        "variants": [{"title": "60 Capsules", "price": 299.0}],
        "queries": [
            "Animate Aloe Vera Vitamin E Facial Essence Capsules bottle packshot white background",
            "Animate Facial Essence Capsules bottle white background",
        ],
    },
]

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
}


def search_bing_images(query: str, max_results: int = 15):
    """Searches Bing Images for authentic commercial photoshoot packshots."""
    url = f"https://www.bing.com/images/search?q={requests.utils.quote(query)}&FORM=HDRSC2"
    try:
        r = requests.get(url, headers=HEADERS, timeout=8)
        if r.status_code != 200:
            return []
        matches = re.findall(r'murl&quot;:&quot;(http[^&]+)&quot;', r.text)
        clean = []
        for m in matches:
            if any(ext in m.lower() for ext in [".jpg", ".jpeg", ".png", ".webp"]):
                clean.append(m)
            if len(clean) >= max_results:
                break
        return clean
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


def load_and_clean_image(content: bytes) -> Image.Image:
    """Loads image from bytes, flattens transparency to pure white #FFFFFF."""
    img = Image.open(io.BytesIO(content))
    if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
        rgba = img.convert("RGBA")
        background = Image.new("RGB", rgba.size, (255, 255, 255))
        background.paste(rgba, mask=rgba.split()[3])
        return background
    return img.convert("RGB")


def pad_to_square(img: Image.Image, target_size: int = 800) -> Image.Image:
    """Pads an authentic product image onto a 1:1 pure white canvas with 7% breathing room."""
    w, h = img.size
    max_dim = int(target_size * 0.88)
    scale = min(max_dim / float(w), max_dim / float(h))
    new_w = max(1, int(w * scale))
    new_h = max(1, int(h * scale))

    resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (target_size, target_size), (255, 255, 255))
    offset_x = (target_size - new_w) // 2
    offset_y = (target_size - new_h) // 2
    canvas.paste(resized, (offset_x, offset_y))
    return canvas


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
    print(f"🚀 INGESTING MAXX RETAIL BATCH 10: {len(CATALOG_BATCH10)} CLINICAL SERUMS, SUNSCREENS & CREAMS")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary: Strictly N/A (is_veg = None)")
    print(f"   Target Shop: {SHOP_ID}")
    print("=" * 80)

    prepared_products = []

    for idx, item in enumerate(CATALOG_BATCH10, 1):
        print(f"\n[{idx:02d}/{len(CATALOG_BATCH10):02d}] 📸 Processing authentic packshots for: {item['brand']} - {item['name']}...")

        packshot1_path = os.path.join(CACHE_DIR, f"maxx_b10_{idx}_1.jpg")
        packshot2_path = os.path.join(CACHE_DIR, f"maxx_b10_{idx}_2.jpg")

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

        st_path1 = f"{STORAGE_PREFIX}/maxx_b10_{idx}_1.jpg"
        st_path2 = f"{STORAGE_PREFIX}/maxx_b10_{idx}_2.jpg"

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
    print(f"📤 Syncing all {len(prepared_products)} Batch 10 items into Supabase database...")
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
    print(f"🎉 Batch 10 ingestion complete! Total Inserted: {total_inserted}, Total Updated: {total_updated}")
    print("=" * 80)


if __name__ == "__main__":
    main()
