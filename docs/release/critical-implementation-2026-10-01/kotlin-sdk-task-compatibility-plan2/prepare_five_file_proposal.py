#!/usr/bin/env python3
"""Exact RAM proposal only; no candidate/shared/pristine SDK source writes."""
import difflib
import hashlib
import json
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
CANDIDATE = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-collect-kotlin-2.4.20-candidate1')
PRISTINE = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-authenticated-foundation-batch1')
TREE = RELEASE / 'kotlin-sdk-foundation-batch1/public-origin/official-recursive-tree-attempt3.body'
PREFIX = 'packages/flutter_tools/gradle/'


def once(body, before, after):
    old, new = before.encode(), after.encode()
    if body.count(old) != 1:
        raise ValueError('exact reviewed context must occur once')
    return body.replace(old, new)


def proposed(path, body):
    if path.endswith('/BaseFlutterTask.kt'):
        body = once(body, 'import org.gradle.api.tasks.OutputFiles\n', 'import org.gradle.api.tasks.OutputFiles\nimport org.gradle.work.DisableCachingByDefault\n')
        return once(body, 'open class BaseFlutterTask : DefaultTask() {', '@DisableCachingByDefault(because = "Task invokes Flutter tooling with local SDK and engine state that is not fully represented as cacheable inputs.")\nopen class BaseFlutterTask : DefaultTask() {')
    if path.endswith('/DeepLinkJsonFromManifestTask.kt'):
        body = once(body, 'import org.gradle.api.tasks.OutputFile\n', 'import org.gradle.api.tasks.OutputFile\nimport org.gradle.api.tasks.PathSensitive\nimport org.gradle.api.tasks.PathSensitivity\n')
        body = once(body, 'import org.gradle.api.tasks.TaskAction\n', 'import org.gradle.api.tasks.TaskAction\nimport org.gradle.work.DisableCachingByDefault\n')
        body = once(body, 'abstract class DeepLinkJsonFromManifestTask : DefaultTask() {', '@DisableCachingByDefault(because = "Task copies merged manifest and generates deep-link metadata; shared-cache behavior is not established.")\nabstract class DeepLinkJsonFromManifestTask : DefaultTask() {')
        return once(body, '    @get:InputFile\n    abstract val manifestFile:', '    @get:InputFile\n    @get:PathSensitive(PathSensitivity.ABSOLUTE)\n    abstract val manifestFile:')
    if path.endswith('/FlutterTask.kt'):
        body = once(body, 'import org.gradle.api.tasks.OutputFiles\n', 'import org.gradle.api.tasks.OutputFiles\nimport org.gradle.api.tasks.PathSensitive\nimport org.gradle.api.tasks.PathSensitivity\n')
        body = once(body, 'import org.gradle.api.tasks.TaskAction\n', 'import org.gradle.api.tasks.TaskAction\nimport org.gradle.work.DisableCachingByDefault\n')
        body = once(body, 'abstract class FlutterTask : BaseFlutterTask() {', '@DisableCachingByDefault(because = "Flutter compilation delegates to external tooling with local SDK and engine state.")\nabstract class FlutterTask : BaseFlutterTask() {')
        return once(body, '    @get:InputFiles\n    val sourceFiles:', '    @get:InputFiles\n    @get:PathSensitive(PathSensitivity.ABSOLUTE)\n    val sourceFiles:')
    if path.endswith('/DeeplinkTest.kt'):
        body = once(body, 'import org.gradle.internal.impldep.org.junit.Assert.assertThrows\n', '')
        body = once(body, 'import kotlin.test.assertContains\n', 'import kotlin.test.assertContains\nimport kotlin.test.assertFailsWith\n')
        return once(body, 'assertThrows(NullPointerException::class.java) { deeplink1.equals(deeplink2) }', 'assertFailsWith<NullPointerException> { deeplink1.equals(deeplink2) }')
    if path.endswith('/FlutterPluginUtilsTest.kt'):
        body = once(body, 'import org.gradle.internal.impldep.junit.framework.TestCase.assertFalse\n', '')
        body = once(body, 'import org.gradle.internal.impldep.junit.framework.TestCase.assertTrue\n', '')
        return once(body, 'import kotlin.test.assertFalse\n', 'import kotlin.test.assertFalse\nimport kotlin.test.assertTrue\n')
    raise ValueError('not one of exact five proposed paths')


