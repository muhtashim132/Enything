import os
import re

dir_path = '.'

for filename in os.listdir(dir_path):
    if filename.endswith('.html'):
        filepath = os.path.join(dir_path, filename)
        with open(filepath, 'r') as f:
            content = f.read()
        
        # We need to make sure we don't accidentally match if they already have details tag
        if '<details>' in content and 'Contact Support' in content:
            continue
            
        pattern1 = r'<div class="footer-info">\s*<h3>Contact Support</h3>\s*(.*?)\s*</div>'
        replacement1 = r'''<div class="footer-info footer-accordion">
                <details>
                    <summary><h3>Contact Support <i class="fas fa-chevron-down accordion-icon"></i></h3></summary>
                    <div class="accordion-content">
                        \1
                    </div>
                </details>
            </div>'''
            
        pattern2 = r'<div class="footer-legal">\s*<h3>Legal (?:&amp;|&) Policies</h3>\s*(.*?)\s*</div>'
        replacement2 = r'''<div class="footer-legal footer-accordion">
                <details>
                    <summary><h3>Legal &amp; Policies <i class="fas fa-chevron-down accordion-icon"></i></h3></summary>
                    <div class="accordion-content">
                        \1
                    </div>
                </details>
            </div>'''
            
        new_content = re.sub(pattern1, replacement1, content, flags=re.DOTALL)
        new_content = re.sub(pattern2, replacement2, new_content, flags=re.DOTALL)
        
        if new_content != content:
            with open(filepath, 'w') as f:
                f.write(new_content)
            print(f"Updated {filename}")

