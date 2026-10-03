#!/usr/bin/env python3
"""Offline JVM checks of actual gateway source; no Android sender/network calls."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
CACHE = Path.home() / '.gradle/caches/modules-2/files-2.1'
JBR = Path('/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home')

def jar(group, name, version):
    found = sorted((CACHE / group / name / version).glob('*/*.jar'))
    if len(found) != 1:
        raise RuntimeError(f'Pinned cached dependency unavailable: {name} {version}')
    return found[0]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet', required=True, type=Path)
    args = parser.parse_args()
    packet = args.packet.resolve()
    packet.mkdir(parents=True, exist_ok=False)
    classes = Path(tempfile.mkdtemp(prefix='collect-gateway-jvm-'))
    base = 'android/app/src/internal_gateway/kotlin/app/cool/mobile/gateway/'
    paths = [ROOT / (base + name + '.kt') for name in ('GatewayJournal', 'GatewayCrypto', 'GatewayDispatch', 'GatewayWire', 'GatewayTransport', 'GatewayRadioObservation')]
    paths += sorted((ROOT / 'android/app/src/testInternal_gateway/kotlin/app/cool/mobile/gateway').glob('*.kt'))
    paths.append(Path(__file__).resolve())
    hashes = {str(p.relative_to(ROOT)): digest(p) for p in paths}
    for path in paths:
        target = packet / 'source' / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        assert digest(target) == hashes[str(path.relative_to(ROOT))]
    deps = [jar('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.3.20'),
            jar('org.jetbrains.kotlin', 'kotlin-stdlib', '2.3.20'),
            jar('org.jetbrains.kotlin', 'kotlin-script-runtime', '2.3.20'),
            jar('org.jetbrains.kotlin', 'kotlin-reflect', '1.6.10'),
            jar('org.jetbrains', 'annotations', '13.0'),
            jar('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.1'),
            jar('junit', 'junit', '4.13.2'), jar('org.hamcrest', 'hamcrest-core', '1.3'), jar('org.json', 'json', '20250517')]
    cp = os.pathsep.join(str(p) for p in deps)
    source_cp = os.pathsep.join(str(deps[index]) for index in (1, 4, 6, 7, 8))
    compile_cmd = [str(JBR / 'bin/java'), '-Xms64m', '-Xmx1g', '-XX:ReservedCodeCacheSize=128m', '-XX:ActiveProcessorCount=2', '-cp', cp, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                   '-no-stdlib', '-no-reflect', '-jvm-target', '17', '-classpath', source_cp, '-d', str(classes),
                   *[str(packet / 'source' / p.relative_to(ROOT)) for p in paths[:-1]]]
    commands = []
    def run(name, argv):
        try:
            result = subprocess.run(argv, capture_output=True, timeout=360)
        except subprocess.TimeoutExpired as error:
            result = subprocess.CompletedProcess(argv, 124, error.stdout or b'', (error.stderr or b'') + b'\nBounded compiler/test timeout.\n')
        (packet / (name + '.stdout')).write_bytes(result.stdout)
        (packet / (name + '.stderr')).write_bytes(result.stderr)
        commands.append({'name': name, 'argv': argv, 'exit_code': result.returncode,
                         'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
                         'stderr_sha256': hashlib.sha256(result.stderr).hexdigest()})
        return result.returncode
    code = run('compile', compile_cmd)
    if code == 0:
        code = run('tests', [str(JBR / 'bin/java'), '-ea', '-cp', os.pathsep.join([str(classes), source_cp]),
                           'org.junit.runner.JUnitCore', 'app.cool.mobile.gateway.GatewaySafetyTest',
                           'app.cool.mobile.gateway.GatewayWireTest', 'app.cool.mobile.gateway.GatewayTransportTest',
                           'app.cool.mobile.gateway.GatewayRadioObservationTest'])
    drift = [p for p, value in hashes.items() if digest(ROOT / p) != value]
    report = {'status': 'pass' if not code and not drift else 'fail', 'commands': commands,
              'source_sha256': hashes, 'source_changes': drift,
              'dependencies_sha256': {str(p): digest(p) for p in deps},
              'scope': 'Actual pure journal/crypto/dispatch source; fake backend and fake sender only. No Android OS, HTTP, physical handset, enrollment, provider or production acceptance.'}
    (packet / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': report['status'], 'exit_code': code, 'source_changes': drift}))
    raise SystemExit(0 if not code and not drift else 1)

if __name__ == '__main__':
    main()
