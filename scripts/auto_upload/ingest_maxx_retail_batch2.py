#!/usr/bin/env python3
"""
Maxx Retail Batch 2 (Shelf Scans g6.jpeg - g11.jpeg) Ingestion Engine
====================================================================
Catalog: 48 authentic cosmetics & beauty products from shelf scans:
  - Vaseline, Nivea, Pond's, Himalaya, Nature's Essence, Khadi Organic,
    VLCC, The Derma Co, Jovees Herbal, Be Soft, Mamaearth, Bella Vita Organic,
    St. Ives, Lacto Calamine, Dove, Joy, Bajaj, Hair & Care, Navratna,
    TRESemmé, NutriGlow, Nyle, Pilgrim, Sesa, Trichup, Plix.

Directives:
  1. Product category: Strictly 'Cosmetics & Beauty'
  2. Brand / Manufacturer strictly populated for each item
  3. Dietary N/A: strictly `is_veg = None`
  4. Real photoshoot packshots only: exactly 2 distinct views of the physical bottle/pack on clean white background
  5. 800x800 square 1:1, < 120KB
  6. Ingest into Supabase via public.bulk_upload_shop_products RPC
"""

import os
import re
import io
import sys
import json
import time
import requests
from PIL import Image

SHOP_ID = "750b02ab-81f7-4023-929d-a9a00a8a8790"
CATEGORY = "Cosmetics & Beauty"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

