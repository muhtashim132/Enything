#!/usr/bin/env python3
"""
Enything Multi-Platform App Store & Google Play Asset Generator
Generates pixel-perfect, framed, high-converting screenshots for:

[APPLE APP STORE]
- iPhone 6.5" Display: 1284 x 2778 px (Space Black flat-edge titanium frame, physical buttons)
- iPad 13" Display: 2048 x 2732 px (Tablet presentation)

[GOOGLE PLAY STORE]
- Phone: 1080 x 1920 px (Portrait 9:16, Aspect Ratio 1.77:1 <= 2:1, Android flagship frame)
- 7-Inch Tablet: 1200 x 1920 px (Portrait 10:16, Android 7" tablet frame)
- 10-Inch Tablet: 1600 x 2560 px (Portrait 10:16, Android 10" tablet frame)

Supports 2-batch ingestion for Android:
- Batch 1: Screens 1 to 4 (Customer Onboarding & Core Services)
- Batch 2: Screens 5 to 8 (Order Tracking & Partner Ecosystem)
"""

import os
import sys
import argparse
from io import BytesIO
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageColor, ImageOps

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(BASE_DIR, ".."))
FONTS_DIR = os.path.join(PROJECT_ROOT, "assets", "google_fonts")
DOWNLOADS_DIR = os.path.expanduser("~/Downloads")

# ── Directory Structure ───────────────────────────────────────────────────────
IOS_INPUT_DIR = os.path.join(BASE_DIR, "input_screenshots")
IOS_IPHONE_DIR = os.path.join(BASE_DIR, "ios", "screenshots", "iphone_6_5")
IOS_IPAD_DIR = os.path.join(BASE_DIR, "ios", "screenshots", "ipad_13")

ANDROID_INPUT_DIR = os.path.join(BASE_DIR, "android", "input_screenshots")
ANDROID_BATCH1_DIR = os.path.join(ANDROID_INPUT_DIR, "batch1")
ANDROID_BATCH2_DIR = os.path.join(ANDROID_INPUT_DIR, "batch2")
ANDROID_PHONE_DIR = os.path.join(BASE_DIR, "android", "screenshots", "phone")
ANDROID_TAB7_DIR = os.path.join(BASE_DIR, "android", "screenshots", "tablet_7")
ANDROID_TAB10_DIR = os.path.join(BASE_DIR, "android", "screenshots", "tablet_10")

for d in [
    IOS_IPHONE_DIR, IOS_IPAD_DIR,
    ANDROID_INPUT_DIR, ANDROID_BATCH1_DIR, ANDROID_BATCH2_DIR,
    ANDROID_PHONE_DIR, ANDROID_TAB7_DIR, ANDROID_TAB10_DIR
]:
    os.makedirs(d, exist_ok=True)

# ── Font loaders ─────────────────────────────────────────────────────────────
def get_font(name, size):
    path = os.path.join(FONTS_DIR, name)
    if os.path.exists(path):
        return ImageFont.truetype(path, size)
    for fallback in [
        "/System/Library/Fonts/SFPro-Bold.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/Library/Fonts/Arial.ttf",
    ]:
        if os.path.exists(fallback):
            return ImageFont.truetype(fallback, size)
    return ImageFont.load_default()

