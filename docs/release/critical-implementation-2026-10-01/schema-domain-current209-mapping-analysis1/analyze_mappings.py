#!/usr/bin/env python3
"""Private current209 source-lineage evidence; never executes SQL or alters the map."""
import hashlib
import importlib.util
import json
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RELEASE = HERE.parent
BASELINE = RELEASE / 'root-schema-drop-lineage-correction1'
BASELINE_SHA = '957df417426e5f23cc0249a29a5ff50191444260d266e8f7c8a89f801ed18cd8'
GENERATED = BASELINE / 'generated-current209-maintained1'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return pathlib.Path(path).read_bytes()


def document(path):
    return json.loads(read(path))


def save(name, value):
    with (HERE / name).open('x') as stream:
        json.dump(value, stream, sort_keys=True, indent=2)
        stream.write('\n')


def admit_inputs():
    raw = read(BASELINE / 'packet-files.json')
    if digest(raw) != BASELINE_SHA:
        raise ValueError('sealed maintained49 baseline manifest drift')
    packet = json.loads(raw)
    if any(digest(read(BASELINE / row['path'])) != row['sha256'] or len(read(BASELINE / row['path'])) != row['bytes'] for row in packet['files']):
        raise ValueError('sealed maintained49 baseline leaf drift')
    manifest = document(GENERATED / 'input-manifest.json')
    rows = manifest['inputs']
    # A migration is also a maintained SQL caller input; preserve both roles.
    if len(rows) != 1091 or len({(r['kind'], r['path']) for r in rows}) != len(rows):
        raise ValueError('exact current209 input cohort differs')
    for row in rows:
        if digest(read(ROOT / row['path'])) != row['sha256']:
            raise ValueError('current input drift: ' + row['path'])
    return rows


def load_mapper(rows):
    row = next(r for r in rows if r['kind'] == 'generator-proposal')
    spec = importlib.util.spec_from_file_location('admitted_mapper49', ROOT / row['path'])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def signature(mapper, value):
    # Only this explicitly reviewed PostgreSQL builtin alias is added privately.
    value = re.sub(r'\btimestamptz\b', 'timestamp with time zone', value)
    text = '(' + value + ')'
    result, _ = mapper.sql_signature(text, mapper.lex(text, sql=True), 0)
    if result is None:
        raise ValueError('unknown input signature')
    return result


def named_arguments(mapper, value):
    signature(mapper, value)
    parts = value.split(',') if value else []
    names = []
    for part in parts:
        match = re.fullmatch(r'\s*(p_[a-z][a-z_0-9]*)\s+(.+?)\s*', part)
        if not match:
            raise ValueError('only explicit safe named IN arguments admitted')
        names.append(match[1])
    if len(set(names)) != len(names):
        raise ValueError('duplicate input argument')
    return names


def original_arguments(text, definition):
    start = definition['definition_offset']
    header = text[start:definition['body_offset']]
    found = re.search(r'\((.*?)\)\s*returns\s+jsonb\b', header, re.I | re.S)
    if not found:
        raise ValueError('roster predecessor is not explicit RETURNS jsonb')
    return found[1]


def roster_template(text):
    entry = re.search(r'entries text\[\]:=array\[(.*?)\];', text, re.S)
    ddl = re.search(r'execute format\(\$ddl\$(.*?)\$ddl\$,f.proname,f.declaration,guard_sql,alias_name,arguments\);', text, re.S)
    expiry = re.search(r'guard_sql:=guard_sql\|\|\$expiry\$(.*?)\$expiry\$;', text, re.S)
    if not entry or not ddl or not expiry:
        raise ValueError('unknown roster installer template')
    entries = re.findall(r"'([a-z_0-9]+)'", entry[1])
    if len(entries) != 14 or len(set(entries)) != 14:
        raise ValueError('unknown or duplicate roster entrypoint cohort')
    wrapper = re.search(r'as \$fn\$(.*?)\$fn\$', ddl[1], re.S)
    if not wrapper or wrapper[1].count('%s') != 2 or wrapper[1].count('%I') != 1:
        raise ValueError('unknown wrapper format placeholders')
    return entries, wrapper[1], expiry[1]


