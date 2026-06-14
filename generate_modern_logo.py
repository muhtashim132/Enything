import math
from PIL import Image, ImageDraw, ImageFilter

def create_logo(output_path, size=1024, pad_factor=1.0):
    # Calculate the actual logo size and the padded canvas size
    canvas_size = int(size * pad_factor)
    img = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    
    # We will draw the logo on a temporary image of exact 'size'
    logo_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(logo_img)
    
    # Colors
    cyan = (0, 255, 255, 255)
    electric_blue = (76, 110, 245, 255) # #4C6EF5
    deep_blue = (91, 139, 255, 255)    # #5B8BFF
    
    # Coordinates for an aggressive, futuristic "E"
    # We'll use a slanted, segmented design.
    margin = int(size * 0.15)
    w = size - 2 * margin
    h = size - 2 * margin
    
    # Origin offset
    ox = margin
    oy = margin
    
    # Let's define the "parts" (polygons)
    # Part 1: Main vertical stem (slanted)
    stem_width = int(w * 0.22)
    slant = int(w * 0.15)
    
    stem_poly = [
        (ox + slant, oy), 
        (ox + slant + stem_width, oy), 
        (ox + stem_width, oy + h), 
        (ox, oy + h)
    ]
    
    # Part 2: Top bar
    top_bar_poly = [
        (ox + slant + stem_width + 20, oy),
        (ox + w, oy),
        (ox + w - slant, oy + stem_width),
        (ox + slant + stem_width - 10, oy + stem_width)
    ]
    
    # Part 3: Middle bar (shorter)
    mid_y = oy + int(h * 0.45)
    mid_bar_poly = [
        (ox + int(slant*0.5) + stem_width + 20, mid_y),
        (ox + int(w * 0.75), mid_y),
        (ox + int(w * 0.75) - slant, mid_y + stem_width),
        (ox + int(slant*0.5) + stem_width - 10, mid_y + stem_width)
    ]
    
    # Part 4: Bottom bar
    bot_bar_poly = [
        (ox + stem_width + 20, oy + h - stem_width),
        (ox + w + slant, oy + h - stem_width),
        (ox + w, oy + h),
        (ox + stem_width - 10, oy + h)
    ]
    
    # Draw glow layers (blurred versions of the polygons)
    glow_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    glow_draw.polygon(stem_poly, fill=(76, 110, 245, 180))
    glow_draw.polygon(top_bar_poly, fill=(76, 110, 245, 180))
    glow_draw.polygon(mid_bar_poly, fill=(76, 110, 245, 180))
    glow_draw.polygon(bot_bar_poly, fill=(76, 110, 245, 180))
    
    glow_img = glow_img.filter(ImageFilter.GaussianBlur(radius=25))
    logo_img.alpha_composite(glow_img)
    
    # Draw solid core layers
    draw.polygon(stem_poly, fill=cyan)
    draw.polygon(top_bar_poly, fill=cyan)
    draw.polygon(mid_bar_poly, fill=cyan)
    draw.polygon(bot_bar_poly, fill=cyan)
    
    # Add some electric blue inner accents (slightly smaller polygons)
    def shrink_poly(poly, amount=0.15):
        cx = sum(p[0] for p in poly) / len(poly)
        cy = sum(p[1] for p in poly) / len(poly)
        return [(int(p[0] + (cx-p[0])*amount), int(p[1] + (cy-p[1])*amount)) for p in poly]
        
    draw.polygon(shrink_poly(stem_poly), fill=electric_blue)
    draw.polygon(shrink_poly(top_bar_poly), fill=electric_blue)
    draw.polygon(shrink_poly(mid_bar_poly), fill=electric_blue)
    draw.polygon(shrink_poly(bot_bar_poly), fill=electric_blue)

    # Paste the centered logo onto the canvas
    offset_x = (canvas_size - size) // 2
    offset_y = (canvas_size - size) // 2
    img.paste(logo_img, (offset_x, offset_y))
    
    img.save(output_path)
    print(f"Generated logo: {output_path} (Canvas: {canvas_size}x{canvas_size})")

if __name__ == "__main__":
    # Create the original logo
    create_logo("logo/Enything_modern.png", size=1024, pad_factor=1.0)
    
    # Create padded versions
    create_logo("logo/Enything_modern_splash.png", size=1024, pad_factor=1.35)