def main():
    foundation = json.loads((RELEASE / 'kotlin-sdk-foundation-batch1/packet-files.json').read_text())['files']
    if hashlib.sha256(TREE.read_bytes()).hexdigest() != foundation[TREE.relative_to(RELEASE / 'kotlin-sdk-foundation-batch1').as_posix()]:
        raise ValueError('pinned authenticated official tree bytes drift')
    tree = {row['path']: row for row in json.loads(TREE.read_text())['tree']}
    paths = [PREFIX + name for name in ['src/main/kotlin/tasks/BaseFlutterTask.kt', 'src/main/kotlin/tasks/DeepLinkJsonFromManifestTask.kt', 'src/main/kotlin/tasks/FlutterTask.kt', 'src/test/kotlin/DeeplinkTest.kt', 'src/test/kotlin/FlutterPluginUtilsTest.kt']]
    records = {}
    patches = []
    for path in paths:
        original = (CANDIDATE / path).read_bytes()
        pristine = (PRISTINE / path).read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(original)).encode() + b'\0' + original).hexdigest()
        row = tree[path]
        if original != pristine or row['type'] != 'blob' or row['mode'] != '100644' or row['sha'] != blob or row['size'] != len(original):
            raise ValueError('current unchanged baseline differs from exact official Git source')
        after = proposed(path, original)
        if original == after or after[:after.find(b'package ')] != original[:original.find(b'package ')]:
            raise ValueError('proposal empty or original copyright/license header changed')
        patches.extend(difflib.unified_diff(original.decode().splitlines(keepends=True), after.decode().splitlines(keepends=True), fromfile='a/' + path, tofile='b/' + path, n=3))
        records[path] = {'official_git_blob': blob, 'official_git_mode': row['mode'], 'before_bytes': len(original), 'before_SHA256': hashlib.sha256(original).hexdigest(), 'after_bytes': len(after), 'RAM_proposed_after_SHA256': hashlib.sha256(after).hexdigest(), 'current_candidate_equals_pristine_exact_official_source': True, 'copyright_license_header_unchanged': True, 'primary_source_URL': 'https://github.com/flutter/flutter/blob/ad70ec4617166f1c38e5d2bfd388af71fda14f06/' + path}
    patch = ''.join(patches).encode()
    with (HERE / 'proposed-five-file-task-test-compatibility.patch').open('xb') as out:
        out.write(patch)
        out.flush()
        os.fsync(out.fileno())
    manifest = {'status': 'REVIEW_PROPOSAL_ONLY__NOT_APPLIED', 'scope': 'Five exact unchanged upstream task/test files only; original three Collect version/checker deltas remain unchanged', 'official_flutter_commit': 'ad70ec4617166f1c38e5d2bfd388af71fda14f06', 'patch_SHA256': hashlib.sha256(patch).hexdigest(), 'files': records, 'candidate_source_modified': False, 'shared_pristine_SDK_modified': False, 'new_dependency_or_version_deltas': False, 'cache_enabled': False, 'path_default_preserved': 'ABSOLUTE', 'test_omission_or_assertion_disabling': False, 'template_maxKnown_fourth_delta': False, 'future_total_exact_changed_source_files': 8, 'future_real_compiler_recipe': 'unchanged complete a1caea5 command; fixed new2700s attempt after explicit root review and actual source admission', 'production_release_approval': False}
    with (HERE / 'proposed-five-file-delta.json').open('x') as out:
        json.dump(manifest, out, indent=2, sort_keys=True)
        out.write('\n')
        out.flush()
        os.fsync(out.fileno())
    print(json.dumps({'five_exact_baselines_authenticated': True, 'patch_SHA256': manifest['patch_SHA256'], 'candidate_source_modified': False}))


if __name__ == '__main__':
    main()
