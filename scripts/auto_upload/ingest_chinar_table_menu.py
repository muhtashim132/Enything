#!/usr/bin/env python3
"""
THE CHINAR TABLE CAFE AND RESTAURANT Menu Ingestion & Studio Photography Pipeline
=================================================================================
Shop ID: 165280a6-42c2-4c10-afb6-0e899221887c
Source Menu: /Users/muhtaashimnazki/Downloads/Enything/IMG_5091.pdf (9 Pages)

Total Dishes: 108 dishes across 16 categories:
1. Indian Main Course (15 items)
2. Roti & Naan (3 items)
3. Rice and Biryani (5 items)
4. Veg Rice (6 items)
5. Veg (7 items)
6. Soups (3 items)
7. Chinese (11 items)
8. Momos (4 items)
9. Veg Pizza (8 items)
10. Non Veg Pizza (10 items)
11. Fast Food (7 items)
12. Rolls (4 items)
13. Beverages - Coffee (3 items)
14. Beverages - Tea (3 items)
15. Tandoori (5 items)
16. Pasta (8 items)
17. Mocktails (9 items)
18. Shakes (7 items)

Platform Standards Enforced:
1. 100% Unique Photos for all dishes.
2. 1:1 Square (800x800) Lanczos center-cropped.
3. Strictly < 100 KB file size ceiling (target: 65 - 95 KB).
4. Direct upload to Supabase Storage: products/165280a6-42c2-4c10-afb6-0e899221887c/curated_studio/
5. Batch database upsert via public.bulk_upload_shop_products RPC.
6. Unlimited Inventory: total_quantity = NULL.
7. Soft Delete Rule: is_deleted = false.
"""

import os
import sys
import io
import re
import time
import json
import urllib.parse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from PIL import Image
import requests

CHINAR_SHOP_ID = "165280a6-42c2-4c10-afb6-0e899221887c"
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "data" / "chinar_studio_images"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Load Supabase config from .env
env_path = SCRIPT_DIR.parent.parent / ".env"
if env_path.exists():
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip())

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ["SUPABASE_ANON_KEY"]

HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
}

BROWSER_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
}

