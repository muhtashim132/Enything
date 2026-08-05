from PIL import Image

# 1. Load the original background
bg = Image.open('store_assets/android/feature_graphic/feature_graphic.png').convert("RGBA")
bg_w, bg_h = bg.size

# 2. The Play Store strictly requires 1024x500
target_w, target_h = 1024, 500

# Resize if the width is not 1024, but maintain aspect ratio for the crop
if bg_w != target_w:
    ratio = target_w / bg_w
    new_h = int(bg_h * ratio)
    bg = bg.resize((target_w, new_h), Image.Resampling.LANCZOS)
    bg_w, bg_h = bg.size

# Crop the center 500 pixels vertically if it's too tall (like the 1024x1024 one)
if bg_h > target_h:
    top = (bg_h - target_h) // 2
    bottom = top + target_h
    bg = bg.crop((0, top, target_w, bottom))
elif bg_h < target_h:
    # If it's too short, we create a new 1024x500 canvas and paste it in the center
    new_bg = Image.new("RGBA", (target_w, target_h), (0,0,0,255))
    top = (target_h - bg_h) // 2
    new_bg.paste(bg, (0, top))
    bg = new_bg

# 3. Load and resize the logo
logo = Image.open('logo/Enything_playstore_512.png').convert("RGBA")
logo = logo.resize((280, 280), Image.Resampling.LANCZOS)
logo_w, logo_h = logo.size

# 4. Paste logo perfectly in the center of the 1024x500 image
offset = ((target_w - logo_w) // 2, (target_h - logo_h) // 2)
bg.paste(logo, offset, mask=logo)

# 5. Save the fixed, perfectly dimensioned file
bg.save('store_assets/android/feature_graphic/feature_graphic_fixed.png', format="PNG")
print("Fixed image created at exactly 1024x500.")
