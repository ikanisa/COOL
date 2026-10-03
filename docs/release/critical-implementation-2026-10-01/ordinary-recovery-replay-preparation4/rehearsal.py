#!/usr/bin/env python3
"""Proposed local, synthetic-only committed backup/restore and original replay.

Execution needs a separately retained review decision bound to this script and
inputs.json. This parser cannot authenticate that decision or manufacture one.
This is a proposed fixture-only compatibility cohort, not shipping admission.
"""
from __future__ import annotations
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
DOCKER = '/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
IMAGE = 'sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a'
CATALOG = 'scripts/sql/collect_recovery_source_catalog.sql'
TRANSPORT = 'scripts/sql/receipt_transport_platform_prerequisites.sql'
FINAL_SHA = '4516b26ba34a426a2d97af40e7f2675d9a8f55de274f159b6da40fded1c0084c'
HASH = re.compile(r'[a-f0-9]{64}')
OPERATIONS = ['local_synthetic_dump', 'local_synthetic_restore', 'ordinary_original_migration_replay']
ENV = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}
LIMIT = 64 * 1024**2
SOURCE_ROLE = ['supabase_functions_admin', False, False, True, False, True,
               False, False, -1, None,
               '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a']
SOURCE_ROLE_SQL = ('create role supabase_functions_admin with nosuperuser noinherit '
                   'createrole nocreatedb login noreplication nobypassrls connection limit -1;')
GRAPHQL_ID = ['graphql_public', 'graphql', '"operationName" text, query text, variables jsonb, extensions jsonb']
GRAPHQL_FUNCTION = [*GRAPHQL_ID, 'f', 'supabase_admin', False, 'v', 'u', False, False,
    ['=X/supabase_admin', 'anon=X/supabase_admin', 'authenticated=X/supabase_admin',
     'postgres=X/supabase_admin', 'service_role=X/supabase_admin', 'supabase_admin=X/supabase_admin'],
    '03b36c9655c8688b452fba90346ce43dafa2ded68bffb9250da6c236133d467e',
    '22e0e26950cfdf51038425ad17051de3fb19bc7afa72edefda05c2da3e0d8bb2']
GRAPHQL_HOOK = ['extensions', 'grant_pg_graphql_access', '', 'f', 'supabase_admin',
    False, 'v', 'u', False, False,
    ['=X/supabase_admin', 'postgres=X*/supabase_admin', 'supabase_admin=X/supabase_admin'],
    'ad8bfb866513170056bbc1f817103be550cd62efcb589fa2a3807718efb3eb6a',
    'c3a126f9bf8958b3af27e6bec128aca58627df257259003b59511fdd3af82333']
GRAPHQL_SCHEMA = ['graphql_public', 'supabase_admin',
    ['anon=U/supabase_admin', 'authenticated=U/supabase_admin', 'postgres=U*/supabase_admin',
     'service_role=U/supabase_admin', 'supabase_admin=UC/supabase_admin']]
GRAPHQL_DEPENDENCIES = [
    ['e', 'function', 'graphql_public', 'graphql_public.graphql(pg_catalog.text,pg_catalog.text,pg_catalog.jsonb,pg_catalog.jsonb)', 'extension', None, 'pg_graphql'],
    ['n', 'function', 'graphql_public', 'graphql_public.graphql(pg_catalog.text,pg_catalog.text,pg_catalog.jsonb,pg_catalog.jsonb)', 'schema', None, 'graphql_public']]
GRAPHQL_TRIGGER = ['issue_pg_graphql_access', 'ddl_command_end', 'supabase_admin',
                   'extensions.grant_pg_graphql_access()', 'O', ['CREATE FUNCTION']]
GRAPHQL_MEMBERSHIP_SQL = 'alter extension pg_graphql add function graphql_public.graphql(text,text,jsonb,jsonb);'
COMPATIBILITY_SOURCE_SHA = '31b4d1ae357afcf8f093ce5417beb50724005734d9d1cf2f1896a777a393c404'
COMPATIBILITY_RESTORED_SHA = '4f5fb4d590dc8aa6eebd0127b5bec74098be649f3fd68cf05a0832e5c08eb90b'
CAPTURED_SOURCE_FILE_SHA = '6219ca6b2169115eb663e6497f190e9116535b01071ddb5728df5596d432ec2d'
CAPTURED_RESTORED_FILE_SHA = 'b4ae2ac11f2c6c55b0f9510a2e76ac0ba8e1d7b5f3f0a1e9741e14ef0c219846'
GRAPHQL_GRANTS_SQL = '''begin;
grant usage on schema graphql,graphql_public to postgres,anon,authenticated,service_role;
grant usage on schema graphql,graphql_public to postgres with grant option;
grant execute on function graphql._internal_resolve(text,jsonb,text,jsonb),graphql.comment_directive(text),graphql.exception(text),graphql.get_schema_version(),graphql.increment_schema_version(),graphql.resolve(text,jsonb,text,jsonb) to postgres,anon,authenticated,service_role;
grant select,update,usage on sequence graphql.seq_schema_version to postgres,anon,authenticated,service_role;
'''
TRANSPORT_INDEX_SQL = 'create index if not exists collect_receipt_http_response_id on net._http_response(id);'
NOTIFICATION_EXPRESSION = '\n    char_length(trim(title)) between 1 and 120\n    and char_length(trim(body)) between 1 and 500'
PROVIDER_EXPRESSION = "\n    provider_network is null or (\n      char_length(provider_network) between 2 and 32 and provider_network ~ '^[a-z0-9_]+$'\n    )"
CHECK_REPAIR_SQL = ('begin;\n'
    'alter table public.notification_events drop constraint notification_events_copy_length_check;\n'
    'alter table public.notification_events add constraint notification_events_copy_length_check check (' + NOTIFICATION_EXPRESSION + '\n  ) not valid;\n'
    'alter table public.provider_finality_requests drop constraint provider_finality_requests_provider_network_check;\n'
    'alter table public.provider_finality_requests add constraint provider_finality_requests_provider_network_check check (' + PROVIDER_EXPRESSION + '\n  );\ncommit;')


class Refused(ValueError):
    pass


def sha(body):
    return hashlib.sha256(body).hexdigest()


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise Refused('DUPLICATE_JSON_KEY')
        result[key] = value
    return result


def read(path, limit=LIMIT):
    path = Path(path)
    if not path.is_absolute() or '..' in path.parts or any(p.is_symlink() for p in (path, *path.parents)):
        raise Refused('ABSOLUTE_UNSUBSTITUTED_PATH_REQUIRED')
    with path.open('rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > limit:
            raise Refused('BOUNDED_SINGLE_LINK_REGULAR_INPUT_REQUIRED')
        body = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
    key = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_mode, s.st_nlink)
    if len(body) > limit or key(before) != key(after) or key(after) != key(path.lstat()):
        raise Refused('INPUT_CHANGED_DURING_READ')
    return body


def document(path):
    return json.loads(read(path), object_pairs_hook=unique)


def admit_review(value, code_sha, inputs_sha):
    expected = {'kind', 'decision', 'review_reference', 'code_sha256', 'inputs_sha256',
                'image_id', 'client_version', 'server_version_num', 'operations', 'scope'}
    if not isinstance(value, dict) or set(value) != expected:
        raise Refused('REVIEW_SCHEMA_INVALID')
    if value['kind'] != 'collect_local_synthetic_recovery_review_v1' or value['decision'] != 'admit':
        raise Refused('SEPARATE_REVIEW_DECISION_REQUIRED')
    if not re.fullmatch(r'[A-Za-z0-9._:/-]{1,160}', value['review_reference']):
        raise Refused('REVIEW_REFERENCE_REQUIRED')
    if value['code_sha256'] != code_sha or value['inputs_sha256'] != inputs_sha:
        raise Refused('REVIEW_INPUT_BINDING_CHANGED')
    if value['image_id'] != IMAGE or value['client_version'] != '17.6' or type(value['server_version_num']) is not int or value['server_version_num'] != 170006:
        raise Refused('COMPATIBILITY_OUTSIDE_PROPOSED_LOCAL_COHORT')
    if value['operations'] != OPERATIONS or value['scope'] != 'owned_networkless_synthetic_fixture_only':
        raise Refused('SCOPE_OUTSIDE_PROPOSED_LOCAL_COHORT')
    return value


def version(tool, output):
    prefix = 'psql' if tool == 'psql' else 'postgres' if tool == 'postgres' else tool
    if not re.fullmatch(re.escape(prefix) + r' \(PostgreSQL\) 17\.6(?: [^\r\n]*)?\n?', output):
        raise Refused('ACTUAL_CLIENT_OUTSIDE_17_6_COHORT')
    return '17.6'