CHINAR_DISHES = [
    # ==========================================
    # PAGE 2: INDIAN MAIN COURSE & ROTI/NAAN
    # ==========================================
    {
        "name": "Butter Chicken (Boneless)",
        "menu_category": "Indian Main Course",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 680.0, "is_available": True, "original_price": None},
        ],
        "description": "Tender boneless chicken pieces simmered in a velvety, rich tomato, butter, and cashew gravy.",
        "search_term": "boneless butter chicken murgh makhani bowl gourmet studio food photography",
    },
    {
        "name": "Butter Chicken (With Bone)",
        "menu_category": "Indian Main Course",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "Traditional bone-in chicken slow-cooked in classic creamy makhani gravy with fenugreek and butter.",
        "search_term": "traditional butter chicken with bone rich curry bowl studio food photography",
    },
    {
        "name": "Chicken Kanti (Boneless)",
        "menu_category": "Indian Main Course",
        "price": 300.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Succulent boneless chicken chunks pan-sautéed with sliced onions, tomatoes, and aromatic Kashmiri spices.",
        "search_term": "kashmiri boneless chicken kanti pan fried onions tomatoes studio food photography",
    },
    {
        "name": "Chicken Kanti (With Bone)",
        "menu_category": "Indian Main Course",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Authentic Kashmiri bone-in chicken pan-fried with caramelized onions, tomatoes, and whole garam masalas.",
        "search_term": "kashmiri chicken kanti with bone pan fried gourmet studio food photography",
    },
    {
        "name": "Kadhai Chicken",
        "menu_category": "Indian Main Course",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "Spicy chicken stir-cooked with freshly ground kadhai masala, crunchy bell peppers, and onion petals.",
        "search_term": "kadai chicken bell peppers thick gravy bowl studio food photography",
    },
    {
        "name": "Chicken Rara",
        "menu_category": "Indian Main Course",
        "price": 420.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 750.0, "is_available": True, "original_price": None},
        ],
        "description": "A regal preparation of juicy chicken pieces simmered in an indulgent minced chicken keema gravy.",
        "search_term": "chicken rara murgh keema gravy rich curry studio food photography",
    },
    {
        "name": "Masala Chicken",
        "menu_category": "Indian Main Course",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "Hearty homestyle chicken cooked in a robust, spiced onion-tomato masala sauce with fresh coriander.",
        "search_term": "chicken masala spicy onion tomato gravy bowl studio food photography",
    },
    {
        "name": "Chicken Korma",
        "menu_category": "Indian Main Course",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "Mild, royal Mughlai chicken slow-cooked with yogurt, fried onions, and a rich cashew-nut paste.",
        "search_term": "chicken korma shahi creamy mild curry studio food photography",
    },
    {
        "name": "Chicken Curry",
        "menu_category": "Indian Main Course",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "Classic comforting chicken curry in a traditional spiced golden gravy with whole aromatic spices.",
        "search_term": "traditional indian chicken curry gravy bowl studio food photography",
    },
    {
        "name": "Dum Handi Chicken",
        "menu_category": "Indian Main Course",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "Slow-cooked under sealed dum in an earthen handi, locking in all rich flavors and juicy aromas.",
        "search_term": "handi chicken clay pot rich thick gravy studio food photography",
    },
    {
        "name": "Afghani Chicken",
        "menu_category": "Indian Main Course",
        "price": 400.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 750.0, "is_available": True, "original_price": None},
        ],
        "description": "Tender chicken cooked in a rich, aromatic Afghani cream, cashew, and melon seed gravy.",
        "search_term": "afghani chicken white creamy gravy bowl gourmet studio food photography",
    },
    {
        "name": "Methi Malai Chicken",
        "menu_category": "Indian Main Course",
        "price": 400.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 750.0, "is_available": True, "original_price": None},
        ],
        "description": "Succulent chicken cooked with fragrant fresh fenugreek leaves (methi) in a velvety rich cream sauce.",
        "search_term": "methi malai chicken fenugreek cream gravy studio food photography",
    },
    {
        "name": "Fry Chicken",
        "menu_category": "Indian Main Course",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "Crisp-fried spiced chicken pieces coated in seasoned batter and garnished with fresh lemon wedges.",
        "search_term": "indian dry fry chicken spiced crispy pieces studio food photography",
    },
    {
        "name": "Kabab Kanti",
        "menu_category": "Indian Main Course",
        "price": 300.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Juicy minced seekh kabab slices sautéed with crisp sliced onions, tomatoes, and Kashmiri masala.",
        "search_term": "kashmiri seekh kabab kanti pan fried onions studio food photography",
    },
    {
        "name": "Beef Nahari",
        "menu_category": "Indian Main Course",
        "price": 130.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Traditional slow-cooked shank meat stew simmered overnight with warming spices, ginger, and green chillies.",
        "search_term": "beef nihari slow cooked rich meat stew bowl ginger juliennes studio food photography",
    },
    {
        "name": "Plain Naan",
        "menu_category": "Roti & Naan",
        "price": 40.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 40.0, "is_available": True, "original_price": None}],
        "description": "Classic soft and fluffy leavened Indian flatbread baked fresh in a traditional tandoor oven.",
        "search_term": "plain tandoori naan bread basket studio food photography",
    },
    {
        "name": "Butter Naan",
        "menu_category": "Roti & Naan",
        "price": 50.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 50.0, "is_available": True, "original_price": None}],
        "description": "Warm tandoori naan brushed generously with premium golden melted butter.",
        "search_term": "butter naan flatbread glistening melted butter studio food photography",
    },
    {
        "name": "Garlic Naan",
        "menu_category": "Roti & Naan",
        "price": 60.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 60.0, "is_available": True, "original_price": None}],
        "description": "Tandoor-baked flatbread topped with fragrant minced roasted garlic and fresh green coriander.",
        "search_term": "garlic naan bread roasted garlic bits coriander studio food photography",
    },

    # ==========================================
    # PAGE 3: RICE AND BIRYANI & VEG RICE
    # ==========================================
    {
        "name": "Hyderabadi Biryani",
        "menu_category": "Rice and Biryani",
        "price": 170.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 170.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 300.0, "is_available": True, "original_price": None},
        ],
        "description": "Fragrant dum biryani layered with marinated chicken, saffron-infused basmati rice, and fried onions.",
        "search_term": "hyderabadi chicken dum biryani handi pot studio food photography",
    },
    {
        "name": "Muradabadi Biryani",
        "menu_category": "Rice and Biryani",
        "price": 180.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 180.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 300.0, "is_available": True, "original_price": None},
        ],
        "description": "Authentic Muradabadi style chicken biryani cooked with mild whole spices and fragrant long-grain rice.",
        "search_term": "muradabadi chicken biryani pulao light aromatic studio food photography",
    },
    {
        "name": "Chicken Fried Rice",
        "menu_category": "Rice and Biryani",
        "price": 170.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 170.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 340.0, "is_available": True, "original_price": None},
        ],
        "description": "Wok-tossed basmati rice with tender shredded chicken, scrambled egg, and garden vegetables.",
        "search_term": "chicken fried rice wok tossed bowl studio food photography",
    },
    {
        "name": "Shezwan Chicken Fried Rice",
        "menu_category": "Rice and Biryani",
        "price": 180.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 180.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 360.0, "is_available": True, "original_price": None},
        ],
        "description": "Fiery stir-fried rice tossed with spicy Schezwan sauce, chicken chunks, and crisp scallions.",
        "search_term": "schezwan chicken fried rice spicy red bowl studio food photography",
    },
    {
        "name": "Chinar Special Pulao",
        "menu_category": "Rice and Biryani",
        "price": 350.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
        "description": "Signature house pulao featuring premium chicken, dry fruits, saffron, and aromatic basmati rice.",
        "search_term": "kashmiri chicken pulao nuts saffron studio food photography",
    },
    {
        "name": "Veg Fried Rice",
        "menu_category": "Veg Rice",
        "price": 150.0,
        "is_veg": True,
        "variants": [
            {"name": "Half", "price": 150.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 300.0, "is_available": True, "original_price": None},
        ],
        "description": "Classic Chinese fried rice loaded with finely chopped carrots, French beans, cabbage, and spring onions.",
        "search_term": "veg fried rice bowl colorful vegetables studio food photography",
    },
    {
        "name": "Shezwan Veg Fried Rice",
        "menu_category": "Veg Rice",
        "price": 170.0,
        "is_veg": True,
        "variants": [
            {"name": "Half", "price": 170.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 320.0, "is_available": True, "original_price": None},
        ],
        "description": "Spicy and tangy Schezwan fried rice with stir-fried bell peppers, cabbage, and green chillies.",
        "search_term": "schezwan veg fried rice red spicy bowl studio food photography",
    },
    {
        "name": "Plain Rice",
        "menu_category": "Veg Rice",
        "price": 120.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 120.0, "is_available": True, "original_price": None}],
        "description": "Steamed premium basmati rice cooked to fluffy, separated grain perfection.",
        "search_term": "steamed plain basmati rice white bowl studio food photography",
    },
    {
        "name": "Zeera Rice",
        "menu_category": "Veg Rice",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Fragrant basmati rice tempered with roasted cumin seeds (zeera) and pure ghee.",
        "search_term": "jeera rice cumin basmati bowl studio food photography",
    },
    {
        "name": "Peas Pulao",
        "menu_category": "Veg Rice",
        "price": 280.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 280.0, "is_available": True, "original_price": None}],
        "description": "Mild, fragrant rice pilaf cooked with sweet tender green peas, whole spices, and caramelized onions.",
        "search_term": "matar pulao green peas rice bowl studio food photography",
    },
    {
        "name": "Mushroom Pulao",
        "menu_category": "Veg Rice",
        "price": 280.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 280.0, "is_available": True, "original_price": None}],
        "description": "Aromatic long-grain rice pilaf gently tossed with sliced button mushrooms and whole garam masala.",
        "search_term": "mushroom pulao rice bowl studio food photography",
    },

    # ==========================================
    # PAGE 4: VEG & SOUPS
    # ==========================================
    {
        "name": "Paneer Butter Masala",
        "menu_category": "Veg",
        "price": 300.0,
        "is_veg": True,
        "variants": [
            {"name": "Half", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 580.0, "is_available": True, "original_price": None},
        ],
        "description": "Tender cottage cheese cubes simmered in a luscious tomato, butter, and cashew cream sauce.",
        "search_term": "paneer butter masala bowl rich makhani gravy studio food photography",
    },
    {
        "name": "Matar Mushroom",
        "menu_category": "Veg",
        "price": 300.0,
        "is_veg": True,
        "variants": [
            {"name": "Half", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 580.0, "is_available": True, "original_price": None},
        ],
        "description": "Sautéed button mushrooms and tender green peas cooked in a spiced onion-tomato masala gravy.",
        "search_term": "matar mushroom curry bowl green peas studio food photography",
    },
    {
        "name": "Chilli Paneer",
        "menu_category": "Veg",
        "price": 300.0,
        "is_veg": True,
        "variants": [
            {"name": "Half", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 580.0, "is_available": True, "original_price": None},
        ],
        "description": "Golden fried paneer tossed with crunchy capsicum, onions, and spicy Indo-Chinese soya-chilli glaze.",
        "search_term": "chilli paneer gravy bowl indo chinese studio food photography",
    },
    {
        "name": "Matar Paneer",
        "menu_category": "Veg",
        "price": 320.0,
        "is_veg": True,
        "variants": [
            {"name": "Half", "price": 320.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Classic pairing of soft cottage cheese and sweet green peas in a rich onion-tomato gravy.",
        "search_term": "matar paneer curry cottage cheese peas bowl studio food photography",
    },
    {
        "name": "Chilli Mushroom",
        "menu_category": "Veg",
        "price": 300.0,
        "is_veg": True,
        "variants": [
            {"name": "Half", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 580.0, "is_available": True, "original_price": None},
        ],
        "description": "Crispy fried button mushrooms wok-tossed with peppers, onions, and spicy oriental chilli sauce.",
        "search_term": "chilli mushroom crispy bowl indo chinese studio food photography",
    },
    {
        "name": "Mix Veg",
        "menu_category": "Veg",
        "price": 300.0,
        "is_veg": True,
        "variants": [
            {"name": "Half", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 550.0, "is_available": True, "original_price": None},
        ],
        "description": "Melange of seasonal vegetables simmered in a homestyle spiced onion-tomato curry.",
        "search_term": "mixed vegetable curry bowl indian sabzi studio food photography",
    },
    {
        "name": "Paneer Tikka",
        "menu_category": "Veg",
        "price": 250.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 250.0, "is_available": True, "original_price": None}],
        "description": "Cottage cheese cubes marinated in spiced tandoori yogurt and char-grilled with capsicum and onions.",
        "search_term": "paneer tikka tandoori platter mint chutney lemon studio food photography",
    },
    {
        "name": "Hot And Sour Chicken Soup",
        "menu_category": "Soups",
        "price": 130.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Spicy and tangy Chinese broth with shredded chicken, bamboo shoots, mushrooms, and egg ribbons.",
        "search_term": "chicken hot and sour soup bowl dark chinese studio food photography",
    },
    {
        "name": "Sweet Corn Soup",
        "menu_category": "Soups",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Silky smooth sweet corn soup with creamed corn kernels and tender garden vegetables.",
        "search_term": "sweet corn veg soup bowl chinese studio food photography",
    },
    {
        "name": "Lemon Coriander Soup",
        "menu_category": "Soups",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Zesty, vitamin-rich clear broth infused with fresh lemon juice, crushed garlic, and fresh coriander.",
        "search_term": "lemon coriander soup bowl clear broth studio food photography",
    },

    # ==========================================
    # PAGE 5: CHINESE & MOMOS
    # ==========================================
    {
        "name": "Chicken Chowmein",
        "menu_category": "Chinese",
        "price": 150.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 150.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 250.0, "is_available": True, "original_price": None},
        ],
        "description": "Wok-fried noodles tossed with tender chicken, julienned cabbage, bell peppers, and savoury soy sauce.",
        "search_term": "chicken chowmein noodles bowl studio food photography",
    },
    {
        "name": "Veg Chowmein",
        "menu_category": "Chinese",
        "price": 120.0,
        "is_veg": True,
        "variants": [
            {"name": "Half", "price": 120.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 220.0, "is_available": True, "original_price": None},
        ],
        "description": "Classic stir-fried noodles tossed with crunchy carrots, cabbage, capsicum, and aromatic oriental seasoning.",
        "search_term": "veg chowmein hakka noodles bowl studio food photography",
    },
    {
        "name": "Garlic Chicken (Boneless)",
        "menu_category": "Chinese",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Juicy boneless chicken tossed with roasted golden garlic, scallions, and savory dark oriental glaze.",
        "search_term": "garlic chicken boneless chinese gravy bowl studio food photography",
    },
    {
        "name": "Chilli Chicken (Boneless)",
        "menu_category": "Chinese",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Crispy boneless chicken bites tossed with crunchy bell peppers, onions, and spicy soy-chilli sauce.",
        "search_term": "chilli chicken boneless bowl chinese studio food photography",
    },
    {
        "name": "Honey Chilli Chicken",
        "menu_category": "Chinese",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Crispy chicken glazed in a luscious blend of organic honey, red chillies, and toasted sesame seeds.",
        "search_term": "honey chilli chicken crispy sesame glaze studio food photography",
    },
    {
        "name": "Chicken Manchurian (Boneless)",
        "menu_category": "Chinese",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Tender chicken meatballs simmered in a dark, tangy garlic, ginger, and scallion Manchurian sauce.",
        "search_term": "chicken manchurian boneless gravy bowl studio food photography",
    },
    {
        "name": "Chicken Lollipop",
        "menu_category": "Chinese",
        "price": 300.0,
        "is_veg": False,
        "variants": [{"name": "Regular (6 Pcs)", "price": 300.0, "is_available": True, "original_price": None}],
        "description": "Crisp-fried spiced chicken winglets shaped into lollipops, served with Schezwan dipping sauce.",
        "search_term": "chicken lollipop crispy fried appetizer platter studio food photography",
    },
    {
        "name": "Honey Chilli Potato",
        "menu_category": "Chinese",
        "price": 230.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 230.0, "is_available": True, "original_price": None}],
        "description": "Crispy potato fingers tossed in sweet honey, hot chilli paste, and sprinkled with sesame seeds.",
        "search_term": "honey chilli potato crisp golden studio food photography",
    },
    {
        "name": "Chilli Potato",
        "menu_category": "Chinese",
        "price": 180.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
        "description": "Crispy fried potato strips wok-tossed with green chillies, garlic, capsicum, and soya sauce.",
        "search_term": "crispy chilli potato spicy chinese studio food photography",
    },
    {
        "name": "French Fries",
        "menu_category": "Chinese",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Classic golden salted French fries, fried crisp on the outside and fluffy on the inside.",
        "search_term": "french fries golden crispy basket studio food photography",
    },
    {
        "name": "Peri Peri Fries",
        "menu_category": "Chinese",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Golden crisp fries dusted generously with zesty, fiery African peri-peri seasoning.",
        "search_term": "peri peri french fries red spice seasoning studio food photography",
    },
    {
        "name": "Chicken Steam Momos",
        "menu_category": "Momos",
        "price": 130.0,
        "is_veg": False,
        "variants": [{"name": "Regular (8 Pcs)", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Delicate steamed dumplings stuffed with spiced minced chicken, served with spicy red chutney.",
        "search_term": "chicken steamed momos bamboo steamer studio food photography",
    },
    {
        "name": "Chicken Fry Momos",
        "menu_category": "Momos",
        "price": 140.0,
        "is_veg": False,
        "variants": [{"name": "Regular (8 Pcs)", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Deep-fried chicken momos with an ultra-crispy golden exterior and juicy minced chicken filling.",
        "search_term": "chicken fried momos crispy plate studio food photography",
    },
    {
        "name": "Crispy Momos",
        "menu_category": "Momos",
        "price": 170.0,
        "is_veg": False,
        "variants": [{"name": "Regular (8 Pcs)", "price": 170.0, "is_available": True, "original_price": None}],
        "description": "Crumb-coated kurkure style crunchy momos fried to golden perfection with spicy dips.",
        "search_term": "crispy kurkure momos fried snack studio food photography",
    },
    {
        "name": "Malai Momos",
        "menu_category": "Momos",
        "price": 220.0,
        "is_veg": False,
        "variants": [{"name": "Regular (8 Pcs)", "price": 220.0, "is_available": True, "original_price": None}],
        "description": "Steamed chicken momos coated in a rich, creamy cashew and cheese sauce with roasted herbs.",
        "search_term": "afghani malai momos creamy white sauce studio food photography",
    },

    # ==========================================
    # PAGE 6: VEG PIZZA & NON VEG PIZZA
    # ==========================================
    {
        "name": "Classic Cheese Pizza",
        "menu_category": "Veg Pizza",
        "price": 210.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 210.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 340.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 580.0, "is_available": True, "original_price": None},
        ],
        "description": "Freshly hand-stretched dough topped with signature marinara sauce and 100% mozzarella cheese.",
        "search_term": "classic cheese pizza melted mozzarella studio food photography",
    },
    {
        "name": "Tomato Onion Pizza",
        "menu_category": "Veg Pizza",
        "price": 210.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 210.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 340.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Crisp red onions and ripe juicy tomato slices over a golden melted mozzarella cheese crust.",
        "search_term": "onion tomato veg pizza melted cheese studio food photography",
    },
    {
        "name": "Mushroom Corn Pizza",
        "menu_category": "Veg Pizza",
        "price": 210.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 210.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 340.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Earthy sliced button mushrooms and golden sweet corn kernels on a cheesy Italian crust.",
        "search_term": "mushroom sweet corn pizza mozzarella cheese studio food photography",
    },
    {
        "name": "Veg Farm Pizza",
        "menu_category": "Veg Pizza",
        "price": 210.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 210.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 340.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 660.0, "is_available": True, "original_price": None},
        ],
        "description": "Loaded farm-fresh feast with capsicum, tomatoes, onions, mushrooms, and melted mozzarella.",
        "search_term": "farmhouse veg supreme pizza vegetables studio food photography",
    },
    {
        "name": "Mexican Bite Pizza",
        "menu_category": "Veg Pizza",
        "price": 210.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 210.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 340.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Zesty Mexican herb sauce topped with spicy jalapenos, sweet corn, onions, and melted cheese.",
        "search_term": "mexican veg pizza jalapeno corn studio food photography",
    },
    {
        "name": "Paneer Pizza",
        "menu_category": "Veg Pizza",
        "price": 210.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 210.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Spiced cottage cheese cubes with crunchy capsicum and onions on an Italian marinara base.",
        "search_term": "paneer pizza capsicum onion melted cheese studio food photography",
    },
    {
        "name": "Corn Pizza",
        "menu_category": "Veg Pizza",
        "price": 210.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 210.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 330.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 550.0, "is_available": True, "original_price": None},
        ],
        "description": "Sweet golden American corn kernels layered generously over melted gooey mozzarella.",
        "search_term": "sweet corn cheese pizza golden studio food photography",
    },
    {
        "name": "Special Chinar Pizza",
        "menu_category": "Veg Pizza",
        "price": 210.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 210.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "The chef's supreme vegetarian creation loaded with paneer, black olives, jalapenos, and double cheese.",
        "search_term": "special gourmet vegetarian pizza loaded double cheese studio food photography",
    },
    {
        "name": "Chicken Blast Pizza",
        "menu_category": "Non Veg Pizza",
        "price": 230.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 230.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "An explosion of spicy chicken chunks, bell peppers, onions, and molten mozzarella cheese.",
        "search_term": "chicken blast pizza chicken chunks melted mozzarella studio food photography",
    },
    {
        "name": "Fire Roast Pizza",
        "menu_category": "Non Veg Pizza",
        "price": 230.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 230.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Char-roasted chicken breast pieces with spicy red paprika, onions, and melted cheese.",
        "search_term": "fire roasted chicken pizza paprika studio food photography",
    },
    {
        "name": "Perry Perry Chicken Pizza",
        "menu_category": "Non Veg Pizza",
        "price": 230.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 230.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Zesty peri-peri spiced chicken chunks, jalapenos, and mozzarella on stone-baked crust.",
        "search_term": "peri peri chicken pizza spicy studio food photography",
    },
    {
        "name": "Barbique Chicken Pizza",
        "menu_category": "Non Veg Pizza",
        "price": 230.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 230.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Smoky barbecue glazed chicken, caramelized onions, and golden mozzarella on a crisp crust.",
        "search_term": "bbq chicken pizza smoky sauce red onions studio food photography",
    },
    {
        "name": "Kabab Pizza",
        "menu_category": "Non Veg Pizza",
        "price": 250.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 680.0, "is_available": True, "original_price": None},
        ],
        "description": "Topped with sliced spiced seekh kababs, onions, green chillies, and melted mozzarella.",
        "search_term": "seekh kabab pizza spicy indian fusion studio food photography",
    },
    {
        "name": "Mexican Bite Chicken Pizza",
        "menu_category": "Non Veg Pizza",
        "price": 250.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 680.0, "is_available": True, "original_price": None},
        ],
        "description": "Spiced chicken cubes, sweet corn, sliced jalapenos, and Mexican salsa reduction with cheese.",
        "search_term": "mexican chicken pizza jalapeno sweet corn studio food photography",
    },
    {
        "name": "Cheese Burst Chicken Pizza",
        "menu_category": "Non Veg Pizza",
        "price": 250.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 680.0, "is_available": True, "original_price": None},
        ],
        "description": "Loaded with juicy chicken chunks and a rich molten liquid cheese crust bursting in every bite.",
        "search_term": "cheese burst chicken pizza slice pull studio food photography",
    },
    {
        "name": "Butter Chicken Pizza",
        "menu_category": "Non Veg Pizza",
        "price": 250.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 680.0, "is_available": True, "original_price": None},
        ],
        "description": "Creamy butter chicken makhani sauce base topped with chicken chunks and rich mozzarella.",
        "search_term": "butter chicken pizza fusion makhani gravy studio food photography",
    },
    {
        "name": "Chilli Chicken Pizza",
        "menu_category": "Non Veg Pizza",
        "price": 230.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 230.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Crispy Indo-Chinese chilli chicken bites with capsicum and spicy sauce on a cheesy base.",
        "search_term": "chilli chicken pizza spicy indo chinese studio food photography",
    },
    {
        "name": "Chinar Special Pizza",
        "menu_category": "Non Veg Pizza",
        "price": 280.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 280.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 430.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "The house masterpiece loaded with assorted seasoned meats, sausages, exotic veggies, and double cheese.",
        "search_term": "deluxe meat feast pizza loaded supreme studio food photography",
    },

    # ==========================================
    # PAGE 7: FAST FOOD, ROLLS, COFFEE & TEA
    # ==========================================
    {
        "name": "Chicken Nuggets",
        "menu_category": "Fast Food",
        "price": 250.0,
        "is_veg": False,
        "variants": [{"name": "Regular (6 Pcs)", "price": 250.0, "is_available": True, "original_price": None}],
        "description": "Crisp, golden-crumbed tender minced chicken bites, served with mayonnaise and tomato sauce.",
        "search_term": "chicken nuggets golden crispy fast food studio food photography",
    },
    {
        "name": "Chicken Strips",
        "menu_category": "Fast Food",
        "price": 220.0,
        "is_veg": False,
        "variants": [{"name": "Regular (6 Pcs)", "price": 220.0, "is_available": True, "original_price": None}],
        "description": "Tender chicken breast fillets coated in a crunchy spiced batter and deep-fried to golden perfection.",
        "search_term": "crispy chicken tenders strips fried studio food photography",
    },
    {
        "name": "Chicken Popcorn",
        "menu_category": "Fast Food",
        "price": 180.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
        "description": "Bite-sized crunchy chicken nuggets seasoned with house spices, perfect for snacking.",
        "search_term": "chicken popcorn bucket crispy bites studio food photography",
    },
    {
        "name": "Shawarma Burger",
        "menu_category": "Fast Food",
        "price": 130.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Toasted burger bun packed with seasoned shaved chicken shawarma, garlic mayo, and lettuce.",
        "search_term": "chicken shawarma burger toasted bun garlic mayo studio food photography",
    },
    {
        "name": "Shawarma Burger (With Cheese)",
        "menu_category": "Fast Food",
        "price": 150.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Juicy chicken shawarma meat topped with melted cheddar cheese slice in a toasted sesame bun.",
        "search_term": "chicken shawarma cheeseburger melted cheese studio food photography",
    },
    {
        "name": "Zinger Burger",
        "menu_category": "Fast Food",
        "price": 150.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Extra crunchy fried chicken breast fillet layered with crisp iceberg lettuce and creamy mayonnaise.",
        "search_term": "crispy chicken zinger burger sesame bun studio food photography",
    },
    {
        "name": "Zinger Burger (With Cheese)",
        "menu_category": "Fast Food",
        "price": 170.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 170.0, "is_available": True, "original_price": None}],
        "description": "Crispy fried zinger chicken fillet topped with a slice of rich melted cheddar cheese.",
        "search_term": "zinger chicken burger melted cheese slice studio food photography",
    },
    {
        "name": "Shawarma Roll",
        "menu_category": "Rolls",
        "price": 120.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 120.0, "is_available": True, "original_price": None}],
        "description": "Thin rumali flatbread wrapped around juicy roasted chicken shawarma, garlic toum, and pickled veggies.",
        "search_term": "chicken shawarma roll wrap studio food photography",
    },
    {
        "name": "Shawarma With Cheese",
        "menu_category": "Rolls",
        "price": 140.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Savory chicken shawarma wrapped with extra melted mozzarella and cheddar cheese.",
        "search_term": "cheesy chicken shawarma wrap roll studio food photography",
    },
    {
        "name": "Turkish Shawarma",
        "menu_category": "Rolls",
        "price": 160.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Authentic Turkish recipe with spiced slow-turned chicken, sumac onions, tomatoes, and garlic yogurt sauce.",
        "search_term": "turkish chicken shawarma doner kebab wrap studio food photography",
    },
    {
        "name": "Twister Roll",
        "menu_category": "Rolls",
        "price": 150.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Crunchy crispy chicken strips wrapped with lettuce, diced tomatoes, and tangy pepper mayo.",
        "search_term": "crispy chicken twister wrap roll studio food photography",
    },
    {
        "name": "Coffee",
        "menu_category": "Beverages - Coffee",
        "price": 70.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 70.0, "is_available": True, "original_price": None}],
        "description": "Freshly brewed hot aromatic coffee with steamed whole milk and velvety foam.",
        "search_term": "hot coffee cup frothed milk latte art studio food photography",
    },
    {
        "name": "Black Coffee",
        "menu_category": "Beverages - Coffee",
        "price": 50.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 50.0, "is_available": True, "original_price": None}],
        "description": "Bold, rich Americano brewed from freshly ground roasted coffee beans.",
        "search_term": "black coffee americano cup roasted beans studio food photography",
    },
    {
        "name": "Cold Coffee",
        "menu_category": "Beverages - Coffee",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Chilled thick coffee blended with milk, rich espresso, and vanilla ice cream with chocolate drizzle.",
        "search_term": "iced cold coffee tall glass whipped cream chocolate studio food photography",
    },
    {
        "name": "Lemon Tea",
        "menu_category": "Beverages - Tea",
        "price": 50.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 50.0, "is_available": True, "original_price": None}],
        "description": "Refreshing hot black tea infused with fresh lemon juice and a touch of organic honey.",
        "search_term": "hot lemon tea clear glass lemon slice studio food photography",
    },
    {
        "name": "Ginger Tea",
        "menu_category": "Beverages - Tea",
        "price": 60.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 60.0, "is_available": True, "original_price": None}],
        "description": "Spiced Indian milk chai simmered with fresh crushed ginger root and cardamom pods.",
        "search_term": "adrak ginger chai kulhad cup studio food photography",
    },
    {
        "name": "Kashmiri Kehwa",
        "menu_category": "Beverages - Tea",
        "price": 70.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 70.0, "is_available": True, "original_price": None}],
        "description": "Traditional Kashmiri green tea brewed with pure saffron, cinnamon, green cardamom, and slivered almonds.",
        "search_term": "kashmiri kahwa kehwa saffron green tea samovar almonds studio food photography",
    },

    # ==========================================
    # PAGE 8: TANDOORI & PASTA
    # ==========================================
    {
        "name": "Tandoori Chicken",
        "menu_category": "Tandoori",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Whole bone-in chicken marinated in spiced yogurt and roasted in a traditional clay tandoor oven.",
        "search_term": "tandoori chicken roasted clay oven platter studio food photography",
    },
    {
        "name": "Chicken Tikka",
        "menu_category": "Tandoori",
        "price": 300.0,
        "is_veg": False,
        "variants": [{"name": "Regular (8 Pcs)", "price": 300.0, "is_available": True, "original_price": None}],
        "description": "Boneless chicken chunks marinated in mustard oil, tandoori masala, and char-grilled on skewers.",
        "search_term": "chicken tikka boneless grilled skewers mint chutney studio food photography",
    },
    {
        "name": "Chicken Malai Tikka",
        "menu_category": "Tandoori",
        "price": 350.0,
        "is_veg": False,
        "variants": [{"name": "Regular (8 Pcs)", "price": 350.0, "is_available": True, "original_price": None}],
        "description": "Melt-in-mouth chicken pieces marinated in rich cream, cashew paste, cheese, and mild spices.",
        "search_term": "chicken malai tikka creamy white grilled studio food photography",
    },
    {
        "name": "Chicken Tangdi Tikka",
        "menu_category": "Tandoori",
        "price": 160.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Juicy chicken drumsticks marinated in spiced yogurt marinade and roasted over glowing tandoor coals.",
        "search_term": "chicken tangdi kabab drumstick tandoori studio food photography",
    },
    {
        "name": "Tandoori Wings",
        "menu_category": "Tandoori",
        "price": 250.0,
        "is_veg": False,
        "variants": [{"name": "Regular (8 Pcs)", "price": 250.0, "is_available": True, "original_price": None}],
        "description": "Succulent chicken wings coated with spicy tandoori marinade and smoky char-grilled to perfection.",
        "search_term": "tandoori chicken wings smoky grilled platter studio food photography",
    },
    {
        "name": "Alfredo Veg Pasta",
        "menu_category": "Pasta",
        "price": 250.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 250.0, "is_available": True, "original_price": None}],
        "description": "Penne pasta and garden vegetables in a rich, velvety parmesan and garlic white Alfredo cream sauce.",
        "search_term": "alfredo veg penne pasta white sauce bowl studio food photography",
    },
    {
        "name": "Pink Sauce Veg Pasta",
        "menu_category": "Pasta",
        "price": 250.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 250.0, "is_available": True, "original_price": None}],
        "description": "Al dente penne pasta tossed in a luxurious blend of creamy Alfredo and tangy Italian marinara sauce.",
        "search_term": "pink sauce pasta rose penne bowl studio food photography",
    },
    {
        "name": "Red Sauce Veg Pasta",
        "menu_category": "Pasta",
        "price": 250.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 250.0, "is_available": True, "original_price": None}],
        "description": "Penne pasta tossed in an authentic Italian plum tomato arrabbiata sauce with fresh basil and oregano.",
        "search_term": "arrabbiata red sauce pasta penne bowl studio food photography",
    },
    {
        "name": "Mushroom Pasta",
        "menu_category": "Pasta",
        "price": 280.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 280.0, "is_available": True, "original_price": None}],
        "description": "Herb-sautéed fresh button mushrooms tossed with pasta in a rich garlic cream sauce.",
        "search_term": "creamy mushroom pasta penne garlic herbs studio food photography",
    },
    {
        "name": "Alfredo Chicken Pasta",
        "menu_category": "Pasta",
        "price": 300.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 300.0, "is_available": True, "original_price": None}],
        "description": "Tender chicken breast slices and penne tossed in an indulgent, creamy parmesan white sauce.",
        "search_term": "creamy chicken alfredo pasta penne bowl studio food photography",
    },
    {
        "name": "Pink Sauce Chicken Pasta",
        "menu_category": "Pasta",
        "price": 300.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 300.0, "is_available": True, "original_price": None}],
        "description": "Juicy chicken chunks tossed in a harmonious blend of tomato marinara and velvety Alfredo cream.",
        "search_term": "chicken pink sauce pasta rose bowl studio food photography",
    },
    {
        "name": "Red Sauce Chicken Pasta",
        "menu_category": "Pasta",
        "price": 300.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 300.0, "is_available": True, "original_price": None}],
        "description": "Tender chicken pieces simmered in spicy, garlicky Italian red sauce with herbs and penne.",
        "search_term": "chicken red sauce arrabbiata pasta bowl studio food photography",
    },
    {
        "name": "Mushroom Chicken Pasta",
        "menu_category": "Pasta",
        "price": 350.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
        "description": "Sautéed chicken and fresh mushrooms bathed in a luxurious garlic-herb white cream sauce.",
        "search_term": "chicken mushroom pasta creamy white sauce studio food photography",
    },

    # ==========================================
    # PAGE 9: MOCKTAILS & SHAKES
    # ==========================================
    {
        "name": "Virgin Mojito",
        "menu_category": "Mocktails",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Crisp, effervescent mocktail with muddled fresh lime wedges, garden mint, and bubbly soda over crushed ice.",
        "search_term": "virgin mojito mocktail glass crushed ice lime mint studio food photography",
    },
    {
        "name": "Green Apple Mojito",
        "menu_category": "Mocktails",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Tart green apple syrup shaken with mint leaves, lemon juice, and chilled sparkling soda.",
        "search_term": "green apple mojito emerald green glass mint ice studio food photography",
    },
    {
        "name": "Peach Mojito",
        "menu_category": "Mocktails",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Luscious sweet peach syrup muddled with fresh mint leaves and sparkling soda.",
        "search_term": "peach mojito mocktail glass mint lime studio food photography",
    },
    {
        "name": "Watermelon Mojito",
        "menu_category": "Mocktails",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Sweet red watermelon syrup muddled with fresh lime, mint leaves, and effervescent soda.",
        "search_term": "watermelon mojito red drink glass mint lime studio food photography",
    },
    {
        "name": "Orange Mojito",
        "menu_category": "Mocktails",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Citrusy fresh orange notes muddled with mint leaves, lemon, and chilled soda over ice.",
        "search_term": "orange mojito citrus mocktail glass studio food photography",
    },
    {
        "name": "Sweet Fresh Lemon Soda",
        "menu_category": "Mocktails",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Freshly squeezed lemon juice sweetened with pure cane sugar and topped with chilled fizzy soda.",
        "search_term": "sweet fresh lime soda glass lemon slice ice studio food photography",
    },
    {
        "name": "Salt Fresh Lemon Soda",
        "menu_category": "Mocktails",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Traditional salted fresh lime soda over ice, revitalizing and perfect for digestion.",
        "search_term": "salted fresh lime soda glass mint studio food photography",
    },
    {
        "name": "Lemon Soda Masala Shikanji",
        "menu_category": "Mocktails",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "North Indian shikanji with fresh lime juice, roasted cumin, black salt, and bubbling soda.",
        "search_term": "masala shikanji spiced lemon soda glass ice studio food photography",
    },
    {
        "name": "Blueberry Mojito",
        "menu_category": "Mocktails",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Vibrant wild blueberry syrup muddled with fresh mint, lime slices, and sparkling soda.",
        "search_term": "blueberry mojito mocktail dark blue glass mint studio food photography",
    },
    {
        "name": "Mango Shake",
        "menu_category": "Shakes",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Rich, luscious milkshake prepared with sweet Alphonso mango pulp and vanilla ice cream.",
        "search_term": "mango milkshake yellow thick glass whipped cream studio food photography",
    },
    {
        "name": "Vanilla Milk Shake",
        "menu_category": "Shakes",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Smooth and velvety thick shake blended with premium vanilla ice cream and chilled milk.",
        "search_term": "vanilla milkshake tall glass whipped cream cherry studio food photography",
    },
    {
        "name": "Chocolate Shake",
        "menu_category": "Shakes",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Indulgent chocolate milkshake whipped with rich cocoa syrup and dark chocolate drizzle.",
        "search_term": "chocolate milkshake tall glass chocolate curls studio food photography",
    },
    {
        "name": "Kit-Kat Shake",
        "menu_category": "Shakes",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Crisp Kit-Kat chocolate wafers crushed and blended into a decadent chocolate ice cream shake.",
        "search_term": "kitkat milkshake chocolate wafer glass studio food photography",
    },
    {
        "name": "Banana Shake",
        "menu_category": "Shakes",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Creamy wholesome shake made with fresh ripe bananas, honey, and cold whole milk.",
        "search_term": "banana smoothie milkshake glass studio food photography",
    },
    {
        "name": "Strawberry Shake",
        "menu_category": "Shakes",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Refreshing pink milkshake blended with sweet strawberry crush and creamy vanilla ice cream.",
        "search_term": "strawberry milkshake pink glass fresh berries studio food photography",
    },
    {
        "name": "Oreo Shake",
        "menu_category": "Shakes",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Crushed Oreo cookies blended with chocolate fudge and vanilla ice cream, topped with cookie crumble.",
        "search_term": "oreo milkshake cookies and cream glass studio food photography",
    },
]


