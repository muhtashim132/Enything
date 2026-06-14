import sys
from PIL import Image

def pad_image(input_path, output_path, padding_factor):
    try:
        img = Image.open(input_path).convert("RGBA")
        width, height = img.size
        # Calculate new size
        new_width = int(width * padding_factor)
        new_height = int(height * padding_factor)
        
        # Create a new image with transparent background
        new_img = Image.new("RGBA", (new_width, new_height), (0, 0, 0, 0))
        
        # Paste the original image in the center
        offset_x = (new_width - width) // 2
        offset_y = (new_height - height) // 2
        new_img.paste(img, (offset_x, offset_y))
        
        new_img.save(output_path)
        print(f"Successfully created padded image: {output_path} (from {width}x{height} to {new_width}x{new_height})")
    except Exception as e:
        print(f"Error padding image: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # Padding factor of 1.35 means the original image will take up ~74% of the width/height
    # This will make it much bigger on the splash screen without getting trimmed
    pad_image("logo/Enything_backup.png", "logo/Enything_backup_splash.png", 1.35)
