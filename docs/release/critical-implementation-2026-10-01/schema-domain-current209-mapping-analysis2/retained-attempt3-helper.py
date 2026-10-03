"""Source-derived evidence for four explicitly reviewed migration programs only."""
import re

def signature(mapper, value):
    # Only this explicitly reviewed PostgreSQL builtin alias is added privately.
    raw_tokens = mapper.lex('(' + value + ')', sql=True)
    if any(t.value == '.' or (t.kind == 'id' and ('(' + value + ')')[t.start:t.start+1] == '"') for t in raw_tokens):
        raise ValueError('qualified or quoted type/argument expression refused before alias normalization')
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


REVIEWED_PROGRAMS = {
    'supabase/migrations/20260930170000_roster_fresh_auth_recovery.sql': '53e5591e5901acc345101c5113a0c75b7b993011b5743119a59f52c883ceb00d',
    'supabase/migrations/20261001140000_receipt_deferral_exceptions.sql': '2bee8ec6bc4cb4323366badb6886987bf364072ee4562fa6751fc0dff6ff1d16',
    'supabase/migrations/20261001210000_receipt_worker_bounded_sweep.sql': '5a242eb7f80a92879f3164c23d3b66d34315f20d1674c6ba7cb31d51ec0b64a5',
    'supabase/migrations/20261002080000_receipt_repeat_run_recovery.sql': '7c71dd8eb98e42f7aaf1697715277b5fcc245ce7ff7982f99f200c0f0ed07998',
}
PATCH_TARGETS = {
    ('collect_ops', 'queue_receipt_exception_source'),
    ('collect_ops', 'receipt_exception_quota_available'),
    ('collect_ops', 'capture_receipt_backlog_budget_refusal'),
    ('public', 'receipt_operations_execute_v2'),
    ('public', 'admin_list_receipt_operation_evidence_v1'),
}


class LineageResult(dict):
    def __init__(self, final, uncertainty):
        super().__init__((key, value) for key, value in final.items() if value.get('source_transformations'))
        self.validated_static_lineage = {key:value for key,value in final.items() if not value.get('source_transformations')}
        self.uncertainty = uncertainty


def unsupported_alter_fences(mapper, text, path, version):
    tokens = mapper.lex(text, sql=True); result = []
    for i, token in enumerate(tokens):
        if token.kind != 'id' or token.value.lower() != 'alter' or i+2 >= len(tokens) or tokens[i+1].value.lower() != 'function':
            continue
        j = i+2
        if tokens[j].kind != 'id':
            result.append(dict(operation='drop-all', names=[], statement_offset=token.start)); continue
        schema, name = None, mapper.sql_identifier(text, tokens[j]); j += 1
        if j+1 < len(tokens) and tokens[j].value == '.' and tokens[j+1].kind == 'id':
            schema, name = name, mapper.sql_identifier(text, tokens[j+1]); j += 2
        types, closing = mapper.sql_signature(text, tokens, j)
        if types is not None and schema is not None:
            continue
        names = [(schema, name)]
        tail = tokens[closing+1:closing+4]
        if len(tail) == 3 and tail[2].kind == 'id':
            if [t.value.lower() for t in tail[:2]] == ['rename', 'to']:
                names.append((schema, mapper.sql_identifier(text, tail[2])))
            elif [t.value.lower() for t in tail[:2]] == ['set', 'schema']:
                names.append((mapper.sql_identifier(text, tail[2]), name))
        result.append(dict(operation='drop-names', names=names, statement_offset=token.start))
    return [{**r, 'path':path, 'version':version, 'line':text[:r['statement_offset']].count('\n')+1,
             'reason':'unsupported-active-ALTER-signature'} for r in result]


def finite_copy_scope(block):
    # Recognize effects, not body lineage, for this complete single-variable
    # pg_get_functiondef / literal qualified-name substitution / EXECUTE grammar.
    qualified = r'[a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*'
    pattern = (r"\s*declare\s+(?P<v>[a-z_][a-z_0-9]*)\s+text\s*;\s*begin\s+select\s+pg_get_functiondef\('"
        r"(?P<source>"+qualified+r")\([^']*\)'::regprocedure\)\s*into\s+(?P=v)\s*;\s*"
        r"(?P=v):=replace\((?P=v),'(?P=source)','(?P<destination>"+qualified+r")'\)\s*;\s*"
        r"execute\s+(?P=v)\s*;\s*end\s*")
    match = re.fullmatch(pattern, block, re.I | re.S)
    if not match:
        return None
    return [tuple(match[name].split('.')) for name in ('source', 'destination')]


