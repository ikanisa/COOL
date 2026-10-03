#!/usr/bin/env python3
"""Freeze candidate3 from unchanged admitted inputs and retained failures."""
from pathlib import Path
import ast
import hashlib
import importlib.util
import json
import stat

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PRIOR = HERE.parent / 'ordinary-recovery-replay-preparation2'
FAILURE = HERE.parent / 'ordinary-recovery-replay-execution2/readback.json'
CANDIDATE = Path('/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate3')


def sha(body):
    return hashlib.sha256(body).hexdigest()


def regular(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('Unsubstituted input required: ' + str(path))
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError('Regular single-link input required: ' + str(path))
    body = path.read_bytes(); after = path.lstat()
    if (before.st_ino,before.st_size,before.st_mtime_ns) != (after.st_ino,after.st_size,after.st_mtime_ns):
        raise ValueError('Input changed during read')
    return body


def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def preservation():
    previous=load('previous_preparation',PRIOR/'prepare.py')
    rows=previous.preservation()
    seal=json.loads(regular(PRIOR/'packet-files.json'))
    for row in seal['files']:
        body=regular(PRIOR/row['path'])
        if sha(body)!=row['sha256'] or len(body)!=row['bytes']:
            raise ValueError('Candidate2 seal drift')
    rows.update({str(path):sha(regular(path)) for path in sorted(PRIOR.iterdir()) if path.is_file()})
    body=regular(FAILURE);failed=json.loads(body)
    if (failed['status']!='failed' or failed['passed_cases']!=13 or
            not failed['all_owned_containers_removed'] or not failed['role_globals_full_comparison_passed'] or
            'function graphql_public.graphql(text, text, jsonb, jsonb) does not exist' not in failed['first_failure'] or
            len(failed['verified_files'])!=141):
        raise ValueError('Exact retained candidate2 failure required')
    rows[str(FAILURE)]=sha(body)
    actual=Path(failed['actual_output_root'])
    for row in failed['verified_files']:
        path=actual/row['path'];body=regular(path)
        if sha(body)!=row['sha256'] or len(body)!=row['bytes']:
            raise ValueError('Failed actual2 evidence drift: '+row['path'])
        rows[str(path)]=sha(body)
    return rows


def nodes(path):
    return {node.name:ast.dump(node,include_attributes=False)
            for node in ast.parse(regular(path)).body if isinstance(node,(ast.FunctionDef,ast.ClassDef))}


def test_asts(path):
    return {node.name:ast.dump(node,include_attributes=False)
            for node in ast.walk(ast.parse(regular(path))) if isinstance(node,ast.FunctionDef) and node.name.startswith('test_')}


def main():
    if CANDIDATE.exists() or (HERE/'inputs.json').exists():
        raise ValueError('Fresh private candidate3 and manifest required')
    before=preservation();prior=json.loads(regular(PRIOR/'inputs.json'))
    original=Path(prior['candidate']);admitted={**prior['sources'],**prior['references']}
    if len(prior['sources'])!=216 or len(prior['references'])!=4:
        raise ValueError('Exact216+4 cohort required')
    names={str(p.relative_to(original)) for p in (original/'supabase/migrations').glob('*.sql')}
    if names!={p for p in prior['sources'] if p.startswith('supabase/migrations/')} or len(names)!=209:
        raise ValueError('Exact209 original migration set required')
    bodies={}
    for name,digest in admitted.items():
        body=regular(original/name)
        if sha(body)!=digest or (name in prior['sources'] and regular(ROOT/name)!=body):
            raise ValueError('Admitted source drift: '+name)
        bodies[name]=body
    old_tests=test_asts(PRIOR/'test_rehearsal.py');new_tests=test_asts(HERE/'test_rehearsal.py')
    if len(old_tests)!=18 or len(new_tests)!=25 or any(new_tests.get(k)!=v for k,v in old_tests.items()):
        raise ValueError('Original18 test AST changed')
    old_nodes,new_nodes=nodes(PRIOR/'rehearsal.py'),nodes(HERE/'rehearsal.py')
    changed={name for name,value in old_nodes.items() if new_nodes.get(name)!=value}
    if changed!={'restore_list','main'}:
        raise ValueError('Unexpected prior parser/runner change: '+str(changed))
    r=load('recovery_candidate3',HERE/'rehearsal.py')
    source=json.loads(bodies['reference/observed-output/ordinary_populated/predecessor-effective-catalog.json'])
    scope=r.graphql_source_scope(bodies['.cache/receipt-foundation-attempt8/schema-only.sql'].decode(),source)
    query=r.graphql_inventory_query(bodies[r.CATALOG].decode())
    CANDIDATE.mkdir(parents=True,mode=0o700)
    for name,body in bodies.items():
        path=CANDIDATE/name;path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(body);path.chmod(0o600)
    manifest=dict(prior,candidate=str(CANDIDATE),status='prepared_only',execution_done=False,
        lineage=dict(prior['lineage'],candidate2_inputs_sha256=sha(regular(PRIOR/'inputs.json')),
            candidate2_packet_sha256=sha(regular(PRIOR/'packet-files.json')),
            failed_execution2_readback_sha256=sha(regular(FAILURE)),failed_execution2_actual_files=141,
            exact_graphql_source_function=r.GRAPHQL_FUNCTION,source_extension_membership=r.GRAPHQL_DEPENDENCIES[0],
            source_hook_body_sha256=r.GRAPHQL_HOOK[11],source_wrapper_body_sha256=r.GRAPHQL_FUNCTION[11],
            source_function_definition_sha256=r.GRAPHQL_FUNCTION[12]))
    (HERE/'inputs.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (HERE/'source-role-globals.json').write_bytes(regular(PRIOR/'source-role-globals.json'))
    (HERE/'graphql-source-scope.json').write_text(json.dumps(scope,indent=2)+'\n')
    (HERE/'graphql-wrapper-query.sql').write_text(query)
    wrapper_sql='\n'.join([scope['create_schema_sql'],scope['create_function_sql'],scope['extension_membership_sql']])+'\n'
    (HERE/'source-graphql-prerequisite.sql').write_text(wrapper_sql)
    (HERE/'retained-failure2-readback.json').write_bytes(regular(FAILURE))
    after=preservation()
    if before!=after:
        raise ValueError('Prior preparation or failure evidence changed')
    (HERE/'preservation-before.json').write_text(json.dumps(before,indent=2)+'\n')
    (HERE/'preparation-readback.json').write_text(json.dumps(dict(status='pass',copied_inputs=admitted,
        admitted_input_count=220,original_migrations=209,original18_test_AST_unchanged=True,
        prior_parser_and_Runner_AST_unchanged_except_restore_list_and_main=True,
        unchanged_node_AST_hashes={name:sha(value.encode()) for name,value in old_nodes.items() if name not in changed},
        changed_prior_nodes=sorted(changed),preserved_prior_and_failed_execution_files=len(after),
        immutable_prior_and_failed_execution_hashes=after,docker_executed=False,
        whole_deadline_seconds=600,maintained_source_mutations=0),indent=2)+'\n')
    print(json.dumps(dict(status='prepared_only',copied_inputs=220,migrations=209,preserved_files=len(after),docker_executed=False)))


if __name__=='__main__':main()
