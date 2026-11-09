#!/usr/bin/env python3
"""Build, inspect and execute isolated Android tests, with evidence for every phase.

plan is read-only. build never signs production or accepts SDK licences. instrument
requires --execute and a named device, and touches only new .nativeTest packages.
A successful host-side test of this script is NOT an executed native build.
"""
from __future__ import annotations
import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
import zipfile

from build_preflight import inspect as preflight
from verify_native_boundary import A, SMS_NAMES, manifest_failures, source_checks

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT.parents[1]
RUNNER = 'androidx.test.runner.AndroidJUnitRunner'
ROLES = {'staff': 'staff', 'internal_receiver': 'gateway'}
TYPES = ('debug', 'qualification', 'nativeTest')
TEST_CLASSES = ('NativeUiContractTest', 'StaffPackageIsolationTest', 'NativeSandboxContractTest')
RECEIVER_TEST_CLASSES = ('app.cool.mobile.receiver_sms.GatewayDurabilityTest',)
# CarrierFixtureReplayTest requires an approved private corpus and a disposable
# .debug package. It cannot run in the offline nativeTest sandbox or contribute
# a skipped/assumed pass to this synthetic instrumentation contract.
SAFE_PACKAGE = re.compile(r'^rw\.ikanisa\.burimunsi\.(staff|gateway)\.nativeTest(?:\.test)?$')

class PipelineError(ValueError):
    """An execution gate failed; no success attestation is permitted."""


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def fresh_dir(path: Path) -> Path:
    path = path.expanduser().absolute()
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise PipelineError('Evidence directory must not traverse symlinks.')
    if path.exists() and (not path.is_dir() or any(path.iterdir())):
        raise PipelineError('Use a new empty evidence directory; stale results are not reusable.')
    path.mkdir(parents=True, exist_ok=True)
    return path


def contained_file(base: Path, relative: str) -> Path:
    p = Path(relative)
    if p.is_absolute() or '..' in p.parts or '\\' in relative:
        raise PipelineError('Unsafe artifact path.')
    path = base / p
    if any(v.is_symlink() for v in (path, *path.parents)):
        raise PipelineError('Artifact links are forbidden.')
    if base.resolve() not in path.resolve().parents or not path.is_file():
        raise PipelineError('Missing/out-of-tree artifact: ' + relative)
    return path


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
        return f'rw.ikanisa.burimunsi.{ROLES[self.flavor]}.{suffix}' + ('.test' if self.test else '')

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


def instrumentation_classes(flavor: str) -> tuple[str, ...]:
    if flavor not in ROLES:
        raise PipelineError('Unknown instrumentation flavor')
    shared = tuple('rw.ikanisa.burimunsi.' + name for name in TEST_CLASSES)
    return shared + (RECEIVER_TEST_CLASSES if flavor == 'internal_receiver' else ())


def expected_tests(root: Path = ROOT, flavor: str = 'staff') -> set[str]:
    found: set[str] = set()
    for qualified in instrumentation_classes(flavor):
        source_set = 'androidTestInternal_receiver' if qualified in RECEIVER_TEST_CLASSES else 'androidTest'
        source = (root / 'app/src' / source_set / 'kotlin' / (qualified.replace('.', '/') + '.kt')).read_text(encoding='utf-8')
        methods = re.findall(r'@Test\s+fun\s+(\w+)\s*\(', source)
        if not methods or len(methods) != len(set(methods)):
            raise PipelineError('Missing or duplicate test declarations in ' + qualified)
        found.update(qualified + '#' + method for method in methods)
    return found


def test_contracts(root: Path = ROOT) -> dict[str, list[str]]:
    return {flavor: sorted(expected_tests(root, flavor)) for flavor in ROLES}


def plan() -> dict:
    return {'schema': 1, 'mode': 'plan', 'native_build_executed': False,
            'gradle_tasks': build_tasks(), 'artifacts': [dataclasses.asdict(a) | {'package': a.package} for a in artifacts()],
            'expected_instrumentation_tests_per_flavor': test_contracts(),
            'device_policy': 'Named emulator by default; physical device requires explicit opt-in. Never overwrite installed packages.',
            'production_signing': False, 'production_deployment': False, 'licence_acceptance': False}


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