# ── 10 Curated Presets (Screens 1–8 for Google Play; Screens 1–10 for App Store)
PRESETS = [
    {
        "id": 1,
        "batch": 1,
        "badge": "🔄 ONE APP FOR EVERYONE",
        "title": "Customer, Seller & Rider",
        "subtitle": "Seamlessly switch roles or sign up with a single phone number",
        "image_file": "1.png",
        "theme": ("#060c2c", "#0e1f6e", "#1e3fd8", "#38bdf8"),
    },
    {
        "id": 2,
        "batch": 1,
        "badge": "⚡ HYPERLOCAL DELIVERY • J&K",
        "title": "Order Enything in Minutes",
        "subtitle": "Fresh food, groceries & daily essentials from your neighborhood",
        "image_file": "2.png",
        "theme": ("#060c2c", "#142d8d", "#1e3fd8", "#38bdf8"),
    },
    {
        "id": 3,
        "batch": 1,
        "badge": "💊 24/7 PHARMACY & ESSENTIALS",
        "title": "Medicines & Daily Needs",
        "subtitle": "Browse verified local pharmacies & get instant doorstep delivery",
        "image_file": "3.png",
        "theme": ("#022c22", "#047857", "#059669", "#10b981"),
    },
    {
        "id": 4,
        "batch": 1,
        "badge": "🍕 CRAVINGS DELIVERED FAST",
        "title": "Hot & Fresh Local Food",
        "subtitle": "From famous local dining to late-night snacks, order in a tap",
        "image_file": "4.png",
        "theme": ("#1e0826", "#991b1b", "#dc2626", "#ea580c"),
    },
    {
        "id": 5,
        "batch": 2,
        "badge": "📦 REAL-TIME ORDER UPDATES",
        "title": "Fast Order Confirmation",
        "subtitle": "Dual-confirmation dispatch ensures orders are prepared instantly",
        "image_file": "5.png",
        "theme": ("#0b0d33", "#1e1b4b", "#3730a3", "#6366f1"),
    },
    {
        "id": 6,
        "batch": 2,
        "badge": "📍 LIVE GPS ORDER RADAR",
        "title": "Track Your Order Live",
        "subtitle": "Watch your delivery rider approach your doorstep in real-time",
        "image_file": "6.png",
        "theme": ("#041e3a", "#0369a1", "#0284c7", "#38bdf8"),
    },
    {
        "id": 7,
        "batch": 2,
        "badge": "🏪 MERCHANT BUSINESS SUITE",
        "title": "Empowering Local Stores",
        "subtitle": "Manage catalog products, live analytics & payouts with ease",
        "image_file": "7.png",
        "theme": ("#0f172a", "#1e293b", "#334155", "#64748b"),
    },
    {
        "id": 8,
        "batch": 2,
        "badge": "🏍️ DELIVERY PARTNER HUB",
        "title": "Deliver & Earn Daily",
        "subtitle": "Flexible delivery missions with instant earnings in your area",
        "image_file": "8.png",
        "theme": ("#052e16", "#14532d", "#16a34a", "#22c55e"),
    },
    {
        "id": 9,
        "batch": 2,
        "badge": "🤝 DUAL-PARTY DISPATCH",
        "title": "Zero-Lag Order Dispatch",
        "subtitle": "Instant acceptance between merchants and nearby delivery partners",
        "image_file": "9.png",
        "theme": ("#1c1917", "#78350f", "#c2410c", "#f97316"),
    },
    {
        "id": 10,
        "batch": 2,
        "badge": "🧭 TURN-BY-TURN NAVIGATION",
        "title": "Smart Route Optimization",
        "subtitle": "Built-in Google Maps navigation for quickest pickup and delivery",
        "image_file": "10.png",
        "theme": ("#022c22", "#065f46", "#059669", "#34d399"),
    },
]

# ── Shared Drawing Utilities ──────────────────────────────────────────────────
def draw_vertical_gradient(width, height, top_color, mid_color, bot_color):
    base = Image.new("RGBA", (width, height))
    draw = ImageDraw.Draw(base)
    r1, g1, b1 = ImageColor.getrgb(top_color)
    r2, g2, b2 = ImageColor.getrgb(mid_color)
    r3, g3, b3 = ImageColor.getrgb(bot_color)
    
    mid_y = int(height * 0.45)
    
    for y in range(mid_y):
        t = y / max(1, mid_y)
        r = int(r1 + (r2 - r1) * t)
        g = int(g1 + (g2 - g1) * t)
        b = int(b1 + (b2 - b1) * t)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))
        
    for y in range(mid_y, height):
        t = (y - mid_y) / max(1, height - mid_y)
        r = int(r2 + (r3 - r2) * t)
        g = int(g2 + (g3 - g2) * t)
        b = int(b2 + (b3 - b2) * t)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))
        
    return base

