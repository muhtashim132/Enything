import os, re

tables = set()
for root, _, files in os.walk('d:\\Enything\\lib'):
    for file in files:
        if file.endswith('.dart'):
            with open(os.path.join(root, file), 'r', encoding='utf-8') as f:
                content = f.read()
                tables.update(re.findall(r"\.from\('([^']+)'\)", content))

for t in sorted(list(tables)):
    print(t)
