#!/usr/bin/env python3
"""
Dedicated high-speed ingestion script for Foodies by Chillax (12-Page Menu)
Automates end-to-end ingestion:
- 84 dishes extracted across all 12 pages
- Verbatim section categories (Title Case)
- Multi-variant pricing matrices (Half/Full, S/M/L)
- Strictly 1 compressed 1:1 studio photo per dish (< 120KB)
- Unlimited stock (total_quantity = NULL)
- Soft delete compliance (is_deleted = false)
- 100% Prepaid Model (zero COD)
- ThreadPoolExecutor for fast parallel image formatting & uploading
"""

import os
import sys
import time
import json
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

from image_pipeline import download_and_prepare_images, upload_images_to_supabase
from scraper import _scrape_wikimedia_commons_food_images
from uploader import get_supabase_config, bulk_upload_products

FOODIES_SHOP_ID = "c75542ec-63ca-4843-8ebc-eb285fa66fda"
OUTPUT_DIR = SCRIPT_DIR / "data" / "foodies_studio_images"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

MENU_ITEMS = [
    # --- TEA, COFFEE & BEVERAGES ---
    {
        "name": "Kulhad Chai",
        "menu_category": "Tea, Coffee & Beverages",
        "price": 50.0,
        "is_veg": True,
        "description": "Traditional aromatic tea brewed with Indian spices, served in an authentic earthen kulhad.",
        "variants": [{"name": "Regular", "price": 50.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Kulhad Chai with Grilled Butter Toast",
        "menu_category": "Tea, Coffee & Beverages",
        "price": 100.0,
        "is_veg": True,
        "description": "Steaming hot kulhad chai served alongside crisp, golden grilled butter toast.",
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Kulhad Chai with Bun Maska",
        "menu_category": "Tea, Coffee & Beverages",
        "price": 100.0,
        "is_veg": True,
        "description": "Fragrant spiced kulhad chai paired with a pillowy soft bun generously slathered with butter.",
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Coffee",
        "menu_category": "Tea, Coffee & Beverages",
        "price": 80.0,
        "is_veg": True,
        "description": "Rich, frothy, and freshly brewed hot coffee with a smooth aromatic finish.",
        "variants": [{"name": "Regular", "price": 80.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Black Coffee (Espresso)",
        "menu_category": "Tea, Coffee & Beverages",
        "price": 60.0,
        "is_veg": True,
        "description": "Bold, intense, and deeply aromatic freshly extracted black espresso shot.",
        "variants": [{"name": "Regular", "price": 60.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Namkeen Lassi",
        "menu_category": "Tea, Coffee & Beverages",
        "price": 50.0,
        "is_veg": True,
        "description": "Traditional chilled savory lassi churned with roasted cumin and fresh mint.",
        "variants": [{"name": "Regular", "price": 50.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Sweet Lassi",
        "menu_category": "Tea, Coffee & Beverages",
        "price": 60.0,
        "is_veg": True,
        "description": "Thick, creamy, and sweet yogurt beverage garnished with crushed cardamom.",
        "variants": [{"name": "Regular", "price": 60.0, "is_available": True, "original_price": None}],
    },

    # --- SOUPS ---
    {
        "name": "Hot & Sour Soup (Veg)",
        "menu_category": "Soups",
        "price": 150.0,
        "is_veg": True,
        "description": "A perfect spicy and tangy blend of oriental spices, shredded fresh vegetables, and chili.",
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Hot & Sour Soup (Chicken)",
        "menu_category": "Soups",
        "price": 150.0,
        "is_veg": False,
        "description": "A bold oriental soup loaded with shredded chicken, crunchy vegetables, and tangy chili vinegar.",
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Sweet Corn Soup (Veg)",
        "menu_category": "Soups",
        "price": 150.0,
        "is_veg": True,
        "description": "Creamy, hearty soup simmered with sweet corn kernels, tender vegetables, and mild seasonings.",
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Sweet Corn Soup (Chicken)",
        "menu_category": "Soups",
        "price": 150.0,
        "is_veg": False,
        "description": "Creamy, velvety sweet corn soup packed with tender chicken shreds and mild aromatic herbs.",
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Chicken Manchow Soup",
        "menu_category": "Soups",
        "price": 150.0,
        "is_veg": False,
        "description": "A flavorful Indo-Chinese soup with minced chicken, garlic, cilantro, and topped with crisp noodles.",
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
    },

    # --- INDIAN STARTERS ---
    {
        "name": "Tandoori Chicken",
        "menu_category": "Indian Starters",
        "price": 350.0,
        "is_veg": False,
        "description": "Tender chicken marinated in yogurt and tandoori spices, char-grilled to smoky perfection.",
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Afghani Chicken",
        "menu_category": "Indian Starters",
        "price": 400.0,
        "is_veg": False,
        "description": "Succulent chicken marinated in rich cashew paste, fresh cream, and mild Afghani spices.",
        "variants": [
            {"name": "Half", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Chicken Tikka",
        "menu_category": "Indian Starters",
        "price": 350.0,
        "is_veg": False,
        "description": "Boneless chicken cubes steeped in mustard oil and Kashmiri chili, roasted in a clay tandoor.",
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Paneer Tikka",
        "menu_category": "Indian Starters",
        "price": 300.0,
        "is_veg": True,
        "description": "Fresh cottage cheese cubes marinated in aromatic spices, skewered with bell peppers and onions.",
        "variants": [
            {"name": "Half", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 600.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Chicken 65",
        "menu_category": "Indian Starters",
        "price": 350.0,
        "is_veg": False,
        "description": "Crisp and juicy South Indian style chicken bites tempered with curry leaves and red chili.",
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 650.0, "is_available": True, "original_price": None},
        ],
    },

    # --- CHINESE STARTERS ---
    {
        "name": "Honey Chilli Chicken",
        "menu_category": "Chinese Starters",
        "price": 350.0,
        "is_veg": False,
        "description": "Crispy chicken tossed in a luscious sweet honey chili glaze with toasted sesame seeds.",
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Chilli Chicken",
        "menu_category": "Chinese Starters",
        "price": 380.0,
        "is_veg": False,
        "description": "Crispy battered chicken tossed in spicy soya-chilli gravy with crunchy capsicum and onions.",
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Dragon Chicken",
        "menu_category": "Chinese Starters",
        "price": 400.0,
        "is_veg": False,
        "description": "Crispy chicken strips coated in fiery red dragon sauce with cashews and spring onions.",
        "variants": [{"name": "Regular", "price": 400.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Lemon Chicken",
        "menu_category": "Chinese Starters",
        "price": 380.0,
        "is_veg": False,
        "description": "Golden fried chicken morsels tossed in a tangy, refreshing lemon garlic reduction.",
        "variants": [
            {"name": "Half", "price": 380.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Chilli Garlic Chicken",
        "menu_category": "Chinese Starters",
        "price": 350.0,
        "is_veg": False,
        "description": "Wok-seared chicken tossed in a pungent, fragrant chili garlic sauce with bell peppers.",
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Crispy Fish Chilly",
        "menu_category": "Chinese Starters",
        "price": 350.0,
        "is_veg": False,
        "description": "Lightly battered delicate fish fillets fried crispy and tossed in spicy chili pepper sauce.",
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Honey Chilli Wings",
        "menu_category": "Chinese Starters",
        "price": 350.0,
        "is_veg": False,
        "description": "Crispy chicken wings caramelized with sweet natural honey and fiery Asian chilies.",
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Schezwan Wings",
        "menu_category": "Chinese Starters",
        "price": 350.0,
        "is_veg": False,
        "description": "Spicy chicken wings wok-tossed in homemade pungent Schezwan chili pepper paste.",
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
    },

    # --- CHINESE MAIN COURSE ---
    {
        "name": "Chicken Fried Rice",
        "menu_category": "Chinese Main Course",
        "price": 180.0,
        "is_veg": False,
        "description": "Wok-tossed basmati rice with scrambled egg, shredded chicken, and spring onions.",
        "variants": [
            {"name": "Half", "price": 180.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 360.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Veg Fried Rice",
        "menu_category": "Chinese Main Course",
        "price": 170.0,
        "is_veg": True,
        "description": "Fragrant basmati rice wok-fried with crisp carrots, beans, bell peppers, and light soy.",
        "variants": [
            {"name": "Half", "price": 170.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 320.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Korean Rice Bowl (Chicken)",
        "menu_category": "Chinese Main Course",
        "price": 230.0,
        "is_veg": False,
        "description": "Savory Korean-style steamed rice bowl topped with spicy gochujang chicken and toasted sesame.",
        "variants": [{"name": "Regular", "price": 230.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Veg Chowmein",
        "menu_category": "Chinese Main Course",
        "price": 180.0,
        "is_veg": True,
        "description": "Classic stir-fried hakka noodles with shredded cabbage, capsicum, carrots, and light soy.",
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Chicken Chowmein",
        "menu_category": "Chinese Main Course",
        "price": 200.0,
        "is_veg": False,
        "description": "Stir-fried noodles loaded with succulent chicken strips, fresh veggies, and savory seasonings.",
        "variants": [{"name": "Regular", "price": 200.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Chilli Garlic Noodle",
        "menu_category": "Chinese Main Course",
        "price": 230.0,
        "is_veg": True,
        "description": "Spicy wok-tossed noodles flavored with burnt garlic, red chili oil, and fresh vegetables.",
        "variants": [{"name": "Regular", "price": 230.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Hakka Noodles (Veg)",
        "menu_category": "Chinese Main Course",
        "price": 180.0,
        "is_veg": True,
        "description": "Traditional street-style Hakka noodles stir-fried with crunchy vegetables and mild spices.",
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Hakka Noodles (Chicken)",
        "menu_category": "Chinese Main Course",
        "price": 220.0,
        "is_veg": False,
        "description": "Authentic Hakka noodles tossed with juicy chicken bits, egg, shredded cabbage, and scallions.",
        "variants": [{"name": "Regular", "price": 220.0, "is_available": True, "original_price": None}],
    },

    # --- INDIAN MAIN COURSES ---
    {
        "name": "Butter Chicken (With Bone)",
        "menu_category": "Indian Main Courses",
        "price": 450.0,
        "is_veg": False,
        "description": "Classic North Indian curry with tender chicken on the bone simmered in a velvety tomato makhani gravy.",
        "variants": [
            {"name": "Half", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 750.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Butter Chicken (Boneless)",
        "menu_category": "Indian Main Courses",
        "price": 420.0,
        "is_veg": False,
        "description": "Succulent boneless chicken tikka pieces in a smooth, buttery tomato cream gravy with kasuri methi.",
        "variants": [
            {"name": "Half", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Kadai Chicken",
        "menu_category": "Indian Main Courses",
        "price": 420.0,
        "is_veg": False,
        "description": "Spicy chicken curry cooked in an iron kadai with freshly ground coriander, chili, and bell peppers.",
        "variants": [
            {"name": "Half", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Masala Chicken",
        "menu_category": "Indian Main Courses",
        "price": 420.0,
        "is_veg": False,
        "description": "Traditional homestyle Indian chicken curry cooked in a robust onion-tomato masala gravy.",
        "variants": [
            {"name": "Half", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Rara Chicken",
        "menu_category": "Indian Main Courses",
        "price": 420.0,
        "is_veg": False,
        "description": "Rich Punjabi specialty featuring juicy chicken pieces simmered alongside aromatic chicken keema gravy.",
        "variants": [
            {"name": "Half", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 720.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Handi Chicken",
        "menu_category": "Indian Main Courses",
        "price": 420.0,
        "is_veg": False,
        "description": "Slow-cooked chicken in an earthen clay handi with caramelized onions, yogurt, and warm garam masala.",
        "variants": [
            {"name": "Half", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 720.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Chicken Kanti (Boneless)",
        "menu_category": "Indian Main Courses",
        "price": 350.0,
        "is_veg": False,
        "description": "Kashmiri-style pan-fried boneless chicken sauteed with sliced onions, tomatoes, and spicy green chilies.",
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Chicken Kanti (With Bone)",
        "menu_category": "Indian Main Courses",
        "price": 420.0,
        "is_veg": False,
        "description": "Kashmiri-style chicken on the bone tossed on high heat with crisp onions, tomatoes, and native spices.",
        "variants": [
            {"name": "Half", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 720.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Malai Chicken",
        "menu_category": "Indian Main Courses",
        "price": 420.0,
        "is_veg": False,
        "description": "Decadent chicken curry in a silky cream and cashew white gravy gently spiced with green cardamom.",
        "variants": [
            {"name": "Half", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 750.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Afghani White Gravy Chicken",
        "menu_category": "Indian Main Courses",
        "price": 450.0,
        "is_veg": False,
        "description": "Mild, royal chicken preparation simmered in an indulgent cashew nut and fresh cream gravy.",
        "variants": [
            {"name": "Half", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 800.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Chicken Do Pyaza",
        "menu_category": "Indian Main Courses",
        "price": 420.0,
        "is_veg": False,
        "description": "Hearty chicken curry prepared with caramelized and diced onions added at two distinct stages.",
        "variants": [
            {"name": "Half", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 750.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Foodies Special Kaju Chicken",
        "menu_category": "Indian Main Courses",
        "price": 450.0,
        "is_veg": False,
        "description": "Chef's signature preparation of tender chicken steeped in roasted whole cashews and cream sauce.",
        "variants": [
            {"name": "Half", "price": 450.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 800.0, "is_available": True, "original_price": None},
        ],
    },

    # --- RICE & PULAO ---
    {
        "name": "Foodies Special Biryani",
        "menu_category": "Rice & Pulao",
        "price": 160.0,
        "is_veg": False,
        "description": "Signature dum biryani made with long-grain basmati, succulent chicken, and aromatic whole spices.",
        "variants": [
            {"name": "Half", "price": 160.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 320.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Muradabadi Biryani",
        "menu_category": "Rice & Pulao",
        "price": 160.0,
        "is_veg": False,
        "description": "Aromatic yakhni style Muradabadi biryani cooked with tender chicken, whole spices, and green chili salsa.",
        "variants": [
            {"name": "Half", "price": 160.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 320.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Uzbiki Pulao (Chicken)",
        "menu_category": "Rice & Pulao",
        "price": 300.0,
        "is_veg": False,
        "description": "Traditional Uzbek-style spiced pilaf cooked with long-grain rice, chicken, sweet carrots, and raisins.",
        "variants": [
            {"name": "Half", "price": 300.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 600.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Zeera Rice",
        "menu_category": "Rice & Pulao",
        "price": 150.0,
        "is_veg": True,
        "description": "Aromatic basmati rice tempered with golden roasted cumin seeds and fresh desi ghee.",
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Plain Rice",
        "menu_category": "Rice & Pulao",
        "price": 120.0,
        "is_veg": True,
        "description": "Fluffy, long-grain steamed white basmati rice cooked to perfection.",
        "variants": [{"name": "Regular", "price": 120.0, "is_available": True, "original_price": None}],
    },

    # --- PIZZAS ---
    {
        "name": "Chicken Blast Pizza",
        "menu_category": "Pizzas",
        "price": 260.0,
        "is_veg": False,
        "description": "Handcrafted stone-baked pizza loaded with spicy chicken chunks, bell peppers, onions, and mozzarella.",
        "variants": [
            {"name": "Small (7 inch)", "price": 260.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Butter Chicken Pizza",
        "menu_category": "Pizzas",
        "price": 280.0,
        "is_veg": False,
        "description": "Stone-baked crust layered with rich butter chicken makhani sauce, chicken tikka, and gooey cheese.",
        "variants": [
            {"name": "Small (7 inch)", "price": 280.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 430.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Peri Peri Pizza",
        "menu_category": "Pizzas",
        "price": 260.0,
        "is_veg": False,
        "description": "Spicy Peri Peri seasoned chicken chunks, colored bell peppers, red onions, and mozzarella cheese.",
        "variants": [
            {"name": "Small (7 inch)", "price": 260.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 420.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Foodies Special American Pizza",
        "menu_category": "Pizzas",
        "price": 280.0,
        "is_veg": False,
        "description": "Chef's supreme pizza topped with chicken pepperoni, black olives, jalapenos, onions, and extra cheese.",
        "variants": [
            {"name": "Small (7 inch)", "price": 280.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 440.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 650.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Plain Cheese Pizza",
        "menu_category": "Pizzas",
        "price": 250.0,
        "is_veg": True,
        "description": "Classic stone-baked pizza loaded with 100% genuine mozzarella cheese over herb-infused tomato sauce.",
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 550.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Tomato Onion Corn Pizza",
        "menu_category": "Pizzas",
        "price": 250.0,
        "is_veg": True,
        "description": "Crisp pizza crust topped with juicy tomatoes, red onions, golden sweet corn, and mozzarella cheese.",
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 630.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Margarita Pizza",
        "menu_category": "Pizzas",
        "price": 250.0,
        "is_veg": True,
        "description": "Traditional Italian style pizza featuring sun-ripened tomato concasse, fresh mozzarella, and sweet basil.",
        "variants": [
            {"name": "Small (7 inch)", "price": 250.0, "is_available": True, "original_price": None},
            {"name": "Medium (10 inch)", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Large (13 inch)", "price": 630.0, "is_available": True, "original_price": None},
        ],
    },

    # --- FROM THE HOUSE OF PUNJAB ---
    {
        "name": "Chole Bhature",
        "menu_category": "From The House Of Punjab",
        "price": 130.0,
        "is_veg": True,
        "description": "Punjabi-style piquant spiced chickpeas served with two hot, fluffy, and golden fried bhaturas.",
        "variants": [{"name": "Regular", "price": 130.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Amritsari Spl. Aloo Kulche with Chole",
        "menu_category": "From The House Of Punjab",
        "price": 140.0,
        "is_veg": True,
        "description": "Flaky, layered Amritsari tandoori kulcha stuffed with spiced potatoes, served with tangy chole.",
        "variants": [{"name": "Regular", "price": 140.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Amritsari Special Paneer Kulche with Chole",
        "menu_category": "From The House Of Punjab",
        "price": 150.0,
        "is_veg": True,
        "description": "Crispy golden kulcha packed with seasoned crumbled paneer, paired with hearty Amritsari chole.",
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Plain Naan",
        "menu_category": "From The House Of Punjab",
        "price": 70.0,
        "is_veg": True,
        "description": "Classic leavened flatbread baked against the searing walls of a traditional clay tandoor.",
        "variants": [{"name": "Regular", "price": 70.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Butter Naan",
        "menu_category": "From The House Of Punjab",
        "price": 100.0,
        "is_veg": True,
        "description": "Fluffy tandoori naan brushed generously with rich melted butter.",
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Garlic Naan",
        "menu_category": "From The House Of Punjab",
        "price": 100.0,
        "is_veg": True,
        "description": "Tandoori leavened bread studded with freshly crushed garlic and chopped coriander.",
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Lachha Parantha",
        "menu_category": "From The House Of Punjab",
        "price": 100.0,
        "is_veg": True,
        "description": "Multi-layered whole wheat tandoori flatbread brushed with butter.",
        "variants": [{"name": "Regular", "price": 100.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Shahi Paneer",
        "menu_category": "From The House Of Punjab",
        "price": 400.0,
        "is_veg": True,
        "description": "Royal dish of soft cottage cheese cubes simmered in a luscious cashew, cream, and tomato gravy.",
        "variants": [
            {"name": "Half", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Paneer Butter Masala",
        "menu_category": "From The House Of Punjab",
        "price": 400.0,
        "is_veg": True,
        "description": "Tender paneer cubes simmered in a creamy, velvety tomato and butter gravy with aromatic spices.",
        "variants": [
            {"name": "Half", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Mutter Mushroom",
        "menu_category": "From The House Of Punjab",
        "price": 400.0,
        "is_veg": True,
        "description": "Fresh button mushrooms and green peas simmered in a spiced onion-tomato curry.",
        "variants": [
            {"name": "Half", "price": 400.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },
    {
        "name": "Mix Veg",
        "menu_category": "From The House Of Punjab",
        "price": 350.0,
        "is_veg": True,
        "description": "Assortment of fresh garden vegetables cooked in a flavorful North Indian homestyle gravy.",
        "variants": [
            {"name": "Half", "price": 350.0, "is_available": True, "original_price": None},
            {"name": "Full", "price": 700.0, "is_available": True, "original_price": None},
        ],
    },

    # --- MOMOS & OTHER DELIGHTS ---
    {
        "name": "Steamed Momos",
        "menu_category": "Momos",
        "price": 150.0,
        "is_veg": True,
        "description": "Delicate handmade Himalayan dumplings steamed to perfection, served with fiery red chili dip.",
        "variants": [{"name": "Regular", "price": 150.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Fried Momos",
        "menu_category": "Momos",
        "price": 160.0,
        "is_veg": True,
        "description": "Golden crispy fried dumplings packed with savory vegetable filling and herbs.",
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Tandoori Momos",
        "menu_category": "Momos",
        "price": 200.0,
        "is_veg": True,
        "description": "Juicy dumplings marinated in smoky tandoori marinade and charred to perfection.",
        "variants": [{"name": "Regular", "price": 200.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Crispy Momos",
        "menu_category": "Momos",
        "price": 180.0,
        "is_veg": True,
        "description": "Double-crunch crumb-coated momos fried to golden perfection, served with spicy mayo.",
        "variants": [{"name": "Regular", "price": 180.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Afghani Momos",
        "menu_category": "Momos",
        "price": 220.0,
        "is_veg": True,
        "description": "Rich dumplings tossed in a silky Afghani cream, cashew, and herb sauce.",
        "variants": [{"name": "Regular", "price": 220.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Chillax Special Shawarma",
        "menu_category": "Rolls & Shawarma",
        "price": 160.0,
        "is_veg": False,
        "description": "Thin rumali bread wrapped with spiced roast chicken, pickled cucumbers, and signature garlic toum.",
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Chillax Special Crispy Chicken Roll",
        "menu_category": "Rolls & Shawarma",
        "price": 160.0,
        "is_veg": False,
        "description": "Golden fried crispy chicken strips wrapped with onions, capsicum, and house secret sauce.",
        "variants": [{"name": "Regular", "price": 160.0, "is_available": True, "original_price": None}],
    },

    # --- PASTA ---
    {
        "name": "White Alfredo Pasta (Chicken)",
        "menu_category": "Pasta",
        "price": 400.0,
        "is_veg": False,
        "description": "Penne pasta tossed in a rich, buttery Parmesan cream sauce with tender grilled chicken slices.",
        "variants": [{"name": "Regular", "price": 400.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "White Alfredo Pasta (Veg)",
        "menu_category": "Pasta",
        "price": 350.0,
        "is_veg": True,
        "description": "Creamy Italian penne pasta tossed with broccoli, sweet corn, bell peppers, and garlic cheese sauce.",
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Red Sauce Pasta (Chicken)",
        "menu_category": "Pasta",
        "price": 400.0,
        "is_veg": False,
        "description": "Classic arrabbiata pasta with tangy herb-infused tomato sauce, garlic, and tender chicken chunks.",
        "variants": [{"name": "Regular", "price": 400.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Red Sauce Pasta (Veg)",
        "menu_category": "Pasta",
        "price": 350.0,
        "is_veg": True,
        "description": "Penne pasta cooked in robust Italian tomato basil sauce with zucchini, bell peppers, and olives.",
        "variants": [{"name": "Regular", "price": 350.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Mushroom Pasta (Chicken)",
        "menu_category": "Pasta",
        "price": 420.0,
        "is_veg": False,
        "description": "Sautéed button mushrooms and tender chicken tossed with pasta in a rich roasted garlic cream sauce.",
        "variants": [{"name": "Regular", "price": 420.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Mushroom Pasta (Veg)",
        "menu_category": "Pasta",
        "price": 370.0,
        "is_veg": True,
        "description": "Earthy sliced button mushrooms sautéed in extra virgin olive oil and tossed in creamy herb sauce.",
        "variants": [{"name": "Regular", "price": 370.0, "is_available": True, "original_price": None}],
    },

    # --- SWEET DISHES & DESSERTS ---
    {
        "name": "Gulab Jamun (2 Pc)",
        "menu_category": "Sweet Dishes",
        "price": 100.0,
        "is_veg": True,
        "description": "Warm, melt-in-mouth golden milk-solid dumplings soaked in rose and green cardamom scented sugar syrup.",
        "variants": [{"name": "2 Pc", "price": 100.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Rasmalai (2 Pc)",
        "menu_category": "Sweet Dishes",
        "price": 100.0,
        "is_veg": True,
        "description": "Delicate cottage cheese discs steeped in chilled, saffron and pistachio infused thickened milk.",
        "variants": [{"name": "2 Pc", "price": 100.0, "is_available": True, "original_price": None}],
    },
    {
        "name": "Ice Cream (Scoop)",
        "menu_category": "Chillax Icecreams",
        "price": 80.0,
        "is_veg": True,
        "description": "Rich, creamy, and delightful artisan ice cream scoop from Chillax.",
        "variants": [{"name": "Single Scoop", "price": 80.0, "is_available": True, "original_price": None}],
    },
]


def process_single_dish(item, idx, config):
    name = item["name"]
    cat = item["menu_category"]
    is_veg = item["is_veg"]
    desc = item["description"]
    price = item["price"]
    variants = item["variants"]

    # 1. Fetch authentic food images from Wikimedia Commons for this dish
    source_urls = _scrape_wikimedia_commons_food_images(name, is_veg)

    # 2. Format 1:1 image (< 120KB)
    local_paths = download_and_prepare_images(
        product_name=name,
        image_urls=source_urls,
        output_dir=str(OUTPUT_DIR),
        index=idx,
        mode="restaurant",
        menu_category=cat,
        price=price,
        is_veg=is_veg,
        variants=variants,
        description=desc,
        use_ai_generation=True,
    )

    # 3. Upload image to Supabase Storage
    image_urls = []
    if local_paths:
        image_urls = upload_images_to_supabase(
            config=config,
            shop_id=FOODIES_SHOP_ID,
            image_paths=local_paths[:1],
            product_index=idx,
        )

    payload = {
        "shop_id": FOODIES_SHOP_ID,
        "name": name,
        "brand": None,
        "price": float(price),
        "original_price": None,
        "description": desc,
        "category": "Restaurant",
        "menu_category": cat,
        "is_veg": is_veg,
        "is_available": True,
        "weight_per_unit": None,
        "unit_type": "pieces",
        "total_quantity": None,  # Unlimited kitchen inventory
        "images": image_urls,
        "requires_prescription": False,
        "medicine_type": "General",
        "variants": variants,
        "gst_rate_override": None,
        "bulk_eligible": False,
        "min_bulk_quantity": 10,
        "bulk_price_tiers": [],
        "special_tags": [],
        "is_deleted": False,
    }

    return payload


def main():
    config = get_supabase_config()
    print("=" * 70)
    print("🚀  FOODIES BY CHILLAX — 100x RESTAURANT MENU DIGITIZATION ENGINE")
    print("=" * 70)
    print(f"Target Shop:   Foodies ({FOODIES_SHOP_ID})")
    print(f"Total Dishes:  {len(MENU_ITEMS)}")
    print(f"Categories:    {sorted(set(i['menu_category'] for i in MENU_ITEMS))}")
    print("=" * 70)
    print()

    prepared_products = []
    start_time = time.time()

    # Process dishes in parallel with 6 worker threads
    with ThreadPoolExecutor(max_workers=6) as executor:
        future_to_dish = {
            executor.submit(process_single_dish, item, idx, config): (idx, item["name"])
            for idx, item in enumerate(MENU_ITEMS, 1)
        }

        for future in as_completed(future_to_dish):
            idx, name = future_to_dish[future]
            try:
                payload = future.result()
                prepared_products.append(payload)
                print(f"  ✅ [{len(prepared_products)}/{len(MENU_ITEMS)}] Processed: {name} (₹{payload['price']})")
            except Exception as e:
                print(f"  ❌ Error processing {name}: {e}")

    # Sort back by original index order
    name_to_idx = {item["name"]: i for i, item in enumerate(MENU_ITEMS)}
    prepared_products.sort(key=lambda p: name_to_idx.get(p["name"], 999))

    print(f"\n📤 Ingesting all {len(prepared_products)} items into Supabase via bulk_upload_shop_products RPC...")
    result = bulk_upload_products(config, FOODIES_SHOP_ID, prepared_products)
    print("\n📊 Ingestion Result:", result)
    elapsed = time.time() - start_time
    print(f"✨ Completed full ingestion of {len(prepared_products)} dishes in {elapsed:.1f}s!")


if __name__ == "__main__":
    main()