def command(args: list[str], log: Path, *, timeout: int = 120, env: dict | None = None) -> str:
    """Stream directly to a retained log, syncing progress while the child runs.

    No shell expansion; log only bounded commands without credentials. Child
    output bypasses Python buffers so interruption does not discard the build
    transcript. Sync at most every second, and again on every normal exit path.
    """
    process = None
    try:
        with log.open('wb', buffering=0) as output:
            try:
                process = subprocess.Popen([str(v) for v in args], stdout=output,
                                           stderr=subprocess.STDOUT, env=env)
                deadline = time.monotonic() + timeout
                while True:
                    try:
                        process.wait(timeout=max(0, min(1, deadline - time.monotonic())))
                        break
                    except subprocess.TimeoutExpired as error:
                        os.fsync(output.fileno())
                        if time.monotonic() >= deadline:
                            process.kill()
                            process.wait()
                            output.write(b'\nTIMED OUT\n')
                            raise PipelineError('Command timed out: ' + Path(str(args[0])).name) from error
            except OSError as error:
                output.write((str(error) + '\n').encode('utf-8', errors='replace'))
                raise PipelineError('Tool could not be executed: ' + str(args[0])) from error
            finally:
                if process is not None and process.poll() is None:
                    process.kill()
                    process.wait()
                os.fsync(output.fileno())
    except OSError as error:
        raise PipelineError('Tool could not be executed: ' + str(args[0])) from error
    if process.returncode:
        raise PipelineError(f'Command failed ({process.returncode}); see {log.name}')
    return log.read_text(encoding='utf-8', errors='replace')


def sdk_path(value: str | None) -> Path:
    sdk = value or os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        raise PipelineError('Set ANDROID_HOME or supply --sdk.')
    return Path(sdk).expanduser().absolute()


def sdk_tool(sdk: Path, name: str) -> Path:
    if name == 'adb':
        p = sdk / 'platform-tools/adb'
    elif name in ('apksigner', 'zipalign', 'aapt2'):
        p = sdk / 'build-tools/36.0.0' / name
    else:
        # Prefer the SDK owner's selected latest directory; otherwise refuse ambiguity.
        p = sdk / 'cmdline-tools/latest/bin' / name
        if not p.is_file():
            choices = sorted(sdk.glob('cmdline-tools/*/bin/' + name))
            if len(choices) != 1:
                raise PipelineError('Select one installed command-line-tools version for ' + name)
            p = choices[0]
    if not p.is_file() or not os.access(p, os.X_OK):
        raise PipelineError('SDK tool missing/not executable: ' + str(p))
    return p


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


def source_fingerprint() -> dict:
    rows = []
    for base in (ROOT, OVERLAY / 'upstream/collect'):
        for path in sorted(base.rglob('*')):
            if not path.is_file() or any(p in ('build', '.gradle', '__pycache__') for p in path.parts) or path.suffix == '.pyc':
                continue
            if path.name == 'local.properties':
                continue
            rows.append({'path': path.relative_to(OVERLAY).as_posix(), 'sha256': sha(path)})
    encoded = json.dumps(rows, sort_keys=True).encode()
    return {'sha256': hashlib.sha256(encoded).hexdigest(), 'files': rows}


