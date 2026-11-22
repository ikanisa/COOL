#!/usr/bin/env python3
"""Inspect permissions, receiver and SDK in the exact Android base bundle manifest.

The bounded native metadata reader validates the ZIP and Android protobuf
identity. This additionally inspects permission declarations and the SMS
receiver, rejects extra module manifests, and returns the inspected AAB digest
for the upload gate to compare. It does not verify signatures, runtime grants,
device behavior or Play acceptance.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys
import zipfile
import zlib

sys.dont_write_bytecode = True
import native_artifact_metadata as metadata

ANDROID_NAME_RESOURCE_ID = 16842755  # android.R.attr.name
ANDROID_IDS = {'name': ANDROID_NAME_RESOURCE_ID, 'permission': 16842758,
               'enabled': 16842766, 'exported': 16842768,
               'minSdkVersion': 16843276, 'targetSdkVersion': 16843376,
               'compileSdkVersion': 16844146}
RESTRICTED = frozenset({
    'android.permission.READ_SMS', 'android.permission.RECEIVE_SMS',
    'android.permission.SEND_SMS', 'android.permission.BROADCAST_SMS',
    'android.permission.RECEIVE_MMS', 'android.permission.RECEIVE_WAP_PUSH',
    'android.permission.BROADCAST_WAP_PUSH', 'android.permission.WRITE_SMS',
    'android.permission.READ_CELL_BROADCASTS',
    'android.permission.READ_CALL_LOG', 'android.permission.WRITE_CALL_LOG',
    'android.permission.PROCESS_OUTGOING_CALLS',
})
PERMISSION_ELEMENTS = frozenset({'uses-permission', 'uses-permission-sdk-23',
                                 'uses-permission-sdk-m'})
NAME = re.compile(r'[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+')


def element(node):
    fields = metadata._proto(node)
    value = metadata._one(fields, 1)
    metadata.require(value is not None and metadata._one(fields, 2) is None, 'manifest_element_invalid')
    fields = metadata._proto(value)
    name = metadata._text(metadata._one(fields, 3))
    namespace = metadata._text(metadata._one(fields, 2, default=b''))
    return namespace, name, fields


def children(fields):
    nodes = [(wire, value) for field, wire, value in fields if field == 5]
    metadata.require(len(nodes) <= 20000, 'manifest_element_bound')
    result = []
    for wire, value in nodes:
        metadata.require(wire == 2, 'manifest_element_invalid')
        node = metadata._proto(value)
        nested = metadata._one(node, 1)
        text = metadata._one(node, 2)
        metadata.require(not (nested is not None and text is not None), 'manifest_element_ambiguous')
        if nested is None:
            metadata.require(text is not None and metadata._text(text).strip() == '', 'manifest_element_invalid')
            continue
        result.append(element(value))
    return result


def attribute(fields, name, kind):
    """Read one framework attribute, rejecting lookalike IDs and duplicates."""
    rows = [(wire, value) for field, wire, value in fields if field == 4]
    metadata.require(len(rows) <= 4096, 'manifest_attribute_bound')
    selected = None
    seen = set()
    for wire, value in rows:
        metadata.require(wire == 2, 'manifest_attribute_invalid')
        row = metadata._proto(value)
        ns = metadata._text(metadata._one(row, 1, default=b''))
        key = metadata._text(metadata._one(row, 2))
        identity = (ns, key)
        metadata.require(identity not in seen, 'manifest_attribute_ambiguous')
        seen.add(identity)
        resource_id = metadata._one(row, 5, wire=0, default=0)
        target = identity == (metadata.ANDROID, name)
        metadata.require((resource_id == ANDROID_IDS[name]) == target, 'manifest_attribute_identity_invalid')
        if target:
            selected = row
    if selected is None:
        return None
    raw = metadata._one(selected, 3)
    compiled = metadata._one(selected, 6)
    raw = metadata._text(raw) if raw is not None else None
    if kind == 'bool':
        metadata.require(compiled is not None and metadata._proto(compiled) and raw in ('true', 'false'),
                         'manifest_boolean_invalid')
        item = metadata._proto(compiled)
        metadata.require(len(item) == 1 and item[0][0:2] == (7, 2), 'manifest_boolean_invalid')
        primitive = metadata._proto(item[0][2])
        metadata.require(len(primitive) == 1 and primitive[0][0:2] == (8, 0)
                         and primitive[0][2] in (0, 1), 'manifest_boolean_invalid')
        value = bool(primitive[0][2])
        metadata.require(raw == ('true' if value else 'false'), 'manifest_boolean_invalid')
        return value
    typed = metadata._compiled_item(compiled) if compiled is not None else None
    if kind == 'int':
        metadata.require(type(typed) is int and raw is not None and metadata._number(raw) == typed,
                         'manifest_integer_invalid')
        return typed
    metadata.require(kind == 'string' and (raw is not None or typed is not None)
                     and (raw is None or typed is None or raw == typed), 'manifest_string_invalid')
    value = typed if typed is not None else raw
    metadata.require(isinstance(value, str), 'manifest_string_invalid')
    return value


def production_runtime_from_manifest(raw):
    namespace, name, root = element(raw)
    metadata.require(namespace == '' and name == 'manifest', 'manifest_root_invalid')
    compile_sdk = attribute(root, 'compileSdkVersion', 'int')
    top = children(root)
    sdk = [fields for ns, tag, fields in top if ns == '' and tag == 'uses-sdk']
    apps = [fields for ns, tag, fields in top if ns == '' and tag == 'application']
    metadata.require(len(sdk) == 1 and len(apps) == 1, 'manifest_runtime_structure_invalid')
    min_sdk = attribute(sdk[0], 'minSdkVersion', 'int')
    target_sdk = attribute(sdk[0], 'targetSdkVersion', 'int')
    metadata.require(type(compile_sdk) is int and type(min_sdk) is int and type(target_sdk) is int
                     and 1 <= min_sdk <= target_sdk
                     and 36 <= compile_sdk <= 0x7fffffff and 36 <= target_sdk <= 0x7fffffff,
                     'manifest_sdk_invalid')
    application = apps[0]
    metadata.require(attribute(application, 'enabled', 'bool') is not False,
                     'manifest_application_disabled')
    receivers = []
    for ns, tag, fields in children(application):
        if ns == '' and tag == 'receiver':
            value = attribute(fields, 'name', 'string')
            if value in ('.receiver_sms.CollectSmsReceiver', 'app.cool.mobile.receiver_sms.CollectSmsReceiver'):
                receivers.append(fields)
    metadata.require(len(receivers) == 1, 'manifest_sms_receiver_missing_or_ambiguous')
    receiver = receivers[0]
    metadata.require(attribute(receiver, 'enabled', 'bool') is not False
                     and attribute(receiver, 'exported', 'bool') is True
                     and attribute(receiver, 'permission', 'string') == 'android.permission.BROADCAST_SMS',
                     'manifest_sms_receiver_invalid')
    matching = 0
    for ns, tag, fields in children(receiver):
        if ns != '' or tag != 'intent-filter':
            continue
        # No filter attributes, categories, or data may restrict this action.
        if any(field == 4 for field, _, _ in fields):
            continue
        actions = children(fields)
        if len(actions) != 1 or actions[0][0:2] != ('', 'action'):
            continue
        action = actions[0][2]
        if (attribute(action, 'name', 'string') == 'android.provider.Telephony.SMS_RECEIVED'
                and len([row for row in action if row[0] == 4]) == 1 and not children(action)):
            matching += 1
    metadata.require(matching == 1, 'manifest_sms_receiver_filter_invalid')
    return {'compile_sdk': compile_sdk, 'min_sdk': min_sdk, 'target_sdk': target_sdk,
            'sms_receiver': 'protected_enabled_exported_with_sms_received_filter'}


def permissions_from_manifest(raw):
    """Read direct manifest permission nodes with exact namespace and IDs."""
    node = metadata._proto(raw)
    metadata.require(metadata._one(node, 2) in (None, b''), 'manifest_root_is_text')
    root = metadata._proto(metadata._one(node, 1))
    metadata.require(metadata._one(root, 3) == b'manifest'
                     and metadata._one(root, 2, default=b'') == b'', 'manifest_root_invalid')
    children = [(wire, value) for field, wire, value in root if field == 5]
    metadata.require(len(children) <= 20000, 'manifest_element_bound')
    permissions = []
    for wire, child in children:
        metadata.require(wire == 2, 'manifest_element_invalid')
        child_node = metadata._proto(child)
        element = metadata._one(child_node, 1)
        text = metadata._one(child_node, 2)
        metadata.require(not (element is not None and text is not None), 'manifest_element_ambiguous')
        if element is None:
            metadata.require(text is not None and metadata._text(text).strip() == '',
                             'manifest_element_invalid')
            continue
        fields = metadata._proto(element)
        name = metadata._text(metadata._one(fields, 3))
        namespace = metadata._text(metadata._one(fields, 2, default=b''))
        if not name.startswith('uses-permission'):
            continue
        metadata.require(namespace == '' and name in PERMISSION_ELEMENTS,
                         'permission_element_invalid')
        attrs = [(kind, value) for field, kind, value in fields if field == 4]
        metadata.require(0 < len(attrs) <= 128 and not any(field == 5 for field, _, _ in fields),
                         'permission_element_invalid')
        names = set()
        permission = None
        for kind, value in attrs:
            metadata.require(kind == 2, 'permission_attribute_invalid')
            attr = metadata._proto(value)
            attr_ns = metadata._text(metadata._one(attr, 1, default=b''))
            attr_name = metadata._text(metadata._one(attr, 2))
            resource = metadata._one(attr, 5, wire=0, default=0)
            key = (attr_ns, attr_name)
            metadata.require(key not in names, 'permission_attribute_ambiguous')
            names.add(key)
            selected = key == (metadata.ANDROID, 'name')
            metadata.require((resource == ANDROID_NAME_RESOURCE_ID) == selected,
                             'permission_name_identity_invalid')
            if not selected:
                continue
            raw_value = metadata._one(attr, 3)
            compiled = metadata._one(attr, 6)
            text_value = metadata._text(raw_value) if raw_value is not None else None
            typed_value = metadata._compiled_item(compiled) if compiled is not None else None
            metadata.require(text_value is not None or typed_value is not None,
                             'permission_name_missing')
            metadata.require(text_value is None or typed_value is None or text_value == typed_value,
                             'permission_name_ambiguous')
            permission = typed_value if typed_value is not None else text_value
        metadata.require(isinstance(permission, str) and len(permission) <= 255
                         and NAME.fullmatch(permission) is not None, 'permission_name_invalid')
        if permission == 'android.permission.RECEIVE_SMS':
            # Conditions or SDK qualifiers can make this permission unavailable
            # even though it appears in an unqualified permission list.
            metadata.require(name == 'uses-permission' and names == {(metadata.ANDROID, 'name')},
                             'required_permission_conditional')
        permissions.append(permission)
    metadata.require(len(permissions) == len(set(permissions)), 'duplicate_permission')
    return sorted(set(permissions) & RESTRICTED)


def inspect(path, pubspec):
    path = Path(path)
    baseline = metadata.inspect_artifact(path, 'aab')
    expected = {'package': 'app.cool.mobile', **metadata.pubspec_version(pubspec)}
    metadata.require(baseline['actual'] == expected, 'artifact_identity_mismatch')
    before = path.lstat()
    metadata.require(stat.S_ISREG(before.st_mode) and not path.is_symlink(), 'artifact_not_regular')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        metadata.require(metadata._identity(os.fstat(stream.fileno())) == metadata._identity(before),
                         'artifact_changed')
        metadata._zip_preflight(stream, before.st_size)
        with zipfile.ZipFile(stream) as archive:
            module_manifests = [item.filename for item in archive.infolist()
                                if item.filename.lower().endswith('/manifest/androidmanifest.xml')]
            metadata.require(module_manifests == ['base/manifest/AndroidManifest.xml'],
                             'unexpected_bundle_module_manifest')
            raw = archive.read('base/manifest/AndroidManifest.xml')
            metadata.require(len(raw) <= metadata.MAX_MANIFEST, 'manifest_size_bound')
        restricted = permissions_from_manifest(raw)
        runtime = production_runtime_from_manifest(raw)
        stream.seek(0)
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024**2), b''):
            digest.update(block)
        metadata.require(metadata._identity(os.fstat(stream.fileno())) == metadata._identity(before)
                         and metadata._identity(path.lstat()) == metadata._identity(before)
                         and digest.hexdigest() == baseline['artifact_sha256']
                         and hashlib.sha256(raw).hexdigest() == baseline['manifest_sha256'],
                         'artifact_changed')
    metadata.require(restricted == ['android.permission.RECEIVE_SMS'], 'restricted_permission_scope')
    return {'status': 'pass', 'artifact_sha256': baseline['artifact_sha256'],
            'manifest_sha256': baseline['manifest_sha256'], 'actual': baseline['actual'],
            'restricted_permissions': restricted, 'module': 'base',
            'runtime': runtime, 'signature_or_release_approval': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', required=True, type=Path)
    parser.add_argument('--pubspec', required=True, type=Path)
    args = parser.parse_args()
    try:
        result = inspect(args.artifact, args.pubspec)
    except metadata.MetadataError as error:
        result = {'status': 'fail', 'error': str(error)}
    except (OSError, ValueError, TypeError, KeyError, EOFError, struct.error, zipfile.BadZipFile,
            RuntimeError, zlib.error):
        result = {'status': 'fail', 'error': 'aab_permission_inspection_unreadable'}
    print(json.dumps(result, sort_keys=True))
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
