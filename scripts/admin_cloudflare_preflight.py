#!/usr/bin/env python3
"""Local-only Cloudflare Admin candidate preflight; this never authorizes release.

Usage: admin_cloudflare_preflight.py --build-root BUILD --source-manifest SOURCE
  --artifact-manifest ARTIFACT --config CONFIG --target-origin HTTPS_ORIGIN
  --output REPORT [--release]

The source/artifact verifiers bind working bytes (including local forks) to the
emitted candidate. Post-build verification deliberately does not run Flutter's
dependency resolver, any build, subprocess, network request or provider command.
Local configuration proves intended bindings, not provisioned/private resources,
hosted migration state, delivered email, approved identity or operational health.
All six hosted acceptance gates remain unverified. Candidate pass exits 0, local
failure exits 1, and --release exits 99 even when every local check passes. This
script accepts no Boolean attestations or self-authored external acceptance.
"""
import argparse
from datetime import datetime, timezone
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import stat
from urllib.parse import urlsplit


REPORT_SCHEMA = 'collect_admin_cloudflare_local_preflight_v1'
ACCOUNT_ID = '2209b915a85b1c11cee79b7806c6e73b'
DATABASE_ID = '6944372d-16ff-4c08-8a23-54076adf26db'
MINIMUM_MIGRATION = '0012_gateway_receiver_ingress.sql'
PRIVATE_BUCKETS = {
    'MEMBER_MEDIA': 'collect-cloudflare-private-media',
    'RECEIPT_PAYLOADS': 'collect-admin-receipt-payloads',
}
HOSTED_GATES = (
    ('hosted_account_setup', 'Authoritative hosted account setup',
     'Delivered Owner activation and authorized Owner/Admin/Staff journeys with server-enforced denials.'),
    ('provider_security_lifecycle', 'Provider and security lifecycle',
     'Real invite/reset delivery, expiry/single use, password change, cross-tab revocation, uncertainty recovery and durable audit.'),
    ('operating_migration_finance', 'Operating migration and finance',
     'Approved target/data strategy and current hosted migrations; controlled financial review/posting, denial, replay and unknown-result recovery.'),
    ('release_identity_ci', 'Release identity and CI',
     'Exact frontend/Worker/configuration/migrations, current independent successful CI, target-specific live gates and approved post-cutover acceptance.'),
    ('monitoring_recovery', 'Monitoring and recovery',
     'Live redacted logs/alerts and disposable restoration with measured RPO/RTO and reconciled data.'),
    ('performance_devices', 'Performance and devices',
     'Hosted hashing/CPU/error/load budgets, long tables, intended physical browsers/devices and spoken screen-reader journeys.'),
)


def _physical(path):
    """Reject links in any component, including a linked parent directory."""
    path = Path(path).absolute()
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError('Linked input is not accepted.')
    return path.resolve(strict=True)


def _supplied(path):
    if '..' in Path(path).parts:
        raise ValueError('Supplied input paths may not contain parent traversal.')
    return _physical(path)


def _json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON key.')
            result[key] = value
        return result
    return json.loads(text, object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Non-finite JSON.')))


def _jsonc(text):
    # Strip comments and trailing commas only outside JSON strings. URLs and
    # escaped quotes keep their exact bytes; duplicate keys fail closed.
    result = []
    i = 0
    in_string = False
    while i < len(text):
        char = text[i]
        if in_string:
            result.append(char)
            if char == '\\':
                i += 1
                if i < len(text):
                    result.append(text[i])
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
            result.append(char)
        elif text.startswith('//', i):
            end = text.find('\n', i)
            i = len(text) if end < 0 else end
            result.append('\n')
            continue
        elif text.startswith('/*', i):
            end = text.find('*/', i + 2)
            if end < 0:
                raise ValueError('Unclosed JSONC comment.')
            result.append(' ')
            i = end + 2
            continue
        elif char == ',':
            j = i + 1
            while j < len(text) and text[j].isspace():
                j += 1
            if j < len(text) and text[j] in ']}':
                i += 1
                continue
            result.append(char)
        else:
            result.append(char)
        i += 1
    # A comma before a comment may become trailing after comment removal.
    stripped = ''.join(result)
    if stripped == text:
        return _json(stripped)
    return _jsonc(stripped) if re.search(r',\s*[}\]]', stripped) else _json(stripped)


def _object(value):
    if not isinstance(value, dict):
        raise ValueError('A JSON object is required.')
    return value


def _origin(value):
    if not isinstance(value, str) or len(value) > 253 or not value.isascii():
        raise ValueError('Invalid origin.')
    uri = urlsplit(value)
    if (uri.scheme != 'https' or uri.username or uri.password or uri.query or
            uri.fragment or uri.path or uri.port is not None or
            not re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)+', uri.hostname or '') or
            value != 'https://' + uri.hostname):
        raise ValueError('A canonical HTTPS origin is required.')
    return value