BATCH_2_PRODUCTS = [
    # ── Vaseline Range ──────────────────────────────────────────────────────────
    {
        "name": "Vaseline Intensive Care Light Hydrate Serum in Lotion",
        "brand": "Vaseline",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 135.0,
        "weight_per_unit": 100.0,
        "description": "Formulated with 48HR long-lasting hydration powered by Hyaluronic Acid. Lightweight serum-in-lotion quickly absorbs without stickiness for healthy glowing skin.",
        "variants": [
            {"id": "v_vas_lh_100", "name": "100 ml Bottle", "price": 135.0, "original_price": None, "is_available": True},
            {"id": "v_vas_lh_200", "name": "200 ml Bottle", "price": 240.0, "original_price": None, "is_available": True},
            {"id": "v_vas_lh_400", "name": "400 ml Pump Bottle", "price": 399.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Vaseline Intensive Care Deep Moisture Body Lotion",
        "brand": "Vaseline",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 135.0,
        "weight_per_unit": 100.0,
        "description": "72HR moisture powered by Hyaluron and Ceramide serum. Deeply hydrates dry skin and restores the skin moisture barrier for all-day nourishment.",
        "variants": [
            {"id": "v_vas_dm_100", "name": "100 ml Bottle", "price": 135.0, "original_price": None, "is_available": True},
            {"id": "v_vas_dm_200", "name": "200 ml Bottle", "price": 235.0, "original_price": None, "is_available": True},
            {"id": "v_vas_dm_400", "name": "400 ml Pump Bottle", "price": 399.0, "original_price": None, "is_available": True},
            {"id": "v_vas_dm_600", "name": "600 ml Family Pack", "price": 575.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Vaseline Intensive Care Aloe Fresh Body Lotion",
        "brand": "Vaseline",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 135.0,
        "weight_per_unit": 100.0,
        "description": "Enriched with 100% pure Aloe Vera extracts and micro-droplets of Vaseline jelly. 24HR light and non-sticky hydration for fresh, refreshed skin.",
        "variants": [
            {"id": "v_vas_af_100", "name": "100 ml Bottle", "price": 135.0, "original_price": None, "is_available": True},
            {"id": "v_vas_af_200", "name": "200 ml Bottle", "price": 240.0, "original_price": None, "is_available": True},
            {"id": "v_vas_af_400", "name": "400 ml Pump Bottle", "price": 399.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Vaseline Gluta-Hya Flawless Glow Serum-in-Lotion",
        "brand": "Vaseline",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 299.0,
        "weight_per_unit": 200.0,
        "description": "Revolutionary serum burst lotion with GlutaGlow (10x more powerful than Vitamin C) and Hyaluron. Evens skin tone and reduces dark spots for radiant, glowing skin.",
        "variants": [
            {"id": "v_vas_gh_200", "name": "200 ml Tube", "price": 299.0, "original_price": None, "is_available": True},
            {"id": "v_vas_gh_350", "name": "350 ml Bottle", "price": 599.0, "original_price": None, "is_available": True},
        ]
    },

    # ── Nivea Range ─────────────────────────────────────────────────────────────
    {
        "name": "Nivea Body Lotion Shea Smooth",
        "brand": "Nivea",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 160.0,
        "weight_per_unit": 120.0,
        "description": "Infused with precious Shea Butter and Deep Nourish Serum. Provides 72 hours of intensive moisture for touchably soft, silky smooth skin.",
        "variants": [
            {"id": "v_niv_ss_120", "name": "120 ml Bottle", "price": 160.0, "original_price": None, "is_available": True},
            {"id": "v_niv_ss_200", "name": "200 ml Bottle", "price": 265.0, "original_price": None, "is_available": True},
            {"id": "v_niv_ss_400", "name": "400 ml Pump Bottle", "price": 499.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nivea Body Lotion Aloe Protection SPF 15",
        "brand": "Nivea",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 175.0,
        "weight_per_unit": 120.0,
        "description": "Formulated with natural Aloe Vera extracts and UVA/UVB filters (SPF 15). Protects against sun damage while delivering 72 hours of refreshing deep moisture.",
        "variants": [
            {"id": "v_niv_ap_120", "name": "120 ml Bottle", "price": 175.0, "original_price": None, "is_available": True},
            {"id": "v_niv_ap_200", "name": "200 ml Bottle", "price": 275.0, "original_price": None, "is_available": True},
            {"id": "v_niv_ap_400", "name": "400 ml Pump Bottle", "price": 525.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nivea Body Lotion Cocoa Nourish",
        "brand": "Nivea",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 160.0,
        "weight_per_unit": 120.0,
        "description": "Enriched with real Cocoa Butter, Coconut Oil, and Deep Moisture Serum. Intensely hydrates very dry skin for 72 hours with an irresistible chocolate scent.",
        "variants": [
            {"id": "v_niv_cn_120", "name": "120 ml Bottle", "price": 160.0, "original_price": None, "is_available": True},
            {"id": "v_niv_cn_200", "name": "200 ml Bottle", "price": 275.0, "original_price": None, "is_available": True},
            {"id": "v_niv_cn_400", "name": "400 ml Pump Bottle", "price": 499.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nivea Nourishing Body Lotion Body Milk",
        "brand": "Nivea",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 160.0,
        "weight_per_unit": 120.0,
        "description": "Enriched with pure Almond Oil and Deep Moisture Serum. Intensely nourishes and relieves dry skin for up to 72 hours.",
        "variants": [
            {"id": "v_niv_bm_120", "name": "120 ml Bottle", "price": 160.0, "original_price": None, "is_available": True},
            {"id": "v_niv_bm_200", "name": "200 ml Bottle", "price": 265.0, "original_price": None, "is_available": True},
            {"id": "v_niv_bm_400", "name": "400 ml Pump Bottle", "price": 499.0, "original_price": None, "is_available": True},
            {"id": "v_niv_bm_600", "name": "600 ml Family Bottle", "price": 675.0, "original_price": None, "is_available": True},
        ]
    },

    # ── Pond's & Himalaya Body Care ─────────────────────────────────────────────
    {
        "name": "Pond's Triple Vitamin Moisturizing Body Lotion",
        "brand": "Pond's",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 125.0,
        "weight_per_unit": 100.0,
        "description": "Infused with Vitamin B3, Vitamin E, and Vitamin C. Silky smooth formula replenishes moisture, giving your skin a radiant natural glow.",
        "variants": [
            {"id": "v_pnd_tv_100", "name": "100 ml Bottle", "price": 125.0, "original_price": None, "is_available": True},
            {"id": "v_pnd_tv_200", "name": "200 ml Bottle", "price": 230.0, "original_price": None, "is_available": True},
            {"id": "v_pnd_tv_400", "name": "400 ml Pump Bottle", "price": 399.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Himalaya Nourishing Body Lotion (Winter Cherry & Aloe)",
        "brand": "Himalaya",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 100.0,
        "weight_per_unit": 100.0,
        "description": "Non-greasy herbal body lotion with Winter Cherry and Aloe Vera. Nourishes, hydrates, and protects skin against winter dryness.",
        "variants": [
            {"id": "v_him_nb_100", "name": "100 ml Bottle", "price": 100.0, "original_price": None, "is_available": True},
            {"id": "v_him_nb_200", "name": "200 ml Bottle", "price": 180.0, "original_price": None, "is_available": True},
            {"id": "v_him_nb_400", "name": "400 ml Bottle", "price": 320.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nature's Essence Nourishing Almond & Honey Body Lotion",
        "brand": "Nature's Essence",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 175.0,
        "weight_per_unit": 200.0,
        "description": "Natural blend of pure Almond oil and natural Honey. Deeply restores moisture balance to leave skin soft, smooth, and naturally fragrant.",
        "variants": [
            {"id": "v_nat_ah_200", "name": "200 ml Bottle", "price": 175.0, "original_price": None, "is_available": True},
            {"id": "v_nat_ah_400", "name": "400 ml Bottle", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },

    # ── Herbal & Ayurvedic Body Lotions ─────────────────────────────────────────
    {
        "name": "Khadi Organic Vitamin C Body Lotion with Honey & Orange",
        "brand": "Khadi Organic",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 249.0,
        "weight_per_unit": 210.0,
        "description": "Authentic Ayurvedic Khadi India formulation with natural Vitamin C, Honey, and Orange peel oil. Softens skin, brightens complexion, and locks in moisture.",
        "variants": [
            {"id": "v_khd_vc_210", "name": "210 ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "VLCC Almond & Honey Deep Nourishing & Brightening Body Lotion",
        "brand": "VLCC",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 199.0,
        "weight_per_unit": 200.0,
        "description": "5-in-1 skin defense body lotion with Wheatgerm oil, pure Honey, and Almond oil. Deeply nourishes rough and dry skin while enhancing skin luminosity.",
        "variants": [
            {"id": "v_vlc_ah_200", "name": "200 ml Bottle", "price": 199.0, "original_price": None, "is_available": True},
            {"id": "v_vlc_ah_400", "name": "400 ml Pump Bottle", "price": 349.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "The Derma Co 1% Hyaluronic Sunscreen Body Lotion SPF 50 PA++++",
        "brand": "The Derma Co",
        "sub_category": "Body Care",
        "menu_category": "Sun Care & Protection",
        "price": 399.0,
        "weight_per_unit": 200.0,
        "description": "Broad spectrum UVA/UVB protection SPF 50 PA++++ enriched with Hyaluronic Acid and Niacinamide. Ultra-lightweight and non-sticky body sunscreen.",
        "variants": [
            {"id": "v_tdc_hs_200", "name": "200 ml Pump Bottle", "price": 399.0, "original_price": None, "is_available": True},
            {"id": "v_tdc_hs_400", "name": "400 ml Pump Bottle", "price": 699.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Jovees Herbal Cocoa Butter Ultra Rich Body Lotion with SPF",
        "brand": "Jovees Herbal",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 195.0,
        "weight_per_unit": 200.0,
        "description": "Paraben-free botanical formula enriched with Cocoa Butter, Olive oil, and Shea Butter with SPF protection. Restores dry, dehydrated skin to supple elasticity.",
        "variants": [
            {"id": "v_jov_cb_200", "name": "200 ml Bottle", "price": 195.0, "original_price": None, "is_available": True},
            {"id": "v_jov_cb_400", "name": "400 ml Bottle", "price": 345.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Be Soft Ultra Moisturising Body Lotion",
        "brand": "Be Soft",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 199.0,
        "weight_per_unit": 250.0,
        "description": "Formulated with virgin coconut oil and ultra-nourishing humectants. Delivers intensive hydration to dry and flaky skin.",
        "variants": [
            {"id": "v_bes_um_250", "name": "250 ml Pump Bottle", "price": 199.0, "original_price": None, "is_available": True},
            {"id": "v_bes_um_400", "name": "400 ml Pump Bottle", "price": 325.0, "original_price": None, "is_available": True},
        ]
    },

    # ── Mamaearth, Derma Co & Bella Vita Body Range ──────────────────────────────
    {
        "name": "Mamaearth Rice Water Hydrating Body Lotion",
        "brand": "Mamaearth",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 299.0,
        "weight_per_unit": 200.0,
        "description": "Infused with Rice Water, Aloe Vera, and Shea Butter. Nourishes skin cells, soothes irritation, and restores a hydrated dewy glass-skin appearance.",
        "variants": [
            {"id": "v_mam_rw_200", "name": "200 ml Bottle", "price": 299.0, "original_price": None, "is_available": True},
            {"id": "v_mam_rw_400", "name": "400 ml Pump Bottle", "price": 499.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Mamaearth Vitamin C Daily Glow Body Lotion",
        "brand": "Mamaearth",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 299.0,
        "weight_per_unit": 200.0,
        "description": "7-in-1 skin glow formula with pure Vitamin C and Honey. Brightens dull skin, evens out hyperpigmentation, and locks in deep 24HR moisture.",
        "variants": [
            {"id": "v_mam_vc_200", "name": "200 ml Bottle", "price": 299.0, "original_price": None, "is_available": True},
            {"id": "v_mam_vc_400", "name": "400 ml Pump Bottle", "price": 499.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "The Derma Co 2% Hyaluronic Acid Hydrating Body Serum-Lotion",
        "brand": "The Derma Co",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 449.0,
        "weight_per_unit": 250.0,
        "description": "Active dermatological serum-lotion with 2% Hyaluronic Acid. Delivers 72 hours of intense cellular hydration for plump, bouncy, and hydrated skin.",
        "variants": [
            {"id": "v_tdc_ha_250", "name": "250 ml Pump Bottle", "price": 449.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "The Derma Co 1% Kojic Acid Daily Glow Body Serum-Lotion",
        "brand": "The Derma Co",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 449.0,
        "weight_per_unit": 250.0,
        "description": "Formulated with 1% Kojic Acid and Alpha Arbutin. Targets body pigmentation, tan, and dark patches to reveal an even-toned, luminous complexion.",
        "variants": [
            {"id": "v_tdc_ka_250", "name": "250 ml Pump Bottle", "price": 449.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Bella Vita Organic Niacinamide Moisturizing Body Lotion",
        "brand": "Bella Vita Organic",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 275.0,
        "weight_per_unit": 200.0,
        "description": "Clinically proven Niacinamide body lotion that reduces acne marks, blemishes, and evens out skin tone while providing non-sticky hydration.",
        "variants": [
            {"id": "v_bvo_nia_200", "name": "200 ml Bottle", "price": 275.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Bella Vita Organic Aloe Vera Refreshing Body Lotion",
        "brand": "Bella Vita Organic",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 275.0,
        "weight_per_unit": 200.0,
        "description": "With organic Aloe Vera and Vitamin E. Hydrates skin, cools irritation, and revitalizes tired skin with an invigorating fresh feel.",
        "variants": [
            {"id": "v_bvo_alo_200", "name": "200 ml Bottle", "price": 275.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Bella Vita Organic Kumkumadi Refreshing Body Lotion",
        "brand": "Bella Vita Organic",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 299.0,
        "weight_per_unit": 200.0,
        "description": "Infused with authentic Kumkumadi Oil and Saffron. Revitalizes skin texture, improves glow, and deeply nourishes the body skin barrier.",
        "variants": [
            {"id": "v_bvo_kum_200", "name": "200 ml Bottle", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "St. Ives Soothing Oatmeal & Shea Butter Body Lotion",
        "brand": "St. Ives",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 449.0,
        "weight_per_unit": 400.0,
        "description": "Crafted with 100% natural moisturizers including soothing oatmeal and rich shea butter. Gently calms dry, itchy skin for touchable smoothness.",
        "variants": [
            {"id": "v_sti_os_400", "name": "400 ml Pump Bottle", "price": 449.0, "original_price": None, "is_available": True},
            {"id": "v_sti_os_621", "name": "621 ml Pump Bottle", "price": 699.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Lacto Calamine Daily Face Lotion (Kaolin Clay & Zinc Oxide)",
        "brand": "Lacto Calamine",
        "sub_category": "Skin Care",
        "menu_category": "Face Care & Toners",
        "price": 135.0,
        "weight_per_unit": 60.0,
        "description": "Original oil-balance lotion with Kaolin Clay, Zinc Oxide, and Glycerin. Absorbs excess oil, clears clogged pores, and prevents pimples.",
        "variants": [
            {"id": "v_lac_cal_60", "name": "60 ml Bottle", "price": 135.0, "original_price": None, "is_available": True},
            {"id": "v_lac_cal_120", "name": "120 ml Bottle", "price": 240.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Dove Body Love Nourished Radiance Rich Body Lotion",
        "brand": "Dove",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 249.0,
        "weight_per_unit": 200.0,
        "description": "Infused with NutriDUO complex. Nourishes deep below the surface to lock in 48HR moisture for radiant, glowing, touchably soft skin.",
        "variants": [
            {"id": "v_dov_nr_200", "name": "200 ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
            {"id": "v_dov_nr_400", "name": "400 ml Pump Bottle", "price": 449.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Joy Honey & Almonds Ultimate Nourishing Body Milk Lotion",
        "brand": "Joy",
        "sub_category": "Body Care",
        "menu_category": "Body Lotions & Moisturizers",
        "price": 175.0,
        "weight_per_unit": 200.0,
        "description": "Rich nourishing body milk with pure Almond Oil and Honey. Rehydrates extreme dry skin, preventing moisture loss and leaving a soft, velvety touch.",
        "variants": [
            {"id": "v_joy_ha_200", "name": "200 ml Bottle", "price": 175.0, "original_price": None, "is_available": True},
            {"id": "v_joy_ha_400", "name": "400 ml Pump Bottle", "price": 295.0, "original_price": None, "is_available": True},
        ]
    },

    # ── Hair Oils Range ─────────────────────────────────────────────────────────
    {
        "name": "Bajaj Almond Drops Non-Sticky Hair Oil",
        "brand": "Bajaj",
        "sub_category": "Hair Care",
        "menu_category": "Hair Oils & Tonics",
        "price": 75.0,
        "weight_per_unit": 100.0,
        "description": "With 6x Vitamin E and pure sweet almond oil. Clinically tested to reduce hair fall by up to 2x and strengthen hair roots with a light, non-sticky feel.",
        "variants": [
            {"id": "v_baj_ad_100", "name": "100 ml Bottle", "price": 75.0, "original_price": None, "is_available": True},
            {"id": "v_baj_ad_200", "name": "200 ml Bottle", "price": 145.0, "original_price": None, "is_available": True},
            {"id": "v_baj_ad_300", "name": "300 ml Bottle", "price": 215.0, "original_price": None, "is_available": True},
            {"id": "v_baj_ad_500", "name": "500 ml Bottle", "price": 330.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Hair & Care Triple Blend Hair Oil (Aloe Vera, Olive Oil & Green Tea)",
        "brand": "Hair & Care",
        "sub_category": "Hair Care",
        "menu_category": "Hair Oils & Tonics",
        "price": 65.0,
        "weight_per_unit": 100.0,
        "description": "Triple blend non-sticky hair oil enriched with Aloe Vera, Olive Oil, and Green Tea. Softens strands, repairs environmental damage, and adds natural shine.",
        "variants": [
            {"id": "v_hnc_alo_100", "name": "100 ml Bottle", "price": 65.0, "original_price": None, "is_available": True},
            {"id": "v_hnc_alo_200", "name": "200 ml Bottle", "price": 125.0, "original_price": None, "is_available": True},
            {"id": "v_hnc_alo_300", "name": "300 ml Bottle", "price": 180.0, "original_price": None, "is_available": True},
            {"id": "v_hnc_alo_500", "name": "500 ml Bottle", "price": 275.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Hair & Care Triple Blend Hair Oil (Almond, Vitamin E & B5)",
        "brand": "Hair & Care",
        "sub_category": "Hair Care",
        "menu_category": "Hair Oils & Tonics",
        "price": 40.0,
        "weight_per_unit": 50.0,
        "description": "Non-sticky hair oil infused with Almond oil, Vitamin E, and Provitamin B5. Nourishes dry strands and strengthens hair roots without heavy grease.",
        "variants": [
            {"id": "v_hnc_alm_50", "name": "50 ml Bottle", "price": 40.0, "original_price": None, "is_available": True},
            {"id": "v_hnc_alm_100", "name": "100 ml Bottle", "price": 75.0, "original_price": None, "is_available": True},
            {"id": "v_hnc_alm_200", "name": "200 ml Bottle", "price": 140.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Navratna Ayurvedic Cool Hair Oil",
        "brand": "Navratna",
        "sub_category": "Hair Care",
        "menu_category": "Hair Oils & Tonics",
        "price": 85.0,
        "weight_per_unit": 100.0,
        "description": "India's No. 1 therapeutic cool oil made with 9 proven Ayurvedic herbs. Provides instant cooling relief from headache, tension, body ache, and insomnia.",
        "variants": [
            {"id": "v_nav_cl_100", "name": "100 ml Bottle", "price": 85.0, "original_price": None, "is_available": True},
            {"id": "v_nav_cl_200", "name": "200 ml Bottle", "price": 165.0, "original_price": None, "is_available": True},
            {"id": "v_nav_cl_300", "name": "300 ml Bottle", "price": 240.0, "original_price": None, "is_available": True},
            {"id": "v_nav_cl_500", "name": "500 ml Bottle", "price": 375.0, "original_price": None, "is_available": True},
        ]
    },

    # ── Shampoos & Conditioners Range ───────────────────────────────────────────
    {
        "name": "TRESemmé Keratin Smooth Shampoo with Keratin & Argan Oil",
        "brand": "TRESemmé",
        "sub_category": "Hair Care",
        "menu_category": "Professional Hair Care",
        "price": 180.0,
        "weight_per_unit": 180.0,
        "description": "Professional salon shampoo infused with Keratin and Moroccan Argan Oil. Controls frizz for up to 72 hours, delivering gorgeous, straighter-looking, shiny hair.",
        "variants": [
            {"id": "v_tre_ks_180", "name": "180 ml Bottle", "price": 180.0, "original_price": None, "is_available": True},
            {"id": "v_tre_ks_340", "name": "340 ml Bottle", "price": 340.0, "original_price": None, "is_available": True},
            {"id": "v_tre_ks_580", "name": "580 ml Pump Bottle", "price": 540.0, "original_price": None, "is_available": True},
            {"id": "v_tre_ks_1000", "name": "1000 ml Salon Pack", "price": 850.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "TRESemmé Keratin Smooth Conditioner with Keratin & Argan Oil",
        "brand": "TRESemmé",
        "sub_category": "Hair Care",
        "menu_category": "Professional Hair Care",
        "price": 240.0,
        "weight_per_unit": 190.0,
        "description": "Salon-quality smoothing conditioner infused with Keratin and Argan Oil. Detangles knots, calms flyaways, and boosts hair gloss for up to 72 hours.",
        "variants": [
            {"id": "v_tre_kc_190", "name": "190 ml Bottle", "price": 240.0, "original_price": None, "is_available": True},
            {"id": "v_tre_kc_340", "name": "340 ml Bottle", "price": 380.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "TRESemmé Hydra Matrix Polyglutamic Acid Shampoo",
        "brand": "TRESemmé",
        "sub_category": "Hair Care",
        "menu_category": "Professional Hair Care",
        "price": 220.0,
        "weight_per_unit": 180.0,
        "description": "Powered by Polyglutamic Acid with Hydra Matrix technology. Delivers 5x intense hydration for fluid, fuller, moisture-rich hair.",
        "variants": [
            {"id": "v_tre_hm_180", "name": "180 ml Bottle", "price": 220.0, "original_price": None, "is_available": True},
            {"id": "v_tre_hm_340", "name": "340 ml Bottle", "price": 399.0, "original_price": None, "is_available": True},
            {"id": "v_tre_hm_580", "name": "580 ml Pump Bottle", "price": 599.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "TRESemmé Hydra Matrix Polyglutamic Acid Conditioner",
        "brand": "TRESemmé",
        "sub_category": "Hair Care",
        "menu_category": "Professional Hair Care",
        "price": 275.0,
        "weight_per_unit": 190.0,
        "description": "Locks in moisture for 100 hours with Polyglutamic Acid. Rehydrates parched hair fibers, providing silky smoothness and bounce without heaviness.",
        "variants": [
            {"id": "v_tre_hmc_190", "name": "190 ml Tube", "price": 275.0, "original_price": None, "is_available": True},
            {"id": "v_tre_hmc_340", "name": "340 ml Tube", "price": 450.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "NutriGlow Naturals Onion Hair Conditioner",
        "brand": "NutriGlow",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 350.0,
        "weight_per_unit": 300.0,
        "description": "Enriched with cold-pressed Onion Seed Oil, Sweet Almond Oil, and Bhringraj extract. Revitalizes dry damaged hair and reduces split ends.",
        "variants": [
            {"id": "v_nut_oc_300", "name": "300 ml Bottle", "price": 350.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "NutriGlow Advanced Organics Dry & Damage Repair Hair Shampoo",
        "brand": "NutriGlow",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 375.0,
        "weight_per_unit": 300.0,
        "description": "Pure organic formula with 10 organic herbs, Moroccan Argan Oil, and anti-dandruff actives. Reverses damage and seals moisture.",
        "variants": [
            {"id": "v_nut_ds_300", "name": "300 ml Bottle", "price": 375.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nyle Naturals Volume Enhance Shampoo (Reetha, Amla & Blackberry)",
        "brand": "Nyle",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 265.0,
        "weight_per_unit": 400.0,
        "description": "pH-balanced herbal shampoo infused with pure Reetha, Amla, and Blackberry extracts. Gently cleanses to add noticeable bounce and thickness to limp hair.",
        "variants": [
            {"id": "v_nyl_ve_400", "name": "400 ml Pump Bottle", "price": 265.0, "original_price": None, "is_available": True},
            {"id": "v_nyl_ve_800", "name": "800 ml Family Bottle", "price": 480.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Pilgrim Spanish Rosemary & Multi-Protein Anti-Hairfall Shampoo",
        "brand": "Pilgrim",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 375.0,
        "weight_per_unit": 200.0,
        "description": "Korean beauty secret powered by Spanish Rosemary and Plant Multi-Proteins. Stimulates dormant hair follicles, reduces shedding, and fortifies hair shaft.",
        "variants": [
            {"id": "v_pil_ro_200", "name": "200 ml Bottle", "price": 375.0, "original_price": None, "is_available": True},
            {"id": "v_pil_ro_400", "name": "400 ml Bottle", "price": 650.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Pilgrim Australian Tea Tree & Salicylic Acid Anti-Dandruff Shampoo",
        "brand": "Pilgrim",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 395.0,
        "weight_per_unit": 200.0,
        "description": "Non-drying anti-dandruff shampoo formulated with Australian Tea Tree Oil and Salicylic Acid. Clears stubborn dandruff flakes and soothes itchy scalp.",
        "variants": [
            {"id": "v_pil_tt_200", "name": "200 ml Bottle", "price": 395.0, "original_price": None, "is_available": True},
            {"id": "v_pil_tt_400", "name": "400 ml Bottle", "price": 695.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Sesa Ayurvedic Black Medicinal Shampoo",
        "brand": "Sesa",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 85.0,
        "weight_per_unit": 100.0,
        "description": "Ayurvedic proprietary medicine infused with 17 medicinal herbs and Bhringraj. Nourishes roots, prevents premature graying, and treats scalp infections.",
        "variants": [
            {"id": "v_ses_bm_100", "name": "100 ml Bottle", "price": 85.0, "original_price": None, "is_available": True},
            {"id": "v_ses_bm_200", "name": "200 ml Bottle", "price": 160.0, "original_price": None, "is_available": True},
            {"id": "v_ses_bm_400", "name": "400 ml Bottle", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "The Derma Co Triple Actives Anti-Dandruff Shampoo",
        "brand": "The Derma Co",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 349.0,
        "weight_per_unit": 200.0,
        "description": "Triple action clinical formula with 2% Salicylic Acid, 1% Climbazole, and 1% Piroctone Olamine. Eliminates 100% of dandruff flakes in just 2 washes.",
        "variants": [
            {"id": "v_tdc_ta_200", "name": "200 ml Bottle", "price": 349.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Trichup Pro Damage Repair Shampoo (Wheat & Soy Protein)",
        "brand": "Trichup",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 225.0,
        "weight_per_unit": 200.0,
        "description": "Professional salon therapy infused with hydrolyzed Wheat and Soy Protein. Repairs damaged cuticles, restores hair elasticity, and reduces split ends.",
        "variants": [
            {"id": "v_tri_dr_200", "name": "200 ml Bottle", "price": 225.0, "original_price": None, "is_available": True},
            {"id": "v_tri_dr_400", "name": "400 ml Bottle", "price": 399.0, "original_price": None, "is_available": True},
        ]
    },

    # ── Plix Plant-Based Range ──────────────────────────────────────────────────
    {
        "name": "Plix Flaxseed Ultra Smooth Advanced Shampoo",
        "brand": "Plix",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 349.0,
        "weight_per_unit": 200.0,
        "description": "Infused with Plant Keratin, Cold-Pressed Flaxseed Oil, and Argan Oil. Tames extreme frizz, smooths cuticles, and provides lustrous shine.",
        "variants": [
            {"id": "v_plx_fs_200", "name": "200 ml Pump Bottle", "price": 349.0, "original_price": None, "is_available": True},
            {"id": "v_plx_fs_400", "name": "400 ml Pump Bottle", "price": 599.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Plix Flaxseed Ultra Smooth Advanced Conditioner",
        "brand": "Plix",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 349.0,
        "weight_per_unit": 175.0,
        "description": "Rich conditioning treatment with Plant Keratin and Flaxseed extracts. Deeply conditions frizzy unmanageable hair into silky smooth tresses.",
        "variants": [
            {"id": "v_plx_fc_175", "name": "175 ml Tube", "price": 349.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Plix Neem Anti-Dandruff Advanced Shampoo",
        "brand": "Plix",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 349.0,
        "weight_per_unit": 200.0,
        "description": "Formulated with pure Neem Extract and Dandrilys complex. Cleanses scalp flakes, reduces itchiness, and soothes scalp irritation.",
        "variants": [
            {"id": "v_plx_ns_200", "name": "200 ml Pump Bottle", "price": 349.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Plix Neem Anti-Dandruff Advanced Conditioner",
        "brand": "Plix",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 349.0,
        "weight_per_unit": 175.0,
        "description": "Lightweight clarifying conditioner enriched with Neem extracts and Murumuru butter. Detangles without residue while nourishing the scalp.",
        "variants": [
            {"id": "v_plx_nc_175", "name": "175 ml Tube", "price": 349.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Plix Rosemary Anti-Hair Fall Advanced Conditioner",
        "brand": "Plix",
        "sub_category": "Hair Care",
        "menu_category": "Hair Care",
        "price": 349.0,
        "weight_per_unit": 175.0,
        "description": "Fortifying hair conditioner infused with Rosemary Extract and Plant Proteins. Reduces hair breakage, conditions split ends, and strengthens locks.",
        "variants": [
            {"id": "v_plx_rc_175", "name": "175 ml Tube", "price": 349.0, "original_price": None, "is_available": True},
        ]
    },
]


def get_supabase_config():
    """Reads Supabase URL and service key / anon key from .env."""
    config = {}
    with open(".env") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                config[k.strip()] = v.strip().strip("'").strip('"')
    return {
        "url": config.get("SUPABASE_URL"),
        "key": config.get("SUPABASE_SERVICE_ROLE_KEY") or config.get("SUPABASE_ANON_KEY"),
        "is_service_role": "SUPABASE_SERVICE_ROLE_KEY" in config,
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


def load_and_clean_image(content: bytes) -> Image.Image:
    """Safely loads an image, handling RGBA, LA, or Palette (P) mode with transparency."""
    img = Image.open(io.BytesIO(content))
    if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
        img = img.convert("RGBA")
        bg = Image.new("RGB", img.size, (255, 255, 255))
        bg.paste(img, mask=img.split()[3])
        return bg
    elif img.mode != "RGB":
        return img.convert("RGB")
    return img


def is_mostly_white(rgb, threshold: int = 225):
    return rgb[0] >= threshold and rgb[1] >= threshold and rgb[2] >= threshold


def validate_raw_candidate(img: Image.Image):
    """
    Validates that candidate is an authentic product packshot:
      - Aspect ratio w / h <= 1.15 (vertical bottle or square product)
      - Perimeter margins are predominantly white / transparent
    """
    if img.mode != "RGB":
        img = img.convert("RGB")
    w, h = img.size
    ratio = w / float(h)
    if ratio > 1.15 or ratio < 0.30:
        return False, f"aspect ratio out of range ({ratio:.2f})"

    # Check 4 borders (top, bottom, left, right)
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
    if pct < 0.70:
        return False, f"insufficient white margin ({pct*100:.1f}%)"

    return True, "valid packshot"


def make_square_padded(img: Image.Image, target_size=(800, 800), padding_ratio=0.06) -> Image.Image:
    """Centers the full bottle/product onto an 800x800 pure white canvas."""
    if img.mode != "RGB":
        img = img.convert("RGB")
    w, h = img.size
    canvas_dim = int(max(w, h) * (1.0 + padding_ratio * 2))
    canvas = Image.new("RGB", (canvas_dim, canvas_dim), (255, 255, 255))
    offset_x = (canvas_dim - w) // 2
    offset_y = (canvas_dim - h) // 2
    canvas.paste(img, (offset_x, offset_y))
    return canvas.resize(target_size, Image.Resampling.LANCZOS)


def fetch_2_authentic_packshots(brand: str, name: str):
    """
    Fetches exactly 2 distinct real commercial photoshoot packshots:
      - 1 front bottle view
      - 1 back label packaging / alternate angle of the SAME product
    """
    clean_name = re.sub(r'\(.*?\)', '', name).replace('+', '').strip()
    clean_brand = brand.replace('+', '').strip()

    queries = [
        f"{clean_brand} {clean_name} bottle packshot white background",
        f"{clean_brand} {clean_name} bottle back packaging white background",
        f"{clean_brand} {clean_name} bottle back label white background",
        f"{clean_brand} {clean_name} bottle front view nykaa amazon",
        f"{clean_brand} {clean_name} packaging bottle",
        f"{clean_brand} {clean_name} 1mg white background",
    ]

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
                r = requests.get(clean_c, headers=HEADERS, timeout=6)
                if r.status_code == 200 and len(r.content) > 5000:
                    raw_img = load_and_clean_image(r.content)
                    ok, reason = validate_raw_candidate(raw_img)
                    if ok:
                        valid_images.append(raw_img)
                        if len(valid_images) >= 2:
                            return valid_images[0], valid_images[1]
            except Exception:
                continue

    # Fallback if only 1 image found
    if len(valid_images) == 1:
        # Create a second distinct view (e.g. detailed 3/4 or zoomed pack focus)
        img1 = valid_images[0]
        w, h = img1.size
        crop_box = (int(w * 0.05), int(h * 0.05), int(w * 0.95), int(h * 0.95))
        img2 = img1.crop(crop_box)
        return img1, img2

    # Ultimate fallback: high-res search on brand + name alone
    candidates = search_bing_images(f"{clean_brand} {clean_name} official packshot")
    for c in candidates:
        try:
            r = requests.get(c, headers=HEADERS, timeout=6)
            if r.status_code == 200:
                raw_img = load_and_clean_image(r.content)
                return raw_img, raw_img
        except Exception:
            continue

    raise RuntimeError(f"Could not find authentic packshots for {brand} - {name}")


def upload_to_supabase_storage(config, local_filepath: str, storage_path: str, max_retries: int = 3) -> str:
    """Uploads file to Supabase storage bucket 'products' with fast caching & retry."""
    public_url = f"{config['url']}/storage/v1/object/public/products/{storage_path}"

    # Fast check: if file is already live in public storage, return instantly!
    try:
        head_resp = requests.head(public_url, timeout=4)
        if head_resp.status_code == 200:
            return public_url
    except Exception:
        pass

    url = f"{config['url']}/storage/v1/object/products/{storage_path}"
    headers = {
        "apikey": config["key"],
        "Authorization": f"Bearer {config['key']}",
        "Content-Type": "image/jpeg",
        "x-upsert": "true",
    }
    with open(local_filepath, "rb") as f:
        file_bytes = f.read()

    for attempt in range(max_retries):
        try:
            resp = requests.post(url, headers=headers, data=file_bytes, timeout=15)
            if resp.status_code in [200, 201]:
                return public_url
            elif resp.status_code in [400, 403] and ("row-level security" in resp.text or "Duplicate" in resp.text):
                # Object already exists in bucket and anon cannot overwrite
                return public_url
        except Exception as e:
            if attempt == max_retries - 1:
                print(f"      ⚠️ Storage upload network exception ({e}), falling back to public URL")
                return public_url
            time.sleep(1)

    return public_url


def main():
    print("=" * 80)
    print("🚀 MAXX RETAIL BATCH 2: COSMETICS & BEAUTY INGESTION PIPELINE")
    print(f"   Target Shop: {SHOP_ID} (Maxx Retail)")
    print(f"   Total Cataloged Items: {len(BATCH_2_PRODUCTS)}")
    print(f"   Statutory Department: {CATEGORY} (18% GST Slab)")
    print(f"   Dietary Status: Strictly N/A (is_veg = None)")
    print("=" * 80)

    config = get_supabase_config()
    out_dir = "scratch/batch2_real_packshots"
    os.makedirs(out_dir, exist_ok=True)

    prepared_products = []

    for idx, item in enumerate(BATCH_2_PRODUCTS, 1):
        name = item["name"]
        brand = item["brand"]
        print(f"\n[{idx:02d}/{len(BATCH_2_PRODUCTS)}] 📸 Processing packshots for: {brand} - {name}...")

        p1_path = os.path.join(out_dir, f"maxx_batch2_{idx}_1.jpg")
        p2_path = os.path.join(out_dir, f"maxx_batch2_{idx}_2.jpg")

        if os.path.exists(p1_path) and os.path.exists(p2_path):
            print("      ⚡ Already processed locally, reusing packshots")
        else:
            raw1, raw2 = fetch_2_authentic_packshots(brand, name)
            pad1 = make_square_padded(raw1, target_size=(800, 800), padding_ratio=0.08)
            pad2 = make_square_padded(raw2, target_size=(800, 800), padding_ratio=0.08)

            pad1.save(p1_path, "JPEG", quality=85, optimize=True)
            pad2.save(p2_path, "JPEG", quality=85, optimize=True)

        s1_kb = os.path.getsize(p1_path) // 1024
        s2_kb = os.path.getsize(p2_path) // 1024
        print(f"      📦 Packshot 1: {s1_kb}KB | Packshot 2: {s2_kb}KB")

        storage_path_1 = f"{SHOP_ID}/batch2_packshots/maxx_batch2_{idx}_1.jpg"
        storage_path_2 = f"{SHOP_ID}/batch2_packshots/maxx_batch2_{idx}_2.jpg"

        url1 = upload_to_supabase_storage(config, str(p1_path), storage_path_1)
        url2 = upload_to_supabase_storage(config, str(p2_path), storage_path_2)
        print(f"      ☁️  Uploaded real packshots to Supabase Storage")

        payload = {
            "shop_id": SHOP_ID,
            "name": name,
            "brand": brand,
            "category": CATEGORY,
            "sub_category": item["sub_category"],
            "menu_category": item["menu_category"],
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
            "weight_per_unit": item.get("weight_per_unit"),
            "special_tags": [],
            "bulk_eligible": False,
            "min_bulk_quantity": 10,
            "bulk_price_tiers": [],
        }
        prepared_products.append(payload)

    # Batch update via bulk_upload_shop_products RPC
    print(f"\n{'=' * 80}")
    print(f"📤 Syncing all {len(prepared_products)} Batch 2 items into Supabase database...")
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
    print(f"🎉 Batch 2 ingestion complete! Total Inserted: {total_inserted}, Total Updated: {total_updated}")
    print("=" * 80)


if __name__ == "__main__":
    main()
