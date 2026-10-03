#!/usr/bin/env python3
"""Terminal-only actual JUnit/class/configuration/origin reader, no SDK changes."""
import hashlib
import json
import os
import re
import stat
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
PREP = RELEASE / 'kotlin-sdk-candidate2-preparation-batch1'
CANDIDATE = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-collect-kotlin-2.4.20-candidate2')
GRADLE = CANDIDATE / 'packages/flutter_tools/gradle'
CACHE = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/private-gradle/sdk-kotlin-2.4.20-candidate1')
OLD = RELEASE / 'kotlin-sdk-candidate-execution-batch1'


def save(name, value):
    with (HERE / name).open('x') as f:
        json.dump(value, f, indent=2, sort_keys=True)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())


def identity(row):
    return row.st_dev, row.st_ino, row.st_size, row.st_mtime_ns, row.st_ctime_ns, row.st_mode, row.st_nlink


def actual_file(path, read_body=False):
    if path.is_symlink() or path.resolve() != path:
        raise ValueError('actual report/artifact path is linked')
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError('actual report/artifact not exclusive regular file')
    sha = hashlib.sha256()
    body = bytearray() if read_body else None
    with path.open('rb') as f:
        opened = os.fstat(f.fileno())
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            sha.update(chunk)
            if body is not None:
                if len(body) + len(chunk) > 8 * 1024 ** 2:
                    raise ValueError('actual structured report body bound')
                body.extend(chunk)
        completed = os.fstat(f.fileno())
    if any(identity(row) != identity(before) for row in (opened, completed, path.lstat())):
        raise ValueError('actual report/artifact FD/named path changed')
    return {'path': str(path), 'bytes': before.st_size, 'sha256': sha.hexdigest(), 'device': before.st_dev, 'inode': before.st_ino, 'nlink': before.st_nlink}, bytes(body) if body is not None else None


def block(raw, name):
    begin = name + '_BEGIN\n'
    end = '\n' + name + '_END'
    if raw.count(begin) != 1 or raw.count(end) != 1:
        raise ValueError('actual observer block absent/duplicate')
    return json.loads(raw.split(begin, 1)[1].split(end, 1)[0])


