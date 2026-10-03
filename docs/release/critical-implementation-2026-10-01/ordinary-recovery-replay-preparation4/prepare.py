#!/usr/bin/env python3
"""Freeze candidate4 from unchanged admitted inputs and retained exact failure."""
from pathlib import Path
import ast
import hashlib
import importlib.util
import json
import stat

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PRIOR = HERE.parent / 'ordinary-recovery-replay-preparation3'
FAILURE = HERE.parent / 'ordinary-recovery-replay-execution3/readback.json'
CANDIDATE = Path('/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate4')
ACTUAL3 = Path('/Users/jeanbosco/Library/Caches/COOL-ORDINARY-RECOVERY/20261002-candidate3/docs/release/committed-recovery3')


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
            raise ValueError('Candidate3 seal drift')
    rows.update({str(path):sha(regular(path)) for path in sorted(PRIOR.iterdir()) if path.is_file()})
    body=regular(FAILURE);failed=json.loads(body)
    if (failed['status']!='actual_failure_retained' or failed['actual_pass_cases']!=15 or failed['whole_pass'] or
            not failed['all_task_containers_removed'] or failed['cleanup_errors'] or
            failed['failure']!='complete restored predecessor catalog and effective ACLs exactly equal committed source' or
            not failed['source216_and_reference4_hashes_unchanged'] or
            len(failed['observed_original_files'])!=146):
        raise ValueError('Exact retained candidate3 failure required')
    rows[str(FAILURE)]=sha(body)
    for row in failed['observed_original_files']:
        path=Path(row['path'])
        if not path.is_relative_to(ACTUAL3):raise ValueError('Unexpected actual3 evidence path')
        body=regular(path)
        if sha(body)!=row['sha256'] or len(body)!=row['bytes']:
            raise ValueError('Failed actual3 evidence drift: '+row['path'])
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
        raise ValueError('Fresh private candidate4 and manifest required')
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
    if len(old_tests)!=25 or len(new_tests)!=34 or any(new_tests.get(k)!=v for k,v in old_tests.items()):
        raise ValueError('Original25 test AST changed')
    old_nodes,new_nodes=nodes(PRIOR/'rehearsal.py'),nodes(HERE/'rehearsal.py')
    changed={name for name,value in old_nodes.items() if new_nodes.get(name)!=value}
    if changed!={'main'}:
        raise ValueError('Unexpected prior parser/runner change: '+str(changed))
    r=load('recovery_candidate4',HERE/'rehearsal.py')
    source=json.loads(bodies['reference/observed-output/ordinary_populated/predecessor-effective-catalog.json'])
    additional={'reference/compatibility3/source-predecessor-catalog.json':regular(ACTUAL3/'source/committed-predecessor-catalog.json'),
        'reference/compatibility3/restored-predecessor-catalog.json':regular(ACTUAL3/'restore/restored-predecessor-catalog.json')}
    if (sha(additional['reference/compatibility3/source-predecessor-catalog.json'])!=r.CAPTURED_SOURCE_FILE_SHA or
            sha(additional['reference/compatibility3/restored-predecessor-catalog.json'])!=r.CAPTURED_RESTORED_FILE_SHA or
            json.loads(additional['reference/compatibility3/source-predecessor-catalog.json'])!=source):
        raise ValueError('Exact retained whole catalog bindings changed')
    bodies.update(additional);admitted.update({name:sha(body) for name,body in additional.items()})
    restored=json.loads(additional['reference/compatibility3/restored-predecessor-catalog.json'])
    compatibility=r.compatibility_source_scope(source,restored,
        bodies['.cache/receipt-foundation-attempt8/schema-only.sql'].decode(),bodies[r.TRANSPORT].decode(),
        bodies['supabase/migrations/20260804150000_native_push_delivery.sql'].decode(),
        bodies['supabase/migrations/20260903084000_hybrid_direct_ussd_financial_core.sql'].decode())
    scope=r.graphql_source_scope(bodies['.cache/receipt-foundation-attempt8/schema-only.sql'].decode(),source)
    query=r.graphql_inventory_query(bodies[r.CATALOG].decode())
    CANDIDATE.mkdir(parents=True,mode=0o700)
    for name,body in bodies.items():
        path=CANDIDATE/name;path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(body);path.chmod(0o600)
    manifest=dict(prior,candidate=str(CANDIDATE),status='prepared_only',execution_done=False,
        references=dict(prior['references'],**{name:sha(body) for name,body in additional.items()}),
        lineage=dict(prior['lineage'],candidate3_inputs_sha256=sha(regular(PRIOR/'inputs.json')),
            candidate3_packet_sha256=sha(regular(PRIOR/'packet-files.json')),
            failed_execution3_readback_sha256=sha(regular(FAILURE)),failed_execution3_actual_files=146,
            compatibility_source_canonical_sha256=r.COMPATIBILITY_SOURCE_SHA,
            exact_admitted_restored_canonical_sha256=r.COMPATIBILITY_RESTORED_SHA,
            actual3_dump_sha256=sha(regular(ACTUAL3/'committed-synthetic-predecessor.dump')),
            actual3_restore_TOC_sha256=sha(regular(ACTUAL3/'full-restore-list.txt'))))
    (HERE/'inputs.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (HERE/'source-role-globals.json').write_bytes(regular(PRIOR/'source-role-globals.json'))
    (HERE/'graphql-source-scope.json').write_text(json.dumps(scope,indent=2)+'\n')
    (HERE/'graphql-wrapper-query.sql').write_text(query)
    wrapper_sql='\n'.join([scope['create_schema_sql'],scope['create_function_sql'],scope['extension_membership_sql']])+'\n'
    (HERE/'source-graphql-prerequisite.sql').write_text(wrapper_sql)
    (HERE/'compatibility-source-scope.json').write_text(json.dumps(compatibility,indent=2)+'\n')
    (HERE/'source-graphql-grants-and-transport-index.sql').write_text(compatibility['admin_sql']+'\n')
    (HERE/'source-original-check-parity.sql').write_text(compatibility['postgres_sql']+'\n')
    (HERE/'retained-failure3-readback.json').write_bytes(regular(FAILURE))
    difference={}
    for key in source:
        left,right=source[key],restored[key]
        row=dict(exact_equal=left==right,source_sha256=r.canonical_catalog_sha(left),restored_sha256=r.canonical_catalog_sha(right))
        if isinstance(left,list) and isinstance(right,list):
            row.update(source_count=len(left),restored_count=len(right),
                source_only_rows=[v for v in left if v not in right],restored_only_rows=[v for v in right if v not in left])
        elif left!=right:row.update(source=left,restored=right)
        difference[key]=row
    if {key for key,row in difference.items() if not row['exact_equal']}!={'columns','constraints','dependencies','functions','indexes','relations','schemas'}:
        raise ValueError('Exact7/20 captured category delta changed')
    toc=regular(ACTUAL3/'full-restore-list.txt');dump=regular(ACTUAL3/'committed-synthetic-predecessor.dump')
    if b'collect_receipt_http_response_id' in toc or b'collect_receipt_http_response_id' in dump:
        raise ValueError('Retained source index is not omitted from archive')
    delta=dict(status='readonly_complete_captured_delta',source_file_sha256=r.CAPTURED_SOURCE_FILE_SHA,
        restored_file_sha256=r.CAPTURED_RESTORED_FILE_SHA,category_count=20,changed_categories=7,exact_categories=13,
        categories=difference,archive_omission_proof=dict(dump_sha256=sha(dump),TOC_sha256=sha(toc),
            exact_index_name_occurrences_in_uncompressed_dump=0,exact_index_name_occurrences_in_TOC=0,
            underlying_table_extension_membership=compatibility['underlying_table_extension_membership'],
            index_not_extension_member=True,only_index_dependency=compatibility['source_index_dependencies']),
        original_catalog_comparator_unchanged=True,docker_executed=False)
    (HERE/'complete-captured-delta.json').write_text(json.dumps(delta,indent=2)+'\n')
    after=preservation()
    if before!=after:
        raise ValueError('Prior preparation or failure evidence changed')
    (HERE/'preservation-before.json').write_text(json.dumps(before,indent=2)+'\n')
    (HERE/'preparation-readback.json').write_text(json.dumps(dict(status='pass',copied_inputs=admitted,
        admitted_input_count=222,original_migrations=209,original25_test_AST_unchanged=True,original18_test_AST_unchanged=True,
        prior_parser_and_Runner_AST_unchanged_except_main=True,
        unchanged_node_AST_hashes={name:sha(value.encode()) for name,value in old_nodes.items() if name not in changed},
        changed_prior_nodes=sorted(changed),preserved_prior_and_failed_execution_files=len(after),
        immutable_prior_and_failed_execution_hashes=after,docker_executed=False,
        whole_deadline_seconds=600,maintained_source_mutations=0),indent=2)+'\n')
    print(json.dumps(dict(status='prepared_only',copied_inputs=222,migrations=209,preserved_files=len(after),docker_executed=False)))


if __name__=='__main__':main()
