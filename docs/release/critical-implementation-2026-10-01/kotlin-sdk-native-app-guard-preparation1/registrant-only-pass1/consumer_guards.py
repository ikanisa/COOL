#!/usr/bin/env python3
"""Real source/lock/metadata guards; no SDK execution or resolution changes."""
import hashlib
import importlib.util
import json
import os
import re
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
    'ios/Flutter/Generated.xcconfig', 'ios/Flutter/flutter_export_environment.sh',
    'ios/Runner/GeneratedPluginRegistrant.h', 'ios/Runner/GeneratedPluginRegistrant.m'}
IOS_REGISTRANTS = ('ios/Runner/GeneratedPluginRegistrant.h', 'ios/Runner/GeneratedPluginRegistrant.m')
PLUGIN_BINDINGS_SHA256 = '4882a556c3a7423321ab8676a0992d8b8f6fe3d792109c5f19c8a07d5b6a76e0'
SDK_PLUGIN_SOURCE_HASHES = {
    'packages/flutter_tools/lib/src/flutter_plugins.dart': 'e144c562723c65fbe1de6e62f90cb923d4f0154b41a4afb4b71b882c9db6604b',
    'packages/flutter_tools/lib/src/platform_plugins.dart': '18289943e5a3b113fd70811f944416a181e34da66301f3e22578fc00200a251b',
    'packages/integration_test/pubspec.yaml': '7d967d43522ee820d94aad81adead9dfbf6c7d90387d595265c683b27e92a776',
}


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


def yaml_mapping(body, route=()):
    """Read only explicit indented mapping keys; ambiguous YAML is refused."""
    lines = body.decode('utf-8').splitlines()
    def entries(start, end):
        active = [(i, line) for i, line in enumerate(lines[start:end], start)
                  if line.strip() and not line.lstrip().startswith('#')]
        if not active: return {}
        if any('\t' in line[:len(line)-len(line.lstrip())] for _, line in active):
            raise ValueError('unsupported YAML indentation')
        indent = min(len(line)-len(line.lstrip()) for _, line in active)
        direct = [(i, line[indent:]) for i, line in active
                  if len(line)-len(line.lstrip()) == indent and not line[indent:].startswith('- ')]
        result = {}
        for index, (i, value) in enumerate(direct):
            match = re.fullmatch(r'([A-Za-z_][A-Za-z_0-9]*):(?:[ ]+(.*))?', value.rstrip())
            if not match or match[1] in result: raise ValueError('unsupported or duplicate YAML mapping key')
            stop = direct[index+1][0] if index+1 < len(direct) else end
            result[match[1]] = (match[2] or '', i+1, stop)
        return result
    start, end = 0, len(lines)
    for key in route:
        values = entries(start, end)
        if key not in values: return {}
        raw, start, end = values[key]
        if raw: raise ValueError('YAML mapping alias/flow/scalar unsupported')
    return entries(start, end)


def yaml_scalar(body, route):
    values = yaml_mapping(body, route[:-1])
    if route[-1] not in values: return None
    raw, start, end = values[route[-1]]
    if any(line.strip() and not line.lstrip().startswith('#')
           for line in body.decode('utf-8').splitlines()[start:end]):
        raise ValueError('YAML scalar has nested content')
    raw = raw.strip()
    if raw.startswith('"'):
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*")(?:\s+#.*)?', raw)
        if not match: raise ValueError('unsupported YAML quoted scalar')
        value = json.loads(match[1])
    elif raw.startswith("'"):
        match = re.fullmatch(r"'((?:[^']|'')*)'(?:\s+#.*)?", raw)
        if not match: raise ValueError('unsupported YAML single quoted scalar')
        value = match[1].replace("''", "'")
    else:
        value = raw.split(' #', 1)[0].strip()
        if not re.fullmatch(r'[A-Za-z0-9_./+:%-]+', value):
            raise ValueError('unsupported YAML scalar/alias')
    if not isinstance(value, str): raise ValueError('YAML scalar must be explicit string')
    return value


def sdk_plugin_sources():
    result = {}
    for relative, digest in SDK_PLUGIN_SOURCE_HASHES.items():
        path = SDK / relative
        safe_directory(path.parent, (SDK,))
        row, body = load_metadata().stable_read(path, True)
        if row['sha256'] != digest: raise ValueError('pinned SDK plugin template/source drift')
        result[relative] = (row, body)
    return result