def sealed_dump(path, expected):
    body = read(path)
    if not body.startswith(b'PGDMP') or not HASH.fullmatch(expected) or sha(body) != expected:
        raise Refused('DUMP_CONTENT_SEAL_CHANGED')
    return body


def owned(info, name):
    if not re.fullmatch(r'collect_ordinary_recovery_(source|restore)_[0-9a-f]{12}', name):
        raise Refused('OWNED_NAME_REQUIRED')
    if info['Image'] != IMAGE or info['Config']['Labels'].get('collect.recovery.owner') != name:
        raise Refused('OWNERSHIP_OR_IMAGE_CHANGED')
    host = info['HostConfig']
    if host['NetworkMode'] != 'none' or host['PortBindings'] or info['HostConfig'].get('Privileged'):
        raise Refused('NETWORK_OR_PRIVILEGED_SCOPE_CHANGED')
    tmpfs = host.get('Tmpfs', {})
    if tmpfs != {'/var/lib/postgresql/collect-rehearsal': 'rw,size=1073741824'}:
        raise Refused('EXACT_BOUNDED_TMPFS_REQUIRED')
    if host.get('Binds') or host.get('Devices') or host.get('CapAdd'):
        raise Refused('HOST_WRITE_OR_DEVICE_SCOPE_CHANGED')
    return True


def database_acl_sql(database):
    # Strict source database identity; no destination/name/SQL text from a caller.
    if database['name'] != 'postgres' or database['owner'] != 'postgres' or database['connection_limit'] != -1:
        raise Refused('DATABASE_OUTSIDE_FROZEN_FIXTURE')
    rows = []
    for entry in database['acl']:
        match = re.fullmatch(r'([a-z_]*)(=)([CTc]+)/postgres', entry)
        if not match:
            raise Refused('DATABASE_ACL_OUTSIDE_FIXTURE')
        role, _, permissions = match.groups()
        rows.append((role or 'PUBLIC', permissions))
    sql = []
    for role, permissions in rows:
        sql.append('revoke all on database postgres from ' + role + ';')
        names = {'C': 'CREATE', 'T': 'TEMPORARY', 'c': 'CONNECT'}
        sql.append('grant ' + ','.join(names[c] for c in permissions) + ' on database postgres to ' + role + ';')
    return ''.join(sql)


def role_inventory_query(catalog_sql):
    # Reuse the exact admitted collector expressions. They need no application
    # tables or extension CTEs and can run before pg_restore has created them.
    start, end = " 'roles',", " 'relations',"
    if catalog_sql.count(start) != 1 or catalog_sql.count(end) != 1:
        raise Refused('EXACT_ROLE_CATALOG_EXPRESSIONS_REQUIRED')
    first, last = catalog_sql.index(start), catalog_sql.index(end)
    fragment = catalog_sql[first:last].rstrip()
    if first >= last or not fragment.endswith(',') or fragment.count(" 'memberships',") != 1 or fragment.count(" 'settings',") != 1:
        raise Refused('EXACT_ROLE_CATALOG_EXPRESSIONS_REQUIRED')
    return ('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\n'
            'SELECT jsonb_build_object(\n' + fragment[:-1] + '\n);\nCOMMIT;\n')


def role_globals(value):
    if not isinstance(value, dict) or set(value) != {'roles', 'memberships', 'settings'}:
        raise Refused('ROLE_GLOBALS_SCHEMA_INVALID')
    valid_name = lambda name: isinstance(name, str) and re.fullmatch(r'[a-z_][a-z0-9_]*', name)
    roles = value['roles']
    if not isinstance(roles, list):
        raise Refused('ROLE_GLOBALS_SCHEMA_INVALID')
    names = []
    for row in roles:
        if (not isinstance(row, list) or len(row) != 11 or not valid_name(row[0]) or
                any(type(x) is not bool for x in row[1:8]) or type(row[8]) is not int or row[8] < -1 or
                (row[9] is not None and not isinstance(row[9], str)) or
                not isinstance(row[10], str) or not HASH.fullmatch(row[10])):
            raise Refused('ROLE_ATTRIBUTES_SCHEMA_INVALID')
        names.append(row[0])
    if names != sorted(set(names)):
        raise Refused('ROLE_IDENTITIES_DUPLICATE_OR_UNORDERED')
    memberships = value['memberships']
    if not isinstance(memberships, list):
        raise Refused('ROLE_GLOBALS_SCHEMA_INVALID')
    identities = []
    for row in memberships:
        if (not isinstance(row, list) or len(row) != 6 or
                any(not valid_name(x) or x not in names for x in row[:3]) or
                any(type(x) is not bool for x in row[3:])):
            raise Refused('ROLE_MEMBERSHIP_SCHEMA_INVALID')
        identities.append(tuple(row[:3]))
    if identities != sorted(set(identities)):
        raise Refused('ROLE_MEMBERSHIP_IDENTITIES_DUPLICATE_OR_UNORDERED')
    settings = value['settings']
    if not isinstance(settings, list):
        raise Refused('ROLE_GLOBALS_SCHEMA_INVALID')
    identities = []
    for row in settings:
        if (not isinstance(row, list) or len(row) != 3 or row[0] not in ('*', 'postgres') or
                (row[1] != '*' and row[1] not in names) or
                not isinstance(row[2], str) or not HASH.fullmatch(row[2])):
            raise Refused('ROLE_SETTINGS_SCHEMA_INVALID')
        identities.append(tuple(row[:2]))
    if len(identities) != len(set(identities)):
        raise Refused('ROLE_SETTINGS_IDENTITIES_DUPLICATE')
    return value


def restore_role_plan(source, restored):
    source, restored = role_globals(source), role_globals(restored)
    wanted = {row[0]: row for row in source['roles']}
    observed = {row[0]: row for row in restored['roles']}
    if len(wanted) != 30 or wanted.get(SOURCE_ROLE[0]) != SOURCE_ROLE:
        raise Refused('EXACT_OBSERVED_SOURCE_ROLE_COHORT_REQUIRED')
    missing = set(wanted) - set(observed)
    if set(observed) - set(wanted) or missing not in (set(), {SOURCE_ROLE[0]}):
        raise Refused('UNADMITTED_ROLE_IDENTITIES')
    if any(row != wanted[name] for name, row in observed.items()):
        raise Refused('SOURCE_ROLE_ATTRIBUTES_CHANGED')
    if source['memberships'] != restored['memberships'] or source['settings'] != restored['settings']:
        raise Refused('SOURCE_ROLE_MEMBERSHIPS_OR_SETTINGS_CHANGED')
    return SOURCE_ROLE_SQL if missing else ''


def exact_role_globals(source, restored):
    role_globals(source); role_globals(restored)
    if source != restored:
        raise Refused('WHOLE_SOURCE_ROLE_GLOBALS_CHANGED')
    return True


def graphql_source_scope(schema_sql, catalog):
    # Admit one declared function from the actual source catalog and the nested
    # frozen hook, not an arbitrary wrapper SQL statement or dump ACL name.
    identity = [row for row in catalog['functions'] if row[:2] == GRAPHQL_ID[:2]]
    hooks = [row for row in catalog['functions'] if row[:2] == GRAPHQL_HOOK[:2]]
    schemas = [row for row in catalog['schemas'] if row[0] == GRAPHQL_SCHEMA[0]]
    triggers = [row for row in catalog['event_triggers'] if row[0] == GRAPHQL_TRIGGER[0]]
    dependencies = [row for row in catalog['dependencies'] if row[1:3] == ['function', 'graphql_public'] and row[3].startswith('graphql_public.graphql(')]
    if identity != [GRAPHQL_FUNCTION] or hooks != [GRAPHQL_HOOK] or schemas != [GRAPHQL_SCHEMA] or triggers != [GRAPHQL_TRIGGER] or dependencies != GRAPHQL_DEPENDENCIES:
        raise Refused('EXACT_DECLARED_GRAPHQL_SOURCE_PROVENANCE_REQUIRED')
    hook_pattern = r'^CREATE FUNCTION extensions\.grant_pg_graphql_access\(\) RETURNS event_trigger\n    LANGUAGE plpgsql\n    AS \$_\$(.*?)\$_\$;'
    hooks = list(re.finditer(hook_pattern, schema_sql, re.M | re.S))
    if len(hooks) != 1 or sha(hooks[0].group(1).encode()) != GRAPHQL_HOOK[11]:
        raise Refused('EXACT_FROZEN_GRAPHQL_HOOK_REQUIRED')
    wrappers = list(re.finditer(r'        create or replace function graphql_public\.graphql\(.*?        \$\$;', hooks[0].group(1), re.S))
    if len(wrappers) != 1 or sha(wrappers[0].group(0).encode()) != 'f1a08a07934d7df8ab26d675093b2069d1ecfa23be2b331b4a1e84bd48091ea8':
        raise Refused('EXACT_FROZEN_GRAPHQL_WRAPPER_REQUIRED')
    wrapper = wrappers[0].group(0)
    body = wrapper.split('as $$', 1)[1].rsplit('$$;', 1)[0]
    if sha(body.encode()) != GRAPHQL_FUNCTION[11]:
        raise Refused('SOURCE_GRAPHQL_BODY_HASH_CHANGED')
    # CREATE alone refuses an unexpected concurrent definition. The definition
    # returned by pg_get_functiondef still renders CREATE OR REPLACE canonically.
    return dict(function=GRAPHQL_FUNCTION, hook=GRAPHQL_HOOK, schema=GRAPHQL_SCHEMA,
        dependencies=GRAPHQL_DEPENDENCIES, event_trigger=GRAPHQL_TRIGGER,
        source_hook_body_sha256=sha(hooks[0].group(1).encode()),
        source_nested_wrapper_sql_sha256=sha(wrapper.encode()),
        source_wrapper_body_sha256=sha(body.encode()),
        source_function_definition_sha256=GRAPHQL_FUNCTION[12],
        create_schema_sql='create schema graphql_public authorization supabase_admin;',
        create_function_sql=wrapper.replace('create or replace function', 'create function', 1),
        extension_membership_sql=GRAPHQL_MEMBERSHIP_SQL,
        source_extension_membership_proven=True, source_hook_only=True,
        wrapper_creation_provenance_not_inferred_from_ACL=True)


