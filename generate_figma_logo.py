import math
from PIL import Image, ImageDraw, ImageFilter

def create_logo(output_path, size=1024, pad_factor=1.0):
    canvas_size = int(size * pad_factor)
    img = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    logo_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Colors
    color_top = (0, 220, 255, 200)    # Cyan translucent
    color_mid = (0, 255, 200, 200)    # Teal/Mint translucent
    color_bot = (100, 50, 255, 200)   # Purple/Indigo translucent
    color_stem = (70, 100, 255, 200)  # Blue translucent
    
    margin = int(size * 0.15)
    w = size - 2 * margin
    h = size - 2 * margin
    ox, oy = margin, margin
    
    radius = int(h * 0.12)
    thickness = radius * 2
    
    # Pill bounding boxes: [x0, y0, x1, y1]
    # Vertical stem (left)
    stem_box = [ox, oy, ox + thickness, oy + h]
    
    # Top bar
    top_box = [ox, oy, ox + w, oy + thickness]
    
    # Mid bar
    mid_box = [ox, oy + h//2 - radius, ox + int(w * 0.8), oy + h//2 + radius]
    
    # Bottom bar
    bot_box = [ox, oy + h - thickness, ox + w, oy + h]
    
    # Draw function for translucent blend
    def draw_pill(box, color):
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        d.rounded_rectangle(box, radius=radius, fill=color)
        return layer

    # 1. Outer Glow
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle(stem_box, radius=radius, fill=(70, 100, 255, 100))
    gd.rounded_rectangle(top_box, radius=radius, fill=(0, 220, 255, 100))
    gd.rounded_rectangle(bot_box, radius=radius, fill=(100, 50, 255, 100))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=40))
    logo_img.alpha_composite(glow)

    # 2. Draw overlapping layers
    l_stem = draw_pill(stem_box, color_stem)
    l_top = draw_pill(top_box, color_top)
    l_mid = draw_pill(mid_box, color_mid)
    l_bot = draw_pill(bot_box, color_bot)
    
    # Composite them
    logo_img.alpha_composite(l_bot)
    logo_img.alpha_composite(l_top)
    logo_img.alpha_composite(l_stem)
    logo_img.alpha_composite(l_mid)
    
    # Center on canvas
    img.paste(logo_img, ((canvas_size - size)//2, (canvas_size - size)//2), mask=logo_img)
    img.save(output_path)
    print(f"Generated figma-style logo: {output_path}")

if __name__ == "__main__":
    create_logo("logo/Enything_modern.png", size=1024, pad_factor=1.0)
    create_logo("logo/Enything_modern_splash.png", size=1024, pad_factor=1.35)
