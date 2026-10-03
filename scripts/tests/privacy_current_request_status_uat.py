#!/usr/bin/env python3
"""Current-chain owned offline canonical status proof; no hosted/provider calls."""
from pathlib import Path
import argparse, contextlib, datetime, hashlib, json, traceback, types

ROOT=Path(__file__).resolve().parents[2]
HELPER=Path('scripts/tests/collect_current_release_upgrade_uat.py')
BASELINE=Path('.cache/receipt-foundation-attempt8/schema-only.sql')
PREREQ=Path('scripts/sql/receipt_transport_platform_prerequisites.sql')
OLD_RUNNER=Path('scripts/tests/privacy_request_intake_uat.py')
SQL=Path('scripts/tests/privacy_current_request_status_uat.sql')
OLD_SQL=Path('scripts/tests/privacy_request_intake_uat.sql')
LEGACY=Path('scripts/local_backend_privacy_lifecycle_uat.sql')
VERSION='20261002042000'
WRAPPER='public.get_current_account_deletion_request_status_v1()'
CATALOG="""select jsonb_build_object('functions',(select coalesce(jsonb_object_agg(n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',
 jsonb_build_object('definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),
 'acl',p.proacl::text,'config',p.proconfig,'anon',has_function_privilege('anon',p.oid,'execute'),
 'authenticated',has_function_privilege('authenticated',p.oid,'execute'),
 'service',has_function_privilege('service_role',p.oid,'execute'))),'{}')from pg_proc p
 join pg_namespace n on n.oid=p.pronamespace where p.prokind='f'and(n.nspname='public'or n.nspname like'collect_%')),
 'foreign_keys',(select coalesce(jsonb_object_agg(c.conrelid::regclass::text||':'||c.conname,pg_get_constraintdef(c.oid)),'{}')from pg_constraint c where c.contype='f'),
 'policies',(select coalesce(jsonb_agg(to_jsonb(p)order by p.schemaname,p.tablename,p.policyname),'[]')from pg_policies p where p.schemaname='public'or p.schemaname like'collect_%'),
 'tables',(select coalesce(jsonb_object_agg(c.oid::regclass::text,jsonb_build_object('acl',c.relacl::text,'rls',c.relrowsecurity,'forced',c.relforcerowsecurity)),'{}')from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where c.relkind='r'and(n.nspname='public'or n.nspname like'collect_%')));"""

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--report-dir',required=True);args=parser.parse_args()
 report=Path(args.report_dir).resolve();permitted=ROOT/'docs/release/critical-implementation-2026-10-01/privacy-client-auth-batch2'
 assert report.is_relative_to(permitted)and not report.exists(),'Fresh owned evidence directory required'
 report.mkdir(parents=True);capture=report/'captured-inputs';hashes={};items=[]
 sources=[Path(__file__).relative_to(ROOT),HELPER,BASELINE,PREREQ,OLD_RUNNER,SQL,OLD_SQL,LEGACY,*[p.relative_to(ROOT)for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))]]
 for rel in sources:
  data=(ROOT/rel).read_bytes();dest=capture/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data);hashes[str(rel)]=sha(dest)
 assert hashes[str(HELPER)]=='343cd3b21ac9629347b0080640891eac3bdacdea7df11752b129c5f943b6c33b'
 helper=types.ModuleType('privacy_current_captured_target');helper.__file__=str(capture/HELPER)
 exec(compile((capture/HELPER).read_bytes(),str(capture/HELPER),'exec'),helper.__dict__);helper.ROOT=capture;helper.BASELINE=capture/BASELINE
 intake=types.ModuleType('privacy_current_captured_snapshot');intake.__file__=str(capture/OLD_RUNNER)
 exec(compile((capture/OLD_RUNNER).read_bytes(),str(capture/OLD_RUNNER),'exec'),intake.__dict__)
 for p in sorted((capture/'supabase/migrations').glob('*.sql')):
  version,name=p.stem.split('_',1);datetime.datetime.strptime(version,'%Y%m%d%H%M%S')
  items.append(dict(path='supabase/migrations/'+p.name,version=version,name=name,sha256=sha(p),body=p.read_text()))
 assert len({i['version']for i in items})==len(items)and VERSION in[i['version']for i in items]
 result=dict(status='running',started_at_utc=now(),source_sha256=hashes,migration_count=len(items),max_version=items[-1]['version'],target={},
  hosted_written=False,provider_called=False,signed_jwt_tested=False,source_rows_copied=False,full_privacy_lifecycle_completed=False,
  limits=['Row-free retained Auth/storage shape; task-local normalized PostgreSQL superuser','Synthetic injected claims and real Auth session rows; no signed JWT/provider runtime','Own-current status only; policy/retention/full erasure remain pending'])
 def save():(report/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 save();failure=None;owned_target=None
 try:
  platform,prov=helper.platform_shape();result['platform']=prov;(report/'platform-schema-only.sql').write_text(platform)
  owned_target=helper.Target(report,'privacy_current',result['target'])
  with owned_target as target:
   target.sql(platform,label='captured row-free platform shape')
   with(report/'migration-progress.log').open('w')as log,contextlib.redirect_stdout(log):
    for item in items:
     if item['version']=='20261001160000':
      target.sql(intake.LOCAL_NET,user='supabase_admin',label='isolated trusted net metadata')
      target.sql((capture/PREREQ).read_text(),user='supabase_admin',label='captured maintained transport reader prerequisite')
     if item['version']==VERSION:
      before=target.json(CATALOG);(report/'before-wrapper-catalog.json').write_text(json.dumps(before,indent=2)+'\n')
     helper.apply(target,[item],result['target'])
     if item['version']==VERSION:
      after=target.json(CATALOG);(report/'after-wrapper-catalog.json').write_text(json.dumps(after,indent=2)+'\n')
      functions=dict(after['functions']);wrapper=functions.pop(WRAPPER)
      assert functions==before['functions'],'Existing application functions changed'
      assert all(after[k]==v for k,v in before.items()if k!='functions'),'Existing table ACL, RLS, policies or FK changed'
      assert not wrapper['anon']and wrapper['authenticated']and not wrapper['service'],wrapper
      result['additive_catalog_proof']=dict(only_added_function=WRAPPER,existing_functions=len(functions),foreign_keys=len(before['foreign_keys']),tables=len(before['tables']),all_other_catalog_values_unchanged=True,wrapper=wrapper)
   assert int(target.scalar('select count(*)from supabase_migrations.schema_migrations;'))==len(items)
   assert target.scalar('select max(version)from supabase_migrations.schema_migrations;')==items[-1]['version']
   for label,source,marker in [('legacy',LEGACY,'LOCAL_BACKEND_PRIVACY_LIFECYCLE_PASS'),('intake',OLD_SQL,'PRIVACY_REQUEST_INTAKE_UAT_PASS'),('current',SQL,'PRIVACY_CURRENT_REQUEST_STATUS_UAT_PASS')]:
    before=intake.snapshot(target);execution=target.sql((capture/source).read_text(),check=False,label='actual '+label+' rollback UAT')
    (report/(label+'-uat.log')).write_text(execution.stdout+execution.stderr)
    after=intake.snapshot(target);(report/(label+'-rollback.json')).write_text(json.dumps(dict(before=before,after=after,unchanged=before==after),indent=2)+'\n')
    assert execution.returncode==0 and marker in execution.stdout,(label,execution.returncode,execution.stderr[-3000:])
    assert before==after,label+' rollback altered retained financial/resource rows'
    row=dict(status='pass',marker=marker,tables=len(before),all_rows_unchanged_after_rollback=True)
    if label!='legacy':row['checks']=next(json.loads(line)for line in execution.stdout.splitlines()if line.startswith('{')and marker in line)
    result[label+'_uat']=row;save()
   # Match the retained helper's honest non-current snapshot refusal.
   denied=target.sql("begin isolation level repeatable read;set local role authenticated;select set_config('request.jwt.claims','{}',true);select public.get_current_account_deletion_request_status_v1();rollback;",check=False,label='actual repeatable-read denial')
   (report/'noncurrent-snapshot-denial.log').write_text(denied.stdout+denied.stderr)
   assert denied.returncode==3 and '40001'in denied.stderr and 'privacy_request_snapshot_retry'in denied.stderr
   result['repeatable_read_refused']=True;result['status']='pass'
 except Exception as error:
  result['status']='fail';result['error']=str(error);(report/'failure.txt').write_text(traceback.format_exc());failure=error
 finally:
  if owned_target is not None and owned_target.made:owned_target.close()
  result['changed_inputs']=[p for p,h in hashes.items()if not(ROOT/p).is_file()or sha(ROOT/p)!=h]
  result['migration_path_drift']=sorted(str(p.relative_to(ROOT))for p in(ROOT/'supabase/migrations').glob('*.sql'))!=sorted(i['path']for i in items)
  if result['changed_inputs']or result['migration_path_drift']:result['status']='stale-source'
  name=result['target'].get('container_name')
  if name:
   absent=helper.command([helper.DOCKER,'inspect',name],check=False);result['target']['absence_verified']=absent.returncode!=0 and'no such object'in absent.stderr.lower()
   if not result['target']['absence_verified']:result['status']='fail'
  result['completed_at_utc']=now();save()
 print(json.dumps(dict(status=result['status'],migration_count=len(items),max_version=items[-1]['version'],target_removed=result['target'].get('absence_verified'),error=result.get('error'))),flush=True)
 if failure:raise failure
 if result['status']!='pass':raise SystemExit(1)

if __name__=='__main__':main()
