#!/usr/bin/env python3
"""Bounded, read-only bytes from one local evaluation AAB; no release approval.

Uses standard zipfile without extraction, external tools or package mapping.
Root supplies existing source/SDK/lock/package/graph/build evidence bindings.
"""
from __future__ import annotations

import argparse
import codecs
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import sys
import time
import zipfile
import zlib

MIB = 1024 ** 2
MAX_ARCHIVE = 1024 * MIB
MAX_INPUT = 1024 * MIB
MAX_MEMBERS = 50000
MAX_CENTRAL = 32 * MIB
MAX_MEMBER = 1024 * MIB
MAX_EXPANDED = 4 * 1024 * MIB
MAX_NOTICES = 64 * MIB
FLUTTER = 'base/assets/flutter_assets/'
MARKER = 'base/assets/collect-local-unsigned-qa.json'
EXPECTED_MARKER = {'kind': 'local_unsigned_native_qa', 'store_acceptance': False,
                   'provider_configuration': False, 'signing': False}
EXPECTED_MARKER_BYTES = b'{"kind":"local_unsigned_native_qa","store_acceptance":false,"provider_configuration":false,"signing":false}\n'


class ReadbackError(ValueError):
    pass


def require(value, code):
    if not value:
        raise ReadbackError(code)


def deadline(until):
    require(time.monotonic() < until, 'reader_deadline')


def identity(row):
    return (row.st_dev, row.st_ino, row.st_size, row.st_mode, row.st_nlink,
            row.st_mtime_ns, row.st_ctime_ns)


def open_regular(path, limit):
    path = Path(path)
    require(path.is_absolute() and path.resolve(strict=True) == path, 'canonical_regular_path_required')
    before = path.lstat()
    require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1
            and not before.st_mode & (stat.S_ISUID | stat.S_ISGID)
            and 0 <= before.st_size <= limit, 'regular_input_bound_or_type')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    stream = os.fdopen(fd, 'rb')
    if identity(os.fstat(fd)) != identity(before):
        stream.close()
        raise ReadbackError('input_changed_before_open')
    return path, before, stream


def file_hash(stream, until, retain=False, limit=MAX_INPUT):
    stream.seek(0)
    digest = hashlib.sha256()
    body = bytearray() if retain else None
    for chunk in iter(lambda: stream.read(MIB), b''):
        deadline(until)
        require(stream.tell() <= limit, 'actual_regular_input_byte_bound')
        digest.update(chunk)
        if body is not None:
            body.extend(chunk)
    return digest.hexdigest(), bytes(body) if body is not None else None


def stable_file(path, expected, until, limit=MAX_INPUT, retain=False):
    require(isinstance(expected, str) and re.fullmatch('[a-f0-9]{64}', expected), 'invalid_expected_sha256')
    path, before, stream = open_regular(path, limit)
    with stream:
        digest, body = file_hash(stream, until, retain, limit)
        require(identity(os.fstat(stream.fileno())) == identity(before)
                and identity(path.lstat()) == identity(before)
                and path.resolve(strict=True) == path, 'bound_input_changed')
    require(digest == expected, 'bound_input_sha256_mismatch')
    return {'path': str(path), 'sha256': digest, 'bytes': before.st_size,
            'identity': list(identity(before))}, body


def zip_envelope(stream, archive_bytes, until):
    # Bound central-directory allocation before ZipFile parses it. This utility
    # handles a single-disk ordinary AAB ZIP, not ZIP64/multi-volume archives.
    deadline(until)
    stream.seek(max(0, archive_bytes - 65557))
    tail = stream.read(65557)
    position = tail.rfind(b'PK\x05\x06')
    require(position >= 0 and len(tail) - position >= 22, 'zip_end_record_missing')
    _, disk, central_disk, disk_count, count, central_size, offset, comment = struct.unpack(
        '<4s4H2LH', tail[position:position + 22])
    absolute = archive_bytes - len(tail) + position
    require(position + 22 + comment == len(tail) and disk == central_disk == 0
            and disk_count == count and 0 < count <= MAX_MEMBERS
            and central_size <= MAX_CENTRAL and offset + central_size == absolute,
            'zip_envelope_unsupported_or_bound')
    return count


def member_paths(infos, until):
    seen = {}
    for item in infos:
        deadline(until)
        name = item.filename
        key = name[:-1] if item.is_dir() else name
        path = PurePosixPath(key)
        mode = item.external_attr >> 16
        require(item.orig_filename == name and 0 < len(name) <= 4096
                and not any(ord(c) < 32 or ord(c) == 127 for c in name)
                and '\\' not in name and not path.is_absolute()
                and bool(path.parts) and path.as_posix() == key and all(p not in ('.', '..') for p in path.parts)
                and not re.match(r'^[A-Za-z]:', key), 'unsafe_zip_member_path')
        require(key not in seen, 'duplicate_zip_member')
        require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR)
                and not item.flag_bits & 1 and item.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED),
                'unsupported_zip_member_type_or_encoding')
        require(stat.S_IFMT(mode) != stat.S_IFDIR or item.is_dir(), 'directory_mode_path_mismatch')
        require(not item.is_dir() or item.file_size == 0, 'nonempty_zip_directory')
        require(0 <= item.file_size <= MAX_MEMBER, 'zip_member_byte_bound')
        seen[key] = item.is_dir()
    for key in seen:
        deadline(until)
        require(all(seen.get(parent.as_posix(), True) for parent in PurePosixPath(key).parents),
                'file_used_as_zip_directory')
    require(sum(item.file_size for item in infos) <= MAX_EXPANDED, 'zip_total_expansion_bound')


