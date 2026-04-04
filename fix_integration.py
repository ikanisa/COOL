import os
def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    new_content = content.replace('features/partners/rayon/', 'features/rayon/')
    new_content = new_content.replace('package:cool_app/features/partners/rayon/', 'package:cool_app/features/rayon/')
    new_content = new_content.replace('/partners/rayon/', '/rayon/')
    if new_content != content:
        with open(filepath, 'w') as f:
            f.write(new_content)
        print(f"Updated {filepath}")

for root, _, files in os.walk('integration_test'):
    for file in files:
        if file.endswith('.dart'):
            process_file(os.path.join(root, file))
