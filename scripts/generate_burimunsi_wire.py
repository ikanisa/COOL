#!/usr/bin/env python3
"""Compile product-owned JSON Schema documents into JS/Kotlin resources. No runtime downloads."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / 'contracts/burimunsi-api'
SERVER = 'supabase/functions/_shared/domain/burimunsi'
ANDROID = 'native/burimunsi/app/src/main/kotlin/rw/ikanisa/wire'
KEYS = {
    '$schema', '$id', '$defs', '$ref', 'type', 'properties', 'required', 'additionalProperties',
    'items', 'minItems', 'maxItems', 'uniqueItems', 'minLength', 'maxLength', 'pattern',
    'format', 'minimum', 'maximum', 'enum', 'const', 'anyOf', 'x-code',
}


def validate_schema(schema):
    if 'const' in schema and 'type' not in schema:
        raise ValueError('Wire constants require an explicit type in both validators')
    for key in schema:
        if key not in KEYS:
            raise ValueError('unsupported schema keyword: ' + key)

    for key in ('properties', '$defs'):
        for child in schema.get(key, {}).values():
            validate_schema(child)
    if 'items' in schema:
        validate_schema(schema['items'])
    if 'anyOf' in schema:
        choices = schema['anyOf']
        if len(choices) != 2 or choices[1] != {'type': 'null'}:
            raise ValueError('anyOf requires one schema followed by the null type')
        validate_schema(choices[0])


def compact(value):
    return json.dumps(value, separators=(',', ':'))


def kotlin_string(value):
    return json.dumps(value, ensure_ascii=True).replace('$', '\\$')


def operator_access_outputs(definitions, policy):
    capabilities = definitions['profile']['properties']['capabilities']['items']['enum']
    for name in ('staffRow', 'staffCreate.request', 'staffUpdate.request'):
        if definitions[name]['properties']['capabilities']['items']['enum'] != capabilities:
            raise ValueError(f'{name} disagrees with the profile capability schema')
    staff = policy['staff']
    classified = staff + policy['adminOnly']
    if (len(set(classified)) != len(classified) or len(set(capabilities)) != len(capabilities)
            or set(classified) != set(capabilities) or policy['required'] not in staff):
        raise ValueError('Every wire capability needs exactly one role classification and both roles need the required capability')

    header = '// Generated from contracts/burimunsi-api/{schema,operator-access}.json.\n'
    required = json.dumps(policy['required'])
    constants = (header
        + f'export const CAPABILITIES = Object.freeze({json.dumps(capabilities)});\n'
        + f'export const STAFF_CAPABILITIES = Object.freeze({json.dumps(staff)});\n'
        + f'export const REQUIRED_CAPABILITY = {required};\n')
    types = header + 'export type OperatorCapability = ' + ' | '.join(map(json.dumps, capabilities)) + ';\n'
    return {
        f'{SERVER}/wire/operator-capabilities.generated.mjs': constants,
        f'{SERVER}/operator-access.d.mts': types + f'export const REQUIRED_CAPABILITY: {required};\n'
            + 'export const CAPABILITIES: readonly OperatorCapability[];\n'
            + 'export function roleAllowsCapability(role: unknown, capability: unknown): boolean;\n'
            + 'export function validOperatorCapabilities(role: unknown, values: unknown): values is OperatorCapability[];\n',
    }


def kotlin_schema(header, definitions, profile):
    lines = [
        'package rw.ikanisa.wire', '', header, 'object BuriMunsiSchemas {',
        f'  const val VERSION = {kotlin_string(profile["contractVersion"])}',
        '  val definitions: Map<String, Any?> by lazy { linkedMapOf(',
    ]
    for name, definition in definitions.items():
        value = kotlin_string(compact(definition))
        lines.append(f'    {kotlin_string(name)} to StrictJson.parse({value}),')
    lines.append('  ) }')

    if profile['routes']:
        routes = ['listOf(' + ','.join(map(kotlin_string, row)) + ')' for row in profile['routes']]
        lines.append('  val routes = listOf(' + ','.join(routes) + ')')
    else:
        lines.append('  val routes: List<List<String>> = emptyList()')
    lines.extend(['  val contract by lazy { WireContract("burimunsi", VERSION, definitions, routes) }', '}', ''])
    return '\n'.join(lines)


def outputs():
    source = (CONTRACT / 'schema.json').read_bytes()
    schema = json.loads(source)
    validate_schema(schema)
    definitions = schema['$defs']
    profile = json.loads((CONTRACT / 'profile.json').read_text())
    policy = json.loads((CONTRACT / 'operator-access.json').read_text())
    header = '// Generated from contracts/burimunsi-api/schema.json; schema SHA-256 ' + hashlib.sha256(source).hexdigest()
    return {
        **operator_access_outputs(definitions, policy),
        f'{SERVER}/wire/burimunsi.generated.mjs':
            f'{header}\nexport const profile={compact(profile)};\nexport const defs={compact(definitions)};\n',
        f'{ANDROID}/BuriMunsiSchemas.kt': kotlin_schema(header, definitions, profile),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    drift = []
    for name, value in outputs().items():
        path = ROOT / name
        if args.check:
            if not path.is_file() or path.read_text() != value:
                drift.append(name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(value)
    if drift:
        print('GENERATED_DRIFT: ' + ', '.join(drift))
        return 1
    print('PASS generated schemas are synchronized' if args.check else 'Generated separate JS/Kotlin schemas')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
