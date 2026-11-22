#!/usr/bin/env python3
"""Replace a rebuilt, offline code-48 nativeTest APK in a fresh API 36 emulator sandbox."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
import native_pipeline as pipeline
import qualify_production as qualify

PREDECESSOR_SOURCE = 'e42bd3ba7b57a6f1eaadce62f3a60b17b39ee04d8720bc7c79b796bc34b146e3'
TEST = 'rw.ikanisa.burimunsi.InstalledUpgradeTest#protectedDataSurvivesPackageReplacement'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(args):
    return subprocess.run(list(map(str, args)), check=True, capture_output=True, timeout=120).stdout


def apk_identity(sdk, path, package, version=None):
    manifest = run([pipeline.sdk_tool(sdk, 'aapt2'), 'dump', 'badging', path]).decode().splitlines()[0]
    require("name='" + package + "'" in manifest, 'Archive has another package ID')
    if version is not None:
        require("versionCode='" + str(version) + "'" in manifest, 'Archive version differs from expected version')
    signature = run([pipeline.sdk_tool(sdk, 'apksigner'), 'verify', '--verbose', '--print-certs', path]).decode()
    pins = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([a-f0-9]{64})$', signature, re.M)
    require(len(pins) == 1 and re.search(r'^Verified using v2 scheme .*: true$', signature, re.M), 'APK signature invalid')
    return {'apk_sha256': pipeline.sha(path), 'certificate_sha256': pins[0], 'version_code': version}


def execute(args):
    require(args.execute and re.fullmatch(r'emulator-[0-9]+', args.serial), 'Specify an emulator with explicit execution')
    sdk = pipeline.sdk_path(args.sdk)
    out = pipeline.fresh_dir(args.evidence_dir)
    predecessor = args.predecessor_root.absolute()
    require(qualify.fingerprint(predecessor)['sha256'] == PREDECESSOR_SOURCE, 'Rebuilt predecessor source differs')
    evidence = args.build_evidence.absolute()
    build = json.loads(pipeline.contained_file(evidence, 'build-result.json').read_text())
    inventory = json.loads(pipeline.contained_file(evidence, 'artifacts.json').read_text())
    source = pipeline.source_fingerprint()['sha256']
    require(build.get('status') == 'PASS' and build.get('apk_inspection_passed') is True and
            inventory.get('source_sha256') == source, 'Candidate differs from inspected build')
    rows = {row['path']: row for row in inventory['artifacts']}
    adb = pipeline.sdk_tool(sdk, 'adb')

    def remote(*command):
        return run([adb, '-s', args.serial, *command])

    def installed_digest(package):
        path = remote('shell', 'pm', 'path', package).decode().strip()
        require(re.fullmatch(r'package:/data/app/[^\r\n]+/base\.apk', path), 'Cannot bind the installed universal APK')
        return hashlib.sha256(remote('exec-out', 'cat', path[8:])).hexdigest()

    def test(package, flavor, stage):
        result = remote('shell', 'am', 'instrument', '-w', '-r', '-e', 'class', TEST,
                        '-e', 'upgradeStage', stage, package + '.test/' + pipeline.RUNNER)
        log = out / (flavor + '-' + stage + '.txt')
        log.write_bytes(result)
        require(pipeline.parse_instrumentation(result.decode(), {TEST})['passed'], 'Installed upgrade assertion failed')
        return pipeline.sha(log)

    require(remote('shell', 'getprop', 'ro.kernel.qemu').strip() == b'1' and
            remote('shell', 'getprop', 'ro.build.version.sdk').strip() == b'36' and
            remote('shell', 'getprop', 'sys.boot_completed').strip() == b'1' and
            remote('shell', 'am', 'get-current-user').strip() == b'0', 'Fresh API 36 emulator primary user required')
    result = {'format': 'collect.burimunsi.synthetic-sandbox-replacement.v1', 'status': 'FAIL',
              'predecessor_source_sha256': PREDECESSOR_SOURCE, 'candidate_source_sha256': source,
              'device_kind': 'emulator', 'api': 36, 'flavors': {}, 'sandbox_packages_removed': []}
    installed = []
    try:
        for flavor in pipeline.ROLES:
            target = pipeline.Artifact(flavor, 'nativeTest')
            runner = pipeline.Artifact(flavor, 'nativeTest', True)
            package = target.package
            require(not remote('shell', 'pm', 'list', 'packages', package).strip(), 'Sandbox package already installed')
            old_dir = predecessor / 'native/burimunsi/app/build/outputs/apk' / flavor / 'nativeTest'
            old = pipeline.select_apk(old_dir, target.variant)
            candidate = pipeline.contained_file(evidence, 'apks/' + target.filename)
            tests = pipeline.contained_file(evidence, 'apks/' + runner.filename)
            before = apk_identity(sdk, old, package, 48)
            after = apk_identity(sdk, candidate, package, pipeline.VERSION_CODE)
            instrument = apk_identity(sdk, tests, runner.package)
            for spec, item in [(target, after), (runner, instrument)]:
                row = rows['apks/' + spec.filename]
                require(row['ok'] and row['signature_verified'] and row['sha256'] == item['apk_sha256'] and
                        row['certificate_sha256'] == item['certificate_sha256'], 'Candidate archive changed')
            require(before['certificate_sha256'] == after['certificate_sha256'] == instrument['certificate_sha256'],
                    'Sandbox signing identities differ')
            require(b'Success' in remote('install', '-t', str(old)), 'Predecessor install failed')
            installed.append(package)
            require(b'Success' in remote('install', '-t', str(tests)), 'Test runner install failed')
            installed.append(runner.package)
            require(installed_digest(package) == before['apk_sha256'], 'Installed predecessor changed')
            seed = test(package, flavor, 'seed')
            require(b'Success' in remote('install', '-r', '-t', str(candidate)), 'In-place update failed')
            require(installed_digest(package) == after['apk_sha256'], 'Installed candidate changed')
            verified = test(package, flavor, 'verify')
            result['flavors'][flavor] = {'package': package, 'before': before, 'after': after,
                                         'seed_test_sha256': seed, 'verify_test_sha256': verified}
        result['status'] = 'PASS'
    finally:
        for package in reversed(installed):
            removed = False
            try:
                removed = b'Success' in remote('uninstall', package)
            except (OSError, subprocess.SubprocessError):
                pass
            result['sandbox_packages_removed'].append({'package': package, 'removed': removed})
            if not removed:
                result['status'] = 'FAIL'
        result['finished_at'] = pipeline.now()
        pipeline.write_json(out / 'result.json', result)
    require(result['status'] == 'PASS', 'Sandbox cleanup failed')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--sdk')
    parser.add_argument('--serial', required=True)
    for field in ('predecessor-root', 'build-evidence', 'evidence-dir'):
        parser.add_argument('--' + field, required=True, type=Path)
    print(json.dumps(execute(parser.parse_args()), indent=2))
