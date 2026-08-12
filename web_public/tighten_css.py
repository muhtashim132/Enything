import re

with open('styles.css', 'r') as f:
    content = f.read()

replacements = [
    (r'padding: 4rem 5%;', r'padding: 2rem 5%;'),
    (r'margin-top: 4rem;', r'margin-top: 2rem;'),
    (r'gap: 2rem;', r'gap: 1.2rem;'),
    (r'padding: 2rem 5%;', r'padding: 1rem 5%;'),
    (r'margin-bottom: 5rem;', r'margin-bottom: 3rem;'),
    (r'margin-bottom: 4rem;', r'margin-bottom: 2rem;'),
    (r'margin-bottom: 3rem;', r'margin-bottom: 1.5rem;'),
    (r'gap: 0.8rem !important;', r'gap: 0.5rem !important;'),
    (r'gap: 3rem;', r'gap: 1.5rem;'),
    (r'padding: 1rem 3% !important;', r'padding: 0.5rem 3% !important;'),
    (r'gap: 20px !important;', r'gap: 10px !important;'),
    (r'gap: 15px !important;', r'gap: 10px !important;'),
    (r'margin-bottom: 2rem;', r'margin-bottom: 1rem;'),
    (r'padding: 5rem 0;', r'padding: 3rem 0;')
]

for old, new in replacements:
    content = re.sub(old, new, content)

with open('styles.css', 'w') as f:
    f.write(content)

print("CSS tightened.")
