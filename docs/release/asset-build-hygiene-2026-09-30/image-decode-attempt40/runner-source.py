import hashlib
import json
from pathlib import Path
import PIL
from PIL import Image

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PACKET = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/image-decode-attempt40'
MANIFEST = ROOT / 'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256'
PACKET.mkdir(exist_ok=False)
(PACKET / 'runner-source.py').write_bytes(Path(__file__).read_bytes())

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

manifest_before = sha(MANIFEST)
images = []
for line in MANIFEST.read_text().splitlines():
    if not line.strip() or line.startswith('#'):
        continue
    expected, relative = line.split(maxsplit=1)
    relative = relative.lstrip('*')
    path = ROOT / relative
    if path.suffix.lower() not in {'.png', '.webp', '.jpg', '.jpeg'}:
        continue
    assert path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(ROOT.resolve()), relative
    assert sha(path) == expected, 'Asset hash mismatch: ' + relative
    with Image.open(path) as check:
        check.verify()
    with Image.open(path) as decoded:
        decoded.load()
        pixels = decoded.convert('RGBA')
        pixels.load()
        images.append({'path': relative, 'sha256': expected, 'width': decoded.width,
                       'height': decoded.height, 'format': decoded.format,
                       'decoded_rgba_sha256': hashlib.sha256(pixels.tobytes()).hexdigest()})
    assert sha(path) == expected, 'Asset changed during decode: ' + relative
assert images and sha(MANIFEST) == manifest_before
assert all(sha(ROOT / row['path']) == row['sha256'] for row in images)
(PACKET / 'image-decode.json').write_text(json.dumps({
    'status': 'pass', 'image_count': len(images), 'approved_manifest_sha256': manifest_before,
    'decoder': {'library': 'Pillow', 'version': PIL.__version__},
    'images': images, 'source_images_unchanged': True, 'image_edits': False,
    'scope': 'Actual full local decoding of every approved PNG/WebP/JPEG; does not grant visual fidelity, rights, native-device or release acceptance',
}, indent=2) + '\n')
print('FULL IMAGE DECODE PASS:', len(images), 'approved files')
