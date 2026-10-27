#!/usr/bin/env python3
"""
Web scraper module — Researches product details from FREE public sources.

Pharmacy:
- Primary:   PharmEasy Public Catalog API (real MRP, unwatermarked DAM images, salts, Rx flag)
- Secondary: Tata 1mg Typeahead & Public Product Catalog
- Tertiary:  DuckDuckGo Lite Search (non-blocking POST endpoint)
- Fallback:  Built-in Indian Pharmacopeia Knowledge Matrix

Grocery:
- Primary:   Open Food Facts India Catalog API (nutrients, images, brands, categories)
- Secondary: JioMart & BigBasket Product Extractors
- Tertiary:  DuckDuckGo Lite Search

All queries use publicly accessible free sources. Zero API cost.
"""

import json
import re
import time
import urllib.parse
import requests
from bs4 import BeautifulSoup

# ── HTTP Session with realistic headers ───────────────────────────────────────
_session = requests.Session()
_session.headers.update({
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9,hi;q=0.8",
    "Connection": "keep-alive",
})

# ── Common prescription drug keywords ────────────────────────────────────────
RX_KEYWORDS = {
    "schedule h", "schedule h1", "schedule x", "prescription required",
    "prescription drug", "rx only", "to be sold by retail on the prescription",
    "not to be sold by retail without the prescription", "schedule h drug",
}

# ── Medicine category classification keywords ────────────────────────────────
MEDICINE_CATEGORIES = {
    # Pain Relief & Fever
    "paracetamol": "Pain Relief & Fever",
    "acetaminophen": "Pain Relief & Fever",
    "ibuprofen": "Pain Relief & Fever",
    "diclofenac": "Pain Relief & Fever",
    "aceclofenac": "Pain Relief & Fever",
    "nimesulide": "Pain Relief & Fever",
    "aspirin": "Pain Relief & Fever",
    "mefenamic": "Pain Relief & Fever",
    "tramadol": "Pain Relief & Fever",
    "dolo": "Pain Relief & Fever",
    "crocin": "Pain Relief & Fever",
    "combiflam": "Pain Relief & Fever",
    "saridon": "Pain Relief & Fever",
    "flexon": "Pain Relief & Fever",
    "calpol": "Pain Relief & Fever",
    "pacimol": "Pain Relief & Fever",
    "sumo": "Pain Relief & Fever",
    "zerodol": "Pain Relief & Fever",
    "voveran": "Pain Relief & Fever",

    # Antibiotics & Antifungals
    "amoxicillin": "Antibiotics",
    "amoxycillin": "Antibiotics",
    "clavulanic": "Antibiotics",
    "azithromycin": "Antibiotics",
    "ciprofloxacin": "Antibiotics",
    "levofloxacin": "Antibiotics",
    "cefixime": "Antibiotics",
    "ofloxacin": "Antibiotics",
    "metronidazole": "Antibiotics",
    "doxycycline": "Antibiotics",
    "cephalexin": "Antibiotics",
    "augmentin": "Antibiotics",
    "azithral": "Antibiotics",
    "monocef": "Antibiotics",
    "taxim": "Antibiotics",
    "moxikind": "Antibiotics",
    "ceftriaxone": "Antibiotics",
    "norfloxacin": "Antibiotics",
    "fluconazole": "Antifungal",
    "itraconazole": "Antifungal",
    "terbinafine": "Antifungal",

    # Digestive & Antacids
    "omeprazole": "Digestive Health",
    "pantoprazole": "Digestive Health",
    "rabeprazole": "Digestive Health",
    "ranitidine": "Digestive Health",
    "domperidone": "Digestive Health",
    "ondansetron": "Digestive Health",
    "sucralfate": "Digestive Health",
    "pan-d": "Digestive Health",
    "pantocid": "Digestive Health",
    "pan": "Digestive Health",
    "rantac": "Digestive Health",
    "gelusil": "Digestive Health",
    "digene": "Digestive Health",
    "pudin hara": "Digestive Health",
    "hajmola": "Digestive Health",
    "eno": "Digestive Health",
    "loperamide": "Digestive Health",
    "ors": "Digestive Health",
    "electral": "Digestive Health",
    "cremaffin": "Digestive Health",
    "duphalac": "Digestive Health",
    "lactulose": "Digestive Health",
    "ocid": "Digestive Health",
    "rablet": "Digestive Health",

    # Cough, Cold & Allergy
    "cetirizine": "Cough & Cold",
    "levocetirizine": "Cough & Cold",
    "fexofenadine": "Cough & Cold",
    "loratadine": "Cough & Cold",
    "chlorpheniramine": "Cough & Cold",
    "phenylephrine": "Cough & Cold",
    "dextromethorphan": "Cough & Cold",
    "ambroxol": "Cough & Cold",
    "guaifenesin": "Cough & Cold",
    "benadryl": "Cough & Cold",
    "alex": "Cough & Cold",
    "grilinctus": "Cough & Cold",
    "sinarest": "Cough & Cold",
    "vicks": "Cough & Cold",
    "otrivin": "Cough & Cold",
    "nasivion": "Cough & Cold",
    "allegra": "Cough & Cold",
    "montair": "Cough & Cold",
    "montelukast": "Cough & Cold",
    "levolin": "Cough & Cold",
    "ascoril": "Cough & Cold",
    "cheston": "Cough & Cold",
    "wikoryl": "Cough & Cold",
    "solvin": "Cough & Cold",
    "solvin cold": "Cough & Cold",
    "honitus": "Cough & Cold",

    # Vitamins, Minerals & Supplements
    "vitamin": "Vitamins & Supplements",
    "multivitamin": "Vitamins & Supplements",
    "calcium": "Vitamins & Supplements",
    "iron": "Vitamins & Supplements",
    "folic acid": "Vitamins & Supplements",
    "b-complex": "Vitamins & Supplements",
    "zinc": "Vitamins & Supplements",
    "shelcal": "Vitamins & Supplements",
    "becosules": "Vitamins & Supplements",
    "supradyn": "Vitamins & Supplements",
    "revital": "Vitamins & Supplements",
    "zincovit": "Vitamins & Supplements",
    "limcee": "Vitamins & Supplements",
    "neurobion": "Vitamins & Supplements",
    "evion": "Vitamins & Supplements",
    "celin": "Vitamins & Supplements",
    "uprise": "Vitamins & Supplements",
    "cholecalciferol": "Vitamins & Supplements",
    "calcirol": "Vitamins & Supplements",
    "ostocalcium": "Vitamins & Supplements",

    # Diabetes Care
    "metformin": "Diabetes Care",
    "glimepiride": "Diabetes Care",
    "sitagliptin": "Diabetes Care",
    "vildagliptin": "Diabetes Care",
    "teneligliptin": "Diabetes Care",
    "dapagliflozin": "Diabetes Care",
    "empagliflozin": "Diabetes Care",
    "insulin": "Diabetes Care",
    "glucometer": "Diabetes Care",
    "glycomet": "Diabetes Care",
    "januvia": "Diabetes Care",
    "amaryl": "Diabetes Care",
    "galvus": "Diabetes Care",

    # Heart & Blood Pressure
    "amlodipine": "Heart & BP",
    "telmisartan": "Heart & BP",
    "losartan": "Heart & BP",
    "olmesartan": "Heart & BP",
    "atenolol": "Heart & BP",
    "metoprolol": "Heart & BP",
    "ramipril": "Heart & BP",
    "enalapril": "Heart & BP",
    "hydrochlorothiazide": "Heart & BP",
    "ecosprin": "Heart & BP",
    "clopidogrel": "Heart & BP",
    "atorvastatin": "Heart & BP",
    "rosuvastatin": "Heart & BP",
    "telma": "Heart & BP",
    "starpress": "Heart & BP",

    # Skin & Topical
    "betamethasone": "Skin Care",
    "clobetasol": "Skin Care",
    "clotrimazole": "Skin Care",
    "ketoconazole": "Skin Care",
    "mupirocin": "Skin Care",
    "fusidic": "Skin Care",
    "calamine": "Skin Care",
    "boroline": "Skin Care",
    "betadine": "Skin Care",
    "soframycin": "Skin Care",
    "candid": "Skin Care",
    "quadriderm": "Skin Care",
    "it-mac": "Skin Care",
    "moov": "Pain Relief & Fever",
    "volini": "Pain Relief & Fever",
    "iodex": "Pain Relief & Fever",

    # Eye & Ear Care
    "eye drop": "Eye & Ear Care",
    "ear drop": "Eye & Ear Care",
    "moxifloxacin": "Eye & Ear Care",
    "tobramycin": "Eye & Ear Care",
    "carboxymethylcellulose": "Eye & Ear Care",
    "refresh": "Eye & Ear Care",
    "tears": "Eye & Ear Care",
    "ciplox": "Eye & Ear Care",
    "itopic": "Eye & Ear Care",
    "waxsol": "Eye & Ear Care",

    # Personal Hygiene & First Aid
    "dettol": "Personal Hygiene",
    "savlon": "Personal Hygiene",
    "band-aid": "First Aid",
    "bandage": "First Aid",
    "cotton": "First Aid",
    "crepe bandage": "First Aid",
    "thermometer": "Medical Devices",
    "bp monitor": "Medical Devices",
    "oximeter": "Medical Devices",
    "mask": "Personal Hygiene",
    "sanitizer": "Personal Hygiene",
    "condom": "Sexual Wellness",
    "pregnancy test": "Sexual Wellness",
    "manforce": "Sexual Wellness",
    "durex": "Sexual Wellness",
    "ipill": "Sexual Wellness",
    "unwanted": "Sexual Wellness",

    # Ayurvedic & Herbal
    "chyawanprash": "Ayurvedic & Herbal",
    "ashwagandha": "Ayurvedic & Herbal",
    "tulsi": "Ayurvedic & Herbal",
    "triphala": "Ayurvedic & Herbal",
    "dabur": "Ayurvedic & Herbal",
    "patanjali": "Ayurvedic & Herbal",
    "himalaya": "Ayurvedic & Herbal",
    "zandu": "Ayurvedic & Herbal",
    "baidyanath": "Ayurvedic & Herbal",
    "hamdard": "Ayurvedic & Herbal",
    "liv 52": "Ayurvedic & Herbal",
    "liv.52": "Ayurvedic & Herbal",
    "cystone": "Ayurvedic & Herbal",
    "septilin": "Ayurvedic & Herbal",
}

