#!/usr/bin/env python3
"""Exercise actual Android manifest encodings and artifact/identity failures."""
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile

sys.dont_write_bytecode = True
HELPER = Path(__file__).resolve().parents[1] / 'qa/native_artifact_metadata.py'
spec = importlib.util.spec_from_file_location('native_metadata', HELPER)
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)

ANDROID = 'http://schemas.android.com/apk/res/android'
IDS = {'versionCode': 0x0101021b, 'versionName': 0x0101021c}
NONE = 0xffffffff


def varint(value):
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def message(number, value):
    return varint(number << 3 | 2) + varint(len(value)) + value


def scalar(number, value):
    return varint(number << 3) + varint(value)


def aab_manifest(package='app.cool.mobile', name='1.2.4', code=23,
                 duplicate=False, wrong_id=False, conflicting_code=False,
                 unresolved=False, uncompiled_code=False):
    def attr(ns, key, value, resource=0, compiled=b''):
        return ((message(1, ns.encode()) if ns else b'') + message(2, key.encode())
                + message(3, value.encode()) + (scalar(5, resource) if resource else b'')
                + (message(6, compiled) if compiled else b''))
    compiled = message(7, scalar(6, code + (1 if conflicting_code else 0)))
    if unresolved:
        compiled = message(1, scalar(2, 0x7f010001))
    if uncompiled_code:
        compiled = b''
    values = [attr('', 'package', package),
              attr(ANDROID, 'versionCode', str(code), IDS['versionCode'], compiled),
              attr(ANDROID, 'versionName', name, 1 if wrong_id else IDS['versionName'])]
    if duplicate:
        values.append(values[-1])
    return message(1, message(3, b'manifest') + b''.join(message(4, value) for value in values))


def _length(value, utf8):
    if utf8:
        return bytes([value]) if value < 128 else bytes([(value >> 8) | 128, value & 255])
    return struct.pack('<H', value) if value < 32768 else struct.pack('<HH', (value >> 16) | 32768, value & 65535)


def apk_manifest(package='app.cool.mobile', name='1.2.4', code=23,
                 utf8=True, duplicate=False, wrong_id=False,
                 conflicting_code=False, unresolved=False, string_code=False):
    strings = ['manifest', 'package', ANDROID, 'versionCode', 'versionName',
               package, name, str(code), 'unused accented é and astral 🌍']
    data, offsets = bytearray(), []
    for value in strings:
        offsets.append(len(data))
        units = len(value.encode('utf-16-le')) // 2
        encoded = value.encode('utf-8' if utf8 else 'utf-16-le')
        data.extend(_length(units, utf8))
        if utf8:
            data.extend(_length(len(encoded), True))
        data.extend(encoded + bytes(1 if utf8 else 2))
    data.extend(bytes(-len(data) % 4))
    start = 28 + 4 * len(strings)
    pool = (struct.pack('<HHIIIIII', 1, 28, start + len(data), len(strings), 0,
                        0x100 if utf8 else 0, start, 0)
            + struct.pack('<' + 'I' * len(offsets), *offsets) + data)
    resources = [0, 0, 0, IDS['versionCode'], 1 if wrong_id else IDS['versionName']]
    resource_map = struct.pack('<HHI', 0x180, 8, 8 + 4 * len(resources)) + struct.pack('<' + 'I' * len(resources), *resources)

    def attr(ns, key, raw, kind, value):
        return struct.pack('<IIIHBBI', ns, key, raw, 8, 0, kind, value)
    attributes = [attr(NONE, 1, 5, 3, 5),
                  attr(2, 3, 7, 3 if string_code else 0x10, 7 if string_code else code + (1 if conflicting_code else 0)),
                  attr(2, 4, 6, 1 if unresolved else 3, 0x7f010001 if unresolved else 6)]
    if duplicate:
        attributes.append(attributes[-1])
    body = (struct.pack('<IIHHHHHH', NONE, 0, 20, 20, len(attributes), 0, 0, 0)
            + b''.join(attributes))
    root = struct.pack('<HHIII', 0x102, 16, 16 + len(body), 1, NONE) + body
    end = struct.pack('<HHIIIII', 0x103, 16, 24, 1, NONE, NONE, 0)
    body = pool + resource_map + root + end
    return struct.pack('<HHI', 3, 8, 8 + len(body)) + body


