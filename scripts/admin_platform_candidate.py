#!/usr/bin/env python3
"""Verify the shipping platform PWA receipt; never deploy or infer hosted acceptance."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct

INPUTS = (
    'scripts/admin_pwa_release_build.sh', 'scripts/supabase/admin_build_config.py', 'scripts/admin_pwa_manifest_gate.sh',
    'scripts/admin_pwa_hosting_gate.sh', 'scripts/admin_cloudflare_assets.py',
    'scripts/templates/admin_pwa_service_worker.js', 'deploy/platform-admin/src/index.js', 'deploy/platform-admin/src/supabase-transport.js',
    'deploy/admin.wrangler.jsonc', 'deploy/platform-admin/wrangler.jsonc',
    '.github/workflows/ci.yml', '.fvmrc', 'pubspec.yaml', 'pubspec.lock',
    'scripts/admin_platform_candidate.py',
)
SUPABASE_BASELINE = 'supabase/migrations/20261020134444_collect_curated_platform_baseline.sql'
SUPABASE_WRANGLER = 'deploy/platform-admin/wrangler.supabase.jsonc'
SUPABASE_INPUTS = ('deploy/platform-admin/src/index.js', SUPABASE_BASELINE,
                   'deploy/platform-admin/src/supabase-transport.js', SUPABASE_WRANGLER)
REQUIRED = {'main.dart.js', 'index.html', 'flutter_bootstrap.js', 'custom-sw.js',
            'manifest.json', '_headers', 'version.json',
            '.well-known/assetlinks.json', '.well-known/apple-app-site-association'}


def fail():
    raise ValueError('Shipping platform candidate identity could not be verified')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def unique(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            fail()
        value[key] = item
    return value


def parse(data):
    return json.loads(data, object_pairs_hook=unique,
                      parse_constant=lambda _: fail())


def physical(path):
    path = Path(os.path.abspath(path))
    if any(part.is_symlink() for part in (path, *path.parents)):
        fail()
    return path


def hosting_profile(backend):
    if backend not in ('cloudflare', 'supabase'):
        fail()
    return {'provider': 'cloudflare_workers',
            'configuration': SUPABASE_WRANGLER if backend == 'supabase'
            else 'deploy/platform-admin/wrangler.jsonc'}


def appledouble_sidecar(path: Path) -> bool:
    """Recognize observed AppleDouble v2 metadata, never a prefix-only exemption.

    Native file inspection identifies the retained metadata as AppleDouble.
    Require its binary magic/version and a complete, bounded entry table in
    addition to the ._ name. Malformed files retain normal reference checks.
    """
    if not path.name.startswith('._') or path.is_symlink():
        return False
    try:
        size = path.stat().st_size
        with path.open('rb') as handle:
            header = handle.read(26)
            if len(header) != 26:
                return False
            magic, version, _, count = struct.unpack('>II16sH', header)
            table_end = 26 + count * 12
            if (magic, version) != (0x00051607, 0x00020000) or not count or table_end > size:
                return False
            table = handle.read(count * 12)
        if len(table) != count * 12:
            return False
        ids = set()
        spans = []
        for index in range(count):
            entry_id, offset, length = struct.unpack_from('>III', table, index * 12)
            if not entry_id or entry_id in ids or offset < table_end or offset + length > size:
                return False
            ids.add(entry_id)
            if length:
                spans.append((offset, offset + length))
        spans.sort()
        return all(left[1] <= right[0] for left, right in zip(spans, spans[1:]))
    except (OSError, struct.error):
        return False


def migration_paths(source_root):
    paths = sorted(path for path in physical(source_root / 'supabase/migrations').glob('*.sql')
                   if not appledouble_sidecar(path))
    if (not paths or paths[0].name != Path(SUPABASE_BASELINE).name or
            any(not re.fullmatch(r'\d{14}_[a-z0-9_]+\.sql', path.name) or
                not physical(path).is_file() or not path.read_bytes().strip() for path in paths)):
        fail()
    return paths


def source_inputs(source_root, backend):
    """One source identity shared by CI receipt production and verification."""
    source_root = physical(source_root)
    if backend == 'cloudflare':
        return INPUTS
    if backend != 'supabase':
        fail()
    profile = parse(physical(source_root / SUPABASE_WRANGLER).read_bytes())
    if (not isinstance(profile, dict) or not isinstance(profile.get('vars'), dict) or
            not isinstance(profile.get('assets'), dict) or profile.get('main') != 'src/index.js' or
            profile.get('vars', {}).get('COLLECT_BACKEND') != 'supabase' or
            profile.get('vars', {}).get('SUPABASE_URL') != 'https://rrlduytparvsjfmegalh.supabase.co' or
            profile.get('vars', {}).get('ADMIN_ORIGIN') != 'https://platform-admin.collect.ikanisa.com' or
            profile.get('assets', {}).get('binding') != 'ASSETS'):
        fail()
    additional = tuple(path.relative_to(source_root).as_posix()
                       for path in migration_paths(source_root)
                       if path.relative_to(source_root).as_posix() not in SUPABASE_INPUTS)
    inputs = tuple(name for name in INPUTS if not name.startswith('deploy/')) + SUPABASE_INPUTS + additional
    if len(inputs) != len(set(inputs)):
        fail()
    return inputs


def verify(root, receipt_path, commit, source_root=Path.cwd(), *, backend='supabase'):
    if not re.fullmatch('[0-9a-f]{40}', commit):
        fail()
    root, receipt_path, source_root = map(physical, (root, receipt_path, source_root))
    if not root.is_dir() or not receipt_path.is_file() or receipt_path.stat().st_size > 4 * 1024 * 1024:
        fail()
    receipt = parse(receipt_path.read_bytes())
    if (receipt.get('source_commit') != commit or receipt.get('source_dirty') is not False or
            receipt.get('hosted_deployment_verified') is not False or receipt.get('build_root') != 'build/web'):
        fail()
    if backend not in ('cloudflare', 'supabase'):
        fail()
    if receipt.get('backend') != backend or receipt.get('hosting') != hosting_profile(backend):
        fail()
    migrations = migration_paths(source_root) if backend == 'supabase' else []
    inputs = source_inputs(source_root, backend)
    expected_inputs = receipt.get('input_sha256')
    if not isinstance(expected_inputs, dict) or set(expected_inputs) != set(inputs):
        fail()
    for name in inputs:
        path = physical(source_root / name)
        if not path.is_file() or digest(path.read_bytes()) != expected_inputs[name]:
            fail()
    files = {}
    for path in sorted(root.rglob('*')):
        if any(part.startswith('._') or part == '.DS_Store' for part in path.relative_to(root).parts):
            continue
        physical(path)
        if path.is_file():
            data = path.read_bytes()
            files[path.relative_to(root).as_posix()] = {'sha256': digest(data), 'bytes': len(data)}
    if (files != receipt.get('files') or digest(canonical(files)) != receipt.get('artifact_manifest_sha256') or
            any(not files.get(name, {}).get('bytes') for name in REQUIRED)):
        fail()
    version = parse((root / 'version.json').read_bytes())
    if ('qualification_complete' in version or
            version.get('purpose') == 'qualification' or
            version.get('environment') == 'qualification' or
            version.get('admin_origin') == 'https://admin-supabase-qa.collect.ikanisa.com' or
            version.get('shipping_candidate') is False):
        fail()
    if backend == 'supabase':
        if not migrations or any(path.is_symlink() or not path.is_file() or not path.read_bytes().strip() for path in migrations):
            fail()
        chain = [{'name': path.name, 'sha256': digest(path.read_bytes())} for path in migrations]
        if version.get('supabase_migrations') != chain or version.get('supabase_migration_chain_sha256') != digest(canonical(chain)):
            fail()
    if (version.get('source_commit') != commit or version.get('source_dirty') is not False or
            version.get('backend') != backend or
            version.get('financial_model') != 'canonical_evidence_ledger' or
            type(version.get('financial_contract_version')) is not int or version['financial_contract_version'] != 2):
        fail()
    if backend == 'cloudflare':
        if (version.get('authentication') != 'email_otp_cookie_with_totp' or
                version.get('minimum_core_schema_migration') != '0017_admin_email_otp.sql'):
            fail()
    elif (version.get('authentication') != 'supabase_auth_cookie_with_email_verification' or
          version.get('minimum_core_schema_migration') != Path(SUPABASE_BASELINE).name or
          version.get('supabase_project_ref') != 'rrlduytparvsjfmegalh' or
          version.get('supabase_schema_sha256') != expected_inputs[SUPABASE_BASELINE] or
          version.get('admin_transport') != 'same_origin_static_proxy' or
          version.get('legacy_data_import_required') is not True or
          version.get('supabase_qualification_complete') is not False):
        fail()
    constants = {}
    worker = (root / 'custom-sw.js').read_text()
    for name in ('CACHE_NAME', 'CACHE_URLS', 'CACHE_HASHES'):
        matches = re.findall(r'^const ' + name + r' = (.*?);$', worker, re.M | re.S)
        if len(matches) != 1:
            fail()
        constants[name] = parse(matches[0])
    if (receipt.get('main_dart_js_sha256') != files['main.dart.js']['sha256'] or
            receipt.get('worker_sha256') != files['custom-sw.js']['sha256'] or
            receipt.get('worker_cache_name') != constants['CACHE_NAME'] or
            receipt.get('cache_urls_sha256') != digest(canonical(constants['CACHE_URLS'])) or
            receipt.get('cache_hashes_sha256') != digest(canonical(constants['CACHE_HASHES']))):
        fail()
    return {'status': 'verified', 'source_commit': commit,
            'artifact_manifest_sha256': receipt['artifact_manifest_sha256'],
            'hosted_deployment_verified': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--backend', choices=('cloudflare', 'supabase'), default='supabase')
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.build_root, args.receipt, args.commit, backend=args.backend)))
    except (ValueError, OSError, TypeError, KeyError):
        parser.exit(1, 'Shipping platform candidate identity could not be verified\n')