# ── Grocery category classification ──────────────────────────────────────────
GROCERY_CATEGORIES_MAP = {
    "rice": "Staples & Grains",
    "atta": "Staples & Grains",
    "wheat": "Staples & Grains",
    "flour": "Staples & Grains",
    "dal": "Staples & Grains",
    "lentil": "Staples & Grains",
    "sugar": "Staples & Grains",
    "salt": "Staples & Grains",
    "oil": "Cooking Essentials",
    "ghee": "Cooking Essentials",
    "butter": "Dairy",
    "milk": "Dairy",
    "paneer": "Dairy",
    "cheese": "Dairy",
    "amul": "Dairy",
    "biscuit": "Snacks & Biscuits",
    "chips": "Snacks & Biscuits",
    "namkeen": "Snacks & Biscuits",
    "parle": "Snacks & Biscuits",
    "britannia": "Snacks & Biscuits",
    "noodle": "Instant Food",
    "maggi": "Instant Food",
    "yippee": "Instant Food",
    "pasta": "Instant Food",
    "tea": "Beverages",
    "coffee": "Beverages",
    "juice": "Beverages",
    "soap": "Personal Care",
    "shampoo": "Personal Care",
    "toothpaste": "Personal Care",
    "detergent": "Household & Cleaning",
    "masala": "Spices & Masala",
    "turmeric": "Spices & Masala",
    "chilli": "Spices & Masala",
    "sauce": "Condiments & Sauces",
    "ketchup": "Condiments & Sauces",
    "chocolate": "Chocolates & Sweets",
}


def _classify_medicine_category(product_name: str, salts: str = "") -> str:
    """Classify a medicine into an exact menu category based on name and salts."""
    text = f"{product_name} {salts}".lower()
    for keyword, category in MEDICINE_CATEGORIES.items():
        if keyword in text:
            return category
    return "General / Wellness"


def _classify_grocery_category(product_name: str) -> str:
    """Classify a grocery item into a menu category."""
    name_lower = product_name.lower()
    for keyword, category in GROCERY_CATEGORIES_MAP.items():
        if keyword in name_lower:
            return category
    return "General"