def build(args: argparse.Namespace) -> int:
    out = fresh_dir(args.output)
    result = {'schema': 1, 'run_id': str(uuid.uuid4()), 'started_at': now(), 'status': 'BLOCKED',
              'native_build_executed': False, 'apk_inspection_passed': False, 'instrumentation_executed': False,
              'production_deployment': False, 'stage': 'preflight'}
    try:
        if args.download_gradle:
            command([sys.executable, str(ROOT / 'scripts/bootstrap_gradle.py'), '--download'], out / 'gradle-bootstrap.log', timeout=180)
        report = preflight(args.sdk)
        write_json(out / 'preflight.json', report)
        if not report['ready_for_build']:
            raise PipelineError('Build prerequisites unavailable: ' + ', '.join(c['name'] for c in report['checks'] if not c['ok']))
        sdk = sdk_path(args.sdk)
        failures = source_checks(ROOT)
        if failures:
            raise PipelineError('Source boundary: ' + '; '.join(failures))
        fingerprint = source_fingerprint()
        write_json(out / 'source-fingerprint.json', fingerprint)
        command([str(sdk_tool(sdk, 'sdkmanager')), '--sdk_root=' + str(sdk), '--list_installed'], out / 'sdk-packages.txt')
        command([str(sdk_tool(sdk, 'adb')), 'version'], out / 'adb-version.txt')
        java = str(Path(os.environ['JAVA_HOME']) / 'bin/java') if os.environ.get('JAVA_HOME') else 'java'
        command([java, '-version'], out / 'java-version.txt')
        result['stage'] = 'gradle-build'
        result['native_build_executed'] = True
        # Never permit locally configured endpoints in this evidence build. Optimized and
        # nativeTest variants also hard-override every endpoint and binding in their DSL.
        config = ['-P' + k + '=' for k in ('collectSupabaseOrigin', 'collectAdminOrigin', 'burimunsiApiOrigin', 'burimunsiApiPathPrefix', 'collectGatewayOrigin', 'burimunsiGroupId',
                  'collectPublishableKey', 'receiptProfileVersion')]
        config.append('-PreceiptUtcOffsetMinutes=2147483647')
        env = os.environ.copy()
        env['ANDROID_HOME'] = str(sdk)
        env['ANDROID_SDK_ROOT'] = str(sdk)
        cmd = ['sh', str(ROOT / 'gradlew'), *build_tasks(), *config, '--no-daemon', '--stacktrace', '--console=plain']
        write_json(out / 'build-command.json', cmd)
        command(cmd, out / 'gradle-build.log', timeout=2400, env=env)
        result['stage'] = 'apk-inspection'
        records = []
        (out / 'apks').mkdir()
        for spec in artifacts():
            path = select_apk(spec.output_dir, spec.variant)
            record = inspect_apk(path, spec, sdk, out / 'inspection')
            dest = out / 'apks' / spec.filename
            shutil.copyfile(path, dest)
            if sha(dest) != record['sha256']:
                raise PipelineError('APK changed during copy')
            record['path'] = dest.relative_to(out).as_posix()
            records.append(record)
        for flavor in ROLES:
            pair = [r for r in records if r['spec']['flavor'] == flavor and r['spec']['kind'] == 'nativeTest']
            if len(pair) != 2 or pair[0]['certificate_sha256'] != pair[1]['certificate_sha256']:
                raise PipelineError('Application and instrumentation APK signer mismatch')
        write_json(out / 'artifacts.json', {'source_sha256': fingerprint['sha256'], 'artifacts': records,
                                         'expected_tests_per_flavor': test_contracts()})
        (out / 'APK_SHA256SUMS').write_text(''.join(r['sha256'] + '  ' + r['path'] + '\n' for r in records))
        for source, dest in ((ROOT / 'app/build/reports', out / 'reports'),
                             (ROOT / 'core/build/test-results', out / 'core-test-results'),
                             (ROOT / 'app/build/outputs/mapping', out / 'mapping')):
            if source.exists():
                shutil.copytree(source, dest)
        if source_fingerprint()['sha256'] != fingerprint['sha256']:
            raise PipelineError('Source changed during build')
        result.update(status='PASS', stage='complete', apk_inspection_passed=True, artifact_count=len(records))
    except (PipelineError, OSError, ValueError, zipfile.BadZipFile, ET.ParseError) as error:
        result.update(status='FAIL' if result['native_build_executed'] else 'BLOCKED', error=str(error))
    finally:
        result['finished_at'] = now()
        write_json(out / 'build-result.json', result)
        print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'PASS' else 2