def locked_plugins(path):
    """Bind each listed plugin to exact configuration, lock and reviewed pubspec."""
    metadata = load_metadata(); reads = {}
    def remember(source):
        row, body = metadata.stable_read(source, True); reads[str(source)] = row['sha256']; return row, body
    first, _ = remember(path); data = read_json(path, first['sha256'])
    if not isinstance(data.get('plugins'), dict) or any(not isinstance(v, list) for v in data['plugins'].values()):
        raise ValueError('plugin metadata/list type differs')
    config_path = APP / '.dart_tool/package_config.json'
    first, _ = remember(config_path); config = package_config(config_path, (APP, PUB, SDK))
    if config['file_sha256'] != first['sha256']: raise ValueError('package configuration changed during binding')
    packages = {row['name']: Path(row['exact_root']) for row in config['packages']}
    _, lock = remember(APP / 'pubspec.lock')
    sources = read_json(HERE / 'plugin-source-bindings.json', PLUGIN_BINDINGS_SHA256)
    if sources.get('format') != 'collect-exact-locked-plugin-pubspec-bindings-v1':
        raise ValueError('plugin source review binding format')
    sdk_sources = sdk_plugin_sources()
    for relative, (row, _) in sdk_sources.items(): reads[str(SDK / relative)] = row['sha256']
    resolved = {}
    for name in {row.get('name') for values in data.get('plugins', {}).values() for row in values if isinstance(row, dict)}:
        if not isinstance(name, str) or name not in sources['sources'] or name not in packages:
            raise ValueError('plugin absent from exact reviewed locked package bindings')
        binding = sources['sources'][name]; root = packages[name]
        allowed = (APP, PUB)
        if root.is_relative_to(SDK):
            if name != 'integration_test' or root != SDK / 'packages/integration_test':
                raise ValueError('SDK plugin binding permits only exact integration_test')
            allowed = (SDK / 'packages/integration_test',)
        safe_directory(root, allowed)
        if str(root) != binding['exact_root']: raise ValueError('reviewed plugin package root changed')
        row, pubspec = remember(root / 'pubspec.yaml')
        if (row['sha256'], row['bytes']) != (binding['pubspec_sha256'], binding['pubspec_bytes']):
            raise ValueError('reviewed plugin pubspec bytes changed')
        version = yaml_scalar(lock, ('packages', name, 'version'))
        pubspec_version = yaml_scalar(pubspec, ('version',))
        if name == 'integration_test' and root == SDK / 'packages/integration_test' and pubspec_version is None:
            pubspec_version = '0.0.0'
        if (yaml_scalar(pubspec, ('name',)) != name
                or pubspec_version != version):
            raise ValueError('plugin pubspec name/version differs from locked package')
        source = yaml_scalar(lock, ('packages', name, 'source'))
        if source == 'hosted':
            if (root != PUB / 'hosted/pub.dev' / (name + '-' + version)
                    or yaml_scalar(lock, ('packages', name, 'description', 'name')) != name
                    or yaml_scalar(lock, ('packages', name, 'description', 'url')) != 'https://pub.dev'):
                raise ValueError('hosted plugin is not exact locked private pub.dev package')
        elif source == 'path':
            if yaml_scalar(lock, ('packages', name, 'description', 'relative')) != 'true':
                raise ValueError('only exact app relative path plugin is reviewed')
            relative = yaml_scalar(lock, ('packages', name, 'description', 'path'))
            safe_relative(relative)
            if root != APP / relative: raise ValueError('path plugin differs from exact lock binding')
        elif source == 'sdk':
            if (name != 'integration_test' or root != SDK / 'packages/integration_test'
                    or yaml_scalar(lock, ('packages', name, 'description')) != 'flutter'):
                raise ValueError('unreviewed SDK plugin lock source')
        else: raise ValueError('unreviewed plugin lock source')
        resolved[name] = {'root': root, 'pubspec': pubspec, 'pubspec_sha256': row['sha256'], 'locked_version': version}
    return data, resolved, reads, sdk_sources


def plugin_metadata(path):
    data, resolved, reads, _ = locked_plugins(path); rows = []
    if not isinstance(data.get('plugins'), dict): raise ValueError('plugin metadata missing')
    for platform, values in data['plugins'].items():
        if not isinstance(values, list): raise ValueError('plugin list type differs')
        names = set()
        for row in values:
            if not isinstance(row, dict) or not isinstance(row.get('path'), str):
                raise ValueError('plugin source binding missing')
            name = row.get('name')
            if name in names or name not in resolved: raise ValueError('duplicate/unbound platform plugin')
            names.add(name); bound = resolved[name]
            allowed = (SDK / 'packages/integration_test',) if name == 'integration_test' else (APP, PUB)
            root = safe_directory(Path(os.path.normpath(row['path'])), allowed)
            if root != bound['root']: raise ValueError('plugin metadata/package_config path differs')
            rows.append({'platform': platform, 'name': name, 'exact_path': str(root),
                         'pubspec_sha256': bound['pubspec_sha256'], 'locked_version': bound['locked_version']})
    for name, digest in reads.items():
        if load_metadata().stable_read(Path(name))[0]['sha256'] != digest: raise ValueError('plugin input changed during readback')
    return {'rows': rows, 'file_sha256': reads[str(path)], 'input_sha256': reads,
            'only_exact_locked_plugin_roots': True, 'SDK_plugin_exception': 'integration_test only'}