def wrapper_body(name, args, template, expiry):
    if not re.fullmatch(r'[a-z_][a-z_0-9]*', name):
        raise ValueError('unreviewed quoted function identifier')
    if 'p_import_id' in args:
        service = name in ('complete_roster_import_preview', 'fail_roster_import_preview')
        guard = 'perform collect_hybrid.' + ('guard_roster_service_recovery' if service else 'roster_recovery_leaf')
        guard += '(p_import_id' + ('' if service else ',false' if name == 'admin_get_roster_import' else ',true') + ');'
    elif name == 'admin_execute_roster_import_intent':
        guard = 'perform collect_hybrid.roster_recovery_leaf((select import_id from collect_hybrid.roster_import_recovery_intents where request_id=p_request_id),true);'
    elif name == 'admin_recover_roster_import':
        guard = 'perform collect_hybrid.roster_recovery_leaf((select id from collect_hybrid.roster_import_sources where request_id=p_upload_request_id),false);'
    elif 'p_request_id' in args:
        guard = 'perform collect_hybrid.guard_roster_service_recovery((select id from collect_hybrid.roster_import_sources where request_id=p_request_id));'
    elif 'p_reservation_id' in args:
        guard = 'perform collect_hybrid.guard_roster_service_recovery((select s.id from collect_hybrid.roster_import_sources s join collect_hybrid.roster_resource_reservations r on r.request_id=s.request_id where r.id=p_reservation_id));'
    else:
        raise ValueError('unknown roster guard branch')
    if name.startswith('admin_'):
        guard = 'perform collect_hybrid.require_roster_caller(); ' + guard
    if name == 'admin_get_roster_import':
        guard += expiry
    # All admitted names are simple identifiers; PostgreSQL quote_ident leaves them unchanged.
    body = template.replace('%s', guard, 1).replace('%I', name + '_guarded_149', 1).replace('%s', ','.join(args), 1)
    if '%' in body:
        raise ValueError('unconsumed PostgreSQL format placeholder')
    return body


def do_blocks(mapper, text):
    tokens = mapper.lex(text, sql=True)
    return [(tokens[i + 1].value, tokens[i + 1].start) for i, token in enumerate(tokens[:-1])
            if token.kind == 'id' and token.value.lower() == 'do' and tokens[i + 1].kind == 'string']


def literal_expression(mapper, expression, needle=None):
    tokens = mapper.lex(expression, sql=True)
    if needle is not None and len(tokens) >= 3 and tokens[0].value == 'needle' and [t.value for t in tokens[1:3]] == ['|', '|']:
        return needle + literal_expression(mapper, expression[tokens[3].start:])
    if len(tokens) == 1 and tokens[0].kind == 'string':
        return tokens[0].value
    if len(tokens) == 2 and tokens[0].value == 'E' and tokens[1].kind == 'string':
        # The actual admitted expression uses only \n; other escape languages refuse.
        value = tokens[1].value
        if re.search(r'\\(?!n)', value):
            raise ValueError('unreviewed E-string escape')
        return value.replace('\\n', '\n')
    raise ValueError('nonliteral patch expression')


def assignment(mapper, block, name, needle=None):
    tokens = mapper.lex(block, sql=True)
    found = []
    for i, token in enumerate(tokens):
        if token.kind != 'id' or token.value != name:
            continue
        j = i + 1
        if j < len(tokens) and tokens[j].value == 'text':
            j += 1
        if [t.value for t in tokens[j:j + 2]] != [':', '=']:
            continue
        j += 2
        end = next((t.start for t in tokens[j:] if t.kind == 'symbol' and t.value == ';'), None)
        if end is None:
            raise ValueError('unterminated literal assignment')
        found.append(literal_expression(mapper, block[tokens[j].start:end], needle))
    if len(found) != 1:
        raise ValueError('missing or multiple patch assignment')
    return found[0]


def patch_parts(mapper, block):
    refs = re.findall(r"body:=pg_get_functiondef\('([a-z_0-9]+\.[a-z_0-9]+\([^']*\))'::regprocedure\);", block)
    if len(refs) != 1 or not re.search(r'execute replace\(body,needle,replacement\);', block):
        raise ValueError('unknown function patch operation')
    ref = re.fullmatch(r'([a-z_0-9]+)\.([a-z_0-9]+)\((.*)\)', refs[0])
    needle = assignment(mapper, block, 'needle')
    replacement = assignment(mapper, block, 'replacement', needle)
    return (ref[1], ref[2], signature(mapper, ref[3])), needle, replacement


def apply_patch_exact(body, needle, replacement):
    if not needle or body.count(needle) != 1:
        raise ValueError('patch needle absent or repeated')
    return body.replace(needle, replacement)