class _Markup(HTMLParser):
    def __init__(self):
        super().__init__()
        self.references = []
        self.scripts = []
        self.inline_script = False
        self.base = None

    def handle_starttag(self, tag, attrs):
        fields = dict(attrs)
        if tag == 'base':
            self.base = fields.get('href')
        if tag in {'script', 'link', 'iframe', 'img', 'form'}:
            value = fields.get('src') or fields.get('href') or fields.get('action')
            if value:
                self.references.append(value)
        if tag == 'script':
            if 'src' not in fields:
                self.inline_script = True
            else:
                self.scripts.append(fields['src'])


def _headers(text):
    blocks = {}
    current = None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if not line[0].isspace():
            if line in blocks or not line.startswith('/'):
                raise ValueError('Duplicate or invalid header route.')
            current = line
            blocks[current] = {}
        else:
            key, separator, value = line.strip().partition(':')
            key = key.lower()
            if current is None or not separator or key in blocks[current]:
                raise ValueError('Invalid or duplicate header.')
            blocks[current][key] = value.strip()
    return blocks


def _static_policy(build_root, version, root, frozen_paths):
    headers = _headers((build_root / '_headers').read_text())
    global_headers = headers.get('/*', {})
    required = {'x-frame-options': 'DENY', 'x-content-type-options': 'nosniff',
                'referrer-policy': 'no-referrer', 'x-robots-tag': 'noindex, nofollow'}
    if any(global_headers.get(key) != value for key, value in required.items()):
        raise ValueError('Private Admin security headers missing.')
    for route, block in headers.items():
        if 'access-control-allow-origin' in block:
            raise ValueError('Static Admin cross-origin policy is not accepted.')
        if route.startswith('/api') and block.get('cache-control') != 'no-store':
            raise ValueError('Account API must not be cached.')
    directives = {}
    for item in global_headers.get('content-security-policy', '').split(';'):
        words = item.strip().split()
        if not words:
            continue
        if words[0] in directives:
            raise ValueError('Duplicate CSP directive.')
        directives[words[0]] = words[1:]
    expected = {'default-src': ["'self'"], 'connect-src': ["'self'"],
                'script-src': ["'self'", "'wasm-unsafe-eval'"],
                'font-src': ["'self'", 'data:'], 'manifest-src': ["'self'"],
                'worker-src': ["'self'"], 'object-src': ["'none'"],
                'base-uri': ["'self'"], 'frame-ancestors': ["'none'"],
                'form-action': ["'self'"], 'upgrade-insecure-requests': []}
    if any(directives.get(key) != value for key, value in expected.items()):
        raise ValueError('Admin runtime must use the canonical same-origin CSP.')
    fonts = _json((build_root / 'assets/FontManifest.json').read_text())
    if not isinstance(fonts, list):
        raise ValueError('Local runtime fonts are missing.')
    inter = [family for family in fonts if isinstance(family, dict) and family.get('family') == 'Inter']
    fallback = [family for family in fonts if isinstance(family, dict) and family.get('family') == 'Roboto']
    if (len(inter) != 1 or len(fallback) != 1 or
            not isinstance(inter[0].get('fonts'), list) or not inter[0]['fonts'] or
            fallback[0] != {'family': 'Roboto', 'fonts': inter[0]['fonts']}):
        raise ValueError('CanvasKit fallback must use the exact local Inter fonts.')
    for font in inter[0]['fonts']:
        asset = font.get('asset') if isinstance(font, dict) else None
        if (not isinstance(asset, str) or not re.fullmatch(r'assets/typefaces/Inter-[A-Za-z0-9_-]+\.ttf', asset) or
                not (build_root / 'assets' / asset).is_file()):
            raise ValueError('The bundled Inter fallback asset is missing or unexpected.')
    for route, value in (('/', 'no-store'), ('/index.html', 'no-store'),
                         ('/flutter_bootstrap.js', 'no-cache'), ('/main.dart.js', 'no-cache'),
                         ('/custom-sw.js', 'no-cache'), ('/flutter_service_worker.js', 'no-cache'),
                         ('/admin-shell-sw.js', 'no-cache'),
                         ('/version.json', 'no-cache')):
        if headers.get(route, {}).get('cache-control') != value:
            raise ValueError('Mutable entrypoint cache fence missing.')
    if version.get('offline_account_data_available') is not False:
        raise ValueError('Offline account data is not supported.')
    index = (build_root / 'index.html').read_text()
    markup = _Markup()
    markup.feed(index)
    if markup.base not in {'./', '/'} or markup.inline_script or markup.scripts != ['flutter_bootstrap.js']:
        raise ValueError('Noncanonical Admin bootstrap markup.')
    if any(value.startswith('//') or urlsplit(value).scheme or '\\' in value
           for value in markup.references):
        raise ValueError('External bootstrap markup is not accepted.')
    bootstrap = (build_root / 'flutter_bootstrap.js').read_text()
    offset = bootstrap.find('var adminAssetBase')
    if offset < 0:
        raise ValueError('Canonical Admin bootstrap missing.')
    custom = bootstrap[offset:]
    if ('{{flutter_' in bootstrap or
            not re.search(r'\buseLocalCanvasKit[\"\']?\s*:\s*true', bootstrap) or
            not re.search(r'\bmainJsPath[\"\']?\s*:\s*[\"\']main\.dart\.js[\"\']', bootstrap) or
            not re.search(r"var adminAssetBase\s*=\s*(['\"])\./\1\s*;", custom) or
            not re.search(r"var adminServiceWorkerVersion\s*=\s*(['\"])__COLLECT_ADMIN_SW_VERSION__\1\s*;", custom) or
            "adminServiceWorkerVersion.indexOf('__') !== 0" not in custom or
            len(re.findall(r'\.register\s*\(', custom)) != 2 or
            # The compiler loader declares this optional parameter even when
            # unused. Only the frozen app suffix can enable it at invocation.
            re.search(r'serviceWorkerSettings\s*:', custom) or
            'entrypointBaseUrl: adminAssetBase' not in custom or
            "canvasKitBaseUrl: adminAssetBase + 'canvaskit/'" not in custom):
        raise ValueError('Offline registration or external runtime escape.')
    for name in ('index.html', 'flutter_bootstrap.js', 'main.dart.js', '_headers'):
        text = (build_root / name).read_text()
        if re.search(r'supabase\.(?:co|in)|SUPABASE_(?:URL|ANON_KEY|SERVICE_ROLE_KEY)', text, re.I):
            raise ValueError('Retired Supabase runtime present.')
    main = (build_root / 'main.dart.js').read_text()
    if re.search(r'serviceWorker|caches\s*\.\s*open\s*\(', main):
        raise ValueError('Account runtime may not enable offline caching.')
    retirement = _physical(root / 'scripts/templates/admin_cloudflare_retirement_worker.js')
    if retirement.relative_to(root).as_posix() not in frozen_paths:
        raise ValueError('Retirement worker is not frozen.')
    retirement_bytes = retirement.read_bytes()
    retirement_text = retirement_bytes.decode()
    if (re.search(r"addEventListener\s*\(\s*['\"]fetch['\"]|\bfetch\s*\(|caches\s*\.\s*open\s*\(|\.put\s*\(", retirement_text) or
            'self.registration.unregister()' not in retirement_text or
            'caches.delete(name)' not in retirement_text):
        raise ValueError('Retirement worker must not fetch or store responses.')
    for name in ('custom-sw.js', 'flutter_service_worker.js'):
        if _physical(build_root / name).read_bytes() != retirement_bytes:
            raise ValueError('Old offline workers must emit the exact frozen retirement worker.')
    # A separate credentialless public shell may work offline. Its exact
    # generated allowlist/template must match, and private data stays disabled.
    from admin_cloudflare_shell import verify_shell
    for name in ('scripts/admin_cloudflare_shell.py', 'scripts/templates/admin_cloudflare_shell_worker.js'):
        if name not in frozen_paths:
            raise ValueError('Public shell generation and template must be frozen.')
    verify_shell(build_root, root / 'scripts/templates/admin_cloudflare_shell_worker.js')


