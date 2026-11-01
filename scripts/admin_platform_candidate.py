#!/usr/bin/env python3
"""Verify the shipping platform PWA receipt; never deploy or infer hosted acceptance."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import struct

INPUTS = (
    'scripts/admin_pwa_release_build.sh', 'scripts/supabase/admin_build_config.py',
    'scripts/supabase/deployment_profile.py',
    'scripts/qa/client_diagnostic_identity.py', 'scripts/admin_pwa_manifest_gate.sh',
    'scripts/admin_pwa_hosting_gate.sh', 'scripts/admin_cloudflare_assets.py',
    'scripts/templates/admin_pwa_service_worker.js', 'deploy/platform-admin/src/index.js', 'deploy/platform-admin/src/supabase-transport.js',
    'deploy/admin.wrangler.jsonc', 'deploy/platform-admin/wrangler.jsonc',
    '.github/workflows/ci.yml', '.fvmrc', 'pubspec.yaml', 'pubspec.lock',
    'scripts/admin_platform_candidate.py',
)
SUPABASE_BASELINE = 'supabase/migrations/20261020134444_collect_curated_platform_baseline.sql'
SUPABASE_WRANGLER = 'deploy/platform-admin/wrangler.supabase.jsonc'
SUPABASE_QA_WRANGLER = 'deploy/platform-admin/wrangler.supabase-qa.jsonc'
TARGETS = {
    'production': {'configuration': SUPABASE_WRANGLER,
                   'origin': 'https://platform-admin.collect.ikanisa.com',
                   'worker': 'collect-platform-admin', 'host': 'platform-admin.collect.ikanisa.com',
                   'profile_sha256': '84115d0d9388df49b3bf789ebbb5c4ca85b78a4170d0a37952892f85363d64aa'},
    'qa': {'configuration': SUPABASE_QA_WRANGLER,
           'origin': 'https://admin-supabase-qa.collect.ikanisa.com',
           'worker': 'collect-platform-admin-supabase-qa', 'host': 'admin-supabase-qa.collect.ikanisa.com',
           'profile_sha256': 'b7f7d4c990095cf513ba1c5cd1903a8b226eed7a410cafac12ce755f5312f509'},
}
WORKER_FIRST = ['/api', '/api/*', '/v1', '/v1/*', '/functions', '/functions/*',
                '/privacy/account-deletion', '/privacy/account-deletion/*',
                '/admin/auth/local-challenge*', '/_build/*']
PUBLIC_DEFINE_KEYS = {'APP_PUBLIC_URL', 'ADMIN_APP_URL', 'COLLECT_BACKEND', 'APP_ENVIRONMENT',
                      'COLLECT_BACKEND_REVISION', 'ENABLE_ADMIN_PANEL', 'COLLECT_PUBLIC_LANDING_HOME',
                      'AUTH_CAPTCHA_ENABLED', 'AUTH_CAPTCHA_PROVIDER', 'AUTH_CAPTCHA_SITE_KEY',
                      'GOOGLE_AUTH_ENABLED', 'COLLECT_ASSISTED_SMS_ENABLED', 'SUPABASE_URL',
                      'SUPABASE_API_URL', 'SUPABASE_ADMIN_API_URL', 'SUPABASE_PUBLISHABLE_KEY',
                      'COLLECT_BUILD_VERSION', 'COLLECT_BUILD_SOURCE_ID'}
SUPABASE_INPUTS = ('deploy/platform-admin/src/index.js', SUPABASE_BASELINE,
                   'deploy/platform-admin/src/supabase-transport.js', SUPABASE_WRANGLER,
                   'deploy/platform-admin/src/static-recovery.js',
                   'deploy/platform-supabase-free/local-challenge.mjs',
                   'supabase/functions/_shared/deployment-profile.js')
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


def hosting_profile(backend, target='production'):
    if backend not in ('cloudflare', 'supabase') or target not in TARGETS or (backend == 'cloudflare' and target != 'production'):
        fail()
    return {'provider': 'cloudflare_workers',
            'configuration': TARGETS[target]['configuration'] if backend == 'supabase'
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


def source_inputs(source_root, backend, target='production'):
    """One source identity shared by CI receipt production and verification."""
    source_root = physical(source_root)
    if target not in TARGETS:
        fail()
    if backend == 'cloudflare':
        if target != 'production':
            fail()
        return INPUTS
    if backend != 'supabase':
        fail()
    expected = TARGETS[target]
    raw = physical(source_root / expected['configuration']).read_bytes()
    if digest(raw) != expected['profile_sha256']:
        fail()
    profile = parse(raw)
    allowed = {'name', 'main', 'compatibility_date', 'account_id', 'workers_dev',
               'observability', 'vars', 'assets', 'routes', 'compatibility_flags'}
    expected_vars = {'ADMIN_ORIGIN': expected['origin'], 'COLLECT_BACKEND': 'supabase',
                     'SUPABASE_URL': 'https://rrlduytparvsjfmegalh.supabase.co'}
    expected_assets = {'directory': './assets', 'binding': 'ASSETS',
                       'not_found_handling': 'single-page-application', 'run_worker_first': WORKER_FIRST}
    if (not isinstance(profile, dict) or set(profile) != allowed or
            profile.get('name') != expected['worker'] or profile.get('main') != 'src/index.js' or
            profile.get('account_id') != '2209b915a85b1c11cee79b7806c6e73b' or
            profile.get('workers_dev') is not False or profile.get('vars') != expected_vars or
            profile.get('assets') != expected_assets or
            profile.get('routes') != [{'pattern': expected['host'], 'custom_domain': True}]):
        fail()
    selected = tuple(expected['configuration'] if name == SUPABASE_WRANGLER else name
                     for name in SUPABASE_INPUTS)
    additional = tuple(path.relative_to(source_root).as_posix()
                       for path in migration_paths(source_root)
                       if path.relative_to(source_root).as_posix() not in selected)
    inputs = tuple(name for name in INPUTS if not name.startswith('deploy/')) + selected + additional
    if len(inputs) != len(set(inputs)):
        fail()
    return inputs


def read_public_defines(path):
    """Read retained public compiler bytes without following links or replacements."""
    path = physical(path)
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | os.O_NONBLOCK)
    try:
        before = os.fstat(descriptor)
        stamp = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
        if (not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or
                not 0 < before.st_size <= 65536 or stamp(before) != stamp(os.lstat(path))):
            fail()
        data = b''
        while len(data) < before.st_size:
            chunk = os.read(descriptor, before.st_size - len(data))
            if not chunk:
                fail()
            data += chunk
        if stamp(before) != stamp(os.fstat(descriptor)) or stamp(before) != stamp(os.lstat(path)):
            fail()
        return data
    finally:
        os.close(descriptor)


def public_build_identity(data, version):
    defines = parse(data)
    profile = version.get('deployment_profile') if isinstance(version, dict) else None
    expected_keys = PUBLIC_DEFINE_KEYS | ({'COLLECT_DEPLOYMENT_PROFILE', 'COLLECT_DEPLOYMENT_PROFILE_SHA256',
                                          'SUPABASE_AUTH_ISSUER'} if profile is not None else set())
    if (not isinstance(defines, dict) or not isinstance(version, dict) or
            set(defines) != expected_keys or
            any(not isinstance(k, str) or not isinstance(v, str) for k, v in defines.items()) or
            (json.dumps(defines, indent=2) + '\n').encode() != data or
            defines.get('COLLECT_BACKEND') != 'supabase' or
            defines.get('COLLECT_BACKEND_REVISION') != 'supabase-platform-20261020' or
            defines.get('ENABLE_ADMIN_PANEL') != 'true' or defines.get('COLLECT_PUBLIC_LANDING_HOME') != 'false' or
            defines.get('GOOGLE_AUTH_ENABLED') not in ('true', 'false') or
            defines.get('COLLECT_ASSISTED_SMS_ENABLED') not in ('true', 'false') or
            defines.get('COLLECT_BUILD_SOURCE_ID') != version.get('diagnostics_source_revision') or
            defines.get('COLLECT_BUILD_VERSION') != version.get('diagnostics_build_version') or
            defines.get('ADMIN_APP_URL') != defines.get('SUPABASE_ADMIN_API_URL') or
            defines.get('ADMIN_APP_URL') != version.get('admin_origin') or
            defines.get('SUPABASE_API_URL') != version.get('api_origin') or
            defines.get('SUPABASE_ADMIN_API_URL') != version.get('admin_api_origin') or
            not re.fullmatch(r'sb_publishable_[A-Za-z0-9_-]{10,300}', defines.get('SUPABASE_PUBLISHABLE_KEY', '')) or
            version.get('public_build_defines_sha256') != digest(data)):
        fail()
    captcha = defines['AUTH_CAPTCHA_ENABLED']
    if (captcha not in ('true', 'false') or
            (captcha == 'false' and (defines['AUTH_CAPTCHA_PROVIDER'] or defines['AUTH_CAPTCHA_SITE_KEY'])) or
            (captcha == 'true' and (defines['AUTH_CAPTCHA_PROVIDER'] != 'turnstile' or
             not re.fullmatch(r'[A-Za-z0-9_-]{10,200}', defines['AUTH_CAPTCHA_SITE_KEY'])))):
        fail()
    if profile is not None:
        if (not isinstance(profile, dict) or
                defines.get('COLLECT_DEPLOYMENT_PROFILE') != canonical(profile).decode() or
                defines.get('COLLECT_DEPLOYMENT_PROFILE_SHA256') != digest(canonical(profile)) or
                version.get('deployment_profile_sha256') != digest(canonical(profile)) or
                defines.get('APP_PUBLIC_URL') != profile.get('public_origin') or
                defines.get('ADMIN_APP_URL') != profile.get('admin_origin') or
                defines.get('SUPABASE_URL') != profile.get('supabase_origin') or
                defines.get('SUPABASE_API_URL') != profile.get('member_api_origin') or
                defines.get('APP_ENVIRONMENT') != profile.get('environment') or
                version.get('supabase_hosting') != profile.get('mode') or
                defines.get('SUPABASE_AUTH_ISSUER') != profile.get('supabase_origin', '') + '/auth/v1'):
            fail()
    elif (defines['APP_PUBLIC_URL'] != 'https://collect.ikanisa.com' or
          defines['SUPABASE_API_URL'] != defines['ADMIN_APP_URL'] or
          defines['APP_ENVIRONMENT'] not in ('supabase-platform', 'qualification')):
        fail()
    return {'public_build_defines_sha256': digest(data)}


def verify(root, receipt_path, commit, source_root=Path.cwd(), *, backend='supabase', target='production'):
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
    if receipt.get('backend') != backend or receipt.get('hosting') != hosting_profile(backend, target):
        fail()
    migrations = migration_paths(source_root) if backend == 'supabase' else []
    inputs = source_inputs(source_root, backend, target)
    expected_inputs = receipt.get('input_sha256')
    if not isinstance(expected_inputs, dict) or set(expected_inputs) != set(inputs):
        fail()
    for name in inputs:
        path = physical(source_root / name)
        if not path.is_file() or digest(path.read_bytes()) != expected_inputs[name]:
            fail()
    if any(not physical(root / name).is_file() for name in ('version.json', 'main.dart.js')):
        fail()
    version = parse((root / 'version.json').read_bytes())
    if not isinstance(version, dict):
        fail()
    if backend == 'supabase':
        public_bytes = read_public_defines(receipt_path.parent / 'admin-public-defines.json')
        public_identity = public_build_identity(public_bytes, version)
        public_defines = parse(public_bytes)
        worker_vars = parse((source_root / TARGETS[target]['configuration']).read_bytes())['vars']
        if (public_defines.get('SUPABASE_URL') != worker_vars['SUPABASE_URL'] or
                public_defines.get('ADMIN_APP_URL') != worker_vars['ADMIN_ORIGIN']):
            fail()
        if any(receipt.get(k) != v for k, v in public_identity.items()):
            fail()
    # Use the current, explicitly source-bound helper; never execute a helper
    # supplied by the artifact directory or an arbitrary receipt path.
    helper_path = physical(Path(__file__).parent / 'qa/client_diagnostic_identity.py')
    helper_spec = importlib.util.spec_from_file_location('admin_diagnostic_identity', helper_path)
    helper = importlib.util.module_from_spec(helper_spec)
    helper_spec.loader.exec_module(helper)
    diagnostics = helper.javascript_identity(root / 'main.dart.js',
                                            version.get('diagnostics_source_revision'),
                                            version.get('diagnostics_build_version'))
    files = {}
    for path in sorted(root.rglob('*')):
        if any(part.startswith('._') or part == '.DS_Store' for part in path.relative_to(root).parts):
            continue
        physical(path)
        if path.is_file():
            data = path.read_bytes()
            files[path.relative_to(root).as_posix()] = {'sha256': digest(data), 'bytes': len(data)}
    if (files != receipt.get('files') or digest(canonical(files)) != receipt.get('artifact_manifest_sha256') or
            files.get('main.dart.js', {}).get('sha256') != diagnostics['sha256'] or
            any(not files.get(name, {}).get('bytes') for name in REQUIRED)):
        fail()
    if target == 'production' and ('qualification_complete' in version or
            version.get('purpose') == 'qualification' or
            version.get('environment') == 'qualification' or
            version.get('admin_origin') == 'https://admin-supabase-qa.collect.ikanisa.com' or
            version.get('shipping_candidate') is False):
        fail()
    if target == 'qa' and (version.get('purpose') != 'qualification' or
            version.get('environment') != 'qualification' or version.get('shipping_candidate') is not False or
            version.get('qualification_complete') is not False or
            version.get('admin_origin') != TARGETS['qa']['origin'] or
            public_defines.get('APP_ENVIRONMENT') != 'qualification' or
            public_defines.get('AUTH_CAPTCHA_ENABLED') != 'true'):
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
    return {'status': 'verified', 'target': target, 'source_commit': commit,
            'artifact_manifest_sha256': receipt['artifact_manifest_sha256'],
            'shipping_candidate': target == 'production',
            'diagnostics': diagnostics,
            'hosted_deployment_verified': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--backend', choices=('cloudflare', 'supabase'), default='supabase')
    parser.add_argument('--target', choices=('production', 'qa'), default='production')
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.build_root, args.receipt, args.commit, backend=args.backend, target=args.target)))
    except (ValueError, OSError, TypeError, KeyError):
        parser.exit(1, 'Shipping platform candidate identity could not be verified\n')
