#!/usr/bin/env python3
"""Read-only real observed code/configurations and independently obtained origin."""
import hashlib
import json
import os
import stat
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
OWNED = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/private-gradle/sdk-kotlin-2.4.20-candidate1')
CACHE = OWNED / 'caches/modules-2/files-2.1'
CORE_META = RELEASE / 'kotlin-dependency-batch1/public-origin/kgp-module'
CORE_META_SHA = '8a88cf52de5fb9c829730b0f5aec1fcd35633e697871e256230f09903c74dd43'
NS = {'m': 'http://maven.apache.org/POM/4.0.0'}


def stable_hash(path):
    if path.is_symlink() or path.resolve() != path:
        raise ValueError('artifact/link path unsafe')
    before = path.stat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError('artifact is not exclusive regular file')
    sha256 = hashlib.sha256()
    sha1 = hashlib.sha1()
    with path.open('rb') as inp:
        for chunk in iter(lambda: inp.read(1024 * 1024), b''):
            sha256.update(chunk)
            sha1.update(chunk)
    after = path.stat()
    identity = lambda row: (row.st_dev, row.st_ino, row.st_size, row.st_mtime_ns, row.st_ctime_ns, row.st_mode, row.st_nlink)
    if identity(before) != identity(after):
        raise ValueError('artifact metadata/content changed during readback')
    return {'path': str(path), 'bytes': after.st_size, 'sha256': sha256.hexdigest(), 'sha1': sha1.hexdigest(), 'device': after.st_dev, 'inode': after.st_ino, 'nlink': after.st_nlink}


def one_cache(group, name, filename):
    directory = CACHE / group / name / '2.4.20'
    rows = list(directory.glob('*/' + filename))
    if len(rows) != 1 or not rows[0].is_relative_to(CACHE):
        raise ValueError('critical cache artifact missing/duplicate')
    return rows[0]


def actual_block(body, marker):
    begin = marker + '_BEGIN\n'
    end = '\n' + marker + '_END'
    if body.count(begin) != 1 or body.count(end) != 1:
        raise ValueError('actual observer block absent/duplicate')
    return json.loads(body.split(begin, 1)[1].split(end, 1)[0])


