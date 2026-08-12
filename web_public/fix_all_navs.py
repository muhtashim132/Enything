import os
import re

dir_path = '.'

for filename in os.listdir(dir_path):
    if filename.endswith('.html'):
        filepath = os.path.join(dir_path, filename)
        with open(filepath, 'r') as f:
            content = f.read()
        
        # We find the <nav> block
        def clean_nav(match):
            nav_block = match.group(0)
            # Remove any <a> with text Home, Contact, About, Restaurants
            nav_block = re.sub(r'<a[^>]*>(Home|Contact|About|Restaurants)</a>\s*', '', nav_block)
            # Remove <div class="dropdown">...</div></div>
            nav_block = re.sub(r'<div class="dropdown">.*?</div>\s*</div>\s*', '', nav_block, flags=re.DOTALL)
            return nav_block

        new_content = re.sub(r'<nav[^>]*>.*?</nav>', clean_nav, content, flags=re.DOTALL)
        
        if new_content != content:
            with open(filepath, 'w') as f:
                f.write(new_content)
            print(f"Updated {filename}")

