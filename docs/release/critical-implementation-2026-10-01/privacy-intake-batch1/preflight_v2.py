"""Task-owned, row-free current-chain context; no hosted/provider/shared writes."""
from pathlib import Path
import datetime,hashlib,json,types,contextlib,traceback
ROOT=Path(__file__).resolve().parents[4]
PACKET=Path(__file__).resolve().parent
HELPER=ROOT/'scripts/tests/collect_current_release_upgrade_uat.py'
BASELINE=ROOT/'.cache/receipt-foundation-attempt8/schema-only.sql'
PREREQ=ROOT/'scripts/sql/receipt_transport_platform_prerequisites.sql'
LOCAL_NET=('alter function net.http_get(text,jsonb,jsonb,integer)security definer;'
 'alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;'
 'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;'
 'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
CATALOG="""select jsonb_build_object(
 'functions',(select jsonb_agg(jsonb_build_object('identity',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),
  'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'config',p.proconfig,'definer',p.prosecdef,
  'anon_execute',has_function_privilege('anon',p.oid,'execute'),'authenticated_execute',has_function_privilege('authenticated',p.oid,'execute'),
  'service_execute',has_function_privilege('service_role',p.oid,'execute'))order by p.oid::regprocedure::text)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where(n.nspname='public'and p.proname in('_lock_notification_session_gate','_notification_session_is_live',
   '_lock_notification_registration_session','lock_notification_auth_revocation','lock_notification_auth_activity',
   'request_account_deletion','is_platform_admin'))or(n.nspname='collect_hybrid'and p.proname in('require_fresh_roster_auth','require_roster_caller'))),
 'tables',(select jsonb_agg(jsonb_build_object('identity',c.oid::regclass::text,'owner',pg_get_userbyid(c.relowner),
  'acl',c.relacl::text,'rls',c.relrowsecurity,'forced_rls',c.relforcerowsecurity,
  'authenticated_select',has_table_privilege('authenticated',c.oid,'select'),
  'authenticated_insert',has_table_privilege('authenticated',c.oid,'insert'),
  'service_select',has_table_privilege('service_role',c.oid,'select'))order by c.oid::regclass::text)
  from pg_class c where c.oid in('public.profiles'::regclass,'public.mobile_account_deletion_requests'::regclass)),
 'policies',(select jsonb_agg(to_jsonb(p)order by policyname)from pg_policies p where schemaname='public'and tablename='mobile_account_deletion_requests'),
 'foreign_keys',(select jsonb_agg(jsonb_build_object('table',c.conrelid::regclass::text,'name',c.conname,'definition',pg_get_constraintdef(c.oid))order by c.conrelid::regclass::text,c.conname)
  from pg_constraint c where c.contype='f'and(c.confrelid in('auth.users'::regclass,'public.profiles'::regclass)
   or c.conrelid='public.mobile_account_deletion_requests'::regclass)),
 'triggers',(select jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,'name',t.tgname,'definition',pg_get_triggerdef(t.oid))order by t.tgrelid::regclass::text,t.tgname)
  from pg_trigger t where not t.tgisinternal and t.tgrelid in('auth.users'::regclass,'auth.sessions'::regclass,'public.mobile_account_deletion_requests'::regclass)),
 'migration_count',(select count(*)from supabase_migrations.schema_migrations),
 'max_version',(select max(version)from supabase_migrations.schema_migrations));"""
def main():
 report=PACKET/'preflight2'
 if report.exists():raise ValueError('Inspect existing terminal/running attempt before reuse')
 report.mkdir();capture=report/'captured-inputs';sources=[Path(__file__),HELPER,BASELINE,PREREQ,*sorted((ROOT/'supabase/migrations').glob('*.sql'))];hashes={}
 for f in sources:
  rel=f.relative_to(ROOT);dest=capture/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(f.read_bytes());hashes[str(rel)]=sha(f)
 assert hashes[str(HELPER.relative_to(ROOT))]=='343cd3b21ac9629347b0080640891eac3bdacdea7df11752b129c5f943b6c33b'
 helper=types.ModuleType('privacy_preflight_helper');helper.__file__=str(capture/HELPER.relative_to(ROOT))
 exec(compile(Path(helper.__file__).read_bytes(),helper.__file__,'exec'),helper.__dict__);helper.ROOT=capture;helper.BASELINE=capture/BASELINE.relative_to(ROOT)
 items=[]
 for f in sorted((capture/'supabase/migrations').glob('*.sql')):
  v,n=f.stem.split('_',1);items.append(dict(path='supabase/migrations/'+f.name,version=v,name=n,body=f.read_text(),sha256=sha(f)))
 assert len(items)==198 and items[-1]['version']=='20261002040000'and len({i['version']for i in items})==198
 result={'status':'running','started_at_utc':now(),'source_sha256':hashes,'target':{},'hosted_written':False,'provider_called':False,'source_rows_copied':False,'scope':'Normalized row-free full current-chain effective helper/ACL/FK context only'}
 def save():(report/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 save()
 try:
  platform,prov=helper.platform_shape();result['platform']=prov;(report/'platform-schema-only.sql').write_text(platform)
  with helper.Target(report,'privacy_preflight',result['target'])as target:
   target.sql(platform,label='retained row-free platform shape')
   with(report/'migration-progress.log').open('w')as progress,contextlib.redirect_stdout(progress):
    for item in items:
     if item['version']=='20261001160000':
      target.sql(LOCAL_NET,user='supabase_admin',label='task-local trusted net metadata')
      target.sql((capture/PREREQ.relative_to(ROOT)).read_text(),user='supabase_admin',label='actual current private-reader prerequisite')
     helper.apply(target,[item],result['target'])
   context=target.json(CATALOG);assert context['migration_count']==198 and context['max_version']=='20261002040000'
   (report/'effective-context.json').write_text(json.dumps(context,indent=2)+'\n');result['effective_context_sha256']=sha(report/'effective-context.json');result['status']='pass'
 except Exception as e:
  result['status']='fail';result['error']=str(e);(report/'failure.txt').write_text(traceback.format_exc());raise
 finally:
  result['changed_inputs']=[f for f,h in hashes.items()if not(ROOT/f).is_file()or sha(ROOT/f)!=h]
  result['migration_path_drift']=sorted(str(f.relative_to(ROOT))for f in(ROOT/'supabase/migrations').glob('*.sql'))!=sorted(i['path']for i in items)
  result['completed_at_utc']=now()
  if result['changed_inputs']or result['migration_path_drift']:result['status']='stale-source'
  name=result['target'].get('container_name')
  if name:
   absent=helper.command([helper.DOCKER,'inspect',name],check=False);result['target']['absence_verified']=absent.returncode!=0 and 'no such object'in absent.stderr.lower()
   if not result['target']['absence_verified']:result['status']='fail'
  save()
 if result['status']!='pass':raise SystemExit(1)
 print(json.dumps({'status':result['status'],'migrations':198,'context_sha256':result['effective_context_sha256'],'cleanup':result['target']['absence_verified']}),flush=True)
if __name__=='__main__':main()
