#!/usr/bin/env python3
"""
Test packshot fetcher for Batch 1 products.
Finds 2 authentic photoshoot photos of the physical product bottle/pack on pure white background.
"""

import io
import re
import os
import sys
import time
import urllib.parse
import requests
from PIL import Image
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from scripts.auto_upload.ingest_maxx_retail_cosmetics import PRODUCTS_DATA

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
}

def make_square_padded(img, target_size=(800, 800), padding_ratio=0.04):
    """Pads image to 1:1 square on pure white background with subtle padding."""
    if img.mode in ('RGBA', 'LA'):
        bg = Image.new('RGB', img.size, (255, 255, 255))
        bg.paste(img, mask=img.split()[-1])
        img = bg
    elif img.mode != 'RGB':
        img = img.convert('RGB')
    
    w, h = img.size
    canvas_dim = int(max(w, h) * (1.0 + padding_ratio * 2))
    canvas = Image.new('RGB', (canvas_dim, canvas_dim), (255, 255, 255))
    offset_x = (canvas_dim - w) // 2
    offset_y = (canvas_dim - h) // 2
    canvas.paste(img, (offset_x, offset_y))
    return canvas.resize(target_size, Image.Resampling.LANCZOS)

def search_bing_images(query):
    url = f"https://www.bing.com/images/search?q={urllib.parse.quote(query)}&FORM=HDRSC2"
    try:
        r = requests.get(url, headers=HEADERS, timeout=8)
        if r.status_code != 200:
            return []
        matches = re.findall(r'murl&quot;:&quot;(http[^&]+)&quot;', r.text)
        if not matches:
            matches = re.findall(r'\"murl\":\"(http[^\"]+)\"', r.text)
        return matches
    except Exception:
        return []

def download_and_validate_image(url):
    """Downloads image and checks if it's a valid, decently sized image."""
    try:
        clean_url = re.sub(r'l_watermark_[^/]+/', '', url)
        r = requests.get(clean_url, headers=HEADERS, timeout=8)
        if r.status_code != 200 or len(r.content) < 5000:
            return None
        img = Image.open(io.BytesIO(r.content))
        w, h = img.size
        if w < 200 or h < 200:
            return None
        # Must have reasonable aspect ratio (not a banner/stripe)
        ratio = max(w, h) / min(w, h)
        if ratio > 3.5:
            return None
        return img
    except Exception:
        return None

def test_fetch_all():
    out_dir = Path("scratch/batch1_photos")
    out_dir.mkdir(parents=True, exist_ok=True)
    
    results = []
    for idx, item in enumerate(PRODUCTS_DATA, 1):
        name = item["name"]
        brand = item["brand"]
        
        # Denver special pre-verified
        if "Denver Beer" in name:
            u1 = "https://onemg.gumlet.io/a_ignore,w_690,h_700,c_pad,q_auto,f_auto/e12768b73a354d27818196f00e847277.jpg"
            u2 = "https://onemg.gumlet.io/a_ignore,w_690,h_700,c_pad,q_auto,f_auto/a65b37e06c0b462ab27a5fddf700904f.jpg"
            img1 = download_and_validate_image(u1)
            img2 = download_and_validate_image(u2)
        else:
            # Query 1: Front packshot
            q1 = f"{brand} {name} bottle packshot white background"
            candidates1 = search_bing_images(q1)
            img1 = None
            used_url1 = None
            for c in candidates1:
                img1 = download_and_validate_image(c)
                if img1:
                    used_url1 = c
                    break
            
            # Query 2: Back or alternate angle
            q2 = f"{brand} {name} bottle back packaging white background"
            candidates2 = search_bing_images(q2)
            img2 = None
            for c in candidates2:
                if c == used_url1:
                    continue
                img2 = download_and_validate_image(c)
                if img2:
                    break
            
            # Fallback for angle 2 if back query didn't find second image
            if not img2:
                for c in candidates1[1:]:
                    if c == used_url1:
                        continue
                    img2 = download_and_validate_image(c)
                    if img2:
                        break

        ok1 = img1 is not None
        ok2 = img2 is not None
        
        if ok1 and ok2:
            sq1 = make_square_padded(img1)
            sq2 = make_square_padded(img2)
            p1 = out_dir / f"maxx_cosmetics_{idx}_1.jpg"
            p2 = out_dir / f"maxx_cosmetics_{idx}_2.jpg"
            sq1.save(p1, "JPEG", quality=85)
            sq2.save(p2, "JPEG", quality=85)
            s1_kb = os.path.getsize(p1) // 1024
            s2_kb = os.path.getsize(p2) // 1024
            print(f"[{idx:02d}/46] ✅ {name[:40]} | Img1: {s1_kb}KB, Img2: {s2_kb}KB")
            results.append((idx, name, True))
        else:
            print(f"[{idx:02d}/46] ❌ {name[:40]} | img1={ok1}, img2={ok2}")
            results.append((idx, name, False))
        
        time.sleep(0.3)

    success_count = sum(1 for _, _, ok in results if ok)
    print(f"\nCompleted: {success_count}/46 successfully downloaded and padded.")

if __name__ == "__main__":
    test_fetch_all()