def dynamic_operation_fences(mapper, text, path, version):
    """Opaque/unproved effects taint all; no final body hash removes that taint."""
    tokens = mapper.lex(text, sql=True); result = []
    for i, token in enumerate(tokens):
        if token.kind != 'id' or token.value.lower() not in {'do', 'execute'}:
            continue
        # Only command starts are active top-level operations. ON CONFLICT DO
        # and CREATE TRIGGER ... EXECUTE FUNCTION do not execute function DDL.
        if i and tokens[i-1].value != ';':
            continue
        if token.value.lower() == 'execute':
            result.append(dict(operation='drop-all', names=[], statement_offset=token.start,
                reason='unreviewed-top-level-EXECUTE')); continue
        if i+1 >= len(tokens) or tokens[i+1].kind != 'string':
            raise ValueError('unreviewed DO syntax or unterminated block')
        block_token = tokens[i+1]
        raw_block = text[block_token.start:block_token.end]
        delimiter = re.match(r'\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$', raw_block)
        if not delimiter or not raw_block.endswith(delimiter[0]) or i+2 >= len(tokens) or tokens[i+2].value != ';':
            raise ValueError('unreviewed DO syntax or unterminated block')
        block = block_token.value; inner = mapper.lex(block, sql=True)
        finite = finite_copy_scope(block)
        if finite is not None:
            result.append(dict(operation='drop-names', names=finite, statement_offset=token.start,
                reason='unreviewed-function-definition-copy-effects')); continue
        executes = [j for j,t in enumerate(inner) if t.kind == 'id' and t.value.lower() == 'execute']
        def function_ddl(tokens):
            for k,t in enumerate(tokens):
                if t.kind != 'id' or t.value.lower() not in {'create','alter','drop'}:
                    continue
                k += 1
                if [v.value.lower() for v in tokens[k:k+2]] == ['or','replace']:
                    k += 2
                if k < len(tokens) and tokens[k].value.lower() in {'function','procedure'}:
                    return True
            return False
        active_function_ddl = function_ddl(inner)
        uncertain = active_function_ddl
        for j in executes:
            end = next((k for k in range(j+1,len(inner)) if inner[k].kind == 'symbol' and inner[k].value == ';'),len(inner))
            expression = inner[j+1:end]
            literal = expression[0].value if expression and expression[0].kind == 'string' else None
            formatted = len(expression)>2 and expression[0].value.lower() == 'format' and expression[1].value == '(' and expression[2].kind == 'string'
            if formatted:
                literal = expression[2].value
                # No concatenation, nested call, subquery or other evaluated
                # argument expression supplies an admitted effect bound.
                if expression[-1].value != ')' or any(t.value in {'(',')','|','+','-'} for t in expression[3:-1]):
                    uncertain = True
            elif len(expression) != 1:
                uncertain = True
            if literal is None:
                uncertain = True; continue
            sql_tokens = mapper.lex(literal, sql=True)
            # Function DDL inside executable SQL is opaque to the maintained
            # parser. SQL-fragment %s and unknown format placeholders can expand
            # into further statements, so their entire effects remain unproved.
            placeholders = re.findall(r'%(?:\d+\$)?([A-Za-z%])', literal)
            if function_ddl(sql_tokens) or (formatted and any(p not in {'I','L','%'} for p in placeholders)):
                uncertain = True
            # Only a single metadata ACL/comment command has an admitted
            # non-body effect. Other DDL/DML or a nested DO/CALL remains opaque.
            elif not sql_tokens or sql_tokens[0].value.lower() not in {'grant','revoke','comment'}:
                uncertain = True
            elif any(t.value == ';' for t in sql_tokens[:-1]):
                uncertain = True
            elif '%' in literal and not formatted:
                uncertain = True
        if uncertain:
            result.append(dict(operation='drop-all', names=[], statement_offset=token.start,
                reason='unreviewed-intervening-dynamic-function-effects'))
    return [{**r, 'path':path, 'version':version, 'line':text[:r['statement_offset']].count('\n')+1} for r in result]


