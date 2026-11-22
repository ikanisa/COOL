"""Expected sandbox cases and evidence from the Android instrumentation runner."""
from __future__ import annotations

from pathlib import Path
import re
import uuid
import xml.etree.ElementTree as ET

from native_artifacts import ROOT, ROLES
from native_pipeline_io import PipelineError


TEST_CLASSES = ('NativeUiContractTest', 'StaffPackageIsolationTest', 'NativeSandboxContractTest', 'export.ExportRenderingTest')
RECEIVER_TEST_CLASSES = ('app.cool.mobile.receiver_sms.GatewayDurabilityTest',)
# CarrierFixtureReplayTest requires an approved private corpus and a disposable
# .debug package. It cannot run in the offline nativeTest sandbox or contribute
# a skipped/assumed pass to this synthetic instrumentation contract.
SAFE_PACKAGE = re.compile(r'^rw\.ikanisa\.burimunsi\.(staff|gateway)\.cloud\.nativeTest(?:\.test)?$')


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
