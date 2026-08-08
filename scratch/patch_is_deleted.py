import os
import re

lib_dir = '/Users/muhtaashimnazki/Downloads/Enything/lib'
pattern = re.compile(r"(\.from\('products'\)\s*\n\s*\.select\(\))", re.MULTILINE)
check_pattern = re.compile(r"(\.from\('products'\)[\s\S]*?;)", re.MULTILINE)

modified_files = []

for root, dirs, files in os.walk(lib_dir):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                content = f.read()

            new_content = content
            
            # Find all blocks of supabase queries starting with from('products')
            def replacer(match):
                block = match.group(0)
                if 'is_deleted' in block:
                    return block
                # Insert .eq('is_deleted', false) after select()
                # Or after from('products') if there's no select() in that line?
                # Actually, pattern is just finding from('products') and select()
                # But what if there is no select? e.g. insert()
                pass

            
            # Let's just do a simple replacement for now, if the block doesn't have is_deleted
            # But regex substitution with a function is better.
            
            def replace_block(match):
                block = match.group(0)
                if 'is_deleted' in block or 'delete()' in block or 'update(' in block or 'insert(' in block:
                    return block
                # Replace the first select() or from('products') to include the eq clause
                
                if '.select()' in block:
                    return block.replace(".select()", ".select()\n          .eq('is_deleted', false)")
                else:
                    return block.replace(".from('products')", ".from('products')\n          .eq('is_deleted', false)")

            new_content = check_pattern.sub(replace_block, content)
            
            # Fix indentation maybe? The above replace just puts it there. 
            
            if new_content != content:
                with open(filepath, 'w') as f:
                    f.write(new_content)
                modified_files.append(filepath)

print("Modified files:")
for f in modified_files:
    print(f)
