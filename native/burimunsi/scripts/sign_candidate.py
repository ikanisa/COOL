#!/usr/bin/env python3
"""Offline testing-candidate signer. Default plan; --execute signs fresh outputs.

No build, keystore generation, network, device operation or production promotion.
Password values travel only through protected files read by JDK/SDK tools.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys
import zipfile

sys.dont_write_bytecode = True
import native_pipeline as pipeline
import release_readiness as readiness
from verify_native_boundary import A, SMS_NAMES, manifest_failures
import xml.etree.ElementTree as ET

PACKAGES = {'staff': 'rw.ikanisa.burimunsi.staff.cloud', 'internal_receiver': 'rw.ikanisa.burimunsi.gateway.cloud'}
TASKS = [':app:assembleStaffRelease', ':app:assembleInternal_receiverRelease']
VERSION_CODE = 45


class SigningRejected(ValueError):
    pass


def need(value, code):
    if not value:
        raise SigningRejected(code)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def fields(value, names):
    need(type(value) is dict and set(value) == set(names), 'evidence_fields_wrong')


def current_source():
    return pipeline.source_fingerprint()['sha256']


def load_evidence(path, expected_sha, alias, certificate):
    readiness._digest(expected_sha); readiness._digest(certificate)
    path = Path(path).absolute()
    need(not any(path.is_relative_to(p) for p in (pipeline.ROOT, pipeline.OVERLAY / 'upstream/collect')), 'evidence_inside_source')
    raw = readiness._physical(path)
    need(digest(raw) == expected_sha, 'evidence_hash_changed')
    doc = readiness._object(raw)
    fields(doc, ('format', 'created_at', 'source_sha256', 'candidate', 'profile', 'signing_profile', 'build', 'artifacts'))
    need(doc['format'] == 'collect.burimunsi.unsigned-testing-candidate.v1', 'evidence_format_wrong')
    now = dt.datetime.now(dt.timezone.utc)
    readiness._fresh(doc['created_at'], now)
    source = readiness._digest(doc['source_sha256'])
    need(current_source() == source, 'source_changed')
    base = path.parent
    refs = [(path, expected_sha)]
    loaded = {}
    for name in ('candidate', 'profile', 'signing_profile', 'build'):
        value, ref = readiness._ref(base, doc[name])
        loaded[name] = value
        loaded[name + '_path'] = ref
        refs.append((ref, doc[name]['sha256']))
    signing = loaded['signing_profile']
    fields(signing, ('format', 'purpose', 'alias', 'certificate_sha256', 'packages', 'version_code', 'production_authorized'))
    need(signing['format'] == 'collect.burimunsi.testing-signing-profile.v1' and
         signing['purpose'] == 'testing-candidate-signing' and signing['packages'] == PACKAGES and
         type(signing['version_code']) is int and signing['version_code'] == VERSION_CODE and
         signing['production_authorized'] is False, 'signing_profile_wrong')
    need(type(alias) is str and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', alias) and
         signing['alias'] == alias and signing['certificate_sha256'] == certificate, 'signing_identity_pin_mismatch')
    build = loaded['build']
    fields(build, ('format', 'source_sha256', 'candidate_sha256', 'properties', 'tasks', 'command_sha256',
                   'returncode', 'finished_at', 'unsigned_apk_sha256'))
    need(build['format'] == 'collect.burimunsi.configured-release-build.v1' and
         build['source_sha256'] == source and build['candidate_sha256'] == doc['candidate']['sha256'] and
         build['tasks'] == TASKS and type(build['returncode']) is int and build['returncode'] == 0,
         'configured_build_wrong')
    readiness._digest(build['command_sha256']); readiness._fresh(build['finished_at'], now)
    fields(build['unsigned_apk_sha256'], PACKAGES)
    # Explicit actual compiler properties; ambient BURI_BUILD_PUBLIC_PROPERTIES
    # cannot replace them. The candidate gate grants no signing/promotion power.
    gate = readiness.evaluate_candidate(loaded['candidate_path'], loaded['profile_path'], build['properties'])
    need(gate.get('ready') is True and gate.get('source_sha256') == source and
         all(gate.get(name) is False for name in ('production_authorized', 'signing_authorized', 'distribution_authorized')),
         'candidate_not_ready')
    rows = doc['artifacts']
    need(type(rows) is list and len(rows) == 2, 'unsigned_artifact_set_wrong')
    artifacts = {}; seen = set()
    for row in rows:
        fields(row, ('flavor', 'package', 'version_code', 'path', 'sha256'))
        flavor = row['flavor']
        need(type(flavor) is str and flavor in PACKAGES and flavor not in seen and
             row['package'] == PACKAGES[flavor] and type(row['version_code']) is int and
             row['version_code'] == VERSION_CODE, 'unsigned_artifact_identity_wrong')
        seen.add(flavor)
        apk, ref = readiness._ref(base, {'path': row['path'], 'sha256': row['sha256']}, False)
        need(ref.suffix == '.apk' and build['unsigned_apk_sha256'][flavor] == row['sha256'], 'unsigned_build_hash_mismatch')
        artifacts[flavor] = {'raw': apk, 'sha256': row['sha256'], 'source_path': ref}
        refs.append((ref, row['sha256']))
    return {'source_sha256': source, 'evidence_sha256': expected_sha, 'profile_sha256': gate['profile_sha256'],
            'signing_profile_sha256': doc['signing_profile']['sha256'], 'alias': alias, 'certificate_sha256': certificate,
            'command_sha256': build['command_sha256'], 'artifacts': artifacts, 'refs': refs}


def stable_evidence(binding):
    need(current_source() == binding['source_sha256'], 'source_changed')
    for path, expected in binding['refs']:
        need(digest(readiness._physical(path, 64 * 1024 * 1024)) == expected, 'evidence_changed')


def private_input(path, maximum, *, password=False):
    path = Path(path).absolute()
    need(path.resolve() == path and not any(p.is_symlink() for p in (path, *path.parents)), 'credential_link_refused')
    parent = path.parent.stat()
    need(parent.st_uid == os.geteuid() and stat.S_IMODE(parent.st_mode) == 0o700, 'credential_parent_not_private')
    info = path.lstat()
    need(stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and
         stat.S_IMODE(info.st_mode) == 0o600 and info.st_nlink == 1, 'credential_not_private')
    need(not any(path.is_relative_to(p) for p in (pipeline.ROOT, pipeline.OVERLAY / 'upstream/collect')), 'credential_inside_source')
    raw = readiness._physical(path, maximum)
    after = path.stat()
    need((info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_ctime_ns) ==
         (after.st_dev, after.st_ino, after.st_mode, after.st_uid, after.st_ctime_ns), 'credential_changed')
    if password:
        line = raw[:-1] if raw.endswith(b'\n') else raw
        line = line[:-1] if line.endswith(b'\r') else line
        need(line and not any(c in line for c in (b'\x00', b'\n', b'\r')), 'password_file_not_one_line')
    return {'path': path, 'sha256': digest(raw), 'mode': info.st_mode, 'uid': info.st_uid}


def stable_credentials(inputs):
    for item in inputs:
        checked = private_input(item['path'], 16 * 1024 * 1024)
        need(checked['sha256'] == item['sha256'] and checked['mode'] == item['mode'] and
             checked['uid'] == item['uid'], 'credential_changed')


def tools(sdk, java_home):
    sdk, java_home = Path(sdk).resolve(strict=True), Path(java_home).resolve(strict=True)
    metadata = readiness._physical(sdk / 'build-tools/36.0.0/source.properties', 65536).decode('utf8')
    need(re.search(r'^Pkg.Revision\s*=\s*36\.0\.0\s*$', metadata, re.M), 'sdk_version_wrong')
    release = readiness._physical(java_home / 'release', 65536).decode('utf8')
    need(re.search(r'^JAVA_VERSION="17(?:\.[^"]*)?"$', release, re.M), 'jdk_version_wrong')
    selected = {name: pipeline.sdk_tool(sdk, name) for name in ('zipalign', 'apksigner', 'apkanalyzer')}
    selected['keytool'] = java_home / 'bin/keytool'
    need(selected['keytool'].is_file() and os.access(selected['keytool'], os.X_OK), 'keytool_unavailable')
    jar = sdk / 'build-tools/36.0.0/lib/apksigner.jar'
    need(jar.is_file(), 'apksigner_jar_unavailable')
    hashes = {name: pipeline.sha(path) for name, path in selected.items()}
    hashes['apksigner_jar'] = pipeline.sha(jar)
    env = {'JAVA_HOME': str(java_home), 'PATH': str(java_home / 'bin') + ':/usr/bin:/bin:/usr/sbin:/sbin',
           'HOME': str(Path.home()), 'LC_ALL': 'C'}
    return selected, hashes, env


def run_tool(argv, env):
    result = None
    try:
        result = subprocess.run([str(v) for v in argv], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=env, timeout=120)
    except (OSError, subprocess.SubprocessError):
        pass
    # No arbitrary command output, exception text, argv or credential hashes enter logs/receipts.
    need(result is not None and result.returncode == 0 and len(result.stdout) <= 4 * 1024 * 1024 and
         len(result.stderr) <= 4 * 1024 * 1024, 'signing_tool_failed')
    return result.stdout


def payload(raw, flavor, *, unsigned):
    need(raw.startswith(b'PK\x03\x04'), 'apk_container_wrong')
    rows = []; names = set(); total = 0
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            for item in archive.infolist():
                name = item.filename
                need(name not in names and not name.startswith('/') and '..' not in Path(name).parts and
                     not item.flag_bits & 1 and len(names) < 10000 and item.file_size <= 64 * 1024 * 1024,
                     'apk_entry_wrong')
                names.add(name); total += item.file_size
                need(total <= 256 * 1024 * 1024 and not name.endswith('.html'), 'apk_payload_wrong')
                if unsigned:
                    need(not re.fullmatch(r'META-INF/[^/]+\.(?:RSA|DSA|EC|SF)', name, re.I), 'apk_already_signed')
                data = archive.read(item)
                if flavor == 'staff' and name.endswith('.dex'):
                    need(not any(value.encode() in data for value in SMS_NAMES), 'staff_receiver_payload_refused')
                rows.append({'path': name, 'bytes': len(data), 'sha256': digest(data)})
        need('AndroidManifest.xml' in names and any(re.fullmatch(r'classes(?:\d+)?\.dex', n) for n in names), 'apk_payload_wrong')
        end = raw.rfind(b'PK\x05\x06', max(0, len(raw) - 65557))
        need(end >= 0 and end + 22 <= len(raw) and end + 22 + struct.unpack_from('<H', raw, end + 20)[0] == len(raw), 'apk_directory_wrong')
        central = struct.unpack_from('<I', raw, end + 16)[0]
        if unsigned:
            need(raw[max(0, central - 16):central] != b'APK Sig Block 42', 'apk_already_signed')
    except (zipfile.BadZipFile, OSError, ValueError, RuntimeError) as error:
        if isinstance(error, SigningRejected): raise
        raise SigningRejected('apk_container_wrong') from None
    return digest(canonical(sorted(rows, key=lambda row: row['path'])))


def manifest(xml, flavor):
    need(b'<!DOCTYPE' not in xml and b'<!ENTITY' not in xml, 'apk_manifest_wrong')
    tree = ET.fromstring(xml)
    apps = tree.findall('application'); sdk = tree.find('uses-sdk')
    need(tree.tag == 'manifest' and tree.get('package') == PACKAGES[flavor] and
         tree.get(A + 'versionCode') == str(VERSION_CODE) and tree.get(A + 'versionCodeMajor', '0') == '0' and
         len(apps) == 1 and not tree.findall('instrumentation') and sdk is not None and
         sdk.get(A + 'minSdkVersion') == '26' and sdk.get(A + 'targetSdkVersion') == '36', 'apk_manifest_identity_wrong')
    need(not manifest_failures(xml.decode('utf8'), flavor, release=True, strict_components=True), 'apk_release_boundary_wrong')
    return {'package': PACKAGES[flavor], 'version_code': VERSION_CODE, 'version_name': tree.get(A + 'versionName'),
            'min_sdk': 26, 'target_sdk': 36, 'debuggable': False, 'test_only': False}


def write_private(path, raw):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(raw); stream.flush(); os.fsync(stream.fileno())


def signing_command(tool, store, password, key_password, alias, pending, aligned):
    command = [tool, 'sign', '--ks', store['path'], '--ks-type', 'PKCS12',
               '--ks-key-alias', alias, '--ks-pass', 'file:' + str(password['path'])]
    # PasswordRetriever caches an opened password file. Supplying its same
    # one-line path twice consumes a second line and fails at EOF. PKCS12's
    # default key password is the store password; let apksigner reuse it.
    if key_password is not None and key_password['path'] != password['path']:
        command += ['--key-pass', 'file:' + str(key_password['path'])]
    return command + ['--min-sdk-version', '26', '--v1-signing-enabled', 'false',
                      '--v2-signing-enabled', 'true', '--v3-signing-enabled', 'true', '--v4-signing-enabled', 'false',
                      '--out', pending, aligned]


def sign(args):
    binding = load_evidence(args.evidence, args.evidence_sha256, args.alias, args.certificate_sha256)
    output = Path(args.output).absolute()
    need(output.resolve() == output and not output.exists() and output.parent.is_dir() and
         not any(p.is_symlink() for p in output.parents) and
         not any(output.is_relative_to(p) for p in (pipeline.ROOT, pipeline.OVERLAY / 'upstream/collect')), 'fresh_output_required')
    store = private_input(args.keystore, 16 * 1024 * 1024)
    password = private_input(args.store_password_file, 4096, password=True)
    key_password = private_input(args.key_password_file, 4096, password=True) if args.key_password_file is not None else None
    if key_password is not None and key_password['path'] == password['path']:
        key_password = None
    credentials = [store, password] + ([key_password] if key_password is not None else [])
    selected, tool_hashes, env = tools(args.sdk, args.java_home)
    cert = run_tool([selected['keytool'], '-exportcert', '-keystore', store['path'], '-storetype', 'PKCS12',
                     '-alias', binding['alias'], '-storepass:file', password['path']], env)
    need(digest(cert) == binding['certificate_sha256'], 'keystore_certificate_mismatch')
    inspected = {}
    # Inspect original APKs read-only before creating any output or signing.
    for flavor, row in binding['artifacts'].items():
        content = payload(row['raw'], flavor, unsigned=True)
        xml = run_tool([selected['apkanalyzer'], 'manifest', 'print', row['source_path']], env)
        inspected[flavor] = {'payload_sha256': content, 'manifest': manifest(xml, flavor)}
    stable_evidence(binding); stable_credentials(credentials)
    receipt = {'format': 'collect.burimunsi.signed-testing-candidate.v1', 'status': 'PLAN',
        'purpose': 'testing-candidate-only', 'production_authorized': False, 'distribution_authorized': False,
        'signing_executed': False, 'signing_attempted_flavors': [], 'signing_tool_completed_flavors': [],
        'source_sha256': binding['source_sha256'],
        'evidence_sha256': binding['evidence_sha256'], 'profile_sha256': binding['profile_sha256'],
        'signing_profile_sha256': binding['signing_profile_sha256'], 'build_command_sha256': binding['command_sha256'],
        'alias': binding['alias'], 'certificate_sha256': binding['certificate_sha256'],
        'key_password_mode': 'separate-protected-file' if key_password is not None else 'store-password-default',
        'sdk_build_tools': '36.0.0', 'tool_sha256': tool_hashes, 'artifacts': []}
    if not args.execute:
        return receipt
    output.mkdir(mode=0o700); work = output / 'work'; work.mkdir(mode=0o700)
    try:
        for flavor in PACKAGES:
            stable_evidence(binding); stable_credentials(credentials)
            row = binding['artifacts'][flavor]
            source = work / (flavor + '-unsigned.apk'); aligned = work / (flavor + '-aligned.apk')
            pending = work / (flavor + '-signed.apk')
            write_private(source, row['raw'])
            run_tool([selected['zipalign'], '-P', '16', '4', source, aligned], env)
            aligned_raw = readiness._physical(aligned, 64 * 1024 * 1024)
            need(payload(aligned_raw, flavor, unsigned=True) == inspected[flavor]['payload_sha256'], 'alignment_changed_payload')
            stable_credentials(credentials)
            receipt['signing_attempted_flavors'].append(flavor)
            run_tool(signing_command(selected['apksigner'], store, password, key_password,
                                     binding['alias'], pending, aligned), env)
            receipt['signing_executed'] = True
            receipt['signing_tool_completed_flavors'].append(flavor)
            verified = run_tool([selected['apksigner'], 'verify', '--verbose', '--print-certs', '-Werr', pending], env).decode('utf8')
            certificates = re.findall(r'Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', verified)
            need(len(certificates) == 1 and certificates[0].lower() == binding['certificate_sha256'] and
                 re.search(r'Verified using v2 scheme[^\n]*:\s*true', verified), 'signed_certificate_or_scheme_wrong')
            run_tool([selected['zipalign'], '-c', '-P', '16', '4', pending], env)
            signed = readiness._physical(pending, 64 * 1024 * 1024)
            need(digest(signed) != digest(aligned_raw) and
                 payload(signed, flavor, unsigned=False) == inspected[flavor]['payload_sha256'], 'signing_changed_payload')
            xml = run_tool([selected['apkanalyzer'], 'manifest', 'print', pending], env)
            need(manifest(xml, flavor) == inspected[flavor]['manifest'], 'signed_manifest_changed')
            stable_credentials(credentials)
            target = output / (flavor + '-testing-candidate.apk')
            write_private(target, signed)
            need(pipeline.sha(target) == digest(signed) and stat.S_IMODE(target.stat().st_mode) == 0o600, 'signed_output_changed')
            receipt['artifacts'].append({'flavor': flavor, **inspected[flavor]['manifest'],
                'path': target.name, 'unsigned_sha256': row['sha256'], 'aligned_sha256': digest(aligned_raw),
                'sha256': digest(signed), 'payload_sha256': inspected[flavor]['payload_sha256'],
                'certificate_sha256': binding['certificate_sha256'], 'signature_verified': True})
        stable_evidence(binding)
        receipt.update(status='PASS', signing_executed=True, completed_at=dt.datetime.now(dt.timezone.utc).isoformat())
        write_private(output / 'result.json', canonical(receipt) + b'\n')
        return receipt
    except Exception:
        receipt.update(status='FAIL', error_code='candidate_signing_incomplete',
                       signing_outcome_unconfirmed=receipt['signing_attempted_flavors'] != receipt['signing_tool_completed_flavors'])
        try: write_private(output / 'result.json', canonical(receipt) + b'\n')
        except OSError: pass
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('evidence', 'sdk', 'java-home', 'keystore', 'store-password-file', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--key-password-file', type=Path,
                        help='Optional separate protected password file; omitted/same-path uses the PKCS12 store password')
    for name in ('evidence-sha256', 'alias', 'certificate-sha256'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(sign(args), sort_keys=True)); return 0
    except Exception as error:
        code = str(error) if isinstance(error, SigningRejected) and re.fullmatch(r'[a-z_]+', str(error)) else 'candidate_signing_refused'
        print(json.dumps({'status': 'FAIL', 'error_code': code, 'production_authorized': False,
                          'distribution_authorized': False})); return 2


if __name__ == '__main__':
    raise SystemExit(main())
