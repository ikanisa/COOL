#!/usr/bin/env python3
"""Render the application's referenced font glyphs for a local asset review.

This is an inventory preview, not native-render or source-fidelity acceptance.
"""
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlparse
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / '.cache/revolut-design-20260905'
config = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
packages = {}
for row in config['packages']:
    uri = row['rootUri']
    packages[row['name']] = Path(unquote(urlparse(uri).path)) if uri.startswith('file:') else (ROOT / '.dart_tool' / uri).resolve()
flutter = packages['flutter']
sources = {
    'Icons': flutter / 'lib/src/material/icons.dart',
    'CupertinoIcons': flutter / 'lib/src/cupertino/icons.dart',
    'FontAwesomeIcons': packages['font_awesome_flutter'] / 'lib/font_awesome_flutter.dart',
}
fonts = {
    'MaterialIcons': flutter.parents[1] / 'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    'CupertinoIcons': packages['cupertino_icons'] / 'assets/CupertinoIcons.ttf',
    'FontAwesomeSolid': packages['font_awesome_flutter'] / 'lib/fonts/Font-Awesome-7-Free-Solid-900.otf',
    'FontAwesomeRegular': packages['font_awesome_flutter'] / 'lib/fonts/Font-Awesome-7-Free-Regular-400.otf',
    'FontAwesomeBrands': packages['font_awesome_flutter'] / 'lib/fonts/Font-Awesome-7-Brands-Regular-400.otf',
}
lookup = {}
for namespace, path in sources.items():
    for match in re.finditer(r'static const (?:IconData|FaIconData)\s+(\w+)\s*=\s*([\s\S]*?);', path.read_text()):
        code = re.search(r'IconData\(\s*(0x[0-9a-fA-F]+)', match[2])
        family = re.search(r"fontFamily:\s*'([^']+)'", match[2])
        if code and family:
            lookup[namespace + '.' + match[1]] = (int(code[1], 16), family[1])
for match in re.finditer(r'static const (\w+) = (Icons\.\w+);', (ROOT / 'lib/app/theme/collect_icons.dart').read_text()):
    lookup['CollectIcons.' + match[1]] = lookup[match[2]]
inventory = json.loads((BASE / 'exhaustive-inventory.json').read_text())
out = BASE / 'icon-atlas'
out.mkdir(exist_ok=True)
rows = []
for symbol in inventory['icon_symbols']:
    row = {'symbol': symbol, 'kind': 'glyph', 'status': 'unresolved'}
    if symbol in lookup:
        code, family = lookup[symbol]
        font_path = fonts[family]
        font = ImageFont.truetype(str(font_path), 48)
        image = Image.new('RGBA', (112, 96), (22, 22, 24, 255))
        draw = ImageDraw.Draw(image)
        draw.text((56, 48), chr(code), font=font, fill='#f4f4f4', anchor='mm')
        path = out / (symbol + '.png')
        image.save(path)
        row.update(status='rendered', image=str(path.relative_to(ROOT)), codepoint=hex(code), family=family,
                   font_sha256=hashlib.sha256(font_path.read_bytes()).hexdigest())
    else:
        row.update(kind='dynamic icon resolver', note='Rendered outcome is selected by the data/state; see its call sites and screen captures.')
    rows.append(row)
(out / 'manifest.json').write_text(json.dumps({'scope': 'Referenced glyphs only; original font assets. No invented icons or visual approval.', 'results': rows}, indent=2) + '\n')
print(json.dumps({'symbols': len(rows), 'rendered': sum(r['status']=='rendered' for r in rows), 'dynamic': [r['symbol'] for r in rows if r['status']!='rendered']}))