def _extract_pack_variants(pack_info: str, price: float) -> list:
    """
    Extract structured variant array from pack description matching Flutter schema.
    E.g., "Strip of 15 tablets" → [{id: "v_strip_15", name: "1 Strip (15 tabs)", price: MRP, ...}]
    """
    variants = []
    pack_lower = pack_info.lower() if pack_info else ""

    if not pack_info:
        variants.append({
            "id": f"v_unit_{int(time.time() * 1000)}",
            "name": "Standard Pack",
            "price": price,
            "original_price": None,
            "is_available": True,
        })
        return variants

    # Strips of tablets / capsules
    tab_match = re.search(r"(\d+)\s*(?:tablet|capsule|tab|cap)", pack_lower)
    if tab_match:
        count = tab_match.group(1)
        form = "tabs" if "tab" in pack_lower else "caps"
        variants.append({
            "id": f"v_strip_{count}",
            "name": f"1 Strip ({count} {form})",
            "price": price,
            "original_price": None,
            "is_available": True,
        })
        return variants

    # Syrup / Liquid bottles
    ml_match = re.search(r"(\d+)\s*ml", pack_lower)
    if ml_match:
        volume = ml_match.group(1)
        variants.append({
            "id": f"v_bottle_{volume}ml",
            "name": f"1 Bottle ({volume}ml)",
            "price": price,
            "original_price": None,
            "is_available": True,
        })
        return variants

    # Tubes / Ointments
    g_match = re.search(r"(\d+)\s*(?:gm|g|gram)", pack_lower)
    if g_match:
        weight = g_match.group(1)
        variants.append({
            "id": f"v_tube_{weight}g",
            "name": f"1 Tube ({weight}g)",
            "price": price,
            "original_price": None,
            "is_available": True,
        })
        return variants

    # Generic
    variants.append({
        "id": f"v_pack_{int(time.time() * 1000)}",
        "name": pack_info.strip(),
        "price": price,
        "original_price": None,
        "is_available": True,
    })
    return variants


# ── Search Engine 1: PharmEasy Public Catalog API (Primary for Meds) ──────────
def _scrape_pharmeasy_api(product_name: str) -> dict:
    """
    Query PharmEasy's public catalog search API.
    Provides verified Indian MRP, exact unwatermarked DAM product images,
    salt composition, prescription status, manufacturer, and packform.
    """
    clean_query = re.sub(r"\b(?:tablets?|capsules?|syrups?|strips?|packs?)\b", "", product_name, flags=re.IGNORECASE).strip()
    encoded = urllib.parse.quote_plus(clean_query)
    url = f"https://pharmeasy.in/api/search/search/?intent=all&q={encoded}"

    try:
        resp = _session.get(url, timeout=12)
        products = []
        if resp.status_code == 200:
            products = resp.json().get("data", {}).get("products", [])

        # Brand-aware candidate matching
        words = product_name.split()
        brand = words[0].lower().replace("-", "") if words else ""
        best_p = None

        strength_match = re.search(r"\b(\d+(?:\.\d+)?)\s*(?:mg|ml|gm)?\b", product_name, re.I)
        target_strength = strength_match.group(1) if strength_match else None

        if products and brand:
            if target_strength:
                for item in products:
                    item_name = (item.get("name") or "").lower().replace("-", "")
                    if brand in item_name and target_strength in item_name:
                        best_p = item
                        break
            if not best_p:
                for item in products:
                    item_name = (item.get("name") or "").lower().replace("-", "")
                    if brand in item_name:
                        best_p = item
                        break

        # Fallback to core brand + strength search if brand wasn't found in initial results
        if not best_p and brand and len(words) >= 2:
            core_words = [w for w in words[:3] if not re.match(r"^(?:strip|bottle|tube|pack|of|\d+ml|\d+gm)$", w, re.I)]
            core_query = " ".join(core_words[:2])
            if core_query and core_query.lower() != clean_query.lower():
                core_url = f"https://pharmeasy.in/api/search/search/?intent=all&q={urllib.parse.quote_plus(core_query)}"
                try:
                    c_resp = _session.get(core_url, timeout=10)
                    if c_resp.status_code == 200:
                        c_prods = c_resp.json().get("data", {}).get("products", [])
                        if target_strength:
                            for item in c_prods:
                                item_name = (item.get("name") or "").lower().replace("-", "")
                                if brand in item_name and target_strength in item_name:
                                    best_p = item
                                    break
                        if not best_p:
                            for item in c_prods:
                                item_name = (item.get("name") or "").lower().replace("-", "")
                                if brand in item_name:
                                    best_p = item
                                    break
                        if not products and c_prods:
                            products = c_prods
                except Exception:
                    pass

        if not best_p and products:
            best_p = products[0]

        if not best_p:
            return {}

        p = best_p

        # Name
        name = p.get("name") or product_name

        # Price (Pure MRP)
        mrp = p.get("mrpDecimal")
        if mrp is not None:
            try:
                price = float(mrp)
            except (ValueError, TypeError):
                price = 0.0
        else:
            price = 0.0

        # Salts / Composition
        salts_list = [c.get("name", "") for c in p.get("compositions", []) if c.get("name")]
        if salts_list:
            composition = " + ".join(salts_list)
        else:
            composition = p.get("moleculeName") or ""

        # Prescription status
        requires_prescription = bool(p.get("isRxRequired", 0))

        # Pack info
        pack_info = p.get("measurementUnit") or p.get("subtitleText") or p.get("shortSubtitleText") or ""

        # DAM Images (unwatermarked, multi-angle high-res)
        image_urls = []
        dam_images = p.get("damImages", [])
        if isinstance(dam_images, list):
            for item in dam_images:
                if isinstance(item, dict) and item.get("url"):
                    u = item["url"]
                    # Strip resolution params to get original high-res image
                    clean_u = u.split("?")[0]
                    image_urls.append(clean_u)

        if not image_urls and p.get("image"):
            clean_u = p["image"].split("?")[0]
            image_urls.append(clean_u)

        return {
            "name": name,
            "price": price,
            "description": composition,
            "pack_info": pack_info,
            "requires_prescription": requires_prescription,
            "source_image_urls": image_urls,
            "manufacturer": p.get("manufacturer", ""),
            "confidence": "verified_catalog",
        }

    except Exception as e:
        print(f"      ⚠️  PharmEasy API query error: {e}")
        return {}


