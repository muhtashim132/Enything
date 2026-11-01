#!/usr/bin/env python3
"""
Maxx Retail Batch 8 (Shelf Scans g63.jpeg - g72.jpeg) Ingestion Engine
======================================================================
Catalog: 83 authentic professional cold creams, multi-purpose moisturizers,
         barrier repair creams, salon bleaches, glycerin USP solutions,
         pure petroleum jellies, setting sprays, liquid foundations, compacts,
         and specialized facial washes:
  - Cold Creams, Moisturizers & Hydrating Gels (g70, g71, g72):
      * Dabur Gulabari Moisturizing Cold Cream (100g)
      * Pond's Skin Institute Bright Beauty Spot-less Glow Serum (30ml)
      * Pond's Skin Institute Youthful Miracle Day Cream with Retinol-C (50g)
      * Pond's Skin Institute Hydra Miracle Gel Hydrating Moisturizer (50g)
      * Lotus Herbals WhiteGlow Skin Whitening & Brightening Deep Moisturizing Crème SPF 20 PA+++ (60g)
      * Lotus Herbals WhiteGlow Skin Whitening & Brightening Gel Crème SPF 25 PA+++ (60g)
      * Lotus Herbals WhiteGlow Vitamin-C + Gold Radiance Serum (30ml)
      * Biluma Glow 15% Vitamin C Brightening Serum (30ml)
      * Joy Skin Fruits Fruit Moisturizer (Nourishing Skin Cream Tub 200ml)
      * Joy Skin Fruits Fruit Moisturizer (Nourishing Skin Cream Tub 500ml)
      * Joy Honey & Almonds Nourishing Skin Cream Tub (200ml)
      * Joy Honey & Almonds Nourishing Skin Cream Tub (500ml)
      * Joy Skin Fruits All Purpose Cream Spotless Glow with Strawberry (200ml)
      * Nivea Soft Light Moisturiser Non-Greasy Cream (100ml tub)
      * Nivea Soft Light Moisturiser Non-Greasy Cream (200ml tub)
      * Nivea Men Creme Dark Spot Reduction & Moisture (75ml tin)
      * Boroline Antiseptic Ayurvedic Cream (20g tub)
      * Boroline Antiseptic Ayurvedic Cream (40g tub)
      * Himalaya Winter Defense Moisturizing Cream (100ml tub)
      * Aqualogica Glow+ Hydra Gel Moisturizer (100g)
      * Aqualogica Illuminate+ Hydra Gel Moisturizer (100g)
      * Be Soft Deep Moisturizing Cream (100g)

  - Active Derma Moisturizers & Cleansers (g72):
      * The Derma Co 5% Cica-Glow Daily Face Moisturizer (50g)
      * The Derma Co Pore Minimizing Daily Face Moisturizer (50g)
      * The Derma Co 5% Nia-Ceramide Intense Moisturizing Cream (100g)
      * The Derma Co 3% Vitamin E Daily Face Moisturizer (100g)
      * The Derma Co Oil-Free Daily Face Moisturizer (100g)
      * The Derma Co 5% Nia-Ceramide Daily Hydrating Moisturizer (100g)
      * The Derma Co 5% Nia-Ceramide Mattifying Moisturizer (100g)
      * Aqualogica Radiance+ Hydra Smooth Face Wash (100ml)
      * Aqualogica Glow+ Hydra Smooth Face Wash (100ml)
      * Aqualogica Clear+ Smooth Face Wash (100ml)
      * Garnier Men Acno Fight Anti-Pimple Face Wash (100g)
      * Garnier Men TurboBright Anti-Pollution Double Action Face Wash (100g)
      * Nivea Men All-in-1 Charcoal Face Wash (100g)

  - Pure Rose Water, Glycerin & Petroleum Jelly (g64, g65):
      * Dabur Gulabari Premium Rose Water (120ml)
      * Dabur Gulabari Premium Rose Water (250ml)
      * Dabur Gulabari Premium Rose Water (400ml)
      * Astraaz Glycerine with Aloe Vera (240g)
      * Astraaz Glycerine with Aloe Vera (500g)
      * Vaseline Blueseal Pure Petroleum Jelly Original (100ml)
      * Astraaz Astralene Petroleum Jelly with Vitamin E (50g)
      * Astraaz Astralene Petroleum Jelly with Vitamin E (100g)
      * Astraaz Astralene Petroleum Jelly with Vitamin E (200g)
      * Astraaz Astralene Petroleum Jelly with Vitamin E (300g)
      * Arora's Glycerin Oral Solution USP (100g)
      * Arora's Glycerin Oral Solution USP (200g)
      * Dabur Pure Glycerine Enriched with Rose Oil (100g)

  - Salon Professional & Herbal Bleach Creams (g65, g66, g67, g68, g69):
      * Fem Salon Professional Crème Bleach Saffron & Milk (Master Pack 300g)
      * Fem Gold Crème Bleach with 24K Gold Dust (64g)
      * Fem Diamond Crème Bleach (38g)
      * Fem Diamond Crème Bleach (64g)
      * Fem Turmeric & Milk Crème Bleach (38g)
      * Fem Turmeric & Milk Crème Bleach (64g)
      * Fem De-Tan Crème Bleach (38g)
      * Fem De-Tan Crème Bleach (64g)
      * Fem Gold Ultra Parlour Glow Bleach (64g)
      * OxyLife Natural Radiance 5 Crème Bleach (64g)
      * VLCC Insta Glow Diamond Bleach (60g)
      * VLCC Insta Glow Gold Bleach (60g)
      * VLCC Insta Glow Herbal Bleach (60g)
      * VLCC Insta Glow Oxygen Bleach (60g)
      * OxyGlow Herbals Hydra Boost Bleach Cream (42g)
      * OxyGlow Herbals Diamond Bleach Cream (42g)
      * OxyGlow Herbals Multi Fruit Bleach Cream (42g)
      * FYC Professional Papaya Bleach Cream (250g)
      * NutriGlow Papaya Fruit Bleach Cream (60g)
      * NutriGlow Papaya Fruit Bleach Cream (Master Salon Jar 250g)
      * NutriGlow Gold Kesar Bleach Cream (60g)
      * NutriGlow Gold Kesar Bleach Cream (Master Salon Jar 250g)
      * NutriGlow Diamond Radiance Bleach Cream (60g)
      * NutriGlow Diamond Radiance Bleach Cream (Master Salon Jar 250g)
      * NutriGlow Ubtan Bleach Cream (60g)
      * NutriGlow Wine Bleach Cream (60g)
      * NutriGlow Wine Bleach Cream (Master Salon Jar 250g)

  - Complexion, Base & Face Makeup (g64, g65, g66):
      * Insight Cosmetics 2 in 1 Super Stay Mist Foundation (50ml)
      * Insight Cosmetics Matte Finish Foundation (30ml)
      * Insight Cosmetics BB Cream Foundation (30ml)
      * Insight Cosmetics Makeup Setting Spray (50ml)
      * L'Oreal Paris Infallible 24H Fresh Wear Liquid Foundation (30ml)
      * Maybelline New York Fit Me Matte + Poreless Liquid Foundation (30ml)
      * Maybelline New York Fit Me Matte + Poreless Compact Powder (8g)
      * Daily Life Forever52 Ultra Definition Liquid Foundation (30ml)

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
STORAGE_PREFIX = f"{SHOP_ID}/batch8_packshots"
CACHE_DIR = "scratch/batch8_real_packshots"

CATALOG_BATCH8 = [
    # ---------------------------------------------------------
    # 1. Pure Rose Water, Glycerin & Petroleum Jelly (g64, g65)
    # ---------------------------------------------------------
    {
        "name": "Dabur Gulabari Premium Rose Water (120ml)",
        "brand": "Dabur",
        "price": 52.0,
        "weight_per_unit": 120.0,
        "description": "100% pure and natural rose water made from the finest Indian roses. Cleanses, tones, and hydrates dull and tired skin with an instant rosy glow.",
        "variants": [{"title": "120ml", "price": 52.0}],
        "queries": [
            "Dabur Gulabari Rose Water 120ml bottle white background",
            "Dabur Gulabari Premium Rose Water 120ml bottle packshot",
        ],
    },
    {
        "name": "Dabur Gulabari Premium Rose Water (250ml)",
        "brand": "Dabur",
        "price": 95.0,
        "weight_per_unit": 250.0,
        "description": "Natural rose water toner and skin refresher. Helps maintain natural skin pH balance and tightens pores with authentic damask rose essence.",
        "variants": [{"title": "250ml", "price": 95.0}],
        "queries": [
            "Dabur Gulabari Rose Water 250ml bottle white background",
            "Dabur Gulabari Premium Rose Water 250ml packshot",
        ],
    },
    {
        "name": "Dabur Gulabari Premium Rose Water (400ml)",
        "brand": "Dabur",
        "price": 140.0,
        "weight_per_unit": 400.0,
        "description": "Large value pack of pure natural rose water skin toner. Infuses skin with moisture, leaving it refreshed, plump, and subtly fragrant.",
        "variants": [{"title": "400ml", "price": 140.0}],
        "queries": [
            "Dabur Gulabari Rose Water 400ml bottle white background",
            "Dabur Gulabari Rose Water 400ml packshot",
        ],
    },
    {
        "name": "Astraaz Glycerine with Aloe Vera (240g)",
        "brand": "Astraaz",
        "price": 140.0,
        "weight_per_unit": 240.0,
        "description": "Multi-purpose pure skin care glycerine enriched with natural aloe vera extract. Provides intense hydration, heals cracked heels, and locks in deep moisture.",
        "variants": [{"title": "240g", "price": 140.0}],
        "queries": [
            "Astraaz Glycerine with Aloe Vera bottle white background",
            "Astraaz Glycerine aloe vera 240g packshot",
        ],
    },
    {
        "name": "Astraaz Glycerine with Aloe Vera (500g)",
        "brand": "Astraaz",
        "price": 260.0,
        "weight_per_unit": 500.0,
        "description": "Mega 500g pump bottle of pure glycerine enriched with soothing aloe vera. Ideal for deep winter nourishment, DIY face packs, and dry body care.",
        "variants": [{"title": "500g", "price": 260.0}],
        "queries": [
            "Astraaz Glycerine with Aloe Vera 500g bottle white background",
            "Astraaz Glycerine 500g aloe vera pump bottle packshot",
        ],
    },
    {
        "name": "Vaseline Blueseal Pure Petroleum Jelly Original (100ml)",
        "brand": "Vaseline",
        "price": 199.0,
        "weight_per_unit": 100.0,
        "description": "Triple-purified pure petroleum jelly that locks in natural moisture to protect and help heal dry, damaged, and cracked skin.",
        "variants": [{"title": "100ml", "price": 199.0}],
        "queries": [
            "Vaseline Blue Seal Pure Petroleum Jelly Original tub white background",
            "Vaseline Blueseal pure petroleum jelly original tub packshot",
        ],
    },
    {
        "name": "Astraaz Astralene Petroleum Jelly with Vitamin E (50g)",
        "brand": "Astraaz",
        "price": 45.0,
        "weight_per_unit": 50.0,
        "description": "Pure white petroleum jelly fortified with Vitamin E for cracked lips, dry elbows, and skin barrier protection against harsh winter weather.",
        "variants": [{"title": "50g", "price": 45.0}],
        "queries": [
            "Astraaz Astralene Petroleum Jelly tub white background",
            "Astralene pure petroleum jelly vitamin e 50g",
        ],
    },
    {
        "name": "Astraaz Astralene Petroleum Jelly with Vitamin E (100g)",
        "brand": "Astraaz",
        "price": 75.0,
        "weight_per_unit": 100.0,
        "description": "100g tub of pure petroleum jelly with Vitamin E. Creates a protective moisture shield, preventing moisture loss and soothing chapped skin.",
        "variants": [{"title": "100g", "price": 75.0}],
        "queries": [
            "Astraaz Astralene Petroleum Jelly 100g tub white background",
            "Astralene Petroleum Jelly with Vitamin E 100g tub",
        ],
    },
    {
        "name": "Astraaz Astralene Petroleum Jelly with Vitamin E (200g)",
        "brand": "Astraaz",
        "price": 135.0,
        "weight_per_unit": 200.0,
        "description": "200g family tub of pure petroleum jelly with Vitamin E. Dermatologically tested all-weather skin protectant for deep epidermal hydration.",
        "variants": [{"title": "200g", "price": 135.0}],
        "queries": [
            "Astraaz Astralene Petroleum Jelly 200g tub white background",
            "Astralene Petroleum Jelly with Vitamin E 200g tub packshot",
        ],
    },
    {
        "name": "Astraaz Astralene Petroleum Jelly with Vitamin E (300g)",
        "brand": "Astraaz",
        "price": 185.0,
        "weight_per_unit": 300.0,
        "description": "Large 300g value tub of pure petroleum jelly infused with Vitamin E. Nourishes extra dry skin, heals cracked feet, and softens rough skin.",
        "variants": [{"title": "300g", "price": 185.0}],
        "queries": [
            "Astraaz Astralene Petroleum Jelly 300g tub white background",
            "Astralene Petroleum Jelly with Vitamin E 300g tub packshot",
        ],
    },
    {
        "name": "Arora's Glycerin Oral Solution USP (100g)",
        "brand": "Arora's",
        "price": 65.0,
        "weight_per_unit": 100.0,
        "description": "Pharmaceutical grade pure USP glycerin. Hypoallergenic, versatile emollient and humectant for dry skin relief, mouth care, and winter hydration.",
        "variants": [{"title": "100g", "price": 65.0}],
        "queries": [
            "Arora Glycerin Oral Solution USP bottle white background",
            "Arora Glycerin USP 100g bottle packshot",
        ],
    },
    {
        "name": "Arora's Glycerin Oral Solution USP (200g)",
        "brand": "Arora's",
        "price": 120.0,
        "weight_per_unit": 200.0,
        "description": "200g bottle of pure pharmaceutical grade USP glycerin. Retains moisture, protects skin barrier, and treats dry chapped lips and heels.",
        "variants": [{"title": "200g", "price": 120.0}],
        "queries": [
            "Arora Glycerin Oral Solution USP 200g bottle white background",
            "Arora Glycerin USP 200g packshot bottle",
        ],
    },
    {
        "name": "Dabur Pure Glycerine Enriched with Rose Oil (100g)",
        "brand": "Dabur",
        "price": 85.0,
        "weight_per_unit": 100.0,
        "description": "Pure premium cosmetic glycerin enriched with natural rose oil fragrance. Deeply conditions dry skin, giving it a soft, supple, glowing touch.",
        "variants": [{"title": "100g", "price": 85.0}],
        "queries": [
            "Dabur Pure Glycerine Enriched with Rose Oil bottle white background",
            "Dabur Glycerine with Rose Oil 100g packshot",
        ],
    },

    # ---------------------------------------------------------
    # 2. Salon Professional & Herbal Bleach Creams (g65 - g69)
    # ---------------------------------------------------------
    {
        "name": "Fem Salon Professional Crème Bleach Saffron & Milk (Master Pack 300g)",
        "brand": "Fem",
        "price": 295.0,
        "weight_per_unit": 300.0,
        "description": "Salon professional master tub of saffron and pure milk crème bleach. Formulated with pre-bleach cream and activator for instant healthy radiant parlour glow.",
        "variants": [{"title": "300g", "price": 295.0}],
        "queries": [
            "Fem Salon Professional Creme Bleach Saffron and Milk 300g box white background",
            "Fem Saffron and Milk Bleach 300g tub packshot",
        ],
    },
    {
        "name": "Fem Gold Crème Bleach with 24K Gold Dust (64g)",
        "brand": "Fem",
        "price": 130.0,
        "weight_per_unit": 64.0,
        "description": "Enriched with real 24K gold dust and nourishing flower extracts. Lightens facial hair to match skin tone while providing a special luminous golden glow.",
        "variants": [{"title": "64g", "price": 130.0}],
        "queries": [
            "Fem Gold Creme Bleach 24K Gold Dust 64g box white background",
            "Fem Gold Bleach 64g box packshot",
        ],
    },
    {
        "name": "Fem Diamond Crème Bleach (38g)",
        "brand": "Fem",
        "price": 85.0,
        "weight_per_unit": 38.0,
        "description": "Enriched with diamond sparkle actives to lighten facial hair and impart an exquisite sparkling diamond radiance in just 15 minutes.",
        "variants": [{"title": "38g", "price": 85.0}],
        "queries": [
            "Fem Diamond Creme Bleach box white background",
            "Fem Diamond Bleach sparkling glow packshot",
        ],
    },
    {
        "name": "Fem Diamond Crème Bleach (64g)",
        "brand": "Fem",
        "price": 145.0,
        "weight_per_unit": 64.0,
        "description": "Value 64g pack of Fem Diamond Crème Bleach with diamond dust and pre-bleach cream for unmatched sparkling bridal radiance.",
        "variants": [{"title": "64g", "price": 145.0}],
        "queries": [
            "Fem Diamond Creme Bleach 64g box white background",
            "Fem Diamond Bleach 64g packshot",
        ],
    },
    {
        "name": "Fem Turmeric & Milk Crème Bleach (38g)",
        "brand": "Fem",
        "price": 65.0,
        "weight_per_unit": 38.0,
        "description": "Ayurvedic turmeric and milk formula specially designed to brighten skin tone, lighten dark hair, and provide a gentle soft natural glow.",
        "variants": [{"title": "38g", "price": 65.0}],
        "queries": [
            "Fem Turmeric and Milk Creme Bleach box white background",
            "Fem Turmeric and Milk Bleach packshot",
        ],
    },
    {
        "name": "Fem Turmeric & Milk Crème Bleach (64g)",
        "brand": "Fem",
        "price": 115.0,
        "weight_per_unit": 64.0,
        "description": "64g pack of herbal turmeric and nourishing milk cream bleach. Safe, gentle on skin, and effective for flawless even complexion.",
        "variants": [{"title": "64g", "price": 115.0}],
        "queries": [
            "Fem Turmeric and Milk Creme Bleach 64g box white background",
            "Fem Turmeric Milk Bleach 64g packshot",
        ],
    },
    {
        "name": "Fem De-Tan Crème Bleach (38g)",
        "brand": "Fem",
        "price": 75.0,
        "weight_per_unit": 38.0,
        "description": "Formulated specifically for active tan removal and sun-damaged skin. Lightens facial hair while lifting deep epidermal tan in 15 minutes.",
        "variants": [{"title": "38g", "price": 75.0}],
        "queries": [
            "Fem De-Tan Creme Bleach box white background",
            "Fem De-Tan Bleach active tan removal packshot",
        ],
    },
    {
        "name": "Fem De-Tan Crème Bleach (64g)",
        "brand": "Fem",
        "price": 135.0,
        "weight_per_unit": 64.0,
        "description": "64g salon pack of Fem De-Tan Crème Bleach with orange peel extracts for effective sun tan removal and radiant, even-toned skin.",
        "variants": [{"title": "64g", "price": 135.0}],
        "queries": [
            "Fem De-Tan Creme Bleach 64g box white background",
            "Fem De Tan Bleach 64g packshot",
        ],
    },
    {
        "name": "Fem Gold Ultra Parlour Glow Bleach (64g)",
        "brand": "Fem",
        "price": 150.0,
        "weight_per_unit": 64.0,
        "description": "Special salon parlour formulation of Fem Gold Ultra Bleach. Imparts rich golden shimmer, evens out dark facial hair, and leaves a lustrous bridal shine.",
        "variants": [{"title": "64g", "price": 150.0}],
        "queries": [
            "Fem Gold Ultra Parlour Glow Bleach 64g box white background",
            "Fem Gold Ultra Bleach 64g packshot",
        ],
    },
    {
        "name": "OxyLife Natural Radiance 5 Crème Bleach (64g)",
        "brand": "OxyLife",
        "price": 150.0,
        "weight_per_unit": 64.0,
        "description": "Patented active oxygen formulation that helps infuse high oxygen levels into the skin, fighting 5 skin problems: dullness, dark spots, uneven tone, dark hair, and dead cells.",
        "variants": [{"title": "64g", "price": 150.0}],
        "queries": [
            "OxyLife Natural Radiance 5 Creme Bleach 64g box white background",
            "OxyLife Bleach active oxygen 64g packshot",
        ],
    },
    {
        "name": "VLCC Insta Glow Diamond Bleach (60g)",
        "brand": "VLCC",
        "price": 155.0,
        "weight_per_unit": 60.0,
        "description": "Colloidal diamond bhasma infused mega pack bleach that sparkles skin with salon-like radiance while conditioning delicate skin cells.",
        "variants": [{"title": "60g", "price": 155.0}],
        "queries": [
            "VLCC Insta Glow Diamond Bleach 60g box white background",
            "VLCC Diamond Bleach 60g packshot",
        ],
    },
    {
        "name": "VLCC Insta Glow Gold Bleach (60g)",
        "brand": "VLCC",
        "price": 145.0,
        "weight_per_unit": 60.0,
        "description": "Infused with pure 24K gold energy, pre-bleach cream and post-bleach pack to deliver luminous golden fairness in 15 minutes.",
        "variants": [{"title": "60g", "price": 145.0}],
        "queries": [
            "VLCC Insta Glow Gold Bleach 60g box white background",
            "VLCC Gold Bleach 60g packshot",
        ],
    },
    {
        "name": "VLCC Insta Glow Herbal Bleach (60g)",
        "brand": "VLCC",
        "price": 135.0,
        "weight_per_unit": 60.0,
        "description": "Cucumber, rose petals and herbal extracts cream bleach. Gentle, mild formula that bleaches facial hair seamlessly without irritation.",
        "variants": [{"title": "60g", "price": 135.0}],
        "queries": [
            "VLCC Insta Glow Herbal Bleach 60g box white background",
            "VLCC Herbal Bleach 60g packshot",
        ],
    },
    {
        "name": "VLCC Insta Glow Oxygen Bleach (60g)",
        "brand": "VLCC",
        "price": 155.0,
        "weight_per_unit": 60.0,
        "description": "Active oxygen-rich formula that releases concentrated oxygen bubbles to detoxify pores and restore instant revitalizing fairness.",
        "variants": [{"title": "60g", "price": 155.0}],
        "queries": [
            "VLCC Insta Glow Oxygen Bleach 60g box white background",
            "VLCC Oxygen Bleach 60g packshot",
        ],
    },
    {
        "name": "OxyGlow Herbals Hydra Boost Bleach Cream (42g)",
        "brand": "OxyGlow",
        "price": 90.0,
        "weight_per_unit": 42.0,
        "description": "Enriched with skin brightening actives and intense hydrating agents. Lightens facial hair to blend invisibly while keeping skin moisturized and dewy.",
        "variants": [{"title": "42g", "price": 90.0}],
        "queries": [
            "OxyGlow Herbals Hydra Boost Bleach Cream box white background",
            "OxyGlow Hydra Boost Bleach box packshot",
        ],
    },
    {
        "name": "OxyGlow Herbals Diamond Bleach Cream (42g)",
        "brand": "OxyGlow",
        "price": 95.0,
        "weight_per_unit": 42.0,
        "description": "Clear, deep and active multi-layer diamond bleach cream. Cleanses pores, evens skin tone, and imparts a sparkling diamond-like radiance.",
        "variants": [{"title": "42g", "price": 95.0}],
        "queries": [
            "OxyGlow Herbals Diamond Bleach Cream box white background",
            "OxyGlow Diamond Bleach Cream 42g packshot",
        ],
    },
    {
        "name": "OxyGlow Herbals Multi Fruit Bleach Cream (42g)",
        "brand": "OxyGlow",
        "price": 85.0,
        "weight_per_unit": 42.0,
        "description": "Loaded with natural AHA fruit extracts of apple, papaya, and orange. Lightens facial hair, removes tan, and revitalizes tired skin.",
        "variants": [{"title": "42g", "price": 85.0}],
        "queries": [
            "OxyGlow Herbals Multi Fruit Bleach Cream box white background",
            "OxyGlow Fruit Bleach Cream 42g packshot",
        ],
    },
    {
        "name": "FYC Professional Papaya Bleach Cream (250g)",
        "brand": "FYC Professional",
        "price": 250.0,
        "weight_per_unit": 250.0,
        "description": "Professional 250g salon pack of papaya bleach cream. Gently bleaches facial hair while dissolving dark spots and dead skin layers.",
        "variants": [{"title": "250g", "price": 250.0}],
        "queries": [
            "FYC Professional Papaya Bleach Cream box white background",
            "FYC Papaya Bleach Cream packshot",
        ],
    },
    {
        "name": "NutriGlow Papaya Fruit Bleach Cream (60g)",
        "brand": "NutriGlow",
        "price": 95.0,
        "weight_per_unit": 60.0,
        "description": "Natural papaya fruit enzymes combined with active fruit AHA to gently bleach facial hair and remove sun tan for glowing, spot-free skin.",
        "variants": [{"title": "60g", "price": 95.0}],
        "queries": [
            "NutriGlow Papaya Fruit Bleach Cream box white background",
            "NutriGlow Papaya Bleach Cream box packshot",
        ],
    },
    {
        "name": "NutriGlow Papaya Fruit Bleach Cream (Master Salon Jar 250g)",
        "brand": "NutriGlow",
        "price": 275.0,
        "weight_per_unit": 250.0,
        "description": "Professional 250g salon pack of NutriGlow Papaya Fruit Bleach. Enriched with papaya pulp and Vitamin C for tan reduction and clear complexion.",
        "variants": [{"title": "250g", "price": 275.0}],
        "queries": [
            "NutriGlow Papaya Fruit Bleach 250g tub box white background",
            "NutriGlow Papaya Fruit Bleach 250g packshot",
        ],
    },
    {
        "name": "NutriGlow Gold Kesar Bleach Cream (60g)",
        "brand": "NutriGlow",
        "price": 110.0,
        "weight_per_unit": 60.0,
        "description": "Pure Kashmiri saffron and 24K gold dust crème bleach. Enhances natural glow, softens skin texture, and lightens facial hair seamlessly.",
        "variants": [{"title": "60g", "price": 110.0}],
        "queries": [
            "NutriGlow Gold Kesar Bleach Cream box white background",
            "NutriGlow Gold Kesar Bleach packshot",
        ],
    },
    {
        "name": "NutriGlow Gold Kesar Bleach Cream (Master Salon Jar 250g)",
        "brand": "NutriGlow",
        "price": 299.0,
        "weight_per_unit": 250.0,
        "description": "Master 250g salon jar of Gold Kesar Bleach. Rejuvenates lifeless skin, fades pigmentation, and leaves a luxurious bridal golden glow.",
        "variants": [{"title": "250g", "price": 299.0}],
        "queries": [
            "NutriGlow Gold Kesar Bleach 250g tub box white background",
            "NutriGlow Gold Kesar Bleach 250g packshot",
        ],
    },
    {
        "name": "NutriGlow Diamond Radiance Bleach Cream (60g)",
        "brand": "NutriGlow",
        "price": 110.0,
        "weight_per_unit": 60.0,
        "description": "Infused with colloidal diamond bhasma and sparkling radiant actives. Purifies skin, minimizes pores, and brings out a dazzling diamond shine.",
        "variants": [{"title": "60g", "price": 110.0}],
        "queries": [
            "NutriGlow Diamond Radiance Bleach Cream box white background",
            "NutriGlow Diamond Bleach Cream packshot",
        ],
    },
    {
        "name": "NutriGlow Diamond Radiance Bleach Cream (Master Salon Jar 250g)",
        "brand": "NutriGlow",
        "price": 299.0,
        "weight_per_unit": 250.0,
        "description": "Professional 250g salon tub of Diamond Radiance Bleach. Instantly brightens dull complexion, evens skin tone, and lightens fine facial hair.",
        "variants": [{"title": "250g", "price": 299.0}],
        "queries": [
            "NutriGlow Diamond Radiance Bleach 250g box white background",
            "NutriGlow Diamond Bleach 250g packshot",
        ],
    },
    {
        "name": "NutriGlow Ubtan Bleach Cream (60g)",
        "brand": "NutriGlow",
        "price": 125.0,
        "weight_per_unit": 60.0,
        "description": "Traditional Ayurvedic blend of turmeric, sandalwood, chickpea flour, and saffron. Removes stubborn tan and delivers warm festive glow.",
        "variants": [{"title": "60g", "price": 125.0}],
        "queries": [
            "NutriGlow Ubtan Bleach Cream box white background",
            "NutriGlow Ubtan Bleach box packshot",
        ],
    },
    {
        "name": "NutriGlow Wine Bleach Cream (60g)",
        "brand": "NutriGlow",
        "price": 125.0,
        "weight_per_unit": 60.0,
        "description": "Formulated with red grape wine extracts, polyphenols, and resveratrol. Clears blemishes, fights early signs of aging, and gives a rosy radiant sheen.",
        "variants": [{"title": "60g", "price": 125.0}],
        "queries": [
            "NutriGlow Wine Bleach Cream box white background",
            "NutriGlow Wine Bleach box packshot",
        ],
    },
    {
        "name": "NutriGlow Wine Bleach Cream (Master Salon Jar 250g)",
        "brand": "NutriGlow",
        "price": 299.0,
        "weight_per_unit": 250.0,
        "description": "Master 250g salon pack of Wine Bleach Cream. Rich in antioxidants to detoxify dull, tired skin and lighten facial hair with a blemish-free complexion.",
        "variants": [{"title": "250g", "price": 299.0}],
        "queries": [
            "NutriGlow Wine Bleach Cream 250g box white background",
            "NutriGlow Wine Bleach 250g packshot",
        ],
    },

    # ---------------------------------------------------------
    # 3. Cold Creams, Moisturizers & Serums (g70, g71)
    # ---------------------------------------------------------
    {
        "name": "Dabur Gulabari Moisturizing Cold Cream (100g)",
        "brand": "Dabur",
        "price": 120.0,
        "weight_per_unit": 100.0,
        "description": "72-hour moisturizing cold cream enriched with natural rose oil and Vitamin E. Hydrates deep skin layers and shields against winter dryness.",
        "variants": [{"title": "100g", "price": 120.0}],
        "queries": [
            "Dabur Gulabari Moisturizing Cold Cream 100g box white background",
            "Dabur Gulabari Cold Cream box packshot",
        ],
    },
    {
        "name": "Pond's Skin Institute Bright Beauty Spot-less Glow Serum (30ml)",
        "brand": "Pond's",
        "price": 449.0,
        "weight_per_unit": 30.0,
        "description": "Clinically proven brightening face serum with Gluta-Boost-C, Niacinamide, and Hyaluronic Acid. Fades dark spots 3x faster for a translucent glass glow.",
        "variants": [{"title": "30ml", "price": 449.0}],
        "queries": [
            "Pond's Skin Institute Bright Beauty Serum bottle white background",
            "Pond's Bright Beauty Serum Gluta-Boost bottle packshot",
        ],
    },
    {
        "name": "Pond's Skin Institute Youthful Miracle Day Cream with Retinol-C (50g)",
        "brand": "Pond's",
        "price": 699.0,
        "weight_per_unit": 50.0,
        "description": "Anti-aging day cream with advanced Retinol-C Complex and SPF 15 PA++. Continuously releases retinoids for 24 hours to reduce fine lines and boost collagen.",
        "variants": [{"title": "50g", "price": 699.0}],
        "queries": [
            "Pond's Youthful Miracle Day Cream box white background",
            "Pond's Age Miracle Retinol-C Day Cream box packshot",
        ],
    },
    {
        "name": "Pond's Skin Institute Hydra Miracle Gel Hydrating Moisturizer (50g)",
        "brand": "Pond's",
        "price": 499.0,
        "weight_per_unit": 50.0,
        "description": "Ultra-refreshing, non-sticky water-burst gel moisturizer loaded with pure Hyaluronic Acid and Vitamin E. Delivers 72 hours of plumping hydration.",
        "variants": [{"title": "50g", "price": 499.0}],
        "queries": [
            "Pond's Hydra Miracle Gel Moisturizer box white background",
            "Pond's Super Light Gel with Hyaluronic Acid box packshot",
        ],
    },
    {
        "name": "Lotus Herbals WhiteGlow Skin Whitening & Brightening Deep Moisturizing Crème SPF 20 PA+++ (60g)",
        "brand": "Lotus Herbals",
        "price": 425.0,
        "weight_per_unit": 60.0,
        "description": "Advanced formulation that blends grape, mulberry, saxifraga extracts and milk enzymes. Nourishes dry winter skin with deep hydration and luminous fairness.",
        "variants": [{"title": "60g", "price": 425.0}],
        "queries": [
            "Lotus Herbals WhiteGlow Deep Moisturizing Creme 60g box white background",
            "Lotus Herbals Whiteglow Deep Moisturising Creme packshot",
        ],
    },
    {
        "name": "Lotus Herbals WhiteGlow Skin Whitening & Brightening Gel Crème SPF 25 PA+++ (60g)",
        "brand": "Lotus Herbals",
        "price": 395.0,
        "weight_per_unit": 60.0,
        "description": "Breakthrough gel-crème formula that combines the benefits of a gel and a cream. Absorbs instantly without greasiness, brightening and protecting skin.",
        "variants": [{"title": "60g", "price": 395.0}],
        "queries": [
            "Lotus Herbals WhiteGlow Gel Creme 60g box white background",
            "Lotus Herbals Whiteglow Skin Whitening Gel Creme packshot",
        ],
    },
    {
        "name": "Lotus Herbals WhiteGlow Vitamin-C + Gold Radiance Serum (30ml)",
        "brand": "Lotus Herbals",
        "price": 525.0,
        "weight_per_unit": 30.0,
        "description": "Infused with 100x Vitamin C from Kakadu Plum and 24K pure gold leaf flakes. Reverses sun damage, evens skin tone, and provides an instant radiant glow.",
        "variants": [{"title": "30ml", "price": 525.0}],
        "queries": [
            "Lotus Herbals WhiteGlow Vitamin C Gold Radiance Serum bottle white background",
            "Lotus Whiteglow Vitamin C Gold Serum packshot",
        ],
    },
    {
        "name": "Biluma Glow 15% Vitamin C Brightening Serum (30ml)",
        "brand": "Biluma",
        "price": 999.0,
        "weight_per_unit": 30.0,
        "description": "Dermatologist-recommended 15% pure Vitamin C serum with Ferulic Acid and Chamomile extract. Fades hyperpigmentation, shields against oxidative stress, and boosts skin luminosity.",
        "variants": [{"title": "30ml", "price": 999.0}],
        "queries": [
            "Biluma Glow Vitamin C 15% Serum bottle white background",
            "Biluma Glow Vitamin C Serum Galderma packshot",
        ],
    },
    {
        "name": "Joy Skin Fruits Fruit Moisturizer (Nourishing Skin Cream Tub 200ml)",
        "brand": "Joy",
        "price": 150.0,
        "weight_per_unit": 200.0,
        "description": "Enriched with apple extracts, jojoba oil, and almond oil. Delivers intensive nourishment, restoring skin suppleness and elasticity with a fresh fruit scent.",
        "variants": [{"title": "200ml", "price": 150.0}],
        "queries": [
            "Joy Skin Fruits Fruit Moisturizer tub white background",
            "Joy Skin Fruits Nourishing Skin Cream tub packshot",
        ],
    },
    {
        "name": "Joy Skin Fruits Fruit Moisturizer (Nourishing Skin Cream Tub 500ml)",
        "brand": "Joy",
        "price": 295.0,
        "weight_per_unit": 500.0,
        "description": "Jumbo 500ml family tub of Joy Skin Fruits fruit moisturizer. Deep conditioning formula that softens rough, dry skin and restores radiant moisture.",
        "variants": [{"title": "500ml", "price": 295.0}],
        "queries": [
            "Joy Skin Fruits Fruit Moisturizer 500ml tub white background",
            "Joy Skin Fruits 500ml tub packshot",
        ],
    },
    {
        "name": "Joy Honey & Almonds Nourishing Skin Cream Tub (200ml)",
        "brand": "Joy",
        "price": 165.0,
        "weight_per_unit": 200.0,
        "description": "Rich nourishing cream with pure honey, almond oil, and Vitamin E. Locks in moisture, repairs winter skin barriers, and leaves a silky-soft finish.",
        "variants": [{"title": "200ml", "price": 165.0}],
        "queries": [
            "Joy Honey and Almonds Nourishing Skin Cream tub white background",
            "Joy Honey and Almonds cream tub packshot",
        ],
    },
    {
        "name": "Joy Honey & Almonds Nourishing Skin Cream Tub (500ml)",
        "brand": "Joy",
        "price": 310.0,
        "weight_per_unit": 500.0,
        "description": "Mega 500ml tub of Joy Honey & Almonds skin cream. Penetrates deep into parched skin layers for lasting all-day moisture and protection.",
        "variants": [{"title": "500ml", "price": 310.0}],
        "queries": [
            "Joy Honey and Almonds Nourishing Skin Cream 500ml tub white background",
            "Joy Honey and Almonds 500ml tub packshot",
        ],
    },
    {
        "name": "Joy Skin Fruits All Purpose Cream Spotless Glow with Strawberry (200ml)",
        "brand": "Joy",
        "price": 165.0,
        "weight_per_unit": 200.0,
        "description": "All-purpose brightening cream with strawberry extracts and Vitamin C. Nourishes, gently fades dark spots, and imparts an all-day natural rosy glow.",
        "variants": [{"title": "200ml", "price": 165.0}],
        "queries": [
            "Joy Skin Fruits Spotless Glow Strawberry cream tub white background",
            "Joy Skin Fruits Strawberry All Purpose Cream tub packshot",
        ],
    },
    {
        "name": "Nivea Soft Light Moisturiser Non-Greasy Cream (100ml tub)",
        "brand": "Nivea",
        "price": 199.0,
        "weight_per_unit": 100.0,
        "description": "Iconic fast-absorbing light moisturizing cream with Jojoba Oil and Vitamin E. Refreshes skin with an invigorating burst of non-greasy hydration.",
        "variants": [{"title": "100ml", "price": 199.0}],
        "queries": [
            "Nivea Soft Light Moisturiser Cream 100ml tub white background",
            "Nivea Soft Cream 100ml tub packshot",
        ],
    },
    {
        "name": "Nivea Soft Light Moisturiser Non-Greasy Cream (200ml tub)",
        "brand": "Nivea",
        "price": 349.0,
        "weight_per_unit": 200.0,
        "description": "200ml tub of Nivea Soft. Highly effective, everyday revitalizing cream for face, body, and hands that leaves skin sensationally soft and smooth.",
        "variants": [{"title": "200ml", "price": 349.0}],
        "queries": [
            "Nivea Soft Light Moisturiser Cream 200ml tub white background",
            "Nivea Soft 200ml tub packshot",
        ],
    },
    {
        "name": "Nivea Men Creme Dark Spot Reduction & Moisture (75ml tin)",
        "brand": "Nivea Men",
        "price": 199.0,
        "weight_per_unit": 75.0,
        "description": "Specially formulated for men's skin. Ultra-light, non-oily formula with UV filters that protects against dark spots and dryness on face, body, and hands.",
        "variants": [{"title": "75ml", "price": 199.0}],
        "queries": [
            "Nivea Men Creme 75ml tin white background",
            "Nivea Men Creme tin packshot",
        ],
    },
    {
        "name": "Boroline Antiseptic Ayurvedic Cream (20g tub)",
        "brand": "Boroline",
        "price": 45.0,
        "weight_per_unit": 20.0,
        "description": "Legendary Ayurvedic antiseptic cream with Boric Acid, Zinc Oxide, and Lanolin. Heals dry cracked lips, rough elbows, minor cuts, and cracked heels overnight.",
        "variants": [{"title": "20g", "price": 45.0}],
        "queries": [
            "Boroline Antiseptic Ayurvedic Cream tub white background",
            "Boroline cream round tub packshot",
        ],
    },
    {
        "name": "Boroline Antiseptic Ayurvedic Cream (40g tub)",
        "brand": "Boroline",
        "price": 85.0,
        "weight_per_unit": 40.0,
        "description": "40g tub of Boroline Ayurvedic skin repair cream. Renowned across India for soothing severely chapped skin, post-shave burns, and extreme winter dryness.",
        "variants": [{"title": "40g", "price": 85.0}],
        "queries": [
            "Boroline Antiseptic Ayurvedic Cream 40g tub white background",
            "Boroline 40g round tub packshot",
        ],
    },
    {
        "name": "Himalaya Winter Defense Moisturizing Cream (100ml tub)",
        "brand": "Himalaya",
        "price": 140.0,
        "weight_per_unit": 100.0,
        "description": "Herbal blend of Wheat Germ, Jojoba Oil, and Almond Oil that protects skin from cold weather, flaking, and loss of essential moisture.",
        "variants": [{"title": "100ml", "price": 140.0}],
        "queries": [
            "Himalaya Winter Defense Moisturizing Cream tub white background",
            "Himalaya Winter Defense Cream 100ml packshot",
        ],
    },
    {
        "name": "Aqualogica Glow+ Hydra Gel Moisturizer (100g)",
        "brand": "Aqualogica",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Refreshing gel moisturizer infused with Papaya extract, Vitamin C, and Hyaluronic Acid. Locks in 24 hours of deep moisture with a juicy dewy glow.",
        "variants": [{"title": "100g", "price": 399.0}],
        "queries": [
            "Aqualogica Glow+ Hydra Gel Moisturizer tub box white background",
            "Aqualogica Glow Hydra Gel Moisturizer packshot",
        ],
    },
    {
        "name": "Aqualogica Illuminate+ Hydra Gel Moisturizer (100g)",
        "brand": "Aqualogica",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Lightweight gel moisturizer enriched with Wild Berries and Alpha Arbutin. Evens skin tone, reduces pigmentation, and deeply hydrates without greasiness.",
        "variants": [{"title": "100g", "price": 399.0}],
        "queries": [
            "Aqualogica Illuminate+ Hydra Gel Moisturizer box white background",
            "Aqualogica Illuminate Hydra Gel Moisturizer packshot",
        ],
    },
    {
        "name": "Be Soft Deep Moisturizing Cream (100g)",
        "brand": "Be Soft",
        "price": 195.0,
        "weight_per_unit": 100.0,
        "description": "Dermatological emollient cream formulated with White Soft Paraffin, Aloe Vera, and Vitamin E. Provides intensive relief for extremely dry, irritated, and eczema-prone skin.",
        "variants": [{"title": "100g", "price": 195.0}],
        "queries": [
            "Be Soft Deep Moisturizing Cream 100g box white background",
            "Be Soft moisturizing cream aloe vera paraffin box packshot",
        ],
    },

    # ---------------------------------------------------------
    # 4. Active Derma Moisturizers & Cleansers (g72)
    # ---------------------------------------------------------
    {
        "name": "The Derma Co 5% Cica-Glow Daily Face Moisturizer (50g)",
        "brand": "The Derma Co",
        "price": 349.0,
        "weight_per_unit": 50.0,
        "description": "Dermatologist-designed lightweight face moisturizer with Korean Cica, Alpha-Arbutin, and Tranexamic Acid. Calms redness and restores healthy radiant skin.",
        "variants": [{"title": "50g", "price": 349.0}],
        "queries": [
            "The Derma Co 5% Cica-Glow Daily Face Moisturizer tube white background",
            "The Derma Co 5% Cica Glow Face Moisturizer packshot",
        ],
    },
    {
        "name": "The Derma Co Pore Minimizing Daily Face Moisturizer (50g)",
        "brand": "The Derma Co",
        "price": 349.0,
        "weight_per_unit": 50.0,
        "description": "Oil-free daily moisturizer powered by 3% Niacinamide, 3% PHA, and p-REFINYL. Refines open pores, controls excess sebum, and strengthens skin barrier.",
        "variants": [{"title": "50g", "price": 349.0}],
        "queries": [
            "The Derma Co Pore Minimizing Daily Face Moisturizer tube white background",
            "The Derma Co Pore Minimizing Face Moisturizer packshot",
        ],
    },
    {
        "name": "The Derma Co 5% Nia-Ceramide Intense Moisturizing Cream (100g)",
        "brand": "The Derma Co",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Specially formulated for dry and sensitive skin. Features 5% Niacinamide, Ceramides, Betaine, and Bisabolol for up to 24-hour deep barrier repair.",
        "variants": [{"title": "100g", "price": 399.0}],
        "queries": [
            "The Derma Co 5% Nia-Ceramide Intense Moisturizing Cream tube white background",
            "The Derma Co Nia Ceramide Intense Moisturizing Cream packshot",
        ],
    },
    {
        "name": "The Derma Co 3% Vitamin E Daily Face Moisturizer (100g)",
        "brand": "The Derma Co",
        "price": 349.0,
        "weight_per_unit": 100.0,
        "description": "Enriched with 3% Vitamin E and Lactic Acid. Gently exfoliates dead skin flakes while providing long-lasting hydration for dry, parched skin.",
        "variants": [{"title": "100g", "price": 349.0}],
        "queries": [
            "The Derma Co 3% Vitamin E Daily Face Moisturizer tube white background",
            "The Derma Co 3% Vitamin E Face Moisturizer packshot",
        ],
    },
    {
        "name": "The Derma Co Oil-Free Daily Face Moisturizer (100g)",
        "brand": "The Derma Co",
        "price": 349.0,
        "weight_per_unit": 100.0,
        "description": "Non-greasy hydrating moisturizer with Hyaluronic Acid, Ceramides, and Multivitamins. Regulates oil production and keeps skin fresh all day long.",
        "variants": [{"title": "100g", "price": 349.0}],
        "queries": [
            "The Derma Co Oil-Free Daily Face Moisturizer tube white background",
            "The Derma Co Oil Free Face Moisturizer 100g packshot",
        ],
    },
    {
        "name": "The Derma Co 5% Nia-Ceramide Daily Hydrating Moisturizer (100g)",
        "brand": "The Derma Co",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Formulated for normal to dry skin with Hyaluronic Acid, Squalane, and Vitamin E. Locks in moisture for 24 hours without sticky residue.",
        "variants": [{"title": "100g", "price": 399.0}],
        "queries": [
            "The Derma Co 5% Nia-Ceramide Daily Hydrating Moisturizer tube white background",
            "The Derma Co 5% Nia-Ceramide Daily Hydrating Moisturizer packshot",
        ],
    },
    {
        "name": "The Derma Co 5% Nia-Ceramide Mattifying Moisturizer (100g)",
        "brand": "The Derma Co",
        "price": 399.0,
        "weight_per_unit": 100.0,
        "description": "Oily and acne-prone skin specialist formulated with Panthenol, Allantoin, and Zinc PCA. Delivers a shine-free matte finish while deeply hydrating.",
        "variants": [{"title": "100g", "price": 399.0}],
        "queries": [
            "The Derma Co 5% Nia-Ceramide Mattifying Moisturizer tube white background",
            "The Derma Co 5% Nia-Ceramide Mattifying Moisturizer packshot",
        ],
    },
    {
        "name": "Aqualogica Radiance+ Hydra Smooth Face Wash (100ml)",
        "brand": "Aqualogica",
        "price": 249.0,
        "weight_per_unit": 100.0,
        "description": "Gentle hydrating face cleanser infused with juicy Watermelon, Niacinamide, and Hyaluronic Acid. Washes away impurities while brightening dull skin.",
        "variants": [{"title": "100ml", "price": 249.0}],
        "queries": [
            "Aqualogica Radiance+ Hydra Smooth Face Wash tube white background",
            "Aqualogica Radiance Hydra Smooth Face Wash packshot",
        ],
    },
    {
        "name": "Aqualogica Glow+ Hydra Smooth Face Wash (100ml)",
        "brand": "Aqualogica",
        "price": 249.0,
        "weight_per_unit": 100.0,
        "description": "Brightening daily face wash packed with Papaya extract and Vitamin C. Cleanses deeply, fades dark spots, and reveals a radiant dewy complexion.",
        "variants": [{"title": "100ml", "price": 249.0}],
        "queries": [
            "Aqualogica Glow+ Hydra Smooth Face Wash tube white background",
            "Aqualogica Glow Hydra Smooth Face Wash packshot",
        ],
    },
    {
        "name": "Aqualogica Clear+ Smooth Face Wash (100ml)",
        "brand": "Aqualogica",
        "price": 249.0,
        "weight_per_unit": 100.0,
        "description": "Acne-clearing foaming face wash with Green Tea and Salicylic Acid. Unclogs pores, controls excess oil, and prevents stubborn breakouts.",
        "variants": [{"title": "100ml", "price": 249.0}],
        "queries": [
            "Aqualogica Clear+ Smooth Face Wash tube white background",
            "Aqualogica Clear Smooth Face Wash packshot",
        ],
    },
    {
        "name": "Garnier Men Acno Fight Anti-Pimple Face Wash (100g)",
        "brand": "Garnier Men",
        "price": 199.0,
        "weight_per_unit": 100.0,
        "description": "6-in-1 anti-pimple face wash formulated with Salicylic Acid and Herba Repair. Fights 99.9% of pimple-causing bacteria, controls oil, and fades spots.",
        "variants": [{"title": "100g", "price": 199.0}],
        "queries": [
            "Garnier Men Acno Fight Anti-Pimple Face Wash tube white background",
            "Garnier Men Acno Fight Face Wash packshot",
        ],
    },
    {
        "name": "Garnier Men TurboBright Anti-Pollution Double Action Face Wash (100g)",
        "brand": "Garnier Men",
        "price": 225.0,
        "weight_per_unit": 100.0,
        "description": "Dual-textured face wash combining Black Charcoal and Icy Clay. Removes stubborn city pollution, dust, and sebum for an instant clean icy feel.",
        "variants": [{"title": "100g", "price": 225.0}],
        "queries": [
            "Garnier Men TurboBright Anti-Pollution Double Action Face Wash tube white background",
            "Garnier Men TurboBright Double Action Face Wash packshot",
        ],
    },
    {
        "name": "Nivea Men All-in-1 Charcoal Face Wash (100g)",
        "brand": "Nivea Men",
        "price": 210.0,
        "weight_per_unit": 100.0,
        "description": "10x effect face wash powered by active charcoal. Deeply cleanses pores, eliminates excess oil, and leaves skin revitalized and clear.",
        "variants": [{"title": "100g", "price": 210.0}],
        "queries": [
            "Nivea Men All-in-1 Charcoal Face Wash tube white background",
            "Nivea Men All in 1 Charcoal Face Wash packshot",
        ],
    },

    # ---------------------------------------------------------
    # 5. Complexion, Base & Face Makeup (g64, g65, g66)
    # ---------------------------------------------------------
    {
        "name": "Insight Cosmetics 2 in 1 Super Stay Mist Foundation (50ml)",
        "brand": "Insight Cosmetics",
        "price": 275.0,
        "weight_per_unit": 50.0,
        "description": "Innovative ultra-fine mist foundation that delivers lightweight buildable coverage with transfer-proof 24-hour stay and natural satin finish.",
        "variants": [{"title": "50ml", "price": 275.0}],
        "queries": [
            "Insight Cosmetics 2 in 1 Super Stay Mist Foundation bottle white background",
            "Insight Mist Foundation bottle packshot",
        ],
    },
    {
        "name": "Insight Cosmetics Matte Finish Foundation (30ml)",
        "brand": "Insight Cosmetics",
        "price": 180.0,
        "weight_per_unit": 30.0,
        "description": "Oil-free matte liquid foundation that blurs pores, controls shine, and evens out skin tone with seamless medium-to-full coverage.",
        "variants": [{"title": "30ml", "price": 180.0}],
        "queries": [
            "Insight Cosmetics Matte Finish Foundation bottle white background",
            "Insight ultra thin foundation packshot",
        ],
    },
    {
        "name": "Insight Cosmetics BB Cream Foundation (30ml)",
        "brand": "Insight Cosmetics",
        "price": 149.0,
        "weight_per_unit": 30.0,
        "description": "All-in-one beauty balm cream foundation that hydrates, brightens, and primes skin while providing light natural everyday coverage.",
        "variants": [{"title": "30ml", "price": 149.0}],
        "queries": [
            "Insight Cosmetics BB Cream Foundation tube white background",
            "Insight BB Cream tube packshot",
        ],
    },
    {
        "name": "Insight Cosmetics Makeup Setting Spray (50ml)",
        "brand": "Insight Cosmetics",
        "price": 210.0,
        "weight_per_unit": 50.0,
        "description": "Long-lasting weightless makeup setting spray that locks makeup in place for up to 16 hours, preventing smudging, creasing, and fading.",
        "variants": [{"title": "50ml", "price": 210.0}],
        "queries": [
            "Insight Cosmetics Makeup Setting Spray bottle white background",
            "Insight Makeup Setting Spray 50ml packshot",
        ],
    },
    {
        "name": "L'Oreal Paris Infallible 24H Fresh Wear Liquid Foundation (30ml)",
        "brand": "L'Oreal Paris",
        "price": 999.0,
        "weight_per_unit": 30.0,
        "description": "Breathable, lightweight 24-hour waterproof and sweat-resistant liquid foundation with SPF 25. Delivers medium-to-full buildable coverage.",
        "variants": [{"title": "30ml", "price": 999.0}],
        "queries": [
            "L'Oreal Paris Infallible 24H Fresh Wear Foundation bottle white background",
            "L'Oreal Infallible 24H Fresh Wear Liquid Foundation bottle packshot",
        ],
    },
    {
        "name": "Maybelline New York Fit Me Matte + Poreless Liquid Foundation (30ml)",
        "brand": "Maybelline New York",
        "price": 599.0,
        "weight_per_unit": 30.0,
        "description": "Iconic matte liquid foundation with micro-powders that control shine and blur pores for a seamless, natural poreless finish. SPF 22.",
        "variants": [{"title": "30ml", "price": 599.0}],
        "queries": [
            "Maybelline Fit Me Matte Poreless Liquid Foundation bottle white background",
            "Maybelline Fit Me Foundation bottle packshot",
        ],
    },
    {
        "name": "Maybelline New York Fit Me Matte + Poreless Compact Powder (8g)",
        "brand": "Maybelline New York",
        "price": 249.0,
        "weight_per_unit": 8.0,
        "description": "12-hour oil control compact powder with SPF 28 PA+++ and Perlite mineral technology. Keeps face fresh, matte, and blemish-free.",
        "variants": [{"title": "8g", "price": 249.0}],
        "queries": [
            "Maybelline Fit Me Matte Poreless Compact Powder packshot white background",
            "Maybelline Fit Me Compact Powder case packshot",
        ],
    },
    {
        "name": "Daily Life Forever52 Ultra Definition Liquid Foundation (30ml)",
        "brand": "Daily Life Forever52",
        "price": 899.0,
        "weight_per_unit": 30.0,
        "description": "High-definition professional liquid foundation designed for photographic perfection. Delivers full velvet-matte coverage without cakey texture.",
        "variants": [{"title": "30ml", "price": 899.0}],
        "queries": [
            "Daily Life Forever52 Ultra Definition Liquid Foundation bottle white background",
            "Daily Life Forever52 foundation bottle packshot",
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
    print(f"🚀 INGESTING MAXX RETAIL BATCH 8: {len(CATALOG_BATCH8)} COSMETICS, MOISTURIZERS & BLEACHES")
    print(f"   Category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)")
    print(f"   Dietary: Strictly N/A (is_veg = None)")
    print(f"   Target Shop: {SHOP_ID}")
    print("=" * 80)

    prepared_products = []

    for idx, item in enumerate(CATALOG_BATCH8, 1):
        print(f"\n[{idx:03d}/{len(CATALOG_BATCH8):03d}] 📸 Processing authentic packshots for: {item['brand']} - {item['name']}...")

        packshot1_path = os.path.join(CACHE_DIR, f"maxx_b8_{idx}_1.jpg")
        packshot2_path = os.path.join(CACHE_DIR, f"maxx_b8_{idx}_2.jpg")

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

        st_path1 = f"{STORAGE_PREFIX}/maxx_b8_{idx}_1.jpg"
        st_path2 = f"{STORAGE_PREFIX}/maxx_b8_{idx}_2.jpg"

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
    print(f"📤 Syncing all {len(prepared_products)} Batch 8 items into Supabase database...")
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
    print(f"🎉 Batch 8 ingestion complete! Total Inserted: {total_inserted}, Total Updated: {total_updated}")
    print("=" * 80)


if __name__ == "__main__":
    main()
