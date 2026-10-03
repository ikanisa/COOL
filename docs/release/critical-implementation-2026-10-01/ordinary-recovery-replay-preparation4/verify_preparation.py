#!/usr/bin/env python3
"""Bounded affected compatibility tests and exact immutable readback; no Docker."""
from pathlib import Path
import datetime
import difflib
import importlib.util
import json
import os
import re
import signal
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent
PYTHON='/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3'
ENV={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin'}


def main():
    if sys.executable!=PYTHON or not sys.flags.isolated or not sys.dont_write_bytecode:
        raise ValueError('Exact absolute isolated Python required')
    spec=importlib.util.spec_from_file_location('prepare_candidate4',HERE/'prepare.py')
    p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
    r=p.load('recovery_candidate4',HERE/'rehearsal.py')
    before=p.preservation()
    if before!=json.loads(p.regular(HERE/'preservation-before.json')):
        raise ValueError('Prior preparations or failed execution evidence changed')
    inputs=json.loads(p.regular(HERE/'inputs.json'));prior=json.loads(p.regular(p.PRIOR/'inputs.json'))
    if (inputs['sources']!=prior['sources'] or len(inputs['references'])!=6 or
            any(inputs['references'].get(name)!=digest for name,digest in prior['references'].items())):
        raise ValueError('Admitted original216+4 hashes changed')
    admitted={**inputs['sources'],**inputs['references']}
    def frozen():
        hashes={name:p.sha(p.regular(p.CANDIDATE/name)) for name in admitted}
        if hashes!=admitted or any(p.regular(p.ROOT/name)!=p.regular(p.CANDIDATE/name) for name in inputs['sources']):
            raise ValueError('Admitted inputs changed')
        migrations={str(path.relative_to(p.CANDIDATE)) for path in (p.CANDIDATE/'supabase/migrations').glob('*.sql')}
        if len(migrations)!=209 or migrations!={name for name in inputs['sources'] if name.startswith('supabase/migrations/')}:
            raise ValueError('Exact209 migration membership changed')
        return hashes
    initial=frozen()
    old,new=p.test_asts(p.PRIOR/'test_rehearsal.py'),p.test_asts(HERE/'test_rehearsal.py')
    if len(old)!=25 or len(new)!=34 or any(new.get(name)!=value for name,value in old.items()):
        raise ValueError('Original25 test AST changed')
    old_nodes,new_nodes=p.nodes(p.PRIOR/'rehearsal.py'),p.nodes(HERE/'rehearsal.py')
    changed={name for name,value in old_nodes.items() if new_nodes.get(name)!=value}
    if changed!={'main'}:raise ValueError('Unexpected prior parser/Runner AST change')
    # Successful prior18 and prior9 receipts jointly cover all unchanged25 methods.
    reused=[]
    for directory,count in [(p.PRIOR.parent/'ordinary-recovery-replay-preparation2',18),(p.PRIOR,9)]:
        receipt=json.loads(p.regular(directory/'focused-tests.json'))
        if (receipt['status']!='pass' or receipt['tests_passed']!=count or
                any(p.sha(p.regular(directory/name))!=digest for name,digest in receipt['tested_artifact_hashes'].items()) or
                p.sha(p.regular(directory/'focused-tests.stdout'))!=receipt['stdout_sha256'] or
                p.sha(p.regular(directory/'focused-tests.stderr'))!=receipt['stderr_sha256']):
            raise ValueError('Retained prior successful proof changed')
        reused.append(dict(path=str(directory/'focused-tests.json'),sha256=p.sha(p.regular(directory/'focused-tests.json')),tests=count))
    for name in ['source-role-globals.json','graphql-source-scope.json','graphql-wrapper-query.sql','source-graphql-prerequisite.sql']:
        if p.regular(HERE/name)!=p.regular(p.PRIOR/name):raise ValueError('Unchanged prior fixture/provenance bytes differ')
    source=json.loads(p.regular(p.CANDIDATE/'reference/compatibility3/source-predecessor-catalog.json'))
    restored=json.loads(p.regular(p.CANDIDATE/'reference/compatibility3/restored-predecessor-catalog.json'))
    scope=r.compatibility_source_scope(source,restored,
        p.regular(p.CANDIDATE/'.cache/receipt-foundation-attempt8/schema-only.sql').decode(),
        p.regular(p.CANDIDATE/r.TRANSPORT).decode(),
        p.regular(p.CANDIDATE/'supabase/migrations/20260804150000_native_push_delivery.sql').decode(),
        p.regular(p.CANDIDATE/'supabase/migrations/20260903084000_hybrid_direct_ussd_financial_core.sql').decode())
    if scope!=json.loads(p.regular(HERE/'compatibility-source-scope.json')):
        raise ValueError('Prepared semantic scope differs from independently rebuilt scope')
    if (p.regular(HERE/'source-graphql-grants-and-transport-index.sql').decode()!=scope['admin_sql']+'\n' or
            p.regular(HERE/'source-original-check-parity.sql').decode()!=scope['postgres_sql']+'\n'):
        raise ValueError('Prepared SQL differs from exact admitted plan')
    artifacts={name:p.sha(p.regular(HERE/name)) for name in ['rehearsal.py','test_rehearsal.py','inputs.json','source-role-globals.json',
        'graphql-source-scope.json','compatibility-source-scope.json','source-graphql-grants-and-transport-index.sql','source-original-check-parity.sql']}
    argv=[PYTHON,'-I','-B',str(HERE/'test_rehearsal.py'),'CompatibilityTests','-v']
    receipt_path=HERE/'focused-tests.json'
    if receipt_path.exists():
        previous=json.loads(p.regular(receipt_path));out,err=p.regular(HERE/'focused-tests.stdout'),p.regular(HERE/'focused-tests.stderr')
        if (previous['status']!='pass' or previous['argv']!=argv or previous['environment']!=ENV or
                previous['tested_artifact_hashes']!=artifacts or previous['admitted222_hashes_before_and_after']!=initial or
                previous['stdout_sha256']!=p.sha(out) or previous['stderr_sha256']!=p.sha(err)):
            raise ValueError('Cannot reuse focused proof')
        elapsed,exit_code,timed_out,at_utc=previous['elapsed_seconds'],previous['exit_code'],previous['timed_out'],previous['at_utc']
    else:
        started=time.monotonic();at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()
        process=subprocess.Popen(argv,cwd=p.ROOT,env=ENV,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
        timed_out=False
        try:out,err=process.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            timed_out=True;os.killpg(process.pid,signal.SIGKILL);out,err=process.communicate(timeout=5)
        elapsed,exit_code=time.monotonic()-started,process.returncode
        (HERE/'focused-tests.stdout').write_bytes(out);(HERE/'focused-tests.stderr').write_bytes(err)
    if timed_out or exit_code or len(out)>1024**2 or len(err)>1024**2 or not re.search(rb'Ran 9 tests in .*\n\nOK\n',err):
        raise ValueError('Actual bounded new9 tests must pass; inspect retained focused-tests.stderr')
    toc=p.regular(p.ACTUAL3/'full-restore-list.txt').decode();dump=p.regular(p.ACTUAL3/'committed-synthetic-predecessor.dump')
    omission=r.compatibility_archive_proof(source,toc,dump)
    # Reconstruct only explicit preinstalled CREATE comments and rerun unchanged
    # parser. Every retained ACL/data/history/other DDL line is identical.
    prefix='; preinstalled exact frozen prerequisite: '
    actual_record=json.loads(p.regular(p.ACTUAL3/'result.json'))
    existing_comments=[line[len(prefix):].rstrip() for line in toc.splitlines(True) if line.startswith(prefix)]
    if existing_comments!=actual_record['restore_scope']['explicitly_preinstalled_toc_entries']:
        raise ValueError('Actual3 prerequisite comments differ from sealed actual3 restore scope')
    raw=''.join(line[len(prefix):] if line.startswith(prefix) else line for line in toc.splitlines(True))
    graphql=r.graphql_source_scope(p.regular(p.CANDIDATE/'.cache/receipt-foundation-attempt8/schema-only.sql').decode(),source)
    proposed,omitted=r.restore_list(raw,source,graphql)
    if proposed!=toc:raise ValueError('Existing exact TOC policy changed')
    (HERE/'retained-TOC-proposal.txt').write_text(proposed)
    toc_receipt=dict(status='pass',actual3_TOC_sha256=p.sha(toc.encode()),proposal_sha256=p.sha(proposed.encode()),
        restore_list_AST_unchanged=True,every_line_unchanged=True,additional_commented_entries=[],
        every_ACL_data_history_and_other_DDL_entry_retained=True,explicit_existing_preinstalled_CREATE_entries=omitted,
        exact_archive_omission_proof=omission,archive_sha256=p.sha(dump),docker_executed=False)
    (HERE/'TOC-readback.json').write_text(json.dumps(toc_receipt,indent=2)+'\n')
    after=p.preservation()
    if after!=before or frozen()!=initial or artifacts!={name:p.sha(p.regular(HERE/name)) for name in artifacts}:
        raise ValueError('Inputs changed during focused verification')
    (HERE/'preservation-after.json').write_text(json.dumps(after,indent=2)+'\n')
    receipt=dict(kind='collect_recovery_candidate4_focused_tests',status='pass',at_utc=at_utc,argv=argv,environment=ENV,cwd=str(p.ROOT),
        timeout_seconds=20,elapsed_seconds=elapsed,exit_code=exit_code,timed_out=timed_out,tests_passed=9,new_compatibility_tests=9,
        unchanged_original25_test_AST=True,unchanged_original18_test_AST=True,prior_pass_receipts_reused=reused,
        prior_parser_and_Runner_AST_unchanged=True,source_and_old_reference_fixture_bytes_unchanged=True,
        stdout_sha256=p.sha(out),stderr_sha256=p.sha(err),tested_artifact_hashes=artifacts,
        admitted222_hashes_before_and_after=initial,preserved_files=len(after),immutable_inputs_unchanged=True,
        actual_retained_TOC_readback=toc_receipt,whole_program_seconds=600,docker_executed=False,
        maintained_source_mutations=0,full_BE08_closed=False,ARC08_closed=False,ARC11_closed=False)
    receipt_path.write_text(json.dumps(receipt,indent=2)+'\n')
    matrix=json.loads(p.regular(p.PRIOR/'command-scope-matrix.json'))
    def replace(value):
        if isinstance(value,str):return value.replace('ordinary-recovery-replay-preparation3','ordinary-recovery-replay-preparation4').replace('20261002-candidate3','20261002-candidate4').replace('committed-recovery3','committed-recovery4')
        if isinstance(value,list):return [replace(v) for v in value]
        if isinstance(value,dict):return {k:replace(v) for k,v in value.items()}
        return value
    matrix=replace(matrix)
    for value in [matrix,matrix['review_record_schema']]:
        value['code_sha256']=artifacts['rehearsal.py'];value['inputs_sha256']=artifacts['inputs.json']
    repair_scope=dict(stage='post_archive_exact_captured_source_compatibility_repairs',
        admitted_source_scope=scope,admitted_target_canonical_sha256=r.COMPATIBILITY_RESTORED_SHA,
        source_canonical_sha256=r.COMPATIBILITY_SOURCE_SHA,
        archive_omission_proof=omission,admin_sql=scope['admin_sql'],admin_sql_sha256=p.sha((scope['admin_sql']+'\n').encode()),
        admin_role='exact local synthetic supabase_admin',postgres_sql=scope['postgres_sql'],
        postgres_sql_sha256=p.sha((scope['postgres_sql']+'\n').encode()),postgres_role='postgres NOSUPERUSER',
        fresh18_projection_parity_immediately_before_and_after_both_transactions=True,
        exact_source_CHECK_identity_flags_definition_hashes_required_before_continuing=True,
        unknown_metadata_or_source_SQL_or_additional_difference_refused=True,
        full_predecessor_and_final209_catalog_comparison_unchanged=True,all85_original_forward_migrations_unchanged=True,
        schema_or_function_rewrite=False,generic_GRANT_ALL=False,CHECK_hash_normalization=False)
    matrix['exact_compatibility_repair_scope']=repair_scope
    index=next(i for i,row in enumerate(matrix['sql_input_and_authority_matrix']) if row['stage']=='target_archive_restore')
    matrix['sql_input_and_authority_matrix'].insert(index+1,repair_scope)
    matrix['retained_failure3_readback_sha256']=inputs['lineage']['failed_execution3_readback_sha256']
    matrix['TOC_derivation_readback']=toc_receipt
    matrix['frozen_input_counts']=dict(sources=216,references=6,original_reference_hashes_unchanged=4,original_migrations=209)
    (HERE/'command-scope-matrix.json').write_text(json.dumps(matrix,indent=2)+'\n')
    for name in ['rehearsal.py','test_rehearsal.py','prepare.py']:
        difference=''.join(difflib.unified_diff(p.regular(p.PRIOR/name).decode().splitlines(True),p.regular(HERE/name).decode().splitlines(True),
            fromfile='preparation3/'+name,tofile='preparation4/'+name))
        (HERE/(name+'.diff')).write_text(difference)
    rows=[dict(path=path.name,bytes=len(body),sha256=p.sha(body)) for path in sorted(HERE.iterdir())
        if path.is_file() and path.name not in ['packet-files.json','SHA256SUMS'] for body in [p.regular(path)]]
    (HERE/'packet-files.json').write_text(json.dumps(dict(status='prepared_only',docker_executed=False,files=rows),indent=2)+'\n')
    (HERE/'SHA256SUMS').write_text(''.join(row['sha256']+'  '+row['path']+'\n' for row in rows))
    for row in rows:
        if p.sha(p.regular(HERE/row['path']))!=row['sha256']:raise ValueError('Final packet readback failed')
    print(json.dumps(dict(status='prepared_and_focused_tests_pass',new_focused_tests=9,original25_AST_unchanged=True,
        inputs=222,preserved_files=len(after),code_sha256=artifacts['rehearsal.py'],inputs_sha256=artifacts['inputs.json'],
        packet_sha256=p.sha(p.regular(HERE/'packet-files.json')),sealed_leaves=len(rows),docker_executed=False)))


if __name__=='__main__':main()