def graphql_inventory_query(catalog_sql):
    # The frozen CTEs and exact schema/function/dependency expressions remain
    # intact. Unlike the full catalog, this needs no restored migration table.
    marker = '\nSELECT jsonb_build_object('
    if catalog_sql.count(marker) != 1:
        raise Refused('EXACT_GRAPHQL_CATALOG_EXPRESSIONS_REQUIRED')
    def fragment(start, end):
        if catalog_sql.count(start) != 1 or catalog_sql.count(end) != 1:
            raise Refused('EXACT_GRAPHQL_CATALOG_EXPRESSIONS_REQUIRED')
        first, last = catalog_sql.index(start), catalog_sql.index(end)
        if first >= last:
            raise Refused('EXACT_GRAPHQL_CATALOG_EXPRESSIONS_REQUIRED')
        return catalog_sql[first:last].rstrip().rstrip(',')
    pieces = [fragment(" 'schemas',", " 'extensions',"),
              fragment(" 'functions',", " 'policies',"),
              fragment(" 'dependencies',", '\n);\nCOMMIT;')]
    return catalog_sql[:catalog_sql.index(marker)] + marker + '\n' + ',\n'.join(pieces) + '\n);\nCOMMIT;\n'


def graphql_state(value):
    if not isinstance(value, dict) or set(value) != {'schemas', 'functions', 'dependencies'} or any(not isinstance(v, list) for v in value.values()):
        raise Refused('GRAPHQL_INVENTORY_SCHEMA_INVALID')
    if any(not isinstance(row, list) or len(row) != size for key, size in [('schemas', 3), ('functions', 13), ('dependencies', 7)] for row in value[key]):
        raise Refused('GRAPHQL_INVENTORY_ROW_INVALID')
    schemas = [row for row in value['schemas'] if row[0] == 'graphql_public']
    functions = [row for row in value['functions'] if row[:2] == GRAPHQL_ID[:2]]
    dependencies = [row for row in value['dependencies'] if row[1:3] == ['function', 'graphql_public'] and row[3].startswith('graphql_public.graphql(')]
    if len(schemas) > 1 or any(len(row) != 13 for row in functions):
        raise Refused('GRAPHQL_INVENTORY_IDENTITIES_INVALID')
    return dict(schema=schemas[0] if schemas else None, functions=functions, dependencies=dependencies)


def graphql_restore_plan(scope, state):
    if (scope['function'] != GRAPHQL_FUNCTION or scope['hook'] != GRAPHQL_HOOK or
            scope['schema'] != GRAPHQL_SCHEMA or scope['event_trigger'] != GRAPHQL_TRIGGER or
            scope['dependencies'] != GRAPHQL_DEPENDENCIES or
            scope['create_schema_sql'] != 'create schema graphql_public authorization supabase_admin;' or
            scope['extension_membership_sql'] != GRAPHQL_MEMBERSHIP_SQL or
            sha(scope['create_function_sql'].encode()) != '92366e4073786ea202bcbeed22c0f4b02c35eeab54aaa9be8757adba92f2edd4'):
        raise Refused('EXACT_DECLARED_GRAPHQL_SOURCE_PROVENANCE_REQUIRED')
    sql = []
    if state['schema'] is None:
        sql.append(scope['create_schema_sql'])
    elif state['schema'][:2] != GRAPHQL_SCHEMA[:2]:
        raise Refused('RESTORE_GRAPHQL_SCHEMA_OWNER_CHANGED')
    functions = state['functions']
    if not functions:
        if state['dependencies']:
            raise Refused('RESTORE_GRAPHQL_DEPENDENCY_CHANGED')
        sql.extend([scope['create_function_sql'], scope['extension_membership_sql']])
    else:
        if len(functions) != 1 or state['schema'] is None:
            raise Refused('UNADMITTED_RESTORE_GRAPHQL_WRAPPER')
        row = functions[0]
        # Source ACLs are applied by the untouched archive. This preliminary
        # check permits only source ACLs or PostgreSQL's exact new-function ACL.
        if row[:10] + row[11:] != GRAPHQL_FUNCTION[:10] + GRAPHQL_FUNCTION[11:] or row[10] not in (GRAPHQL_FUNCTION[10], ['=X/supabase_admin', 'supabase_admin=X/supabase_admin']):
            raise Refused('RESTORE_GRAPHQL_FUNCTION_METADATA_CHANGED')
        if state['dependencies'] == [GRAPHQL_DEPENDENCIES[1]]:
            sql.append(scope['extension_membership_sql'])
        elif state['dependencies'] != GRAPHQL_DEPENDENCIES:
            raise Refused('RESTORE_GRAPHQL_DEPENDENCY_CHANGED')
    return '\n'.join(sql)


def restore_list(toc, catalog, graphql_scope=None):
    # All data, original migration history, object definitions and ACL entries
    # remain. Only exact preinstalled platform extension/schema CREATE entries
    # and separately restored database control entries are omitted explicitly.
    schemas = {row[2] for row in catalog['extensions']} - {'pg_catalog'}
    extensions = {row[0] for row in catalog['extensions']}
    lines, omitted, seen = [], [], set()
    graphql_schema_count, graphql_acl_count = 0, 0
    for line in toc.splitlines(keepends=True):
        match = re.fullmatch(r'(\d+);\s+\d+\s+\d+\s+(EXTENSION|SCHEMA|DATABASE|DATABASE PROPERTIES) - (\S+)(?: ([^\s]+))?\s*', line)
        skip = False
        if match:
            _, kind, name, owner_name = match.groups()
            skip = ((kind == 'EXTENSION' and name in extensions) or
                    (kind == 'SCHEMA' and name in schemas) or
                    (kind in {'DATABASE', 'DATABASE PROPERTIES'} and name == 'postgres'))
            if graphql_scope is not None and kind == 'SCHEMA' and name == 'graphql_public':
                if owner_name != 'supabase_admin':
                    raise Refused('EXACT_GRAPHQL_SCHEMA_TOC_REQUIRED')
                graphql_schema_count += 1; skip = True
            if kind == 'EXTENSION':
                seen.add(name)
        if skip:
            omitted.append(line.rstrip())
            lines.append('; preinstalled exact frozen prerequisite: ' + line)
        else:
            lines.append(line)
        if graphql_scope is not None and re.search(r'\b(?:FUNCTION graphql_public graphql|ACL graphql_public FUNCTION graphql)\(', line):
            allowed_acl = r'\d+;\s+\d+\s+\d+\s+ACL graphql_public FUNCTION graphql\("operationName" text, query text, variables jsonb, extensions jsonb\) supabase_admin\s*'
            if not re.fullmatch(allowed_acl, line):
                raise Refused('UNADMITTED_GRAPHQL_WRAPPER_TOC')
            graphql_acl_count += 1
    if not seen or not seen.issubset(extensions) or not any('TABLE DATA supabase_migrations schema_migrations' in line for line in lines):
        raise Refused('FULL_HISTORY_OR_EXTENSION_TOC_REQUIRED')
    if not any('TABLE DATA auth users' in line for line in lines):
        raise Refused('FULL_SYNTHETIC_AUTH_DATA_REQUIRED')
    if graphql_scope is not None and (graphql_scope['function'] != GRAPHQL_FUNCTION or graphql_schema_count != 1 or graphql_acl_count != 1):
        raise Refused('EXACT_GRAPHQL_SCHEMA_AND_RETAINED_ACL_TOC_REQUIRED')
    return ''.join(lines), omitted


