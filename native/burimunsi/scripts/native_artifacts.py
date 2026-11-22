"""Build identities, Gradle artifact selection and APK boundary inspection."""
from __future__ import annotations

import dataclasses
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile

from native_pipeline_io import PipelineError, command, contained_file, sdk_tool, sha, write_json
from verify_native_boundary import A, SMS_NAMES, manifest_failures


ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT.parents[1]
RUNNER = 'androidx.test.runner.AndroidJUnitRunner'
VERSION_CODE = 49
VERSION_NAME = '0.23.0-collect.27'
ROLES = {'staff': 'staff', 'internal_receiver': 'gateway'}
TYPES = ('debug', 'qualification', 'nativeTest')


@dataclasses.dataclass(frozen=True)
class Artifact:
    flavor: str
    kind: str
    test: bool = False

    @property
    def variant(self) -> str:
        return self.flavor + self.kind[0].upper() + self.kind[1:] + ('AndroidTest' if self.test else '')

    @property
    def package(self) -> str:
        suffix = 'debug' if self.kind == 'debug' else self.kind
        return f'rw.ikanisa.burimunsi.{ROLES[self.flavor]}.cloud.{suffix}' + ('.test' if self.test else '')

    @property
    def filename(self) -> str:
        return self.flavor + '-' + self.kind + ('-androidTest' if self.test else '') + '.apk'

    @property
    def output_dir(self) -> Path:
        prefix = ROOT / 'app/build/outputs/apk'
        return prefix / 'androidTest' / self.flavor / self.kind if self.test else prefix / self.flavor / self.kind


def artifacts() -> list[Artifact]:
    return [Artifact(f, k) for f in ROLES for k in TYPES] + [Artifact(f, 'nativeTest', True) for f in ROLES]


def build_tasks() -> list[str]:
    tasks = ['clean', ':core:coreChecks', ':core:managedTransportChecks', ':app:lintStaffDebug', ':app:lintInternal_receiverDebug',
             ':app:lintStaffNativeTest', ':app:lintInternal_receiverNativeTest']
    return tasks + [':app:assemble' + a.variant[0].upper() + a.variant[1:] for a in artifacts()]


def select_apk(directory: Path, expected_variant: str) -> Path:
    """Select one current single-APK output by AGP metadata; never arbitrary find/head."""
    metadata = contained_file(directory, 'output-metadata.json')
    doc = json.loads(metadata.read_text())
    if doc.get('variantName') != expected_variant:
        raise PipelineError('Unexpected Gradle variant in ' + str(metadata))
    elements = doc.get('elements', [])
    if len(elements) != 1 or elements[0].get('filters'):
        raise PipelineError('Exactly one universal APK is required; split/ambiguous output refused.')
    output = elements[0].get('outputFile', '')
    if not output.endswith('.apk'):
        raise PipelineError('APK output filename missing.')
    return contained_file(directory, output)


def inspect_xml(xml: str, spec: Artifact) -> list[str]:
    tree = ET.fromstring(xml)
    errors: list[str] = []
    if tree.get('package') != spec.package:
        errors.append('APK package identity mismatch')
    if tree.get(A + 'sharedUserId'):
        errors.append('Shared UID is forbidden')
    if spec.test:
        runners = tree.findall('instrumentation')
        target = Artifact(spec.flavor, 'nativeTest').package
        if len(runners) != 1 or runners[0].get(A + 'name') != RUNNER or runners[0].get(A + 'targetPackage') != target:
            errors.append('Test APK runner/target mismatch')
        return errors
    suffix = {'debug': '', 'qualification': '-qualification', 'nativeTest': '-native-test'}[spec.kind]
    if (tree.get(A + 'versionCode') != str(VERSION_CODE) or tree.get(A + 'versionCodeMajor', '0') != '0' or
            tree.get(A + 'versionName') != VERSION_NAME + suffix):
        errors.append('APK version does not match the local candidate')
    errors.extend(manifest_failures(xml, spec.flavor, qualification=spec.kind == 'qualification',
                                   native_test=spec.kind == 'nativeTest', strict_components=True))
    app = tree.find('application')
    sdk = tree.find('uses-sdk')
    if sdk is None or sdk.get(A + 'minSdkVersion') != '26' or sdk.get(A + 'targetSdkVersion') != '36':
        errors.append('APK SDK levels do not match pinned min26/target36')
    if app is not None and spec.kind == 'debug' and app.get(A + 'debuggable') != 'true':
        errors.append('Expected debug artifact is not debuggable')
    return errors


def inspect_apk(path: Path, spec: Artifact, sdk: Path, output: Path) -> dict:
    folder = output / spec.filename.removesuffix('.apk')
    folder.mkdir(parents=True, exist_ok=False)
    analyzer = sdk_tool(sdk, 'apkanalyzer')
    xml = command([str(analyzer), 'manifest', 'print', str(path)], folder / 'manifest.xml')
    failures = inspect_xml(xml, spec)
    with zipfile.ZipFile(path) as archive:
        entries = archive.namelist()
        if not any(re.fullmatch(r'classes(?:\d+)?\.dex', n) for n in entries):
            failures.append('APK contains no DEX')
        if not spec.test and spec.flavor == 'staff':
            for name in entries:
                if name.endswith('.dex') and any(v.encode() in archive.read(name) for v in SMS_NAMES):
                    failures.append('Staff DEX contains prohibited receiver/listener marker')
        if not spec.test and any(v.endswith('.html') for v in entries):
            failures.append('Native APK contains HTML')
    command([str(sdk_tool(sdk, 'zipalign')), '-c', '-P', '16', '4', str(path)], folder / 'alignment.txt')
    certificate = None
    if spec.kind != 'qualification':
        signed = command([str(sdk_tool(sdk, 'apksigner')), 'verify', '--verbose', '--print-certs', str(path)], folder / 'signature.txt')
        matches = re.findall(r'Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', signed)
        if len(matches) != 1:
            failures.append('Exactly one signing certificate is required for this test pipeline')
        else:
            certificate = matches[0].lower()
    result = {'spec': dataclasses.asdict(spec), 'package': spec.package, 'bytes': path.stat().st_size,
              'sha256': sha(path), 'certificate_sha256': certificate, 'signature_verified': certificate is not None,
              'optimized_unsigned_qualification': spec.kind == 'qualification',
              'ok': not failures, 'failures': failures, 'scope': 'actual APK inspection'}
    write_json(folder / 'inspection.json', result)
    if failures:
        raise PipelineError('; '.join(failures))
    return result