def draw_radial_glow(canvas, center_x, center_y, radius, glow_hex, max_alpha=100):
    r, g, b = ImageColor.getrgb(glow_hex)
    glow = Image.new("RGBA", (radius * 2, radius * 2), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    
    steps = 50
    for i in range(steps, 0, -1):
        step_rad = int(radius * (i / steps))
        alpha = int(max_alpha * (1.0 - (i / steps)) ** 1.8)
        glow_draw.ellipse(
            [radius - step_rad, radius - step_rad, radius + step_rad, radius + step_rad],
            fill=(r, g, b, alpha)
        )
    
    canvas.alpha_composite(glow, (center_x - radius, center_y - radius))

def open_and_orient_image(path):
    """
    Opens an image file and correctly handles EXIF orientation so phone screenshots
    never appear rotated or inverted.
    """
    try:
        im = Image.open(path)
        im = ImageOps.exif_transpose(im)
        return im.convert("RGBA")
    except Exception:
        return Image.open(path).convert("RGBA")

def fit_screen_to_viewport(screen_img, target_w, target_h):
    """
    Scales and crops screen image to target dimensions without ANY aspect ratio distortion.
    Preserves top app bar/status bar alignment and centers horizontally.
    """
    img_w, img_h = screen_img.size
    scale = max(target_w / img_w, target_h / img_h)
    new_w = max(1, int(round(img_w * scale)))
    new_h = max(1, int(round(img_h * scale)))
    
    scaled = screen_img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    crop_x = max(0, (new_w - target_w) // 2)
    crop_y = 0  # Top anchor for headers/app bars
    return scaled.crop((crop_x, crop_y, crop_x + target_w, crop_y + target_h))

def load_screen_image(preset, platform="ios"):
    """
    Intelligently and robustly loads screen image for iOS or Android.
    Supports 2-batch ingestion:
    - Batch 1: Screens 1 to 4
    - Batch 2: Screens 5 to 8
    Supports multiple image formats (.png, .jpg, .jpeg, .webp) and automatic EXIF orientation.
    """
    num = preset["id"]
    file_name = preset["image_file"]
    batch_num = preset["batch"]
    batch_folder = f"batch{batch_num}"
    rel_num = num if batch_num == 1 else (num - 4)

    # Base stems to search
    name_stems = [
        str(num),
        str(rel_num),
        f"screen_{num}",
        f"Screen_{num}",
        f"screen{num}",
        f"Screen{num}",
        f"screenshot_{num}",
        f"Screenshot_{num}",
        f"screenshot{num}",
        f"Screenshot{num}",
    ]

    # Specific names mapped to preset functions
    if num == 1:
        name_stems.extend(["customer 1", "customer1", "onboarding", "role_select"])
    elif num == 2:
        name_stems.extend(["customer 2", "customer2", "home", "browse"])
    elif num == 3:
        name_stems.extend(["pharmacy", "medicine", "essentials"])
    elif num == 4:
        name_stems.extend(["food", "restaurant", "dining"])
    elif num == 5:
        name_stems.extend(["order", "tracking", "cart", "checkout"])
    elif num == 6:
        name_stems.extend(["map", "radar", "live_tracking"])
    elif num == 7:
        name_stems.extend(["seller 1", "seller 2", "seller1", "merchant"])
    elif num == 8:
        name_stems.extend(["Rider 1", "rider 1", "rider 2", "rider1", "delivery"])

    extensions = [".png", ".PNG", ".jpg", ".JPG", ".jpeg", ".JPEG", ".webp", ".WEBP"]

    # Directories to search
    search_dirs = []
    if platform == "android":
        search_dirs.extend([
            os.path.join(ANDROID_INPUT_DIR, batch_folder),
            ANDROID_INPUT_DIR,
            os.path.join(DOWNLOADS_DIR, "android screenshots"),
            os.path.join(DOWNLOADS_DIR, "android_screenshots"),
            os.path.join(DOWNLOADS_DIR, "Android Screenshots"),
            os.path.join(DOWNLOADS_DIR, batch_folder),
        ])

    # Universal fallback directories
    search_dirs.extend([
        IOS_INPUT_DIR,
        os.path.join(DOWNLOADS_DIR, "Ios screenshots 6.5"),
        os.path.join(DOWNLOADS_DIR, "ios screenshots 6.5"),
        DOWNLOADS_DIR,
    ])

    for d in search_dirs:
        if not os.path.isdir(d):
            continue
        # Direct filename check
        exact_path = os.path.join(d, file_name)
        if os.path.isfile(exact_path):
            return open_and_orient_image(exact_path)
            
        # Stems + extensions
        for stem in name_stems:
            for ext in extensions:
                cand = os.path.join(d, f"{stem}{ext}")
                if os.path.isfile(cand):
                    return open_and_orient_image(cand)

    # Fallback blank placeholder if no image file is found
    blank = Image.new("RGBA", (1080, 2400), (15, 23, 42, 255))
    return blank

# ==============================================================================
# 🍎 SECTION 1: APPLE APP STORE (iPhone 6.5" & iPad 13")
# ==============================================================================

def build_iphone_frame(screen_img, target_w):
    """
    Constructs an authentic Apple iPhone 6.5" Display (Pro/Plus) flat-edge chassis:
    - Precision Space Black / Titanium dual-rim frame
    - Physical hardware buttons (Action/Mute, Vol Up, Vol Down on left, Power on right)
    - Precision antenna isolation bands
    - Top ear-speaker slit in bezel
    - Authentic Apple squircle corner radius
    - Zero fake camera overlay (preserves native iOS status bar cleanly)
    """
    border_w = 12   # Outer titanium band
    bezel_w = 10    # Inner OLED bezel
    total_margin = border_w + bezel_w
    
    screen_w = target_w - total_margin * 2
    screen_h = int(screen_w * (2778 / 1284))
    
    frame_w = target_w
    frame_h = screen_h + total_margin * 2
    corner_r = 56
    screen_r = 44
    
    btn_w = 5
    canvas_w = frame_w + btn_w * 2 + 8
    canvas_h = frame_h + 8
    
    mockup = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(mockup)
    
    ox = btn_w + 4
    oy = 4
    
    # 1. Physical Apple Hardware Buttons
    btn_color = (38, 44, 56, 255)
    btn_border = (85, 98, 118, 255)
    
    # Left: Action/Mute toggle
    draw.rounded_rectangle([ox - btn_w, oy + 110, ox + 1, oy + 152], radius=2, fill=btn_color, outline=btn_border, width=1)
    # Left: Volume Up
    draw.rounded_rectangle([ox - btn_w, oy + 180, ox + 1, oy + 265], radius=2, fill=btn_color, outline=btn_border, width=1)
    # Left: Volume Down
    draw.rounded_rectangle([ox - btn_w, oy + 285, ox + 1, oy + 370], radius=2, fill=btn_color, outline=btn_border, width=1)
    # Right: Side / Power Button
    draw.rounded_rectangle([ox + frame_w - 1, oy + 210, ox + frame_w + btn_w, oy + 330], radius=2, fill=btn_color, outline=btn_border, width=1)
    
    # 2. Outer Titanium Band
    draw.rounded_rectangle(
        [ox, oy, ox + frame_w, oy + frame_h],
        radius=corner_r,
        fill=(22, 26, 34, 255),
        outline=(90, 102, 122, 255),
        width=2
    )
    
    # Inner metallic edge line
    draw.rounded_rectangle(
        [ox + 2, oy + 2, ox + frame_w - 2, oy + frame_h - 2],
        radius=corner_r - 2,
        outline=(44, 52, 65, 255),
        width=1
    )
    
    # Antenna bands
    antenna_col = (14, 17, 22, 255)
    for ay in [oy + 165, oy + frame_h - 165]:
        draw.line([(ox, ay), (ox + border_w, ay)], fill=antenna_col, width=2)
        draw.line([(ox + frame_w - border_w, ay), (ox + frame_w, ay)], fill=antenna_col, width=2)
        
    # 3. Inner Screen Bezel
    inner_x = ox + border_w
    inner_y = oy + border_w
    inner_w = frame_w - border_w * 2
    inner_h = frame_h - border_w * 2
    draw.rounded_rectangle(
        [inner_x, inner_y, inner_x + inner_w, inner_y + inner_h],
        radius=corner_r - border_w,
        fill=(4, 5, 7, 255)
    )
    
    # 4. Top Ear-Speaker Slit
    sp_w = 72
    sp_h = 4
    sp_x = ox + (frame_w - sp_w) // 2
    sp_y = inner_y + 3
    draw.rounded_rectangle([sp_x, sp_y, sp_x + sp_w, sp_y + sp_h], radius=2, fill=(16, 20, 26, 255), outline=(50, 60, 75, 255), width=1)
    
    # 5. Screen Viewport with Specular Glass Sheen
    scr_x = ox + total_margin
    scr_y = oy + total_margin
    scaled_screen = fit_screen_to_viewport(screen_img, screen_w, screen_h)
    
    sheen = Image.new("RGBA", (screen_w, screen_h), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(sheen)
    sh_draw.polygon([(0, 0), (int(screen_w * 0.65), 0), (0, int(screen_h * 0.45))], fill=(255, 255, 255, 14))
    scaled_screen.alpha_composite(sheen)
    
    mask = Image.new("L", (screen_w, screen_h), 0)
    m_draw = ImageDraw.Draw(mask)
    m_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=screen_r, fill=255)
    mockup.paste(scaled_screen, (scr_x, scr_y), mask)
    
    return mockup, canvas_w, canvas_h

def render_ios_screenshot(preset, is_ipad=False):
    W = 2048 if is_ipad else 1284
    H = 2732 if is_ipad else 2778
    
    top_c, mid_c, bot_c, glow_c = preset["theme"]
    canvas = draw_vertical_gradient(W, H, top_c, mid_c, bot_c)
    draw_radial_glow(canvas, W // 2, int(H * 0.60), int(W * 0.68), glow_c, max_alpha=110)
    
    draw = ImageDraw.Draw(canvas)
    badge_font = get_font("Outfit-Bold.ttf", 34 if is_ipad else 26)
    title_font = get_font("Outfit-Bold.ttf", 94 if is_ipad else 74)
    subtitle_font = get_font("Inter-Medium.ttf", 44 if is_ipad else 36)
    
    # Badge Pill
    badge_text = preset["badge"]
    badge_bbox = badge_font.getbbox(badge_text)
    badge_w = badge_bbox[2] - badge_bbox[0]
    badge_h = badge_bbox[3] - badge_bbox[1]
    
    pad_h = 20 if is_ipad else 16
    pad_w = 36 if is_ipad else 28
    pill_w = badge_w + pad_w * 2
    pill_h = badge_h + pad_h * 2
    pill_x = (W - pill_w) // 2
    pill_y = 150 if is_ipad else 130
    
    pill_overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    p_draw = ImageDraw.Draw(pill_overlay)
    p_draw.rounded_rectangle([pill_x, pill_y, pill_x + pill_w, pill_y + pill_h], radius=pill_h // 2, fill=(255, 255, 255, 30), outline=(255, 255, 255, 65), width=2)
    canvas.alpha_composite(pill_overlay)
    
    draw = ImageDraw.Draw(canvas)
    draw.text((pill_x + pad_w, pill_y + pad_h - (4 if is_ipad else 3)), badge_text, font=badge_font, fill=(255, 255, 255, 255))
    
    # Headline
    title_text = preset["title"]
    title_bbox = title_font.getbbox(title_text)
    title_w = title_bbox[2] - title_bbox[0]
    title_x = (W - title_w) // 2
    title_y = pill_y + pill_h + (36 if is_ipad else 28)
    draw.text((title_x, title_y + 4), title_text, font=title_font, fill=(0, 0, 0, 90))
    draw.text((title_x, title_y), title_text, font=title_font, fill=(255, 255, 255, 255))
    
    # Subtitle
    sub_text = preset["subtitle"]
    sub_bbox = subtitle_font.getbbox(sub_text)
    sub_w = sub_bbox[2] - sub_bbox[0]
    sub_x = (W - sub_w) // 2
    sub_y = title_y + (title_bbox[3] - title_bbox[1]) + (22 if is_ipad else 18)
    draw.text((sub_x, sub_y), sub_text, font=subtitle_font, fill=(255, 255, 255, 215))
    
    # Device Mockup
    raw_img = load_screen_image(preset, platform="ios")
    target_phone_w = 1060 if is_ipad else 1040
    device, canvas_w, canvas_h = build_iphone_frame(raw_img, target_phone_w)
    
    dev_x = (W - canvas_w) // 2
    dev_y = 450 if is_ipad else 490
    
    # Shadow
    shadow_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_img)
    s_draw.rounded_rectangle([dev_x + 30, dev_y + 40, dev_x + canvas_w - 30, dev_y + canvas_h + 30], radius=70, fill=(0, 0, 0, 180))
    shadow_blur = shadow_img.filter(ImageFilter.GaussianBlur(radius=50 if is_ipad else 42))
    canvas.alpha_composite(shadow_blur)
    canvas.alpha_composite(device, (dev_x, dev_y))
    
    return canvas.convert("RGB")

# ==============================================================================
# 🤖 SECTION 2: GOOGLE PLAY STORE (Phone 1080x1920, 7" & 10" Tablets)
# ==============================================================================

ANDROID_PRESETS = [
    # ── BATCH 1: Customer Shopping & Instant Checkout ────────────────────────
    {
        "id": 1,
        "batch": 1,
        "badge": "⚡ HYPERLOCAL DELIVERY • J&K",
        "title": "Order Enything in Minutes",
        "subtitle": "Fresh food, groceries & daily essentials from your neighborhood",
        "image_file": "1.png",
        "theme": ("#060c2c", "#0e1f6e", "#1e3fd8", "#38bdf8"),
    },
    {
        "id": 2,
        "batch": 1,
        "badge": "💊 24/7 PHARMACY & ESSENTIALS",
        "title": "Medicines & Daily Needs",
        "subtitle": "Browse verified local pharmacies & get instant doorstep delivery",
        "image_file": "2.png",
        "theme": ("#022c22", "#047857", "#059669", "#10b981"),
    },
    {
        "id": 3,
        "batch": 1,
        "badge": "🍕 CRAVINGS DELIVERED FAST",
        "title": "Hot & Fresh Local Food",
        "subtitle": "From famous local dining to late-night snacks, order in a tap",
        "image_file": "3.png",
        "theme": ("#1e0826", "#991b1b", "#dc2626", "#ea580c"),
    },
    {
        "id": 4,
        "batch": 1,
        "badge": "📦 FAST ORDER CONFIRMATION",
        "title": "Express Doorstep Checkout",
        "subtitle": "Instant address routing with 35–45 minute delivery times",
        "image_file": "4.png",
        "theme": ("#0b0d33", "#1e1b4b", "#3730a3", "#6366f1"),
    },
    # ── BATCH 2: Live Tracking & Partner Ecosystem ───────────────────────────
    {
        "id": 5,
        "batch": 2,
        "badge": "📍 LIVE GPS ORDER RADAR",
        "title": "Track Your Order Live",
        "subtitle": "Watch your delivery rider approach your doorstep in real-time",
        "image_file": "5.png",
        "theme": ("#041e3a", "#0369a1", "#0284c7", "#38bdf8"),
    },
    {
        "id": 6,
        "batch": 2,
        "badge": "🤝 DUAL-PARTY DISPATCH",
        "title": "Zero-Lag Order Dispatch",
        "subtitle": "Instant synchronized acceptance between merchants and delivery riders",
        "image_file": "6.png",
        "theme": ("#1c1917", "#78350f", "#c2410c", "#f97316"),
    },
    {
        "id": 7,
        "batch": 2,
        "badge": "🏪 MERCHANT BUSINESS SUITE",
        "title": "Empowering Local Stores",
        "subtitle": "Manage catalog products, live analytics & payouts with ease",
        "image_file": "7.png",
        "theme": ("#0f172a", "#1e293b", "#334155", "#64748b"),
    },
    {
        "id": 8,
        "batch": 2,
        "badge": "🏍️ DELIVERY PARTNER HUB",
        "title": "Deliver & Earn Daily",
        "subtitle": "Flexible delivery missions with instant earnings in your area",
        "image_file": "8.png",
        "theme": ("#052e16", "#14532d", "#16a34a", "#22c55e"),
    },
]

def build_android_phone_frame(screen_img, target_w=760):
    """
    Constructs an authentic Modern Android Flagship chassis:
    - Precision Armor Aluminum dark frame with sleek corner radius
    - Android hardware buttons on Right Side (Volume Rocker + Power Button)
    - Centered punch-hole selfie camera with subtle optical reflection
    - Symmetrical slim black bezel
    """
    border_w = 10
    bezel_w = 8
    total_margin = border_w + bezel_w
    
    screen_w = target_w - total_margin * 2
    screen_h = 1460  # Tailored for 1080x1920 canvas proportions
    
    frame_w = target_w
    frame_h = screen_h + total_margin * 2
    corner_r = 48
    screen_r = 34
    
    btn_w = 4
    canvas_w = frame_w + btn_w + 6
    canvas_h = frame_h + 6
    
    mockup = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(mockup)
    ox, oy = 2, 2
    
    # 1. Android Hardware Buttons (Right Side: Vol Rocker + Power)
    btn_col = (38, 44, 56, 255)
    btn_border = (80, 92, 110, 255)
    # Volume Rocker (Upper Right)
    draw.rounded_rectangle([ox + frame_w - 1, oy + 170, ox + frame_w + btn_w, oy + 280], radius=2, fill=btn_col, outline=btn_border, width=1)
    # Power Button (Mid Right)
    draw.rounded_rectangle([ox + frame_w - 1, oy + 310, ox + frame_w + btn_w, oy + 400], radius=2, fill=btn_col, outline=btn_border, width=1)
    
    # 2. Outer Armor Frame
    draw.rounded_rectangle([ox, oy, ox + frame_w, oy + frame_h], radius=corner_r, fill=(20, 24, 30, 255), outline=(75, 88, 105, 255), width=2)
    
    # 3. Inner OLED Bezel
    inner_x = ox + border_w
    inner_y = oy + border_w
    inner_w = frame_w - border_w * 2
    inner_h = frame_h - border_w * 2
    draw.rounded_rectangle([inner_x, inner_y, inner_x + inner_w, inner_y + inner_h], radius=corner_r - border_w, fill=(4, 5, 7, 255))
    
    # 4. Screen Viewport with Specular Glass Sheen
    scr_x = ox + total_margin
    scr_y = oy + total_margin
    scaled_screen = fit_screen_to_viewport(screen_img, screen_w, screen_h)
    
    sheen = Image.new("RGBA", (screen_w, screen_h), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(sheen)
    sh_draw.polygon([(0, 0), (int(screen_w * 0.65), 0), (0, int(screen_h * 0.45))], fill=(255, 255, 255, 14))
    scaled_screen.alpha_composite(sheen)
    
    mask = Image.new("L", (screen_w, screen_h), 0)
    m_draw = ImageDraw.Draw(mask)
    m_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=screen_r, fill=255)
    mockup.paste(scaled_screen, (scr_x, scr_y), mask)
    
    # 5. Centered Punch-Hole Camera (Subtle & authentic Android design)
    cam_size = 18
    cam_x = scr_x + (screen_w - cam_size) // 2
    cam_y = scr_y + 14
    draw.ellipse([cam_x, cam_y, cam_x + cam_size, cam_y + cam_size], fill=(0, 0, 0, 255))
    lens_inner = 8
    draw.ellipse(
        [cam_x + (cam_size - lens_inner) // 2, cam_y + (cam_size - lens_inner) // 2,
         cam_x + (cam_size + lens_inner) // 2, cam_y + (cam_size + lens_inner) // 2],
        fill=(15, 23, 42, 255)
    )
    
    return mockup, canvas_w, canvas_h

def build_android_tablet_frame(screen_img, target_w, target_h):
    """
    Constructs an authentic Android Tablet unibody frame (Galaxy Tab / Pixel Tablet):
    - Symmetrical slim metallic bezel
    - Centered camera sensor in the top bezel
    """
    border_w = 12
    bezel_w = 10
    total_margin = border_w + bezel_w
    
    screen_w = target_w - total_margin * 2
    screen_h = target_h - total_margin * 2
    corner_r = 40
    screen_r = 28
    
    mockup = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(mockup)
    
    # Outer metal chassis
    draw.rounded_rectangle([0, 0, target_w, target_h], radius=corner_r, fill=(24, 28, 36, 255), outline=(75, 88, 105, 255), width=2)
    # Inner black bezel
    draw.rounded_rectangle([border_w, border_w, target_w - border_w, target_h - border_w], radius=corner_r - border_w, fill=(5, 7, 10, 255))
    
    # Camera sensor in top bezel
    cam_x = target_w // 2
    cam_y = border_w // 2 + 2
    draw.ellipse([cam_x - 4, cam_y - 4, cam_x + 4, cam_y + 4], fill=(12, 16, 24, 255), outline=(40, 50, 65, 255), width=1)
    
    # Screen viewport
    scaled = fit_screen_to_viewport(screen_img, screen_w, screen_h)
    mask = Image.new("L", (screen_w, screen_h), 0)
    m_draw = ImageDraw.Draw(mask)
    m_draw.rounded_rectangle([0, 0, screen_w, screen_h], radius=screen_r, fill=255)
    mockup.paste(scaled, (total_margin, total_margin), mask)
    
    return mockup

def render_android_screenshot(preset, device_type="phone"):
    """
    Renders official Google Play Store screenshots:
    - phone: 1080 x 1920 px (aspect ratio 1.77:1 <= 2:1, portrait)
    - tablet_7: 1200 x 1920 px (7-inch tablet, 10:16)
    - tablet_10: 1600 x 2560 px (10-inch tablet, 10:16)
    """
    if device_type == "phone":
        W, H = 1080, 1920
    elif device_type == "tablet_7":
        W, H = 1200, 1920
    else:  # tablet_10
        W, H = 1600, 2560
        
    top_c, mid_c, bot_c, glow_c = preset["theme"]
    canvas = draw_vertical_gradient(W, H, top_c, mid_c, bot_c)
    draw_radial_glow(canvas, W // 2, int(H * 0.60), int(W * 0.70), glow_c, max_alpha=100)
    
    # Typography sizing tailored to Google Play specifications
    if device_type == "phone":
        b_size, t_size, s_size = 22, 60, 28
        pill_y, title_gap, sub_gap, dev_gap = 90, 22, 14, 38
    elif device_type == "tablet_7":
        b_size, t_size, s_size = 24, 68, 32
        pill_y, title_gap, sub_gap, dev_gap = 100, 26, 16, 44
    else:  # tablet_10
        b_size, t_size, s_size = 32, 86, 40
        pill_y, title_gap, sub_gap, dev_gap = 140, 32, 20, 50
        
    badge_font = get_font("Outfit-Bold.ttf", b_size)
    title_font = get_font("Outfit-Bold.ttf", t_size)
    subtitle_font = get_font("Inter-Medium.ttf", s_size)
    
    # 1. Badge Pill
    badge_text = preset["badge"]
    badge_bbox = badge_font.getbbox(badge_text)
    badge_w = badge_bbox[2] - badge_bbox[0]
    badge_h = badge_bbox[3] - badge_bbox[1]
    
    pad_h = int(b_size * 0.55)
    pad_w = int(b_size * 1.1)
    pill_w = badge_w + pad_w * 2
    pill_h = badge_h + pad_h * 2
    pill_x = (W - pill_w) // 2
    
    pill_overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    p_draw = ImageDraw.Draw(pill_overlay)
    p_draw.rounded_rectangle([pill_x, pill_y, pill_x + pill_w, pill_y + pill_h], radius=pill_h // 2, fill=(255, 255, 255, 30), outline=(255, 255, 255, 65), width=2)
    canvas.alpha_composite(pill_overlay)
    
    draw = ImageDraw.Draw(canvas)
    draw.text((pill_x + pad_w, pill_y + pad_h - 2), badge_text, font=badge_font, fill=(255, 255, 255, 255))
    
    # 2. Headline
    title_text = preset["title"]
    title_bbox = title_font.getbbox(title_text)
    title_w = title_bbox[2] - title_bbox[0]
    title_x = (W - title_w) // 2
    title_y = pill_y + pill_h + title_gap
    draw.text((title_x, title_y + 3), title_text, font=title_font, fill=(0, 0, 0, 90))
    draw.text((title_x, title_y), title_text, font=title_font, fill=(255, 255, 255, 255))
    
    # 3. Subtitle
    sub_text = preset["subtitle"]
    sub_bbox = subtitle_font.getbbox(sub_text)
    sub_w = sub_bbox[2] - sub_bbox[0]
    sub_x = (W - sub_w) // 2
    sub_y = title_y + (title_bbox[3] - title_bbox[1]) + sub_gap
    draw.text((sub_x, sub_y), sub_text, font=subtitle_font, fill=(255, 255, 255, 215))
    
    # 4. Device Mockup
    raw_img = load_screen_image(preset, platform="android")
    
    if device_type == "phone":
        target_w = int(W * 0.72)
        mockup, dev_w, dev_h = build_android_phone_frame(raw_img, target_w)
    elif device_type == "tablet_7":
        dev_w = int(W * 0.76)
        dev_h = int(dev_w * 1.55)
        mockup = build_android_tablet_frame(raw_img, dev_w, dev_h)
    else:  # tablet_10
        dev_w = int(W * 0.78)
        dev_h = int(dev_w * 1.55)
        mockup = build_android_tablet_frame(raw_img, dev_w, dev_h)
        
    dev_x = (W - dev_w) // 2
    dev_y = sub_y + (sub_bbox[3] - sub_bbox[1]) + dev_gap
    
    # Drop Shadow
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    s_draw.rounded_rectangle([dev_x + 20, dev_y + 30, dev_x + dev_w - 20, dev_y + dev_h + 25], radius=60, fill=(0, 0, 0, 180))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=36 if device_type == "phone" else 48))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(mockup, (dev_x, dev_y))
    
    return canvas.convert("RGB")

# ==============================================================================
# 🚀 BATCH EXECUTIONS
# ==============================================================================

def generate_ios_assets():
    print("🍎 [APPLE APP STORE] Generating 10 Presets (iPhone 6.5\" & iPad 13\")...")
    for i, preset in enumerate(PRESETS, 1):
        # 1. iPhone 6.5" (1284 x 2778)
        iphone_path = os.path.join(IOS_IPHONE_DIR, f"iphone_6_5_screenshot_{i}.png")
        img_iphone = render_ios_screenshot(preset, is_ipad=False)
        img_iphone.save(iphone_path, "PNG", optimize=True)
        print(f"  ✓ [{i}/10] Saved iPhone 6.5\": iphone_6_5_screenshot_{i}.png (1284x2778 RGB)")
        
        # 2. iPad 13" (2048 x 2732)
        ipad_path = os.path.join(IOS_IPAD_DIR, f"ipad_13_screenshot_{i}.png")
        img_ipad = render_ios_screenshot(preset, is_ipad=True)
        img_ipad.save(ipad_path, "PNG", optimize=True)
        print(f"  ✓ [{i}/10] Saved iPad 13\": ipad_13_screenshot_{i}.png (2048x2732 RGB)")
    print("  🎉 iOS Screenshots complete!")

def generate_android_assets(batch_choice=None):
    print("🤖 [GOOGLE PLAY STORE] Generating Android Presets (Phone, 7\" Tablet, 10\" Tablet)...")
    
    # Google Play allows up to 8 screenshots per device category
    android_presets = ANDROID_PRESETS
    if batch_choice == 1:
        android_presets = [p for p in android_presets if p["batch"] == 1]
        print("  ℹ️ Filtering for Batch 1 (Screens 1 to 4)")
    elif batch_choice == 2:
        android_presets = [p for p in android_presets if p["batch"] == 2]
        print("  ℹ️ Filtering for Batch 2 (Screens 5 to 8)")
        
    for p in android_presets:
        i = p["id"]
        # 1. Phone (1080 x 1920 - portrait 9:16, aspect ratio 1.77:1 <= 2:1)
        phone_path = os.path.join(ANDROID_PHONE_DIR, f"playstore_phone_screenshot_{i}.png")
        img_phone = render_android_screenshot(p, device_type="phone")
        img_phone.save(phone_path, "PNG", optimize=True)
        print(f"  ✓ [{i}/8] Saved Android Phone: playstore_phone_screenshot_{i}.png (1080x1920 RGB)")
        
        # 2. 7-inch Tablet (1200 x 1920)
        tab7_path = os.path.join(ANDROID_TAB7_DIR, f"playstore_tablet7_screenshot_{i}.png")
        img_tab7 = render_android_screenshot(p, device_type="tablet_7")
        img_tab7.save(tab7_path, "PNG", optimize=True)
        print(f"  ✓ [{i}/8] Saved Android 7\" Tablet: playstore_tablet7_screenshot_{i}.png (1200x1920 RGB)")
        
        # 3. 10-inch Tablet (1600 x 2560)
        tab10_path = os.path.join(ANDROID_TAB10_DIR, f"playstore_tablet10_screenshot_{i}.png")
        img_tab10 = render_android_screenshot(p, device_type="tablet_10")
        img_tab10.save(tab10_path, "PNG", optimize=True)
        print(f"  ✓ [{i}/8] Saved Android 10\" Tablet: playstore_tablet10_screenshot_{i}.png (1600x2560 RGB)")
        
    print("  🎉 Android Play Store Screenshots complete!")

def main():
    parser = argparse.ArgumentParser(description="Generate App Store & Google Play screenshots")
    parser.add_argument("--platform", choices=["all", "ios", "android"], default="all", help="Target platform (default: all)")
    parser.add_argument("--batch", choices=["all", "1", "2"], default="all", help="Android batch choice (1 for screens 1-4, 2 for screens 5-8)")
    args = parser.parse_args()
    
    batch_val = None if args.batch == "all" else int(args.batch)
    
    print("🚀 Starting Enything Asset Studio Batch Generator...")
    if args.platform in ["all", "ios"]:
        generate_ios_assets()
    if args.platform in ["all", "android"]:
        generate_android_assets(batch_choice=batch_val)
        
    print("\n✨ All operations completed successfully! Ready for store deployment.")

if __name__ == "__main__":
    main()