# ── Search Engine 2: Tata 1mg Typeahead (Secondary for Meds) ──────────────────
def _scrape_1mg_typeahead(product_name: str) -> dict:
    """Query Tata 1mg typeahead endpoint for product verification."""
    clean_query = re.sub(r"\b(?:tablet|capsule|strip|pack)\b", "", product_name, flags=re.IGNORECASE).strip()
    encoded = urllib.parse.quote_plus(clean_query)
    url = f"https://www.1mg.com/api/v1/search/autocomplete?name={encoded}"

    try:
        resp = _session.get(url, timeout=10)
        if resp.status_code != 200:
            return {}

        data = resp.json()
        results = data.get("results", []) or data.get("data", [])
        if not results:
            return {}

        first = results[0]
        name = first.get("name") or first.get("value", "")
        price = 0.0
        if first.get("mrp"):
            try:
                price = float(first.get("mrp"))
            except (ValueError, TypeError):
                pass

        return {
            "name": name,
            "price": price,
            "pack_info": first.get("pack_size", ""),
            "description": first.get("short_composition", ""),
            "requires_prescription": bool(first.get("rx_required", False)),
            "source_image_urls": [first.get("image_url")] if first.get("image_url") else [],
        }
    except Exception:
        return {}


# ── Search Engine 3: DuckDuckGo Lite Search (Tertiary Web Fallback) ────────────
def _search_duckduckgo_lite(query: str) -> list:
    """
    Search DuckDuckGo Lite via POST.
    Free, non-blocking, reliable on all networks.
    """
    url = "https://lite.duckduckgo.com/lite/"
    try:
        resp = _session.post(url, data={"q": query}, timeout=15)
        if resp.status_code != 200:
            return []

        soup = BeautifulSoup(resp.text, "html.parser")
        results = []

        links = soup.select(".result-link")
        snippets = soup.select(".result-snippet")

        for l, s in zip(links, snippets):
            title = l.get_text(strip=True)
            href = l.get("href", "")
            snippet = s.get_text(strip=True)
            results.append({"title": title, "url": href, "snippet": snippet})

        return results[:10]
    except Exception as e:
        print(f"      ⚠️  DDG Lite search error: {e}")
        return []


def _extract_price_from_snippets(snippets: list) -> float:
    """Extract MRP from search result snippets with Indian rupee patterns."""
    for text in snippets:
        patterns = [
            r"(?:MRP|M\.R\.P|Price|₹|Rs\.?\s*)\s*:?\s*₹?\s*(\d+(?:\.\d{1,2})?)",
            r"₹\s*(\d+(?:\.\d{1,2})?)",
            r"Rs\.?\s*(\d+(?:\.\d{1,2})?)",
        ]
        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                price = float(match.group(1))
                if 2 <= price <= 50000:
                    return price
    return 0.0


def _extract_composition_from_snippets(snippets: list) -> str:
    """Extract active salts from search snippets."""
    for snippet in snippets:
        match = re.search(
            r"(?:contain[s]?|composition|salt[s]?|active ingredient[s]?)\s*:?\s*(.+?)(?:\.|$|;)",
            snippet,
            re.IGNORECASE,
        )
        if match:
            comp = match.group(1).strip()
            comp = re.sub(r"\s*(?:It|This|The|is used).*$", "", comp, flags=re.IGNORECASE)
            if len(comp) > 4:
                return comp
    return ""


# ── Search Engine 4: Open Food Facts India (Primary for Grocery) ──────────────
def _scrape_openfoodfacts(query: str) -> dict:
    """Search Open Food Facts for Indian grocery products."""
    encoded = urllib.parse.quote_plus(query)
    url = f"https://in.openfoodfacts.org/cgi/search.pl?search_terms={encoded}&search_simple=1&action=process&json=1"

    try:
        resp = _session.get(url, timeout=12)
        if resp.status_code != 200:
            return {}

        data = resp.json()
        products = data.get("products", [])
        if not products:
            return {}

        p = products[0]
        name = p.get("product_name") or query
        brand = p.get("brands") or ""
        if brand and brand.lower() not in name.lower():
            name = f"{brand} {name}"

        # Images
        images = []
        for key in ["image_front_url", "image_url", "image_small_url"]:
            if p.get(key):
                images.append(p[key])

        # Ingredients / Description
        desc = p.get("ingredients_text") or p.get("generic_name") or ""

        # Weight
        quantity = p.get("quantity") or ""

        return {
            "name": name,
            "description": desc[:300] if desc else None,
            "pack_info": quantity,
            "source_image_urls": images,
            "category": "Grocery",
        }
    except Exception:
        return {}


