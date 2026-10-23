#!/usr/bin/env python3
"""Read actual Android artifact identity; never infer it from build arguments.

AAB fields follow AAPT Resources.proto XmlNode/XmlElement/XmlAttribute, Item,
Primitive and String. APK fields follow Android's ResXMLTree/StringPool chunks.
The numeric schema/resource IDs were checked against the existing AAPT schema
and android.R.attr in the qualified local Android SDK. No SDK/JAR is executed.
This verifies metadata only; signatures, complete payloads and store acceptance
remain separate checks.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import zipfile
import zlib

ANDROID = 'http://schemas.android.com/apk/res/android'
RESOURCE_IDS = {'versionCode': 16843291, 'versionName': 16843292,
                'versionCodeMajor': 16844150}
MAX_MANIFEST = 4 * 1024**2
MAX_ARTIFACT = 2 * 1024**3
NONE = 0xffffffff


class MetadataError(ValueError):
    """Fixed public failure code; never include raw artifact text or keys."""


def require(condition, code):
    if not condition:
        raise MetadataError(code)


def _identity(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


def _proto(raw):
    require(len(raw) <= MAX_MANIFEST, 'manifest_size_bound')
    offset = 0

    def integer():
        nonlocal offset
        value = 0
        for index in range(10):
            require(offset < len(raw), 'truncated_protobuf')
            byte = raw[offset]
            offset += 1
            require(index != 9 or byte <= 1, 'protobuf_integer_bound')
            value |= (byte & 127) << (7 * index)
            if not byte & 128:
                return value
        raise MetadataError('protobuf_integer_bound')

    rows = []
    while offset < len(raw):
        key = integer()
        number, wire = key >> 3, key & 7
        require(0 < number <= 536870911, 'invalid_protobuf_tag')
        if wire == 0:
            value = integer()
        elif wire in (1, 2, 5):
            size = integer() if wire == 2 else 8 if wire == 1 else 4
            require(size <= len(raw) - offset, 'truncated_protobuf')
            value = raw[offset:offset + size]
            offset += size
        else:
            raise MetadataError('unsupported_protobuf_wire')
        rows.append((number, wire, value))
        require(len(rows) <= 100000, 'protobuf_field_bound')
    return rows


def _one(rows, number, wire=2, default=None):
    values = [(kind, value) for field, kind, value in rows if field == number]
    if not values:
        return default
    require(len(values) == 1 and values[0][0] == wire,
            'duplicate_or_invalid_protobuf_scalar')
    return values[0][1]


def _text(raw):
    require(isinstance(raw, bytes) and len(raw) <= 65536, 'invalid_manifest_text')
    try:
        value = raw.decode('utf-8')
    except UnicodeError:
        raise MetadataError('invalid_manifest_text') from None
    require('\x00' not in value, 'invalid_manifest_text')
    return value


def _number(value):
    require(isinstance(value, str) and re.fullmatch(r'(?:0|[1-9][0-9]*|0[xX][0-9a-fA-F]+)', value) is not None,
            'invalid_android_version_code')
    result = int(value, 16 if value.lower().startswith('0x') else 10)
    require(0 <= result <= 0x7fffffff, 'invalid_android_version_code')
    return result


def _compiled_item(raw):
    rows = _proto(raw)
    require(len(rows) == 1, 'ambiguous_compiled_manifest_value')
    field, wire, value = rows[0]
    require(wire == 2, 'unsupported_compiled_manifest_value')
    if field in (2, 3):  # Item.str/raw_str -> String.value
        string = _proto(value)
        return _text(_one(string, 1, default=b''))
    if field == 7:  # Item.prim -> Primitive.int_decimal/hexadecimal_value
        primitive = _proto(value)
        require(len(primitive) == 1 and primitive[0][0] in (6, 7)
                and primitive[0][1] == 0, 'unsupported_compiled_manifest_value')
        result = primitive[0][2]
        require(result <= 0x7fffffff, 'invalid_android_version_code')
        return result
    raise MetadataError('unresolved_compiled_manifest_value')


def _metadata_attributes(attributes):
    """Enforce both namespace/name and framework ID, not a lookalike label."""
    found = {}
    used_resource_ids = set()
    for namespace, name, resource_id, value in attributes:
        key = namespace, name
        require(key not in found, 'duplicate_manifest_attribute')
        found[key] = value
        if resource_id in RESOURCE_IDS.values():
            require(resource_id not in used_resource_ids, 'duplicate_manifest_resource_id')
            used_resource_ids.add(resource_id)
            require(namespace == ANDROID and RESOURCE_IDS.get(name) == resource_id,
                    'manifest_resource_identity_mismatch')
        if namespace == ANDROID and name in RESOURCE_IDS:
            require(resource_id == RESOURCE_IDS[name], 'manifest_resource_identity_mismatch')
    require(('', 'package') in found and (ANDROID, 'versionName') in found
            and (ANDROID, 'versionCode') in found, 'required_manifest_metadata_missing')
    package, name = found[('', 'package')], found[(ANDROID, 'versionName')]
    require(isinstance(package, str) and len(package) <= 255
            and re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+', package) is not None,
            'invalid_android_package')
    require(isinstance(name, str) and re.fullmatch(r'[0-9][0-9A-Za-z.+-]{0,127}', name) is not None,
            'invalid_android_version_name')
    code = found[(ANDROID, 'versionCode')]
    code = _number(code) if isinstance(code, str) else code
    major = found.get((ANDROID, 'versionCodeMajor'), 0)
    major = _number(major) if isinstance(major, str) else major
    require(type(code) is int and 0 < code <= 0x7fffffff
            and type(major) is int and 0 <= major <= 0x7fffffff,
            'invalid_android_version_code')
    require(major == 0, 'unsupported_android_version_code_major')
    return {'package': package, 'version_name': name, 'version_code': code}


def read_aab_manifest(raw):
    node = _proto(raw)
    require(_one(node, 2) in (None, b''), 'manifest_root_is_text')
    element = _one(node, 1)
    require(element is not None, 'manifest_root_missing')
    root = _proto(element)
    require(_one(root, 3) == b'manifest', 'manifest_root_invalid')
    attributes = []
    for number, wire, value in root:
        if number != 4:
            continue
        require(wire == 2, 'invalid_manifest_attribute')
        row = _proto(value)
        namespace = _text(_one(row, 1, default=b''))
        name = _text(_one(row, 2))
        raw_value = _one(row, 3)
        compiled = _one(row, 6)
        resource_id = _one(row, 5, wire=0, default=0)
        # Other root attributes may legitimately reference resources. Only the
        # three identity fields need scalar interpretation here.
        selected = (namespace == '' and name == 'package') or name in RESOURCE_IDS or resource_id in RESOURCE_IDS.values()
        if selected:
            text = _text(raw_value) if raw_value is not None else None
            typed = _compiled_item(compiled) if compiled is not None else None
            require(text is not None or typed is not None, 'required_manifest_metadata_missing')
            if namespace == ANDROID and name in ('versionCode', 'versionCodeMajor'):
                require(type(typed) is int, 'uncompiled_android_version_code')
            if text is not None and typed is not None:
                require((_number(text) if isinstance(typed, int) else text) == typed,
                        'raw_compiled_manifest_value_mismatch')
            actual = typed if typed is not None else text
        else:
            actual = None
        attributes.append((namespace, name, resource_id, actual))
    return _metadata_attributes(attributes)


def _string_pool(raw, start, header, size):
    require(header >= 28 and size >= header, 'invalid_string_pool')
    count, styles, flags, strings_start, styles_start = struct.unpack_from('<IIIII', raw, start + 8)
    require(count <= 65536 and styles <= count and flags & ~0x101 == 0,
            'string_pool_bound')
    require(header + 4 * (count + styles) <= strings_start <= size,
            'invalid_string_pool_offsets')
    limit = styles_start if styles_start else size
    require(strings_start <= limit <= size and (styles == 0 or styles_start != 0),
            'invalid_string_pool_offsets')

    def length(at, utf8):
        width = 1 if utf8 else 2
        require(at + width <= start + limit, 'truncated_string_pool')
        value = raw[at] if utf8 else struct.unpack_from('<H', raw, at)[0]
        at += width
        mask = 0x80 if utf8 else 0x8000
        if value & mask:
            require(at + width <= start + limit, 'truncated_string_pool')
            next_value = raw[at] if utf8 else struct.unpack_from('<H', raw, at)[0]
            value = ((value & (mask - 1)) << (8 if utf8 else 16)) | next_value
            at += width
        return value, at

    result = []
    utf8 = bool(flags & 0x100)
    for index in range(count):
        offset = struct.unpack_from('<I', raw, start + header + 4 * index)[0]
        require(offset < limit - strings_start, 'invalid_string_pool_offsets')
        at = start + strings_start + offset
        characters, at = length(at, utf8)
        require(characters <= 32768, 'string_pool_text_bound')
        byte_count, at = length(at, True) if utf8 else (characters * 2, at)
        terminator = 1 if utf8 else 2
        require(at + byte_count + terminator <= start + limit
                and raw[at + byte_count:at + byte_count + terminator] == bytes(terminator),
                'truncated_string_pool')
        try:
            value = raw[at:at + byte_count].decode('utf-8' if utf8 else 'utf-16-le')
        except UnicodeError:
            raise MetadataError('invalid_string_pool_text') from None
        require(len(value.encode('utf-16-le')) // 2 == characters and '\x00' not in value,
                'invalid_string_pool_text')
        result.append(value)
    return result


def read_apk_manifest(raw):
    require(8 <= len(raw) <= MAX_MANIFEST, 'manifest_size_bound')
    kind, header, total = struct.unpack_from('<HHI', raw)
    require(kind == 3 and header == 8 and total == len(raw), 'invalid_binary_xml_header')
    offset = header
    strings, resources, stack, root_attributes = None, None, [], None
    root_closed = False
    chunks = 0

    def string(index, optional=False):
        if optional and index == NONE:
            return ''
        require(strings is not None and index < len(strings), 'invalid_binary_xml_string_index')
        return strings[index]

    while offset < len(raw):
        require(offset + 8 <= len(raw), 'truncated_binary_xml_chunk')
        kind, header, size = struct.unpack_from('<HHI', raw, offset)
        require(8 <= header <= size <= len(raw) - offset, 'invalid_binary_xml_chunk')
        chunks += 1
        require(chunks <= 100000, 'binary_xml_chunk_bound')
        if kind == 1:
            require(strings is None and not stack and root_attributes is None, 'duplicate_binary_xml_string_pool')
            strings = _string_pool(raw, offset, header, size)
        elif kind == 0x180:
            require(resources is None and strings is not None and root_attributes is None
                    and header == 8 and (size - header) % 4 == 0, 'invalid_binary_xml_resource_map')
            resources = list(struct.unpack_from('<' + 'I' * ((size - header) // 4), raw, offset + header))
            require(len(resources) <= len(strings), 'invalid_binary_xml_resource_map')
        elif kind in (0x100, 0x101):
            require(header == 16 and size == 24, 'invalid_binary_xml_namespace')
            prefix, uri = struct.unpack_from('<II', raw, offset + header)
            string(prefix, optional=True)
            string(uri)
        elif kind == 0x102:
            require(header == 16 and size >= 36 and strings is not None and not root_closed,
                    'invalid_binary_xml_element')
            namespace, name, attr_start, attr_size, count, id_index, class_index, style_index = struct.unpack_from('<IIHHHHHH', raw, offset + header)
            element = (string(namespace, optional=True), string(name))
            require(attr_start >= 20 and attr_size == 20 and count <= 4096
                    and max(id_index, class_index, style_index) <= count
                    and header + attr_start + count * attr_size <= size,
                    'invalid_binary_xml_attributes')
            attributes = []
            for index in range(count):
                at = offset + header + attr_start + index * attr_size
                ns, name_index, raw_index, typed_size, zero, value_type, data = struct.unpack_from('<IIIHBBI', raw, at)
                require(typed_size == 8 and zero == 0, 'invalid_binary_xml_typed_value')
                ns, attr_name = string(ns, optional=True), string(name_index)
                raw_value = None if raw_index == NONE else string(raw_index)
                resource_id = resources[name_index] if resources is not None and name_index < len(resources) else 0
                selected = not stack and ((ns == '' and attr_name == 'package')
                                          or attr_name in RESOURCE_IDS or resource_id in RESOURCE_IDS.values())
                if selected:
                    if ns == ANDROID and attr_name in ('versionCode', 'versionCodeMajor'):
                        require(value_type in (0x10, 0x11), 'noninteger_binary_xml_version_code')
                    if value_type == 3:
                        typed = string(data)
                    elif value_type in (0x10, 0x11):
                        typed = data
                    else:
                        raise MetadataError('unresolved_binary_xml_metadata')
                    if raw_value is not None:
                        require((_number(raw_value) if isinstance(typed, int) else raw_value) == typed,
                                'raw_compiled_manifest_value_mismatch')
                    actual = typed
                else:
                    actual = None
                attributes.append((ns, attr_name, resource_id, actual))
            if not stack:
                require(root_attributes is None and element == ('', 'manifest'), 'manifest_root_invalid')
                root_attributes = attributes
            stack.append(element)
            require(len(stack) <= 128, 'binary_xml_depth_bound')
        elif kind == 0x103:
            require(header == 16 and size == 24 and stack, 'invalid_binary_xml_end_element')
            ns, name = struct.unpack_from('<II', raw, offset + header)
            require(stack.pop() == (string(ns, optional=True), string(name)), 'binary_xml_element_mismatch')
            root_closed = not stack
        elif kind == 0x104:
            require(header == 16 and size >= 28 and stack, 'invalid_binary_xml_cdata')
        else:
            raise MetadataError('unsupported_binary_xml_chunk')
        offset += size
    require(root_attributes is not None and root_closed and not stack, 'incomplete_binary_xml_document')
    return _metadata_attributes(root_attributes)


def pubspec_version(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 1024**2,
            'pubspec_unreadable')
    text = path.read_text(encoding='utf-8-sig')
    declarations = re.findall(r'^version:\s*(.*?)\s*$', text, re.M)
    require(len(declarations) == 1, 'pubspec_version_ambiguous')
    value = declarations[0].split(' #', 1)[0].strip()
    if len(value) >= 2 and value[0] in "\"'" and value[-1] == value[0]:
        value = value[1:-1]
    match = re.fullmatch(r'((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?)\+([1-9][0-9]*)', value)
    require(match is not None, 'pubspec_android_version_invalid')
    code = int(match.group(2))
    require(code <= 0x7fffffff, 'pubspec_android_version_invalid')
    return {'version_name': match.group(1), 'version_code': code}


def _zip_preflight(stream, size):
    require(22 <= size <= MAX_ARTIFACT, 'artifact_size_bound')
    stream.seek(max(0, size - 65557))
    tail = stream.read(65557)
    at = tail.rfind(b'PK\x05\x06')
    require(at >= 0 and at + 22 <= len(tail), 'zip_end_record_missing')
    _, disk, central_disk, disk_count, count, central_size, central_offset, comment = struct.unpack_from('<4sHHHHIIH', tail, at)
    absolute = max(0, size - 65557) + at
    require(disk == central_disk == 0 and disk_count == count and 0 < count < 65535
            and central_size <= 32 * 1024**2 and central_offset + central_size == absolute
            and at + 22 + comment == len(tail), 'unsupported_or_ambiguous_zip_directory')


def inspect_artifact(path, artifact_format):
    path = Path(path)
    before = path.lstat()
    require(stat.S_ISREG(before.st_mode) and not path.is_symlink(), 'artifact_not_regular')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        require(_identity(os.fstat(stream.fileno())) == _identity(before), 'artifact_changed')
        _zip_preflight(stream, before.st_size)
        with zipfile.ZipFile(stream) as archive:
            seen = set()
            selected = None
            target = 'AndroidManifest.xml' if artifact_format == 'apk' else 'base/manifest/AndroidManifest.xml'
            for info in archive.infolist():
                name = info.filename
                parts = PurePosixPath(name).parts
                require(name and not name.startswith('/') and '\\' not in name
                        and '\x00' not in name and all(part not in ('.', '..') for part in parts)
                        and name.rstrip('/') == '/'.join(parts), 'noncanonical_archive_path')
                require(name not in seen, 'duplicate_archive_member')
                seen.add(name)
                # Android resource ZIP names are case-sensitive; AAPT can emit
                # distinct res/9N.png and res/9n.png. Only a lookalike of the
                # authoritative manifest name creates metadata ambiguity here.
                if name.casefold() == target.casefold():
                    require(name == target, 'ambiguous_manifest_member_name')
                require(not stat.S_ISLNK(info.external_attr >> 16), 'archive_symlink_member')
                if name == target:
                    require(not info.is_dir() and not info.flag_bits & 1
                            and info.file_size <= MAX_MANIFEST, 'manifest_size_or_encryption_bound')
                    selected = info
            require(selected is not None, 'artifact_manifest_missing')
            raw = archive.read(selected)
            require(len(raw) <= MAX_MANIFEST, 'manifest_size_bound')
        actual = read_apk_manifest(raw) if artifact_format == 'apk' else read_aab_manifest(raw)
        stream.seek(0)
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024**2), b''):
            digest.update(block)
        require(_identity(os.fstat(stream.fileno())) == _identity(before)
                and _identity(path.lstat()) == _identity(before), 'artifact_changed')
    return {'format': artifact_format, 'artifact_sha256': digest.hexdigest(),
            'artifact_bytes': before.st_size, 'manifest_member': target,
            'manifest_sha256': hashlib.sha256(raw).hexdigest(), 'actual': actual}


def validate_artifact(path, artifact_format, pubspec, package):
    require(artifact_format in ('apk', 'aab'), 'unsupported_artifact_format')
    expected = {'package': package, **pubspec_version(pubspec)}
    result = inspect_artifact(path, artifact_format)
    result.update(expected=expected, status='pass' if result['actual'] == expected else 'fail',
                  metadata_only=True, signature_or_release_approval=False)
    if result['status'] != 'pass':
        result['error'] = 'artifact_metadata_mismatch'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', required=True, type=Path)
    parser.add_argument('--format', required=True, choices=('apk', 'aab'))
    parser.add_argument('--pubspec', required=True, type=Path)
    parser.add_argument('--package', required=True)
    args = parser.parse_args()
    try:
        result = validate_artifact(args.artifact, args.format, args.pubspec, args.package)
    except MetadataError as error:
        result = {'status': 'fail', 'error': str(error)}
    except (OSError, ValueError, EOFError, struct.error, zipfile.BadZipFile, RuntimeError, zlib.error):
        result = {'status': 'fail', 'error': 'artifact_metadata_unreadable'}
    print(json.dumps(result, sort_keys=True))
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
