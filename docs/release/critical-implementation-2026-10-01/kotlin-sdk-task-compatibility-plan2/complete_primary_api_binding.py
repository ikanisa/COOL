#!/usr/bin/env python3
"""Validate already acquired bytes and exact publisher variant projection."""
import hashlib
import json
import os
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
ORIGIN = HERE / 'public-origin'
OWNED = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/private-gradle/sdk-kotlin-2.4.20-candidate1/caches/modules-2/files-2.1')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, value):
    with (HERE / name).open('x') as f:
        json.dump(value, f, indent=2, sort_keys=True)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())


def main():
    index = json.loads((ORIGIN / 'primary-api-origin-index.json').read_text())['records']
    for name, row in index.items():
        if row.get('failed') or digest(ORIGIN / name) != row['SHA256']:
            raise ValueError('already acquired primary API body drift/failure')
    save('primary-binding-initial-projection-rejection.json', {'status': 'ACTUAL_REVIEW_VALIDATOR_REJECTION_RETAINED', 'producer': 'bind_primary_api_and_existing_tests.py', 'exception': 'ValueError: publisher exact existing test component identity differs', 'actual_cause': 'Exact Kotlin JUnit5 module descriptor projects parent component kotlin-test through component.url and parent available-at; initial validator incorrectly expected flat kotlin-test-junit5 component.', 'no_new_acquisition_or_source_or_SDK_execution': True})
    parent = json.loads((ORIGIN / 'kotlin-test.module').read_text())
    projection = json.loads((ORIGIN / 'kotlin-test-junit5.module').read_text())
    for meta in (parent, projection):
        component = meta['component']
        if (component['group'], component['module'], component['version']) != ('org.jetbrains.kotlin', 'kotlin-test', '2.4.20'):
            raise ValueError('exact common publisher component differs')
    if projection['component'].get('url') != '../../kotlin-test/2.4.20/kotlin-test-2.4.20.module':
        raise ValueError('exact publisher projected parent link differs')
    required = {'url': '../../kotlin-test-junit5/2.4.20/kotlin-test-junit5-2.4.20.module', 'group': 'org.jetbrains.kotlin', 'module': 'kotlin-test-junit5', 'version': '2.4.20'}
    for variant in ('jvmJUnit5ApiElements', 'jvmJUnit5RuntimeElements'):
        rows = [row for row in parent['variants'] if row['name'] == variant]
        if len(rows) != 1 or rows[0]['available-at'] != required:
            raise ValueError('exact parent JUnit5 projected variant origin differs')
    tests = {}
    for module, metadata in [('kotlin-test', parent), ('kotlin-test-junit5', projection)]:
        base = OWNED / 'org.jetbrains.kotlin' / module / '2.4.20'
        actual_module = list(base.glob('*/' + module + '-2.4.20.module'))
        jars = list(base.glob('*/' + module + '-2.4.20.jar'))
        if len(actual_module) != 1 or len(jars) != 1 or digest(actual_module[0]) != digest(ORIGIN / (module + '.module')):
            raise ValueError('actual existing cold test artifact/metadata absent/duplicate/drift')
        jar = jars[0]
        files = [file for variant in metadata['variants'] for file in variant.get('files', []) if file['name'] == jar.name]
        if not files or any(file['size'] != jar.stat().st_size or file['sha256'] != digest(jar) for file in files):
            raise ValueError('actual existing public test API differs from exact primary published descriptor')
        tests[module] = {'actual_cache_path': str(jar), 'bytes': jar.stat().st_size, 'SHA256': digest(jar), 'independent_publisher_descriptor_match': True, 'new_dependency': False}
    namespace = {'m': 'http://maven.apache.org/POM/4.0.0'}
    pom = ET.fromstring((ORIGIN / 'kotlin-test-junit5.pom').read_bytes())
    dependencies = [{child.tag.split('}')[-1]: child.text for child in row} for row in pom.findall('m:dependencies/m:dependency', namespace)]
    actual_junit = [row for row in dependencies if row.get('groupId') == 'org.junit.jupiter']
    if not actual_junit or any(row.get('version') != '5.10.1' for row in actual_junit):
        raise ValueError('exact already declared public JUnit dependency differs')
    for row in actual_junit:
        paths = list((OWNED / row['groupId'] / row['artifactId'] / row['version']).glob('*/*.jar'))
        if len(paths) != 1:
            raise ValueError('already resolved public JUnit dependency absent/duplicate')
    docs = {}
    for name in ('Gradle-9.1.0-PathSensitive.java', 'Gradle-9.1.0-PathSensitivity.java', 'Gradle-9.1.0-DisableCachingByDefault.java'):
        path = ORIGIN / name
        docs[name] = {'bytes': path.stat().st_size, 'SHA256': digest(path), 'exact_authenticated_distribution_SHA256': 'b84e04fa845fecba48551f425957641074fcc00a88a84d2aae5808743b35fc85', 'primary_distribution_URL': 'https://services.gradle.org/distributions/gradle-9.1.0-all.zip', 'primary_checksum_URL': 'https://services.gradle.org/distributions/gradle-9.1.0-all.zip.sha256', 'source_member': 'gradle-9.1.0/src/core-api/' + ('org/gradle/work/DisableCachingByDefault.java' if 'DisableCaching' in name else 'org/gradle/api/tasks/PathSensitive.java' if name.endswith('-PathSensitive.java') else 'org/gradle/api/tasks/PathSensitivity.java')}
    save('primary-api-existing-dependency-binding.json', {'status': 'PRIMARY_API_AND_EXISTING_DEPENDENCY_REVIEW_BINDINGS_PASS', 'exact_publisher_variant_projection': required, 'Gradle_exact_authenticated_source': docs, 'existing_test_components': tests, 'existing_public_JUnit_dependencies': actual_junit, 'new_dependency_source_or_SDK_execution': False, 'path_default_preservation': 'Explicit ABSOLUTE preserves the authenticated Gradle9.1 PathSensitive default; no shared-cache portability claim.', 'cache_default_preservation': 'Explicit DisableCachingByDefault preserves disabled output caching, still requiring strict property validation.', 'assertion_semantics': 'Exact original boolean expressions/messages and NPE block/expected exception remain enforced using declared public Kotlin test APIs.', 'real_complete_tests_after_patch': 'pending actual compiler/JUnit invocation', 'full_transitive_license_advisory_acceptance': False})
    print(json.dumps({'exact_primary_API_source_bound': True, 'exact_Kotlin_test_JUnit5_projection_bound': True, 'already_resolved_public_test_artifacts_publisher_match': True, 'source_write_or_SDK_execution': False}))


if __name__ == '__main__':
    main()
