#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
FLUTTER="${FLUTTER:-flutter}"
SOURCE_MANIFEST="$ROOT_DIR/build/admin-cloudflare-source.json"
python3 scripts/admin_cloudflare_source.py record "$SOURCE_MANIFEST"

# Fresh Cloudflare accounts, operating services and email; no Supabase runtime.
"$FLUTTER" build web --release --no-pub --no-wasm-dry-run \
  --no-web-resources-cdn --output build/admin-cloudflare \
  --target lib/main_admin_cloudflare.dart \
  --dart-define=APP_ENVIRONMENT=cloudflare-preview \
  --dart-define=COLLECT_BACKEND_REVISION=cloudflare-admin-20261005 \
  --dart-define=ENABLE_ADMIN_PANEL=true

python3 scripts/admin_cloudflare_assets.py build/admin-cloudflare --local-engine-fallback

python3 - <<'PY'
import json
import hashlib
import re
from pathlib import Path
root = Path('build/admin-cloudflare')
bootstrap = root / 'flutter_bootstrap.js'
bootstrap.write_text(bootstrap.read_text().replace('__COLLECT_ADMIN_ASSET_BASE__', './'))
# Only the sealed public shell may work offline. Account API responses must
# never enter its cache or become available without current online authority.
index = root / 'index.html'
index.write_text(index.read_text().replace('<title>Collect</title>', '<title>Collect Admin</title>'))
(root / 'robots.txt').write_text('User-agent: *\nDisallow: /\n')
# The Admin origin installs as its own operator workspace. Keep Collect's
# existing artwork while allowing desktop/tablet orientation and deep links.
manifest_path = root / 'manifest.json'
manifest = json.loads(manifest_path.read_text())
manifest.update(name='Collect Admin', short_name='Collect Admin',
                description='Collect Rwanda operations: groups, people, payments and reconciliation.',
                id='/collect-admin', scope='/', start_url='/#/admin',
                display='standalone', orientation='any',
                background_color='#000000', theme_color='#000000')
manifest['shortcuts'] = [
    {'name': title, 'url': '/#/admin/' + route}
    for title, route in [('Groups', 'groups'), ('Transactions', 'transactions'),
                         ('Reconciliations', 'reconciliations')]
]
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')

headers = Path('web/_headers').read_text().replace(' https://*.supabase.co wss://*.supabase.co', '')
headers = headers.replace('Referrer-Policy: strict-origin-when-cross-origin', 'Referrer-Policy: no-referrer')
# Retired workers remain mutable update endpoints for old installed tabs.
headers += '\n/flutter_service_worker.js\n  Cache-Control: no-cache\n'
headers += '\n/admin-shell-sw.js\n  Cache-Control: no-cache\n'
for directive, policy in {
    'script-src': "'self' 'wasm-unsafe-eval'",
    'font-src': "'self' data:",
    'connect-src': "'self'",
}.items():
    headers, count = re.subn(rf'(?<![\w-]){directive} [^;]+;', f'{directive} {policy};', headers)
    if count != 1:
        raise SystemExit(f'Expected one Admin {directive} directive')
(root / '_headers').write_text(headers)
# Retire prior Admin/Flutter workers at both historical update URLs. The
# candidate uses a separate public-shell worker, never an account-data cache.
retirement = Path('scripts/templates/admin_cloudflare_retirement_worker.js').read_bytes()
for worker_name in ('custom-sw.js', 'flutter_service_worker.js'):
    (root / worker_name).write_bytes(retirement)
version_path = root / 'version.json'
version = json.loads(version_path.read_text())
version.update(backend='cloudflare', operational_migration_complete=False,
               data_strategy='fresh_cloudflare', legacy_data_import_required=False,
               minimum_core_schema_migration='0012_gateway_receiver_ingress.sql',
               enabled_core_views=['groups', 'users', 'members', 'payees', 'transactions', 'ledgers', 'reconciliations', 'sms_receipts'],
               operating_actions_available=True,
               authentication='email', notifications='email',
               offline_account_data_available=False,
               offline_shell_available=True,
               source_release_status='candidate_requires_hosted_acceptance')
source = json.loads(Path('build/admin-cloudflare-source.json').read_text())
version.update({key: source[key] for key in ('source_commit', 'source_dirty', 'source_manifest_sha256')})
version['main_dart_js_sha256'] = hashlib.sha256((root / 'main.dart.js').read_bytes()).hexdigest()
version_path.write_text(json.dumps(version, indent=2) + '\n')
assert (root / 'main.dart.js').stat().st_size > 0
print('Cloudflare workspace built: build/admin-cloudflare (operating actions and email services).')
PY
python3 scripts/admin_cloudflare_shell.py generate build/admin-cloudflare
python3 scripts/admin_cloudflare_source.py verify "$SOURCE_MANIFEST"
ADMIN_PWA_BUILD_DIR="$ROOT_DIR/build/admin-cloudflare" bash scripts/admin_pwa_hosting_gate.sh
python3 scripts/admin_cloudflare_artifact.py record build/admin-cloudflare \
  "$SOURCE_MANIFEST" "$ROOT_DIR/build/admin-cloudflare-artifact.json"
python3 scripts/admin_cloudflare_artifact.py verify build/admin-cloudflare \
  "$SOURCE_MANIFEST" "$ROOT_DIR/build/admin-cloudflare-artifact.json"
python3 scripts/admin_cloudflare_preflight.py \
  --build-root build/admin-cloudflare \
  --source-manifest "$SOURCE_MANIFEST" \
  --artifact-manifest "$ROOT_DIR/build/admin-cloudflare-artifact.json" \
  --config deploy/admin.cloudflare.wrangler.jsonc \
  --target-origin https://admin-preview.collect.ikanisa.com \
  --output "$ROOT_DIR/build/admin-cloudflare-preflight.json"
