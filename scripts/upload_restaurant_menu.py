#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════════════╗
║             ENYTHING — AUTO RESTAURANT MENU DIGITIZATION ENGINE              ║
║                                                                              ║
║  Automated Restaurant Menu Ingestion Pipeline:                               ║
║  1. Scans multi-page menu photos (Native Apple Vision Neural OCR or          ║
║     Gemini 2.0 Flash Vision free tier)                                       ║
║  2. Extracts Section Headings as `menu_category` (Pizzas, Burgers,           ║
║     Starters, Main Course, Biryani, Beverages, Desserts, etc.)               ║
║  3. Identifies Veg vs Non-Veg (FSSAI green/red dietary indicator)            ║
║  4. Parses multi-variant pricing (Half/Full, Small/Medium/Large, Pcs)        ║
║  5. Researches free unwatermarked food dish photos from Wikipedia &          ║
║     TheMealDB, or creates studio-grade 1:1 culinary cards                    ║
║  6. Formats exactly 2 distinct 1:1 (800x800) images guaranteed per item      ║
║  7. Uploads to Supabase products table enforcing soft-delete & schema rules  ║
║                                                                              ║
║  Cost: $0 — 100% Free Public APIs & Apple Silicon Local Acceleration         ║
╚══════════════════════════════════════════════════════════════════════════════╝

Usage Examples:
    # 1. From Menu Photos (Single or Multi-Page):
    python3 scripts/upload_restaurant_menu.py --menu page1.jpg,page2.jpg --shop-name "Kamrans Restaurant"

    # 2. Dry-Run Preview (Tests pipeline with zero database changes):
    python3 scripts/upload_restaurant_menu.py --menu menu_page1.jpg --shop-name "Kamrans Restaurant" --dry-run

    # 3. From Menu Items List or JSON:
    python3 scripts/upload_restaurant_menu.py --products "Pizzas > Margherita: 199, Main Course > Butter Chicken: 240" --shop-name "Kamrans Restaurant"
"""

import argparse
import os
import sys
from pathlib import Path

# Add script directory to module path
SCRIPT_DIR = Path(__file__).parent / "auto_upload"
sys.path.insert(0, str(SCRIPT_DIR))

from engine import run_engine


def main():
    parser = argparse.ArgumentParser(
        description="Enything Auto Restaurant Menu Digitization Engine",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--menu",
        "--image",
        dest="image",
        type=str,
        help="Path to menu photo or comma-separated page paths / glob (e.g. 'page1.jpg,page2.jpg' or 'menu/*.jpg')",
    )
    parser.add_argument(
        "--products",
        type=str,
        help="Comma-separated dishes or path to JSON file containing menu items",
    )
    parser.add_argument(
        "--shop-id",
        type=str,
        default=None,
        help="Target restaurant shop UUID",
    )
    parser.add_argument(
        "--shop-name",
        type=str,
        default="Kamrans Restaurant",
        help="Target restaurant name (defaults to 'Kamrans Restaurant')",
    )
    parser.add_argument(
        "--mode",
        choices=["restaurant", "food"],
        default="restaurant",
        help="Mode (defaults to restaurant)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate extraction, categorization, and card generation without writing to database",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        default=False,
        help="Update/overwrite existing products in shop with fresh OCR data and images",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Max number of menu items to process",
    )


    args = parser.parse_args()

    if not args.image and not args.products:
        parser.error("Must provide menu pictures via --menu / --image or dish list via --products")

    run_engine(args)


if __name__ == "__main__":
    main()