def _identity_policy(value):
    if not isinstance(value, str):
        raise ValueError('Gateway policy must be serialized JSON.')
    policy = _json(value)
    if not isinstance(policy, list) or len(policy) > 20:
        raise ValueError('Gateway identity policy is not narrowed.')
    identities = set()
    for item in policy:
        if (not isinstance(item, dict) or set(item) != {'app_id', 'signing_certificate_sha256'} or
                not isinstance(item['app_id'], str) or
                not 3 <= len(item['app_id']) <= 160 or
                not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+', item['app_id']) or
                not isinstance(item['signing_certificate_sha256'], str) or
                not re.fullmatch(r'[0-9a-f]{64}', item['signing_certificate_sha256'])):
            raise ValueError('Gateway policy requires exact app/certificate pairs.')
        identity = (item['app_id'], item['signing_certificate_sha256'].lower())
        if identity in identities:
            raise ValueError('Gateway policy must have unique identities.')
        identities.add(identity)
    return {'status': 'configured_not_hosted_accepted' if policy else 'unaccepted',
            'configured_identity_count': len(policy), 'hosted_acceptance_verified': False,
            'reason': 'Live enrollment and approved signing identity remain unverified.' if policy
            else 'No gateway app/signing identity is approved in local configuration; enrollment remains unavailable.'}