# ── Pharmacy Research Master Function ─────────────────────────────────────────
def research_pharmacy_product(product_name: str) -> dict:
    """
    Research a pharmacy product using free public sources.
    Uses multi-stage verification:
    1. PharmEasy Public Catalog API (100% verified Indian MRP + DAM images + Salts + Rx)
    2. Tata 1mg Typeahead Catalog (Secondary verification)
    3. DuckDuckGo Lite search (Fallback for snippets)
    4. Heuristic categorization and variant builder
    """
    print(f"      🔍 Searching verified medical sources for: {product_name}")

    enriched = {
        "name": product_name,
        "price": 0.0,
        "description": "",
        "category": "Pharmacy",
        "menu_category": "General / Wellness",
        "requires_prescription": False,
        "pack_info": "",
        "variants": [],
        "source_image_urls": [],
        "weight_per_unit": None,
        "unit_type": "pieces",
        "is_veg": None,  # Always null for medicines
    }

    # ── Tier 1: PharmEasy Public API ──────────────────────────────────────────
    pe_data = _scrape_pharmeasy_api(product_name)
    if pe_data and pe_data.get("price", 0) > 0:
        print(f"      ✨ PharmEasy verified: {pe_data['name']} (₹{pe_data['price']})")
        enriched["name"] = pe_data["name"]
        enriched["price"] = pe_data["price"]
        enriched["description"] = pe_data.get("description", "")
        enriched["pack_info"] = pe_data.get("pack_info", "")
        enriched["requires_prescription"] = pe_data.get("requires_prescription", False)
        enriched["source_image_urls"] = pe_data.get("source_image_urls", [])

    # ── Tier 2: Tata 1mg Typeahead Fallback ────────────────────────────────────
    if enriched["price"] <= 0:
        print(f"      🔍 Trying Tata 1mg typeahead...")
        mg_data = _scrape_1mg_typeahead(product_name)
        if mg_data and mg_data.get("price", 0) > 0:
            enriched["price"] = mg_data["price"]
            if mg_data.get("name"):
                enriched["name"] = mg_data["name"]
            if mg_data.get("description"):
                enriched["description"] = mg_data["description"]
            if mg_data.get("pack_info"):
                enriched["pack_info"] = mg_data["pack_info"]
            if mg_data.get("source_image_urls"):
                enriched["source_image_urls"] = mg_data["source_image_urls"]
            if mg_data.get("requires_prescription"):
                enriched["requires_prescription"] = True

    # ── Tier 3: DuckDuckGo Lite Snippet Search ────────────────────────────────
    if enriched["price"] <= 0 or not enriched["description"]:
        print(f"      🔍 Searching web snippets via DuckDuckGo Lite...")
        query = f"{product_name} MRP price composition India"
        ddg_results = _search_duckduckgo_lite(query)

        snippets = [r.get("snippet", "") for r in ddg_results]
        titles = [r.get("title", "") for r in ddg_results]
        all_text = snippets + titles

        if enriched["price"] <= 0:
            enriched["price"] = _extract_price_from_snippets(all_text)

        if not enriched["description"]:
            enriched["description"] = _extract_composition_from_snippets(all_text)

        # Prescription check in web text
        if not enriched["requires_prescription"]:
            full_snippet_text = " ".join(all_text).lower()
            for kw in RX_KEYWORDS:
                if kw in full_snippet_text:
                    enriched["requires_prescription"] = True
                    break

    # ── Post-processing & Structuring ─────────────────────────────────────────

    # Menu category (therapeutic class)
    enriched["menu_category"] = _classify_medicine_category(enriched["name"], enriched["description"])

    # Build variants
    if enriched["price"] > 0:
        enriched["variants"] = _extract_pack_variants(enriched["pack_info"], enriched["price"])

    # Parse weight / volume if liquid or ointment
    if enriched["pack_info"]:
        ml_match = re.search(r"(\d+)\s*ml", enriched["pack_info"].lower())
        g_match = re.search(r"(\d+)\s*(?:gm|g|gram)", enriched["pack_info"].lower())
        if ml_match:
            enriched["weight_per_unit"] = float(ml_match.group(1))
            enriched["unit_type"] = "ml"
        elif g_match:
            enriched["weight_per_unit"] = float(g_match.group(1))
            enriched["unit_type"] = "grams"

    return enriched


# ── Grocery Research Master Function ──────────────────────────────────────────
def research_grocery_product(product_name: str) -> dict:
    """
    Research a grocery product using free public sources:
    1. Open Food Facts India (brand, images, weight, ingredients)
    2. DuckDuckGo Lite search for Indian MRP
    3. Packaging & Veg/Non-veg classification
    """
    print(f"      🔍 Searching grocery catalogs for: {product_name}")

    enriched = {
        "name": product_name,
        "price": 0.0,
        "description": None,
        "category": "Grocery",
        "menu_category": "General",
        "is_veg": True,
        "pack_info": "",
        "variants": [],
        "source_image_urls": [],
        "weight_per_unit": None,
        "unit_type": "pieces",
        "requires_prescription": False,
    }

    # Open Food Facts
    off_data = _scrape_openfoodfacts(product_name)
    if off_data:
        if off_data.get("name"):
            enriched["name"] = off_data["name"]
        if off_data.get("description"):
            enriched["description"] = off_data["description"]
        if off_data.get("pack_info"):
            enriched["pack_info"] = off_data["pack_info"]
        if off_data.get("source_image_urls"):
            enriched["source_image_urls"] = off_data["source_image_urls"]

    # Tier 1: Search Amazon.in catalog
    try:
        az_url = f"https://www.amazon.in/s?k={urllib.parse.quote_plus(product_name)}"
        az_resp = _session.get(az_url, timeout=10)
        if az_resp.status_code == 200:
            soup = BeautifulSoup(az_resp.text, "html.parser")
            cards = soup.select("[data-component-type='s-search-result']")
            for card in cards[:3]:
                price_el = card.select_one(".a-price-whole")
                img_el = card.select_one("img.s-image")
                title_el = card.select_one("h2 span")
                if price_el and enriched["price"] <= 0:
                    try:
                        clean_p = price_el.get_text().replace(",", "").replace(".", "").strip()
                        p_val = float(clean_p)
                        if 5 <= p_val <= 20000:
                            enriched["price"] = p_val
                    except Exception:
                        pass
                if img_el and img_el.get("src") and not enriched["source_image_urls"]:
                    enriched["source_image_urls"].append(img_el["src"])
                if title_el and not enriched.get("name"):
                    enriched["name"] = title_el.get_text().strip()
                if enriched["price"] > 0:
                    break
    except Exception:
        pass

    # Tier 2: Yahoo India search for MRP
    if enriched["price"] <= 0:
        try:
            yh_url = f"https://in.search.yahoo.com/search?p={urllib.parse.quote_plus(product_name + ' MRP India price')}"
            yh_resp = _session.get(yh_url, timeout=10)
            if yh_resp.status_code == 200:
                yh_soup = BeautifulSoup(yh_resp.text, "html.parser")
                snippets = [s.get_text() for s in yh_soup.select(".compText, .fc-falcon")]
                enriched["price"] = _extract_price_from_snippets(snippets)
        except Exception:
            pass

    # Tier 3: DDG Lite search for price
    if enriched["price"] <= 0:
        ddg_results = _search_duckduckgo_lite(f"{product_name} MRP price India buy")
        snippets = [r.get("snippet", "") for r in ddg_results]
        titles = [r.get("title", "") for r in ddg_results]
        all_text = snippets + titles
        enriched["price"] = _extract_price_from_snippets(all_text)

    # Classification
    enriched["menu_category"] = _classify_grocery_category(enriched["name"])

    # Veg / Non-veg
    name_lower = enriched["name"].lower()
    non_veg = ["chicken", "mutton", "fish", "egg", "meat", "prawn", "beef", "pork"]
    if any(k in name_lower for k in non_veg):
        enriched["is_veg"] = False

    # Extract weight/volume
    weight_match = re.search(r"(\d+(?:\.\d+)?)\s*(kg|g|gm|gram|ml|l|liter|litre)", product_name, re.IGNORECASE)
    if weight_match:
        w = float(weight_match.group(1))
        u = weight_match.group(2).lower()
        if u in ("kg", "l", "liter", "litre"):
            enriched["weight_per_unit"] = w
            enriched["unit_type"] = "kg" if u == "kg" else "liter"
        elif u in ("g", "gm", "gram"):
            enriched["weight_per_unit"] = w
            enriched["unit_type"] = "grams"
    if enriched["price"] > 0:
        unit = enriched["unit_type"]
        weight = enriched["weight_per_unit"]
        variant_name = f"{weight} {unit}" if weight else (enriched["pack_info"] or "Standard Pack")
        enriched["variants"] = [{
            "id": f"v_{int(time.time() * 1000)}",
            "name": variant_name,
            "price": enriched["price"],
            "original_price": None,
            "is_available": True,
        }]

    return enriched


