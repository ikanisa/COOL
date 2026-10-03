from pathlib import Path
import subprocess,time,uuid,json,hashlib,datetime
ROOT=Path.cwd();REPORT=ROOT/'.cache/goal19-runtime-capability-attempt2';REPORT.mkdir(exist_ok=False)
DOCKER='/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
IMAGE='public.ecr.aws/supabase/postgres:17.6.1.095';IID='sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a'
self_bytes=Path(__file__).read_bytes();(REPORT/'executed-runner.py').write_bytes(self_bytes)
name='collect_goal19_probe_'+uuid.uuid4().hex[:12];made=False
x={'scope':'Private cached-image runtime capability probe; no app SQL, source rows, external network, sender or hosted mutation','started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'runner_sha256':hashlib.sha256(self_bytes).hexdigest(),'image':IMAGE,'image_id':IID,'container_name':name,'queries':[]}
def cmd(a,text=None,check=True):
 r=subprocess.run(a,input=text,text=True,capture_output=True,timeout=120)
 if check and r.returncode:raise RuntimeError(r.stderr[-2500:])
 return r
def sql(label,s,user='supabase_admin'):
 r=cmd([DOCKER,'exec','-i',name,'psql','-XqAt','-U',user,'-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],s,False)
 (REPORT/(label+'.sql')).write_text(s+'\n');(REPORT/(label+'.log')).write_text(r.stdout+r.stderr)
 x['queries'].append({'name':label,'user':user,'exit_code':r.returncode,'sql_sha256':hashlib.sha256(s.encode()).hexdigest()})
 if r.returncode:raise RuntimeError(label+': '+r.stderr[-1500:])
 return json.loads(r.stdout.strip().splitlines()[-1])
try:
 assert cmd([DOCKER,'image','inspect',IMAGE,'--format','{{.Id}}']).stdout.strip()==IID
 password=uuid.uuid4().hex+uuid.uuid4().hex
 cid=cmd([DOCKER,'run','--detach','--pull=never','--name',name,'--label','collect.goal19.owner='+name,'--network','none','--tmpfs','/var/lib/postgresql/goal19:rw,size=1073741824','-e','POSTGRES_PASSWORD='+password,'-e','PGDATA=/var/lib/postgresql/goal19/data',IMAGE,'postgres','-D','/var/lib/postgresql/goal19/data','-c','shared_preload_libraries=pg_stat_statements,pgaudit,plpgsql,plpgsql_check,pg_cron,pg_net,pgsodium,auto_explain,pg_tle,plan_filter,supabase_vault','-c','wal_level=logical','-c','cron.database_name=postgres','-c','cron.launch_active_jobs=off','-c','cron.timezone=UTC','-c','pg_net.batch_size=0','-c','listen_addresses=']).stdout.strip();made=True;x['container_id']=cid
 for _ in range(240):
  logs=cmd([DOCKER,'logs',name],check=False)
  if 'PostgreSQL init process complete; ready for start up.' in logs.stdout and cmd([DOCKER,'exec',name,'pg_isready','-U','postgres'],check=False).returncode==0:break
  time.sleep(.25)
 else:raise RuntimeError('Private image initialization bound expired')
 host=json.loads(cmd([DOCKER,'inspect',name,'--format','{{json .HostConfig}}']).stdout);labels=json.loads(cmd([DOCKER,'inspect',name,'--format','{{json .Config.Labels}}']).stdout)
 assert host['NetworkMode']=='none' and not host['PortBindings'] and labels['collect.goal19.owner']==name
 x['guard']={'network':'none','ports':False,'label_verified':True}
 x['environment']=sql('environment',"select jsonb_build_object('server',version(),'shared_preload_libraries',current_setting('shared_preload_libraries'),'cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'listen',current_setting('listen_addresses'),'installed',(select jsonb_agg(jsonb_build_object('name',e.extname,'version',e.extversion,'schema',n.nspname,'owner',r.rolname)order by e.extname)from pg_extension e join pg_namespace n on n.oid=e.extnamespace join pg_roles r on r.oid=e.extowner),'available',(select jsonb_agg(to_jsonb(t)order by name)from(select name,default_version,installed_version from pg_available_extensions where name in('pg_net','pg_cron','supabase_vault','pgsodium','pgcrypto','uuid-ossp','pg_stat_statements'))t));")
 x['roles']=sql('roles',"select jsonb_agg(jsonb_build_object('name',rolname,'superuser',rolsuper,'inherit',rolinherit,'create_role',rolcreaterole,'create_db',rolcreatedb,'bypass_rls',rolbypassrls,'memberships',(select coalesce(jsonb_agg(r.rolname order by r.rolname),'[]')from pg_auth_members m join pg_roles r on r.oid=m.roleid where m.member=p.oid))order by rolname)from pg_roles p where rolname in('postgres','supabase_admin','supabase_auth_admin','supabase_storage_admin','anon','authenticated','service_role');")
 x['platform_acl']=sql('platform-acl',"select jsonb_build_object('schemas',(select jsonb_agg(jsonb_build_object('name',nspname,'owner',pg_get_userbyid(nspowner),'acl',nspacl::text)order by nspname)from pg_namespace where nspname in('auth','storage','net','vault','extensions')),'relations',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'kind',c.relkind,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text)order by n.nspname,c.relname),'[]')from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('auth','storage','net','vault')and c.relkind in('r','v','S')),'publications',(select coalesce(jsonb_agg(jsonb_build_object('name',pubname,'owner',pg_get_userbyid(pubowner))order by pubname),'[]')from pg_publication),'default_acl',(select coalesce(jsonb_agg(jsonb_build_object('role',pg_get_userbyid(d.defaclrole),'schema',n.nspname,'kind',d.defaclobjtype,'acl',d.defaclacl::text)order by n.nspname,d.defaclobjtype),'[]')from pg_default_acl d join pg_namespace n on n.oid=d.defaclnamespace where n.nspname in('auth','storage'))); ")
 x['installer']=sql('default-installer',"select jsonb_build_object('role',current_user,'superuser',(select rolsuper from pg_roles where rolname=current_user),'admin_usage',pg_has_role(current_user,'supabase_admin','USAGE'),'auth_schema_usage',has_schema_privilege(current_user,'auth','USAGE'),'auth_schema_create',has_schema_privilege(current_user,'auth','CREATE'),'net_owner_usage',case when to_regclass('net._http_response')is not null then pg_has_role(current_user,(select relowner from pg_class where oid=to_regclass('net._http_response')),'USAGE')else null end);",'postgres')
 assert x['environment']['cron']=='off' and x['environment']['net']=='0' and x['environment']['listen']==''
 assert next(r for r in x['roles'] if r['name']=='postgres')['superuser'] is False
 x['status']='pass'
except Exception as e:x['status']='failed';x['failure']=str(e)
finally:
 if made:
  logs=cmd([DOCKER,'logs',name],check=False);(REPORT/'container.log').write_text(logs.stdout+logs.stderr)
  x['removed']=cmd([DOCKER,'rm','--force','--volumes',name],check=False).returncode==0
 x['runner_unchanged']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()==x['runner_sha256'];(REPORT/'result.json').write_text(json.dumps(x,indent=2)+'\n');print(json.dumps({k:x[k]for k in ['status','removed','runner_unchanged']if k in x}));print(x.get('failure',''));print('report',REPORT)