def parse_instrumentation(text: str, expected: set[str]) -> dict:
    """adb exit 0 is not a JUnit pass. Require exact start/completion identities."""
    block: dict[str, str] = {}
    started: set[str] = set()
    completed: dict[str, int] = {}
    failures: list[str] = []
    final_codes: list[int] = []
    for line in text.splitlines():
        if line.startswith('INSTRUMENTATION_STATUS: '):
            key, sep, value = line[len('INSTRUMENTATION_STATUS: '):].partition('=')
            if sep:
                block[key] = value
        elif line.startswith('INSTRUMENTATION_STATUS_CODE: '):
            try:
                code = int(line.split(':', 1)[1])
            except ValueError:
                failures.append('Malformed instrumentation status code')
                block = {}
                continue
            identity = block.get('class', '') + '#' + block.get('test', '')
            if identity not in expected:
                failures.append('Unexpected/missing test identity: ' + identity)
            if code == 1:
                if identity in started:
                    failures.append('Duplicate test start: ' + identity)
                started.add(identity)
            else:
                if identity not in started or identity in completed:
                    failures.append('Missing start/duplicate completion: ' + identity)
                completed[identity] = code
                if code != 0:
                    failures.append('Test failed, ignored or assumption-skipped: ' + identity)
            block = {}
        elif line.startswith('INSTRUMENTATION_CODE: '):
            try:
                final_codes.append(int(line.split(':', 1)[1]))
            except ValueError:
                failures.append('Malformed final instrumentation code')
    if not expected:
        failures.append('No expected tests')
    if set(completed) != expected or started != expected:
        failures.append('Executed test set differs from source contract')
    if final_codes != [-1]:
        failures.append('Runner did not finish exactly once with RESULT_OK')
    totals = re.findall(r'\bOK \((\d+) tests?\)', text)
    if totals != [str(len(expected))]:
        failures.append('Missing or inconsistent JUnit total')
    if any(v in text for v in ('INSTRUMENTATION_FAILED', 'INSTRUMENTATION_ABORTED', 'FAILURES!!!', 'Process crashed')):
        failures.append('Runner reported an execution failure')
    return {'passed': not failures, 'expected': len(expected), 'completed': len(completed),
            'passed_tests': sorted(k for k, v in completed.items() if v == 0), 'failures': failures}


def selected_device(devices_text: str, serial: str) -> None:
    if not re.fullmatch(r'[A-Za-z0-9_.:-]+', serial):
        raise PipelineError('Invalid device serial')
    matches = [line.split() for line in devices_text.splitlines() if line.split() and line.split()[0] == serial]
    if len(matches) != 1 or len(matches[0]) < 2 or matches[0][1] != 'device':
        raise PipelineError('Selected device is absent, unauthorized or offline')


def validated_sandbox_package(package: str) -> str:
    if not SAFE_PACKAGE.fullmatch(package):
        raise PipelineError('Only dedicated BuriMunsi nativeTest packages may be installed/removed')
    return package


def wait_for_startup_ui(call, package: str, flavor: str) -> None:
    """Wait for UIAutomator's idle hierarchy before evidence-only capture.

    am start -W reports activity startup before Compose/launch transitions have
    necessarily settled. UIAutomator waits for accessibility idle; retain its
    hierarchy as evidence and refuse a splash/foreign window without app content.
    The only device file removed here is the unique dump created by this call.
    """
    validated_sandbox_package(package)
    remote = '/data/local/tmp/burimunsi-startup-' + uuid.uuid4().hex + '.xml'
    try:
        dumped = call(['shell', 'uiautomator', 'dump', remote], flavor + '-ui-idle.txt', timeout=30)
        # The Android shell tool can report an idle/root failure with exit zero.
        if 'error:' in dumped.lower():
            raise PipelineError('Startup UI did not reach accessibility idle')
        text = call(['shell', 'cat', remote], flavor + '-startup.xml', timeout=30)
        try:
            hierarchy = ET.fromstring(text)
        except ET.ParseError as error:
            raise PipelineError('Invalid startup UI hierarchy') from error
        visible = [node for node in hierarchy.iter('node')
                   if node.get('package') == package and
                   (node.get('text', '').strip() or node.get('content-desc', '').strip())]
        if hierarchy.tag != 'hierarchy' or not visible:
            raise PipelineError('Startup UI hierarchy has no content owned by the sandbox package')
    finally:
        call(['shell', 'rm', '-f', remote], flavor + '-ui-cleanup.txt', timeout=30)