def reviewed_transform_lineage(mapper, sources, definitions, alterations):
    """No SQL evaluation: exact reviewed programs + literal predecessors + order."""
    normalized = []
    for d in definitions:
        if d['signature_types'] is None and (d['schema'], d['name']) in {
                ('public', 'receipt_operations_execute_v2'),
                ('public', 'admin_list_receipt_operation_evidence_v1')}:
            args = original_arguments(sources[d['path']]['text'], d)
            d = {**d, 'signature_types': signature(mapper, args),
                 'original_parser_signature_types': None,
                 'signature_normalization': 'explicit builtin timestamptz -> timestamp with time zone'}
        normalized.append(d)
    # An unsupported later declaration may be an overload replacement. Preserve
    # uncertainty for every signature under that name instead of retaining an
    # older reconstructed candidate. The maintained parser/engine are unchanged.
    conservative_alterations = [*alterations, *[
        dict(path=d['path'], line=d['line'], version=d['version'],
             statement_offset=d['definition_offset'], schema=d['schema'], name=d['name'],
             signature_types=None, operation='drop-name', destination=None)
        for d in normalized if d['routine_kind'] == 'function' and d['signature_types'] is None]]
    uncertainty = []
    for path, source in sorted(sources.items()):
        fences = unsupported_alter_fences(mapper, source['text'], path, source['version'])
        if path not in REVIEWED_PROGRAMS:
            fences += dynamic_operation_fences(mapper, source['text'], path, source['version'])
        uncertainty.extend({**f, 'source_migration_sha256':source['sha256']} for f in fences)
    # Expand an unbounded operation to every known short name, including names
    # introduced by reviewed programs. A later literal declaration can supply
    # new evidence, but equality of a final hash never revives a removed chain.
    known_names = {d['name'] for d in normalized} | {a['name'] for a in alterations}
    known_names |= {a['destination'] for a in alterations if a['operation'] == 'rename'}
    known_names |= {name + '_guarded_149' for name in known_names}
    known_names |= {'receipt_exception_base_refresh_source', 'receipt_exception_base_transaction_sms_id',
                    'receipt_transport_base_schedule'}
    for fence in uncertainty:
        names = [(None, name) for name in sorted(known_names)] if fence['operation'] == 'drop-all' else fence['names']
        for schema, name in names:
            conservative_alterations.append(dict(path=fence['path'], line=fence['line'], version=fence['version'],
                statement_offset=fence['statement_offset'], schema=schema, name=name, signature_types=None,
                operation='drop-name', destination=None))
    derived = []

    def state_before(version, offset):
        defs = [d for d in normalized + derived if (d['version'], d['definition_offset']) < (version, offset)]
        alts = [a for a in conservative_alterations if (a['version'], a['statement_offset']) < (version, offset)]
        return mapper.sql_static_lineage(defs, alts)

    def predecessor(state, schema, name, types=None):
        found = [d for (s, n, t), d in state.items() if (s, n) == (schema, name) and (types is None or t == types)]
        if len(found) != 1 or found[0]['routine_kind'] != 'function' or found[0]['signature_types'] is None:
            raise ValueError('reviewed transform predecessor missing, invalidated or ambiguous')
        return found[0]

    def admitted_predecessor(state, schema, name, path, offset, types=None):
        try:
            return predecessor(state, schema, name, types)
        except ValueError as error:
            uncertainty.append(dict(path=path, version=sources[path]['version'], statement_offset=offset,
                line=sources[path]['text'][:offset].count('\n')+1, operation='reviewed-transform-withheld',
                names=[(schema,name)], reason=str(error)))
            return None

    def emit(source, schema, name, body, path, offset, operation, **details):
        before = mapper.sha(source['body'].encode())
        after = mapper.sha(body.encode())
        proof = dict(path=path, line=sources[path]['text'][:offset].count('\n') + 1,
                     source_migration_sha256=sources[path]['sha256'], operation=operation,
                     source_identity=[source['schema'], source['name'], source['signature_types']],
                     destination_identity=[schema, name, source['signature_types']],
                     before_prosrc_sha256=before, after_prosrc_sha256=after, **details)
        original = source.get('original_definition', {k:v for k,v in source.items()
            if k not in {'body', 'body_offset', 'definition_offset'}})
        result = {**source, 'schema':schema, 'name':name, 'body':body, 'prosrc_sha256':after,
                  'path':path, 'line':proof['line'], 'version':sources[path]['version'],
                  'definition_offset':offset, 'body_offset':None,
                  'declaration_sha256':None, 'declaration_kind':'reviewed-reconstructed-body',
                  'original_definition':original,
                  'source_transformations':[*source.get('source_transformations', []), *source.get('static_lineage', []), proof],
                  'SQL_evaluation_performed':False}
        derived.append(result)
        return result

    for path, expected in sorted(REVIEWED_PROGRAMS.items()):
        if path not in sources:
            continue
        source = sources[path]
        if source['sha256'] != expected:
            raise ValueError('reviewed dynamic program changed; new lineage review required: ' + path)
        text, version = source['text'], source['version']
        if version == '20260930170000':
            entries, template, expiry = roster_template(text)
            offset = text.index('do $install$')
            state = state_before(version, offset)
            for name in entries:
                d = admitted_predecessor(state, 'public', name, path, offset)
                if d is None:
                    continue
                args = named_arguments(mapper, original_arguments(sources[d['path']]['text'], d))
                alias = name + '_guarded_149'
                if any(key[:2] == ('collect_hybrid', alias) for key in state):
                    raise ValueError('reviewed roster alias destination collision')
                emit(d, 'collect_hybrid', alias, d['body'], path, offset,
                     'reviewed-roster-move-rename', source_parameter_names=args)
                emit(d, 'public', name, wrapper_body(name, args, template, expiry), path, offset,
                     'reviewed-roster-guard-template', source_parameter_names=args)
            continue
        for block, offset in do_blocks(mapper, text):
            if 'execute replace(body,needle,replacement);' not in block:
                if version != '20261001140000':
                    continue
                for source_name, destination in [('refresh_source', 'receipt_exception_base_refresh_source'),
                                                  ('transaction_sms_id', 'receipt_exception_base_transaction_sms_id')]:
                    proof = "execute replace(body,'FUNCTION collect_ops." + source_name + "(', 'FUNCTION collect_ops." + destination + "(');"
                    if proof not in block:
                        continue
                    state = state_before(version, offset)
                    d = admitted_predecessor(state, 'collect_ops', source_name, path, offset, ('text', 'uuid'))
                    if d is None:
                        continue
                    if ('FUNCTION collect_ops.' + source_name + '(') in d['body'] or any(key[:2] == ('collect_ops', destination) for key in state):
                        raise ValueError('definition-copy replacement affects body or existing destination')
                    emit(d, 'collect_ops', destination, d['body'], path, offset,
                         'reviewed-exact-header-copy', exact_header_replacement=proof)
                continue
            starts = [m.start() for m in re.finditer(r'body:=pg_get_functiondef\(', block)]
            chunks = [(block, offset)] if len(starts) == 1 else [
                (block[start:(starts[i + 1] if i + 1 < len(starts) else len(block))], offset + start)
                for i, start in enumerate(starts)]
            for chunk, position in chunks:
                key, needle, replacement = patch_parts(mapper, chunk)
                if key[:2] not in PATCH_TARGETS:
                    continue
                state = state_before(version, position)
                d = admitted_predecessor(state, *key[:2], path, position, key[2])
                if d is None:
                    continue
                emit(d, key[0], key[1], apply_patch_exact(d['body'], needle, replacement), path, position,
                     'reviewed-exact-once-body-patch', needle_sha256=mapper.sha(needle.encode()),
                     replacement_sha256=mapper.sha(replacement.encode()), replacement_occurrences=1)
    # Re-run the unchanged conservative DROP/move/rename engine over the complete
    # source order. Later declarations and DROP invalidate derived candidates too.
    final = mapper.sql_static_lineage(normalized + derived, conservative_alterations)
    return LineageResult(final, uncertainty)