def evaluate_preflight(build_root, source_manifest, artifact_manifest, config, target_origin,
                       *, release=False, source_root=None):
    """Read inputs only; fixed six-gate report never returns release_admissible=True."""
    from admin_cloudflare_source import verify_source_manifest
    from admin_cloudflare_artifact import verify_artifact

    root = Path(source_root) if source_root is not None else Path(__file__).resolve().parents[1]
    checks = []
    report = {'schema': REPORT_SCHEMA, 'generated_at': datetime.now(timezone.utc).isoformat(),
              'mode': 'release' if release else 'candidate', 'local_status': 'fail',
              'release_admissible': False, 'hosted_acceptance_verified': False,
              'compiler_dependency_resolution_verified': False, 'local_checks': checks,
              'hosted_gates': [{'key': key, 'label': label, 'status': 'unverified',
                               'required_evidence': evidence} for key, label, evidence in HOSTED_GATES],
              'limits': ['Local files do not prove deployed bindings, resource privacy or hosted migration application.',
                         'This tool does not ingest external acceptance or authorize cutover.']}

    def check(key, action, failure):
        try:
            result = action()
            checks.append({'key': key, 'status': 'pass'})
            return result
        except (ValueError, OSError, KeyError, TypeError, UnicodeError, RuntimeError, RecursionError):
            checks.append({'key': key, 'status': 'fail', 'reason': failure})
            return None

    paths = check('physical_inputs', lambda: tuple(_supplied(path) for path in
                  (root, build_root, source_manifest, artifact_manifest, config)),
                  'All supplied input paths must exist as physical files/directories without linked ancestors.')
    target = check('target_origin', lambda: _origin(target_origin),
                   'Target must be a canonical HTTPS custom-domain origin without credentials, port, path, query or fragment.')
    if paths is None:
        return report
    root, build, source_path, artifact_path, config_path = paths
    source = check('frozen_source', lambda: verify_source_manifest(root, source_path, check_resolution=False),
                   'Frozen working-source closure, declared fork bytes or source manifest failed verification.')
    artifact = check('exact_artifact', lambda: verify_artifact(build, source_path, artifact_path),
                     'Emitted artifact bytes, candidate version metadata or source identity failed verification.')
    if artifact is not None:
        report['artifact_identity'] = {key: artifact[key] for key in
                                      ('source_commit', 'source_dirty', 'source_manifest_sha256',
                                       'artifact_manifest_sha256', 'main_dart_js_sha256',
                                       'version_json_sha256', 'minimum_core_schema_migration')}
    configuration = check('configuration_jsonc', lambda: _object(_jsonc(config_path.read_text())),
                          'Configuration must be valid JSONC with unique keys; no configuration values are logged.')
    if source is None or configuration is None:
        return report
    variables = check('configuration_shape', lambda: _object(configuration.get('vars')),
                      'Configuration vars must be an object containing canonical runtime values.')
    if variables is None:
        return report
    frozen_paths = {row['path'] for row in source['files']}

    def bound_config():
        relative = config_path.relative_to(root).as_posix()
        if relative not in frozen_paths or configuration.get('main') != 'admin-api/src/worker.mjs':
            raise ValueError('Unbound config/worker.')
        main = _physical(config_path.parent / configuration['main'])
        if main.relative_to(root).as_posix() not in frozen_paths:
            raise ValueError('Worker outside frozen closure.')
        if configuration.get('account_id') != ACCOUNT_ID or configuration.get('name') != 'collect-admin-cloudflare':
            raise ValueError('Wrong Cloudflare project.')
        if configuration.get('workers_dev') is not False or configuration.get('preview_urls') is not False:
            raise ValueError('Alternate origins enabled.')
        if set(configuration.get('vars', {})) != {'ADMIN_ORIGIN', 'ENVIRONMENT', 'GATEWAY_ALLOWED_IDENTITIES'}:
            raise ValueError('Unexpected runtime values or retired configuration.')
    check('configuration_source_binding', bound_config, 'Configuration, Worker entrypoint and exact account/project must belong to the frozen source closure; alternate workers.dev/preview URLs must be disabled.')

    def same_origin():
        admin_origin = _origin(configuration['vars']['ADMIN_ORIGIN'])
        if target is None or admin_origin != target:
            raise ValueError('Wrong origin.')
        if configuration.get('routes') != [{'pattern': urlsplit(target).hostname, 'custom_domain': True}]:
            raise ValueError('Wrong custom-domain route.')
        if configuration['vars'].get('ENVIRONMENT') != 'production':
            raise ValueError('Wrong environment.')
        report['target_origin'] = target
    check('custom_domain_origin', same_origin, 'Exactly one intended custom domain, ADMIN_ORIGIN and target HTTPS origin must agree.')

    def assets():
        value = configuration.get('assets')
        if (not isinstance(value, dict) or value.get('directory') != '../build/admin-cloudflare' or
                value.get('binding') != 'ASSETS' or value.get('not_found_handling') != 'single-page-application' or
                value.get('run_worker_first') != ['/api/admin/*', '/api/gateway', '/api/gateway/*'] or
                _physical(config_path.parent / value['directory']) != build):
            raise ValueError('Wrong ASSETS target/routing.')
    check('assets_binding_path', assets, 'ASSETS must resolve exactly to the supplied canonical build/admin-cloudflare and preserve API-first routes.')

    def database():
        expected = [{'binding': 'ADMIN_DB', 'database_name': 'collect-admin-accounts',
                     'database_id': DATABASE_ID, 'migrations_dir': 'admin-api/migrations'}]
        if configuration.get('d1_databases') != expected:
            raise ValueError('Wrong D1 binding.')
        migrations = _physical(config_path.parent / 'admin-api/migrations')
        migration = _physical(migrations / MINIMUM_MIGRATION)
        if migration.relative_to(root).as_posix() not in frozen_paths:
            raise ValueError('Minimum migration not frozen.')
        if artifact is None or artifact.get('minimum_core_schema_migration') != MINIMUM_MIGRATION:
            raise ValueError('Wrong artifact migration minimum.')
        if migration.stat().st_size == 0:
            raise ValueError('Empty migration.')
    check('database_migration_binding', database, 'Exact ADMIN_DB identity/binding and frozen nonempty minimum migration 0012 are required; this does not verify hosted application.')

    def buckets():
        rows = configuration.get('r2_buckets')
        if (not isinstance(rows, list) or len(rows) != len(PRIVATE_BUCKETS) or
                any(not isinstance(row, dict) or set(row) != {'binding', 'bucket_name'} for row in rows) or
                {row['binding']: row['bucket_name'] for row in rows} != PRIVATE_BUCKETS):
            raise ValueError('Private payload bindings mismatch.')
        report['private_storage'] = {'configured_bindings': sorted(PRIVATE_BUCKETS),
                                     'hosted_privacy_status': 'unverified',
                                     'reason': 'No public URL is configured; actual bucket public-access controls/read authorization remain a hosted gate.'}
    check('private_payload_bindings', buckets, 'Both exact private receiver/member R2 bindings are required; public URL/exposure options and extra bindings are rejected.')
    check('email_sender', lambda: None if configuration.get('send_email') ==
          [{'name': 'EMAIL', 'allowed_sender_addresses': ['info@ikanisa.com']}] else
          (_ for _ in ()).throw(ValueError('Wrong EMAIL sender.')),
          'EMAIL must permit only the intended info@ikanisa.com sender; actual delivery remains unverified.')
    policy = check('gateway_identity_policy', lambda: _identity_policy(configuration['vars'].get('GATEWAY_ALLOWED_IDENTITIES')),
                   'Gateway policy must be an explicit empty unaccepted array or bounded unique exact app/signing-certificate pairs.')
    if policy is not None:
        report['identity_policy'] = policy

    def observability():
        expected = {'enabled': True, 'redact_query_string': True,
                    'logs': {'enabled': True, 'invocation_logs': False}}
        if configuration.get('observability') != expected:
            raise ValueError('Unsafe log configuration.')
        path = _physical(root / 'deploy/admin-api/src/observability.mjs')
        if path.relative_to(root).as_posix() not in frozen_paths:
            raise ValueError('Log module not frozen.')
        text = path.read_text()
        shape = "emit(JSON.stringify({ service: 'collect_admin', schema_version: 1, event, component }))"
        if (shape not in text or 'if (!events.has(event) || !components.has(component)) return;' not in text or
                len(re.findall(r'console\s*\.', text)) != 1 or 'console.warn(value)' not in text or
                len(re.findall(r'emit\s*\(', text)) != 1):
            raise ValueError('Unbounded health log payload.')
        for row in source['files']:
            if row['path'].startswith('deploy/admin-api/src/') and row['path'].endswith('.mjs') and row['path'] != path.relative_to(root).as_posix():
                if re.search(r'console\s*\.', (root / row['path']).read_text()):
                    raise ValueError('Unredacted service logger present.')
    check('redacted_observability', observability, 'Query redaction and disabled invocation logs plus frozen closed-field health logging are required; live alerts remain unverified.')
    version = check('candidate_version_json', lambda: _object(_json((build / 'version.json').read_text())),
                    'Candidate version metadata must be valid JSON with unique keys.')
    if version is not None:
        check('same_origin_no_offline_accounts', lambda: _static_policy(build, version, root, frozen_paths),
              'Emitted CSP/entrypoint cache fences, canonical local bootstrap, retired-runtime exclusion and disabled offline account caching must all pass.')
    report['local_status'] = 'pass' if all(item['status'] == 'pass' for item in checks) else 'fail'
    if release:
        report['release_refusal'] = 'Authoritative external acceptance for all six hosted gates is absent from this local-only workflow. Production release is not authorized.'
    return report