def analyze(mapper):
    catalog_paths = [ROOT / row['path'] for row in document(GENERATED / 'input-manifest.json')['inputs'] if row['kind'] == 'effective-catalog']
    catalog = document(catalog_paths[0])
    if read(catalog_paths[0]) != read(catalog_paths[1]) or len(catalog['migrations']) != 209:
        raise ValueError('current209 peers differ')
    gaps = [r for r in document(GENERATED / 'gaps.json')['function_body_match_review']
            if not r['resolved'] and r['source_scope'] == 'application-schema-or-public']
    if len(gaps) != 34:
        raise ValueError('admitted unresolved application cohort differs')
    wanted = {r['identity']: r for r in gaps}
    functions = {mapper.function_id(r): r for r in catalog['functions']}
    records = {}
    texts = {}
    definitions = {}
    migration_rows = [row for row in document(GENERATED / 'input-manifest.json')['inputs'] if row['kind'] == 'original-migration']
    admitted_paths = {row['path'] for row in migration_rows}
    actual_paths = {path.relative_to(ROOT).as_posix() for path in (ROOT / 'supabase/migrations').glob('*.sql')}
    if actual_paths != admitted_paths or {row['version'] for row in migration_rows} != set(catalog['migrations']):
        raise ValueError('source migration membership differs from admitted current209')
    for path in sorted(ROOT / name for name in admitted_paths):
        relative = path.relative_to(ROOT).as_posix()
        text = read(path).decode()
        texts[relative] = text
        for d in mapper.sql_definitions(text, relative, path.name[:14]):
            definitions.setdefault((d['schema'], d['name']), []).append(d)

    def latest(schema, name, before):
        candidates = [d for d in definitions.get((schema, name), []) if d['version'] < before]
        if not candidates:
            raise ValueError('missing literal predecessor')
        return max(candidates, key=lambda d: (d['version'], d['definition_offset']))

    def add(identity, category, predecessor, body, steps):
        if identity not in wanted or identity in records:
            raise ValueError('extra or repeated mapping')
        row = functions[identity]
        if digest(body.encode()) != wanted[identity]['required_final_prosrc_sha256'] or row[11] != digest(body.encode()):
            raise ValueError('final exact catalog body hash mismatch: ' + identity)
        source_signature = predecessor['signature_types']
        if source_signature is None:
            # The maintained parser conservatively leaves timestamptz unresolved.
            source_arguments = original_arguments(texts[predecessor['path']], predecessor)
            source_signature = signature(mapper, source_arguments)
            if named_arguments(mapper, source_arguments) != named_arguments(mapper, row[2]):
                raise ValueError('patched function argument-name change')
            predecessor = {**predecessor, 'signature_types': source_signature,
                           'original_parser_signature_types': None,
                           'private_signature_normalization': 'explicit builtin timestamptz -> timestamp with time zone'}
        if tuple(source_signature) != signature(mapper, row[2]) or row[3] != 'f':
            raise ValueError('function kind or exact input signature differs')
        records[identity] = dict(identity=identity, category=category,
            catalog_owner_observed=row[4], catalog_row=row, original_definition={k:v for k,v in predecessor.items() if k not in ('body', 'body_offset', 'definition_offset')},
            transformation_steps=steps, reconstructed_prosrc=body, reconstructed_prosrc_sha256=digest(body.encode()),
            exact_final_catalog_prosrc_match=True, maintained_mapping_changed=False, business_owner_acceptance=False)

    prefix = 'supabase/migrations/'
    roster_path = prefix + '20260930170000_roster_fresh_auth_recovery.sql'
    entries, template, expiry = roster_template(texts[roster_path])
    prior_paths = [path for path in texts if pathlib.Path(path).name[:14] < '20260930170000']
    defs = [d for values in definitions.values() for d in values if d['path'] in prior_paths]
    alterations = [a for path in prior_paths for a in mapper.sql_static_alterations(texts[path], path, pathlib.Path(path).name[:14])]
    state = mapper.sql_static_lineage(defs, alterations)
    for name in entries:
        sources = [d for (schema, short, _), d in state.items() if schema == 'public' and short == name]
        if len(sources) != 1:
            raise ValueError('unknown or multiple installer overloads')
        d = sources[0]
        args = named_arguments(mapper, original_arguments(texts[d['path']], d))
        for schema, short, category, body in (
                ('collect_hybrid', name + '_guarded_149', 'roster-preserved-private-alias', d['body']),
                ('public', name, 'roster-public-guard-wrapper', wrapper_body(name, args, template, expiry))):
            candidates = [identity for identity in wanted if functions[identity][:2] == [schema, short]]
            if not candidates:
                continue  # verify_roster_source_integrity private alias was later literally replaced.
            if len(candidates) != 1 or named_arguments(mapper, functions[candidates[0]][2]) != args:
                raise ValueError('unknown final overload or argument-name change')
            steps = [*d['static_lineage'], dict(path=roster_path, line=texts[roster_path][:texts[roster_path].index('do $install$')].count('\n') + 1, operation=category,
                installer_sha256=digest(texts[roster_path].encode()), entrypoint=name, private_alias=name + '_guarded_149', signature_types=d['signature_types'])]
            add(candidates[0], category, d, body, steps)

    copy_path = prefix + '20261001140000_receipt_deferral_exceptions.sql'
    for short, base in (('receipt_exception_base_refresh_source', 'refresh_source'), ('receipt_exception_base_transaction_sms_id', 'transaction_sms_id')):
        d = latest('collect_ops', base, '20261001140000')
        proof = "execute replace(body,'FUNCTION collect_ops." + base + "(', 'FUNCTION collect_ops." + short + "(');"
        if texts[copy_path].count(proof) != 1:
            raise ValueError('unknown exact definition-copy header replacement')
        # A header rename must not replace a second occurrence inside prosrc.
        if ('FUNCTION collect_ops.' + base + '(') in d['body']:
            raise ValueError('definition-copy replacement also changes prosrc')
        candidates = [identity for identity in wanted if functions[identity][:2] == ['collect_ops', short]]
        if len(candidates) != 1:
            raise ValueError('copied function identity missing or ambiguous')
        add(candidates[0], 'receipt-exact-header-definition-copy', d, d['body'],
            [dict(path=copy_path, line=texts[copy_path][:texts[copy_path].index(proof)].count('\n') + 1, operation='exact-header-copy', source_schema='collect_ops', source_name=base, destination_name=short)])

    patched = [r for r in gaps if r['identity'] not in records]
    states = {}
    for r in patched:
        row = functions[r['identity']]
        d = latest(row[0], row[1], '99999999999999')
        states[(row[0], row[1], signature(mapper, row[2]))] = [r['identity'], d, d['body'], []]
    patch_paths = [prefix + n for n in ('20261001140000_receipt_deferral_exceptions.sql', '20261001210000_receipt_worker_bounded_sweep.sql', '20261002080000_receipt_repeat_run_recovery.sql')]
    for path in patch_paths:
        text = texts[path]
        for block, offset in do_blocks(mapper, text):
            if 'execute replace(body,needle,replacement);' not in block:
                continue
            starts = [m.start() for m in re.finditer(r'body:=pg_get_functiondef\(', block)]
            chunks = [block] if len(starts) == 1 else [block[s:(starts[i + 1] if i + 1 < len(starts) else len(block))] for i, s in enumerate(starts)]
            for chunk in chunks:
                key, needle, replacement = patch_parts(mapper, chunk)
                if key not in states:
                    continue
                identity, d, body, steps = states[key]
                if d['version'] >= pathlib.Path(path).name[:14]:
                    raise ValueError('patch is not after literal predecessor')
                before_sha = digest(body.encode())
                after = apply_patch_exact(body, needle, replacement)
                steps.append(dict(path=path, line=text[:offset].count('\n') + 1, operation='exact-once-literal-body-replacement',
                    needle=needle, replacement=replacement, before_prosrc_sha256=before_sha, after_prosrc_sha256=digest(after.encode())))
                states[key][2] = after
    for identity, d, body, steps in states.values():
        if not steps:
            raise ValueError('no literal patch lineage')
        add(identity, 'receipt-exact-literal-body-patches', d, body, steps)
    if set(records) != set(wanted):
        raise ValueError('omitted final application mapping')
    return dict(format='private-current209-function-source-analysis-v1',
        status='exact-body-evidence-proposal-only', application_gap_count=34,
        categories={name:sum(r['category'] == name for r in records.values()) for name in sorted({r['category'] for r in records.values()})},
        catalog_sha256=digest(read(catalog_paths[0])), catalog_categories=len(catalog), catalog_function_count=len(catalog['functions']),
        mappings=[records[k] for k in sorted(records)], platform_gaps_remaining=91,
        maintained_mapping_changed=False, catalog_hash_scope_unchanged=True, SQL_evaluated=False,
        runtime_call_graph_complete=False, business_owner_acceptance=False, BE08_complete=False)


def main():
    before = admit_inputs()
    mapper = load_mapper(before)
    result = analyze(mapper)
    after = admit_inputs()
    if before != after:
        raise ValueError('input cohort changed during analysis')
    save('input-readback.json', dict(baseline_manifest_sha256=BASELINE_SHA, input_count=len(before), before_after_exact=True,
        source_input_manifest_sha256=digest(read(GENERATED / 'input-manifest.json')), bound_inputs=before))
    save('mapping-analysis.json', result)
    print(json.dumps({k:v for k,v in result.items() if k != 'mappings'}, sort_keys=True))


if __name__ == '__main__':
    main()