def ios_registrants():
    """Reconstruct exact Objective-C files from pinned SDK and locked plugin bytes."""
    data, resolved, reads, sdk_sources = locked_plugins(APP / '.flutter-plugins-dependencies')
    plugin_metadata(APP / '.flutter-plugins-dependencies')
    ios = data['plugins'].get('ios')
    if not isinstance(ios, list): raise ValueError('iOS plugin metadata absent')
    if [row.get('name') for row in ios] != sorted({row.get('name') for row in ios}):
        raise ValueError('iOS plugin ordering/duplicates differs from pinned SDK')
    plugins = []
    for row in ios:
        name = row['name']; pubspec = resolved[name]['pubspec']
        plugin_class = yaml_scalar(pubspec, ('flutter', 'plugin', 'platforms', 'ios', 'pluginClass'))
        if plugin_class is None:
            if row.get('native_build') is not False: raise ValueError('unreviewed iOS native/FFI plugin without method channel class')
            continue
        if (row.get('native_build') is not True or not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', name)
                or not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', plugin_class)):
            raise ValueError('unreviewed iOS plugin class/name')
        # Pinned IOSPlugin.fromYaml sets modern platforms-format classPrefix=''.
        plugins.append({'name': name, 'class': plugin_class, 'prefix': '',
                        'pubspec_sha256': resolved[name]['pubspec_sha256']})
    source = sdk_sources['packages/flutter_tools/lib/src/flutter_plugins.dart'][1].decode('utf-8')
    def render(template_name):
        matches = re.findall(r"const " + template_name + r" = '''\n(.*?)''';", source, re.S)
        if len(matches) != 1: raise ValueError('pinned Objective-C template extraction differs')
        template = matches[0]
        def fields(value, context):
            for key, replacement in context.items(): value = value.replace('{{' + key + '}}', replacement)
            if '{{' in value: raise ValueError('unsupported pinned template field')
            return value
        pattern = r'(?m)^\{\{#methodChannelPlugins\}\}\n(.*?)^\{\{/methodChannelPlugins\}\}\n'
        template = re.sub(pattern, lambda match: ''.join(fields(match[1], {k:p[k] for k in ('name', 'class', 'prefix')}) for p in plugins), template, flags=re.S)
        return fields(template, {'framework': 'Flutter'}).encode('utf-8')
    results = {}
    for name, template_name in zip(IOS_REGISTRANTS, ('_objcPluginRegistryHeaderTemplate', '_objcPluginRegistryImplementationTemplate')):
        row, body = load_metadata().stable_read(APP / name, True)
        expected = render(template_name)
        if body != expected: raise ValueError('generated iOS registrant differs from pinned SDK/locked plugin rendering: ' + name)
        results[name] = {'actual': row, 'rendered_sha256': hashlib.sha256(expected).hexdigest(), 'template': template_name}
    for name, digest in reads.items():
        if load_metadata().stable_read(Path(name))[0]['sha256'] != digest: raise ValueError('registrant input drift during render readback')
    for name, proof in results.items():
        if load_metadata().stable_read(APP / name)[0] != proof['actual']:
            raise ValueError('generated registrant identity changed during final readback')
    return {'generated_files': results, 'method_channel_plugins': plugins,
            'input_sha256': reads, 'exact_template_rendering': True, 'output_hash_allowlist_used': False}


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
    ios = ios_registrants() if any(name in generated for name in IOS_REGISTRANTS) else None
    if ios and any(generated[name] != proof['actual'] for name, proof in ios['generated_files'].items()):
        raise ValueError('generated registrant changed between app scan and render proof')
    if metadata.stable_read(manifest_path)[0]['sha256'] != expected_manifest_sha256:
        raise ValueError('export manifest changed during generated registrant proof')
    return {'source_files_exact': observed, 'generated_files_separate': generated,
            'source_manifest_sha256': manifest['source_manifest_sha256'], 'strict_source_unchanged': True,
            'export_manifest_file_sha256': expected_manifest_sha256,
            'no_signing_provider_or_release_acceptance': True,
            'exact_generated_ios_registrants': ios}


def process_success(record):
    if (record.get('exit_code') != 0 or record.get('timed_out') or record.get('headroom_failure')
            or record.get('actual_controller_error') or record.get('actual_group_probe_error')
            or record.get('residual_process_group_required_stop')
            or record.get('owned_process_group_absent') is not True):
        raise ValueError('genuine terminal stage failure; no next stage or acceptance')


if __name__ == '__main__':
    raise SystemExit('Guards are readers only; use separately authorized exact controller.')
