import os
import re

dir_path = '.'

for filename in os.listdir(dir_path):
    if filename.endswith('.html'):
        filepath = os.path.join(dir_path, filename)
        with open(filepath, 'r') as f:
            content = f.read()
        
        # Replace <i class="fas fa-shopping-cart"></i> with a link if it's not already wrapped
        new_content = re.sub(
            r'(?<!<a href="cart\.html" style="margin-left:0; color:var\(--text-main\);">)<i class="fas fa-shopping-cart"></i>',
            r'<a href="cart.html" style="margin-left:0; color:var(--text-main);"><i class="fas fa-shopping-cart"></i></a>',
            content
        )
        
        if new_content != content:
            with open(filepath, 'w') as f:
                f.write(new_content)
            print(f"Updated {filename}")