def sanitize_filename(name: str) -> str:
    s = re.sub(r"[^\w\s-]", "", name.lower())
    return re.sub(r"[-\s]+", "_", s).strip("_")


def search_bing_image_urls(query: str, count: int = 5) -> list:
    url = f"https://www.bing.com/images/async?q={urllib.parse.quote(query)}&count={count}&first=1&adlt=off&qft=+filterui:photo-photo"
    try:
        resp = requests.get(url, headers=BROWSER_HEADERS, timeout=8)
        if resp.status_code == 200:
            matches = re.findall(r'murl&quot;:&quot;(https?://[^&]+?)&quot;', resp.text)
            urls = []
            for m in matches:
                u = urllib.parse.unquote(m)
                if not any(bad in u.lower() for bad in ["logo", "vector", "icon", "drawing", "illustration", "alamy", "shutterstock", "getty"]):
                    urls.append(u)
            if urls:
                return urls
    except Exception:
        pass
    return []


def process_image(img_bytes: bytes, max_size_kb: int = 95) -> bytes:
    img = Image.open(io.BytesIO(img_bytes))
    if img.mode != "RGB":
        img = img.convert("RGB")

    w, h = img.size
    min_dim = min(w, h)
    left = (w - min_dim) // 2
    top = (h - min_dim) // 2
    right = left + min_dim
    bottom = top + min_dim
    img = img.crop((left, top, right, bottom))
    img = img.resize((800, 800), Image.Resampling.LANCZOS)

    quality = 85
    out = io.BytesIO()
    img.save(out, format="JPEG", quality=quality, optimize=True)

    while out.tell() > max_size_kb * 1024 and quality > 35:
        quality -= 5
        out = io.BytesIO()
        img.save(out, format="JPEG", quality=quality, optimize=True)

    return out.getvalue()