def instrument(args: argparse.Namespace) -> int:
    if not args.execute:
        print(json.dumps({'mode': 'plan', 'execute': False, 'serial': args.serial,
                          'packages': [a.package for a in artifacts() if a.kind == 'nativeTest'],
                          'expected_tests_per_flavor': test_contracts(),
                          'note': 'Add --execute to inspect, install and run on the named device.'}, indent=2))
        return 0
    out = fresh_dir(args.output)
    result = {'schema': 1, 'run_id': str(uuid.uuid4()), 'started_at': now(), 'status': 'BLOCKED',
              'installation_executed': False, 'instrumentation_executed': False, 'flavors': [],
              'production_deployment': False, 'cleanup': []}
    installed: list[str] = []
    adb: Path | None = None
    try:
        sdk = sdk_path(args.sdk)
        adb = sdk_tool(sdk, 'adb')
        serial = args.serial
        listed = command([str(adb), 'devices', '-l'], out / 'devices.txt')
        selected_device(listed, serial)
        def call(parts: list[str], name: str, timeout: int = 120) -> str:
            return command([str(adb), '-s', serial, *parts], out / name, timeout=timeout)
        qemu = call(['shell', 'getprop', 'ro.kernel.qemu'], 'device-kind.txt').strip()
        if qemu != '1' and not args.allow_physical_device:
            raise PipelineError('Physical device requires --allow-physical-device; use an emulator for synthetic tests')
        api = int(call(['shell', 'getprop', 'ro.build.version.sdk'], 'device-api.txt').strip())
        if api < 26:
            raise PipelineError('Device API below supported minimum 26')
        call(['shell', 'getprop', 'ro.build.fingerprint'], 'device-fingerprint.txt')
        if call(['shell', 'getprop', 'sys.boot_completed'], 'boot-state.txt').strip() != '1':
            raise PipelineError('Device has not completed boot')
        if call(['shell', 'am', 'get-current-user'], 'device-user.txt').strip() != '0':
            raise PipelineError('Use the primary device user (0); work-profile/secondary-user installation is refused')
        result.update(device_api=api, device_kind='emulator' if qemu == '1' else 'physical')
        evidence = args.build_evidence.expanduser().absolute()
        build_result = json.loads(contained_file(evidence, 'build-result.json').read_text())
        inventory = json.loads(contained_file(evidence, 'artifacts.json').read_text())
        if build_result.get('status') != 'PASS' or not build_result.get('apk_inspection_passed'):
            raise PipelineError('Build evidence is not a passing inspected build')
        contracts = test_contracts()
        if (inventory.get('source_sha256') != source_fingerprint()['sha256'] or
                inventory.get('expected_tests_per_flavor') != contracts):
            raise PipelineError('Current source does not match the built/tested source contract')
        rows = inventory.get('artifacts', [])
        prepared = {}
        for spec in [a for a in artifacts() if a.kind == 'nativeTest']:
            matches = [r for r in rows if r.get('spec') == dataclasses.asdict(spec)]
            if len(matches) != 1:
                raise PipelineError('Missing/ambiguous native-test artifact')
            row = matches[0]
            path = contained_file(evidence, row['path'])
            if sha(path) != row['sha256']:
                raise PipelineError('APK differs from build evidence')
            checked = inspect_apk(path, spec, sdk, out / 'inspection')
            if checked['certificate_sha256'] != row['certificate_sha256']:
                raise PipelineError('APK signer differs from build evidence')
            package = validated_sandbox_package(spec.package)
            # No -r, no pm clear, no uninstall of a pre-existing app, even a QA app.
            if call(['shell', 'pm', 'list', 'packages', '-u', package], spec.filename + '.existing.txt').strip():
                raise PipelineError('Sandbox package already installed; refusing to overwrite or erase it: ' + package)
            prepared[(spec.flavor, spec.test)] = (spec, path, checked)
        for flavor in ROLES:
            if prepared[(flavor, False)][2]['certificate_sha256'] != prepared[(flavor, True)][2]['certificate_sha256']:
                raise PipelineError('Test and target signer mismatch')
        # All four APKs and existing-package checks have passed before the first install.
        for flavor in ROLES:
            app_spec, app_path, _ = prepared[(flavor, False)]
            test_spec, test_path, _ = prepared[(flavor, True)]
            for spec, path in ((app_spec, app_path), (test_spec, test_path)):
                output = call(['install', '-t', str(path)], spec.filename + '.install.txt', timeout=180)
                if not re.search(r'^Success\s*$', output, re.MULTILINE):
                    raise PipelineError('Installation did not report success')
                installed.append(spec.package)
                result['installation_executed'] = True
                call(['shell', 'dumpsys', 'package', spec.package], spec.filename + '.installed.txt')
            result['instrumentation_executed'] = True
            names = ','.join(instrumentation_classes(flavor))
            text = call(['shell', 'am', 'instrument', '-w', '-r', '-e', 'class', names,
                         test_spec.package + '/' + RUNNER], flavor + '-instrumentation.txt', timeout=900)
            parsed = parse_instrumentation(text, set(contracts[flavor]))
            write_json(out / (flavor + '-instrumentation.json'), parsed)
            result['flavors'].append({'flavor': flavor, **parsed})
            if not parsed['passed']:
                raise PipelineError('Instrumentation failed contract for ' + flavor)
            if qemu == '1':
                # Exact offline nativeTest form, captured before any synthetic
                # credentials. Read only the UID installed by this invocation.
                image = subprocess.run([str(adb), '-s', serial, 'exec-out', 'run-as',
                    validated_sandbox_package(app_spec.package), 'cat', 'cache/collect-sign-in.png'],
                    capture_output=True, timeout=30, check=True).stdout
                if not image.startswith(b'\x89PNG\r\n\x1a\n') or len(image) > 10_000_000:
                    raise PipelineError('Invalid native Collect sign-in screenshot')
                destination = out / (flavor + '-collect-sign-in.png')
                destination.write_bytes(image)
                result.setdefault('ui_artifacts', []).append({'flavor': flavor, 'path': destination.name,
                    'sha256': sha(destination), 'scope': 'offline synthetic Compose root; no live identity or TLS proof'})
            # Evidence-only startup smoke: no SMS permissions, test account or financial action.
            launch = call(['shell', 'am', 'start', '-W', '-n', app_spec.package + '/rw.ikanisa.burimunsi.MainActivity'], flavor + '-launch.txt')
            if not re.search(r'^Status:\s*ok\s*$', launch, re.MULTILINE):
                raise PipelineError('Main activity failed to launch')
            if qemu == '1':
                wait_for_startup_ui(call, app_spec.package, flavor)
            focused = call(['shell', 'dumpsys', 'activity', 'activities'], flavor + '-activity.txt')
            if not any(app_spec.package in line and ('mResumedActivity' in line or 'topResumedActivity' in line) for line in focused.splitlines()):
                raise PipelineError('Sandbox activity is not foreground; screenshot refused')
            # Avoid collecting a personal physical-device screenshot by default.
            if qemu == '1':
                shot = subprocess.run([str(adb), '-s', serial, 'exec-out', 'screencap', '-p'], capture_output=True, timeout=30, check=True).stdout
                if not shot.startswith(b'\x89PNG\r\n\x1a\n'):
                    raise PipelineError('Invalid screenshot output')
                (out / (flavor + '-startup.png')).write_bytes(shot)
            call(['shell', 'am', 'force-stop', app_spec.package], flavor + '-stop.txt')
        result['status'] = 'PASS'
    except (PipelineError, OSError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError, subprocess.SubprocessError) as error:
        result.update(status='FAIL' if result['installation_executed'] else 'BLOCKED', error=str(error))
    finally:
        if adb:
            for package in reversed(installed):
                try:
                    # Only packages installed successfully by this invocation are owned here.
                    text = command([str(adb), '-s', args.serial, 'uninstall', validated_sandbox_package(package)],
                                   out / (package + '.cleanup.txt'))
                    ok = bool(re.search(r'^Success\s*$', text, re.MULTILINE))
                except (PipelineError, OSError):
                    ok = False
                result['cleanup'].append({'package': package, 'removed': ok})
                if not ok:
                    result.update(status='FAIL', cleanup_error='A sandbox installed by this run remains; inspect cleanup evidence.')
        result['finished_at'] = now()
        write_json(out / 'instrumentation-result.json', result)
        print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'PASS' else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    sub.add_parser('plan')
    p = sub.add_parser('build')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--sdk')
    p.add_argument('--download-gradle', action='store_true')
    p = sub.add_parser('instrument')
    p.add_argument('--build-evidence', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--serial', required=True)
    p.add_argument('--sdk')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--allow-physical-device', action='store_true')
    args = parser.parse_args()
    if args.mode == 'plan':
        print(json.dumps(plan(), indent=2))
        return 0
    return build(args) if args.mode == 'build' else instrument(args)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (PipelineError, OSError, ValueError) as error:
        print(json.dumps({'status': 'BLOCKED', 'error': str(error), 'native_success_claimed': False}), file=sys.stderr)
        sys.exit(2)