def archive(path, kind, *, padding=0, duplicate=False, alias=False, extra=(), **kwargs):
    target = 'AndroidManifest.xml' if kind == 'apk' else 'base/manifest/AndroidManifest.xml'
    manifest = apk_manifest(**kwargs) if kind == 'apk' else aab_manifest(**kwargs)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with warnings.catch_warnings():
        warnings.simplefilter('ignore', UserWarning)
        with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_STORED) as z:
            z.writestr(target, manifest)
            if duplicate:
                z.writestr(target, manifest)
            if alias:
                z.writestr(target.lower(), manifest)
            if padding:
                z.writestr('synthetic-padding.bin', b'0' * padding)
            for name, data in extra:
                z.writestr(name, data)
    return path


def provenance_fixtures(root, name='1.0.0', code=1, package='app.cool.mobile'):
    root = Path(root)
    archive(root/'build/app/outputs/flutter-apk/app-production-release.apk', 'apk',
            name=name, code=int(code), package=package, padding=1_000_001)
    archive(root/'build/app/outputs/bundle/productionRelease/app-production-release.aab', 'aab',
            name=name, code=int(code), package=package, padding=1_000_001)


class NativeArtifactMetadataTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.pubspec = self.root/'pubspec.yaml'
        self.pubspec.write_text('name: synthetic_fixture\nversion: 1.2.4+23\n')

    def validate(self, kind, **kwargs):
        p = archive(self.root/('artifact.'+kind), kind, **kwargs)
        return metadata.validate_artifact(p, kind, self.pubspec, 'app.cool.mobile')

    def test_both_real_encodings_require_actual_identity(self):
        for kind in ('apk', 'aab'):
            with self.subTest(kind=kind):
                result = self.validate(kind)
                self.assertEqual('pass', result['status'])
                self.assertEqual({'package':'app.cool.mobile', 'version_name':'1.2.4', 'version_code':23}, result['actual'])
                self.assertFalse(result['signature_or_release_approval'])
                self.assertEqual(64, len(result['manifest_sha256']))

    def test_utf16_pool_and_case_sensitive_ordinary_resources_are_valid(self):
        result = self.validate('apk', utf8=False, extra=[('res/QZ.xml', b'a'), ('res/qz.xml', b'b')])
        self.assertEqual('pass', result['status'])

    def test_each_identity_mismatch_fails_despite_matching_caller_pubspec(self):
        for kind in ('apk', 'aab'):
            for changed in ({'name':'1.0'}, {'code':1}, {'package':'app.unrelated.mobile'}):
                with self.subTest(kind=kind, changed=changed):
                    result = self.validate(kind, **changed)
                    self.assertEqual('fail', result['status'])
                    self.assertEqual('artifact_metadata_mismatch', result['error'])

    def test_exact_duplicate_and_case_alias_manifests_are_rejected(self):
        for kind in ('apk', 'aab'):
            for changed in ({'duplicate':True}, {'alias':True}):
                with self.subTest(kind=kind, changed=changed):
                    with self.assertRaises(metadata.MetadataError):
                        self.validate(kind, **changed)

    def test_duplicate_root_attributes_and_spoofed_resource_ids_fail(self):
        for reader, builder in ((metadata.read_apk_manifest, apk_manifest), (metadata.read_aab_manifest, aab_manifest)):
            for changed in ({'duplicate':True}, {'wrong_id':True}, {'conflicting_code':True}, {'unresolved':True}):
                with self.subTest(reader=reader.__name__, changed=changed):
                    with self.assertRaises(metadata.MetadataError):
                        reader(builder(**changed))

    def test_wrong_namespace_or_lookalike_framework_id_is_rejected(self):
        raw = aab_manifest().replace(ANDROID.encode(), b'x' * len(ANDROID))
        with self.assertRaises(metadata.MetadataError):
            metadata.read_aab_manifest(raw)

    def test_text_only_version_code_cannot_spoof_actual_typed_identity(self):
        with self.assertRaises(metadata.MetadataError):
            metadata.read_aab_manifest(aab_manifest(uncompiled_code=True))
        with self.assertRaises(metadata.MetadataError):
            metadata.read_apk_manifest(apk_manifest(string_code=True))

    def test_binary_chunk_truncation_header_and_string_offsets_fail(self):
        raw = apk_manifest()
        damaged = [raw[:-1], b'not XML', raw[:8]+b'\0'*4+raw[12:]]
        offset = bytearray(raw)
        struct.pack_into('<I', offset, 8+28, 0xffffff00)
        damaged.append(bytes(offset))
        for value in damaged:
            with self.subTest(bytes=len(value)):
                with self.assertRaises((metadata.MetadataError, struct.error)):
                    metadata.read_apk_manifest(value)

    def test_invalid_protobuf_truncation_duplicate_root_and_wrong_type_fail(self):
        raw = aab_manifest()
        for value in (raw[:-1], raw+raw, b'\x00', b'\x0a\xff'*10, scalar(1, 1)):
            with self.subTest(value=value[:12]):
                with self.assertRaises(metadata.MetadataError):
                    metadata.read_aab_manifest(value)

    def test_archive_path_alias_and_duplicate_nonmanifest_members_fail(self):
        for name in ('../AndroidManifest.xml', './AndroidManifest.xml', '/AndroidManifest.xml'):
            with self.subTest(name=name):
                with self.assertRaises(metadata.MetadataError):
                    self.validate('apk', extra=[(name, b'bad')])
        with self.assertRaises(metadata.MetadataError):
            self.validate('apk', extra=[('duplicate', b'a'), ('duplicate', b'b')])

    def test_oversized_manifest_and_zip64_marker_fail_before_payload_parse(self):
        p = self.root/'large.apk'
        with zipfile.ZipFile(p, 'w', compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr('AndroidManifest.xml', b'a'*(metadata.MAX_MANIFEST+1))
        with self.assertRaisesRegex(metadata.MetadataError, 'manifest_size_or_encryption_bound'):
            metadata.inspect_artifact(p, 'apk')
        p = archive(self.root/'zip64.apk', 'apk')
        raw = bytearray(p.read_bytes())
        struct.pack_into('<H', raw, len(raw)-22+10, 0xffff)
        p.write_bytes(raw)
        with self.assertRaises(metadata.MetadataError):
            metadata.inspect_artifact(p, 'apk')

    def test_symlink_and_artifact_mutation_are_rejected(self):
        p = archive(self.root/'original.apk', 'apk')
        link = self.root/'alias.apk'
        link.symlink_to(p)
        with self.assertRaises(metadata.MetadataError):
            metadata.inspect_artifact(link, 'apk')
        original = metadata.read_apk_manifest
        def mutate(raw):
            p.write_bytes(p.read_bytes()+b'changed-after-manifest-read')
            return original(raw)
        with mock.patch.object(metadata, 'read_apk_manifest', side_effect=mutate):
            with self.assertRaisesRegex(metadata.MetadataError, 'artifact_changed'):
                metadata.inspect_artifact(p, 'apk')

    def test_pubspec_missing_duplicate_nonnumeric_or_unbounded_code_is_denied(self):
        for text in ('name: sample\n', 'version: 1.2.4+23\nversion: 1.2.4+23\n',
                     'version: 1.2.4+upload\n', 'version: 1.2.4+2147483648\n'):
            self.pubspec.write_text(text)
            with self.assertRaises(metadata.MetadataError):
                metadata.pubspec_version(self.pubspec)

    def test_cli_unreadable_file_returns_fixed_failure_without_source_bytes(self):
        p = self.root/'bad.apk'
        p.write_text('PRIVATE_FIXTURE_CONTENT_MUST_NOT_LEAK')
        result = subprocess.run([sys.executable, str(HELPER), '--artifact', str(p),
            '--format', 'apk', '--pubspec', str(self.pubspec), '--package', 'app.cool.mobile'],
            capture_output=True, text=True, timeout=10)
        self.assertNotEqual(0, result.returncode)
        self.assertEqual('fail', json.loads(result.stdout)['status'])
        self.assertNotIn('PRIVATE_FIXTURE', result.stdout+result.stderr)
        self.assertNotIn('Traceback', result.stderr)


if __name__ == '__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--write-provenance-fixtures':
        provenance_fixtures(*sys.argv[2:])
    else:
        unittest.main()