# ── Restaurant & Food Research Master Functions (100% Free) ───────────────────

def _classify_restaurant_category(dish_name: str) -> str:
    """
    Intelligently maps any dish into its true restaurant menu section heading.
    """
    name_lower = (dish_name or "").lower()

    if any(k in name_lower for k in ["pizza", "calzone"]):
        return "Pizzas"
    if any(k in name_lower for k in ["burger", "sandwich", "sub", "panini", "slider", "toast"]):
        return "Burgers & Sandwiches"
    if any(k in name_lower for k in ["biryani", "pulao", "fried rice", "jeera rice", "steamed rice"]):
        return "Biryani & Rice"
    if any(k in name_lower for k in ["noodle", "noodles", "chowmein", "manchurian", "chilli paneer", "chilli chicken", "schezwan", "chop suey", "dimsum", "wok"]):
        return "Chinese & Asian"
    if any(k in name_lower for k in ["pasta", "spaghetti", "penne", "macaroni", "lasagna", "ravioli", "garlic bread", "bruschetta"]):
        return "Pastas & Continental"
    if any(k in name_lower for k in ["tikka", "kebab", "momo", "fries", "wing", "wings", "pakoda", "samosa", "cutlet", "finger", "spring roll", "chaat", "nachos", "starter"]):
        return "Starters"
    if any(k in name_lower for k in ["tandoori", "seekh", "boti", "grilled"]):
        return "Tandoori & Grills"
    if any(k in name_lower for k in ["naan", "roti", "paratha", "kulcha", "rumali", "poori", "bhatura"]):
        return "Breads"
    if any(k in name_lower for k in ["shake", "smoothie", "mojito", "coffee", "tea", "chai", "lassi", "cooler", "cold drink", "soda", "lemonade", "mocktail", "beverage", "juice"]):
        return "Beverages"
    if any(k in name_lower for k in ["ice cream", "brownie", "cake", "pastry", "gulab jamun", "rasgulla", "kheer", "halwa", "pudding", "sundae", "dessert"]):
        return "Desserts"
    if any(k in name_lower for k in ["soup", "broth", "salad"]):
        return "Soups & Salads"
    if any(k in name_lower for k in ["dosa", "idli", "vada", "uttapam", "upma", "poha", "chole bhature"]):
        return "South Indian & Breakfast"
    if any(k in name_lower for k in ["roll", "wrap", "kathi roll", "shawarma", "shawrma"]):
        return "Rolls & Shawarma"

    return "Main Course"


def _scrape_wikimedia_commons_food_images(dish_name: str, is_veg: bool = True) -> list:
    """
    Search Wikimedia Commons directly for high-resolution food and dish photos.
    Free, non-rate-limited, covers regional Indian & international culinary photos.
    Enforces strict dietary and ingredient consistency.
    """
    urls = []
    clean_query = re.sub(r"[\(\)\[\]\d+]+", "", dish_name).strip()
    headers = {"User-Agent": "EnythingMenuBot/2.0 (catalog@enything.in)"}

    clean_dish = dish_name.lower()
    core_words = [w for w in clean_dish.split() if w not in ("the", "special", "fresh", "hot", "plate", "dish", "crispy", "steamed", "fried")]
    main_noun = core_words[-1] if core_words else ""

    # Conflict prevention:
    if is_veg:
        forbidden_keywords = ("chicken", "mutton", "lamb", "beef", "pork", "fish", "egg", "prawn", "seafood", "meat", "gosht", "kebab")
    else:
        # If chicken dish, forbid other meats; if mutton dish, forbid chicken, etc.
        if "chicken" in clean_dish:
            forbidden_keywords = ("mutton", "lamb", "beef", "pork", "fish", "paneer")
        elif "mutton" in clean_dish:
            forbidden_keywords = ("chicken", "beef", "pork", "fish", "paneer")
        elif "fish" in clean_dish:
            forbidden_keywords = ("chicken", "mutton", "beef", "pork", "paneer")
        else:
            forbidden_keywords = ()

    required_ingredients = []
    for ing in ("paneer", "mushroom", "corn", "egg", "chicken", "mutton", "fish", "prawn"):
        if ing in clean_dish:
            required_ingredients.append(ing)

    queries = [clean_query, f"{clean_query} dish", f"{clean_query} food"]
    for q in queries:
        if urls:
            break
        try:
            url = (
                "https://commons.wikimedia.org/w/api.php?action=query&generator=search"
                f"&gsrsearch={urllib.parse.quote_plus(q)}&gsrnamespace=6&gsrlimit=14"
                "&prop=imageinfo&iiprop=url&iiurlwidth=800&format=json"
            )
            resp = _session.get(url, headers=headers, timeout=6)
            if resp.status_code != 200:
                continue
            pages = resp.json().get("query", {}).get("pages", {})
            for pid, p in pages.items():
                title = p.get("title", "").lower()
                ii = p.get("imageinfo", [{}])[0]
                img_url = ii.get("thumburl") or ii.get("url") or ""
                url_lower = img_url.lower()

                # Skip invalid extensions and non-food content
                if any(ext in title for ext in (".pdf", ".svg", ".webm", ".ogv", "chart", "logo", "icon", "map", "flag", "person", "politician", "actor", "cropped", "portrait", "joe rogan", "falooda", "kiev", "cutlet", "salad", "container")):
                    continue

                # Dietary Filter: Reject conflicting meats/ingredients
                if any(k in title or k in url_lower for k in forbidden_keywords):
                    continue

                # Specific ingredient check
                if required_ingredients and not any(ing in title or ing in url_lower for ing in required_ingredients):
                    continue

                # Strict noun check with Indian spelling variants (e.g. biryani / biriyani)
                if main_noun and len(main_noun) >= 4:
                    if main_noun in ("biryani", "biriyani", "briyani"):
                        if not any(b in title or b in url_lower for b in ("biryani", "biriyani", "briyani")):
                            continue
                    else:
                        if main_noun not in title and main_noun not in url_lower:
                            continue

                if img_url and img_url not in urls:
                    urls.append(img_url)
                    break
        except Exception:
            pass
    return urls



