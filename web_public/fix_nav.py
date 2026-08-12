import os
import re

dir_path = '.'

for filename in os.listdir(dir_path):
    if filename.endswith('.html'):
        filepath = os.path.join(dir_path, filename)
        with open(filepath, 'r') as f:
            content = f.read()
        
        # Regex to remove Home, Contact, and dropdown. 
        # Since the format might slightly vary, we use re.sub with dotall.
        # We look for the location-container, and remove everything between it and the cart container div.
        
        pattern = r'(<div id="location-container"[^>]*></div>)\s*<a[^>]*>Home</a>\s*<a[^>]*>Contact</a>\s*<div class="dropdown">.*?</div>\s*</div>\s*(<div[^>]*>.*?<a href="checkout\.html")'
        
        new_content = re.sub(pattern, r'\1\n            \2', content, flags=re.DOTALL)
        
        if new_content != content:
            with open(filepath, 'w') as f:
                f.write(new_content)
            print(f"Updated {filename}")
        else:
            # Maybe the nav doesn't have location-container? e.g. privacy.html
            # Let's try a simpler pattern that just targets the 3 items
            pattern2 = r'<a href="index\.html"[^>]*>Home</a>\s*<a href="(#contact|contact\.html)"[^>]*>Contact</a>\s*<div class="dropdown">.*?</div>\s*</div>'
            new_content2 = re.sub(pattern2, r'', content, flags=re.DOTALL)
            if new_content2 != content:
                with open(filepath, 'w') as f:
                    f.write(new_content2)
                print(f"Updated {filename} (pattern2)")

