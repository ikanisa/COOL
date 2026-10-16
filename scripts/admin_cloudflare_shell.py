#!/usr/bin/env python3
"""Generate/verify a credential-free, hash-bound public Admin offline shell."""
import argparse
import hashlib
import json
from pathlib import Path
import re

from admin_cloudflare_source import canonical, physical_path, read_json, write_json

WORKER = 'admin-shell-sw.js'
MANIFEST = 'admin-shell-assets.json'
REGISTRATION = """
// BEGIN COLLECT CLOUDFLARE PUBLIC SHELL
window.addEventListener('load', function () {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('admin-shell-sw.js', { updateViaCache: 'none' }).catch(function () {
      console.warn('Collect Admin offline shell could not be prepared.');
    });
  }
});
// END COLLECT CLOUDFLARE PUBLIC SHELL
"""
ROOT_FILES = {'index.html', 'flutter_bootstrap.js', 'main.dart.js', 'flutter.js', 'manifest.json', 'version.json'}
ENGINE_FILES = {'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
                'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm'}
ASSET_FILES = {'assets/AssetManifest.bin', 'assets/AssetManifest.bin.json', 'assets/FontManifest.json',
               'assets/assets/brand/collect_runtime/app_icons/app-icon-rule.png'}


def asset_rows(build):
    # This release compiles Dart2JS/CanvasKit only. Do not install unused mobile
    # artwork, debug symbols or other renderer variants into an operator PWA.
    bootstrap = (build / 'flutter_bootstrap.js').read_text()
    config = re.search(r'_flutter\.buildConfig\s*=\s*(\{[^\n]+\})\s*;', bootstrap)
    if not config or {row.get('renderer') for row in json.loads(config[1]).get('builds', [])} != {'canvaskit'}:
        raise ValueError('Public shell requires the verified CanvasKit release renderer.')
    fonts = read_json(build / 'assets/FontManifest.json')
    if not isinstance(fonts, list):
        raise ValueError('Public shell font declarations are invalid.')
    selected = ROOT_FILES | ENGINE_FILES | ASSET_FILES
    for family in fonts:
        if not isinstance(family, dict) or not isinstance(family.get('fonts'), list):
            raise ValueError('Public shell font declarations are invalid.')
        for font in family['fonts']:
            asset = font.get('asset') if isinstance(font, dict) else None
            if (not isinstance(asset, str) or not re.fullmatch(r'[A-Za-z0-9_.\-/]+\.(?:ttf|otf|woff2?)', asset)
                    or any(part in {'', '.', '..'} for part in asset.split('/'))):
                raise ValueError('Public shell font must be a bounded local asset.')
            selected.add('assets/' + asset)
    rows = []
    for path in sorted(build.rglob('*')):
        if path.is_symlink():
            raise ValueError('Linked shell resources are not allowed.')
        if not path.is_file():
            continue
        relative = path.relative_to(build).as_posix()
        if relative not in selected and not (relative.startswith('icons/') or (
                relative.startswith('assets/shaders/') and relative.endswith('.frag'))):
            continue
        if not re.fullmatch(r'[A-Za-z0-9_.\-/]+', relative):
            raise ValueError('Unexpected public shell resource path.')
        data = path.read_bytes()
        if not data:
            raise ValueError('An empty public shell resource is not allowed.')
        rows.append({'url': './' if relative == 'index.html' else './' + relative,
                     'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
    rows.sort(key=lambda row: row['url'])
    required = selected - {'flutter.js'}
    present = {row['url'] for row in rows}
    if not {('./' if path == 'index.html' else './' + path) for path in required}.issubset(present):
        raise ValueError('Required public shell resources are missing.')
    return rows


def metadata(build, template):
    rows = asset_rows(build)
    body = {'schema_version': 1, 'template_sha256': hashlib.sha256(template).hexdigest(),
            'assets': rows, 'total_bytes': sum(row['bytes'] for row in rows)}
    return {**body, 'cache_name': 'collect-admin-shell-' + hashlib.sha256(canonical(body)).hexdigest()}


def render(template, manifest):
    text = template.decode('utf-8')
    for marker, value in [('__COLLECT_SHELL_CACHE_NAME__', manifest['cache_name']),
                          ('__COLLECT_SHELL_ASSET_HASHES__', {row['url']: row['sha256'] for row in manifest['assets']})]:
        if text.count(marker) != 1:
            raise ValueError('Public shell worker template is invalid.')
        text = text.replace(marker, json.dumps(value, separators=(',', ':'), sort_keys=True))
    return text.encode('utf-8')


def verify_shell(build_root, template_path):
    build = physical_path(build_root, directory=True)
    template = physical_path(template_path).read_bytes()
    version = read_json(build / 'version.json')
    if version.get('offline_shell_available') is not True or version.get('offline_account_data_available') is not False:
        raise ValueError('Public shell and private account availability must remain distinct.')
    bootstrap = (build / 'flutter_bootstrap.js').read_text()
    if bootstrap.count(REGISTRATION) != 1:
        raise ValueError('Public shell registration differs from its fixed contract.')
    expected = metadata(build, template)
    if read_json(build / MANIFEST) != expected or physical_path(build / WORKER).read_bytes() != render(template, expected):
        raise ValueError('Public shell bytes, allowlist or hashes do not match this build.')
    return expected


def generate_shell(build_root, template_path):
    build = physical_path(build_root, directory=True)
    template = physical_path(template_path).read_bytes()
    bootstrap_path = physical_path(build / 'flutter_bootstrap.js')
    bootstrap = bootstrap_path.read_text()
    if 'BEGIN COLLECT CLOUDFLARE PUBLIC SHELL' in bootstrap and bootstrap.count(REGISTRATION) != 1:
        raise ValueError('Unexpected existing public shell registration.')
    if REGISTRATION not in bootstrap:
        bootstrap_path.write_text(bootstrap + REGISTRATION)
    expected = metadata(build, template)
    write_json(build / MANIFEST, expected)
    physical_path(build / WORKER, allow_missing=True).write_bytes(render(template, expected))
    return verify_shell(build, template_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('generate', 'verify'))
    parser.add_argument('build_root')
    args = parser.parse_args()
    template = Path(__file__).resolve().parent / 'templates/admin_cloudflare_shell_worker.js'
    value = (generate_shell if args.command == 'generate' else verify_shell)(args.build_root, template)
    print(json.dumps({'public_shell': args.command, 'asset_count': len(value['assets']),
                      'cache_name': value['cache_name'], 'total_bytes': value['total_bytes'], 'offline_account_data_available': False}))


if __name__ == '__main__':
    main()