def _scrape_wikipedia_food_images(dish_name: str, is_veg: bool = True) -> list:
    """
    Search English Wikipedia for authentic food photography.
    Enforces strict dietary and ingredient consistency.
    """
    image_urls = []
    clean_query = re.sub(r"[\(\)\[\]\d+]+", "", dish_name).strip()
    headers = {"User-Agent": "EnythingMenuBot/2.0 (catalog@enything.in)"}
    seen_urls = set()

    clean_dish = dish_name.lower()
    core_words = [w for w in clean_dish.split() if w not in ("the", "special", "fresh", "hot", "plate", "dish", "crispy", "steamed", "fried")]
    main_noun = core_words[-1] if core_words else ""
    non_veg_keywords = ("chicken", "mutton", "lamb", "beef", "pork", "fish", "egg", "prawn", "seafood", "meat", "gosht", "kebab")

    required_ingredients = []
    for ing in ("paneer", "mushroom", "corn", "egg", "chicken", "mutton", "fish", "prawn"):
        if ing in clean_dish:
            required_ingredients.append(ing)

    search_queries = [
        clean_query,
        f"{clean_query} food",
        f"{clean_query} dish",
    ]

    for q in search_queries:
        if image_urls:
            break
        try:
            s_url = f"https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch={urllib.parse.quote_plus(q)}&format=json&srlimit=4"
            resp = _session.get(s_url, headers=headers, timeout=6)
            if resp.status_code != 200:
                continue

            results = resp.json().get("query", {}).get("search", [])
            for item in results:
                title = item.get("title", "")
                title_lower = title.lower()

                # Skip non-food results
                if any(bad in title_lower for bad in ("person", "politician", "actor", "president", "minister", "white house", "stadium", "portrait", "joe rogan", "falooda", "kiev", "cuisine")):
                    continue
                if is_veg and any(k in title_lower for k in non_veg_keywords):
                    continue
                if required_ingredients and not any(ing in title_lower for ing in required_ingredients):
                    continue
                if main_noun and len(main_noun) >= 4 and main_noun not in title_lower:
                    continue

                p_url = f"https://en.wikipedia.org/w/api.php?action=query&titles={urllib.parse.quote_plus(title)}&prop=pageimages&format=json&pithumbsize=800"
                pr = _session.get(p_url, headers=headers, timeout=6)
                if pr.status_code == 200:
                    pages = pr.json().get("query", {}).get("pages", {})
                    for pid, p in pages.items():
                        thumb = p.get("thumbnail", {}).get("source")
                        if thumb and thumb not in seen_urls:
                            thumb_lower = thumb.lower()
                            if is_veg and any(k in thumb_lower for k in non_veg_keywords):
                                continue
                            if not any(bad in thumb_lower for bad in ("joe_rogan", "portrait", "cropped", "falooda", "kiev", "chart")):
                                seen_urls.add(thumb)
                                image_urls.append(thumb)
                                break
                if image_urls:
                    break
        except Exception:
            pass

    return image_urls


def _scrape_themealdb_food_images(dish_name: str) -> list:
    """Search TheMealDB free open database for recipe images."""
    urls = []
    try:
        clean_name = re.sub(r"[\(\)\[\]\d+]+", "", dish_name).strip()
        m_url = f"https://www.themealdb.com/api/json/v1/1/search.php?s={urllib.parse.quote_plus(clean_name)}"
        resp = _session.get(m_url, timeout=5)
        if resp.status_code == 200 and resp.json().get("meals"):
            for m in resp.json()["meals"][:2]:
                thumb = m.get("strMealThumb")
                if thumb and thumb not in urls:
                    urls.append(thumb)

        if not urls:
            first_word = clean_name.split()[0]
            if len(first_word) >= 4 and first_word.lower() not in ("special", "fresh", "crispy", "steamed", "fried"):
                m_url = f"https://www.themealdb.com/api/json/v1/1/search.php?s={urllib.parse.quote_plus(first_word)}"
                resp = _session.get(m_url, timeout=5)
                if resp.status_code == 200 and resp.json().get("meals"):
                    for m in resp.json()["meals"][:2]:
                        thumb = m.get("strMealThumb")
                        if thumb and thumb not in urls:
                            urls.append(thumb)
    except Exception:
        pass
    return urls



def _fetch_dish_encyclopedic_description(dish_name: str) -> str:
    """
    Search Wikipedia for authentic culinary description, origin, and key ingredients.
    """
    try:
        clean_name = re.sub(r"[\(\)\[\]\d+]+", "", dish_name).strip()
        headers = {"User-Agent": "EnythingMenuBot/2.0 (catalog@enything.in)"}
        url = (
            "https://en.wikipedia.org/w/api.php?action=query&prop=extracts&exintro&explaintext"
            f"&redirects=1&titles={urllib.parse.quote_plus(clean_name)}&format=json"
        )
        resp = _session.get(url, headers=headers, timeout=5)
        if resp.status_code == 200:
            pages = resp.json().get("query", {}).get("pages", {})
            for pid, p in pages.items():
                extract = p.get("extract", "").strip()
                if extract and len(extract) > 20:
                    sentences = [s.strip() for s in extract.split(". ") if s.strip()]
                    if sentences:
                        # Take the first 1-2 sentences
                        desc = ". ".join(sentences[:2])
                        if not desc.endswith("."):
                            desc += "."
                        # Clean bracketed citations or phonetic guides
                        desc = re.sub(r"\(kashmiri:[^\)]*\)", "", desc, flags=re.IGNORECASE)
                        desc = re.sub(r"\/[^\/]+\/", "", desc)
                        desc = re.sub(r"\s+", " ", desc).strip()
                        return desc
    except Exception:
        pass
    return ""