def preflight_exit_code(report):
    if report['mode'] == 'release':
        return 99
    return 0 if report['local_status'] == 'pass' else 1


def _write_report(path, report, protected):
    path = Path(path).absolute()
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError('Output may not traverse a link.')
    destination = path.resolve()
    if any(destination == item or item in destination.parents for item in protected):
        raise ValueError('Output may not overwrite an input or enter the build.')
    if path.exists():
        information = path.stat()
        if not stat.S_ISREG(information.st_mode) or information.st_nlink != 1:
            raise ValueError('Output must be a physical unrelated-free report.')
        previous = _json(path.read_text())
        if not isinstance(previous, dict) or previous.get('schema') != REPORT_SCHEMA:
            raise ValueError('Output would overwrite an unrelated file.')
    from admin_cloudflare_source import write_json
    write_json(path, report)


def main(argv=None, *, source_root=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('build-root', 'source-manifest', 'artifact-manifest', 'config', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--target-origin', required=True)
    parser.add_argument('--release', action='store_true')
    args = parser.parse_args(argv)
    try:
        report = evaluate_preflight(args.build_root, args.source_manifest, args.artifact_manifest,
                                    args.config, args.target_origin, release=args.release,
                                    source_root=source_root)
        protected = [path.absolute().resolve() for path in
                     (args.build_root, args.source_manifest, args.artifact_manifest, args.config)]
        root = Path(source_root) if source_root is not None else Path(__file__).resolve().parents[1]
        from admin_cloudflare_source import SOURCE_DIRS, SOURCE_FILES, read_json, validate_source_manifest
        protected.extend(root.absolute() / name for name in SOURCE_DIRS + SOURCE_FILES)
        # Writing a report cannot add/change an input after a successful freeze,
        # including a declared local fork outside the known source directories.
        if report['local_status'] == 'pass':
            source = validate_source_manifest(read_json(args.source_manifest))
            protected.extend(root.absolute() / Path(row['path']).parts[0]
                             for row in source['files'] if len(Path(row['path']).parts) > 1)
        _write_report(args.output, report, protected)
    except (ValueError, OSError, ImportError, TypeError, KeyError):
        # Never print untrusted file/configuration values or provider credentials.
        print('Cloudflare Admin preflight could not validate inputs or safely write its report.')
        return 99 if args.release else 1
    code = preflight_exit_code(report)
    print(f"Cloudflare Admin local preflight: {report['local_status']}; release_admissible=false; six hosted gates unverified; exit={code}.")
    return code


if __name__ == '__main__':
    raise SystemExit(main())
