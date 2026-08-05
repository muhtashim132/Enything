from PIL import Image

# Open the background (feature graphic) and logo
bg = Image.open('store_assets/android/feature_graphic/feature_graphic.png').convert("RGBA")
logo = Image.open('logo/Enything_playstore_512.png').convert("RGBA")

# Resize the logo to fit the safe zone (height 300 max, we use 280 for padding)
# Play store safe zone is 800x300 in the center
logo = logo.resize((280, 280), Image.Resampling.LANCZOS)

# Calculate the position to center the logo perfectly
# background is 1024x500
bg_w, bg_h = bg.size
logo_w, logo_h = logo.size

offset = ((bg_w - logo_w) // 2, (bg_h - logo_h) // 2)

# Paste the logo using its own alpha channel as the mask
bg.paste(logo, offset, mask=logo)

# Save the final image
bg.save('store_assets/android/feature_graphic/feature_graphic_with_logo.png', format="PNG")
print("Successfully generated feature_graphic_with_logo.png")