class Runner:
    def __init__(self, report, deadline):
        self.report, self.deadline, self.records = report, deadline, []

    def call(self, argv, body=None, check=True, timeout=120, limit=LIMIT):
        left = self.deadline - time.monotonic()
        if left <= 0:
            raise Refused('WHOLE_600_SECOND_DEADLINE')
        if isinstance(body, str):
            body = body.encode()
        if body is not None and len(body) > LIMIT:
            raise Refused('INPUT_LIMIT')
        process = subprocess.Popen(argv, env=ENV, stdin=subprocess.PIPE if body is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        end = time.monotonic() + min(timeout, left)
        out, err, offset = bytearray(), bytearray(), 0
        try:
            with selectors.DefaultSelector() as selector:
                for stream, label in [(process.stdout, 'out'), (process.stderr, 'err')]:
                    os.set_blocking(stream.fileno(), False)
                    selector.register(stream, selectors.EVENT_READ, label)
                if process.stdin is not None:
                    os.set_blocking(process.stdin.fileno(), False)
                    selector.register(process.stdin, selectors.EVENT_WRITE, 'in')
                while selector.get_map():
                    if time.monotonic() >= end:
                        raise Refused('BOUNDED_TOOL_DEADLINE')
                    for key, _ in selector.select(.05):
                        if key.data == 'in':
                            if offset == len(body):
                                selector.unregister(key.fileobj); key.fileobj.close(); continue
                            try:
                                offset += os.write(key.fileobj.fileno(), body[offset:offset + 16384])
                            except BrokenPipeError:
                                selector.unregister(key.fileobj); key.fileobj.close()
                        else:
                            chunk = os.read(key.fileobj.fileno(), 16384)
                            if not chunk:
                                selector.unregister(key.fileobj); continue
                            stream = out if key.data == 'out' else err
                            stream.extend(chunk)
                            if len(stream) > (limit if key.data == 'out' else 1024**2):
                                raise Refused('BOUNDED_TOOL_OUTPUT_LIMIT')
                code = process.wait(timeout=max(.001, end - time.monotonic()))
        except BaseException as error:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
            command = ['POSTGRES_PASSWORD=<ephemeral-unlogged>' if str(a).startswith('POSTGRES_PASSWORD=') else a for a in argv]
            row = dict(command=command, status='refused', reason=str(error),
                input_sha256=sha(body) if body is not None else None,
                stdout_bytes=len(out), stdout_sha256=sha(out), stderr_bytes=len(err), stderr_sha256=sha(err))
            self.records.append(row)
            with (self.report / 'commands.jsonl').open('a') as log:
                log.write(json.dumps(row) + '\n')
            raise
        finally:
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream is not None and not stream.closed:
                    stream.close()
        command = ['POSTGRES_PASSWORD=<ephemeral-unlogged>' if str(a).startswith('POSTGRES_PASSWORD=') else a for a in argv]
        row = dict(command=command, exit_code=code, input_sha256=sha(body) if body is not None else None,
            stdout_bytes=len(out), stdout_sha256=sha(out), stderr_bytes=len(err), stderr_sha256=sha(err))
        self.records.append(row)
        with (self.report / 'commands.jsonl').open('a') as log:
            log.write(json.dumps(row) + '\n')
        if check and code:
            # SQL/text is synthetic, but avoid exporting dump bodies in failures.
            raise Refused('TOOL_FAILED: ' + str(command[1:3]) + ': ' + bytes(err[-1500:]).decode(errors='replace'))
        return subprocess.CompletedProcess(argv, code, bytes(out), bytes(err))

    def text(self, argv, text=None, check=True, timeout=120):
        result = self.call(argv, text, check, timeout)
        return subprocess.CompletedProcess(argv, result.returncode, result.stdout.decode(), result.stderr.decode())


def canonical_catalog_sha(value):
    return sha(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def compatibility_source_scope(source, captured_restored, hook_sql, transport_sql, notification_sql, provider_sql):
    # Complete captured catalog hashes admit every category/row, not just names
    # or ACLs. Any additional object, changed body, owner, ACL or flag refuses.
    if canonical_catalog_sha(source) != COMPATIBILITY_SOURCE_SHA or canonical_catalog_sha(captured_restored) != COMPATIBILITY_RESTORED_SHA:
        raise Refused('EXACT_CAPTURED_COMPATIBILITY_CATALOGS_REQUIRED')
    files = [(hook_sql, '77262947961ac1a724195ea77bdb98088cebd30caecc625ded1d4a93ccbf6d3d'),
        (transport_sql, 'f5c7b3a18ae3bc5da46b4de98398c4504ac04ca27c404b47fc6fcd725ebbb64f'),
        (notification_sql, '33a57d2d756089b842e906cfa051cc09cfcb19d99a0ae6adde0803187cd66105'),
        (provider_sql, '1f1a77a04bd0e9e369a134f49a6022e5645fe28798603fd94d316c115774744f')]
    if any(sha(text.encode()) != digest for text, digest in files):
        raise Refused('EXACT_FROZEN_COMPATIBILITY_SOURCE_SQL_REQUIRED')
    graphql_source_scope(hook_sql, source)
    notification = re.findall(r'^alter table notification_events\n  add constraint notification_events_copy_length_check check \((.*?)\n  \) not valid;', notification_sql, re.M | re.S)
    provider = re.findall(r'^  provider_network text check \((.*?)\n  \),', provider_sql, re.M | re.S)
    index = re.findall(r'^create index if not exists collect_receipt_http_response_id on net\._http_response\(id\);$', transport_sql, re.M)
    if notification != [NOTIFICATION_EXPRESSION] or provider != [PROVIDER_EXPRESSION] or index != [TRANSPORT_INDEX_SQL]:
        raise Refused('EXACT_ORIGINAL_BETWEEN_EXPRESSIONS_AND_INDEX_REQUIRED')
    functions = [row for row in source['functions'] if row[0] == 'graphql']
    signatures = [row[:3] for row in functions]
    expected = [['graphql', '_internal_resolve', 'query text, variables jsonb, "operationName" text, extensions jsonb'],
        ['graphql', 'comment_directive', 'comment_ text'], ['graphql', 'exception', 'message text'],
        ['graphql', 'get_schema_version', ''], ['graphql', 'increment_schema_version', ''],
        ['graphql', 'resolve', 'query text, variables jsonb, "operationName" text, extensions jsonb']]
    if signatures != expected or any(row[4] != 'supabase_admin' for row in functions):
        raise Refused('EXACT_GRAPHQL_GRANT_OBJECTS_REQUIRED')
    index_rows = {key: [row for row in source[key] if row[:2] == ['net', 'collect_receipt_http_response_id']]
                  for key in ('columns', 'relations', 'indexes')}
    index_dependencies = [row for row in source['dependencies'] if row[2:4] == ['net', 'net.collect_receipt_http_response_id']]
    table_member = ['e', 'table', 'net', 'net._http_response', 'extension', None, 'pg_net']
    if (table_member not in source['dependencies'] or len(index_rows['indexes']) != 1 or
            index_rows['indexes'][0][2:] != [True, True, True, '9328daab9410518dca5727ad8889381de3d298d548b204d8bed7fd1437a90df3'] or
            index_dependencies != [['a', 'index', 'net', 'net.collect_receipt_http_response_id', 'table column', 'net', 'net._http_response.id']]):
        raise Refused('EXACT_SOURCE_EXTENSION_TABLE_AND_INDEX_REQUIRED')
    constraints = [row for row in source['constraints'] if row[2] in
        ('notification_events_copy_length_check', 'provider_finality_requests_provider_network_check')]
    restored_constraints = [row for row in captured_restored['constraints'] if row[2] in
        ('notification_events_copy_length_check', 'provider_finality_requests_provider_network_check')]
    if constraints != [
        ['public', 'public.notification_events', 'notification_events_copy_length_check', 'c', False, False, False, 'd39f28d2b96e15bb3abe3c66ef153a22ec19a6381e78c24db1965407925a9e87'],
        ['public', 'public.provider_finality_requests', 'provider_finality_requests_provider_network_check', 'c', True, False, False, '05c313d4a8d16cf1745983feb6df49956260bf6fa1dc8eaf65ccc10630086d51']]:
        raise Refused('EXACT_SOURCE_CHECK_IDENTITIES_FLAGS_AND_HASHES_REQUIRED')
    return dict(source_catalog_canonical_sha256=COMPATIBILITY_SOURCE_SHA,
        captured_restored_catalog_canonical_sha256=COMPATIBILITY_RESTORED_SHA,
        graphql_functions=functions, graphql_schemas=[row for row in source['schemas'] if row[0] in ('graphql','graphql_public')],
        graphql_sequence=[row for row in source['relations'] if row[:2] == ['graphql','seq_schema_version']],
        graphql_extension_function_members=[row for row in source['dependencies'] if row[0]=='e' and row[1:3]==['function','graphql']],
        source_index_rows=index_rows, source_index_dependencies=index_dependencies, underlying_table_extension_membership=table_member,
        source_constraints=constraints, exact_admitted_restored_constraints=restored_constraints,
        notification_original_expression=notification[0], provider_original_expression=provider[0],
        admin_sql=GRAPHQL_GRANTS_SQL + index[0] + '\ncommit;', postgres_sql=CHECK_REPAIR_SQL,
        schema_or_function_rewrite=False, generic_GRANT_ALL=False, full_catalog_comparator_unchanged=True,
        graphql_public_nonpostgres_usage_grants_proven_by_captured_schema_ACL=True)


def compatibility_plan(source, restored, scope):
    if (canonical_catalog_sha(source) != COMPATIBILITY_SOURCE_SHA or
            scope['source_catalog_canonical_sha256'] != COMPATIBILITY_SOURCE_SHA or
            scope['captured_restored_catalog_canonical_sha256'] != COMPATIBILITY_RESTORED_SHA or
            scope['admin_sql'] != GRAPHQL_GRANTS_SQL + TRANSPORT_INDEX_SQL + '\ncommit;' or
            scope['postgres_sql'] != CHECK_REPAIR_SQL):
        raise Refused('SOURCE_COMPATIBILITY_SCOPE_CHANGED')
    observed = canonical_catalog_sha(restored)
    if observed == COMPATIBILITY_SOURCE_SHA:
        return dict(admin_sql='', postgres_sql='', reason='already_exact_source_catalog')
    if observed != COMPATIBILITY_RESTORED_SHA:
        raise Refused('UNKNOWN_RESTORED_METADATA_ACL_INDEX_OR_CHECK')
    return dict(admin_sql=scope['admin_sql'], postgres_sql=scope['postgres_sql'],
                reason='only_exact_retained_recovery3_catalog_difference_admitted')


def projection_parity(observed, committed):
    if not isinstance(observed, dict) or not isinstance(committed, dict) or len(observed) != 18 or len(committed) != 18 or observed != committed:
        raise Refused('ALL18_COMMITTED_PROJECTIONS_MUST_MATCH_AROUND_REPAIRS')
    return True


def compatibility_archive_proof(source, toc, dump):
    if canonical_catalog_sha(source) != COMPATIBILITY_SOURCE_SHA:
        raise Refused('EXACT_SOURCE_ARCHIVE_OMISSION_PROVENANCE_REQUIRED')
    sequence_member = ['e', 'sequence', 'graphql', 'graphql.seq_schema_version', 'extension', None, 'pg_graphql']
    if (sequence_member not in source['dependencies'] or
            'collect_receipt_http_response_id' in toc or b'collect_receipt_http_response_id' in dump or
            re.search(r'^\d+;\s+\d+\s+\d+\s+(?:FUNCTION|ACL|SEQUENCE) graphql ', toc, re.M)):
        raise Refused('EXACT_KNOWN_EXTENSION_OBJECT_INDEX_ARCHIVE_OMISSIONS_REQUIRED')
    return dict(index_name_occurrences_in_uncompressed_archive=0,index_name_occurrences_in_TOC=0,
        six_graphql_extension_function_definitions_and_ACLs_absent_from_TOC=True,
        sequence_definition_and_ACL_absent_from_TOC=True,sequence_extension_membership=sequence_member,
        no_archive_line_omitted_or_rewritten_by_this_proof=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, default=HERE / 'inputs.json')
    parser.add_argument('--review-record', type=Path, required=True)
    parser.add_argument('--review-record-sha256', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    absolute = lambda path: path if path.is_absolute() else Path.cwd() / path
    code_body, inputs_body = read(Path(__file__).resolve()), read(absolute(args.inputs))
    review_body = read(absolute(args.review_record), 16384)
    if not HASH.fullmatch(args.review_record_sha256) or sha(review_body) != args.review_record_sha256:
        raise Refused('REVIEW_RECORD_BINDING_CHANGED')
    review = admit_review(json.loads(review_body, object_pairs_hook=unique), sha(code_body), sha(inputs_body))
    inputs = json.loads(inputs_body, object_pairs_hook=unique)
    candidate = Path(inputs['candidate'])
    expected_candidate = Path('/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate4')
    report = args.output.resolve()
    if candidate != expected_candidate or report.exists() or not report.is_relative_to(candidate / 'docs/release'):
        raise Refused('FRESH_PRIVATE_OWNED_OUTPUT_REQUIRED')
    report.mkdir(parents=True, mode=0o700)
    record = dict(kind='collect_local_committed_synthetic_recovery_v1', status='running',
        shipping_restore_admission=False, proposed_local_compatibility_review=review,
        review_authentication=False, cases=[], targets={}, maintained_source_mutations=0,
        source_rows_copied=False, real_auth_or_customer_or_provider_rows=False,
        hosted_called=False, provider_called=False, production_app_export=False,
        full_BE08_closed=False, ARC08_restore_adapter_closed=False, ARC11_closed=False,
        whole_deadline_seconds=600, started_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
    started = time.monotonic()
    whole_deadline = started + 600
    # Reserve one minute for failure reconciliation inside the whole600 bound.
    runner = Runner(report, started + 540)
    record['execution_budget_seconds'] = 540
    record['cleanup_budget_seconds'] = 60
    targets = []
    def save():
        (report / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    def case(name, ok=True):
        if not ok:
            raise AssertionError(name)
        record['cases'].append(dict(name=name, status='pass')); save(); print('PASS ' + name, flush=True)
    def freeze():
        for name, digest in {**inputs['sources'], **inputs['references']}.items():
            if sha(read(candidate / name)) != digest:
                raise Refused('PRIVATE_FROZEN_INPUT_DRIFT: ' + name)
        names = {str(p.relative_to(candidate)) for p in (candidate / 'supabase/migrations').glob('*.sql')}
        if names != {name for name in inputs['sources'] if name.startswith('supabase/migrations/')}:
            raise Refused('MIGRATION_SET_DRIFT')
    freeze()
    spec = importlib.util.spec_from_file_location('collect_current_release_upgrade_uat', candidate / 'scripts/tests/collect_current_release_upgrade_uat.py')
    replay = importlib.util.module_from_spec(spec); spec.loader.exec_module(replay)
    replay.command = runner.text
    replay.IMAGE = IMAGE
    reference = document(candidate / 'reference/observed-output/result.json')
    reference_pre = document(candidate / 'reference/observed-output/ordinary_populated/predecessor-effective-catalog.json')
    reference_final_body = read(candidate / 'reference/observed-output/ordinary_populated/final-effective-catalog.json')
    reference_final = json.loads(reference_final_body)
    if sha(reference_final_body) != FINAL_SHA or len(reference['preserved_columns']) != 18:
        raise Refused('REFERENCE_BINDING_CHANGED')
    globals_query = role_inventory_query(read(candidate / CATALOG).decode())
    reference_globals = role_globals({key: reference_pre[key] for key in ('roles', 'memberships', 'settings')})
    # Validate the source-only role admission before any container can be made.
    restore_role_plan(reference_globals, reference_globals)
    (report / 'role-globals-query.sql').write_text(globals_query)
    graphql_scope = graphql_source_scope(read(candidate / '.cache/receipt-foundation-attempt8/schema-only.sql').decode(), reference_pre)
    graphql_query = graphql_inventory_query(read(candidate / CATALOG).decode())
    (report / 'graphql-wrapper-query.sql').write_text(graphql_query)
    record['graphql_wrapper_admitted_source_scope'] = graphql_scope
    captured_source_body = read(candidate / 'reference/compatibility3/source-predecessor-catalog.json')
    captured_restored_body = read(candidate / 'reference/compatibility3/restored-predecessor-catalog.json')
    if sha(captured_source_body) != CAPTURED_SOURCE_FILE_SHA or sha(captured_restored_body) != CAPTURED_RESTORED_FILE_SHA:
        raise Refused('CAPTURED_RECOVERY3_CATALOG_FILE_BINDING_CHANGED')
    captured_source, captured_restored = json.loads(captured_source_body), json.loads(captured_restored_body)
    if reference_pre != captured_source:
        raise Refused('FROZEN_PREDECESSOR_NOT_EXACT_CAPTURED_SOURCE')
    compatibility_scope = compatibility_source_scope(captured_source, captured_restored,
        read(candidate / '.cache/receipt-foundation-attempt8/schema-only.sql').decode(),
        read(candidate / TRANSPORT).decode(),
        read(candidate / 'supabase/migrations/20260804150000_native_push_delivery.sql').decode(),
        read(candidate / 'supabase/migrations/20260903084000_hybrid_direct_ussd_financial_core.sql').decode())
    record['admitted_compatibility_repair_scope'] = compatibility_scope
    items = []
    for row in reference['source_inventory']:
        body = read(candidate / row['path'])
        if sha(body) != row['sha256'] or inputs['sources'][row['path']] != row['sha256']:
            raise Refused('ORIGINAL_MIGRATION_CHANGED')
        items.append(dict(**row, body=body.decode()))
    if len(items) != 209 or reference_pre['migrations'] != [i['version'] for i in items[:124]]:
        raise Refused('EXACT_124_PLUS_85_CHAIN_REQUIRED')
    record['input_binding'] = dict(inputs_sha256=sha(inputs_body), code_sha256=sha(code_body),
        source_count=216, source_hashes=inputs['sources'], final_reference_sha256=FINAL_SHA,
        reference_data_hashes_not_reused=True)

    class Target(replay.Target):
        def __init__(self, phase):
            outcome = record['targets'][phase] = {}
            super().__init__(report, phase, outcome)
            self.name = 'collect_ordinary_recovery_' + phase + '_' + uuid.uuid4().hex[:12]
            self.tools = {}
            with (report / 'owned-targets.jsonl').open('a') as log:
                log.write(json.dumps(dict(name=self.name, phase=phase, image_id=IMAGE)) + '\n')
            targets.append(self)
        def __enter__(self):
            # Add the recovery ownership label to the inherited exact-image run.
            original = replay.command
            def creation(argv, *a, **kw):
                if argv[:2] == [DOCKER, 'run']:
                    argv = list(argv); argv[2:2] = ['--label', 'collect.recovery.owner=' + self.name]
                return original(argv, *a, **kw)
            replay.command = creation
            try:
                super().__enter__()
            finally:
                replay.command = original
            self.guard()
            self.identities()
            return self
        def guard(self):
            info = json.loads(runner.call([DOCKER, 'container', 'inspect', self.name], limit=1024**2).stdout)[0]
            owned(info, self.name)
            self.evidence['guard_verified'] = True
        def identities(self):
            for tool in ['psql', 'pg_dump', 'pg_restore', 'postgres']:
                # Fixed shell text only; no source/caller interpolation.
                path = runner.call([DOCKER, 'exec', self.name, '/bin/sh', '-c', 'command -v ' + tool]).stdout.decode().strip()
                if not re.fullmatch(r'/[A-Za-z0-9_./-]+', path):
                    raise Refused('ABSOLUTE_IN_IMAGE_TOOL_REQUIRED')
                resolved = runner.call([DOCKER, 'exec', self.name, 'readlink', '-f', path]).stdout.decode().strip()
                digest = runner.call([DOCKER, 'exec', self.name, 'sha256sum', resolved]).stdout.decode().split()[0]
                if not HASH.fullmatch(digest):
                    raise Refused('ACTUAL_TOOL_HASH_REQUIRED')
                observed = runner.call([DOCKER, 'exec', self.name, resolved, '--version']).stdout.decode()
                self.tools[tool] = dict(path=resolved, sha256=digest, version=version(tool, observed), raw_version=observed, image_id=IMAGE)
            self.evidence['actual_tools'] = self.tools
            if self.scalar("select current_setting('server_version_num');") != '170006':
                raise Refused('ACTUAL_SERVER_OUTSIDE_17_6_COHORT')
        def tool(self, tool, arguments, body=None, check=True):
            self.guard()
            identity = self.tools[tool]
            digest = runner.call([DOCKER, 'exec', self.name, 'sha256sum', identity['path']]).stdout.decode().split()[0]
            if digest != identity['sha256']:
                raise Refused('IN_IMAGE_TOOL_CHANGED')
            return runner.call([DOCKER, 'exec', '-i', self.name, identity['path'], *arguments], body, check)
        def sql(self, text, check=True, label='query', user='postgres'):
            # The inherited platform-init probes run before identity discovery.
            # Every admitted application/dump/restore consumer thereafter uses
            # the captured absolute in-image psql path with a fresh byte check.
            if 'psql' not in self.tools:
                return super().sql(text, check, label, user)
            with (self.report / 'queries.sql').open('a') as log:
                log.write('-- Offline synthetic target: ' + label + '\n' + text + '\n')
            result = self.tool('psql', ['-XqAt', '-U', user, '-d', 'postgres',
                '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'],
                "set search_path=public,extensions,auth;set timezone='UTC';\n" + text, False)
            value = subprocess.CompletedProcess(result.args, result.returncode, result.stdout.decode(), result.stderr.decode())
            with (self.report / 'queries.log').open('a') as log:
                log.write(json.dumps(dict(label=label, sql_sha256=sha(text.encode()), exit_code=value.returncode,
                    stdout_sha256=sha(result.stdout), stderr_sha256=sha(result.stderr))) + '\n')
            if check and value.returncode:
                raise Refused(label + ': ' + value.stderr[-1500:])
            return value
        def control(self, sql):
            return self.tool('psql', ['-XqAt', '-U', 'supabase_admin', '-d', 'template1', '-v', 'ON_ERROR_STOP=1'], sql)
        def close(self):
            # Even a failed/uncertain docker run is reconciled by the exact name.
            response = runner.call([DOCKER, 'container', 'inspect', self.name], check=False, timeout=15, limit=1024**2)
            if response.returncode == 0:
                owned(json.loads(response.stdout)[0], self.name)
                runner.call([DOCKER, 'rm', '--force', '--volumes', self.name], timeout=15)
            elif response.returncode != 1 or not re.search(rb'No such (?:container|object)', response.stderr, re.I):
                raise Refused('OWNED_CLEANUP_READBACK_UNKNOWN')
            absent = runner.call([DOCKER, 'container', 'inspect', self.name], check=False, timeout=15, limit=1024**2)
            if absent.returncode != 1 or not re.search(rb'No such (?:container|object)', absent.stderr, re.I):
                raise Refused('OWNED_CONTAINER_NOT_REMOVED')
            self.made = False; self.evidence['task_container_removed'] = True
        def __exit__(self, kind, error, traceback):
            if error is not None:
                self.evidence['first_failure'] = str(error)
            try:
                self.close()
            except BaseException as cleanup_error:
                self.evidence['deferred_cleanup_error'] = str(cleanup_error)
                if error is None:
                    raise
                # Retain the actual operation failure; final reserved cleanup
                # retries the same exact owner/name under the whole deadline.
            return False

    def ordinary(target):
        state = target.json("select jsonb_build_object('user',current_user,'role',current_role,'superuser',rolsuper,'create_db',rolcreatedb,'create_role',rolcreaterole,'bypass_rls',rolbypassrls)from pg_roles where rolname=current_user;")
        if state['user'] != 'postgres' or state['role'] != 'postgres' or state['superuser'] is not False:
            raise Refused('ORDINARY_INSTALLER_REQUIRED')
        return state
    def safeguards(target):
        target.guard()
        state = target.json("select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'listen',current_setting('listen_addresses'),'cron_history',(select count(*)from cron.job_run_details),'net_queue',(select count(*)from net.http_request_queue));")
        if state != dict(cron='off', net='0', listen='', cron_history=0, net_queue=0):
            raise Refused('SCHEDULER_OR_NETWORK_SAFEGUARD_CHANGED')
        target.evidence['scheduler_safeguards'] = state
    def catalog(target, boundary, expected):
        ordinary(target)
        result = target.json(read(candidate / CATALOG).decode())
        if result['migrations'] != expected or result['server']['version'] != reference_pre['server']['version']:
            raise Refused('CATALOG_VERSION_BOUNDARY_CHANGED')
        body = (json.dumps(result, indent=2) + '\n').encode()
        if len(body) > 32 * 1024**2:
            raise Refused('CATALOG_LIMIT')
        path = target.report / (boundary + '-catalog.json'); path.write_bytes(body)
        target.evidence.setdefault('catalogs', {})[boundary] = dict(sha256=sha(body),
            canonical_sha256=sha(json.dumps(result, sort_keys=True, separators=(',', ':')).encode()),
            bytes=len(body), query_sha256=inputs['sources'][CATALOG], whole_catalog_and_effective_acls=True)
        return result, body
    def inventory_roles(target, boundary):
        result = role_globals(target.json(globals_query))
        body = (json.dumps(result, indent=2) + '\n').encode()
        (target.report / (boundary + '-role-globals.json')).write_bytes(body)
        target.evidence.setdefault('role_globals', {})[boundary] = dict(
            sha256=sha(body), query_sha256=sha(globals_query.encode()),
            exact_catalog_expression_input_sha256=inputs['sources'][CATALOG],
            names=[row[0] for row in result['roles']], role_count=len(result['roles']),
            memberships=len(result['memberships']), settings=len(result['settings']),
            readonly=True, secrets_exported=False)
        return result
    def inventory_graphql(target, boundary):
        raw = target.json(graphql_query)
        state = graphql_state(raw)
        body = (json.dumps(state, indent=2) + '\n').encode()
        (target.report / (boundary + '-graphql-wrapper.json')).write_bytes(body)
        target.evidence.setdefault('graphql_wrapper', {})[boundary] = dict(
            sha256=sha(body), query_sha256=sha(graphql_query.encode()),
            exact_catalog_expression_input_sha256=inputs['sources'][CATALOG],
            readonly=True, ACLs_pending_archive=(target.phase == 'restore'))
        return state
    def platform(target):
        shape, provenance = replay.platform_shape()
        if sha(shape.encode()) != reference['platform_bootstrap']['extracted_platform_sha256']:
            raise Refused('EXACT_PLATFORM_SHAPE_CHANGED')
        target.sql(shape, label='sealed schema-only platform fixture before application migration')
        for sql in ["create extension if not exists pg_cron with schema pg_catalog;",
                    "create extension if not exists pg_net with schema extensions;",
                    "alter function net.http_get(text,jsonb,jsonb,integer)security definer;alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;",
                    read(candidate / TRANSPORT).decode(),
                    "grant execute on function cron.alter_job(bigint,text,text,text,text,boolean)to postgres;",
                    "alter role postgres nosuperuser;"]:
            target.sql(sql, user='supabase_admin', label='exact privileged local platform prerequisite')
        target.evidence['platform_provenance'] = provenance
        ordinary(target); safeguards(target)
    def apply(target, selected, preserved=None):
        for item in selected:
            authority = ordinary(target)
            before = replay.fingerprints(target, reference['preserved_columns']) if preserved is not None else None
            replay.apply(target, [item], target.evidence)
            row = target.evidence['migrations'][-1]; row['authority'] = authority
            ordinary(target)
            if preserved is not None:
                after = replay.fingerprints(target, reference['preserved_columns'])
                if before != preserved or after != preserved:
                    raise AssertionError('18 committed projections changed at ' + item['version'])
                row['all_18_fresh_committed_projections_preserved'] = True
            save()

    save()
    try:
        socket = runner.call([DOCKER, 'context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], timeout=15).stdout.decode().strip()
        if not socket.startswith('unix://'):
            raise Refused('LOCAL_DOCKER_UNIX_SOCKET_REQUIRED')
        ENV['DOCKER_HOST'] = socket
        image = runner.call([DOCKER, 'image', 'inspect', IMAGE, '--format', '{{.Id}}'], timeout=15).stdout.decode().strip()
        if image != IMAGE:
            raise Refused('CACHED_IMMUTABLE_IMAGE_REQUIRED')
        source = Target('source')
        with source:
            platform(source); apply(source, items[:124])
            pre, _ = catalog(source, 'before-seed', [i['version'] for i in items[:124]])
            case('fresh predecessor whole catalog equals sealed ordinary124 reference', pre == reference_pre)
            replay.seed_populated(source, record, case)
            case('fresh synthetic projection cohort equals actual current209 reference cohort', record['preserved_columns'] == reference['preserved_columns'])
            # Independent psql invocations prove rows and registry are committed;
            # pg_dump is another process/session after all seed COMMITs.
            preserved = replay.fingerprints(source, reference['preserved_columns'])
            record['fresh_committed_predecessor_fingerprints'] = preserved
            case('all18 committed synthetic projections are present', len(preserved) == 18 and preserved['auth.users']['rows'] == 2)
            case('synthetic Auth rows have no password/token/session secrets', source.scalar("select not exists(select 1 from auth.users where id not in('99780000-0000-4000-8000-000000000001','99780000-0000-4000-8000-000000000002')or coalesce(encrypted_password,'')<>''or coalesce(confirmation_token,'')<>''or coalesce(recovery_token,'')<>''or coalesce(email_change_token_new,'')<>''or coalesce(email_change_token_current,'')<>''or coalesce(phone_change_token,'')<>''or coalesce(reauthentication_token,'')<>'')and not exists(select 1 from auth.sessions where id<>'99780000-0000-4000-8000-000000010001'or coalesce(refresh_token_hmac_key,'')<>'')and not exists(select 1 from auth.refresh_tokens);") == 't')
            committed, _ = catalog(source, 'committed-predecessor', [i['version'] for i in items[:124]])
            case('committed predecessor whole catalog remains exact reference', committed == reference_pre)
            committed_globals = inventory_roles(source, 'committed-predecessor')
            case('readonly all30 source role attributes memberships settings equal frozen source',
                 exact_role_globals(reference_globals, committed_globals))
            # Whole committed equality precedes this dedicated source readback.
            actual_graphql_scope = graphql_source_scope(read(candidate / '.cache/receipt-foundation-attempt8/schema-only.sql').decode(), committed)
            source_graphql_state = inventory_graphql(source, 'committed-predecessor')
            case('source GraphQL wrapper hook body definition owner and extension membership match frozen scope',
                 actual_graphql_scope == graphql_scope and graphql_restore_plan(graphql_scope, source_graphql_state) == '')
            safeguards(source)
            dump = source.tool('pg_dump', ['--format=custom', '--compress=0', '--no-password', '--username=supabase_admin', '--dbname=postgres']).stdout
            if not dump.startswith(b'PGDMP') or len(dump) > LIMIT:
                raise Refused('ACTUAL_BOUNDED_CUSTOM_ARCHIVE_REQUIRED')
            dump_path = report / 'committed-synthetic-predecessor.dump'
            with dump_path.open('xb') as stream:
                stream.write(dump); stream.flush(); os.fsync(stream.fileno())
            dump_path.chmod(0o600)
            record['dump_seal'] = dict(path=str(dump_path), bytes=len(dump), sha256=sha(dump), format='custom',
                full_database=True, filters=False, owner_or_acl_omission=False,
                pg_dump=source.tools['pg_dump'], dump_role='supabase_admin',
                role_globals_excluded_by_pg_dump=True,
                role_globals_require_exact_image_and_observed_source_prerequisite=True, real_rows_exported=False,
                committed_outside_seed_transaction=True)
            case('durable full logical dump exists after committed seed in separate session', sha(read(dump_path)) == sha(dump))
            case('source dump did not change18 projections', replay.fingerprints(source, reference['preserved_columns']) == preserved)
        case('source container removed before independently owned restore target', source.evidence['task_container_removed'])
        restored = Target('restore')
        with restored:
            if restored.tools != source.tools:
                raise Refused('INDEPENDENT_TARGET_TOOL_IDENTITY_CHANGED')
            d = committed['database']
            if (d['encoding'], d['locale_provider'], d['collate'], d['ctype'], d['locale']) != ('UTF8', 'i', 'en_US.UTF-8', 'en_US.UTF-8', 'en-US'):
                raise Refused('DATABASE_LOCALE_OUTSIDE_FROZEN_FIXTURE')
            restored.control("drop database postgres with(force);create database postgres with template=template0 owner=postgres encoding='UTF8' locale_provider=icu locale='en_US.UTF-8' icu_locale='en-US';")
            # pg_dump excludes cluster roles and extension member definitions.
            # This explicit prerequisite restores the admitted image globals and
            # exact extension owner/version/member metadata, not arbitrary SQL.
            for schema_name, owner_name, _ in committed['schemas']:
                if schema_name in {e[2] for e in committed['extensions']} - {'pg_catalog'}:
                    restored.sql('create schema if not exists ' + schema_name + ' authorization ' + owner_name + ';', user='supabase_admin', label='empty target exact extension schema prerequisite')
            for name, ext_version, schema_name, owner_name in committed['extensions']:
                if not re.fullmatch(r'[a-z0-9_-]+', name) or owner_name not in ('postgres', 'supabase_admin'):
                    raise Refused('EXTENSION_OUTSIDE_FROZEN_FIXTURE')
                restored.sql('create extension if not exists "' + name + '" with schema ' + schema_name + " version '" + ext_version + "';", user=owner_name, label='exact source extension owner/version prerequisite')
            restored.sql("alter function net.http_get(text,jsonb,jsonb,integer)security definer;alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;", user='supabase_admin', label='explicit exact extension member metadata omitted by pg_dump')
            restored.sql(database_acl_sql(d), label='exact source database owner-issued ACL prerequisite')
            # The actual candidate1 failure proved the image fixture alone lacks
            # a source role referenced by the net ACL. No roles are inferred from
            # arbitrary dump text and no other missing role can be synthesized.
            restored.sql('alter role postgres nosuperuser;', user='supabase_admin',
                         label='finish extension owner prerequisites before readonly role-global comparison')
            ordinary(restored)
            before_roles = inventory_roles(restored, 'before-source-role-prerequisite')
            role_sql = restore_role_plan(committed_globals, before_roles)
            record['source_role_restore_prerequisite'] = dict(
                role=SOURCE_ROLE[0], exact_observed_source_row=SOURCE_ROLE,
                source_names=[row[0] for row in committed_globals['roles']],
                restore_names_before=[row[0] for row in before_roles['roles']],
                missing_roles=[SOURCE_ROLE[0]] if role_sql else [],
                sql=role_sql, sql_sha256=sha(role_sql.encode()),
                source_global_excluded_by_single_database_dump=True,
                image_fixture_complete=False, unknown_roles_or_mismatches_refused=True,
                secrets_exported=False, business_authority_inferred=False)
            if role_sql:
                restored.sql(role_sql, user='supabase_admin',
                             label='exact admitted source-only supabase_functions_admin local restore prerequisite')
            after_roles = inventory_roles(restored, 'after-source-role-prerequisite')
            case('all30 restored role attributes memberships settings exactly equal committed source before pg_restore',
                 exact_role_globals(committed_globals, after_roles))
            # The retained candidate2 failure identifies an extension-member
            # wrapper definition omitted by the archive. Install only this exact
            # source schema/function before its intact archive ACL is restored.
            before_graphql = inventory_graphql(restored, 'before-source-graphql-prerequisite')
            graphql_sql = graphql_restore_plan(graphql_scope, before_graphql)
            record['graphql_wrapper_restore_prerequisite'] = dict(
                admitted_source_scope=graphql_scope, before=before_graphql,
                sql=graphql_sql, sql_sha256=sha(graphql_sql.encode()),
                source_extension_member_definition_omitted_by_archive=True,
                source_schema_CREATE_TOC_explicitly_preinstalled=True,
                all_wrapper_ACLs_restored_from_archive=True,
                full_catalog_comparison_not_relaxed=True)
            if graphql_sql:
                restored.sql(graphql_sql, user='supabase_admin',
                             label='exact frozen source GraphQL schema wrapper and proven extension membership prerequisite')
            after_graphql = inventory_graphql(restored, 'after-source-graphql-prerequisite')
            case('exact source GraphQL wrapper metadata and extension membership verified before archive ACL',
                 graphql_restore_plan(graphql_scope, after_graphql) == '')
            toc = restored.tool('pg_restore', ['--list'], read(dump_path)).stdout.decode()
            record['exact_extension_object_index_archive_omission_proof'] = compatibility_archive_proof(committed, toc, sealed_dump(dump_path, record['dump_seal']['sha256']))
            listing, omitted = restore_list(toc, committed, graphql_scope)
            list_path = report / 'full-restore-list.txt'; list_path.write_text(listing)
            # The allow-list is copied only into this labelled, networkless
            # container; the archive continues to arrive on stdin.
            runner.call([DOCKER, 'cp', str(list_path), restored.name + ':/tmp/collect-full-restore-list.txt'])
            record['restore_scope'] = dict(role='supabase_admin', local_fixture_only=True,
                archive_sha256=sha(read(dump_path)), list_sha256=sha(listing.encode()),
                explicitly_preinstalled_toc_entries=omitted,
                all_application_objects_data_history_and_acls_retained=True,
                image_and_source_role_globals_and_extension_members_explicit_prerequisites=True,
                shipping_postgres_admission_operations=['query', 'migration'], shipping_restore_not_admitted=True)
            # Seal failure prevents sending corrupted archive bytes to a target.
            corrupt = bytearray(read(dump_path)); corrupt[-1] ^= 1
            corrupt_path = report / 'deliberately-corrupt-synthetic.dump'; corrupt_path.write_bytes(corrupt)
            try:
                sealed_dump(corrupt_path, record['dump_seal']['sha256'])
            except Refused as error:
                case('corrupt dump negative rejects changed content before restore', str(error) == 'DUMP_CONTENT_SEAL_CHANGED')
            else:
                raise AssertionError('Corrupt archive was admitted')
            finally:
                corrupt_path.unlink()
            restored.tool('pg_restore', ['--exit-on-error', '--no-password', '--username=supabase_admin', '--dbname=postgres', '--use-list=/tmp/collect-full-restore-list.txt'], sealed_dump(dump_path, record['dump_seal']['sha256']))
            restored.sql('alter role postgres nosuperuser;', user='supabase_admin', label='end explicit privileged local restore before any forward migration')
            ordinary(restored)
            before_metadata, _ = catalog(restored, 'before-compatibility-repairs', [i['version'] for i in items[:124]])
            repair = compatibility_plan(committed, before_metadata, compatibility_scope)
            record['compatibility_repair_plan'] = repair
            # Fingerprints bracket only the two bounded compatibility SQL
            # transactions. No source rows or migration history are rewritten.
            before_repair = replay.fingerprints(restored, reference['preserved_columns'])
            record['fresh_before_compatibility_fingerprints'] = before_repair
            case('all18 restored projections equal committed source immediately before compatibility repairs',
                 projection_parity(before_repair, preserved))
            if repair['admin_sql']:
                restored.sql(repair['admin_sql'], user='supabase_admin', label='exact captured GraphQL grants and source extension-table index prerequisite')
                restored.sql(repair['postgres_sql'], label='transactional exact original BETWEEN CHECK parity restoration with original validation flags')
            after_repair = replay.fingerprints(restored, reference['preserved_columns'])
            record['fresh_after_compatibility_fingerprints'] = after_repair
            case('all18 committed projections survive compatibility repairs immediately after both transactions',
                 projection_parity(after_repair, preserved) and projection_parity(after_repair, before_repair))
            roundtrip, _ = catalog(restored, 'restored-predecessor', [i['version'] for i in items[:124]])
            after_constraints = [row for row in roundtrip['constraints'] if row[2] in
                ('notification_events_copy_length_check', 'provider_finality_requests_provider_network_check')]
            case('both CHECK identities validation flags and exact source definition hashes verified before continuing',
                 after_constraints == compatibility_scope['source_constraints'])
            case('complete restored predecessor catalog and effective ACLs exactly equal committed source', roundtrip == committed)
            fresh = replay.fingerprints(restored, reference['preserved_columns'])
            record['fresh_restored_predecessor_fingerprints'] = fresh
            case('all18 committed projection hashes exactly survive independent restore', fresh == preserved)
            safeguards(restored)
            # A real reversible wrong-ACL fault is observed from a read-only
            # catalog in the same transaction; rollback is only this fault probe.
            probe = restored.json("begin;grant select on public.payments to anon;" + read(candidate / CATALOG).decode().replace('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;', '').replace('COMMIT;', '') + 'rollback;')
            case('wrong ACL negative differs from full predecessor catalog', probe != committed)
            again, _ = catalog(restored, 'after-negative-rollback', [i['version'] for i in items[:124]])
            case('wrong ACL probe rollback restores exact predecessor before forward replay', again == committed)
            apply(restored, items[124:], preserved)
            final, final_body = catalog(restored, 'final209', [i['version'] for i in items])
            case('all85 original forward migrations execute as postgres NOSUPERUSER', len(restored.evidence['migrations']) == 85 and all(m['authority']['superuser'] is False for m in restored.evidence['migrations']))
            case('complete final209 catalog and effective ACLs equal actual sealed current209 reference', final == reference_final and sha(final_body) == FINAL_SHA)
            record['fresh_final_fingerprints'] = replay.fingerprints(restored, reference['preserved_columns'])
            case('all18 fresh committed projection hashes survive every forward migration', record['fresh_final_fingerprints'] == preserved)
            safeguards(restored)
        case('both independently owned containers removed', all(t.evidence.get('task_container_removed') for t in targets))
        freeze(); case('all216 admitted inputs and sealed reference remain unchanged')
        record['status'] = 'pass'
    except BaseException as error:
        record.update(status='failed', failure=str(error)); save(); raise
    finally:
        # Cleanup uses the reserved minute inside the same whole600 bound.
        runner.deadline = whole_deadline
        cleanup_errors = []
        for target in targets:
            try:
                target.close()
            except BaseException as error:
                cleanup_errors.append(dict(name=target.name, error=str(error)))
        record['cleanup_errors'] = cleanup_errors
        record['all_task_containers_removed'] = not cleanup_errors and all(t.evidence.get('task_container_removed') for t in targets)
        if cleanup_errors:
            record['status'] = 'failed'
        record['completed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat(); save()
        record['elapsed_seconds'] = time.monotonic() - started
        save()
    return 0 if record['status'] == 'pass' else 1


if __name__ == '__main__':
    raise SystemExit(main())