def license_rows(jar):
    rows = []
    with zipfile.ZipFile(jar) as archive:
        members = archive.infolist()
        if len(members) > 200000 or len({i.filename for i in members}) != len(members):
            raise ValueError('JAR member count or duplicate path')
        for entry in members:
            base = Path(entry.filename).name.lower()
            if base not in {'license', 'license.txt', 'notice', 'notice.txt', 'copying', 'copying.txt', 'thirdpartynotices.txt'} and not base.endswith('.license'):
                continue
            if entry.file_size > 1024 * 1024:
                raise ValueError('legal member byte bound')
            data = archive.read(entry)
            rows.append({'member': entry.filename, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    return rows


def save(name, value):
    with (HERE / name).open('x') as out:
        json.dump(value, out, indent=2, sort_keys=True)
        out.write('\n')
        out.flush()
        os.fsync(out.fileno())


def main():
    raw = (HERE / 'sdk-compiler-runtime-attempt2.stdout').read_text()
    applied = actual_block(raw, 'COLLECT_CANDIDATE_APPLIED_KOTLIN')
    graphs = actual_block(raw, 'COLLECT_CANDIDATE_SDK_GRAPHS')
    metadata = CORE_META.read_bytes()
    if hashlib.sha256(metadata).hexdigest() != CORE_META_SHA:
        raise ValueError('independent core metadata drift')
    core = stable_hash(one_cache('org.jetbrains.kotlin', 'kotlin-gradle-plugin', 'kotlin-gradle-plugin-2.4.20-gradle813.jar'))
    published = [f for v in json.loads(metadata)['variants'] for f in v.get('files', []) if f['name'] == 'kotlin-gradle-plugin-2.4.20-gradle813.jar']
    if not published or any(f['size'] != core['bytes'] or f['sha256'] != core['sha256'] for f in published):
        raise ValueError('actual core raw bytes differ from publisher descriptor')
    compiler = stable_hash(one_cache('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', 'kotlin-compiler-embeddable-2.4.20.jar'))
    origin = json.loads((HERE / 'public-origin/compiler-independent-publisher-body.json').read_text())
    location = json.loads((HERE / 'public-origin/compiler-publisher-body-location.json').read_text())
    independent = stable_hash(Path(location['current_outside_repository_path']))
    if compiler['sha256'] != independent['sha256'] or compiler['sha256'] != origin['actual_SHA256'] or compiler['sha1'] != origin['published_SHA1'] or compiler['bytes'] != origin['bytes'] or (compiler['device'], compiler['inode']) == (independent['device'], independent['inode']):
        raise ValueError('actual compiler differs from independently obtained publisher body')
    for entry in applied['actual_class_hierarchy']:
        path = Path(urllib.parse.unquote(urllib.parse.urlparse(entry['loaded_code_source']).path))
        if path != Path(core['path']) or entry['package_implementation_version'] != '2.4.20' or entry.get('actual_sha256') != core['sha256']:
            raise ValueError('actual applied JVM plugin not from exact publisher-matched raw core artifact')
    for config, required, artifact in [('runtimeClasspath', 'kotlin-gradle-plugin', core), ('kotlinCompilerClasspath', 'kotlin-compiler-embeddable', compiler)]:
        graph = graphs['actual_configurations'][config]
        matched = [a for a in graph['artifacts'] if a['group'] == 'org.jetbrains.kotlin' and a['name'] == required]
        if len(matched) != 1 or matched[0]['version'] != '2.4.20' or matched[0]['sha256'] != artifact['sha256'] or matched[0]['bytes'] != artifact['bytes']:
            raise ValueError('actual observed critical graph artifact mismatch')
    poms = {}
    for name, group, filename, primary in [
        ('core', 'org.jetbrains.kotlin', 'kotlin-gradle-plugin-2.4.20.pom', RELEASE / 'kotlin-dependency-batch1/public-origin/kgp-pom'),
        ('compiler', 'org.jetbrains.kotlin', 'kotlin-compiler-embeddable-2.4.20.pom', HERE / 'public-origin/compiler-pom'),
        ('jvm-marker', 'org.jetbrains.kotlin.jvm', 'org.jetbrains.kotlin.jvm.gradle.plugin-2.4.20.pom', HERE / 'public-origin/jvm-marker-pom'),
    ]:
        module = 'org.jetbrains.kotlin.jvm.gradle.plugin' if name == 'jvm-marker' else 'kotlin-gradle-plugin' if name == 'core' else 'kotlin-compiler-embeddable'
        path = one_cache(group, module, filename)
        actual = stable_hash(path)
        if actual['sha256'] != hashlib.sha256(primary.read_bytes()).hexdigest():
            raise ValueError('actual POM differs from independent primary bytes')
        tree = ET.fromstring(path.read_bytes())
        poms[name] = {'actual': actual, 'independent_primary_bytes_match': True, 'declared_licenses': [{child.tag.split('}')[-1]: child.text for child in license} for license in tree.findall('m:licenses/m:license', NS)]}
    save('actual-applied-code-and-configurations.json', {'actual_applied': applied, 'actual_runtime_and_compiler_graphs': graphs, 'producing_stdout_sha256_at_observation': hashlib.sha256(raw.encode()).hexdigest(), 'compiler_process_terminal_or_tests_acceptance_claimed': False})
    save('actual-critical-publisher-license-bindings.json', {
        'status': 'ACTUAL_CRITICAL_ARTIFACT_ORIGIN_AND_LOADED_CODE_BINDINGS_PASS',
        'core_raw_artifact': core, 'core_independent_published_module_sha256': CORE_META_SHA,
        'core_primary_module_url': 'https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/2.4.20/kotlin-gradle-plugin-2.4.20.module',
        'compiler_actual_cache_artifact': compiler, 'compiler_independent_direct_HTTPS_publisher_body': independent,
        'compiler_primary_body_url': origin['primary_url'], 'compiler_published_SHA1_match': True,
        'compiler_independently_published_SHA256_available': False,
        'compiler_direct_publisher_body_and_actual_cache_full_SHA256_match': True,
        'applied_JVM_plugin_loaded_exact_raw_publisher_core': True,
        'POMs': poms, 'core_embedded_legal_members': license_rows(Path(core['path'])),
        'compiler_embedded_legal_members': license_rows(Path(compiler['path'])),
        'scope': 'Exact loaded core JVM and real runtime/compiler configuration artifacts plus their independent origin and retained legal metadata. Full transitive provenance/license/advisory inventory, Kotlin DSL warning support, application consumers and release approval remain separate.',
        'compiler_process_terminal_or_tests_acceptance_claimed': False,
    })
    print(json.dumps({'critical_raw_origin_loaded_code_bindings': 'PASS', 'actual_core_sha256': core['sha256'], 'actual_compiler_sha256': compiler['sha256'], 'compiler_independent_published_SHA256': False}))


if __name__ == '__main__':
    main()
