#!/usr/bin/env python3
"""Offline147 source/contract/guard validation; never connects to a database."""
import argparse, hashlib, json, os, pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
SQL='supabase/migrations/20260930150000_runtime_control_governance.sql'
UAT='scripts/tests/runtime_control_governance_uat.sql'
RACE='scripts/tests/runtime_control_concurrency_uat.rb'
SPEC='docs/release/runtime-controls-2026-09-30/source-candidate/control-spec.json'
CONTRACT='docs/release/runtime-controls-2026-09-30/contracts/client-contract-v2.json'
INPUTS=[SQL,UAT,RACE,SPEC,CONTRACT,'scripts/tests/runtime_control_source_gate.py',
 'docs/release/runtime-controls-2026-09-30/inventory146-attempt1/inventory.json',
 'supabase/migrations/20260929180000_notification_registration_sessions.sql',
 'supabase/migrations/20260930130000_signed_otp_uncertain_recovery.sql',
 'supabase/migrations/20260930140000_roster_resource_integrity.sql']
def hashes():return {x:hashlib.sha256((ROOT/x).read_bytes()).hexdigest() for x in INPUTS}
def run():
 before=hashes();spec=json.loads((ROOT/SPEC).read_text());contract=json.loads((ROOT/CONTRACT).read_text())
 inventory=json.loads((ROOT/INPUTS[6]).read_text())
 expected={x['relation'] for x in inventory['tables']}|{'public.collection_category_subtypes'}
 assert len(spec)==26 and {x['relation'] for x in spec.values()}==expected
 sql=(ROOT/SQL).read_text();literal=sql.split('$spec$')[1].split(" select '",1)[1].split("'::jsonb -> p_family;",1)[0]
 assert json.loads(literal.replace("''","'"))==spec
 for family,x in spec.items():
  assert set(x['identity']+x['writable'])<=set(x['types'])
  assert not set(x['identity'])&set(x['writable'])
  assert x['types'] and isinstance(x['create_allowed'],bool)
 assert spec['notification_preferences']['user_owned'] is True
 assert 'permission' not in spec['notification_preferences']
 import pglast
 assert pglast.__version__=='v7.7', 'Use recorded offline parser pglast7.7'
 parsed={}
 for filename in [SQL,UAT]:
  text='\n'.join(x for x in (ROOT/filename).read_text().splitlines() if not x.startswith('\\'))
  parsed[filename]={'sql_statements':len(pglast.parse_sql(text)),'plpgsql_units':len(pglast.parse_plpgsql(text))}
 subprocess.run(['ruby','-c',str(ROOT/RACE)],check=True,capture_output=True,text=True)
 # Fail-closed launcher guard cases use an inert docker sentinel. Any attempted
 # DB/Docker command makes the guard tests fail; source checks never call SQL.
 with tempfile.TemporaryDirectory(prefix='collect147-source-') as d:
  tmp=pathlib.Path(d);sentinel=tmp/'docker';marker=tmp/'unexpected-docker'
  sentinel.write_text('#!/bin/sh\ntouch "'+str(marker)+'"\nexit 99\n');sentinel.chmod(0o700)
  base={k:v for k,v in os.environ.items() if not k.startswith('COLLECT_RUNTIME_CONTROL') and k!='COLLECT_RUNTIME_CONTROLS_QA'}
  base['PATH']=str(tmp)+':'+base.get('PATH','')
  cases=[({},'Set COLLECT_RUNTIME_CONTROLS_QA'),({'COLLECT_RUNTIME_CONTROLS_QA':'wrong'},'Set COLLECT_RUNTIME_CONTROLS_QA'),
   ({'COLLECT_RUNTIME_CONTROLS_QA':'isolated_clone'},'New absolute checkpoint'),
   ({'COLLECT_RUNTIME_CONTROLS_QA':'isolated_clone','COLLECT_RUNTIME_CONTROL_CHECKPOINT':str(tmp/'checkpoint.json'),'COLLECT_RUNTIME_CONTROL_MIGRATION_SHA':'0'*64},'Exact frozen147 SHA')]
  for extra,message in cases:
   result=subprocess.run(['ruby',str(ROOT/RACE)],env=base|extra,capture_output=True,text=True,timeout=10)
   assert result.returncode!=0 and message in result.stderr and not marker.exists()
  assert not (tmp/'checkpoint.json').exists()
 for family in ['feature_flags','notification_preferences']:
  c=contract[family]
  for key in ['changed_ack','no_change_ack']:
   ack=c[key];assert set(ack)==set(c['ack_keys']) and ack['contract_version']==2 and ack['ok'] is True
   assert type(ack['previous_revision']) is int and type(ack['revision']) is int and type(ack['changed']) is bool
   assert ack['revision']==ack['previous_revision']+(1 if ack['changed'] else 0)
 for key in ['read_example','absent_example']:
  r=contract['notification_preferences'][key]
  assert set(r)==set(contract['notification_preferences']['read_keys'])
  assert set(r['preferences'])==set(contract['notification_preferences']['preference_keys'])
  assert all(type(v) is bool for v in r['preferences'].values())
 after=hashes();assert before==after
 return {'status':'pass','scope':'offline source grammar, inventory parity, frozen client fixtures and fail-closed launcher guards only',
  'sql_parser':pglast.__version__,'parsed':parsed,'governed_families':26,'launcher_guard_cases':4,
  'database_calls':0,'provider_calls':0,'runtime_sql_acceptance_verified':False,'source_sha256_before':before,'source_sha256_after':after}
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--output',type=pathlib.Path);args=parser.parse_args()
 report=run();body=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if args.output:
  if args.output.exists():raise SystemExit('Output exists; preserve earlier source receipt')
  args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(body)
 print(body,end='')