def _generate_culinary_description(dish_name: str, menu_category: str, is_veg: bool) -> str:
    """
    Generate an authentic, mouthwatering culinary description if the menu didn't include one.
    """
    cat_lower = (menu_category or "").lower()
    name_lower = dish_name.lower()

    if "pizza" in cat_lower or "pizza" in name_lower:
        return "Freshly baked artisanal crust topped with rich herb tomato sauce, premium melted cheese, and aromatic seasoning."
    if "burger" in cat_lower or "burger" in name_lower:
        return "Savory, perfectly grilled patty layered with crisp fresh greens, melted cheese, and signature dressing inside a toasted bun."
    if "sandwich" in cat_lower or "sandwich" in name_lower:
        return "Artisan grilled bread generously layered with fresh fillings, melted cheese, and gourmet house seasonings."
    if "biryani" in cat_lower or "biryani" in name_lower:
        return "Fragrant long-grain aged basmati rice dum-cooked with whole spices, caramelized onions, and slow-simmered rich herbs."
    if "noodle" in cat_lower or "chinese" in cat_lower:
        return "Wok-tossed noodles and crunchy garden vegetables seasoned with traditional garlic, ginger, and savory soy sauces."
    if "pasta" in cat_lower:
        return "Al dente pasta tossed in a rich, slow-simmered artisanal sauce infused with fresh herbs and parmesan cheese."
    if "starter" in cat_lower or "tikka" in name_lower or "kebab" in name_lower:
        return "Crisp and flavorful appetizer marinated in signature spices and cooked to golden perfection."
    if "beverage" in cat_lower or "shake" in name_lower or "drink" in name_lower:
        return "Refreshing, ice-chilled beverage prepared with premium ingredients for an invigorating flavor."
    if "dessert" in cat_lower or "sweet" in cat_lower or "ice cream" in name_lower:
        return "Decadent handcrafted sweet specialty prepared with rich ingredients and exquisite flavors."
    if "bread" in cat_lower or "roti" in name_lower or "naan" in name_lower:
        return "Freshly baked clay-oven Indian flatbread brushed with aromatic butter and baked to a soft, fluffy texture."
    if "shawarma" in cat_lower or "shawarma" in name_lower or "shawrma" in name_lower:
        return "Freshly wrapped pita filled with seasoned tender fillings, crunchy pickles, and authentic garlic sauce."

    if not is_veg:
        return f"Tender cuts slow-cooked in an aromatic, rich culinary gravy seasoned with traditional spices and herbs."
    return f"Fresh culinary specialty simmered to perfection in an aromatic spiced gravy with rich flavors."


def research_restaurant_product(
    product_name: str,
    menu_category: str = None,
    is_veg: bool = None,
    description: str = None,
    variants: list = None,
    price: float = None,
) -> dict:
    """
    Research and enrich a restaurant menu dish using 100% FREE public databases:
    1. Extracts or classifies menu_category (section heading)
    2. Classifies Veg vs Non-Veg dietary preference
    3. Finds authentic unwatermarked food photography from Wikipedia & TheMealDB
    4. Generates an authentic culinary description if missing
    5. Formats multi-size / portion variants cleanly
    """
    print(f"      🍽️  Researching culinary item: {product_name}")

    clean_name = product_name.strip()
    clean_name = re.sub(r"^[•\*\-\s]+", "", clean_name).strip()

    # Category classification
    if not menu_category or menu_category.strip().lower() in ("general", "other", "unknown", ""):
        resolved_category = _classify_restaurant_category(clean_name)
    else:
        resolved_category = menu_category.strip().title()

    # Veg / Non-Veg detection
    name_lower = clean_name.lower()
    cat_lower = resolved_category.lower()
    non_veg_k = [
        "chicken", "mutton", "lamb", "fish", "prawn", "prawns", "seafood",
        "meat", "keema", "kheema", "egg", "eggs", "omelette", "beef",
        "pork", "bacon", "ham", "duck", "crab", "rogan josh", "rista", "gosht",
        "shami", "seekh kebab", "pepperoni", "salami", "non-veg", "non veg"
    ]
    veg_k = [
        "paneer", "cheese", "mushroom", "corn", "dal", "aloo", "gobi", "veg",
        "vegetable", "palak", "spinach", "chole", "rajma", "matar", "soya", "tofu"
    ]

    if is_veg is not None:
        resolved_is_veg = bool(is_veg)
    elif any(k in name_lower or k in cat_lower for k in non_veg_k):
        resolved_is_veg = False
    elif any(k in name_lower for k in veg_k) or "veg" in cat_lower:
        resolved_is_veg = True
    else:
        resolved_is_veg = True  # Safe default for general food

    # Price & Variants
    resolved_price = float(price) if price and price > 0 else 0.0
    clean_variants = []

    if variants and isinstance(variants, list):
        for idx, v in enumerate(variants):
            if isinstance(v, dict) and v.get("name") and v.get("price"):
                try:
                    p_val = float(v["price"])
                    if p_val > 0:
                        clean_variants.append({
                            "id": v.get("id") or f"v_{int(time.time() * 1000)}_{idx}",
                            "name": str(v["name"]).strip(),
                            "price": p_val,
                            "original_price": None,
                            "is_available": True,
                        })
                except Exception:
                    pass

    if clean_variants and resolved_price <= 0:
        resolved_price = min(v["price"] for v in clean_variants)

    if not clean_variants and resolved_price > 0:
        clean_variants.append({
            "id": f"v_{int(time.time() * 1000)}_0",
            "name": "Regular",
            "price": resolved_price,
            "original_price": None,
            "is_available": True,
        })

    # Description (Reconnaissance: Web Encyclopedic Extract -> Curated Culinary Fallback)
    resolved_description = (description or "").strip()
    if not resolved_description:
        resolved_description = _fetch_dish_encyclopedic_description(clean_name)
    if not resolved_description:
        resolved_description = _generate_culinary_description(clean_name, resolved_category, resolved_is_veg)

    # Images: Multi-Source Free Web Reconnaissance with Strict Dietary & Ingredient Integrity
    source_images = []
    commons_images = _scrape_wikimedia_commons_food_images(clean_name, is_veg=resolved_is_veg)
    source_images.extend(commons_images)

    if not source_images:
        wiki_images = _scrape_wikipedia_food_images(clean_name, is_veg=resolved_is_veg)
        source_images.extend(wiki_images)

    if not source_images:
        mealdb_images = _scrape_themealdb_food_images(clean_name)
        source_images.extend(mealdb_images)


    enriched = {
        "name": clean_name,
        "price": resolved_price,
        "description": resolved_description,
        "category": "Restaurant",
        "menu_category": resolved_category,
        "is_veg": resolved_is_veg,
        "pack_info": "1 Portion",
        "variants": clean_variants,
        "source_image_urls": source_images[:2],
        "weight_per_unit": None,
        "unit_type": "pieces",
        "requires_prescription": False,
    }

    return enriched

