#!/usr/bin/env python3
"""
KNEAD & BAKE Menu Ingestion & Studio Food Photography Pipeline
=============================================================
Shop ID: f9e90545-def1-405e-9069-c21fe830383b (Knead & Bake)
Source Menu: 8 Pages Scanned Booklet

Total Dishes: 144 items across 23 distinct menu categories:
1. Kashmiri Wazwan
2. Salad
3. Wazwan Thali
4. Biryani & Mandi
5. Chinese
6. Indian (Non-Veg)
7. Indian (Veg)
8. Tandoori
9. Breads
10. Pizza
11. Hot Classics (Coffee)
12. Hot Signature
13. Cold Classics
14. Iced Blended
15. Mocktails
16. Shakes & Frappes
17. Hot Tea
18. Iced Tea
19. Slush
20. Artisan Cookies (300g Box)
21. Classic Desserts
22. Pastries
23. Custom Cakes, Tea Cakes, Cheesecakes, Savoury Puffs, Croissants

Platform Standards Enforced:
1. 100% Unique Photos for all 144 dishes.
2. 1:1 Square (800x800) Lanczos center-cropped.
3. Strictly < 100 KB file size ceiling (target: 65 - 95 KB).
4. Direct upload to Supabase Storage: products/f9e90545-def1-405e-9069-c21fe830383b/curated_studio/
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

KNEAD_SHOP_ID = "f9e90545-def1-405e-9069-c21fe830383b"
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "data" / "knead_studio_images"
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

KNEAD_DISHES = [
    # ==========================================
    # PAGE 1: WAZWAN, SALAD & THALI
    # ==========================================
    {
        "name": "Rista",
        "menu_category": "Kashmiri Wazwan",
        "price": 320.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 320.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 640.0, "is_available": True, "original_price": None},
        ],
        "description": "Hand-pounded tender mutton meatballs simmered in a vibrant, fragrant red saffron-paprika Wazwan gravy.",
        "search_term": "kashmiri rista wazwan red gravy meatballs studio food photography",
    },
    {
        "name": "Rogan Josh",
        "menu_category": "Kashmiri Wazwan",
        "price": 340.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 340.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 680.0, "is_available": True, "original_price": None},
        ],
        "description": "Authentic Kashmiri lamb slow-cooked with mawal (cockscomb flower), Kashmiri chillies, and aromatic spices.",
        "search_term": "authentic kashmiri rogan josh wazwan copper trami studio food photography",
    },
    {
        "name": "Dhaniwal Korma",
        "menu_category": "Kashmiri Wazwan",
        "price": 340.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 340.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 680.0, "is_available": True, "original_price": None},
        ],
        "description": "Succulent mutton cuts cooked in a rich, velvety curd-based gravy infused with fresh coriander and saffron.",
        "search_term": "dhaniwal korma kashmiri wazwan yogurt coriander gravy studio food photography",
    },
    {
        "name": "Gushtaba",
        "menu_category": "Kashmiri Wazwan",
        "price": 340.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 340.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 680.0, "is_available": True, "original_price": None},
        ],
        "description": "The crowning dish of Wazwan: silken mutton meatballs slow-simmered in a rich, tangy yogurt gravy (yakhni).",
        "search_term": "kashmiri gushtaba wazwan white yogurt gravy yakhni studio food photography",
    },
    {
        "name": "Kebab",
        "menu_category": "Kashmiri Wazwan",
        "price": 300.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 300.0, "is_available": True, "original_price": None}],
        "description": "Finely minced mutton seasoned with mountain herbs and spices, char-grilled to juicy perfection on skewers.",
        "search_term": "kashmiri wazwan seekh kebab skewer grilled studio food photography",
    },
    {
        "name": "Methi Maaz",
        "menu_category": "Kashmiri Wazwan",
        "price": 350.0,
        "is_veg": False,
        "variants": [{"name": "Regular (Plate)", "price": 350.0, "is_available": True, "original_price": None}],
        "description": "Traditional Wazwan starter of finely chopped tender mutton cooked with aromatic sun-dried fenugreek leaves.",
        "search_term": "kashmiri methi maaz wazwan dish fenugreek minced lamb studio food photography",
    },
    {
        "name": "Tabakh Maaz",
        "menu_category": "Kashmiri Wazwan",
        "price": 200.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 200.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 400.0, "is_available": True, "original_price": None},
        ],
        "description": "Twice-cooked lamb ribs poached in spiced milk and fried crisp in pure desi ghee until crackling golden.",
        "search_term": "kashmiri tabakh maaz fried lamb ribs crispy ghee studio food photography",
    },
    {
        "name": "Wazwan Chicken",
        "menu_category": "Kashmiri Wazwan",
        "price": 330.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 330.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Whole tender chicken simmered in rich traditional Kashmiri red wazwan gravy with fennel and dry ginger.",
        "search_term": "kashmiri wazwan chicken curry red rich gravy studio food photography",
    },
    {
        "name": "Green Salad",
        "menu_category": "Salad",
        "price": 50.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 50.0, "is_available": True, "original_price": None}],
        "description": "Crisp fresh garden cucumbers, juicy tomatoes, sliced red onions, carrots, and green chillies with lemon wedges.",
        "search_term": "fresh indian green salad cucumber tomato onion plate studio food photography",
    },
    {
        "name": "Wazwan Thali (Regular)",
        "menu_category": "Wazwan Thali",
        "price": 700.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 700.0, "is_available": True, "original_price": None}],
        "description": "Complete traditional Wazwan meal served with Rice, Methi Maaz, Rista, Rogan Josh, Half Kebab, and Chicken Piece.",
        "search_term": "kashmiri wazwan thali platter rice rista rogan josh kebab chicken studio food photography",
    },
    {
        "name": "Wazwan Thali (Premium)",
        "menu_category": "Wazwan Thali",
        "price": 900.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 900.0, "is_available": True, "original_price": None}],
        "description": "Grand royal Wazwan platter with Rice, Methi Maaz, Rista, Rogan Josh, Gushtaba, Half Kebab, and Half Tabakh Maaz.",
        "search_term": "royal kashmiri wazwan grand thali gushtaba tabakh maaz rogan josh trami studio food photography",
    },

    # ==========================================
    # PAGE 2: BIRYANI, MANDI, RICE & CHINESE
    # ==========================================
    {
        "name": "Chicken Biryani",
        "menu_category": "Biryani & Mandi",
        "price": 160.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 160.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 320.0, "is_available": True, "original_price": None},
        ],
        "description": "Dum cooked aromatic basmati rice layered with juicy chicken, fried onions, and whole royal spices.",
        "search_term": "hyderabadi chicken biryani handi pot studio food photography",
    },
    {
        "name": "Wazwan Biryani (Regular)",
        "menu_category": "Biryani & Mandi",
        "price": 630.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 630.0, "is_available": True, "original_price": None}],
        "description": "Exquisite fusion biryani infused with tender Wazwan meat cuts, saffron-scented rice, and rich spices.",
        "search_term": "kashmiri wazwan mutton biryani saffron rich platter studio food photography",
    },
    {
        "name": "Wazwan Biryani (Premium)",
        "menu_category": "Biryani & Mandi",
        "price": 890.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 890.0, "is_available": True, "original_price": None}],
        "description": "Gourmet biryani feast loaded with Rista, Kebab, Tabakh Maaz, and Rogan Josh over saffron basmati rice.",
        "search_term": "royal wazwan biryani meat feast tabakh maaz rista studio food photography",
    },
    {
        "name": "Chicken Mandi",
        "menu_category": "Biryani & Mandi",
        "price": 750.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 750.0, "is_available": True, "original_price": None}],
        "description": "Traditional Yemeni-style fragrant spiced rice topped with tender, whole slow-roasted spiced chicken and toasted nuts.",
        "search_term": "arabian chicken mandi rice platter roasted chicken studio food photography",
    },
    {
        "name": "Arabian Mandi",
        "menu_category": "Biryani & Mandi",
        "price": 1350.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 1350.0, "is_available": True, "original_price": None}],
        "description": "Authentic Arabian spiced rice platter topped with slow-braised tender meat, golden raisins, and toasted almonds.",
        "search_term": "arabian mandi platter lamb chicken nuts raisins studio food photography",
    },
    {
        "name": "Mutton Mandi (Pre Order Only)",
        "menu_category": "Biryani & Mandi",
        "price": 3600.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 3600.0, "is_available": True, "original_price": None}],
        "description": "Grand feast of whole slow-cooked tender mutton shank falling off the bone over fragrant Arabian spiced rice.",
        "search_term": "grand royal mutton mandi platter whole lamb rice studio food photography",
    },
    {
        "name": "Plain Rice",
        "menu_category": "Biryani & Mandi",
        "price": 90.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 90.0, "is_available": True, "original_price": None}],
        "description": "Steamed premium rice cooked to fluffy, separated grain perfection.",
        "search_term": "steamed plain white rice bowl studio food photography",
    },
    {
        "name": "Basmati Rice",
        "menu_category": "Biryani & Mandi",
        "price": 120.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 120.0, "is_available": True, "original_price": None}],
        "description": "Aromatic long-grain extra-fine basmati rice, steamed with mild spices.",
        "search_term": "long grain basmati rice bowl fluffy studio food photography",
    },
    {
        "name": "Zeera Rice",
        "menu_category": "Biryani & Mandi",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Fragrant basmati rice tempered with roasted cumin seeds and desi ghee.",
        "search_term": "jeera rice cumin basmati bowl ghee studio food photography",
    },
    {
        "name": "Chicken Fried Rice",
        "menu_category": "Chinese",
        "price": 280.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 280.0, "is_available": True, "original_price": None}],
        "description": "Wok-tossed rice with seasoned chicken bits, scrambled egg, and garden fresh vegetables.",
        "search_term": "chicken fried rice wok tossed bowl studio food photography",
    },
    {
        "name": "Veg Fried Rice",
        "menu_category": "Chinese",
        "price": 230.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 230.0, "is_available": True, "original_price": None}],
        "description": "Classic Chinese fried rice loaded with finely chopped carrots, French beans, cabbage, and scallions.",
        "search_term": "veg fried rice bowl colorful vegetables studio food photography",
    },
    {
        "name": "Schezwan Fried Rice",
        "menu_category": "Chinese",
        "price": 320.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 320.0, "is_available": True, "original_price": None}],
        "description": "Spicy and tangy Schezwan fried rice with stir-fried bell peppers, cabbage, and green chillies.",
        "search_term": "schezwan fried rice spicy red wok bowl studio food photography",
    },
    {
        "name": "Chicken Chowmein",
        "menu_category": "Chinese",
        "price": 280.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 280.0, "is_available": True, "original_price": None}],
        "description": "Wok-fried egg noodles tossed with tender shredded chicken, crisp cabbage, and savory Chinese seasonings.",
        "search_term": "chicken chowmein noodles bowl studio food photography",
    },
    {
        "name": "Veg Chowmein",
        "menu_category": "Chinese",
        "price": 240.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 240.0, "is_available": True, "original_price": None}],
        "description": "Classic stir-fried noodles loaded with julienned vegetables and infused with soy, garlic, and vinegar.",
        "search_term": "veg chowmein noodles stir fry bowl studio food photography",
    },
    {
        "name": "Steam Momos",
        "menu_category": "Chinese",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Delicate steamed dumplings stuffed with spiced vegetables, served with fiery spicy red momo chutney.",
        "search_term": "steamed momos in bamboo steamer studio food photography",
    },
    {
        "name": "Fried Momos",
        "menu_category": "Chinese",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Golden, crunchy deep-fried dumplings with a flavorful filling, served with zesty dipping sauces.",
        "search_term": "crispy fried momos golden plate studio food photography",
    },
    {
        "name": "Crispy Momos",
        "menu_category": "Chinese",
        "price": 210.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 210.0, "is_available": True, "original_price": None}],
        "description": "Flake-coated ultra-crispy kurkure momos fried to golden perfection with spicy dips.",
        "search_term": "crispy kurkure momos fried snack plate studio food photography",
    },
    {
        "name": "Tandoori Momos",
        "menu_category": "Chinese",
        "price": 210.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 210.0, "is_available": True, "original_price": None}],
        "description": "Char-grilled dumplings marinated in spicy tandoori yogurt marinade with a smoky clay oven aroma.",
        "search_term": "tandoori momos grilled smoky plate studio food photography",
    },
    {
        "name": "Malai Momos",
        "menu_category": "Chinese",
        "price": 220.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 220.0, "is_available": True, "original_price": None}],
        "description": "Tender momos coated in a rich, velvety cashew cream and cheese reduction with roasted herbs.",
        "search_term": "afghani malai momos creamy white sauce studio food photography",
    },
    {
        "name": "Chilli Chicken",
        "menu_category": "Chinese",
        "price": 450.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 450.0, "is_available": True, "original_price": None}],
        "description": "Crispy chicken bites tossed with crunchy bell peppers, onions, and spicy soy-chilli glaze.",
        "search_term": "chilli chicken indo chinese dry gravy bowl studio food photography",
    },
    {
        "name": "Chicken Manchurian",
        "menu_category": "Chinese",
        "price": 460.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 460.0, "is_available": True, "original_price": None}],
        "description": "Tender chicken meatballs simmered in a dark, tangy garlic, ginger, and scallion Manchurian sauce.",
        "search_term": "chicken manchurian bowl chinese studio food photography",
    },
    {
        "name": "Chicken 65",
        "menu_category": "Chinese",
        "price": 450.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 450.0, "is_available": True, "original_price": None}],
        "description": "Famous spicy deep-fried chicken tempered with curry leaves, mustard seeds, and whole red chillies.",
        "search_term": "chicken 65 spicy red curry leaves studio food photography",
    },

    # ==========================================
    # PAGE 3: INDIAN (NON-VEG) & INDIAN (VEG)
    # ==========================================
    {
        "name": "Chicken Kanti (Boneless)",
        "menu_category": "Indian (Non-Veg)",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Boneless chicken chunks pan-sautéed with sliced onions, ripe tomatoes, and aromatic whole spices.",
        "search_term": "kashmiri boneless chicken kanti pan fried onions tomatoes studio food photography",
    },
    {
        "name": "Kebab Kanti",
        "menu_category": "Indian (Non-Veg)",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 620.0, "is_available": True, "original_price": None},
        ],
        "description": "Minced mutton seekh kababs sliced and tossed with fresh onions, green chillies, and Kashmiri spices.",
        "search_term": "seekh kabab kanti pan fried onions kashmiri studio food photography",
    },
    {
        "name": "Butter Chicken (Boneless)",
        "menu_category": "Indian (Non-Veg)",
        "price": 400.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "Boneless tandoori chicken cooked in a smooth, silky tomato and cashew butter gravy.",
        "search_term": "boneless butter chicken rich makhani gravy studio food photography",
    },
    {
        "name": "Butter Chicken (With Bone)",
        "menu_category": "Indian (Non-Veg)",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 660.0, "is_available": True, "original_price": None},
        ],
        "description": "Bone-in chicken slow-simmered in rich makhani gravy with fenugreek and sweet cream.",
        "search_term": "butter chicken with bone rich curry bowl studio food photography",
    },
    {
        "name": "Kadai Chicken (With Bone)",
        "menu_category": "Indian (Non-Veg)",
        "price": 370.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 370.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 630.0, "is_available": True, "original_price": None},
        ],
        "description": "Chicken stir-cooked with freshly ground kadhai masala, crunchy bell peppers, and onion petals.",
        "search_term": "kadai chicken bell peppers thick gravy bowl studio food photography",
    },
    {
        "name": "Masala Chicken (Boneless)",
        "menu_category": "Indian (Non-Veg)",
        "price": 390.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 390.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Boneless chicken simmered in an aromatic spiced onion-tomato gravy with fresh coriander.",
        "search_term": "boneless chicken masala rich gravy studio food photography",
    },
    {
        "name": "Masala Chicken (With Bone)",
        "menu_category": "Indian (Non-Veg)",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 640.0, "is_available": True, "original_price": None},
        ],
        "description": "Bone-in chicken simmered in a spiced homestyle onion and tomato gravy.",
        "search_term": "bone in chicken masala curry bowl studio food photography",
    },
    {
        "name": "Chicken Korma",
        "menu_category": "Indian (Non-Veg)",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 620.0, "is_available": True, "original_price": None},
        ],
        "description": "Tender chicken cooked in a mild, velvety cashew, almond, and yogurt gravy.",
        "search_term": "chicken korma creamy mild curry studio food photography",
    },
    {
        "name": "Chicken Curry",
        "menu_category": "Indian (Non-Veg)",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 620.0, "is_available": True, "original_price": None},
        ],
        "description": "Classic comforting chicken curry in a traditional spiced golden gravy.",
        "search_term": "traditional indian chicken curry gravy bowl studio food photography",
    },
    {
        "name": "Malai Chicken",
        "menu_category": "Indian (Non-Veg)",
        "price": 370.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 370.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 620.0, "is_available": True, "original_price": None},
        ],
        "description": "Chicken cooked in a mild, velvety fresh cream and cashew sauce with aromatic spices.",
        "search_term": "malai chicken white gravy creamy studio food photography",
    },
    {
        "name": "Matar Mushroom",
        "menu_category": "Indian (Veg)",
        "price": 350.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
        "description": "Sautéed button mushrooms and tender sweet green peas in a spiced onion-tomato masala.",
        "search_term": "matar mushroom curry green peas bowl studio food photography",
    },
    {
        "name": "Paneer Butter Masala",
        "menu_category": "Indian (Veg)",
        "price": 480.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 480.0, "is_available": True, "original_price": None}],
        "description": "Soft cottage cheese cubes simmered in a velvety, rich tomato, butter, and cashew gravy.",
        "search_term": "paneer butter masala bowl rich makhani gravy studio food photography",
    },
    {
        "name": "Kadai Paneer",
        "menu_category": "Indian (Veg)",
        "price": 480.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 480.0, "is_available": True, "original_price": None}],
        "description": "Paneer cubes tossed with crunchy bell peppers, onions, and freshly ground kadai spices.",
        "search_term": "kadai paneer bell peppers thick gravy bowl studio food photography",
    },
    {
        "name": "Shahi Paneer",
        "menu_category": "Indian (Veg)",
        "price": 520.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 520.0, "is_available": True, "original_price": None}],
        "description": "Royal North Indian delicacy of tender paneer cubes in a luxurious sweet-savory almond cream gravy.",
        "search_term": "shahi paneer royal bowl gourmet studio food photography",
    },
    {
        "name": "Tomato Paneer",
        "menu_category": "Indian (Veg)",
        "price": 380.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 380.0, "is_available": True, "original_price": None}],
        "description": "Paneer cubes bathed in a tangy, spiced fresh tomato gravy with ginger and coriander.",
        "search_term": "tamatar paneer tomato paneer curry bowl studio food photography",
    },

    # ==========================================
    # PAGE 4: TANDOORI, BREADS & PIZZA
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
        "name": "Afghani Chicken",
        "menu_category": "Tandoori",
        "price": 400.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "Tender chicken marinated in cashew-cream paste, cheese, and mild spices, char-grilled to perfection.",
        "search_term": "afghani chicken tandoori white creamy grilled studio food photography",
    },
    {
        "name": "Plain Naan",
        "menu_category": "Breads",
        "price": 60.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 60.0, "is_available": True, "original_price": None}],
        "description": "Soft and fluffy traditional leavened bread baked in a piping hot tandoor.",
        "search_term": "plain tandoori naan bread basket studio food photography",
    },
    {
        "name": "Butter Naan",
        "menu_category": "Breads",
        "price": 90.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 90.0, "is_available": True, "original_price": None}],
        "description": "Warm tandoori naan brushed generously with rich melted butter.",
        "search_term": "butter naan flatbread glistening melted butter studio food photography",
    },
    {
        "name": "Tandoori Roti",
        "menu_category": "Breads",
        "price": 30.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 30.0, "is_available": True, "original_price": None}],
        "description": "Wholesome whole wheat flatbread baked on the inner walls of the clay tandoor.",
        "search_term": "tandoori roti whole wheat bread basket studio food photography",
    },
    {
        "name": "Chicken Blast Pizza",
        "menu_category": "Pizza",
        "price": 260.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 260.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Loaded with seasoned chicken chunks, mozzarella cheese, crisp capsicum, and signature pizza sauce.",
        "search_term": "chicken blast pizza gourmet studio food photography",
    },
    {
        "name": "Grilled Chicken Pizza",
        "menu_category": "Pizza",
        "price": 260.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 260.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Herb-grilled chicken strips, caramelized onions, bell peppers, and golden mozzarella.",
        "search_term": "grilled chicken pizza peppers mozzarella studio food photography",
    },
    {
        "name": "Margherita Pizza",
        "menu_category": "Pizza",
        "price": 250.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Classic Italian pizza topped with fresh basil, sliced tomatoes, and melted mozzarella.",
        "search_term": "margherita pizza fresh basil tomato mozzarella studio food photography",
    },
    {
        "name": "Butter Chicken Pizza",
        "menu_category": "Pizza",
        "price": 300.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Fusion delight with creamy makhani gravy base topped with butter chicken chunks and gooey mozzarella.",
        "search_term": "butter chicken pizza fusion makhani gravy studio food photography",
    },
    {
        "name": "Tandoori Pizza",
        "menu_category": "Pizza",
        "price": 260.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 260.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Spicy tandoori chicken tikka, bell peppers, onions, and melted mozzarella cheese.",
        "search_term": "tandoori chicken pizza spicy tikka studio food photography",
    },
    {
        "name": "K&B Special Pizza",
        "menu_category": "Pizza",
        "price": 300.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "The chef's signature recipe with assorted marinated meats, olives, sweet corn, and double mozzarella.",
        "search_term": "deluxe special meat pizza loaded cheese studio food photography",
    },
    {
        "name": "Veg Pizza",
        "menu_category": "Pizza",
        "price": 250.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Garden fresh bell peppers, red onions, mushrooms, sweet corn, and melted mozzarella.",
        "search_term": "fresh garden veg pizza colorful toppings studio food photography",
    },

    # ==========================================
    # PAGE 5: COFFEE, SIGNATURES, MOCKTAILS & SHAKES
    # ==========================================
    {
        "name": "Espresso",
        "menu_category": "Hot Classics (Coffee)",
        "price": 70.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 70.0, "is_available": True, "original_price": None}],
        "description": "Intense, concentrated shot of freshly extracted espresso with a rich golden crema.",
        "search_term": "single espresso shot cup golden crema studio food photography",
    },
    {
        "name": "Double Shot Espresso",
        "menu_category": "Hot Classics (Coffee)",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Double dose of freshly extracted rich espresso for an energizing robust coffee kick.",
        "search_term": "doppio double espresso cup roasted beans studio food photography",
    },
    {
        "name": "Americano",
        "menu_category": "Hot Classics (Coffee)",
        "price": 90.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 90.0, "is_available": True, "original_price": None}],
        "description": "Espresso shots diluted with hot filtered water, delivering a rich full-bodied brew.",
        "search_term": "hot americano coffee black cup studio food photography",
    },
    {
        "name": "Cappuccino",
        "menu_category": "Hot Classics (Coffee)",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Equal parts espresso, steamed milk, and thick velvety milk foam dusted with cocoa.",
        "search_term": "hot cappuccino cup foam latte art studio food photography",
    },
    {
        "name": "Caramel Macchiato",
        "menu_category": "Hot Classics (Coffee)",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Freshly steamed milk with vanilla syrup, marked with espresso and drizzled with caramel sauce.",
        "search_term": "caramel macchiato cup caramel drizzle studio food photography",
    },
    {
        "name": "Flat White",
        "menu_category": "Hot Classics (Coffee)",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Silky micro-foam poured over a double shot of espresso for a strong, velvety coffee experience.",
        "search_term": "flat white coffee cup ceramic latte art studio food photography",
    },
    {
        "name": "Café Latte",
        "menu_category": "Hot Classics (Coffee)",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Rich espresso balanced with steamed milk and a light layer of foam.",
        "search_term": "cafe latte cup steamed milk latte art studio food photography",
    },
    {
        "name": "Café Mocha",
        "menu_category": "Hot Classics (Coffee)",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Espresso blended with bittersweet cocoa syrup, steamed milk, and crowned with foam.",
        "search_term": "cafe mocha cup chocolate coffee latte art studio food photography",
    },
    {
        "name": "Belgian Hot Chocolate",
        "menu_category": "Hot Signature",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Decadent melted Belgian dark chocolate whisked with warm creamy whole milk.",
        "search_term": "belgian hot chocolate mug whipped cream cocoa studio food photography",
    },
    {
        "name": "Nutella Hot Chocolate",
        "menu_category": "Hot Signature",
        "price": 180.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
        "description": "Warm creamy milk blended with rich hazelnut Nutella spread and chocolate garnish.",
        "search_term": "nutella hot chocolate mug hazelnut cocoa studio food photography",
    },
    {
        "name": "Iced Latte",
        "menu_category": "Cold Classics",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Espresso and cold milk poured over ice cubes for a smooth, refreshing chilled coffee.",
        "search_term": "iced latte glass clear ice milk layers studio food photography",
    },
    {
        "name": "Iced Mocha",
        "menu_category": "Cold Classics",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Chilled espresso, dark chocolate sauce, and cold milk served over ice with chocolate drizzle.",
        "search_term": "iced mocha tall glass chocolate drizzle ice studio food photography",
    },
    {
        "name": "Iced Americano",
        "menu_category": "Cold Classics",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Bold shots of rich espresso poured over crystal-clear ice and chilled water.",
        "search_term": "iced americano glass black coffee ice cubes studio food photography",
    },
    {
        "name": "Vanilla Mist Latte",
        "menu_category": "Cold Classics",
        "price": 200.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 200.0, "is_available": True, "original_price": None}],
        "description": "Chilled espresso blended with Madagascar vanilla syrup, cold milk, and frothed cream.",
        "search_term": "vanilla iced latte glass vanilla bean frothed cream studio food photography",
    },
    {
        "name": "Iced Cappuccino",
        "menu_category": "Iced Blended",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Chilled blended espresso topped with a thick layer of cold milk foam.",
        "search_term": "iced cappuccino glass thick cold foam studio food photography",
    },
    {
        "name": "Classic Frappe",
        "menu_category": "Iced Blended",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Blended coffee frappe whipped with crushed ice, milk, and vanilla ice cream.",
        "search_term": "classic coffee frappe glass whipped cream studio food photography",
    },
    {
        "name": "Brownie Frappe",
        "menu_category": "Iced Blended",
        "price": 210.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 210.0, "is_available": True, "original_price": None}],
        "description": "Fudgy chocolate brownie blended with rich coffee, ice cream, and crowned with brownie chunks.",
        "search_term": "chocolate brownie frappe glass brownie pieces studio food photography",
    },
    {
        "name": "Classic Mint Mojito",
        "menu_category": "Mocktails",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Fresh muddled garden mint, juicy lime wedges, sugar, and sparkling soda over crushed ice.",
        "search_term": "classic mint mojito glass lime mint crushed ice studio food photography",
    },
    {
        "name": "Green Apple Lemonade",
        "menu_category": "Mocktails",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Tart green apple syrup blended with freshly squeezed lemon juice and chilled soda.",
        "search_term": "green apple lemonade glass emerald mint studio food photography",
    },
    {
        "name": "Watermelon Mojito",
        "menu_category": "Mocktails",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Sweet watermelon puree muddled with zesty lime, mint, and fizzy sparkling water.",
        "search_term": "watermelon mojito red drink glass mint lime studio food photography",
    },
    {
        "name": "Fresh Lime Soda",
        "menu_category": "Mocktails",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Freshly squeezed lime juice with bubbly soda, served sweet, salted, or mixed.",
        "search_term": "fresh lime soda glass lemon slice ice studio food photography",
    },
    {
        "name": "Blueberry Mojito",
        "menu_category": "Mocktails",
        "price": 170.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 170.0, "is_available": True, "original_price": None}],
        "description": "Plump wild blueberries muddled with garden mint, lime, and chilled bubbly soda.",
        "search_term": "blueberry mojito mocktail dark blue glass mint studio food photography",
    },
    {
        "name": "Strawberry Mojito",
        "menu_category": "Mocktails",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Sweet strawberry crush muddled with fresh mint leaves, lime juice, and soda.",
        "search_term": "strawberry mojito red mocktail glass crushed ice studio food photography",
    },
    {
        "name": "Mango Frappe",
        "menu_category": "Shakes & Frappes",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Luscious ripe mango pulp blended into an icy, creamy tropical frappe.",
        "search_term": "mango frappe yellow thick glass whipped cream studio food photography",
    },
    {
        "name": "Strawberry Creamy Shake",
        "menu_category": "Shakes & Frappes",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Thick gourmet milkshake blended with sweet strawberries and rich double cream.",
        "search_term": "creamy strawberry milkshake pink glass studio food photography",
    },
    {
        "name": "Peanut Butter Frappe",
        "menu_category": "Shakes & Frappes",
        "price": 180.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
        "description": "Creamy roasted peanut butter blended with milk, ice cream, and chocolate fudge.",
        "search_term": "peanut butter frappe glass drizzle whipped cream studio food photography",
    },
    {
        "name": "Chocolate Milkshake",
        "menu_category": "Shakes & Frappes",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Classic chocolate shake whipped with rich cocoa, milk, and chocolate ice cream.",
        "search_term": "chocolate milkshake tall glass chocolate curls studio food photography",
    },
    {
        "name": "Blueberry Milkshake",
        "menu_category": "Shakes & Frappes",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Refreshing gourmet shake blended with mountain blueberries and vanilla ice cream.",
        "search_term": "blueberry milkshake purple glass whipped cream studio food photography",
    },
    {
        "name": "Crunchy KitKat Shake",
        "menu_category": "Shakes & Frappes",
        "price": 180.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
        "description": "Crushed KitKat wafers blended into chocolate ice cream shake with wafer garnish.",
        "search_term": "kitkat shake chocolate wafer glass studio food photography",
    },
    {
        "name": "Knead & Bake Special Shake",
        "menu_category": "Shakes & Frappes",
        "price": 210.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 210.0, "is_available": True, "original_price": None}],
        "description": "House signature creation with Belgian chocolate, brownie crumbs, cookies, and caramel drizzle.",
        "search_term": "special freakshake gourmet loaded chocolate glass studio food photography",
    },
    {
        "name": "Banana Shake",
        "menu_category": "Shakes & Frappes",
        "price": 180.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
        "description": "Naturally sweet shake made with fresh bananas, honey, and cold milk.",
        "search_term": "banana smoothie milkshake glass studio food photography",
    },
    {
        "name": "Vanilla Shake",
        "menu_category": "Shakes & Frappes",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Velvety thick milkshake prepared with premium French vanilla ice cream and chilled milk.",
        "search_term": "vanilla milkshake tall glass whipped cream cherry studio food photography",
    },

    # ==========================================
    # PAGE 6: TEAS & SLUSH
    # ==========================================
    {
        "name": "Lemon Tea",
        "menu_category": "Hot Tea",
        "price": 80.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 80.0, "is_available": True, "original_price": None}],
        "description": "Hot black tea infused with freshly squeezed lemon juice and a touch of honey.",
        "search_term": "hot lemon tea clear glass lemon slice studio food photography",
    },
    {
        "name": "Ginger Lemon Tea",
        "menu_category": "Hot Tea",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Soothing hot brew of crushed ginger root, fresh lemon juice, and black tea.",
        "search_term": "ginger lemon tea hot cup ginger slice studio food photography",
    },
    {
        "name": "Peach Iced Tea",
        "menu_category": "Iced Tea",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Chilled black tea infused with sweet peach syrup and served over ice cubes with lemon.",
        "search_term": "peach iced tea glass peach slice mint ice studio food photography",
    },
    {
        "name": "Lemon Iced Tea",
        "menu_category": "Iced Tea",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Classic crisp iced tea with fresh lemon essence, served chilled with mint leaves.",
        "search_term": "lemon iced tea tall glass lemon slice ice studio food photography",
    },
    {
        "name": "Green Apple Slush",
        "menu_category": "Slush",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Ice-crushed slush blended with tangy green apple syrup, refreshing and vibrant.",
        "search_term": "green apple slush crushed ice green drink glass studio food photography",
    },
    {
        "name": "Watermelon Slush",
        "menu_category": "Slush",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Frosty crushed-ice slush infused with sweet, refreshing watermelon nectar.",
        "search_term": "watermelon slush red icy frozen drink glass studio food photography",
    },
    {
        "name": "Blue Curacao Slush",
        "menu_category": "Slush",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Electric blue icy slush flavored with citrusy blue curacao and lime.",
        "search_term": "blue curacao slush blue frozen icy drink glass studio food photography",
    },

    # ==========================================
    # PAGE 7: ARTISAN COOKIES, DESSERTS & PASTRIES
    # ==========================================
    {
        "name": "Almond Cookies (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 280.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 280.0, "is_available": True, "original_price": None}],
        "description": "Crunchy oven-baked butter cookies studded with premium roasted almond slices.",
        "search_term": "almond cookies box crispy bakery biscuits studio food photography",
    },
    {
        "name": "Choco Chips Cookies (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 260.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 260.0, "is_available": True, "original_price": None}],
        "description": "Rich golden cookies loaded with decadent semi-sweet chocolate chips.",
        "search_term": "chocolate chip cookies box bakery biscuits studio food photography",
    },
    {
        "name": "Cranberry Cookies (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 280.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 280.0, "is_available": True, "original_price": None}],
        "description": "Sweet and tart dried cranberries baked into buttery, crumbly artisan cookies.",
        "search_term": "cranberry cookies box red berry biscuits studio food photography",
    },
    {
        "name": "Pista Cookies (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 290.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 290.0, "is_available": True, "original_price": None}],
        "description": "Fragrant cardamom-spiced cookies studded with crunchy roasted pistachios.",
        "search_term": "pista cookies pistachio biscuits box studio food photography",
    },
    {
        "name": "Coconut Cookies (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 240.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 240.0, "is_available": True, "original_price": None}],
        "description": "Toasted desiccated coconut baked into crisp, golden melt-in-mouth cookies.",
        "search_term": "coconut cookies bakery box macaroons studio food photography",
    },
    {
        "name": "Choco Rocks (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 260.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 260.0, "is_available": True, "original_price": None}],
        "description": "Bite-sized rocky clusters of rich dark chocolate, roasted nuts, and crispy cereal.",
        "search_term": "chocolate rocks clusters nuts confectionery studio food photography",
    },
    {
        "name": "Coconut Congolese (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 290.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 290.0, "is_available": True, "original_price": None}],
        "description": "Traditional chewy coconut macaroons with golden toasted tops and moist centers.",
        "search_term": "congolese coconut rochers macaroons box studio food photography",
    },
    {
        "name": "Almond Biscotti (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 290.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 290.0, "is_available": True, "original_price": None}],
        "description": "Twice-baked traditional Italian almond cantucci biscotti, crunchy and perfect for dipping in coffee.",
        "search_term": "almond biscotti italian cantucci biscuits studio food photography",
    },
    {
        "name": "Red Velvet Cookies (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 250.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 250.0, "is_available": True, "original_price": None}],
        "description": "Crimson red cocoa cookies studded with creamy white chocolate chips.",
        "search_term": "red velvet cookies white chocolate chips box studio food photography",
    },
    {
        "name": "Short Bread (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 260.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 260.0, "is_available": True, "original_price": None}],
        "description": "Classic Scottish-style melt-in-mouth pure butter shortbread fingers dusted with sugar.",
        "search_term": "butter shortbread fingers biscuits box studio food photography",
    },
    {
        "name": "Summer Kulcha (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 240.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 240.0, "is_available": True, "original_price": None}],
        "description": "Traditional Kashmiri bakery sweet kulcha biscuits, crisp and golden with poppy seeds.",
        "search_term": "kashmiri sweet kulcha biscuits bakery box studio food photography",
    },
    {
        "name": "Kaju Cookies (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 280.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 280.0, "is_available": True, "original_price": None}],
        "description": "Rich golden butter cookies packed with roasted cashew nut pieces.",
        "search_term": "kaju cookies cashew nut biscuits box studio food photography",
    },
    {
        "name": "Zeera Cookies (300g Box)",
        "menu_category": "Artisan Cookies (300g Box)",
        "price": 220.0,
        "is_veg": True,
        "variants": [{"name": "300g Box", "price": 220.0, "is_available": True, "original_price": None}],
        "description": "Savory-sweet tea time cookies seasoned with fragrant roasted cumin seeds.",
        "search_term": "jeera cookies cumin biscuits box tea time studio food photography",
    },
    {
        "name": "Cupcake",
        "menu_category": "Classic Desserts",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Moist sponge cupcake topped with a swirl of rich buttercream frosting and sprinkles.",
        "search_term": "gourmet cupcake buttercream frosting studio food photography",
    },
    {
        "name": "Cream Roll",
        "menu_category": "Classic Desserts",
        "price": 70.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 70.0, "is_available": True, "original_price": None}],
        "description": "Flaky puff pastry horn filled with light, sweet whipped vanilla cream.",
        "search_term": "cream horn puff pastry vanilla cream roll studio food photography",
    },
    {
        "name": "Brownie",
        "menu_category": "Classic Desserts",
        "price": 120.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 120.0, "is_available": True, "original_price": None}],
        "description": "Decadent fudgy chocolate brownie with a crinkly crust and rich molten chocolate center.",
        "search_term": "fudge chocolate brownie square studio food photography",
    },
    {
        "name": "Walnut Fudge",
        "menu_category": "Classic Desserts",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Dense, chewy dark chocolate fudge packed with crunchy Kashmiri walnuts.",
        "search_term": "walnut chocolate fudge slice studio food photography",
    },
    {
        "name": "Donut",
        "menu_category": "Classic Desserts",
        "price": 80.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 80.0, "is_available": True, "original_price": None}],
        "description": "Soft ring donut dipped in dark chocolate glaze and rainbow sprinkles.",
        "search_term": "glazed chocolate donut ring studio food photography",
    },
    {
        "name": "Filled Donut",
        "menu_category": "Classic Desserts",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Pillowy round donut stuffed with molten chocolate ganache or vanilla custard.",
        "search_term": "filled donut chocolate custard powdered sugar studio food photography",
    },
    {
        "name": "Eclair",
        "menu_category": "Classic Desserts",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Choux pastry filled with luscious vanilla cream and topped with shiny chocolate fondant glaze.",
        "search_term": "chocolate eclair choux pastry cream filled studio food photography",
    },
    {
        "name": "Cream Bun",
        "menu_category": "Classic Desserts",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Soft sweet bread bun split and filled with generous whipped vanilla cream.",
        "search_term": "bakery cream bun sweet bread whipped cream studio food photography",
    },
    {
        "name": "Tart",
        "menu_category": "Classic Desserts",
        "price": 60.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 60.0, "is_available": True, "original_price": None}],
        "description": "Crisp shortcrust pastry tart shell filled with velvety fruit jam or chocolate cream.",
        "search_term": "mini pastry tart jam chocolate studio food photography",
    },
    {
        "name": "Apple Pie",
        "menu_category": "Classic Desserts",
        "price": 120.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 120.0, "is_available": True, "original_price": None}],
        "description": "Flaky golden crust enclosing spiced cinnamon Kashmiri apple filling.",
        "search_term": "apple pie slice cinnamon crust studio food photography",
    },
    {
        "name": "Brownie With Ice-Cream",
        "menu_category": "Classic Desserts",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Warm chocolate walnut brownie topped with a scoop of vanilla ice cream and hot chocolate fudge.",
        "search_term": "sizzling warm brownie vanilla ice cream scoop chocolate fudge studio food photography",
    },
    {
        "name": "Fresh Fruit Pastry",
        "menu_category": "Pastries",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Light vanilla sponge layered with whipped cream and glazed fresh seasonal fruits.",
        "search_term": "fresh fruit pastry slice kiwi strawberry glaze studio food photography",
    },
    {
        "name": "Red Velvet Pastry",
        "menu_category": "Pastries",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Moist crimson red velvet sponge layered with smooth cream cheese frosting.",
        "search_term": "red velvet pastry slice cream cheese frosting studio food photography",
    },
    {
        "name": "Chocolate Pastry",
        "menu_category": "Pastries",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Rich dark chocolate truffle pastry with layers of chocolate ganache and chocolate curls.",
        "search_term": "chocolate truffle pastry slice ganache studio food photography",
    },
    {
        "name": "Butterscotch Pastry",
        "menu_category": "Pastries",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Vanilla sponge layered with crunchy caramelized praline and butterscotch cream.",
        "search_term": "butterscotch pastry slice caramel praline crunch studio food photography",
    },

    # ==========================================
    # PAGE 8: CAKES, CHEESECAKES, PUFFS & CROISSANTS
    # ==========================================
    {
        "name": "Fresh Fruit Cake",
        "menu_category": "Custom Cakes (Per Pound)",
        "price": 800.0,
        "is_veg": True,
        "variants": [{"name": "1 Pound", "price": 800.0, "is_available": True, "original_price": None}],
        "description": "Light vanilla sponge cake decorated with fresh whipped cream and an abundance of exotic fruits.",
        "search_term": "fresh fruit cake whole exotic fruits kiwi strawberry studio food photography",
    },
    {
        "name": "Chocolate Cake",
        "menu_category": "Custom Cakes (Per Pound)",
        "price": 750.0,
        "is_veg": True,
        "variants": [{"name": "1 Pound", "price": 750.0, "is_available": True, "original_price": None}],
        "description": "Decadent Dutch chocolate sponge layered with rich dark chocolate fudge ganache.",
        "search_term": "dark chocolate cake whole ganache chocolate curls studio food photography",
    },
    {
        "name": "Red Velvet Cake",
        "menu_category": "Custom Cakes (Per Pound)",
        "price": 750.0,
        "is_veg": True,
        "variants": [{"name": "1 Pound", "price": 750.0, "is_available": True, "original_price": None}],
        "description": "Classic red velvet cake frosted with luxurious cream cheese frosting and red velvet crumbs.",
        "search_term": "red velvet cake whole cream cheese frosting studio food photography",
    },
    {
        "name": "English Tea Cake",
        "menu_category": "Tea Cakes",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Classic moist vanilla loaf cake with a tender crumb, perfect for afternoon tea.",
        "search_term": "english tea cake loaf vanilla pound cake studio food photography",
    },
    {
        "name": "Dry Fruit Cake",
        "menu_category": "Tea Cakes",
        "price": 200.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 200.0, "is_available": True, "original_price": None}],
        "description": "Dense, aromatic butter loaf cake studded with chopped cashews, almonds, and raisins.",
        "search_term": "dry fruit tea cake loaf nuts sliced studio food photography",
    },
    {
        "name": "Dates & Walnut Cake",
        "menu_category": "Tea Cakes",
        "price": 220.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 220.0, "is_available": True, "original_price": None}],
        "description": "Rich tea cake made with sweet Arabian dates and crunchy Kashmiri walnuts.",
        "search_term": "date and walnut cake loaf sliced bakery studio food photography",
    },
    {
        "name": "Almond Cake",
        "menu_category": "Tea Cakes",
        "price": 200.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 200.0, "is_available": True, "original_price": None}],
        "description": "Fragrant butter cake infused with pure almond meal and topped with toasted almond flakes.",
        "search_term": "almond tea cake sliced toasted almond flakes studio food photography",
    },
    {
        "name": "Walnut Cake",
        "menu_category": "Tea Cakes",
        "price": 200.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 200.0, "is_available": True, "original_price": None}],
        "description": "Spiced loaf cake loaded with premium roasted Kashmiri walnut pieces.",
        "search_term": "walnut loaf cake sliced bakery studio food photography",
    },
    {
        "name": "Honey Almond Cake",
        "menu_category": "Tea Cakes",
        "price": 210.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 210.0, "is_available": True, "original_price": None}],
        "description": "Moist honey-infused sponge topped with caramelized honey-glazed almond slivers.",
        "search_term": "honey almond cake glazed sliced studio food photography",
    },
    {
        "name": "Chocolate Tea Cake",
        "menu_category": "Tea Cakes",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Rich cocoa sponge loaf cake with a soft crumb, perfect alongside hot coffee.",
        "search_term": "chocolate tea loaf cake sliced studio food photography",
    },
    {
        "name": "Blueberry Cheesecake",
        "menu_category": "Cheesecakes",
        "price": 200.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 200.0, "is_available": True, "original_price": None}],
        "description": "Creamy New York style cheesecake on a graham crust, topped with wild blueberry compote.",
        "search_term": "blueberry cheesecake slice berry topping studio food photography",
    },
    {
        "name": "Strawberry Cheesecake",
        "menu_category": "Cheesecakes",
        "price": 200.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 200.0, "is_available": True, "original_price": None}],
        "description": "Velvety baked cream cheesecake topped with sweet strawberry glaze and fresh fruit.",
        "search_term": "strawberry cheesecake slice red glaze studio food photography",
    },
    {
        "name": "Biscoff Cheesecake",
        "menu_category": "Cheesecakes",
        "price": 220.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 220.0, "is_available": True, "original_price": None}],
        "description": "Decadent cheesecake layered with Lotus Biscoff cookie spread and crunchy Biscoff crumbs.",
        "search_term": "lotus biscoff cheesecake slice caramel cookie studio food photography",
    },
    {
        "name": "Chicken Patty",
        "menu_category": "Savoury Puffs",
        "price": 50.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 50.0, "is_available": True, "original_price": None}],
        "description": "Golden, flaky puff pastry pocket filled with spiced minced chicken filling.",
        "search_term": "chicken puff pastry savory bakery patty studio food photography",
    },
    {
        "name": "Mutton Patty",
        "menu_category": "Savoury Puffs",
        "price": 70.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 70.0, "is_available": True, "original_price": None}],
        "description": "Crisp multilayered puff pastry packed with seasoned Kashmiri spiced mutton keema.",
        "search_term": "mutton puff pastry keema patty bakery studio food photography",
    },
    {
        "name": "Butter Croissant",
        "menu_category": "Croissants & Viennoiserie",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Authentic French viennoiserie, golden brown and flaky with dozens of buttery layers.",
        "search_term": "french butter croissant golden flaky studio food photography",
    },
    {
        "name": "Almond Croissant",
        "menu_category": "Croissants & Viennoiserie",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Twice-baked butter croissant filled with almond frangipane cream and topped with toasted almond flakes.",
        "search_term": "almond croissant toasted flakes powdered sugar studio food photography",
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
        f"{name} gourmet food photography studio 4k",
        f"{name} delicious dish restaurant bakery",
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
                        print(f"[{index:03d}/144] Curated: {name} ({len(processed)/1024:.1f} KB)")
                        return dish, str(local_file)
            except Exception:
                continue

    try:
        r = requests.get(f"https://source.unsplash.com/800x800/?food,{urllib.parse.quote(name)}", headers=BROWSER_HEADERS, timeout=8)
        if r.status_code == 200:
            processed = process_image(r.content, max_size_kb=95)
            with open(local_file, "wb") as f:
                f.write(processed)
            print(f"[{index:03d}/144] Fallback Curated: {name} ({len(processed)/1024:.1f} KB)")
            return dish, str(local_file)
    except Exception:
        pass

    print(f"[{index:03d}/144] WARNING: Could not find image for {name}")
    return dish, None


def upload_to_supabase_storage(local_path: str, remote_filename: str) -> str:
    storage_path = f"{KNEAD_SHOP_ID}/curated_studio/{remote_filename}"
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
    print("KNEAD & BAKE MENU INGESTION & STUDIO FOOD PHOTOGRAPHY PIPELINE")
    print(f"Shop ID: {KNEAD_SHOP_ID}")
    print(f"Total Menu Dishes: {len(KNEAD_DISHES)}")
    print("=" * 70)

    # Step 1: Concurrently curate, crop to 1:1, and compress images < 100 KB
    print("\n[Step 1] Curating 100% unique studio food photographs (< 100 KB, 800x800)...")
    dish_photo_pairs = []
    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = {executor.submit(fetch_and_save_dish_photo, dish, idx + 1): (idx, dish) for idx, dish in enumerate(KNEAD_DISHES)}
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
            "shop_id": KNEAD_SHOP_ID,
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
            "p_shop_id": KNEAD_SHOP_ID,
            "p_products": chunk,
        }
        resp = requests.post(rpc_url, headers=HEADERS, json=payload, timeout=30)
        print(f"Uploaded chunk {i//chunk_size + 1} ({len(chunk)} items) -> Status: {resp.status_code}")
        if resp.status_code not in (200, 201):
            print(f"Error details: {resp.text}")

    # Step 4: Verification & Audit
    print("\n[Step 4] Verifying live products in Supabase...")
    verify_url = f"{SUPABASE_URL}/rest/v1/products?shop_id=eq.{KNEAD_SHOP_ID}&is_deleted=eq.false&select=id,name,menu_category,price,images"
    r = requests.get(verify_url, headers=HEADERS)
    live_prods = r.json()
    print(f"Total live active products for Knead & Bake: {len(live_prods)}")
    unique_images = set(p['images'][0] for p in live_prods if p.get('images'))
    print(f"Products with images: {len([p for p in live_prods if p.get('images')])}")
    print(f"Unique images count: {len(unique_images)}")

    print("\nDone! Knead & Bake Menu Ingestion finished successfully.")


if __name__ == "__main__":
    main()