def notice_digest(payload, compressed, until):
    digest, count = hashlib.sha256(), 0
    utf8 = codecs.getincrementaldecoder('utf-8')('strict')
    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS) if compressed else None
    for position in range(0, len(payload), 65536):
        pending = payload[position:position + 65536]
        while pending:
            deadline(until)
            chunk = decoder.decompress(pending, MIB) if decoder else pending
            pending = decoder.unconsumed_tail if decoder else b''
            count += len(chunk)
            require(count <= MAX_NOTICES, 'decoded_notices_byte_bound')
            utf8.decode(chunk)
            digest.update(chunk)
            if decoder:
                require(not decoder.unused_data, 'notices_trailing_or_concatenated_gzip')
    if decoder:
        require(decoder.eof and not decoder.unconsumed_tail, 'notices_gzip_incomplete')
    utf8.decode(b'', final=True)
    return {'decoded_sha256': digest.hexdigest(), 'decoded_bytes': count,
            'format': 'gzip' if compressed else 'UTF-8 text', 'decoded_UTF8_valid': True,
            'license_completeness_or_approval_verified': False}


def inspect(aab, aab_sha256, bindings_path, bindings_sha256, seconds=120):
    require(isinstance(seconds, (int, float)) and 0 < seconds <= 600, 'finite_reader_deadline_required')
    until = time.monotonic() + seconds
    binding_file, raw = stable_file(bindings_path, bindings_sha256, until, MIB, True)
    bindings = json.loads(raw)
    require(isinstance(bindings, dict) and bindings.get('schema_version') == 1
            and set(bindings) <= {'schema_version', 'inputs', 'fonts'}, 'bindings_schema')
    inputs, fonts = bindings.get('inputs'), bindings.get('fonts', [])
    require(isinstance(inputs, list) and 0 < len(inputs) <= 128
            and isinstance(fonts, list) and len(fonts) <= 128, 'bindings_count')
    observed, expected_fonts, labels = [], [], set()
    for spec in [*inputs, *fonts]:
        require(isinstance(spec, dict) and isinstance(spec.get('label'), str)
                and re.fullmatch('[A-Za-z0-9_.:-]{1,128}', spec['label'])
                and spec['label'] not in labels, 'binding_label')
        require(isinstance(spec.get('role', 'font'), str)
                and re.fullmatch('[A-Za-z0-9_.:-]{1,128}', spec.get('role', 'font')), 'binding_role_label')
        labels.add(spec['label'])
        row, _ = stable_file(spec['path'], spec['sha256'], until)
        row.update(label=spec['label'], role=spec.get('role', 'font'))
        observed.append(row)
        if spec in fonts:
            asset = spec.get('asset')
            require(isinstance(asset, str) and asset.startswith('assets/')
                    and PurePosixPath(asset).as_posix() == asset
                    and '..' not in PurePosixPath(asset).parts, 'font_asset_path')
            expected_fonts.append({'label': spec['label'], 'family': spec.get('family'),
                                   'member': FLUTTER + asset, 'source_sha256': row['sha256']})
    path, before, stream = open_regular(aab, MAX_ARCHIVE)
    members, selected = [], {}
    with stream:
        before_sha, _ = file_hash(stream, until)
        require(before_sha == aab_sha256, 'aab_sha256_mismatch')
        count = zip_envelope(stream, before.st_size, until)
        with zipfile.ZipFile(stream) as archive:
            infos = archive.infolist()
            require(len(infos) == count, 'zip_member_count_mismatch')
            member_paths(infos, until)
            expanded = 0
            for item in infos:
                deadline(until)
                capture_limit = (16384 if item.filename == MARKER else MIB
                                 if item.filename == FLUTTER + 'FontManifest.json' else 32 * MIB
                                 if item.filename in (FLUTTER + 'NOTICES', FLUTTER + 'NOTICES.Z') else 0)
                require(not capture_limit or item.file_size <= capture_limit, 'selected_payload_byte_bound')
                payload, digest, crc, size = bytearray(), hashlib.sha256(), 0, 0
                with archive.open(item) as member:
                    for chunk in iter(lambda: member.read(MIB), b''):
                        deadline(until)
                        size += len(chunk)
                        expanded += len(chunk)
                        require(size <= item.file_size and expanded <= MAX_EXPANDED, 'actual_zip_expansion_bound')
                        digest.update(chunk)
                        crc = zlib.crc32(chunk, crc)
                        if capture_limit:
                            payload.extend(chunk)
                require(size == item.file_size and crc & 0xffffffff == item.CRC, 'zip_member_size_or_crc_mismatch')
                members.append({'path': item.filename, 'bytes': size, 'compressed_bytes': item.compress_size,
                                'sha256': digest.hexdigest(), 'crc32': f'{crc & 0xffffffff:08x}',
                                'directory': item.is_dir(), 'compression': item.compress_type,
                                'unix_mode': oct(item.external_attr >> 16), 'create_system': item.create_system})
                if capture_limit:
                    selected[item.filename] = bytes(payload)
        after_sha, _ = file_hash(stream, until)
        require(after_sha == before_sha and identity(os.fstat(stream.fileno())) == identity(before)
                and identity(path.lstat()) == identity(before)
                and path.resolve(strict=True) == path, 'aab_changed_during_readback')
    require(selected.get(MARKER) == EXPECTED_MARKER_BYTES, 'local_QA_marker_missing_or_wrong')
    by_path = {row['path']: row for row in members}
    for row in expected_fonts:
        payload = by_path.get(row['member'])
        row.update(present=payload is not None, packaged_sha256=payload['sha256'] if payload else None,
                   source_bytes_match=payload is not None and payload['sha256'] == row['source_sha256'])
    notices = [{**by_path[name], **notice_digest(body, name.endswith('.Z'), until)}
               for name, body in selected.items() if name in (FLUTTER + 'NOTICES', FLUTTER + 'NOTICES.Z')]
    font_manifest = json.loads(selected[FLUTTER + 'FontManifest.json']) if FLUTTER + 'FontManifest.json' in selected else None
    for row in observed:
        after, _ = stable_file(row['path'], row['sha256'], until)
        require(after['identity'] == row['identity'], 'bound_input_identity_changed')
    binding_after, _ = stable_file(bindings_path, bindings_sha256, until, MIB)
    require(binding_after['identity'] == binding_file['identity'], 'binding_manifest_changed')
    deadline(until)
    return {'status': 'pass', 'scope': 'Complete local unsigned-evaluation AAB ZIP byte readback only',
            'aab': {'path': str(path), 'sha256_before': before_sha, 'sha256_after': after_sha,
                    'bytes': before.st_size, 'identity': list(identity(before))},
            'bindings_manifest': binding_file, 'bound_inputs_before_and_after': observed,
            'binding_roles_present': sorted({str(row['role']) for row in observed}),
            'member_count': len(members), 'expanded_bytes': sum(row['bytes'] for row in members),
            'members': members, 'qa_marker': {'path': MARKER, 'payload': EXPECTED_MARKER, 'exact_match': True},
            'native_libraries': [row for row in members if re.fullmatch(r'[^/]+/lib/[^/]+/[^/]+\.so', row['path'])],
            'flutter_libraries': [row for row in members if re.fullmatch(r'[^/]+/lib/[^/]+/lib(?:app|flutter)\.so', row['path'])],
            'font_payloads': [row for row in members if row['path'].startswith(FLUTTER) and row['path'].lower().endswith(('.ttf', '.otf', '.woff', '.woff2'))],
            'declared_font_source_comparisons': expected_fonts, 'font_manifest': font_manifest,
            'compiled_notices': notices,
            'signature_metadata_members': [row['path'] for row in members if row['path'].startswith('META-INF/') and row['path'].upper().endswith(('.SF', '.RSA', '.DSA', '.EC'))],
            'signature_verified': False, 'unsignedness_verified': False, 'package_level_SBOM_complete': False,
            'license_or_font_rights_approval': False, 'advisory_acceptance': False,
            'device_or_store_acceptance': False, 'ARC09_closed': False,
            'network_calls': 0, 'archive_extracted': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('--aab', type=Path, required=True)
    parser.add_argument('--aab-sha256', required=True)
    parser.add_argument('--bindings', type=Path, required=True)
    parser.add_argument('--bindings-sha256', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout-seconds', type=float, default=120)
    args = parser.parse_args()
    require(args.output.is_absolute() and args.output.parent.resolve(strict=True) == args.output.parent,
            'canonical_existing_output_parent_required')
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        result = inspect(args.aab, args.aab_sha256, args.bindings, args.bindings_sha256, args.timeout_seconds)
    except Exception as error:
        result = {'status': 'fail', 'error_type': type(error).__name__,
                  'error': str(error) if isinstance(error, ReadbackError) else 'input_or_archive_decode_error',
                  'ARC09_closed': False, 'archive_extracted': False, 'network_calls': 0}
    with os.fdopen(fd, 'w') as output:
        json.dump(result, output, indent=2)
        output.write('\n')
        output.flush()
        os.fsync(output.fileno())
    print(json.dumps({key: result.get(key) for key in ('status', 'member_count', 'error', 'ARC09_closed')}))
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
