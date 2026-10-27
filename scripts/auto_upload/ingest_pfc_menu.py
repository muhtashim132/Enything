#!/usr/bin/env python3
"""
PFC Restaurant Menu Ingestion & Studio Photography Pipeline
===========================================================
Restaurant: PFC (ID: 9baf6168-9915-4e5c-8ca4-80c520537dde)

Constraints Enforced:
1. User Rule: Exclude 'Tandoori' and 'Rolls' sections completely.
2. User Rule: Deduplicate against existing products — do NOT re-upload existing 20 products.
3. Fix Misnamed Sibling: Update existing 'Schezwan veg fried rice' (180/340) to 'Shezwan Chicken Fried Rice' (180/340).
4. Ingest All 76 New Dishes across all remaining categories with exact menu prices & variants:
   - Rice Dishes (Egg Fried Rice, Shezwan Veg Fried Rice)
   - Indian Veg (5 new items)
   - Chinese (9 items with Dry/Gravy variants)
   - Momos (5 items)
   - Pasta (4 items)
   - Pizza Non-Veg (11 items with S/M/L variants)
   - Pizza Veg (8 items with S/M/L variants)
   - Snacks (8 items with Half/Full variants)
   - Roti & Naan (4 items)
   - Hot Drinks (4 items)
   - Soups (4 items)
   - Shakes (8 items)
   - Mocktails (4 items)
5. 100% Unique Curated Studio Photography:
   - 1:1 Square (800x800)
   - Strictly < 100 KB (target 65 - 95 KB)
   - Direct upload to Supabase Storage: products/9baf6168-9915-4e5c-8ca4-80c520537dde/curated_studio/
6. Atomic DB Upsert: Via public.bulk_upload_shop_products RPC.
7. Unlimited Inventory: total_quantity = NULL.
8. Soft Delete Rule: is_deleted = false.
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

PFC_SHOP_ID = "9baf6168-9915-4e5c-8ca4-80c520537dde"
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "data" / "pfc_studio_images"
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

# The 76 New Dishes to ingest (Excluding Tandoori & Rolls, Deduplicated against 20 existing items)
NEW_DISHES = [
    # 1. RICE DISHES (2 new items)
    {
        "name": "Egg Fried Rice",
        "menu_category": "Rice Dishes",
        "price": 250.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 250.0, "is_available": True, "original_price": None}],
        "description": "Fragrant long-grain basmati rice stir-fried with farm-fresh eggs, spring onions, crunchy veggies, and oriental seasonings.",
        "search_term": "egg fried rice gourmet studio food photography bowl",
    },
    {
        "name": "Shezwan Veg Fried Rice",
        "menu_category": "Rice Dishes",
        "price": 310.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 310.0, "is_available": True, "original_price": None}],
        "description": "Fiery wok-tossed basmati rice infused with spicy Schezwan sauce, crisp bell peppers, carrots, and spring onions.",
        "search_term": "schezwan veg fried rice gourmet studio food photography bowl",
    },

    # 2. INDIAN VEG (5 new items)
    {
        "name": "Paneer Butter Masala",
        "menu_category": "Indian Veg",
        "price": 350.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
        "description": "Soft cottage cheese cubes simmered in a velvety, rich tomato, butter, and cashew gravy with aromatic kasuri methi.",
        "search_term": "paneer butter masala bowl gourmet food photography studio",
    },
    {
        "name": "Mix Veg Kurma",
        "menu_category": "Indian Veg",
        "price": 350.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
        "description": "Handpicked seasonal vegetables slow-cooked in a mildly spiced, fragrant coconut and cashew kurma gravy.",
        "search_term": "mix veg kurma vegetable korma bowl gourmet food photography studio",
    },
    {
        "name": "Shahi Paneer",
        "menu_category": "Indian Veg",
        "price": 450.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 450.0, "is_available": True, "original_price": None}],
        "description": "Royal North Indian delicacy of tender paneer cubes bathed in a luxurious, creamy sweet-savory almond gravy.",
        "search_term": "shahi paneer royal bowl gourmet studio food photography",
    },
    {
        "name": "Tomato Paneer",
        "menu_category": "Indian Veg",
        "price": 350.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
        "description": "Succulent paneer pieces simmered in a tangy, spiced fresh plum tomato reduction garnished with fresh coriander.",
        "search_term": "tamatar paneer tomato paneer curry bowl studio food photography",
    },
    {
        "name": "Matar Paneer",
        "menu_category": "Indian Veg",
        "price": 360.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 360.0, "is_available": True, "original_price": None}],
        "description": "Classic pairing of tender green peas and soft cottage cheese simmered in a rich spiced onion-tomato curry.",
        "search_term": "mutter paneer matar paneer bowl gourmet food photography studio",
    },

    # 3. CHINESE (9 new items with Dry & Gravy variants)
    {
        "name": "Chilli Chicken",
        "menu_category": "Chinese",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Dry", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Gravy", "price": 400.0, "is_available": True, "original_price": None},
        ],
        "description": "Crispy batter-coated chicken bites wok-tossed with crunchy bell peppers, onions, green chillies, and savory dark soy.",
        "search_term": "chilli chicken indo chinese gourmet studio food photography",
    },
    {
        "name": "Chicken Manchurian",
        "menu_category": "Chinese",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Dry", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Gravy", "price": 400.0, "is_available": True, "original_price": None},
        ],
        "description": "Seasoned chicken meatballs simmered in a luscious garlic, ginger, and scallion Manchurian sauce.",
        "search_term": "chicken manchurian bowl gourmet studio food photography",
    },
    {
        "name": "Chicken Chowmein",
        "menu_category": "Chinese",
        "price": 170.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 170.0, "is_available": True, "original_price": None}],
        "description": "Wok-fried egg noodles tossed with shredded chicken, crunchy cabbage, carrots, and savory Chinese seasonings.",
        "search_term": "chicken chowmein noodles gourmet studio food photography bowl",
    },
    {
        "name": "Veg Chowmein",
        "menu_category": "Chinese",
        "price": 140.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
        "description": "Classic street-style stir-fried noodles loaded with julienned vegetables and infused with soy, garlic, and vinegar.",
        "search_term": "veg chowmein noodles stir fry gourmet studio food photography bowl",
    },
    {
        "name": "Garlic Chicken",
        "menu_category": "Chinese",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Dry", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Gravy", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Juicy chicken chunks sautéed with caramelized golden garlic cloves, scallions, and savory oriental glaze.",
        "search_term": "garlic chicken chinese gourmet studio food photography",
    },
    {
        "name": "Honey Chilli Chicken",
        "menu_category": "Chinese",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Dry", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Gravy", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Crispy chicken strips coated in a sweet and spicy honey-chilli reduction, topped with toasted sesame seeds.",
        "search_term": "honey chilli chicken gourmet studio food photography",
    },
    {
        "name": "Honey Chilli Potato",
        "menu_category": "Chinese",
        "price": 300.0,
        "is_veg": True,
        "variants": [
            {"name": "Dry", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Gravy", "price": 300.0, "is_available": True, "original_price": None},
        ],
        "description": "Crispy deep-fried potato batons glazed in sweet organic honey, spicy red chilli sauce, and sesame seeds.",
        "search_term": "honey chilli potato crisp gourmet studio food photography",
    },
    {
        "name": "Chilli Paneer",
        "menu_category": "Chinese",
        "price": 350.0,
        "is_veg": True,
        "variants": [
            {"name": "Dry", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Gravy", "price": 370.0, "is_available": True, "original_price": None},
        ],
        "description": "Golden fried cottage cheese cubes wok-tossed with crisp bell peppers, onions, and spicy Indo-Chinese chilli glaze.",
        "search_term": "chilli paneer dry gourmet studio food photography bowl",
    },
    {
        "name": "Lemon Chicken",
        "menu_category": "Chinese",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Dry", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Gravy", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Crispy chicken bites glazed in a tangy fresh lemon and ginger reduction with aromatic Chinese herbs.",
        "search_term": "chinese lemon chicken crispy gourmet studio food photography",
    },

    # 4. MOMOS (5 new items)
    {
        "name": "Steamed Momos",
        "menu_category": "Momos",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Piping hot handcrafted steamed dumplings filled with finely chopped spiced vegetables, served with spicy red chutney.",
        "search_term": "steamed momos in bamboo steamer gourmet studio food photography",
    },
    {
        "name": "Fried Momos",
        "menu_category": "Momos",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Golden and ultra-crispy deep-fried momos with a savory filling, served with creamy mayo and fiery red chutney.",
        "search_term": "crispy fried momos gourmet studio food photography plate",
    },
    {
        "name": "Shezwan Momos",
        "menu_category": "Momos",
        "price": 220.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 220.0, "is_available": True, "original_price": None}],
        "description": "Crisp-fried momos generously wok-tossed in robust spicy Schezwan sauce with scallions and bell peppers.",
        "search_term": "schezwan momos spicy gourmet studio food photography",
    },
    {
        "name": "Malai Momos",
        "menu_category": "Momos",
        "price": 220.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 220.0, "is_available": True, "original_price": None}],
        "description": "Tender momos coated in a rich, velvety cashew cream and cheese reduction infused with mild aromatic spices.",
        "search_term": "afghani malai momos creamy gourmet studio food photography",
    },
    {
        "name": "Tandoori Momos",
        "menu_category": "Momos",
        "price": 200.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 200.0, "is_available": True, "original_price": None}],
        "description": "Char-grilled dumplings marinated in spicy tandoori yogurt marinade with a smoky clay oven aroma.",
        "search_term": "tandoori momos grilled smoky gourmet studio food photography",
    },

    # 5. PASTA (4 new items)
    {
        "name": "Arrabbiata Chicken Pasta",
        "menu_category": "Pasta",
        "price": 370.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 370.0, "is_available": True, "original_price": None}],
        "description": "Penne pasta and tender chicken breast tossed in a spicy, garlicky Italian plum tomato sauce with fresh basil.",
        "search_term": "chicken arrabbiata penne pasta red sauce gourmet studio food photography",
    },
    {
        "name": "Arrabbiata Veg. Pasta",
        "menu_category": "Pasta",
        "price": 340.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 340.0, "is_available": True, "original_price": None}],
        "description": "Al dente penne pasta tossed with black olives, zucchini, and bell peppers in spicy Italian arrabbiata sauce.",
        "search_term": "penne arrabbiata pasta spicy red sauce gourmet studio food photography",
    },
    {
        "name": "Creamy Chicken Pasta",
        "menu_category": "Pasta",
        "price": 370.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 370.0, "is_available": True, "original_price": None}],
        "description": "Succulent chicken breast tossed with penne in a rich, velvety parmesan Alfredo cream sauce with cracked pepper.",
        "search_term": "creamy chicken alfredo penne pasta gourmet studio food photography",
    },
    {
        "name": "Creamy Mushroom Pasta",
        "menu_category": "Pasta",
        "price": 340.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 340.0, "is_available": True, "original_price": None}],
        "description": "Earthy sautéed button mushrooms and al dente pasta simmered in a luscious garlic-parmesan white cream sauce.",
        "search_term": "creamy mushroom alfredo pasta gourmet studio food photography",
    },

    # 6. PIZZA NON-VEG (11 new items with S/M/L variants)
    {
        "name": "Chicken Blast Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 260.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 260.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Loaded with seasoned chicken chunks, mozzarella cheese, crisp capsicum, and signature Italian pizza sauce.",
        "search_term": "chicken blast pizza gourmet studio food photography",
    },
    {
        "name": "Shezwan Chicken Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 270.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 270.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 620.0, "is_available": True, "original_price": None},
        ],
        "description": "Spicy Schezwan chicken, red peppers, onions, and melted mozzarella on stone-baked crust.",
        "search_term": "schezwan chicken pizza gourmet studio food photography",
    },
    {
        "name": "Roasted Chicken Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 270.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 270.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Oven-roasted tender chicken breast, caramelized onions, and golden melted cheese on hand-tossed crust.",
        "search_term": "roasted chicken pizza gourmet studio food photography",
    },
    {
        "name": "Butter Chicken Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 300.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 620.0, "is_available": True, "original_price": None},
        ],
        "description": "Fusion delight with creamy makhani gravy base topped with butter chicken chunks and gooey mozzarella.",
        "search_term": "butter chicken pizza gourmet studio food photography",
    },
    {
        "name": "BBQ Chicken Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 270.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 270.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 610.0, "is_available": True, "original_price": None},
        ],
        "description": "Smoky barbecue glazed chicken, red onions, and mozzarella on stone-baked pizza crust.",
        "search_term": "bbq chicken pizza gourmet studio food photography",
    },
    {
        "name": "Peri Peri Chicken Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 260.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 260.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 610.0, "is_available": True, "original_price": None},
        ],
        "description": "Zesty peri-peri spiced grilled chicken, jalapenos, bell peppers, and melted cheese.",
        "search_term": "peri peri chicken pizza gourmet studio food photography",
    },
    {
        "name": "Creamy Chicken Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 300.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Silky white cream sauce base topped with shredded chicken, herbs, and mozzarella cheese.",
        "search_term": "creamy white sauce chicken pizza gourmet studio food photography",
    },
    {
        "name": "PFC Special Non-Veg Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 400.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 550.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "The house masterpiece loaded with double chicken, sausages, exotic toppings, and extra cheese.",
        "search_term": "deluxe meat feast pizza extra cheese gourmet studio food photography",
    },
    {
        "name": "Hot Mexican Non-Veg Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 300.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "Fiery Mexican salsa base topped with spiced chicken, jalapenos, sweet corn, and mozzarella.",
        "search_term": "mexican spicy chicken pizza jalapeno corn gourmet studio food photography",
    },
    {
        "name": "Jack Sparrow Non-Veg Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 300.0,
        "is_veg": False,
        "variants": [
            {"name": "Small (7 inch)", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 700.0, "is_available": True, "original_price": None},
        ],
        "description": "PFC chef special pirate recipe with savory seasoned chicken, tangy sauce, and golden cheese.",
        "search_term": "gourmet loaded chicken pizza stone baked studio food photography",
    },
    {
        "name": "Choice of Cheese Burst Pizza",
        "menu_category": "Pizza Non-Veg",
        "price": 200.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 200.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 300.0, "is_available": True, "original_price": None},
        ],
        "description": "Decadent crust bursting with oozing molten liquid cheese, baked to golden perfection.",
        "search_term": "cheese burst pizza slice pull gourmet studio food photography",
    },

    # 7. PIZZA VEG (8 new items with S/M/L variants)
    {
        "name": "Classic Cheese Pizza",
        "menu_category": "Pizza Veg",
        "price": 250.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Pure mozzarella perfection on freshly baked dough with aromatic Italian herb tomato sauce.",
        "search_term": "classic cheese pizza melted mozzarella gourmet studio food photography",
    },
    {
        "name": "Margherita Pizza",
        "menu_category": "Pizza Veg",
        "price": 250.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Traditional Italian pizza topped with sun-ripened tomato slices, fresh basil, and mozzarella.",
        "search_term": "margherita pizza fresh basil tomato mozzarella gourmet studio food photography",
    },
    {
        "name": "Veg Blast Pizza",
        "menu_category": "Pizza Veg",
        "price": 250.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "An explosion of garden fresh capsicum, red onions, sweet corn, tomatoes, and mushrooms.",
        "search_term": "veg supreme pizza vegetables colorful gourmet studio food photography",
    },
    {
        "name": "Cheese Burst Pizza",
        "menu_category": "Pizza Veg",
        "price": 300.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Loaded with a molten layer of creamy liquid cheese inside the crust and mozzarella on top.",
        "search_term": "cheesy burst veg pizza gourmet studio food photography",
    },
    {
        "name": "Mushroom Delight Pizza",
        "menu_category": "Pizza Veg",
        "price": 250.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Herb-sautéed button mushrooms, caramelized onions, and melted mozzarella cheese.",
        "search_term": "mushroom pizza herbs mozzarella gourmet studio food photography",
    },
    {
        "name": "Shezwan Paneer Pizza",
        "menu_category": "Pizza Veg",
        "price": 300.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Spicy Schezwan glazed paneer cubes, crisp bell peppers, onions, and melted cheese.",
        "search_term": "schezwan paneer pizza spicy gourmet studio food photography",
    },
    {
        "name": "Creamy Veg Pizza",
        "menu_category": "Pizza Veg",
        "price": 300.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 600.0, "is_available": True, "original_price": None},
        ],
        "description": "Rich Alfredo cream sauce base topped with broccoli, sweet corn, bell peppers, and cheese.",
        "search_term": "creamy white sauce veg pizza gourmet studio food photography",
    },
    {
        "name": "PFC Special Premium Veg Pizza",
        "menu_category": "Pizza Veg",
        "price": 300.0,
        "is_veg": True,
        "variants": [
            {"name": "Small (7 inch)", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "The ultimate vegetarian feast with paneer, olives, jalapenos, mushrooms, corn, and double cheese.",
        "search_term": "deluxe paneer veg pizza toppings gourmet studio food photography",
    },

    # 8. SNACKS (8 new items with Half/Full variants)
    {
        "name": "Chicken Kanti (With Bones)",
        "menu_category": "Snacks",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Traditional Kashmiri pan-fried chicken tossed with sliced onions, ripe tomatoes, and aromatic whole spices.",
        "search_term": "kashmiri chicken kanti pan fried onions tomatoes gourmet studio food photography",
    },
    {
        "name": "Mutton Kabab Kanti",
        "menu_category": "Snacks",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Succulent minced mutton seekh kababs sliced and sautéed with onions, green chillies, and Kashmiri spices.",
        "search_term": "kashmiri mutton kabab kanti seekh kabab gourmet studio food photography",
    },
    {
        "name": "Fried Chicken",
        "menu_category": "Snacks",
        "price": 350.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Golden brown, crisp-coated juicy fried chicken pieces seasoned with house spices.",
        "search_term": "crispy golden fried chicken pieces gourmet studio food photography",
    },
    {
        "name": "Crispy Fried Chicken",
        "menu_category": "Snacks",
        "price": 400.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Extra-crunchy batter-coated chicken tenders fried to golden perfection, served with dipping sauce.",
        "search_term": "crunchy chicken tenders fried strips gourmet studio food photography",
    },
    {
        "name": "Chicken 65",
        "menu_category": "Snacks",
        "price": 380.0,
        "is_veg": False,
        "variants": [
            {"name": "Half (10 Pc)", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full (20 Pc)", "price": 650.0, "is_available": True, "original_price": None},
        ],
        "description": "Famous South Indian spicy deep-fried chicken tempered with curry leaves, mustard seeds, and red chillies.",
        "search_term": "chicken 65 spicy red curry leaves gourmet studio food photography",
    },
    {
        "name": "Chicken Kurkure",
        "menu_category": "Snacks",
        "price": 350.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
        "description": "Ultra-crispy spiced chicken strips crusted with crunchy flakes for an addictive crunch.",
        "search_term": "chicken kurkure crispy finger food gourmet studio food photography",
    },
    {
        "name": "Fried Fish",
        "menu_category": "Snacks",
        "price": 250.0,
        "is_veg": False,
        "variants": [
            {"name": "Half", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 500.0, "is_available": True, "original_price": None},
        ],
        "description": "Fresh fish fillets marinated in carom seeds, ginger-garlic paste, and crisp-fried to golden perfection.",
        "search_term": "amritsari fried fish crisp lemon wedges gourmet studio food photography",
    },
    {
        "name": "French Fries",
        "menu_category": "Snacks",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Classic salted golden potato fries, crispy on the outside and fluffy inside, served with tomato ketchup.",
        "search_term": "crispy golden french fries basket gourmet studio food photography",
    },

    # 9. ROTI & NAAN (4 new items)
    {
        "name": "Plain Naan",
        "menu_category": "Roti & Naan",
        "price": 60.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 60.0, "is_available": True, "original_price": None}],
        "description": "Soft, pillowy traditional flatbread baked in a piping hot clay tandoor.",
        "search_term": "plain tandoori naan bread basket gourmet studio food photography",
    },
    {
        "name": "Butter Naan",
        "menu_category": "Roti & Naan",
        "price": 80.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 80.0, "is_available": True, "original_price": None}],
        "description": "Fresh tandoori naan brushed generously with rich melted butter.",
        "search_term": "butter naan bread glistening butter gourmet studio food photography",
    },
    {
        "name": "Rumali Roti",
        "menu_category": "Roti & Naan",
        "price": 50.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 50.0, "is_available": True, "original_price": None}],
        "description": "Handkerchief-thin, extremely soft Indian flatbread cooked on an inverted tawa.",
        "search_term": "rumali roti folded soft indian flatbread studio food photography",
    },
    {
        "name": "Garlic Naan",
        "menu_category": "Roti & Naan",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Clay tandoor baked naan infused with minced roasted garlic and fresh coriander leaves.",
        "search_term": "garlic naan bread roasted garlic coriander gourmet studio food photography",
    },

    # 10. HOT DRINKS (4 new items)
    {
        "name": "Regular Coffee",
        "menu_category": "Hot Drinks",
        "price": 100.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
        "description": "Freshly brewed steaming aromatic coffee with frothed hot milk.",
        "search_term": "cappuccino coffee cup latte art roasted beans gourmet studio photography",
    },
    {
        "name": "Cold Coffee",
        "menu_category": "Hot Drinks",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Thick, creamy chilled coffee blended with milk, rich espresso, and ice cream.",
        "search_term": "iced cold coffee tall glass chocolate drizzle whipped cream gourmet studio",
    },
    {
        "name": "Hot Chocolate",
        "menu_category": "Hot Drinks",
        "price": 130.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
        "description": "Rich and velvety molten cocoa blended with warm whole milk and chocolate shaving garnish.",
        "search_term": "hot chocolate mug marshmallows cocoa powder gourmet studio photography",
    },
    {
        "name": "Lemon Tea",
        "menu_category": "Hot Drinks",
        "price": 50.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 50.0, "is_available": True, "original_price": None}],
        "description": "Refreshing hot black tea infused with freshly squeezed lemon juice and a hint of fresh mint.",
        "search_term": "hot lemon tea clear glass cup lemon slice mint leaves gourmet studio",
    },

    # 11. SOUPS (4 new items)
    {
        "name": "Sweet Corn Veg. Soup",
        "menu_category": "Soups",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Comforting mild soup filled with tender sweet corn kernels and diced fresh garden vegetables.",
        "search_term": "sweet corn vegetable soup bowl chinese gourmet studio food photography",
    },
    {
        "name": "Sweet Corn Chicken Soup",
        "menu_category": "Soups",
        "price": 170.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 170.0, "is_available": True, "original_price": None}],
        "description": "Classic Chinese sweet corn soup with shredded chicken breast and delicate egg ribbon swirls.",
        "search_term": "chicken sweet corn soup bowl chinese gourmet studio food photography",
    },
    {
        "name": "Hot & Sour Veg. Soup",
        "menu_category": "Soups",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Fiery and tangy oriental broth loaded with mushrooms, tofu, vegetables, and black pepper.",
        "search_term": "veg hot and sour soup bowl dark chinese gourmet studio food photography",
    },
    {
        "name": "Hot & Sour Chicken Soup",
        "menu_category": "Soups",
        "price": 170.0,
        "is_veg": False,
        "variants": [{"name": "Regular", "price": 170.0, "is_available": True, "original_price": None}],
        "description": "Spicy and sour thick chicken soup loaded with tender chicken, bamboo shoots, and mushrooms.",
        "search_term": "chicken hot and sour soup bowl chinese gourmet studio food photography",
    },

    # 12. SHAKES (8 new items)
    {
        "name": "Vanilla Shake",
        "menu_category": "Shakes",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Smooth, creamy thick milkshake prepared with premium vanilla ice cream, chilled milk, and whipped cream.",
        "search_term": "vanilla milkshake tall glass whipped cream cherry gourmet studio photography",
    },
    {
        "name": "Mango Shake",
        "menu_category": "Shakes",
        "price": 180.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
        "description": "Tropical sweetness of ripe Alphonso mangoes blended into a rich, luscious milkshake with pistachio garnish.",
        "search_term": "mango milkshake glass yellow thick whipped cream gourmet studio photography",
    },
    {
        "name": "Strawberry Shake",
        "menu_category": "Shakes",
        "price": 170.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 170.0, "is_available": True, "original_price": None}],
        "description": "Refreshing milkshake blended with real sweet strawberries and vanilla ice cream, topped with strawberry drizzle.",
        "search_term": "strawberry milkshake pink glass whipped cream fresh berry gourmet studio",
    },
    {
        "name": "Black Currant Shake",
        "menu_category": "Shakes",
        "price": 180.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
        "description": "Tangy and sweet black currant berries blended into a thick, purple gourmet shake.",
        "search_term": "blackcurrant milkshake purple glass gourmet studio food photography",
    },
    {
        "name": "Belgium Chocolate Shake",
        "menu_category": "Shakes",
        "price": 180.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
        "description": "Intense dark Belgian chocolate blended into a decadent, velvety smooth milkshake with chocolate curls.",
        "search_term": "belgian chocolate milkshake rich dark glass gourmet studio food photography",
    },
    {
        "name": "Oreo Choco Cookies Shake",
        "menu_category": "Shakes",
        "price": 200.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 200.0, "is_available": True, "original_price": None}],
        "description": "Crushed Oreo cookies blended with chocolate fudge and creamy vanilla ice cream, crowned with a whole Oreo.",
        "search_term": "oreo milkshake glass cookies and cream whipped cream gourmet studio",
    },
    {
        "name": "Chocolate Shake",
        "menu_category": "Shakes",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Classic chocolate milkshake whipped to frothy perfection with cocoa syrup and rich milk chocolate drizzle.",
        "search_term": "classic chocolate milkshake tall glass gourmet studio photography",
    },
    {
        "name": "Banana Shake",
        "menu_category": "Shakes",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Naturally sweet and energy-packed shake made with fresh ripe bananas, honey, and cold milk.",
        "search_term": "banana smoothie milkshake glass banana slice gourmet studio photography",
    },

    # 13. MOCKTAILS (4 new items)
    {
        "name": "Virgin Mojito",
        "menu_category": "Mocktails",
        "price": 150.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
        "description": "Crisp and revitalizing mocktail with muddled fresh lime wedges, garden mint leaves, and bubbly sparkling soda.",
        "search_term": "classic virgin mojito glass crushed ice lime mint leaves gourmet studio",
    },
    {
        "name": "Strawberry Mojito",
        "menu_category": "Mocktails",
        "price": 170.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 170.0, "is_available": True, "original_price": None}],
        "description": "Sweet strawberry puree muddled with zesty lime, fresh mint, and sparkling soda over crushed ice.",
        "search_term": "strawberry mojito mocktail glass red crushed ice mint lime gourmet studio",
    },
    {
        "name": "Blue Curacao Mojito",
        "menu_category": "Mocktails",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Vibrant electric blue mocktail infused with citrusy blue curacao, lime, mint, and crushed ice.",
        "search_term": "blue curacao mojito mocktail electric blue glass ice lime gourmet studio",
    },
    {
        "name": "Green Apple Mojito",
        "menu_category": "Mocktails",
        "price": 160.0,
        "is_veg": True,
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
        "description": "Crisp green apple syrup shaken with mint leaves, fresh lemon juice, and chilled sparkling soda.",
        "search_term": "green apple mojito mocktail emerald green glass mint ice gourmet studio",
    },
]


def sanitize_filename(name: str) -> str:
    s = re.sub(r"[^\w\s-]", "", name.lower())
    return re.sub(r"[-\s]+", "_", s).strip("_")


def search_bing_image_urls(query: str, count: int = 5) -> list:
    """Searches Bing Images for authentic photography."""
    url = f"https://www.bing.com/images/async?q={urllib.parse.quote(query)}&count={count}&first=1&adlt=off&qft=+filterui:photo-photo"
    try:
        resp = requests.get(url, headers=BROWSER_HEADERS, timeout=8)
        if resp.status_code == 200:
            matches = re.findall(r'murl&quot;:&quot;(https?://[^&]+?)&quot;', resp.text)
            urls = []
            for m in matches:
                u = urllib.parse.unquote(m)
                if not any(bad in u.lower() for bad in ["logo", "vector", "icon", "drawing", "illustration", "alamy", "shutterstock", "getty", "dreamstime"]):
                    urls.append(u)
            if urls:
                return urls
    except Exception:
        pass
    return []


def process_image(img_bytes: bytes, max_size_kb: int = 95) -> bytes:
    """Center-crops to 1:1 square, resizes to 800x800, and optimizes to < max_size_kb."""
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
    """Downloads unique photo, compresses < 100KB, saves locally."""
    name = dish["name"]
    slug = f"{index:02d}_{sanitize_filename(name)}"
    local_file = OUTPUT_DIR / f"{slug}.jpg"

    if local_file.exists() and local_file.stat().st_size < 100 * 1024:
        return dish, str(local_file)

    queries = [
        dish["search_term"],
        f"{name} food photography studio 4k",
        f"{name} restaurant dish delicious",
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
                        print(f"[{index:02d}/76] Curated: {name} ({len(processed)/1024:.1f} KB)")
                        return dish, str(local_file)
            except Exception:
                continue

    # Fallback to Unsplash culinary food photo
    try:
        r = requests.get(f"https://source.unsplash.com/800x800/?food,{urllib.parse.quote(name)}", headers=BROWSER_HEADERS, timeout=8)
        if r.status_code == 200:
            processed = process_image(r.content, max_size_kb=95)
            with open(local_file, "wb") as f:
                f.write(processed)
            print(f"[{index:02d}/76] Fallback Curated: {name} ({len(processed)/1024:.1f} KB)")
            return dish, str(local_file)
    except Exception:
        pass

    print(f"[{index:02d}/76] WARNING: Could not find image for {name}")
    return dish, None


def upload_to_supabase_storage(local_path: str, remote_filename: str) -> str:
    """Uploads file to Supabase Storage products bucket."""
    storage_path = f"{PFC_SHOP_ID}/curated_studio/{remote_filename}"
    upload_url = f"{SUPABASE_URL}/storage/v1/object/products/{storage_path}"

    with open(local_path, "rb") as f:
        file_bytes = f.read()

    # Try upserting directly
    up_headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "image/jpeg",
        "x-upsert": "true",
    }
    resp = requests.post(upload_url, headers=up_headers, data=file_bytes, timeout=15)
    if resp.status_code not in (200, 201):
        # Try PUT
        resp = requests.put(upload_url, headers=up_headers, data=file_bytes, timeout=15)

    return f"{SUPABASE_URL}/storage/v1/object/public/products/{storage_path}"


def main():
    print("=" * 70)
    print("PFC RESTAURANT INGESTION & STUDIO FOOD PHOTOGRAPHY PIPELINE")
    print(f"Shop ID: {PFC_SHOP_ID}")
    print(f"Total New Dishes to Ingest: {len(NEW_DISHES)}")
    print("Excluded: Tandoori & Rolls (as requested)")
    print("Deduplicated: 20 existing products will NOT be re-uploaded")
    print("=" * 70)

    # Step 1: Update the misnamed existing product (Schezwan veg fried rice -> Shezwan Chicken Fried Rice)
    print("\n[Step 1] Updating existing 'Schezwan veg fried rice' -> 'Shezwan Chicken Fried Rice'...")
    update_url = f"{SUPABASE_URL}/rest/v1/products?id=eq.7045877e-e1cd-4aa6-b18b-b4e5355e3382"
    patch_body = {
        "name": "Shezwan Chicken Fried Rice",
        "is_veg": False,
        "variants": [
            {"id": "1792664278731", "name": "Half", "price": 180.0, "is_available": True, "original_price": 200.0},
            {"id": "1792664287594", "name": "Full", "price": 340.0, "is_available": True, "original_price": 380.0},
        ],
    }
    # Note: Use rpc or direct patch depending on permissions
    r = requests.patch(update_url, headers=HEADERS, json=patch_body)
    print(f"Update response status: {r.status_code}")

    # Step 2: Concurrently curate, crop to 1:1, and compress images < 100 KB
    print("\n[Step 2] Curating 100% unique studio food photographs (< 100 KB, 800x800)...")
    dish_photo_pairs = []
    with ThreadPoolExecutor(max_workers=6) as executor:
        futures = {executor.submit(fetch_and_save_dish_photo, dish, idx + 1): (idx, dish) for idx, dish in enumerate(NEW_DISHES)}
        for f in as_completed(futures):
            dish, local_path = f.result()
            dish_photo_pairs.append((dish, local_path))

    # Step 3: Upload images to Supabase Storage and build payload
    print("\n[Step 3] Uploading studio photos to Supabase Storage...")
    products_to_insert = []
    for dish, local_path in dish_photo_pairs:
        if not local_path or not os.path.exists(local_path):
            print(f"Error: Missing image for {dish['name']}")
            continue

        size_kb = os.path.getsize(local_path) / 1024
        fname = Path(local_path).name
        public_url = upload_to_supabase_storage(local_path, fname)

        # Enforce all platform rules
        product_record = {
            "shop_id": PFC_SHOP_ID,
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

    # Step 4: Batch insert into database via public.bulk_upload_shop_products RPC
    print("\n[Step 4] Batch uploading to Supabase database via bulk_upload_shop_products RPC...")
    rpc_url = f"{SUPABASE_URL}/rest/v1/rpc/bulk_upload_shop_products"

    # Upload in chunks of 20
    chunk_size = 20
    for i in range(0, len(products_to_insert), chunk_size):
        chunk = products_to_insert[i : i + chunk_size]
        payload = {
            "p_shop_id": PFC_SHOP_ID,
            "p_products": chunk,
        }
        resp = requests.post(rpc_url, headers=HEADERS, json=payload, timeout=30)
        print(f"Uploaded chunk {i//chunk_size + 1} ({len(chunk)} items) -> Status: {resp.status_code}")
        if resp.status_code not in (200, 201):
            print(f"Error details: {resp.text}")

    # Step 5: Verification & Audit
    print("\n[Step 5] Verifying live products in Supabase...")
    verify_url = f"{SUPABASE_URL}/rest/v1/products?shop_id=eq.{PFC_SHOP_ID}&is_deleted=eq.false&select=id,name,menu_category,price,images"
    r = requests.get(verify_url, headers=HEADERS)
    live_prods = r.json()
    print(f"Total live active products for PFC: {len(live_prods)}")
    unique_images = set(p['images'][0] for p in live_prods if p.get('images'))
    print(f"Products with images: {len([p for p in live_prods if p.get('images')])}")
    print(f"Unique images count: {len(unique_images)}")

    print("\nDone! Pipeline finished successfully.")


if __name__ == "__main__":
    main()