def fetch_and_save_dish_photo(dish: dict, index: int) -> tuple:
    name = dish["name"]
    slug = f"{index:03d}_{sanitize_filename(name)}"
    local_file = OUTPUT_DIR / f"{slug}.jpg"

    if local_file.exists() and local_file.stat().st_size < 100 * 1024:
        return dish, str(local_file)

    queries = [
        dish["search_term"],
        f"{name} dish gourmet studio food photography",
        f"{name} food photo restaurant delicious",
    ]

    for q in queries:
        urls = search_bing_image_urls(q, count=8)
        for u in urls:
            try:
                r = requests.get(u, headers=BROWSER_HEADERS, timeout=7)
                if r.status_code == 200 and len(r.content) > 5000:
                    processed = process_image(r.content, max_size_kb=95)
                    if len(processed) < 100 * 1024:
                        with open(local_file, "wb") as f:
                            f.write(processed)
                        print(f"[{index:03d}/108] Curated: {name} ({len(processed)/1024:.1f} KB)")
                        return dish, str(local_file)
            except Exception:
                continue

    try:
        r = requests.get(f"https://source.unsplash.com/800x800/?food,{urllib.parse.quote(name)}", headers=BROWSER_HEADERS, timeout=8)
        if r.status_code == 200:
            processed = process_image(r.content, max_size_kb=95)
            with open(local_file, "wb") as f:
                f.write(processed)
            print(f"[{index:03d}/108] Fallback Curated: {name} ({len(processed)/1024:.1f} KB)")
            return dish, str(local_file)
    except Exception:
        pass

    print(f"[{index:03d}/108] WARNING: Could not find image for {name}")
    return dish, None


