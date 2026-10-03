#!/usr/bin/env python3
"""One bounded synthetic current208 guard fixture. Reused205 bytes, no new archive."""
import pathlib,subprocess,json,hashlib,types,sys,datetime,uuid
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL');S=pathlib.Path(__file__).resolve().parent
H=ROOT/'.cache/receipt-worker-history-storage-20261002/sql-attempt12'
T=pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08/scripts/tests/collect_current_release_upgrade_uat.py')
sha=lambda b:hashlib.sha256(b).hexdigest()
def main():
 report=pathlib.Path(sys.argv[1]).resolve();assert not report.exists();report.mkdir();(report/'commands').mkdir()
 result={'status':'running','scope':'actual ordinary-owner current208 guard fixture from exact reused selected205 bytes plus three admitted delta migrations; no full208 archive, hosted, Vault, native/device/RPO claim','targets':{},'bindings':{},'checks':[]}
 def save(): (report/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 def bind(p):
  b=p.read_bytes();result['bindings'][str(p)]={'bytes':len(b),'sha256':sha(b)};return b
 helper=bind(T);m=types.ModuleType('retained');m.__file__=str(T);exec(compile(helper,str(T),'exec'),m.__dict__)
 bind(pathlib.Path(m.DOCKER));bind(pathlib.Path(sys.executable));bind(pathlib.Path('/usr/bin/ruby'));bind(pathlib.Path(__file__));bind(S/'overlay_driver.rb');bind(ROOT/'.cache/receipt-successor-workflows-20261001/accepted-successor-observations-archive-current1/proof/attempt4/inputs/reused-predecessor-setup.sql')
 for p in(S/'promote').rglob('*'):
  if p.is_file():bind(p)
 for p in list((S/'promote').rglob('*'))+[pathlib.Path(__file__),S/'overlay_driver.rb']:
  if p.is_file():
   dest=report/'frozen-owned-inputs'/p.relative_to(S);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(p.read_bytes())
 raw=bind(H/'commands/00405.stdout');assert sha(raw)=='c0afe5f1e7faf3610e6acda1228d1021052e6abd913980f4f39231be0fa5d311'
 original=m.command;n=0
 def command(argv,text=None,check=True,timeout=120):
  nonlocal n;n+=1;p=report/'commands'/f'{n:04d}';av=list(argv)
  if av[1:3]==['run','--detach']:
   ix=av.index(m.IMAGE);av[ix:ix]=['--tmpfs','/run/collect:rw,mode=1777'];av+=['-c','pg_net.database_name=template1','-c','collect.recovery_drill=production-archive-v1','-c','unix_socket_directories=/run/collect,/var/run/postgresql']
  if av[1:3]==['run','--detach']:
   # Keep PID1 alive during postmaster restart. The exact image entrypoint still initializes the same PGDATA.
   import shlex
   ix=av.index(m.IMAGE);original_args=av[ix+1:]
   shell='docker-entrypoint.sh '+shlex.join(original_args)+' & child=$!; wait "$child"; while :; do sleep 3600; done'
   av=av[:ix+1]+['sh','-c',shell]
  r=original(av,text,False,timeout);p.with_suffix('.stdout').write_text(r.stdout);p.with_suffix('.stderr').write_text(r.stderr)
  p.with_suffix('.json').write_text(json.dumps({'argv':[x if not x.startswith('POSTGRES_PASSWORD=')else'POSTGRES_PASSWORD=<random-local-only>'for x in av],'input_sha256':sha(text.encode())if text else None,'exit_code':r.returncode,'stdout_sha256':sha(r.stdout.encode()),'stderr_sha256':sha(r.stderr.encode())},indent=2)+'\n')
  if check and r.returncode:raise RuntimeError('retained command failed '+r.stderr[-1000:])
  return r
 m.command=command
 try:
  evidence={};result['targets']['sql']=evidence
  target=m.Target(report,'inactive',evidence);target.name='collect-recovery-inactive-'+uuid.uuid4().hex[:12]
  with target as t:
   t.sql("do $$begin if not exists(select 1 from pg_roles where rolname='supabase_functions_admin')then create user supabase_functions_admin noinherit createrole login noreplication;end if;end$$;",user='supabase_admin')
   t.sql('alter extension pg_graphql drop function graphql_public.graphql(text,text,jsonb,jsonb);drop function graphql_public.graphql(text,text,jsonb,jsonb);\n'+raw.decode(),user='supabase_admin',label='exact retained selected205 fixture; no archive duplication')
   t.sql('alter role postgres nosuperuser;',user='supabase_admin')
   # These three source-identical migrations are guard-fixture admissions, not a full208 restore.
   for version in ['20261002042000','20261002044000','20261002080000']:
    p=next((ROOT/'supabase/migrations').glob(version+'_*.sql'));body=bind(p);t.sql(body.decode(),label='exact ordinary-owner guard delta '+version)
   names=[]
   for p in sorted((ROOT/'supabase/migrations').glob('*.sql')):
    data=bind(p);v=p.name.split('_')[0];names.append(v)
    t.sql('insert into supabase_migrations.schema_migrations(version,name,statements)values('+m.quoted(v)+','+m.quoted(p.stem.split('_',1)[1])+',array['+m.quoted(data.decode())+'])on conflict(version)do nothing;',label='already-applied source version association')
   assert len(names)==208
   (report/'source-catalog.json').write_text(t.scalar(bind(ROOT/'scripts/sql/collect_recovery_source_catalog.sql').decode())+'\n')
   config={'reused_plain_database_sha256':sha(raw),'target':t.name,'docker':m.DOCKER,'report':str(report),'root':str(ROOT),'stage':str(S),'catalog':str(report/'source-catalog.json')}
   (report/'driver.json').write_text(json.dumps(config,indent=2)+'\n')
   r=command(['/usr/bin/ruby',str(S/'overlay_driver.rb'),str(report/'driver.json')],timeout=300)
   driver=json.loads((report/'driver-result.json').read_text());result['driver']=driver
   assert r.returncode==0 and driver['status']=='passed'
  result['checks'].append({'name':'owned target removed','passed':evidence.get('task_container_removed')is True});assert evidence.get('task_container_removed')
  assert all(pathlib.Path(p).stat().st_size==v['bytes']and sha(pathlib.Path(p).read_bytes())==v['sha256']for p,v in result['bindings'].items())
  result['checks'].append({'name':'all captured source/tool/prerequisite inputs unchanged','passed':True});result['status']='passed'
 except Exception as e:result['status']='failed';result['error']=str(e);raise
 finally:
  if 'target' in locals() and target.made and not result['targets']['sql'].get('task_container_removed'):
   target.__exit__(None,None,None)
  save()
if __name__=='__main__':main()
