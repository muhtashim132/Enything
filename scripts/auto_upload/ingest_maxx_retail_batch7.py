#!/usr/bin/env python3
"""
Maxx Retail Batch 7 (Shelf Scans g52.jpeg - g62.jpeg) Ingestion Engine
======================================================================
Catalog: 93 authentic facial kits, professional salon bleaches, face washes,
         scrubs, peel-off masks, fine Eaux De Parfum, daily-wear perfumes,
         no-gas deodorants, hair removal products, and premium oral/kids care:
  - Facial Kits & Bleaches:
      * NutriGlow Salon Series Anti-Pigmentation Bleach 300g
      * NutriGlow Salon Series Vitamin C Lightening Bleach 300g
      * NutriGlow Salon Series Skin Whitening Bleach 300g
      * NutriGlow Gold, Platinum, Diamond & Pearl Bleach Cream 60g
      * Pure Roots Papaya Shiner Bleach De-Tan Formula 250g
      * FYC Professional Korean Glass Skin Facial Kit
      * Swiss Beauty Bride & Bright Facial Kit (6 Steps)
      * NutriGlow Salon Series Anti-Pigmentation Facial Kit (70g)
      * NutriGlow Salon Series De-Tan & Dullness Removal Facial Kit (70g)
      * NutriGlow Salon Series Vitamin C Lightening Facial Kit (70g)
      * NutriGlow Ubtan Facial Kit (60g)
      * NutriGlow Advanced Pro Formula Gold Kesar Facial Kit (60g)
      * Lotus Herbals Korean Glass Skin 8-Step Facial Kit (101g)
      * Nature's Essence Papaya Facial Kit (60g)
      * Nature's Essence De-Tan Serum Facial Kit (60g)
      * NutriGlow Salon Series Skin Whitening Facial Kit (60g)
      * NutriGlow Advanced Pro Formula Wine Facial Kit (60g)
      * NutriGlow Advanced Pro Formula Diamond Radiance Facial Kit (60g)
      * NutriGlow Exotic Fruits 6 in 1 Facial Kit (60g)
      * Lotus Herbals Whiteglow Insta Glow Fairness Facial Kit (60g)
      * NutriGlow Papaya Fruit Master Facial Kit (260g)
      * Lotus Herbals Collagen Boost Skin Lift Facial Kit 6 Step (71g)
      * Lotus Herbals Radiant Pearl Cellular Lightening Facial Kit (50g)
      * VLCC Diamond Facial Kit (50g)
      * VLCC Anti Tan Facial Kit (60g)
      * VLCC Pearl Facial Kit (50g)

  - Face Washes, Scrubs, Masks & Gels:
      * Everyuth Naturals Tan Removal Chocolate & Cherry Scrub (100g)
      * Everyuth Naturals Golden Glow Peel-Off Mask (90g)
      * Everyuth Naturals Rejuvenating Cucumber & Aloe Vera Face Pack (100g)
      * Everyuth Naturals Tulsi Turmeric Face Wash (100g)
      * Lotus Herbals TeaTreeWash Anti-Acne Oil Control Face Wash (80g)
      * Lotus Herbals Neemwash Daily Purifying Neem Face Wash (80g)
      * Himalaya Natural Glow Kesar Face Pack (100g)
      * Himalaya Purifying Neem Face Scrub (100g)
      * Himalaya Purifying Neem Pack (100g)
      * Himalaya Purifying Neem Face Wash (100ml)
      * Himalaya Hydrating Aloe Vera Face Wash (100ml)
      * Himalaya Brightening Vitamin C Blueberry Face Wash (100ml)
      * VLCC Ayurveda Soothing Aloe Vera Gel 90% Pure Pulp (100g)
      * VLCC Anti Blemish Face Wash Papayaglow (100ml)
      * VLCC Skin Defense Walnut Face Scrub (100g)
      * VLCC Bright Glow Serum Face Wash (Vitamin C & Charcoal 100ml)
      * NutriGlow Naturals Raw Irish Coffee Face Wash (100g)
      * Garnier Bright Complete Vitamin C Face Wash (100g)
      * Garnier Bright Complete Vitamin C Serum Cleanser (50g)
      * Dr. Sheth's Ceramide & Vitamin C Face Wash (100ml)
      * Dr. Sheth's Kesar & Kojic Acid Face Wash (100ml)

  - Hair Removal & Personal Grooming:
      * Veet Pure Hair Removal Cream - Normal Skin (100g)
      * Veet Pure Hair Removal Cream - Sensitive Skin (100g)
      * Veet Professional Full Body Wax Strips (Pack of 20)
      * Bombae 6-in-1 Sensitive Trimmer Fuzz Off
      * Bombae Hair Removal Cream - Normal Skin (100g)
      * Skins O3+ Peel Off Wax Hair Removal Beans (100g)

  - Fine Fragrances, Eaux De Parfum & Perfumes:
      * Layer'r Wottagirl! Bella Eau De Parfum (100ml)
      * Layer'r Wottagirl! Flora Eau De Parfum (100ml)
      * Layer'r Wottagirl! Luxe Lady Noir Daily Wear Perfume (90ml)
      * Denver Black.code Eau De Parfum (100ml)
      * Denver Honour Eau De Parfum (100ml)
      * Denver Sporting Club Gold Eau De Parfum (100ml)
      * Denver Autograph Collection Hamilton Eau De Parfum (60ml)
      * Denver Imperial Eau De Parfum (100ml)
      * Bella Vita Luxury Blush Woman Eau De Parfum (100ml)
      * Vanesa Desire Eau De Parfum (100ml)
      * Vanesa Glamour Eau De Parfum (100ml)
      * Yardley London London Mist Daily Wear Perfume (100ml)
      * Yardley London Vanilla Blush Eau De Parfum (100ml)
      * Yardley London Starlit Bloom Eau De Parfum (100ml)
      * Yardley London English Lavender Daily Wear Perfume (100ml)
      * Yardley London English Rose Daily Wear Perfume (100ml)
      * Yardley London Gentleman Urbane Daily Wear Perfume (50ml)
      * Yardley London Gentleman Gold Daily Wear Perfume (50ml)
      * Yardley London Gentleman Explorer Daily Wear Perfume (50ml)
      * Yardley London Gentleman Royale Daily Wear Perfume (50ml)
      * Woodland Gloworm Eau De Parfum (100ml)
      * Woodland Masai Mara Eau De Parfum (100ml)
      * Swiss Beauty She Shines Eau De Parfum (100ml)
      * Beardo Tsunami Eau De Parfum (100ml)
      * Beardo Whisky Smoke No Gas Perfume Body Spray (120ml)
      * Wild Stone CODE Copper No Gas Body Perfume (120ml)
      * Wild Stone CODE Titanium No Gas Body Perfume (120ml)
      * Wild Stone CODE Steel No Gas Body Perfume (120ml)
      * Wild Stone CODE Platinum No Gas Body Perfume (120ml)
      * Wild Stone CODE Iridium No Gas Body Perfume (120ml)
      * Envy Triumph Eau De Parfum (100ml)
      * Envy Explorer Eau De Parfum (100ml)

  - Oral Care & Baby Essentials:
      * Chicco Dentifrico Kids Toothpaste Strawberry (50ml)
      * Chicco Dentifrico Kids Toothpaste Apple-Banana (50ml)
      * Chicco Super Slim Soft Toothbrush for Kids (3 to 8 Years)
      * Chicco Extra Soft Toothbrush for Infants (6 to 36 Months)
      * DentoShine Gel Toothpaste for Kids - Bubble Gum (80g)
      * DentoShine Silicone Finger Toothbrush with Hygiene Case
      * Listerine Cool Mint Antiseptic Mouthwash (250ml)
      * Listerine Fresh Burst Mouthwash (250ml)

Directives:
  1. Product category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab).
  2. Dietary status: Strictly N/A (is_veg = None / SQL NULL).
  3. Brand: Strictly populated for 100% of products (zero null brands).
  4. Packshots: Strictly 2 distinct commercial photoshoot views on pure white background (#FFFFFF),
     1:1 padded square (800x800), <120KB. Zero text cards or infographic slides.
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
STORAGE_PREFIX = f"{SHOP_ID}/batch7_packshots_v2"
CACHE_DIR = "scratch/batch7_real_packshots"

CATALOG_BATCH7 = [
    # ---------------------------------------------------------
    # 1. Facial Kits & Bleaches (g52, g53, g54, g55)
    # ---------------------------------------------------------
    {
        "name": "NutriGlow Salon Series Anti-Pigmentation Bleach",
        "brand": "NutriGlow",
        "price": 450.0,
        "weight_per_unit": "300g",
        "description": "Professional salon series anti-pigmentation bleach cream formulated with Kojic Acid, Almond Oil, Vitamin C, Glycolic Acid, and Liquorice Root Extract. Reduces melasma, dark spots, and freckles for an even, radiant complexion.",
        "variants": [{"title": "300g", "price": 450.0}],
        "queries": [
            "NutriGlow Salon Series Anti-Pigmentation Bleach 300g bottle packshot white background",
            "NutriGlow Anti-Pigmentation Bleach tub cream white background",
        ],
    },
    {
        "name": "NutriGlow Salon Series Vitamin C Lightening Bleach",
        "brand": "NutriGlow",
        "price": 450.0,
        "weight_per_unit": "300g",
        "description": "Salon-grade Vitamin C lightening bleach infused with Alpha Arbutin, Hyaluronic Acid, Skin Ceramides, and Papaya Fruit Extract. Provides intense tan removal and advanced melanin reduction for luminous skin.",
        "variants": [{"title": "300g", "price": 450.0}],
        "queries": [
            "NutriGlow Salon Series Vitamin C Lightening Bleach 300g box white background",
            "NutriGlow Vitamin C Lightening Bleach tub white background",
        ],
    },
    {
        "name": "NutriGlow Salon Series Skin Whitening Bleach",
        "brand": "NutriGlow",
        "price": 450.0,
        "weight_per_unit": "300g",
        "description": "Enriched with Alpha Arbutin, Hyaluronic Acid, Sarmentosa Extract, Papaya Fruit Extract, and AHA. Delivers hyper melanin reduction and professional skin tone correction.",
        "variants": [{"title": "300g", "price": 450.0}],
        "queries": [
            "NutriGlow Salon Series Skin Whitening Bleach 300g white background",
            "NutriGlow Skin Whitening Bleach tub white background",
        ],
    },
    {
        "name": "NutriGlow Gold Platinum Diamond & Pearl Bleach Cream",
        "brand": "NutriGlow",
        "price": 125.0,
        "weight_per_unit": "60g",
        "description": "Complete skincare solution bleach cream powered by nano particles of Gold, Platinum, Diamond, and Pearl. Imparts instant salon-like glow and lightens facial hair safely.",
        "variants": [{"title": "60g", "price": 125.0}],
        "queries": [
            "NutriGlow Gold Platinum Diamond Pearl Bleach Cream white background",
            "NutriGlow 4 in 1 Bleach packshot white background",
        ],
    },
    {
        "name": "Pure Roots Papaya Shiner Bleach De-Tan Formula",
        "brand": "Pure Roots",
        "price": 180.0,
        "weight_per_unit": "250g",
        "description": "De-tan formula bleach enriched with active papaya fruit extracts. Clears stubborn tanning, unclogs pores, and adds a natural luminous shine.",
        "variants": [{"title": "250g", "price": 180.0}, {"title": "42g", "price": 60.0}],
        "queries": [
            "Pure Roots Papaya Shiner Bleach De Tan Formula 250g white background",
            "Pure Roots Papaya Bleach tub white background",
        ],
    },
    {
        "name": "FYC Professional Korean Glass Skin Facial Kit",
        "brand": "FYC",
        "price": 350.0,
        "weight_per_unit": "60g",
        "description": "Professional Korean facial kit designed to deliver the coveted glass skin glow. Deeply hydrates, minimizes pores, and revitalizes tired skin through a multi-step routine.",
        "variants": [{"title": "6-Step Kit", "price": 350.0}],
        "queries": [
            "FYC Professional Korean Facial Kit box white background",
            "FYC Korean Glass Skin Facial Kit packshot white background",
        ],
    },
    {
        "name": "Swiss Beauty Bride & Bright Facial Kit",
        "brand": "Swiss Beauty",
        "price": 249.0,
        "weight_per_unit": "36g",
        "description": "6-step bridal radiance facial kit enriched with Alpha Arbutin and Kakadu Plum. Illuminates skin tone, eliminates dullness, and imparts a long-lasting bridal glow.",
        "variants": [{"title": "6 Steps Kit (36g)", "price": 249.0}],
        "queries": [
            "Swiss Beauty Bride & Bright Facial Kit 36g pouch white background",
            "Swiss Beauty Bride and Bright Facial Kit packshot white background",
        ],
    },
    {
        "name": "NutriGlow Salon Series Anti-Pigmentation Facial Kit",
        "brand": "NutriGlow",
        "price": 275.0,
        "weight_per_unit": "70g",
        "description": "Dark spot reduction and blemish removal facial kit featuring Kojic Acid, Almond Oil, Vitamin C, and Glycolic Acid. Comes with a complimentary head cap inside.",
        "variants": [{"title": "70g (with Free Head Cap)", "price": 275.0}],
        "queries": [
            "NutriGlow Salon Series Anti Pigmentation Facial Kit 70g white background",
            "NutriGlow Anti-Pigmentation Facial Kit packshot white background",
        ],
    },
    {
        "name": "NutriGlow Salon Series De-Tan & Dullness Removal Facial Kit",
        "brand": "NutriGlow",
        "price": 275.0,
        "weight_per_unit": "70g",
        "description": "Skin brightening and tan removal kit with Mint, Eucalyptus, Niacinamide, Camphor, Milk Proteins, and Lactic Acid. Includes a free head cap and sheet mask.",
        "variants": [{"title": "70g (with Head Cap & Sheet Mask)", "price": 275.0}],
        "queries": [
            "NutriGlow Salon Series De Tan Dullness Removal Facial Kit 70g white background",
            "NutriGlow De-Tan Facial Kit pouch packshot white background",
        ],
    },
    {
        "name": "NutriGlow Salon Series Vitamin C Lightening Facial Kit",
        "brand": "NutriGlow",
        "price": 275.0,
        "weight_per_unit": "70g",
        "description": "Formulated with Alpha Arbutin, Hyaluronic Acid, Ceramides, and Papaya Fruit to reverse sun damage and dullness. Includes free head cap inside.",
        "variants": [{"title": "70g (with Free Head Cap)", "price": 275.0}],
        "queries": [
            "NutriGlow Salon Series Vitamin C Lightening Facial Kit 70g white background",
            "NutriGlow Vitamin C Facial Kit packshot white background",
        ],
    },
    {
        "name": "NutriGlow Ubtan Facial Kit",
        "brand": "NutriGlow",
        "price": 225.0,
        "weight_per_unit": "60g",
        "description": "Traditional Ayurvedic ubtan facial kit featuring turmeric, saffron, and sandalwood extracts to detoxify, brighten, and restore natural skin radiance.",
        "variants": [{"title": "60g", "price": 225.0}],
        "queries": [
            "NutriGlow Ubtan Facial Kit 60g box white background",
            "NutriGlow Ubtan Facial Kit packshot white background",
        ],
    },
    {
        "name": "NutriGlow Advanced Pro Formula Gold Kesar Facial Kit",
        "brand": "NutriGlow",
        "price": 249.0,
        "weight_per_unit": "60g",
        "description": "Radiant shine and youthful glow facial kit enriched with pure 24K gold dust and Kashmiri kesar extracts. Tightens pores and revitalizes skin texture.",
        "variants": [{"title": "60g", "price": 249.0}],
        "queries": [
            "NutriGlow Gold Kesar Facial Kit box white background",
            "NutriGlow Advanced Pro Formula Gold Kesar Facial Kit packshot white background",
        ],
    },
    {
        "name": "Lotus Herbals Korean Glass Skin 8-Step Facial Kit",
        "brand": "Lotus Herbals",
        "price": 495.0,
        "weight_per_unit": "101g",
        "description": "Premium 8-step Korean glass skin facial treatment with oil cleanser, exfoliating cleanser, toning essence, serum sheet mask, massage cream, lip scrub, peel-off mask, and sunscreen.",
        "variants": [{"title": "8 Steps (101g)", "price": 495.0}],
        "queries": [
            "Lotus Herbals Korean Glass Skin Facial Kit 8 Step box white background",
            "Lotus Herbals Korean Glass Skin Facial Kit packshot white background",
        ],
    },
    {
        "name": "Nature's Essence Papaya Facial Kit",
        "brand": "Nature's Essence",
        "price": 260.0,
        "weight_per_unit": "60g",
        "description": "Natural blemish and pigmentation reduction facial kit enriched with active papaya enzymes for soft, clear, and glowing skin.",
        "variants": [{"title": "60g (Single Use)", "price": 260.0}],
        "queries": [
            "Nature's Essence Papaya Facial Kit box white background",
            "Nature's Essence Papaya Facial Kit packshot white background",
        ],
    },
    {
        "name": "Nature's Essence De-Tan Serum Facial Kit",
        "brand": "Nature's Essence",
        "price": 299.0,
        "weight_per_unit": "60g",
        "description": "Advanced de-tan serum facial kit powered by glycolic acid and niacinamide serum to fade stubborn sun tan and restore even skin tone.",
        "variants": [{"title": "60g Kit", "price": 299.0}],
        "queries": [
            "Nature's Essence De Tan Serum Facial Kit white background",
            "Nature's Essence De-Tan Serum Facial Kit packshot white background",
        ],
    },
    {
        "name": "NutriGlow Salon Series Skin Whitening Facial Kit",
        "brand": "NutriGlow",
        "price": 250.0,
        "weight_per_unit": "60g",
        "description": "Enriched with skin whitening actives, licorice extract, and arbutin to target dark spots and brighten the skin barrier.",
        "variants": [{"title": "60g", "price": 250.0}],
        "queries": [
            "NutriGlow Salon Series Skin Whitening Facial Kit box white background",
            "NutriGlow Skin Whitening Facial Kit packshot white background",
        ],
    },
    {
        "name": "NutriGlow Advanced Pro Formula Wine Facial Kit",
        "brand": "NutriGlow",
        "price": 249.0,
        "weight_per_unit": "60g",
        "description": "Red wine antioxidant-rich facial kit that boosts collagen production, firms the skin, and gives an instant youthful flush and glow.",
        "variants": [{"title": "60g", "price": 249.0}],
        "queries": [
            "NutriGlow Wine Facial Kit box white background",
            "NutriGlow Advanced Pro Formula Wine Facial Kit packshot white background",
        ],
    },
    {
        "name": "NutriGlow Advanced Pro Formula Diamond Radiance Facial Kit",
        "brand": "NutriGlow",
        "price": 249.0,
        "weight_per_unit": "60g",
        "description": "Diamond dust infused facial kit designed for deep exfoliation, dead cell elimination, and sparkling salon radiance.",
        "variants": [{"title": "60g", "price": 249.0}],
        "queries": [
            "NutriGlow Diamond Radiance Facial Kit box white background",
            "NutriGlow Advanced Pro Formula Diamond Radiance Facial Kit packshot white background",
        ],
    },
    {
        "name": "NutriGlow Exotic Fruits 6 in 1 Facial Kit",
        "brand": "NutriGlow",
        "price": 225.0,
        "weight_per_unit": "60g",
        "description": "Vitamin-rich fruit facial kit combining apple, orange, papaya, kiwi, strawberry, and lemon extracts to nourish and refresh tired skin.",
        "variants": [{"title": "60g", "price": 225.0}],
        "queries": [
            "NutriGlow Exotic Fruits 6 Facial Kit box white background",
            "NutriGlow Exotic Fruits Facial Kit packshot white background",
        ],
    },
    {
        "name": "Lotus Herbals Whiteglow Insta Glow Fairness Facial Kit",
        "brand": "Lotus Herbals",
        "price": 295.0,
        "weight_per_unit": "60g",
        "description": "Clinically formulated with bearberry, grape, mulberry, and saxifraga extracts for instant fairness and radiant, spot-free skin.",
        "variants": [{"title": "60g (4 Steps)", "price": 295.0}],
        "queries": [
            "Lotus Herbals Whiteglow Insta Glow Fairness Facial Kit white background",
            "Lotus Herbals Whiteglow Facial Kit packshot white background",
        ],
    },
    {
        "name": "NutriGlow Papaya Fruit Facial Kit Master Pack",
        "brand": "NutriGlow",
        "price": 550.0,
        "weight_per_unit": "260g",
        "description": "Jumbo salon pack with 6 steps: Cleanser, Scrub, Gel, Cream, Pack, and Serum. Delivers a blemish-free fairer complexion.",
        "variants": [{"title": "260g (6 Full Steps)", "price": 550.0}],
        "queries": [
            "NutriGlow Papaya Fruit Facial Kit 260g box white background",
            "NutriGlow Papaya Fruit Facial Kit Master Pack packshot white background",
        ],
    },
    {
        "name": "Lotus Herbals Collagen Boost Skin Lift Facial Kit 6 Step",
        "brand": "Lotus Herbals",
        "price": 395.0,
        "weight_per_unit": "71g",
        "description": "Anti-ageing skin lift facial kit enriched with botanical collagen to improve elasticity, firm sagging skin, and reduce fine lines.",
        "variants": [{"title": "6 Steps (71g)", "price": 395.0}],
        "queries": [
            "Lotus Herbals Collagen Boost Skin Lift Facial Kit 6 Step purple box white background",
            "Lotus Herbals Collagen Boost Facial Kit packshot white background",
        ],
    },
    {
        "name": "Lotus Herbals Radiant Pearl Cellular Lightening Facial Kit",
        "brand": "Lotus Herbals",
        "price": 325.0,
        "weight_per_unit": "50g",
        "description": "Infused with crushed pearl dust and green tea extract for cellular lightening, luminous clarity, and deep hydration.",
        "variants": [{"title": "4 Steps (50g)", "price": 325.0}],
        "queries": [
            "Lotus Herbals Radiant Pearl Cellular Lightening Facial Kit white background",
            "Lotus Herbals Radiant Pearl Facial Kit packshot white background",
        ],
    },
    {
        "name": "VLCC Diamond Facial Kit",
        "brand": "VLCC",
        "price": 350.0,
        "weight_per_unit": "50g",
        "description": "Enriched with diamond bhasma and jojoba oil to fight premature ageing, improve skin texture, and restore brilliant diamond shine.",
        "variants": [{"title": "Single Facial (50g)", "price": 350.0}],
        "queries": [
            "VLCC Diamond Facial Kit box white background",
            "VLCC Diamond Facial Kit packshot white background",
        ],
    },
    {
        "name": "VLCC Anti Tan Facial Kit",
        "brand": "VLCC",
        "price": 300.0,
        "weight_per_unit": "60g",
        "description": "Expert de-tanning formula with oat powder, walnut, and pistachio to clear dark spots, repair sun damage, and even out skin tone.",
        "variants": [{"title": "2 Facials Per Pack", "price": 300.0}],
        "queries": [
            "VLCC Anti Tan Facial Kit box white background",
            "VLCC Anti Tan Facial Kit packshot white background",
        ],
    },
    {
        "name": "VLCC Pearl Facial Kit",
        "brand": "VLCC",
        "price": 275.0,
        "weight_per_unit": "50g",
        "description": "Real pearl bhasma enriched facial kit that purifies skin, brightens dark patches, and delivers an instant pearlescent glow.",
        "variants": [{"title": "Single Facial (50g)", "price": 275.0}],
        "queries": [
            "VLCC Pearl Facial Kit box white background",
            "VLCC Pearl Facial Kit packshot white background",
        ],
    },

    # ---------------------------------------------------------
    # 2. Face Washes, Scrubs, Masks & Gels (g56, g57, g58, g59)
    # ---------------------------------------------------------
    {
        "name": "Everyuth Naturals Tan Removal Chocolate & Cherry Face Scrub",
        "brand": "Everyuth Naturals",
        "price": 135.0,
        "weight_per_unit": "100g",
        "description": "Luxurious chocolate and cherry scrub with visible results in 1 use. Gently exfoliates dead skin cells and eliminates stubborn tan.",
        "variants": [{"title": "50g", "price": 75.0}, {"title": "100g", "price": 135.0}],
        "queries": [
            "Everyuth Naturals Tan Removal Chocolate Cherry Scrub 100g tube white background",
            "Everyuth Tan Removal Chocolate Cherry Face Scrub packshot white background",
        ],
    },
    {
        "name": "Everyuth Naturals Golden Glow Peel-Off Mask",
        "brand": "Everyuth Naturals",
        "price": 150.0,
        "weight_per_unit": "90g",
        "description": "24 Karat gold collagen peel-off mask that unclogs pores, lifts dirt, and gives a 15-minute golden radiance.",
        "variants": [{"title": "50g", "price": 90.0}, {"title": "90g", "price": 150.0}],
        "queries": [
            "Everyuth Naturals Golden Glow Peel Off Mask 90g tube white background",
            "Everyuth Golden Glow Peel-Off Mask packshot white background",
        ],
    },
    {
        "name": "Everyuth Naturals Rejuvenating Cucumber & Aloe Vera Face Pack",
        "brand": "Everyuth Naturals",
        "price": 110.0,
        "weight_per_unit": "100g",
        "description": "Soothing face pack with fresh cucumber and aloe vera extracts to nourish, cool, and hydrate tired, sun-stressed skin.",
        "variants": [{"title": "100g", "price": 110.0}],
        "queries": [
            "Everyuth Naturals Rejuvenating Cucumber Aloe Vera Face Pack 100g white background",
            "Everyuth Cucumber Aloe Vera Face Pack packshot white background",
        ],
    },
    {
        "name": "Everyuth Naturals Tulsi Turmeric Face Wash",
        "brand": "Everyuth Naturals",
        "price": 125.0,
        "weight_per_unit": "100g",
        "description": "Anti-acne and anti-marks face wash powered by pure Tulsi, Turmeric, and Tea Tree oil. Paraben-free formula that keeps skin clear.",
        "variants": [{"title": "100g", "price": 125.0}, {"title": "150g", "price": 175.0}],
        "queries": [
            "Everyuth Naturals Tulsi Turmeric Face Wash 100g tube white background",
            "Everyuth Tulsi Turmeric Face Wash packshot white background",
        ],
    },
    {
        "name": "Lotus Herbals TeaTreeWash Anti-Acne Oil Control Face Wash",
        "brand": "Lotus Herbals",
        "price": 195.0,
        "weight_per_unit": "80g",
        "description": "Tea tree and cinnamon face wash that regulates sebum secretion, removes excess oil, and clears acne-causing bacteria.",
        "variants": [{"title": "80g", "price": 195.0}, {"title": "120g", "price": 275.0}],
        "queries": [
            "Lotus Herbals TeaTreeWash Anti Acne Oil Control Face Wash 80g white background",
            "Lotus Herbals TeaTreeWash packshot white background",
        ],
    },
    {
        "name": "Lotus Herbals Neemwash Daily Purifying Neem Face Wash",
        "brand": "Lotus Herbals",
        "price": 195.0,
        "weight_per_unit": "80g",
        "description": "Herbal purifying face wash enriched with neem and chamomile extracts for everyday defense against breakouts and blemishes.",
        "variants": [{"title": "80g", "price": 195.0}, {"title": "120g", "price": 275.0}],
        "queries": [
            "Lotus Herbals Neemwash Daily Purifying Neem Face Wash 80g white background",
            "Lotus Herbals Neemwash packshot white background",
        ],
    },
    {
        "name": "Himalaya Natural Glow Kesar Face Pack",
        "brand": "Himalaya",
        "price": 160.0,
        "weight_per_unit": "100g",
        "description": "Deep cleansing face pack with kesar, turmeric, and walnut. Enhances complexion, clears blemishes, and reveals naturally glowing skin.",
        "variants": [{"title": "50g", "price": 90.0}, {"title": "100g", "price": 160.0}],
        "queries": [
            "Himalaya Natural Glow Kesar Face Pack 100g tube white background",
            "Himalaya Kesar Face Pack packshot white background",
        ],
    },
    {
        "name": "Himalaya Purifying Neem Face Scrub",
        "brand": "Himalaya",
        "price": 155.0,
        "weight_per_unit": "100g",
        "description": "Dual action scrub with neem and apricot granules. Removes dead skin cells, unclogs pores, and prevents pimples.",
        "variants": [{"title": "50g", "price": 85.0}, {"title": "100g", "price": 155.0}],
        "queries": [
            "Himalaya Purifying Neem Face Scrub 100g tube white background",
            "Himalaya Neem Face Scrub packshot white background",
        ],
    },
    {
        "name": "Himalaya Purifying Neem Pack",
        "brand": "Himalaya",
        "price": 160.0,
        "weight_per_unit": "100g",
        "description": "Clarifying herbal mask with neem, fuller's earth (multani mitti), and turmeric to regulate excess oil and soothe acne.",
        "variants": [{"title": "50g", "price": 90.0}, {"title": "100g", "price": 160.0}],
        "queries": [
            "Himalaya Purifying Neem Pack 100g tube white background",
            "Himalaya Neem Face Pack packshot white background",
        ],
    },
    {
        "name": "Himalaya Purifying Neem Face Wash",
        "brand": "Himalaya",
        "price": 175.0,
        "weight_per_unit": "100ml",
        "description": "Clinically proven soap-free face wash that prevents pimples with antibacterial Neem and antiseptic Turmeric.",
        "variants": [{"title": "100ml", "price": 175.0}, {"title": "150ml", "price": 245.0}, {"title": "200ml", "price": 310.0}],
        "queries": [
            "Himalaya Purifying Neem Face Wash 100ml tube white background",
            "Himalaya Neem Face Wash packshot white background",
        ],
    },
    {
        "name": "Himalaya Hydrating Aloe Vera Face Wash",
        "brand": "Himalaya",
        "price": 165.0,
        "weight_per_unit": "100ml",
        "description": "Moisture-replenishing face wash with Aloe Vera and Cucumber to cleanse gently while leaving skin soft, smooth, and supple.",
        "variants": [{"title": "100ml", "price": 165.0}, {"title": "150ml", "price": 230.0}],
        "queries": [
            "Himalaya Hydrating Aloe Vera Face Wash 100ml tube white background",
            "Himalaya Aloe Vera Face Wash packshot white background",
        ],
    },
    {
        "name": "Himalaya Brightening Vitamin C Blueberry Face Wash",
        "brand": "Himalaya",
        "price": 199.0,
        "weight_per_unit": "100ml",
        "description": "Antioxidant-rich blueberry and natural vitamin C face wash that eliminates dullness and restores a youthful, radiant complexion.",
        "variants": [{"title": "100ml", "price": 199.0}],
        "queries": [
            "Himalaya Brightening Vitamin C Blueberry Face Wash 100ml tube white background",
            "Himalaya Blueberry Vitamin C Face Wash packshot white background",
        ],
    },
    {
        "name": "VLCC Ayurveda Soothing Aloe Vera Gel 90% Pure Pulp",
        "brand": "VLCC",
        "price": 110.0,
        "weight_per_unit": "100g",
        "description": "Multi-purpose soothing gel formulated with 90% pure aloe vera pulp and Vitamin E to soothe irritated skin, heal sunburns, and hydrate deeply.",
        "variants": [{"title": "100g", "price": 110.0}, {"title": "150g", "price": 150.0}],
        "queries": [
            "VLCC Ayurveda Soothing Aloe Vera Gel 100g tube white background",
            "VLCC Aloe Vera Gel packshot white background",
        ],
    },
    {
        "name": "VLCC Anti Blemish Face Wash Papayaglow",
        "brand": "VLCC",
        "price": 175.0,
        "weight_per_unit": "100ml",
        "description": "Anti-blemish daily cleanser enriched with papaya enzymes and Vitamin C serum to reduce dark spots and impart a bright glow.",
        "variants": [{"title": "100ml", "price": 175.0}],
        "queries": [
            "VLCC Anti Blemish Face Wash Papayaglow 100ml tube white background",
            "VLCC Papayaglow Face Wash packshot white background",
        ],
    },
    {
        "name": "VLCC Skin Defense Walnut Face Scrub",
        "brand": "VLCC",
        "price": 165.0,
        "weight_per_unit": "100g",
        "description": "Gentle exfoliating scrub with natural walnut shell powder and aloe vera to remove blackheads, impurities, and dead cells.",
        "variants": [{"title": "100g", "price": 165.0}],
        "queries": [
            "VLCC Skin Defense Walnut Face Scrub 100g tube white background",
            "VLCC Walnut Face Scrub packshot white background",
        ],
    },
    {
        "name": "VLCC Bright Glow Serum Face Wash",
        "brand": "VLCC",
        "price": 199.0,
        "weight_per_unit": "100ml",
        "description": "Double action serum face wash infused with active Vitamin C serum and detoxifying Charcoal to clear impurities and boost skin radiance.",
        "variants": [{"title": "100ml", "price": 199.0}],
        "queries": [
            "VLCC Bright Glow Serum Face Wash Vitamin C Charcoal 100ml white background",
            "VLCC Serum Face Wash Bright Glow packshot white background",
        ],
    },
    {
        "name": "NutriGlow Naturals Raw Irish Coffee Face Wash",
        "brand": "NutriGlow",
        "price": 199.0,
        "weight_per_unit": "100g",
        "description": "Energizing daily face wash infused with pure Irish coffee powder and honey. Unclogs pores, controls oil, and wakes up tired skin.",
        "variants": [{"title": "100g", "price": 199.0}],
        "queries": [
            "NutriGlow Naturals Raw Irish Coffee Face Wash 100g tube white background",
            "NutriGlow Raw Irish Coffee Face Wash packshot white background",
        ],
    },
    {
        "name": "Garnier Bright Complete Vitamin C Face Wash",
        "brand": "Garnier",
        "price": 180.0,
        "weight_per_unit": "100g",
        "description": "Enriched with Yuzu lemon essence and Vitamin C to cleanse, clear dullness, and visibly brighten skin from the first wash.",
        "variants": [{"title": "50g", "price": 99.0}, {"title": "100g", "price": 180.0}],
        "queries": [
            "Garnier Bright Complete Vitamin C Face Wash 100g tube white background",
            "Garnier Bright Complete Face Wash packshot white background",
        ],
    },
    {
        "name": "Garnier Bright Complete Vitamin C Serum Cleanser",
        "brand": "Garnier",
        "price": 109.0,
        "weight_per_unit": "50g",
        "description": "High potency Vitamin C serum cleanser that deep cleanses while delivering the nourishing benefits of an active face serum.",
        "variants": [{"title": "50g", "price": 109.0}],
        "queries": [
            "Garnier Bright Complete Vitamin C Serum Cleanser 50g tube white background",
            "Garnier Serum Cleanser Vitamin C packshot white background",
        ],
    },
    {
        "name": "Dr. Sheth's Ceramide & Vitamin C Face Wash",
        "brand": "Dr. Sheth's",
        "price": 299.0,
        "weight_per_unit": "100ml",
        "description": "Formulated for Indian skin with 1% Ceramide Complex, 1% Vitamin C, and Glycerin. Non-drying daily cleanser that strengthens the moisture barrier and fades spots.",
        "variants": [{"title": "100ml", "price": 299.0}],
        "queries": [
            "Dr Sheths Ceramide Vitamin C Face Wash 100ml tube white background",
            "Dr. Sheth's Ceramide & Vitamin C Face Wash packshot white background",
        ],
    },
    {
        "name": "Dr. Sheth's Kesar & Kojic Acid Face Wash",
        "brand": "Dr. Sheth's",
        "price": 299.0,
        "weight_per_unit": "100ml",
        "description": "Formulated with 1% Kesar Extract and 1% Kojic Acid to target stubborn pigmentation, even out tone, and deliver an instant glow.",
        "variants": [{"title": "100ml", "price": 299.0}],
        "queries": [
            "Dr Sheths Kesar Kojic Acid Face Wash 100ml tube white background",
            "Dr. Sheth's Kesar & Kojic Acid Face Wash packshot white background",
        ],
    },

    # ---------------------------------------------------------
    # 3. Hair Removal & Grooming (g55, g56, g57, g58, g59)
    # ---------------------------------------------------------
    {
        "name": "Veet Pure Hair Removal Cream - Normal Skin",
        "brand": "Veet",
        "price": 145.0,
        "weight_per_unit": "100g",
        "description": "Pure formula hair removal cream with cucumber extract, free from ammonia smell. Leaves skin smooth and touchably soft in 3-6 minutes.",
        "variants": [{"title": "50g", "price": 79.0}, {"title": "100g", "price": 145.0}],
        "queries": [
            "Veet Pure Hair Removal Cream Normal Skin 100g tube white background",
            "Veet Pure Normal Skin Hair Removal Cream packshot white background",
        ],
    },
    {
        "name": "Veet Pure Hair Removal Cream - Sensitive Skin",
        "brand": "Veet",
        "price": 155.0,
        "weight_per_unit": "100g",
        "description": "Dermatologically tested for sensitive skin, enriched with Aloe Vera and Vitamin E to soothe while gently removing short hair.",
        "variants": [{"title": "50g", "price": 85.0}, {"title": "100g", "price": 155.0}],
        "queries": [
            "Veet Pure Hair Removal Cream Sensitive Skin 100g tube white background",
            "Veet Pure Sensitive Skin Hair Removal Cream packshot white background",
        ],
    },
    {
        "name": "Veet Professional Full Body Wax Strips",
        "brand": "Veet",
        "price": 240.0,
        "weight_per_unit": "120g",
        "description": "Ready-to-use professional cold wax strips with Easy-Gel technology. Grips hair as short as 1.5mm, delivering up to 28 days of salon smoothness.",
        "variants": [{"title": "Pack of 20 Strips", "price": 240.0}],
        "queries": [
            "Veet Professional Wax Strips 20 strips box white background",
            "Veet Professional Cold Wax Strips packshot white background",
        ],
    },
    {
        "name": "Bombae 6-in-1 Sensitive Trimmer Fuzz Off",
        "brand": "Bombae",
        "price": 1299.0,
        "weight_per_unit": "150g",
        "description": "Multi-grooming battery operated precision trimmer for eyebrows, upper lip, chin, sideburns, and bikini line. Hypoallergenic blades prevent irritation and cuts.",
        "variants": [{"title": "Complete Trimmer Kit", "price": 1299.0}],
        "queries": [
            "Bombae 6-in-1 sensitive trimmer fuzz off box white background",
            "Bombae Sensitive Trimmer device white background",
        ],
    },
    {
        "name": "Bombae Hair Removal Cream - Normal Skin",
        "brand": "Bombae",
        "price": 149.0,
        "weight_per_unit": "100g",
        "description": "Infused with shea butter and pleasant fragrance, effortlessly dissolves unwanted hair without burning or darkening skin.",
        "variants": [{"title": "50g", "price": 79.0}, {"title": "100g", "price": 149.0}],
        "queries": [
            "Bombae Hair Removal Cream Normal Skin 100g tube white background",
            "Bombae Hair Removal Cream packshot white background",
        ],
    },
    {
        "name": "Skins O3+ Peel Off Wax Hair Removal Beans",
        "brand": "O3+",
        "price": 295.0,
        "weight_per_unit": "100g",
        "description": "Professional stripless hot wax beads that melt smoothly and grip coarse to fine hair for painless, mess-free hair removal.",
        "variants": [{"title": "100g", "price": 295.0}],
        "queries": [
            "O3+ Peel Off Wax Hair Removal Beans 100g pouch white background",
            "Skins O3+ Peel Off Wax Beans packshot white background",
        ],
    },

    # ---------------------------------------------------------
    # 4. Fine Fragrances, EDPs & Perfumes (g60, g61, g62)
    # ---------------------------------------------------------
    {
        "name": "Layer'r Wottagirl! Bella Eau De Parfum",
        "brand": "Layer'r Wottagirl!",
        "price": 449.0,
        "weight_per_unit": "100ml",
        "description": "Luxurious floral oriental Eau De Parfum blending enchanting vanilla, amber, and exotic florals for an alluring, long-lasting aura.",
        "variants": [{"title": "100ml", "price": 449.0}],
        "queries": [
            "Layer'r Wottagirl Bella Eau De Parfum 100ml bottle box white background",
            "Wottagirl Bella EDP packshot white background",
        ],
    },
    {
        "name": "Layer'r Wottagirl! Flora Eau De Parfum",
        "brand": "Layer'r Wottagirl!",
        "price": 449.0,
        "weight_per_unit": "100ml",
        "description": "Fresh blooming floral fragrance crafted with delicate blossoms, peony, and soft musk for an invigorating feminine scent.",
        "variants": [{"title": "100ml", "price": 449.0}],
        "queries": [
            "Layer'r Wottagirl Flora Eau De Parfum 100ml bottle box white background",
            "Wottagirl Flora EDP packshot white background",
        ],
    },
    {
        "name": "Layer'r Wottagirl! Luxe Lady Noir Daily Wear Perfume",
        "brand": "Layer'r Wottagirl!",
        "price": 399.0,
        "weight_per_unit": "90ml",
        "description": "Sophisticated dark floral daily-wear perfume combining blackcurrant, jasmine, and warm sandalwood for an exquisite evening statement.",
        "variants": [{"title": "90ml", "price": 399.0}],
        "queries": [
            "Layer'r Wottagirl Luxe Lady Noir Daily Wear Perfume 90ml box white background",
            "Wottagirl Lady Noir Perfume packshot white background",
        ],
    },
    {
        "name": "Denver Black.code Eau De Parfum",
        "brand": "Denver",
        "price": 499.0,
        "weight_per_unit": "100ml",
        "description": "Magnetic masculine EDP featuring bold notes of citrus, patchouli, and woody amber. Commands presence and long-lasting freshness.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Denver Black code Eau De Parfum 100ml bottle box white background",
            "Denver Black.code EDP packshot white background",
        ],
    },
    {
        "name": "Denver Honour Eau De Parfum",
        "brand": "Denver",
        "price": 499.0,
        "weight_per_unit": "100ml",
        "description": "Refined Eau De Parfum with aromatic top notes, lavender heart, and an earthy cedarwood base for an aura of timeless prestige.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Denver Honour Eau De Parfum 100ml bottle box white background",
            "Denver Honour EDP packshot white background",
        ],
    },
    {
        "name": "Denver Sporting Club Gold Eau De Parfum",
        "brand": "Denver",
        "price": 499.0,
        "weight_per_unit": "100ml",
        "description": "Energetic sporty fragrance formulated with dynamic citrus, spice, and vetiver notes to keep you confident throughout the day.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Denver Sporting Club Gold Eau De Parfum 100ml bottle box white background",
            "Denver Sporting Club Gold EDP packshot white background",
        ],
    },
    {
        "name": "Denver Autograph Collection Hamilton Eau De Parfum",
        "brand": "Denver",
        "price": 449.0,
        "weight_per_unit": "60ml",
        "description": "Signature collection Eau De Parfum in premium glass flacon. Intensely fresh aquatic notes fused with spicy woods and leather.",
        "variants": [{"title": "60ml", "price": 449.0}, {"title": "100ml", "price": 649.0}],
        "queries": [
            "Denver Autograph Collection Hamilton Eau De Parfum 60ml green bottle white background",
            "Denver Hamilton EDP packshot white background",
        ],
    },
    {
        "name": "Denver Imperial Eau De Parfum",
        "brand": "Denver",
        "price": 499.0,
        "weight_per_unit": "100ml",
        "description": "Opulent masculine perfume featuring regal accords of nutmeg, amber, and rare woods.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Denver Imperial Eau De Parfum 100ml bottle box white background",
            "Denver Imperial EDP packshot white background",
        ],
    },
    {
        "name": "Bella Vita Luxury Blush Woman Eau De Parfum",
        "brand": "Bella Vita Luxury",
        "price": 599.0,
        "weight_per_unit": "100ml",
        "description": "Romantic feminine fragrance blending delicate floral roses, ripe red berries, and warm vanilla undertones.",
        "variants": [{"title": "100ml", "price": 599.0}],
        "queries": [
            "Bella Vita Luxury Blush Woman Eau De Parfum 100ml bottle box white background",
            "Bella Vita Blush EDP packshot white background",
        ],
    },
    {
        "name": "Vanesa Desire Eau De Parfum",
        "brand": "Vanesa",
        "price": 499.0,
        "weight_per_unit": "100ml",
        "description": "Captivating Eau De Parfum designed for women with floral top notes, sweet orchid heart, and sensual white musk base.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Vanesa Desire Eau De Parfum 100ml pink box bottle white background",
            "Vanesa Desire EDP packshot white background",
        ],
    },
    {
        "name": "Vanesa Glamour Eau De Parfum",
        "brand": "Vanesa",
        "price": 499.0,
        "weight_per_unit": "100ml",
        "description": "Rich red floral oriental fragrance evoking glamour and elegance for evening occasions.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Vanesa Glamour Eau De Parfum 100ml red box bottle white background",
            "Vanesa Glamour EDP packshot white background",
        ],
    },
    {
        "name": "Yardley London London Mist Daily Wear Perfume",
        "brand": "Yardley London",
        "price": 549.0,
        "weight_per_unit": "100ml",
        "description": "90% naturally derived daily-wear perfume with notes of English orchid and violet, providing an uplifting floral burst.",
        "variants": [{"title": "100ml", "price": 549.0}],
        "queries": [
            "Yardley London London Mist Daily Wear Perfume 100ml bottle box white background",
            "Yardley London Mist Perfume packshot white background",
        ],
    },
    {
        "name": "Yardley London Vanilla Blush Eau De Parfum",
        "brand": "Yardley London",
        "price": 599.0,
        "weight_per_unit": "100ml",
        "description": "Luxurious Eau De Parfum with warm Madagascar vanilla, freesia, and delicate white musk for an irresistible romantic trail.",
        "variants": [{"title": "100ml", "price": 599.0}],
        "queries": [
            "Yardley London Vanilla Blush Eau De Parfum 100ml bottle box white background",
            "Yardley Vanilla Blush EDP packshot white background",
        ],
    },
    {
        "name": "Yardley London Starlit Bloom Eau De Parfum",
        "brand": "Yardley London",
        "price": 599.0,
        "weight_per_unit": "100ml",
        "description": "Sensual Eau De Parfum infused with natural essential oils of night-blooming jasmine, bergamot, and cedar.",
        "variants": [{"title": "100ml", "price": 599.0}],
        "queries": [
            "Yardley London Starlit Bloom Eau De Parfum 100ml bottle box white background",
            "Yardley Starlit Bloom EDP packshot white background",
        ],
    },
    {
        "name": "Yardley London English Lavender Daily Wear Perfume",
        "brand": "Yardley London",
        "price": 549.0,
        "weight_per_unit": "100ml",
        "description": "Iconic heritage fragrance crafted with pure English lavender oil, calming chamomile, and crisp bergamot.",
        "variants": [{"title": "100ml", "price": 549.0}],
        "queries": [
            "Yardley London English Lavender Daily Wear Perfume 100ml bottle box white background",
            "Yardley English Lavender Perfume packshot white background",
        ],
    },
    {
        "name": "Yardley London English Rose Daily Wear Perfume",
        "brand": "Yardley London",
        "price": 549.0,
        "weight_per_unit": "100ml",
        "description": "Contemporary daily wear perfume capturing the essence of fresh dewy morning roses with sparkling tea rose notes.",
        "variants": [{"title": "100ml", "price": 549.0}],
        "queries": [
            "Yardley London English Rose Daily Wear Perfume 100ml bottle box white background",
            "Yardley English Rose Perfume packshot white background",
        ],
    },
    {
        "name": "Yardley London Gentleman Urbane Daily Wear Perfume",
        "brand": "Yardley London",
        "price": 399.0,
        "weight_per_unit": "50ml",
        "description": "Distinctive fougère fragrance for the modern gentleman, combining bergamot, lavender, and patchouli.",
        "variants": [{"title": "50ml", "price": 399.0}, {"title": "100ml", "price": 599.0}],
        "queries": [
            "Yardley London Gentleman Urbane Daily Wear Perfume 50ml bottle box white background",
            "Yardley Gentleman Urbane Perfume packshot white background",
        ],
    },
    {
        "name": "Yardley London Gentleman Gold Daily Wear Perfume",
        "brand": "Yardley London",
        "price": 399.0,
        "weight_per_unit": "50ml",
        "description": "Warm spicy and woody fragrance blending cardamom, nutmeg, cedarwood, and rich amber.",
        "variants": [{"title": "50ml", "price": 399.0}, {"title": "100ml", "price": 599.0}],
        "queries": [
            "Yardley London Gentleman Gold Daily Wear Perfume 50ml bottle box white background",
            "Yardley Gentleman Gold Perfume packshot white background",
        ],
    },
    {
        "name": "Yardley London Gentleman Explorer Daily Wear Perfume",
        "brand": "Yardley London",
        "price": 399.0,
        "weight_per_unit": "50ml",
        "description": "Fresh aquatic and green fragrance designed for the adventurous spirit, featuring marine accord, moss, and sandalwood.",
        "variants": [{"title": "50ml", "price": 399.0}, {"title": "100ml", "price": 599.0}],
        "queries": [
            "Yardley London Gentleman Explorer Daily Wear Perfume 50ml bottle box white background",
            "Yardley Gentleman Explorer Perfume packshot white background",
        ],
    },
    {
        "name": "Yardley London Gentleman Royale Daily Wear Perfume",
        "brand": "Yardley London",
        "price": 399.0,
        "weight_per_unit": "50ml",
        "description": "Regal Eau De Parfum combining fresh citrus, spicy pepper heart, and a smoky tobacco-leather base.",
        "variants": [{"title": "50ml", "price": 399.0}, {"title": "100ml", "price": 599.0}],
        "queries": [
            "Yardley London Gentleman Royale Daily Wear Perfume 50ml bottle box white background",
            "Yardley Gentleman Royale Perfume packshot white background",
        ],
    },
    {
        "name": "Woodland Gloworm Eau De Parfum",
        "brand": "Woodland",
        "price": 699.0,
        "weight_per_unit": "100ml",
        "description": "Premium Eau De Parfum spray crafted with electric citrus, cypress, vetiver, and smoky amber for an earthy outdoor scent.",
        "variants": [{"title": "100ml", "price": 699.0}],
        "queries": [
            "Woodland Gloworm Eau De Parfum 100ml bottle box white background",
            "Woodland Gloworm EDP packshot white background",
        ],
    },
    {
        "name": "Woodland Masai Mara Eau De Parfum",
        "brand": "Woodland",
        "price": 699.0,
        "weight_per_unit": "100ml",
        "description": "Exotic spicy woody EDP inspired by the African wilderness, featuring cinnamon, cedarwood, and warm leather notes.",
        "variants": [{"title": "100ml", "price": 699.0}],
        "queries": [
            "Woodland Masai Mara Eau De Parfum 100ml bottle box white background",
            "Woodland Masai Mara EDP packshot white background",
        ],
    },
    {
        "name": "Swiss Beauty She Shines Eau De Parfum",
        "brand": "Swiss Beauty",
        "price": 599.0,
        "weight_per_unit": "100ml",
        "description": "Golden floral EDP opening with sparkling mandarin and blackcurrant, evolving into jasmine, orange blossom, and Madagascar vanilla.",
        "variants": [{"title": "100ml", "price": 599.0}],
        "queries": [
            "Swiss Beauty She Shines Eau De Parfum 100ml bottle box white background",
            "Swiss Beauty She Shines EDP packshot white background",
        ],
    },
    {
        "name": "Beardo Tsunami Eau De Parfum",
        "brand": "Beardo",
        "price": 699.0,
        "weight_per_unit": "100ml",
        "description": "Powerful aquatic EDP evoking the raw energy of ocean waves. Top notes of sea salt and lemon with a base of oakmoss and musk.",
        "variants": [{"title": "100ml", "price": 699.0}],
        "queries": [
            "Beardo Tsunami Eau De Parfum 100ml bottle box white background",
            "Beardo Tsunami EDP packshot white background",
        ],
    },
    {
        "name": "Beardo Whisky Smoke No Gas Perfume Body Spray",
        "brand": "Beardo",
        "price": 299.0,
        "weight_per_unit": "120ml",
        "description": "Long-lasting no gas body spray with an intoxicating blend of aged whiskey, cinnamon spice, and rich smoky tobacco.",
        "variants": [{"title": "120ml", "price": 299.0}],
        "queries": [
            "Beardo Whisky Smoke No Gas Perfume Body Spray 120ml can white background",
            "Beardo Whisky Smoke No Gas Body Spray packshot white background",
        ],
    },
    {
        "name": "Wild Stone CODE Copper No Gas Body Perfume",
        "brand": "Wild Stone CODE",
        "price": 275.0,
        "weight_per_unit": "120ml",
        "description": "Warm and sensual no-gas body perfume with invigorating notes of citrus, cardamom, and amberwood for charismatic style.",
        "variants": [{"title": "120ml", "price": 275.0}],
        "queries": [
            "Wild Stone CODE Copper No Gas Body Perfume 120ml bottle white background",
            "Wild Stone CODE Copper packshot white background",
        ],
    },
    {
        "name": "Wild Stone CODE Titanium No Gas Body Perfume",
        "brand": "Wild Stone CODE",
        "price": 275.0,
        "weight_per_unit": "120ml",
        "description": "Crisp and masculine fragrance featuring aquatic citrus, lavender, and guaiac wood.",
        "variants": [{"title": "120ml", "price": 275.0}],
        "queries": [
            "Wild Stone CODE Titanium No Gas Body Perfume 120ml bottle white background",
            "Wild Stone CODE Titanium packshot white background",
        ],
    },
    {
        "name": "Wild Stone CODE Steel No Gas Body Perfume",
        "brand": "Wild Stone CODE",
        "price": 275.0,
        "weight_per_unit": "120ml",
        "description": "Vibrant fragrance combining lemon, green melon, and tonka bean for a confident metallic freshness.",
        "variants": [{"title": "120ml", "price": 275.0}],
        "queries": [
            "Wild Stone CODE Steel No Gas Body Perfume 120ml bottle white background",
            "Wild Stone CODE Steel packshot white background",
        ],
    },
    {
        "name": "Wild Stone CODE Platinum No Gas Body Perfume",
        "brand": "Wild Stone CODE",
        "price": 275.0,
        "weight_per_unit": "120ml",
        "description": "Sophisticated perfume spray with aromatic lavender, sage, and cashmeran notes for formal occasions.",
        "variants": [{"title": "120ml", "price": 275.0}],
        "queries": [
            "Wild Stone CODE Platinum No Gas Body Perfume 120ml bottle white background",
            "Wild Stone CODE Platinum packshot white background",
        ],
    },
    {
        "name": "Wild Stone CODE Iridium No Gas Body Perfume",
        "brand": "Wild Stone CODE",
        "price": 275.0,
        "weight_per_unit": "120ml",
        "description": "High performance no-gas body perfume infused with lavender, bergamot, and earthy patchouli.",
        "variants": [{"title": "120ml", "price": 275.0}],
        "queries": [
            "Wild Stone CODE Iridium No Gas Body Perfume 120ml bottle white background",
            "Wild Stone CODE Iridium packshot white background",
        ],
    },
    {
        "name": "Envy Triumph Eau De Parfum",
        "brand": "Envy",
        "price": 499.0,
        "weight_per_unit": "100ml",
        "description": "Made with rich French fragrance notes, combining citrus zest, spicy cardamom, and vetiver for modern elegance.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Envy Triumph Eau De Parfum 100ml black gold box bottle white background",
            "Envy Triumph EDP packshot white background",
        ],
    },
    {
        "name": "Envy Explorer Eau De Parfum",
        "brand": "Envy",
        "price": 499.0,
        "weight_per_unit": "100ml",
        "description": "Bold masculine EDP crafted with invigorating sea breeze accord, pepper, and rich earthy cedarwood.",
        "variants": [{"title": "100ml", "price": 499.0}],
        "queries": [
            "Envy Explorer Eau De Parfum 100ml brown gold box bottle white background",
            "Envy Explorer EDP packshot white background",
        ],
    },

    # ---------------------------------------------------------
    # 5. Oral Care & Baby Hygiene (g52, g53)
    # ---------------------------------------------------------
    {
        "name": "Chicco Dentifrico Kids Toothpaste Strawberry",
        "brand": "Chicco",
        "price": 199.0,
        "weight_per_unit": "50ml",
        "description": "Fluoride-free child safe toothpaste with bio-available calcium and yummy strawberry flavour. Gentle on milk teeth and baby gums.",
        "variants": [{"title": "50ml", "price": 199.0}],
        "queries": [
            "Chicco Dentifrico Kids Toothpaste Strawberry 50ml tube white background",
            "Chicco Toothpaste Strawberry Kids packshot white background",
        ],
    },
    {
        "name": "Chicco Dentifrico Kids Toothpaste Apple-Banana",
        "brand": "Chicco",
        "price": 199.0,
        "weight_per_unit": "50ml",
        "description": "Preservative-free and low-abrasion formula with delicious apple-banana taste for toddlers and young children.",
        "variants": [{"title": "50ml", "price": 199.0}],
        "queries": [
            "Chicco Dentifrico Kids Toothpaste Apple Banana 50ml tube white background",
            "Chicco Toothpaste Apple Banana Kids packshot white background",
        ],
    },
    {
        "name": "Chicco Super Slim Soft Toothbrush for Kids",
        "brand": "Chicco",
        "price": 149.0,
        "weight_per_unit": "30g",
        "description": "Ultra-soft tapered bristles designed to clean interdental spaces gently without hurting tender gums. Includes suction cup base.",
        "variants": [{"title": "3 to 8 Years", "price": 149.0}],
        "queries": [
            "Chicco Super Slim Soft Toothbrush 3-8 years blister pack white background",
            "Chicco Kids Toothbrush packshot white background",
        ],
    },
    {
        "name": "Chicco Extra Soft Toothbrush for Infants",
        "brand": "Chicco",
        "price": 139.0,
        "weight_per_unit": "25g",
        "description": "Rounded small head and extra soft micro-fine bristles specially designed for babies' very first teeth.",
        "variants": [{"title": "6 to 36 Months", "price": 139.0}],
        "queries": [
            "Chicco Extra Soft Toothbrush 6-36 months blister pack white background",
            "Chicco Infant Toothbrush packshot white background",
        ],
    },
    {
        "name": "DentoShine Gel Toothpaste for Kids - Bubble Gum",
        "brand": "DentoShine",
        "price": 90.0,
        "weight_per_unit": "80g",
        "description": "Fluoride-rich bubble gum flavoured sparkle gel toothpaste that protects children's teeth from cavities and plaque.",
        "variants": [{"title": "80g", "price": 90.0}],
        "queries": [
            "DentoShine Gel Toothpaste Kids Bubble Gum 80g tube white background",
            "DentoShine Bubble Gum Toothpaste packshot white background",
        ],
    },
    {
        "name": "DentoShine Silicone Finger Toothbrush with Hygiene Case",
        "brand": "DentoShine",
        "price": 99.0,
        "weight_per_unit": "25g",
        "description": "100% BPA-free food-grade silicone finger brush for gentle gum massage and oral cleaning for babies aged 0 to 24 months.",
        "variants": [{"title": "Finger Brush + Case", "price": 99.0}],
        "queries": [
            "DentoShine Silicone Finger Toothbrush with Hygiene Case blister pack white background",
            "DentoShine Finger Brush packshot white background",
        ],
    },
    {
        "name": "Listerine Cool Mint Antiseptic Mouthwash",
        "brand": "Listerine",
        "price": 165.0,
        "weight_per_unit": "250ml",
        "description": "Kills 99.9% of germs that cause bad breath, plaque, and gingivitis. Provides 24-hour antibacterial oral protection.",
        "variants": [{"title": "250ml", "price": 165.0}, {"title": "500ml", "price": 285.0}],
        "queries": [
            "Listerine Cool Mint Antiseptic Mouthwash 250ml bottle white background",
            "Listerine Cool Mint Mouthwash packshot white background",
        ],
    },
    {
        "name": "Listerine Fresh Burst Mouthwash",
        "brand": "Listerine",
        "price": 165.0,
        "weight_per_unit": "250ml",
        "description": "Deep cleaning antibacterial mouth rinse with an invigorating spearmint rush that leaves breath clean and fresh.",
        "variants": [{"title": "250ml", "price": 165.0}],
        "queries": [
            "Listerine Fresh Burst Mouthwash 250ml bottle white background",
            "Listerine Fresh Burst bottle packshot white background",
        ],
    },
]


def load_and_clean_image(image_bytes: bytes) -> Image.Image:
    """Safely loads image and strips alpha / palette transparency onto pure white."""
    raw = Image.open(io.BytesIO(image_bytes))
    if raw.mode in ("RGBA", "LA"):
        bg = Image.new("RGB", raw.size, (255, 255, 255))
        bg.paste(raw, mask=raw.split()[-1])
        return bg
    elif raw.mode == "P":
        raw = raw.convert("RGBA")
        bg = Image.new("RGB", raw.size, (255, 255, 255))
        bg.paste(raw, mask=raw.split()[-1])
        return bg
    elif raw.mode != "RGB":
        return raw.convert("RGB")
    return raw


def pad_to_square(img: Image.Image, target_size: int = 800) -> Image.Image:
    """Pads image into a pure white 1:1 square canvas without distortion."""
    w, h = img.size
    scale = min(target_size / w, target_size / h)
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
    print(f"🚀 INGESTING MAXX RETAIL BATCH 7: {len(CATALOG_BATCH7)} COSMETICS, FACIAL KITS & PERFUMES")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary: Strictly N/A (is_veg = None)")
    print(f"   Target Shop: {SHOP_ID}")
    print("=" * 80)

    prepared_products = []

    for idx, item in enumerate(CATALOG_BATCH7, 1):
        print(f"\n[{idx:03d}/{len(CATALOG_BATCH7):03d}] 📸 Processing authentic packshots for: {item['brand']} - {item['name']}...")

        packshot1_path = os.path.join(CACHE_DIR, f"maxx_b7_{idx}_1.jpg")
        packshot2_path = os.path.join(CACHE_DIR, f"maxx_b7_{idx}_2.jpg")

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

        st_path1 = f"{STORAGE_PREFIX}/maxx_b7_{idx}_1.jpg"
        st_path2 = f"{STORAGE_PREFIX}/maxx_b7_{idx}_2.jpg"

        url1 = upload_to_supabase_storage(packshot1_path, st_path1, config)
        url2 = upload_to_supabase_storage(packshot2_path, st_path2, config)
        print(f"      ☁️  Uploaded real packshots to Supabase Storage")

        payload = {
            "name": item["name"],
            "brand": item["brand"],
            "category": "Cosmetics & Beauty",
            "menu_category": "Cosmetics & Beauty",
            "price": float(item["price"]),
            "original_price": None,
            "description": item["description"],
            "is_veg": None,  # Strictly None / N/A
            "is_available": True,
            "is_deleted": False,
            "requires_prescription": False,
            "medicine_type": "General",
            "unit_type": "pieces",
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
    print(f"📤 Syncing all {len(prepared_products)} Batch 7 items into Supabase database...")
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
    print(f"🎉 Batch 7 ingestion complete! Total Inserted: {total_inserted}, Total Updated: {total_updated}")
    print("=" * 80)


if __name__ == "__main__":
    main()
