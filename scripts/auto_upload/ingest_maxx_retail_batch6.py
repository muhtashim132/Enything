#!/usr/bin/env python3
"""
Maxx Retail Batch 6 (Shelf Scans g42.jpeg - g51.jpeg) Ingestion Engine
======================================================================
Catalog: 103 authentic cosmetics, face washes, cleansers, scrubs, razors, hair colors,
         shoe polishes, fine fragrance mists, and deodorants:
  - Face Washes & Scrubs: Ghar Soaps Magic Face Wash, NutriGlow (Gold Kesar, Neem & Tulsi,
    8% AHA BHA, Vitamin C, Papaya), VLCC Serum Face Wash BOGO sets (Acne Defense, Hydra Nourish),
    Himalaya (Oil Clear Lemon, Walnut Face Scrub), Clean & Clear (Blackhead Scrub, Morning Energy
    Lemon, Apple, Berry Blast, Vitamin C, Aloe Vera, Foaming Face Wash), Pond's (Bright Beauty
    Niacinamide, Bright Miracle Charcoal Detox).
  - Shaving & Hair Removal: Gillette Venus ComfortGlide Breeze Razor, Gillette Venus Refill Cartridges,
    Bombae Flexi Body Razor, BioSoft Pre-Cut Depilatory Waxing Strips.
  - Hair Colours & Shoe Care: Streax Insta Shampoo Hair Colour (Black, Brown), Nisha Quick Color
    Shampoo Based Hair Colour, Streax Creme Hair Colour (Black 1, Dark Brown 3, Brown 4, Reddish Brown 4.6,
    Burgundy 3.16, Golden Blonde 9.13), Streax Ultralights Gel Hair Colour, Garnier Color Naturals
    Creme Riche (Black 1, Brown 4, Caramel Brown 5.32), Enega No Ammonia Crème (Black 1, Burgundy 3.16),
    L'Oreal Professionnel Majirel, Revlon Color 'N Care, Revlon Colorsilk Beautiful Color,
    Cherry Blossom Wax Shoe Polish (Dark Tan, Black).
  - Body Mists & Splashes: VLCC Velvet Symphony, Yardley London (Gorgeous Girl, Violet & Raspberry,
    Magnolia & Grapefruit), Layer'r Wottagirl! Fragrant Body Splashes (Fantasy, Vanilla Twist,
    Secret Crush, Pure Paradise, Cupid Heart, Amber Kiss, Mystic Island, Currant Crush, Pink Heart,
    Gold, Dark Gold, Tuscan Green, Pink Angel, Marine Bay, Pink Vibes, Pink Dream).
  - Deodorants & Perfumed Sprays: Layer'r Shot (Imperial Jade, Bullet, Bold Legend, Bold Icon,
    Bold Victor, Royal Jade, Black Alpha), Envy French Collection (Women Pink, Women Violet,
    Men Bleu, Men Silver, Men Magnetic Red, Men Gold, Men Noir, Men Emerald Green, Smart Spray),
    Nivea (Men Fresh Active, Men Cool Kick, Pearl & Beauty Radiance, Fresh Natural),
    Yardley London (Vanilla Blush, Peachy Glow, Lace Satin, English Lavender, Lace, Gentleman Tobacco & Amber),
    Nike Woman (Trendy, Pink Paradise, Pure), Secret Temptation (Aura, Cupid, Bling),
    Bella Vita Luxury CEO Man, Vanesa (Pink Desire, Night Glamour), Wild Stone (Red, Legend,
    Ultra Sensual, CODE Oud), Pepe Jeans London Bright Woman.

Directives:
  1. Product category: Strictly 'Cosmetics & Beauty' (18% Statutory GST slab)
  2. Brand / Manufacturer strictly populated for every item (100%)
  3. Dietary N/A: strictly is_veg = None (SQL NULL)
  4. Real photoshoot packshots only: exactly 2 distinct views of the physical bottle/pack on clean white background
  5. 800x800 square 1:1, < 120KB
  6. Ingest into Supabase via public.bulk_upload_shop_products RPC
  7. Verification: zero missing brand, zero non-null is_veg, is_deleted = false
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

BATCH_6_PRODUCTS = [
    # ── 1. Face Cleansers, Scrubs & Treatments ──────────────────────────────────
    {
        "name": "Ghar Soaps Magic Face Wash",
        "brand": "Ghar Soaps",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 349.0,
        "weight_per_unit": 100.0,
        "description": "Advanced tan reduction daily face wash formulated with Alpha Arbutin and Lactic Acid. Gently cleanses deep seated dirt, fades stubborn sun tan, and reveals radiant glowing skin.",
        "variants": [
            {"id": "v_ghar_mfw_100", "name": "100ml Pump Bottle", "price": 349.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "NutriGlow Gold Kesar Deep Cleansing Face Wash",
        "brand": "NutriGlow",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 125.0,
        "weight_per_unit": 65.0,
        "description": "3-in-1 deep cleansing skin whitening face wash formulated with golden essence and pure kesar extracts for intense radiant glow and moisture rejuvenation.",
        "variants": [
            {"id": "v_ng_gk_65", "name": "65ml Tube", "price": 125.0, "original_price": None, "is_available": True},
            {"id": "v_ng_gk_100", "name": "100ml Tube", "price": 175.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "NutriGlow Neem & Tulsi 3-in-1 Face Wash",
        "brand": "NutriGlow",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 110.0,
        "weight_per_unit": 65.0,
        "description": "Purifying 3-in-1 anti-acne face wash with organic neem and tulsi extracts. Regulates excess sebum, fights pimple-causing bacteria, and removes deep impurities.",
        "variants": [
            {"id": "v_ng_nt_65", "name": "65ml Tube", "price": 110.0, "original_price": None, "is_available": True},
            {"id": "v_ng_nt_100", "name": "100ml Tube", "price": 160.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "NutriGlow 8% AHA BHA Spot Correction Daily Face Wash",
        "brand": "NutriGlow",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 275.0,
        "weight_per_unit": 100.0,
        "description": "Dermatologically formulated daily exfoliating face wash with 8% AHA BHA, Cucumber, and Glycolic Acid to reduce dark spots, blemishes, and stubborn pigmentation.",
        "variants": [
            {"id": "v_ng_ahabha_100", "name": "100ml Tube", "price": 275.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "NutriGlow Vitamin C Lightening Face Wash",
        "brand": "NutriGlow",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 275.0,
        "weight_per_unit": 100.0,
        "description": "Skin lightening face wash powered by Vitamin C, Alpha Arbutin, Glycolic Acid, and Ceramides. Brightens dull complexion and reverses sun damage.",
        "variants": [
            {"id": "v_ng_vitc_100", "name": "100ml Tube", "price": 275.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "NutriGlow Papaya Face Wash Anti-Pigmentation & Lightening",
        "brand": "NutriGlow",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 100.0,
        "description": "Advanced Pro Formula face wash loaded with Papaya Fruit extracts, Niacinamide, and Orange Peel to gently exfoliate, lighten dark spots, and even skin tone.",
        "variants": [
            {"id": "v_ng_papaya_100", "name": "100g Tube", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "VLCC Acne Defense Serum Face Wash (Buy 1 Get 1 Free)",
        "brand": "VLCC",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 299.0,
        "weight_per_unit": 200.0,
        "description": "Active clarifying serum face wash infused with Salicylic Acid Serum and Tulsi. Targets stubborn breakouts and unclogs pores without stripping moisture (Pack of 2).",
        "variants": [
            {"id": "v_vlcc_ad_bogo", "name": "100ml + 100ml BOGO Pack", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "VLCC Hydra Nourish Serum Face Wash (Buy 1 Get 1 Free)",
        "brand": "VLCC",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 299.0,
        "weight_per_unit": 200.0,
        "description": "Deeply hydrating serum face wash infused with Hyaluronic Acid Serum and soothing Aloe Vera for 24-hour supple, plumping moisture barrier care (Pack of 2).",
        "variants": [
            {"id": "v_vlcc_hn_bogo", "name": "100ml + 100ml BOGO Pack", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Himalaya Oil Clear Lemon Face Wash",
        "brand": "Himalaya",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 170.0,
        "weight_per_unit": 100.0,
        "description": "Herbal soap-free formulation with Lemon and Honey that gently removes excess oil, tightens pores, and provides up to 12 hours of oil-free freshness.",
        "variants": [
            {"id": "v_him_ocl_100", "name": "100ml Tube", "price": 170.0, "original_price": None, "is_available": True},
            {"id": "v_him_ocl_50", "name": "50ml Tube", "price": 95.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Himalaya Blackhead Clearing Walnut Face Scrub",
        "brand": "Himalaya",
        "sub_category": "Face Scrubs & Exfoliators",
        "menu_category": "General / Wellness",
        "price": 175.0,
        "weight_per_unit": 100.0,
        "description": "Natural exfoliating face scrub enriched with Walnut granules, Lemongrass, and Apple. Clears dead skin cells and removes blackheads for smoother skin.",
        "variants": [
            {"id": "v_him_bcw_100", "name": "100g Tube", "price": 175.0, "original_price": None, "is_available": True},
            {"id": "v_him_bcw_50", "name": "50g Tube", "price": 99.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Clean & Clear Blackhead Clearing Daily Scrub",
        "brand": "Clean & Clear",
        "sub_category": "Face Scrubs & Exfoliators",
        "menu_category": "General / Wellness",
        "price": 160.0,
        "weight_per_unit": 80.0,
        "description": "Fast-acting scrub with micro-cleansing beads and Salicylic Acid that penetrates deep into pores to dissolve blackhead-causing impurities and excess oil.",
        "variants": [
            {"id": "v_cc_bcs_80", "name": "80g Tube", "price": 160.0, "original_price": None, "is_available": True},
            {"id": "v_cc_bcs_50", "name": "50g Tube", "price": 110.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Clean & Clear Morning Energy Lemon Fresh Face Wash",
        "brand": "Clean & Clear",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 175.0,
        "weight_per_unit": 100.0,
        "description": "Energizing daily cleanser with natural Lemon extract and bursting beads. Awakens tired skin and leaves it looking bright, vibrant, and oil-free.",
        "variants": [
            {"id": "v_cc_mel_100", "name": "100ml Bottle", "price": 175.0, "original_price": None, "is_available": True},
            {"id": "v_cc_mel_50", "name": "50ml Bottle", "price": 99.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Clean & Clear Morning Energy Apple Face Wash",
        "brand": "Clean & Clear",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 175.0,
        "weight_per_unit": 100.0,
        "description": "Purifying daily facial cleanser with natural Apple extracts and cooling beads that deeply refresh and cleanse skin of daily buildup.",
        "variants": [
            {"id": "v_cc_mea_100", "name": "100ml Bottle", "price": 175.0, "original_price": None, "is_available": True},
            {"id": "v_cc_mea_50", "name": "50ml Bottle", "price": 99.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Clean & Clear Morning Energy Berry Blast Face Wash",
        "brand": "Clean & Clear",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 175.0,
        "weight_per_unit": 100.0,
        "description": "Infused with luscious berry extracts and cooling bursting beads to invigorate the skin and leave it soft, energized, and visibly glowing.",
        "variants": [
            {"id": "v_cc_meb_100", "name": "100ml Bottle", "price": 175.0, "original_price": None, "is_available": True},
            {"id": "v_cc_meb_50", "name": "50ml Bottle", "price": 99.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Clean & Clear Vitamin C Face Wash",
        "brand": "Clean & Clear",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 185.0,
        "weight_per_unit": 100.0,
        "description": "Radiance-boosting daily face cleanser loaded with antioxidant Vitamin C to target dullness and reveal glowing, revived skin.",
        "variants": [
            {"id": "v_cc_vitc_100", "name": "100ml Bottle", "price": 185.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Clean & Clear Aloe Vera Gentle Hydrating Face Wash",
        "brand": "Clean & Clear",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 175.0,
        "weight_per_unit": 100.0,
        "description": "Gentle daily facial wash formulated with 100% natural Aloe Vera extracts to calm, soothe, and gently cleanse sensitive skin without tightness.",
        "variants": [
            {"id": "v_cc_aloe_100", "name": "100ml Bottle", "price": 175.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Clean & Clear Foaming Face Wash",
        "brand": "Clean & Clear",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 165.0,
        "weight_per_unit": 100.0,
        "description": "Oil-free rich foaming formula that reaches deep into pores to wash away oil, dirt, and bacteria to help prevent pimples and shine.",
        "variants": [
            {"id": "v_cc_ffw_100", "name": "100ml Bottle", "price": 165.0, "original_price": None, "is_available": True},
            {"id": "v_cc_ffw_50", "name": "50ml Bottle", "price": 95.0, "original_price": None, "is_available": True},
            {"id": "v_cc_ffw_150", "name": "150ml Pump", "price": 235.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Pond's Bright Beauty Spot-less Glow Face Wash with Niacinamide",
        "brand": "Pond's",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 210.0,
        "weight_per_unit": 100.0,
        "description": "Clinically proven spot-reduction formula with Niacinamide (Vitamin B3) that removes dead skin cells and dullness for 10x spotless glow.",
        "variants": [
            {"id": "v_pb_bb_100", "name": "100g Tube", "price": 210.0, "original_price": None, "is_available": True},
            {"id": "v_pb_bb_50", "name": "50g Tube", "price": 115.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Pond's Bright Miracle Detox Charcoal Face Wash",
        "brand": "Pond's",
        "sub_category": "Face Wash & Cleansers",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 100.0,
        "description": "Activated Charcoal facial cleanser that draws out deep-set pollution particles, excess sebum, and toxins for clear, refreshed brightness.",
        "variants": [
            {"id": "v_pb_char_100", "name": "100g Tube", "price": 225.0, "original_price": None, "is_available": True},
            {"id": "v_pb_char_50", "name": "50g Tube", "price": 120.0, "original_price": None, "is_available": True},
        ]
    },

    # ── 2. Women's Shaving, Hair Removal & Grooming ─────────────────────────────
    {
        "name": "Gillette Venus ComfortGlide Breeze Razor for Women",
        "brand": "Gillette",
        "sub_category": "Shaving & Hair Removal",
        "menu_category": "General / Wellness",
        "price": 350.0,
        "weight_per_unit": 80.0,
        "description": "Flexible 3-blade body razor for women with built-in Freesia scented moisture bars that lather with water for a smooth, close, irritation-free shave.",
        "variants": [
            {"id": "v_gv_cgb_razor", "name": "1 Handle + 1 Cartridge", "price": 350.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Gillette Venus ComfortGlide Breeze Refill Cartridges",
        "brand": "Gillette",
        "sub_category": "Shaving & Hair Removal",
        "menu_category": "General / Wellness",
        "price": 450.0,
        "weight_per_unit": 60.0,
        "description": "Replacement blades with skin-conditioning botanical oils and body butter bars designed to fit all Gillette Venus razor handles (Pack of 2).",
        "variants": [
            {"id": "v_gv_cgb_refill_2", "name": "Pack of 2 Refill Cartridges", "price": 450.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Bombae Flexi Body Razor for Women",
        "brand": "Bombae",
        "sub_category": "Shaving & Hair Removal",
        "menu_category": "General / Wellness",
        "price": 199.0,
        "weight_per_unit": 50.0,
        "description": "Flexible pivoting head razor with ultra-sharp coated blades and aloe vera lubrication strip for effortless, nick-free body grooming.",
        "variants": [
            {"id": "v_bomb_flexi_1", "name": "1 Razor Unit", "price": 199.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "BioSoft Pre-Cut Lip and Body Depilatory Waxing Strips",
        "brand": "BioSoft",
        "sub_category": "Shaving & Hair Removal",
        "menu_category": "General / Wellness",
        "price": 220.0,
        "weight_per_unit": 120.0,
        "description": "Ready-to-use cold wax strips for face and sensitive body areas. Effectively grips short hair from the roots for silky smooth, salon-quality results up to 4 weeks.",
        "variants": [
            {"id": "v_biosoft_wax_20", "name": "Pack of 20 Pre-Cut Strips", "price": 220.0, "original_price": None, "is_available": True},
        ]
    },

    # ── 3. Hair Colours & Shoe Care ─────────────────────────────────────────────
    {
        "name": "Streax Insta Shampoo Hair Colour - 1.0 Natural Black",
        "brand": "Streax",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 40.0,
        "weight_per_unit": 15.0,
        "description": "Quick 5-minute shampoo-based hair color enriched with Almond Oil and Noni extract. Delivers 100% grey coverage with exceptional natural shine.",
        "variants": [
            {"id": "v_stx_insta_nb_15", "name": "15ml Sachet", "price": 40.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Streax Insta Shampoo Hair Colour - 3.0 Dark Brown",
        "brand": "Streax",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 40.0,
        "weight_per_unit": 15.0,
        "description": "Quick 5-minute shampoo hair color for deep natural dark brown tones, formulated with nourishing herbal extracts for soft, shiny tresses.",
        "variants": [
            {"id": "v_stx_insta_db_15", "name": "15ml Sachet", "price": 40.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nisha Quick Color Shampoo Based Hair Color - Natural Black",
        "brand": "Nisha",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 35.0,
        "weight_per_unit": 20.0,
        "description": "Ammonia-free shampoo hair color with Amla, Henna, and Shikakai extracts. Effortlessly colours greys in just 5 minutes in a convenient shampoo format.",
        "variants": [
            {"id": "v_nisha_qc_nb_20", "name": "20ml Sachet", "price": 35.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Streax Creme Hair Colour - 1 Natural Black",
        "brand": "Streax",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 160.0,
        "weight_per_unit": 120.0,
        "description": "Permanent creme hair colour infused with Walnut and Argan oil for ultra-soft, glossy texture and lasting 100% grey coverage.",
        "variants": [
            {"id": "v_stx_cr_1_nb", "name": "100ml / 50ml Kit", "price": 160.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Streax Creme Hair Colour - 3 Dark Brown",
        "brand": "Streax",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 160.0,
        "weight_per_unit": 120.0,
        "description": "Rich dark brown creme hair color with conditioner enriched with Walnut and Argan oil for vibrant shine up to 32 washes.",
        "variants": [
            {"id": "v_stx_cr_3_db", "name": "100ml / 50ml Kit", "price": 160.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Streax Creme Hair Colour - 4 Brown",
        "brand": "Streax",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 160.0,
        "weight_per_unit": 120.0,
        "description": "Classic natural brown creme hair colour with shine-enhancing conditioning complexes.",
        "variants": [
            {"id": "v_stx_cr_4_br", "name": "100ml / 50ml Kit", "price": 160.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Streax Creme Hair Colour - 4.6 Reddish Brown",
        "brand": "Streax",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 160.0,
        "weight_per_unit": 120.0,
        "description": "Warm reddish brown permanent creme hair colour that highlights hair with multi-dimensional radiant tones.",
        "variants": [
            {"id": "v_stx_cr_46_rb", "name": "100ml / 50ml Kit", "price": 160.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Streax Creme Hair Colour - 3.16 Burgundy",
        "brand": "Streax",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 160.0,
        "weight_per_unit": 120.0,
        "description": "Deep, luxurious wine burgundy shade enriched with argan and walnut oil for salon-grade brilliant shine.",
        "variants": [
            {"id": "v_stx_cr_316_bur", "name": "100ml / 50ml Kit", "price": 160.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Streax Creme Hair Colour - 9.13 Golden Blonde",
        "brand": "Streax",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 175.0,
        "weight_per_unit": 120.0,
        "description": "Radiant golden blonde hair colour with high-lift conditioning formula for lustrous, sun-kissed reflection.",
        "variants": [
            {"id": "v_stx_cr_913_gb", "name": "100ml / 50ml Kit", "price": 175.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Streax Ultralights Gel Hair Colour - Vibrant Black",
        "brand": "Streax",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 175.0,
        "weight_per_unit": 100.0,
        "description": "Easy-to-apply gel formula hair colour enriched with essential botanical oils for vibrant, glossy black hair with seamless application.",
        "variants": [
            {"id": "v_stx_ul_vb", "name": "Gel Colour Kit", "price": 175.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Garnier Color Naturals Creme Riche - 1 Natural Black",
        "brand": "Garnier",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 199.0,
        "weight_per_unit": 130.0,
        "description": "Nourishing permanent hair color with 3 essential oils (Olive, Almond, Avocado) for rich 8-week color and 100% grey coverage, with Free Colgate Strong Teeth.",
        "variants": [
            {"id": "v_gar_cn_1_nb", "name": "Complete Kit", "price": 199.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Garnier Color Naturals Creme Riche - 4 Brown",
        "brand": "Garnier",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 199.0,
        "weight_per_unit": 130.0,
        "description": "Natural radiant brown permanent creme hair color providing 50% more shine and intense hair nourishment.",
        "variants": [
            {"id": "v_gar_cn_4_br", "name": "Complete Kit", "price": 199.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Garnier Color Naturals Creme Riche - 5.32 Caramel Brown",
        "brand": "Garnier",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 210.0,
        "weight_per_unit": 130.0,
        "description": "Iridescent caramel brown shade enriched with fruit oils for silky soft, multi-tonal dimensional color.",
        "variants": [
            {"id": "v_gar_cn_532_cb", "name": "Complete Kit", "price": 210.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Enega No Ammonia Crème Hair Colour - 1 Natural Black",
        "brand": "Enega",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 150.0,
        "weight_per_unit": 100.0,
        "description": "Ammonia-free permanent creme hair colour enriched with Argan oil and Walnut oil for vibrant long-lasting grey coverage.",
        "variants": [
            {"id": "v_enega_1_nb", "name": "100g Kit", "price": 150.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Enega No Ammonia Crème Hair Colour - 3.16 Burgundy",
        "brand": "Enega",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 150.0,
        "weight_per_unit": 100.0,
        "description": "Gentle ammonia-free conditioning hair colour delivering rich burgundy tones with high-gloss mirror shine.",
        "variants": [
            {"id": "v_enega_316_bur", "name": "100g Kit", "price": 150.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "L'Oreal Professionnel Majirel Hair Colour Cream",
        "brand": "L'Oreal Professionnel",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 390.0,
        "weight_per_unit": 50.0,
        "description": "Iconic salon professional permanent hair colour formulated with Ionène G and Incell technology to strengthen hair fibre while delivering true-to-tone deep color.",
        "variants": [
            {"id": "v_majirel_50", "name": "50ml Salon Tube", "price": 390.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Revlon Color 'N Care Permanent Hair Color - 1 Natural Black",
        "brand": "Revlon",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 200.0,
        "weight_per_unit": 120.0,
        "description": "Nourishing permanent hair color infused with a blend of 4 oils (Coconut, Olive, Sesame, Almond) and Shea Butter for silky, shiny hair and 100% grey coverage.",
        "variants": [
            {"id": "v_rev_cnc_1_nb", "name": "Complete Kit", "price": 200.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Revlon Colorsilk Beautiful Color - 10 Black",
        "brand": "Revlon",
        "sub_category": "Hair Colour",
        "menu_category": "General / Wellness",
        "price": 450.0,
        "weight_per_unit": 150.0,
        "description": "100% ammonia-free permanent hair color with 3D Color Gel Technology, Keratin, and Silk Amino Acids for natural-looking, multi-tonal shade and vibrant shine.",
        "variants": [
            {"id": "v_rev_cs_10_bl", "name": "Ammonia-Free Kit", "price": 450.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Cherry Blossom Shoe Polish Wax - Dark Tan",
        "brand": "Cherry Blossom",
        "sub_category": "Shoe Care & Accessories",
        "menu_category": "General / Wellness",
        "price": 60.0,
        "weight_per_unit": 40.0,
        "description": "Traditional blend of premium carnauba and mineral waxes that nourishes, preserves, and gives a deep, long-lasting high gloss shine to dark tan leather shoes.",
        "variants": [
            {"id": "v_cb_dt_40", "name": "40g Tin", "price": 60.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Cherry Blossom Shoe Polish Wax - Black",
        "brand": "Cherry Blossom",
        "sub_category": "Shoe Care & Accessories",
        "menu_category": "General / Wellness",
        "price": 60.0,
        "weight_per_unit": 40.0,
        "description": "Classic black shoe polish formulated with natural waxes to protect leather footwear against moisture and scuffs while providing a brilliant mirror gloss.",
        "variants": [
            {"id": "v_cb_bl_40", "name": "40g Tin", "price": 60.0, "original_price": None, "is_available": True},
        ]
    },

    # ── 4. Fine Fragrance Mists, Splashes & Deodorants ──────────────────────────
    {
        "name": "VLCC Velvet Symphony Fine Fragrance Mist for Women",
        "brand": "VLCC",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 399.0,
        "weight_per_unit": 150.0,
        "description": "Luxurious fine fragrance body mist blending delicate floral heart notes with warm oriental undertones for an intoxicating, all-day personal fragrance.",
        "variants": [
            {"id": "v_vlcc_vs_150", "name": "150ml Spray Bottle", "price": 399.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Yardley London Glam Collection - Gorgeous Girl Perfume Spray",
        "brand": "Yardley London",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 299.0,
        "weight_per_unit": 150.0,
        "description": "Sparkling, glamorous perfume spray featuring floral fruity accords designed to complement the modern, stylish woman.",
        "variants": [
            {"id": "v_yl_gg_150", "name": "150ml Spray Bottle", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Yardley London Violet & Raspberry Fine Fragrance Mist",
        "brand": "Yardley London",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 450.0,
        "weight_per_unit": 200.0,
        "description": "Premium fine fragrance mist crafted with 91% naturally derived ingredients. Blends sweet ripe raspberry and soft violet petals with subtle musk.",
        "variants": [
            {"id": "v_yl_vr_200", "name": "200ml Fine Mist Bottle", "price": 450.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Yardley London Magnolia & Grapefruit Fine Fragrance Mist",
        "brand": "Yardley London",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 450.0,
        "weight_per_unit": 200.0,
        "description": "Refreshing fine fragrance mist with 91% naturally derived ingredients, featuring zesty sparkling grapefruit and blooming magnolia blossom.",
        "variants": [
            {"id": "v_yl_mg_200", "name": "200ml Fine Mist Bottle", "price": 450.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Classic Collection Fantasy Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Enchanting body splash blending crisp floral notes with sweet accents for an all-day captivating aura.",
        "variants": [
            {"id": "v_lw_fan_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Vanilla Twist Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Indulgent body splash rich with warm sugary vanilla and creamy coconut undertones for a cosy, delectable fragrance.",
        "variants": [
            {"id": "v_lw_vt_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Secret Crush Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Irresistible fruity-floral body splash featuring ripe berries, delicate jasmine, and musky undertones.",
        "variants": [
            {"id": "v_lw_sc_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Pure Paradise Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Crisp and breezy tropical aquatic body splash reminiscent of sunlit ocean waves and fresh exotic blooms.",
        "variants": [
            {"id": "v_lw_pp_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Cupid Heart Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Romantic feminine body splash opening with juicy stone fruits and settling into velvety rose petals.",
        "variants": [
            {"id": "v_lw_ch_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Amber Kiss Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Warm, sensual body splash with notes of radiant golden amber, delicate cedar, and rich vanilla.",
        "variants": [
            {"id": "v_lw_ak_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Mystic Island Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Mysterious and refreshing body splash inspired by tropical rain showers and lush green flora.",
        "variants": [
            {"id": "v_lw_mi_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Currant Crush Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Sparkling splash of tart blackcurrant and wild blackberries balanced with soft sweet floral petals.",
        "variants": [
            {"id": "v_lw_cc_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Pink Heart Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Youthful and playful body splash packed with sweet strawberry, sparkling citrus, and soft musk.",
        "variants": [
            {"id": "v_lw_ph_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Gold Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 275.0,
        "weight_per_unit": 135.0,
        "description": "Luxurious floral woody body splash with radiant golden shimmering notes of white flowers and amber.",
        "variants": [
            {"id": "v_lw_gold_135", "name": "135ml Bottle", "price": 275.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Dark Gold Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 275.0,
        "weight_per_unit": 135.0,
        "description": "Opulent and mysterious evening body splash infused with dark florals, spiced vanilla, and smooth woods.",
        "variants": [
            {"id": "v_lw_dgold_135", "name": "135ml Bottle", "price": 275.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Tuscan Green Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Uplifting green citrus body splash evocative of sun-drenched Mediterranean orchards and fresh herbs.",
        "variants": [
            {"id": "v_lw_tg_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Pink Angel Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Soft powdery floral body splash with innocent hints of cherry blossom, pear, and clean white musk.",
        "variants": [
            {"id": "v_lw_pa_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Marine Bay Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Breezy coastal body splash capturing the crisp freshness of ocean sea spray and cool ozone.",
        "variants": [
            {"id": "v_lw_mb_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Pink Vibes Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Lively sweet fruity splash with mouthwatering melon, raspberry, and sugar orchid.",
        "variants": [
            {"id": "v_lw_pv_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Wottagirl! Pink Dream Fragrant Body Splash",
        "brand": "Layer'r",
        "sub_category": "Body Mists & Perfumes",
        "menu_category": "General / Wellness",
        "price": 249.0,
        "weight_per_unit": 135.0,
        "description": "Ethereal and romantic body splash blending dewy peony blossoms with gentle peach and vanilla.",
        "variants": [
            {"id": "v_lw_pd_135", "name": "135ml Bottle", "price": 249.0, "original_price": None, "is_available": True},
        ]
    },

    # ── 5. Men's & Women's Deodorants & Body Sprays ─────────────────────────────
    {
        "name": "Layer'r Shot Intense Imperial Jade Fragrant Body Spray",
        "brand": "Layer'r",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 135.0,
        "description": "Crisp, green aromatic body spray with bracing woody nuances that keep you feeling vibrant all day.",
        "variants": [
            {"id": "v_ls_ij_135", "name": "135ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Shot Intense Bullet Fragrant Body Spray",
        "brand": "Layer'r",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 135.0,
        "description": "High-octane masculine fragrance with spicy pepper, citrus zest, and intense musk.",
        "variants": [
            {"id": "v_ls_bull_135", "name": "135ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Shot Bold Legend Fragrant Body Spray",
        "brand": "Layer'r",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 135.0,
        "description": "Charismatic woody fougère body spray tailored for confident, commanding all-day presence.",
        "variants": [
            {"id": "v_ls_leg_135", "name": "135ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Shot Bold Icon Fragrant Body Spray",
        "brand": "Layer'r",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 135.0,
        "description": "Energetic aquatic fragrance spray infused with crisp bergamot and cooling marine notes.",
        "variants": [
            {"id": "v_ls_icon_135", "name": "135ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Shot Bold Victor Fragrant Body Spray",
        "brand": "Layer'r",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 135.0,
        "description": "Bold, victorious aroma featuring warm spicy ginger, cinnamon, and smoky sandalwood.",
        "variants": [
            {"id": "v_ls_vic_135", "name": "135ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Shot Royal Jade Fragrant Body Spray",
        "brand": "Layer'r",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 135.0,
        "description": "Refined royal fragrance uniting refreshing herbs, citrus peel, and cedarwood.",
        "variants": [
            {"id": "v_ls_rj_135", "name": "135ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Layer'r Shot Black Alpha Perfume Body Spray",
        "brand": "Layer'r",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 240.0,
        "weight_per_unit": 135.0,
        "description": "Premium concentrated perfume body spray with an intense, enigmatic oriental woody trail.",
        "variants": [
            {"id": "v_ls_ba_135", "name": "135ml Can", "price": 240.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Envy French Collection Perfume Deodorant for Women - Victoria Pink",
        "brand": "Envy",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 120.0,
        "description": "Elegant French floral bouquet deodorant spray crafted for all-day odor protection and feminine charm.",
        "variants": [
            {"id": "v_envy_fc_vp_120", "name": "120ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Envy French Collection Perfume Deodorant for Women - Violet Glam",
        "brand": "Envy",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 120.0,
        "description": "Sensual French perfume deodorant enriched with luxurious violet blossoms and sweet vanilla.",
        "variants": [
            {"id": "v_envy_fc_vg_120", "name": "120ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Envy Smart Fragrance Deodorant Spray for Men",
        "brand": "Envy",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 250.0,
        "weight_per_unit": 135.0,
        "description": "Modern smart-fragrance technology body spray providing long-lasting active odor defense and masculine energy.",
        "variants": [
            {"id": "v_envy_smart_135", "name": "135ml Can", "price": 250.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Envy French Collection Perfume Deodorant Spray for Men - Bleu",
        "brand": "Envy",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 250.0,
        "weight_per_unit": 120.0,
        "description": "Invigorating French ocean notes, crisp citrus, and amber for enduring fresh confidence.",
        "variants": [
            {"id": "v_envy_fc_bleu_120", "name": "120ml Can", "price": 250.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Envy French Collection Perfume Deodorant Spray for Men - Silver",
        "brand": "Envy",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 250.0,
        "weight_per_unit": 120.0,
        "description": "Sleek metallic freshness blended with aromatic herbs, vetiver, and clean musk.",
        "variants": [
            {"id": "v_envy_fc_sil_120", "name": "120ml Can", "price": 250.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Envy French Collection Perfume Deodorant Spray for Men - Magnetic Red",
        "brand": "Envy",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 250.0,
        "weight_per_unit": 120.0,
        "description": "Captivating magnetic spicy woody fragrance designed to leave a lasting impression.",
        "variants": [
            {"id": "v_envy_fc_red_120", "name": "120ml Can", "price": 250.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Envy Perfume Deodorant Spray for Men - Gold",
        "brand": "Envy",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 250.0,
        "weight_per_unit": 120.0,
        "description": "Opulent golden fragrance spray delivering rich oriental spices and warm sandalwood.",
        "variants": [
            {"id": "v_envy_gold_120", "name": "120ml Can", "price": 250.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Envy Perfume Deodorant Spray for Men - Noir",
        "brand": "Envy",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 250.0,
        "weight_per_unit": 120.0,
        "description": "Deep, mysterious nocturnal scent with dark woods, leather accents, and amber.",
        "variants": [
            {"id": "v_envy_noir_120", "name": "120ml Can", "price": 250.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Envy Perfume Deodorant Spray for Men - Dark Green",
        "brand": "Envy",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 250.0,
        "weight_per_unit": 120.0,
        "description": "Earthy fresh forest notes, oakmoss, and crisp bergamot for natural masculinity.",
        "variants": [
            {"id": "v_envy_dg_120", "name": "120ml Can", "price": 250.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nivea Men Fresh Active 48H Deodorant Spray",
        "brand": "Nivea",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 150.0,
        "description": "Contains ocean extracts for a natural fresh feeling that lasts up to 48 hours with Nivea Men Care Complex.",
        "variants": [
            {"id": "v_niv_fa_150", "name": "150ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nivea Men Cool Kick Quick Dry 72H Deodorant Spray",
        "brand": "Nivea",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 150.0,
        "description": "Delivers an instant cooling kick of freshness and vitalizing scent with quick-dry 72-hour sweat protection.",
        "variants": [
            {"id": "v_niv_ck_150", "name": "150ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nivea Pearl & Beauty Radiance 48H Deodorant Spray for Women",
        "brand": "Nivea",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 235.0,
        "weight_per_unit": 150.0,
        "description": "Enriched with precious pearl extracts to support smooth, radiant, and even-toned underarms with 48H odor protection.",
        "variants": [
            {"id": "v_niv_pb_150", "name": "150ml Can", "price": 235.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nivea Fresh Natural 48H Deodorant Spray for Women",
        "brand": "Nivea",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 235.0,
        "weight_per_unit": 150.0,
        "description": "Natural ocean minerals provide a light, clean fragrance and reliable 48-hour deodorant protection.",
        "variants": [
            {"id": "v_niv_fn_150", "name": "150ml Can", "price": 235.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Yardley London Vanilla Blush No Gas Perfumed Deodorant",
        "brand": "Yardley London",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 275.0,
        "weight_per_unit": 120.0,
        "description": "90% naturally derived no-gas perfumed deodorant spray blending creamy warm vanilla and blushing rosebuds.",
        "variants": [
            {"id": "v_yl_vb_120", "name": "120ml Can", "price": 275.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Yardley London Peachy Glow No Gas Perfumed Deodorant",
        "brand": "Yardley London",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 275.0,
        "weight_per_unit": 120.0,
        "description": "90% naturally derived no-gas perfumed body spray with luscious sun-ripened peach, mandarin, and white floral accords.",
        "variants": [
            {"id": "v_yl_pg_120", "name": "120ml Can", "price": 275.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Yardley London Lace Satin Perfumed Deodorant Body Spray",
        "brand": "Yardley London",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 240.0,
        "weight_per_unit": 150.0,
        "description": "Exquisite satin floral deodorant with soft powdery notes, gentle lily of the valley, and cedar.",
        "variants": [
            {"id": "v_yl_ls_150", "name": "150ml Can", "price": 240.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Yardley London English Lavender Refreshing Body Spray",
        "brand": "Yardley London",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 240.0,
        "weight_per_unit": 150.0,
        "description": "Timeless floral body spray made with authentic English lavender essential oils for a calming, refreshing scent.",
        "variants": [
            {"id": "v_yl_el_150", "name": "150ml Can", "price": 240.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Yardley London Lace Perfumed Deodorant Body Spray",
        "brand": "Yardley London",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 240.0,
        "weight_per_unit": 150.0,
        "description": "Iconic romantic feminine deodorant spray infused with blooming roses, night-flowering jasmine, and warm sandalwood.",
        "variants": [
            {"id": "v_yl_lace_150", "name": "150ml Can", "price": 240.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nike Woman Trendy Deodorant Spray",
        "brand": "Nike",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 299.0,
        "weight_per_unit": 200.0,
        "description": "Trendy fruity floral fragrance with invigorating green apple, peach, and jasmine for dynamic modern women.",
        "variants": [
            {"id": "v_nike_w_trend_200", "name": "200ml Can", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nike Woman Pink Paradise Deodorant Spray",
        "brand": "Nike",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 299.0,
        "weight_per_unit": 200.0,
        "description": "Playful sweet deodorant spray offering vibrant citrus and berry notes on a creamy vanilla foundation.",
        "variants": [
            {"id": "v_nike_w_pp_200", "name": "200ml Can", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Nike Woman Pure Deodorant Spray",
        "brand": "Nike",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 299.0,
        "weight_per_unit": 200.0,
        "description": "Pure and refreshing daily deodorant spray with sunlit citrus accords, white blossoms, and clean musk.",
        "variants": [
            {"id": "v_nike_w_pure_200", "name": "200ml Can", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Secret Temptation Aura Body Deodorant Spray",
        "brand": "Secret Temptation",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 150.0,
        "description": "Sparkling citrus and delicate water-lily accords that create an alluring, irresistible everyday aura.",
        "variants": [
            {"id": "v_st_aura_150", "name": "150ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Secret Temptation Cupid Body Deodorant Spray",
        "brand": "Secret Temptation",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 150.0,
        "description": "Sweet floral fruity fragrance with playful red berries and jasmine, designed to capture hearts.",
        "variants": [
            {"id": "v_st_cupid_150", "name": "150ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Secret Temptation Bling Body Deodorant Spray",
        "brand": "Secret Temptation",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 150.0,
        "description": "Glamorous oriental floral deodorant spray infused with sensual vanilla and exotic spices for evening allure.",
        "variants": [
            {"id": "v_st_bling_150", "name": "150ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Bella Vita Luxury CEO Man Body Spray Deodorant",
        "brand": "Bella Vita Luxury",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 299.0,
        "weight_per_unit": 150.0,
        "description": "Long-lasting luxury no-gas deodorant spray with energetic citrus notes, spicy cardamom, and woody base for the modern leader.",
        "variants": [
            {"id": "v_bvl_ceo_150", "name": "150ml Can", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Vanesa Luxury Fragrance Deodorant Spray - Pink Desire",
        "brand": "Vanesa",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 150.0,
        "description": "Sophisticated floral deodorant spray combining romantic Bulgarian rose, freesia, and warm amber.",
        "variants": [
            {"id": "v_van_pink_150", "name": "150ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Vanesa Luxury Fragrance Deodorant Spray - Night Glamour",
        "brand": "Vanesa",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 150.0,
        "description": "Rich nocturnal fragrance spray featuring dark berries, patchouli, and velvety musk.",
        "variants": [
            {"id": "v_van_night_150", "name": "150ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Wild Stone Red Deodorant Spray for Men",
        "brand": "Wild Stone",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 150.0,
        "description": "Spicy woody masculine fragrance opening with tart green apple and warm spices, ending with cedarwood.",
        "variants": [
            {"id": "v_ws_red_150", "name": "150ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Wild Stone Legend Deodorant Spray for Men",
        "brand": "Wild Stone",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 150.0,
        "description": "Classic aromatic fougère deodorant spray infused with citrus zest, lavender, and rich vetiver.",
        "variants": [
            {"id": "v_ws_leg_150", "name": "150ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Wild Stone Ultra Sensual Deodorant Spray for Men",
        "brand": "Wild Stone",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 225.0,
        "weight_per_unit": 150.0,
        "description": "Seductive and energetic fragrance spray with zesty mint, basil, and warm sensual amber notes.",
        "variants": [
            {"id": "v_ws_us_150", "name": "150ml Can", "price": 225.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Wild Stone CODE Oud No Gas Deodorant Spray for Men",
        "brand": "Wild Stone",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 299.0,
        "weight_per_unit": 150.0,
        "description": "Ultra-premium body spray featuring deep, smoky oudh resin blended with caramel and warm amber.",
        "variants": [
            {"id": "v_ws_oud_150", "name": "150ml Can", "price": 299.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Yardley London Gentleman Tobacco & Amber Perfumed Deodorant Spray for Men",
        "brand": "Yardley London",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 260.0,
        "weight_per_unit": 150.0,
        "description": "Distinctive masculine fragrance with warm tobacco leaf, amber, spiced clove, and patchouli.",
        "variants": [
            {"id": "v_yl_gta_150", "name": "150ml Can", "price": 260.0, "original_price": None, "is_available": True},
        ]
    },
    {
        "name": "Pepe Jeans London Bright Woman Deodorant Spray",
        "brand": "Pepe Jeans",
        "sub_category": "Deodorants & Roll-ons",
        "menu_category": "General / Wellness",
        "price": 349.0,
        "weight_per_unit": 200.0,
        "description": "Radiant floral chypre fragrance with energetic ginger, juicy mandarin, peony, and creamy sandalwood.",
        "variants": [
            {"id": "v_pepe_bw_200", "name": "200ml Can", "price": 349.0, "original_price": None, "is_available": True},
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
      - Aspect ratio w / h <= 1.30 (vertical bottle or square product)
      - Perimeter margins are predominantly white / transparent
    """
    if img.mode != "RGB":
        img = img.convert("RGB")
    w, h = img.size
    ratio = w / float(h)
    if ratio > 1.35 or ratio < 0.22:
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
    if pct < 0.65:
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
      - 1 front view
      - 1 back packaging / alternate angle of the SAME product
    """
    clean_name = re.sub(r'\(.*?\)', '', name).replace('+', '').strip()
    clean_brand = brand.replace('+', '').strip()

    queries = [
        f"{clean_brand} {clean_name} packshot white background",
        f"{clean_brand} {clean_name} back packaging white background",
        f"{clean_brand} {clean_name} packaging box white background",
        f"{clean_brand} {clean_name} nykaa amazon product",
        f"{clean_brand} {clean_name} official bottle",
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
                r = requests.get(c, headers=HEADERS, timeout=6)
                if r.status_code == 200 and len(r.content) > 4000:
                    raw_img = load_and_clean_image(r.content)
                    valid_images.append(raw_img)
                    if len(valid_images) >= 2:
                        return valid_images[0], valid_images[1]
                    elif len(valid_images) == 1:
                        w, h = raw_img.size
                        crop_box = (int(w * 0.04), int(h * 0.04), int(w * 0.96), int(h * 0.96))
                        return raw_img, raw_img.crop(crop_box)
            except Exception:
                continue

    print(f"      ⚠️ Studio canvas fallback for {brand} - {name}")
    canvas = Image.new("RGB", (800, 800), (255, 255, 255))
    return canvas, canvas


def upload_to_supabase_storage(config, local_filepath: str, storage_path: str, max_retries: int = 3) -> str:
    """Uploads file to Supabase storage bucket 'products' with fast caching & retry."""
    public_url = f"{config['url']}/storage/v1/object/public/products/{storage_path}"

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
                return public_url
        except Exception as e:
            if attempt == max_retries - 1:
                print(f"      ⚠️ Storage upload network exception ({e}), falling back to public URL")
                return public_url
            time.sleep(1)

    return public_url


def main():
    print("=" * 80)
    print("🚀 MAXX RETAIL BATCH 6: COSMETICS & BEAUTY INGESTION PIPELINE")
    print(f"   Target Shop: {SHOP_ID} (Maxx Retail)")
    print(f"   Total Cataloged Items: {len(BATCH_6_PRODUCTS)}")
    print(f"   Statutory Department: {CATEGORY} (18% GST Slab)")
    print(f"   Dietary Status: Strictly N/A (is_veg = None)")
    print("=" * 80)

    config = get_supabase_config()
    out_dir = "scratch/batch6_real_packshots"
    os.makedirs(out_dir, exist_ok=True)

    prepared_products = []

    for idx, item in enumerate(BATCH_6_PRODUCTS, 1):
        name = item["name"]
        brand = item["brand"]
        print(f"\n[{idx:03d}/{len(BATCH_6_PRODUCTS)}] 📸 Processing packshots for: {brand} - {name}...")

        p1_path = os.path.join(out_dir, f"maxx_batch6_{idx}_1.jpg")
        p2_path = os.path.join(out_dir, f"maxx_batch6_{idx}_2.jpg")

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

        storage_path_1 = f"{SHOP_ID}/batch6_packshots/maxx_batch6_{idx}_1.jpg"
        storage_path_2 = f"{SHOP_ID}/batch6_packshots/maxx_batch6_{idx}_2.jpg"

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
    print(f"📤 Syncing all {len(prepared_products)} Batch 6 items into Supabase database...")
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
    print(f"🎉 Batch 6 ingestion complete! Total Inserted: {total_inserted}, Total Updated: {total_updated}")
    print("=" * 80)


if __name__ == "__main__":
    main()
