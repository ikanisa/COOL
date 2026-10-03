#!/usr/bin/env python3
"""Real source/lock/metadata guards; no SDK execution or resolution changes."""
import hashlib
import importlib.util
import json
import os
import stat
import unicodedata
import urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
SDK = BASE / 'flutter'
APP = BASE / 'app-source'
PUB = BASE / 'pub-cache'
COMMIT = 'ad70ec4617166f1c38e5d2bfd388af71fda14f06'
ENGINE = 'a10d8ac38de835021c8d2f920dbf50a920ccc030'
SDK_LOCK = '1aa193fc5df798338a2ca97d1737450f9c2cc1984ec0095b2efbaa0f4dcad340'
APP_GENERATED_ROOTS = ('.dart_tool', 'build', 'android/.gradle', 'android/.kotlin',
                       'ios/Flutter/ephemeral')
APP_GENERATED_FILES = {'.flutter-plugins-dependencies', 'android/local.properties',
    'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
    'ios/Flutter/Generated.xcconfig', 'ios/Flutter/flutter_export_environment.sh'}


def load_metadata():
    spec = importlib.util.spec_from_file_location('consumer_exact_metadata', HERE / 'publisher_metadata.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def read_json(path, expected_sha256=None):
    observation, body = load_metadata().stable_read(Path(path), True)
    if expected_sha256 is not None and observation['sha256'] != expected_sha256:
        raise ValueError('independently pinned exact JSON/manifest bytes changed')
    if len(body) > 64 * 1024**2: raise ValueError('metadata size bound')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result: raise ValueError('duplicate JSON key')
            result[key] = value
        return result
    return json.loads(body, object_pairs_hook=unique)


def require_lock(path, expected):
    row, _ = load_metadata().stable_read(path)
    if row['sha256'] != expected: raise ValueError('exact enforced lock bytes changed')
    return row


def safe_directory(path, allowed):
    path = Path(path)
    resolved = path.resolve(strict=True)
    if not any(resolved == root or resolved.is_relative_to(root) for root in allowed):
        raise ValueError('package/generated binding escapes exact owned roots')
    if resolved != path or not path.is_dir(): raise ValueError('directory alias or absent binding')
    for parent in (path, *path.parents):
        if parent.is_symlink(): raise ValueError('directory symbolic ancestor')
    return resolved


def uri_directory(config, raw, allowed):
    if not isinstance(raw, str) or '\\' in raw or '\x00' in raw:
        raise ValueError('unsafe package URI')
    parsed = urllib.parse.urlparse(urllib.parse.urljoin(config.as_uri(), raw))
    if parsed.scheme != 'file' or parsed.netloc not in ('', 'localhost') or parsed.query or parsed.fragment:
        raise ValueError('package URI must be local filesystem')
    path = Path(os.path.normpath(urllib.parse.unquote(parsed.path)))
    return safe_directory(path, allowed)


def package_config(path, roots):
    document = read_json(path)
    if document.get('configVersion') != 2 or not document.get('packages'):
        raise ValueError('actual resolved package configuration absent/unsupported')
    names = set(); rows = []
    for row in document['packages']:
        name = row.get('name')
        if not isinstance(name, str) or not name or name in names:
            raise ValueError('duplicate or missing resolved package')
        names.add(name)
        root = uri_directory(path, row.get('rootUri'), roots)
        load_metadata().stable_read(root / 'pubspec.yaml')
        package = row.get('packageUri', 'lib/')
        if not isinstance(package, str) or urllib.parse.urlparse(package).scheme or package.startswith('/'):
            raise ValueError('packageUri must remain inside package root')
        lib = Path(os.path.normpath(str(root / urllib.parse.unquote(package))))
        if not (lib == root or lib.is_relative_to(root)):
            raise ValueError('packageUri escapes resolved package root')
        # Pub packageUri may name a missing lib directory (non-library tool/package).
        # Every existing path prefix must nevertheless remain physical inside this package.
        physical = lib
        while not physical.exists() and not physical.is_symlink(): physical = physical.parent
        safe_directory(physical, (root,))
        rows.append({'name': name, 'exact_root': str(root), 'package_uri': package,
                     'existing_physical_package_prefix': str(physical)})
    return {'packages': rows, 'file_sha256': load_metadata().stable_read(path)[0]['sha256'],
            'only_exact_owned_bindings': True}


def plugin_metadata(path):
    data = read_json(path); rows = []
    if not isinstance(data.get('plugins'), dict): raise ValueError('plugin metadata missing')
    for platform, values in data['plugins'].items():
        if not isinstance(values, list): raise ValueError('plugin list type differs')
        for row in values:
            if not isinstance(row, dict) or not isinstance(row.get('path'), str):
                raise ValueError('plugin source binding missing')
            root = safe_directory(Path(os.path.normpath(row['path'])), (APP, PUB))
            rows.append({'platform': platform, 'name': row.get('name'), 'exact_path': str(root)})
    return {'rows': rows, 'file_sha256': load_metadata().stable_read(path)[0]['sha256']}


def forbid_upgrade_branch(stdout, stderr):
    body = stdout + '\n' + stderr
    for marker in ('Building flutter tool...', "Command 'pub upgrade'", "Unable to 'pub upgrade'", 'Downloading Dart SDK'):
        if marker in body: raise ValueError('actual unreviewed SDK upgrade/bootstrap branch occurred')


def startup_version(stdout, stderr):
    forbid_upgrade_branch(stdout, stderr)
    data = json.loads(stdout)
    if (data.get('frameworkVersion') != '3.44.4' or data.get('frameworkRevision') != COMMIT
            or data.get('engineRevision') != ENGINE or str(data.get('dartSdkVersion', '')).split(' ', 1)[0] != '3.12.2'):
        raise ValueError('actual startup framework/engine/Dart identity differs')
    return data


def safe_relative(name):
    path = Path(name)
    if (not name or path.is_absolute() or '..' in path.parts or '\\' in name or '\x00' in name
            or path.as_posix() != name or any(ord(char) < 32 for char in name)):
        raise ValueError('unsafe source manifest relative path')
    return path


def generated_allowed(name, phase):
    if phase not in ('app-locked', 'built'): return False
    return (name in APP_GENERATED_FILES
            or any(name == root or name.startswith(root + '/') for root in APP_GENERATED_ROOTS))


def app_readback(phase, expected_manifest_sha256=None):
    if phase not in ('app-export', 'app-locked', 'built'): raise ValueError('unreviewed app source phase')
    if APP.resolve() != APP or not APP.is_dir(): raise ValueError('not exact independent app export')
    if phase != 'app-export' and (not isinstance(expected_manifest_sha256, str) or len(expected_manifest_sha256) != 64):
        raise ValueError('later app stage requires independent original export manifest binding')
    manifest_path = APP / '.collect-release-candidate.json'
    manifest_row, _ = load_metadata().stable_read(manifest_path)
    expected_manifest_sha256 = expected_manifest_sha256 or manifest_row['sha256']
    manifest = read_json(manifest_path, expected_manifest_sha256)
    if (manifest.get('kind') != 'unapproved_collect_source_export' or manifest.get('retain_source_drift') is not False
            or manifest.get('capture_classification') != 'strict_unapproved_source_export'
            or manifest.get('approvals') != {name: False for name in
                ('trusted_source_verified', 'reviewed', 'frozen', 'owner_approved', 'signed', 'production_release_accepted')}):
        raise ValueError('strict unapproved app source export required')
    expected = manifest['source_files']; metadata = load_metadata(); observed = {}; generated = {}
    canonical = (json.dumps(expected, sort_keys=True, separators=(',', ':')) + '\n').encode()
    if hashlib.sha256(canonical).hexdigest() != manifest['source_manifest_sha256']:
        raise ValueError('source manifest canonical hash drift')
    for name, row in expected.items():
        safe_relative(name)
        actual, _ = metadata.stable_read(APP / name)
        if (actual['sha256'], actual['bytes'], actual['mode']) != (row['sha256'], row['bytes'], row['mode']):
            raise ValueError('exported authored source/lock/mode changed: ' + name)
        observed[name] = actual
    aliases = set(); total = 0
    source_directories = {part.as_posix() for name in expected for part in safe_relative(name).parents if part != Path('.')}
    for parent, directories, files in os.walk(APP, followlinks=False):
        for item in directories + files:
            path = Path(parent) / item; name = path.relative_to(APP).as_posix()
            safe_relative(name)
            alias = unicodedata.normalize('NFC', name).casefold()
            if alias in aliases: raise ValueError('app case/Unicode alias')
            aliases.add(alias)
            if len(aliases) > 200000: raise ValueError('app generated entry bound')
            st = path.lstat()
            if stat.S_ISLNK(st.st_mode) or not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)):
                raise ValueError('app generated alias/special file')
            if stat.S_ISDIR(st.st_mode):
                if name not in source_directories and not generated_allowed(name, phase):
                    raise ValueError('app unreviewed directory path: ' + name)
                continue
            if name not in expected and name != '.collect-release-candidate.json':
                if not generated_allowed(name, phase) or path.name.lower() == 'skill.md':
                    raise ValueError('app unreviewed generated source/path: ' + name)
                if path.suffix.lower() in {'.jks', '.keystore', '.p12', '.pem', '.key'} or path.name == 'key.properties':
                    raise ValueError('private signing input materialized')
                actual, _ = metadata.stable_read(path); total += actual['bytes']; generated[name] = actual
                if total > 8 * 1024**3: raise ValueError('app generated byte bound')
    if len(observed) != manifest['file_count']: raise ValueError('app source file count differs')
    if metadata.stable_read(manifest_path)[0]['sha256'] != expected_manifest_sha256:
        raise ValueError('export manifest changed during source readback')
    return {'source_files_exact': observed, 'generated_files_separate': generated,
            'source_manifest_sha256': manifest['source_manifest_sha256'], 'strict_source_unchanged': True,
            'export_manifest_file_sha256': expected_manifest_sha256,
            'no_signing_provider_or_release_acceptance': True}


def process_success(record):
    if (record.get('exit_code') != 0 or record.get('timed_out') or record.get('headroom_failure')
            or record.get('actual_controller_error') or record.get('actual_group_probe_error')
            or record.get('residual_process_group_required_stop')
            or record.get('owned_process_group_absent') is not True):
        raise ValueError('genuine terminal stage failure; no next stage or acceptance')


if __name__ == '__main__':
    raise SystemExit('Guards are readers only; use separately authorized exact controller.')