def main():
    command = json.loads((PREP / 'candidate2-next-command.json').read_text())
    compiler = json.loads((HERE / 'sdk-compiler-runtime-attempt1.json').read_text())
    readback = json.loads((HERE / 'built-readback-attempt1.json').read_text())
    terminal = json.loads((HERE / 'workflow-terminal.json').read_text())
    if (compiler['exit_code'] != 0 or readback['exit_code'] != 0
            or compiler['timed_out'] or compiler['headroom_failure']
            or readback['timed_out'] or readback['headroom_failure']
            or terminal['status'] != 'ACTUAL_COMPLETE_SDK_RECIPE_PASS__JUNIT_PUBLISHER_REVIEW_PENDING'
            or compiler['argv'] != command['argv']):
        raise ValueError('true full native compiler/readback terminal success required; no substitute acceptance')
    stdout_row, stdout_body = actual_file(HERE / 'sdk-compiler-runtime-attempt1.stdout', True)
    stderr_row, _ = actual_file(HERE / 'sdk-compiler-runtime-attempt1.stderr', True)
    if stdout_row['sha256'] != compiler['stdout_sha256'] or stderr_row['sha256'] != compiler['stderr_sha256']:
        raise ValueError('actual producing terminal logs drift')
    raw = stdout_body.decode()
    if 'BUILD SUCCESSFUL' not in raw or ' FAILED' in raw:
        raise ValueError('actual terminal Gradle task outcome differs')
    applied = block(raw, 'COLLECT_CANDIDATE_APPLIED_KOTLIN')
    graphs = block(raw, 'COLLECT_CANDIDATE_SDK_GRAPHS')
    if applied['candidate_root'] != str(CANDIDATE) or graphs['candidate_root'] != str(CANDIDATE):
        raise ValueError('actual native observer did not execute this exact independent candidate')
    expected_families = []
    for name in command['all14_sdk_test_classes']:
        body = (CANDIDATE / name).read_text()
        package = re.search(r'^package\s+([\w.]+)', body, re.M)
        if package is None:
            raise ValueError('actual test source family package absent')
        expected_families.append(package.group(1) + '.' + Path(name).stem)
    if len(expected_families) != 14 or len(set(expected_families)) != 14:
        raise ValueError('not exact fourteen reviewed top-level test source families')
    reports = sorted((GRADLE / 'build/test-results/test').glob('TEST-*.xml'))
    if not reports:
        raise ValueError('no actual JUnit XML reports')
    suites = []
    case_rows = []
    totals = {key: 0 for key in ('tests', 'failures', 'errors', 'skipped')}
    families = set()
    for path in reports:
        record, body = actual_file(path, True)
        if b'<!DOCTYPE' in body or b'<!ENTITY' in body:
            raise ValueError('unsafe external XML input')
        suite = ET.fromstring(body)
        if suite.tag != 'testsuite':
            raise ValueError('unexpected genuine Gradle JUnit report shape')
        counts = {key: int(suite.attrib.get(key, '0')) for key in totals}
        for key in totals:
            totals[key] += counts[key]
        cases = suite.findall('testcase')
        if counts['tests'] != len(cases) or counts['tests'] <= 0:
            raise ValueError('actual JUnit suite count/case mismatch or empty suite')
        for case in cases:
            name = case.attrib['name']
            classname = case.attrib['classname']
            family = classname.split('$', 1)[0]
            if family not in expected_families:
                raise ValueError('actual JUnit class outside fourteen reviewed families')
            families.add(family)
            case_rows.append({'name': name, 'classname': classname, 'top_level_source_family': family, 'failure': case.find('failure') is not None, 'error': case.find('error') is not None, 'skipped': case.find('skipped') is not None})
        suites.append({'report': record, 'suite_name': suite.attrib.get('name'), 'counts': counts})
    if families != set(expected_families) or any(totals[key] for key in ('failures', 'errors', 'skipped')) or any(row['failure'] or row['error'] or row['skipped'] for row in case_rows):
        raise ValueError('actual required JUnit family missing/failure/error/skip')
    named_requirements = ['previous SDK and application KGP versions fail the Collect candidate minimum', 'stable fixed KGP passes the Collect candidate minimum without warning', 'equals should throw NullPointerException for null other']
    required_cases = []
    for required in named_requirements:
        rows = [row for row in case_rows if row['name'].removesuffix('()') == required]
        if len(rows) != 1:
            raise ValueError('actual meaningful KGP/NPE assertion case missing/duplicate')
        required_cases.extend(rows)
    core_anchor = json.loads((OLD / 'actual-critical-publisher-license-bindings.json').read_text())
    critical = {'kotlin-gradle-plugin': core_anchor['core_raw_artifact'], 'kotlin-compiler-embeddable': core_anchor['compiler_actual_cache_artifact']}
    for config, component in [('runtimeClasspath', 'kotlin-gradle-plugin'), ('kotlinCompilerClasspath', 'kotlin-compiler-embeddable')]:
        rows = [row for row in graphs['actual_configurations'][config]['artifacts'] if row['group'] == 'org.jetbrains.kotlin' and row['name'] == component]
        anchor = critical[component]
        if len(rows) != 1 or rows[0]['version'] != '2.4.20' or rows[0]['sha256'] != anchor['sha256'] or rows[0]['bytes'] != anchor['bytes']:
            raise ValueError('actual native critical graph artifact differs from independent publisher origin')
        actual, _ = actual_file(Path(anchor['path']))
        if actual['sha256'] != anchor['sha256'] or actual['bytes'] != anchor['bytes']:
            raise ValueError('real owned cache critical bytes differ after native execution')
    for row in applied['actual_class_hierarchy']:
        loaded = Path(urllib.parse.unquote(urllib.parse.urlparse(row['loaded_code_source']).path))
        if loaded != Path(critical['kotlin-gradle-plugin']['path']) or row['package_implementation_version'] != '2.4.20' or row.get('actual_sha256') != critical['kotlin-gradle-plugin']['sha256']:
            raise ValueError('actual loaded JVM code source not publisher-matched raw core2.4.20')
    classes = {}
    for path in sorted((GRADLE / 'build/classes/kotlin/main').rglob('*.class')):
        row, body = actual_file(path, True)
        if body[:4] != b'\xca\xfe\xba\xbe':
            raise ValueError('actual main class magic differs')
        classes[path.relative_to(GRADLE / 'build/classes/kotlin/main').as_posix()] = row['sha256']
    jar = GRADLE / 'build/libs/gradle-1.0.0.jar'
    jar_row, _ = actual_file(jar)
    with zipfile.ZipFile(jar) as archive:
        jar_classes = {name: hashlib.sha256(archive.read(name)).hexdigest() for name in archive.namelist() if name.endswith('.class')}
    if len(classes) != 83 or classes != jar_classes:
        raise ValueError('actual83 main class/JAR correspondence differs')
    built_manifest = json.loads((HERE / 'candidate2-built-readback.json').read_text())
    if len(built_manifest['allowed_source_deltas']) != 8 or built_manifest['retained_publisher_members'] != 22415 or not built_manifest['zero_pristine_installed_failed_candidate_shared_inodes']:
        raise ValueError('complete eight-source physical/source readback differs')
    save('actual-JUnit-reports.json', {'status': 'ACTUAL_ALL14_SOURCE_FAMILIES_JUNIT_PASS', 'totals': totals, 'top_level_source_families': sorted(families), 'actual_XML_suite_count': len(suites), 'suite_report_hashes': suites, 'all_actual_case_names': case_rows, 'meaningful_old_version_and_stable_and_NPE_cases': required_cases, 'old_versions_exercised_in_actual_named_rejection_test': ['2.0.0', '2.2.20', '2.3.20'], 'old_version_claim_source': 'Exact reviewed source plus actual executed test case, not source-string-only acceptance.'})
    save('actual-classloader-runtime-compiler-reports.json', {'status': 'ACTUAL_CRITICAL_CLASSLOADER_CONFIGURATIONS_ORIGIN_PASS', 'actual_applied': applied, 'actual_configurations': graphs, 'core_and_compiler_origin_anchor': 'kotlin-sdk-candidate-execution-batch1/actual-critical-publisher-license-bindings.json', 'critical_publisher_anchor_SHA256': hashlib.sha256((OLD / 'actual-critical-publisher-license-bindings.json').read_bytes()).hexdigest(), 'uniform_Kotlin_runtime_2_4_20': False, 'full_transitive_licenses_advisories_ABI_or_release_cleared': False})
    save('actual-native-results.json', {'status': 'ACTUAL_COMPLETE_SDK_RECIPE_JUNIT_AND_CRITICAL_ORIGIN_PASS__SCOPED_ONLY', 'compiler_exit_code': 0, 'actual_seconds': compiler['actual_seconds'], 'fixed_actual_deadline_seconds': compiler['actual_deadline_seconds'], 'timed_out': False, 'main_classes': 83, 'main_class_SHA256': classes, 'actual_JAR': jar_row, 'JUnit_totals': totals, 'all14_top_level_test_families_executed': True, 'strict_validatePlugins_pass_in_same_actual_command': True, 'complete_candidate2_source_physical_generated_readback_pass': True, 'retained_publisher_members': 22415, 'exact_source_deltas': 8, 'actual_core_JVM_runtime_KGP_and_compiler_2_4_20_origin_bound': True, 'full_runtime_graph_uniform_2_4_20': False, 'Kotlin_DSL_support_warning_retained': 'WARNING: Unsupported Kotlin plugin version.' in raw, 'candidate_promoted': False, 'production_release_approval': False, 'ARC09_closed': False})
    print(json.dumps({'real_compiler_JUnit_and_origin': 'SCOPED_PASS', 'seconds': compiler['actual_seconds'], 'actual_JUnit_totals': totals, 'actual_top_level_test_families': len(families), 'actual_XML_suites': len(suites), 'candidate_promoted': False}))


if __name__ == '__main__':
    main()
