#!/usr/bin/python3
"""One fixed, count-only local-container observation; no credentials or rows.

The named Docker context, socket, container, image tag and psql connection are
fixed. No production endpoint, caller-provided SQL, user ID or token exists.
Run only after the pinned owned synthetic tests and independent source review.
"""
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

ROOT=Path('/Volumes/COLLECT-STAGING-20261109/main-source')
DOCKER='/Applications/Docker.app/Contents/Resources/bin/docker'
CONTEXT='colima-supabase-local'
SOCKET='/Volumes/SupaRuntime/.colima/supabase-local/docker.sock'
CONTAINER='supabase_db_local-app'
IMAGE='public.ecr.aws/supabase/postgres:17.11.0.006'
OUT=Path('/Volumes/T7/01 Projects/COLLECT/outputs/cloud-supabase-assessment-2026-11-14/unlinked-sms-classification-source-20261114.json')
INPUTS={
 'scripts/supabase/current-pg-transfer/unlinked-sms-import/classification.sql':'8407b92c4db2bea1cefc912b4878380660a0f7991fe57762c1f1e13930f16da8',
 'scripts/supabase/current-pg-transfer/unlinked-sms-import/classification.test.mjs':'67cdfb8eb2e37f36cc0b8339d59c8c95d2c2356166b01625986b3ae036f01461',
 'scripts/supabase/current-pg-transfer/financial-consistency/native-readiness-v3/fixture.sql':'3509dc9af66db10983e4b6f1fc44612b648f6aaf01fb938881fcb49e8a6be9b6',
 'scripts/supabase/current-pg-transfer/test-support/owned-pg17.mjs':'d16afa140b3d2e45c25781bf5f7de1e071762b8cfbef417edb89b2017cc8f9db'
}
IDENTITY="""SELECT jsonb_build_object('tag','identity','database',current_database(),
 'major',current_setting('server_version_num')::integer/10000,'socket',inet_server_addr() IS NULL,
 'session',session_user,'role',current_user,'replication',current_setting('session_replication_role'),
 'system_identifier',(SELECT system_identifier::text FROM pg_control_system()),
 'postmaster_started',pg_postmaster_start_time()::text,'backend_pid',pg_backend_pid(),
 'database_oid',(SELECT oid::bigint FROM pg_database WHERE datname=current_database()))::text;
"""
SCOPE={'receipts','linked','unlinked','link_unknown','multiple_paths'}
UNLINKED={'allocation_unallocated','allocation_needs_review','allocation_not_applicable','allocation_other_or_null',
 'state_completed','state_other_or_null','phase_finished','phase_other_or_null','event_incoming','event_outgoing','event_reversal',
 'event_failed_pending_other_unknown','outcome_successful','outcome_not_successful_or_null','relation_not_accepted_or_unknown',
 'graph_mismatch_or_unknown','fingerprint_mismatch_or_unknown','job_missing','conflict_nonzero_or_unknown','provider_reference_null','amount_null','currency_null',
 'currency_scale_null','transaction_wallet_null','posting_facts_sql_null','posting_facts_json_null','posting_facts_object',
 'posting_facts_incomplete','wallet_key_missing','wallet_json_null'}

def require(ok):
 if not ok:raise ValueError('local_classification_refused')

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def input_pins():
 found={name:digest(ROOT/name) for name in INPUTS}
 require(found==INPUTS)
 return found