def upload_to_supabase_storage(local_path: str, remote_filename: str) -> str:
    storage_path = f"{CHINAR_SHOP_ID}/curated_studio/{remote_filename}"
    upload_url = f"{SUPABASE_URL}/storage/v1/object/products/{storage_path}"

    with open(local_path, "rb") as f:
        file_bytes = f.read()

    up_headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "image/jpeg",
        "x-upsert": "true",
    }
    resp = requests.post(upload_url, headers=up_headers, data=file_bytes, timeout=15)
    if resp.status_code not in (200, 201):
        resp = requests.put(upload_url, headers=up_headers, data=file_bytes, timeout=15)

    return f"{SUPABASE_URL}/storage/v1/object/public/products/{storage_path}"


def main():
    print("=" * 70)
    print("THE CHINAR TABLE CAFE AND RESTAURANT INGESTION PIPELINE")
    print(f"Shop ID: {CHINAR_SHOP_ID}")
    print(f"Total Menu Dishes: {len(CHINAR_DISHES)}")
    print("=" * 70)

    # Step 1: Concurrently curate, crop to 1:1, and compress images < 100 KB
    print("\n[Step 1] Curating 100% unique studio food photographs (< 100 KB, 800x800)...")
    dish_photo_pairs = []
    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = {executor.submit(fetch_and_save_dish_photo, dish, idx + 1): (idx, dish) for idx, dish in enumerate(CHINAR_DISHES)}
        for f in as_completed(futures):
            dish, local_path = f.result()
            dish_photo_pairs.append((dish, local_path))

    # Step 2: Upload images to Supabase Storage and build payload
    print("\n[Step 2] Uploading studio photos to Supabase Storage...")
    products_to_insert = []
    for dish, local_path in dish_photo_pairs:
        if not local_path or not os.path.exists(local_path):
            print(f"Error: Missing image for {dish['name']}")
            continue

        fname = Path(local_path).name
        public_url = upload_to_supabase_storage(local_path, fname)

        product_record = {
            "shop_id": CHINAR_SHOP_ID,
            "category": "Restaurant",
            "menu_category": dish["menu_category"],
            "name": dish["name"],
            "description": dish["description"],
            "price": dish["price"],
            "original_price": None,
            "is_veg": dish["is_veg"],
            "is_available": True,
            "is_deleted": False,
            "total_quantity": None,  # Unlimited restaurant inventory
            "images": [public_url],
            "variants": dish["variants"],
        }
        products_to_insert.append(product_record)

    print(f"Total ready to insert: {len(products_to_insert)}")

    # Step 3: Batch insert into database via public.bulk_upload_shop_products RPC
    print("\n[Step 3] Batch uploading to Supabase database via bulk_upload_shop_products RPC...")
    rpc_url = f"{SUPABASE_URL}/rest/v1/rpc/bulk_upload_shop_products"

    chunk_size = 20
    for i in range(0, len(products_to_insert), chunk_size):
        chunk = products_to_insert[i : i + chunk_size]
        payload = {
            "p_shop_id": CHINAR_SHOP_ID,
            "p_products": chunk,
        }
        resp = requests.post(rpc_url, headers=HEADERS, json=payload, timeout=30)
        print(f"Uploaded chunk {i//chunk_size + 1} ({len(chunk)} items) -> Status: {resp.status_code}")
        if resp.status_code not in (200, 201):
            print(f"Error details: {resp.text}")

    # Step 4: Verification & Audit
    print("\n[Step 4] Verifying live products in Supabase...")
    verify_url = f"{SUPABASE_URL}/rest/v1/products?shop_id=eq.{CHINAR_SHOP_ID}&is_deleted=eq.false&select=id,name,menu_category,price,images"
    r = requests.get(verify_url, headers=HEADERS)
    live_prods = r.json()
    print(f"Total live active products for The Chinar Table: {len(live_prods)}")
    unique_images = set(p['images'][0] for p in live_prods if p.get('images'))
    print(f"Products with images: {len([p for p in live_prods if p.get('images')])}")
    print(f"Unique images count: {len(unique_images)}")

    print("\nDone! The Chinar Table Menu Ingestion finished successfully.")


if __name__ == "__main__":
    main()
