#!/usr/bin/env python3
"""Focused GraphQL/TOC tests and immutable readback; no Docker or database use."""
from pathlib import Path
import datetime
import difflib
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
    import importlib.util
    spec=importlib.util.spec_from_file_location('prepare_candidate3',HERE/'prepare.py')
    p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
    r=p.load('recovery_candidate3',HERE/'rehearsal.py')
    before=p.preservation()
    if before!=json.loads(p.regular(HERE/'preservation-before.json')):
        raise ValueError('Prior preparations or failed execution evidence changed')
    inputs=json.loads(p.regular(HERE/'inputs.json'));original=json.loads(p.regular(p.PRIOR/'inputs.json'))
    if inputs['sources']!=original['sources'] or inputs['references']!=original['references']:
        raise ValueError('Admitted216+4 hashes changed')
    admitted={**inputs['sources'],**inputs['references']}
    def frozen():
        hashes={name:p.sha(p.regular(p.CANDIDATE/name)) for name in admitted}
        if hashes!=admitted or any(p.regular(p.ROOT/name)!=p.regular(p.CANDIDATE/name) for name in inputs['sources']):
            raise ValueError('Admitted inputs changed')
        return hashes
    initial=frozen()
    old,new=p.test_asts(p.PRIOR/'test_rehearsal.py'),p.test_asts(HERE/'test_rehearsal.py')
    if len(old)!=18 or len(new)!=25 or any(new.get(name)!=value for name,value in old.items()):
        raise ValueError('Original18 test AST changed')
    old_nodes,new_nodes=p.nodes(p.PRIOR/'rehearsal.py'),p.nodes(HERE/'rehearsal.py')
    changed={name for name,value in old_nodes.items() if new_nodes.get(name)!=value}
    if changed!={'restore_list','main'}:
        raise ValueError('Prior parser or Runner changed')
    prior_receipt=json.loads(p.regular(p.PRIOR/'focused-tests.json'))
    if (prior_receipt['status']!='pass' or prior_receipt['tests_passed']!=18 or
            any(p.sha(p.regular(p.PRIOR/name))!=digest for name,digest in prior_receipt['tested_artifact_hashes'].items()) or
            p.sha(p.regular(p.PRIOR/'focused-tests.stdout'))!=prior_receipt['stdout_sha256'] or
            p.sha(p.regular(p.PRIOR/'focused-tests.stderr'))!=prior_receipt['stderr_sha256']):
        raise ValueError('Retained prior18 proof changed')
    artifacts={name:p.sha(p.regular(HERE/name)) for name in ['rehearsal.py','test_rehearsal.py','inputs.json','source-role-globals.json','graphql-source-scope.json']}
    argv=[PYTHON,'-I','-B',str(HERE/'test_rehearsal.py'),'ArchiveTests','GraphQLSourceTests','-v']
    receipt_path=HERE/'focused-tests.json'
    if receipt_path.exists():
        previous=json.loads(p.regular(receipt_path))
        out,err=p.regular(HERE/'focused-tests.stdout'),p.regular(HERE/'focused-tests.stderr')
        if (previous['status']!='pass' or previous['argv']!=argv or previous['environment']!=ENV or
                previous['tested_artifact_hashes']!=artifacts or previous['admitted220_hashes_before_and_after']!=initial or
                previous['stdout_sha256']!=p.sha(out) or previous['stderr_sha256']!=p.sha(err)):
            raise ValueError('Cannot reuse focused test proof')
        elapsed,exit_code,timed_out=previous['elapsed_seconds'],previous['exit_code'],previous['timed_out']
        at_utc=previous['at_utc']
    else:
        started=time.monotonic();at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()
        process=subprocess.Popen(argv,cwd=p.ROOT,env=ENV,stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
        timed_out=False
        try:out,err=process.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            timed_out=True;os.killpg(process.pid,signal.SIGKILL);out,err=process.communicate(timeout=5)
        elapsed,exit_code=time.monotonic()-started,process.returncode
        (HERE/'focused-tests.stdout').write_bytes(out);(HERE/'focused-tests.stderr').write_bytes(err)
    if timed_out or exit_code or len(out)>1024**2 or len(err)>1024**2 or not re.search(rb'Ran 9 tests in .*\n\nOK\n',err):
        raise ValueError('Actual bounded focused9 tests must pass')
    # The retained listing is already a derivative with explicit comments. Undo
    # only that fixed prefix, proving its contents against the actual2 record.
    failed=json.loads(p.regular(p.FAILURE));actual=Path(failed['actual_output_root'])
    old_listing=p.regular(actual/'full-restore-list.txt').decode()
    actual_record=json.loads(p.regular(actual/'result.json'))
    prefix='; preinstalled exact frozen prerequisite: '
    old_omitted=[line[len(prefix):].rstrip() for line in old_listing.splitlines(True) if line.startswith(prefix)]
    if old_omitted!=actual_record['restore_scope']['explicitly_preinstalled_toc_entries']:
        raise ValueError('Retained actual TOC prerequisite comments drifted')
    raw=''.join(line[len(prefix):] if line.startswith(prefix) else line for line in old_listing.splitlines(True))
    catalog=json.loads(p.regular(p.CANDIDATE/'reference/observed-output/ordinary_populated/predecessor-effective-catalog.json'))
    scope=r.graphql_source_scope(p.regular(p.CANDIDATE/'.cache/receipt-foundation-attempt8/schema-only.sql').decode(),catalog)
    if r.restore_list(raw,catalog)[0]!=old_listing:
        raise ValueError('Original TOC rules changed')
    proposed,omitted=r.restore_list(raw,catalog,scope)
    differences=[(i,a,b) for i,(a,b) in enumerate(zip(old_listing.splitlines(True),proposed.splitlines(True)),1) if a!=b]
    if (len(old_listing.splitlines(True))!=len(proposed.splitlines(True)) or len(differences)!=1 or
            differences[0][2]!=prefix+differences[0][1] or
            not re.fullmatch(r'\d+;\s+\d+\s+\d+\s+SCHEMA - graphql_public supabase_admin\s*',differences[0][1]) or
            set(omitted)-set(old_omitted)!={differences[0][1].rstrip()}):
        raise ValueError('Only exact GraphQL schema CREATE may be newly commented')
    (HERE/'retained-TOC-proposal.txt').write_text(proposed)
    toc_receipt=dict(status='pass',retained_actual2_listing_sha256=p.sha(old_listing.encode()),
        reconstructed_logical_TOC_sha256=p.sha(raw.encode()),proposal_sha256=p.sha(proposed.encode()),
        original_prerequisite_comments_exactly_match_retained_actual_record=True,
        newly_commented_entries=[differences[0][1].rstrip()],changed_line=differences[0][0],
        every_other_line_unchanged=True,every_ACL_data_history_and_other_DDL_entry_retained=True,
        reconstruction_is_readonly_derivation_not_new_pg_restore_list=True,docker_executed=False)
    (HERE/'TOC-readback.json').write_text(json.dumps(toc_receipt,indent=2)+'\n')
    after=p.preservation()
    if after!=before or frozen()!=initial or artifacts!={name:p.sha(p.regular(HERE/name)) for name in artifacts}:
        raise ValueError('Inputs changed during focused verification')
    (HERE/'preservation-after.json').write_text(json.dumps(after,indent=2)+'\n')
    receipt=dict(kind='collect_recovery_candidate3_focused_tests',status='pass',at_utc=at_utc,argv=argv,environment=ENV,
        cwd=str(p.ROOT),timeout_seconds=20,elapsed_seconds=elapsed,exit_code=exit_code,timed_out=timed_out,
        tests_passed=9,new_GraphQL_tests=7,affected_archive_tests=2,original18_test_AST_unchanged=True,
        prior18_pass_receipt_sha256=p.sha(p.regular(p.PRIOR/'focused-tests.json')),
        unchanged_prior16_checks_reused=True,unchanged_prior_parser_and_Runner_AST=True,
        stdout_sha256=p.sha(out),stderr_sha256=p.sha(err),tested_artifact_hashes=artifacts,
        admitted220_hashes_before_and_after=initial,preserved_files=len(after),immutable_inputs_unchanged=True,
        actual_retained_TOC_readback=toc_receipt,whole_program_seconds=600,docker_executed=False,
        maintained_source_mutations=0,full_BE08_closed=False,ARC08_closed=False,ARC11_closed=False)
    receipt_path.write_text(json.dumps(receipt,indent=2)+'\n')
    matrix=json.loads(p.regular(p.PRIOR/'command-scope-matrix.json'))
    def replace(value):
        if isinstance(value,str):return value.replace('ordinary-recovery-replay-preparation2','ordinary-recovery-replay-preparation3').replace('20261002-candidate2','20261002-candidate3').replace('committed-recovery2','committed-recovery3')
        if isinstance(value,list):return [replace(v) for v in value]
        if isinstance(value,dict):return {k:replace(v) for k,v in value.items()}
        return value
    matrix=replace(matrix)
    for value in [matrix,matrix['review_record_schema']]:
        value['code_sha256']=artifacts['rehearsal.py'];value['inputs_sha256']=artifacts['inputs.json']
    wrapper_scope=dict(stage='exact_source_GraphQL_schema_wrapper_extension_membership_prerequisite',
        admitted_source_scope=scope,sql=p.regular(HERE/'source-graphql-prerequisite.sql').decode(),
        sql_sha256=p.sha(p.regular(HERE/'source-graphql-prerequisite.sql')),
        query=p.regular(HERE/'graphql-wrapper-query.sql').decode(),
        query_sha256=p.sha(p.regular(HERE/'graphql-wrapper-query.sql')),
        role='readonly postgres NOSUPERUSER inventory; fixed prerequisite SQL as local synthetic supabase_admin',
        newly_preinstalled_schema_CREATE_TOC_only=True,every_wrapper_schema_and_other_ACL_retained=True,
        unknown_source_or_restore_identity_body_owner_definition_dependency_provenance_refused=True,
        preliminary_ACL_cohorts=['exact_new_function_default','exact_final_source'],
        full_predecessor_and_final_catalog_comparison_unchanged=True)
    matrix['source_graphql_wrapper_prerequisite']=wrapper_scope
    index=next(i for i,row in enumerate(matrix['sql_input_and_authority_matrix']) if row['stage']=='target_archive_restore')
    matrix['sql_input_and_authority_matrix'].insert(index,wrapper_scope)
    matrix['retained_failure2_readback_sha256']=inputs['lineage']['failed_execution2_readback_sha256']
    matrix['TOC_derivation_readback']=toc_receipt
    (HERE/'command-scope-matrix.json').write_text(json.dumps(matrix,indent=2)+'\n')
    for name in ['rehearsal.py','test_rehearsal.py']:
        difference=''.join(difflib.unified_diff(p.regular(p.PRIOR/name).decode().splitlines(True),
            p.regular(HERE/name).decode().splitlines(True),fromfile='preparation2/'+name,tofile='preparation3/'+name))
        (HERE/(name+'.diff')).write_text(difference)
    rows=[dict(path=path.name,bytes=len(body),sha256=p.sha(body)) for path in sorted(HERE.iterdir())
        if path.is_file() and path.name not in ['packet-files.json','SHA256SUMS'] for body in [p.regular(path)]]
    (HERE/'packet-files.json').write_text(json.dumps(dict(status='prepared_only',docker_executed=False,files=rows),indent=2)+'\n')
    (HERE/'SHA256SUMS').write_text(''.join(row['sha256']+'  '+row['path']+'\n' for row in rows))
    for row in rows:
        if p.sha(p.regular(HERE/row['path']))!=row['sha256']:raise ValueError('Final packet readback failed')
    print(json.dumps(dict(status='prepared_and_focused_tests_pass',focused_tests=9,new_tests=7,original18_AST_unchanged=True,
        inputs=220,preserved_files=len(after),code_sha256=artifacts['rehearsal.py'],inputs_sha256=artifacts['inputs.json'],
        packet_sha256=p.sha(p.regular(HERE/'packet-files.json')),sealed_leaves=len(rows),docker_executed=False)))


if __name__=='__main__':main()