def validate_output(raw):
 require(isinstance(raw,bytes) and len(raw)<=65536)
 lines=raw.decode('utf8','strict').splitlines();require(len(lines)==3)
 first,obs,last=[json.loads(line) for line in lines]
 identity_keys={'tag','database','major','socket','session','role','replication','system_identifier','postmaster_started','backend_pid','database_oid'}
 require(isinstance(first,dict) and set(first)==identity_keys and first==last and first['tag']=='identity' and
  first['database']=='postgres' and first['major']==17 and first['socket'] is True and first['session']=='postgres' and
  first['role']=='postgres' and first['replication']=='origin' and isinstance(first['system_identifier'],str) and
  re.fullmatch(r'[0-9]{1,32}',first['system_identifier']) is not None and isinstance(first['postmaster_started'],str) and
  type(first['backend_pid']) is int and first['backend_pid']>1 and type(first['database_oid']) is int and first['database_oid']>0)
 require(isinstance(obs,dict) and set(obs)=={'format','observed_at_utc','scope','unlinked','visibility','source_frozen','complete_graph_verified','provider_or_object_verified','write_authorized'})
 require(obs['format']=='collect.native-unlinked-classification.v1' and isinstance(obs['observed_at_utc'],str) and
  re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z',obs['observed_at_utc']) is not None)
 require(obs['source_frozen'] is False and obs['complete_graph_verified'] is False and obs['provider_or_object_verified'] is False and obs['write_authorized'] is False)
 require(obs['visibility']=={'active_rls_filtering':False,'full_table_select_checked':True,'inherited_tables_refused':True,'required_columns_checked':True})
 s,u=obs['scope'],obs['unlinked'];require(isinstance(s,dict) and set(s)==SCOPE and isinstance(u,dict) and set(u)==UNLINKED)
 require(all(type(v) is int and 0<=v<=1000000 for v in [*s.values(),*u.values()]))
 require(s['receipts']==s['linked']+s['unlinked']+s['link_unknown'] and s['multiple_paths']<=s['link_unknown'])
 n=s['unlinked'];require(all(v<=n for v in u.values()))
 for group in [('allocation_unallocated','allocation_needs_review','allocation_not_applicable','allocation_other_or_null'),
  ('state_completed','state_other_or_null'),('phase_finished','phase_other_or_null'),
  ('event_incoming','event_outgoing','event_reversal','event_failed_pending_other_unknown'),('outcome_successful','outcome_not_successful_or_null')]:
  require(sum(u[k] for k in group)==n)
 require(u['job_missing']+u['posting_facts_sql_null']+u['posting_facts_json_null']+u['posting_facts_object']<=n)
 require(u['posting_facts_incomplete']<=n-u['job_missing'] and u['job_missing']<=u['graph_mismatch_or_unknown'])
 return obs

def command(args,input_bytes=None):
 p=subprocess.run(args,input=input_bytes,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=25,check=False)
 require(p.returncode==0 and len(p.stdout)<=65536)
 return p.stdout

def context_host():
 raw=command([DOCKER,'context','inspect',CONTEXT,'--format','{{json .Endpoints.docker.Host}}'])
 value=json.loads(raw);require(value=='unix://'+SOCKET and os.path.realpath(SOCKET)==SOCKET and stat.S_ISSOCK(os.stat(SOCKET).st_mode))
 return value

def container_identity():
 fmt='{{json .Id}}|{{json .Image}}|{{json .State.StartedAt}}|{{json .Name}}|{{json .Config.Image}}|{{json .State.Running}}'
 raw=command([DOCKER,'--context',CONTEXT,'inspect','--format',fmt,CONTAINER]).decode('utf8','strict').strip().split('|')
 require(len(raw)==6);cid,image,started,name,tag,running=[json.loads(x) for x in raw]
 require(re.fullmatch(r'[a-f0-9]{64}',cid or '') is not None and re.fullmatch(r'sha256:[a-f0-9]{64}',image or '') is not None and
  isinstance(started,str) and name=='/'+CONTAINER and tag==IMAGE and running is True)
 return (cid,image,started,name,tag,running)

def run():
 require(os.path.expanduser('~')=='/Users/jeanbosco')
 require(not any(os.environ.get(k) for k in ('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_CONFIG','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH')))
 before=input_pins();host_before=context_host();container_before=container_identity()
 query=(ROOT/'scripts/supabase/current-pg-transfer/unlinked-sms-import/classification.sql').read_text()
 args=[DOCKER,'--context',CONTEXT,'exec','-i','-u','postgres',CONTAINER,'/usr/bin/env','-i',
  'PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin','LC_ALL=C','/nix/var/nix/profiles/default/bin/psql',
  '-X','-qAt','-v','ON_ERROR_STOP=1','-h','/var/run/postgresql','-U','postgres','-d','postgres']
 raw=command(args,(IDENTITY+query+'\n'+IDENTITY).encode('utf8'))
 obs=validate_output(raw);require(context_host()==host_before and container_identity()==container_before and input_pins()==before)
 report={'format':'collect.native-unlinked-source-observation.v1','source':'configured local service: supabase_db_local-app, point in time',
  'containerImageTag':IMAGE,'observation':obs,'inputHashes':before,
  'verification':{'localUnixDockerContext':True,'containerIdImageAndStartUnchanged':True,
   'databaseSystemPostmasterAndBackendUnchanged':True,'sourceInputsUnchanged':True,'databaseSocketVerified':True,
   'sameBackendLockBeforeSnapshot':True,'sourceFrozen':False},
  'limits':['selected aggregate fields only','unfenced configured local source, point in time','not bound to an independently retained prior database identity','no object-byte/provider/credential/complete-graph proof','not a transfer or authorization']}
 require(OUT.parent.is_dir() and not OUT.exists());fd=os.open(OUT,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
 with os.fdopen(fd,'w') as f:json.dump(report,f,sort_keys=True,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
 return report

if __name__=='__main__':
 try:
  require(sys.argv==[__file__,'--run-local-count']);result=run()
  print(json.dumps({'status':'completed','observation':result['observation'],'sourceFrozen':False},sort_keys=True))
 except Exception:
  print(json.dumps({'status':'refused_or_unconfirmed','observation':None,'sourceFrozen':False}));sys.exit(1)
