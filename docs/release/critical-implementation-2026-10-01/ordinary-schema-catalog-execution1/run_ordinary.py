from pathlib import Path
import datetime,hashlib,json,os,re,signal,stat,subprocess,sys,time
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
PREP=HERE.parent/'ordinary-schema-catalog-preparation1'
PLAN=json.loads((PREP/'candidate-inputs.json').read_bytes())
CANDIDATE=Path(PLAN['candidate']);OUTPUT=CANDIDATE/'docs/release/ordinary-effective-catalog1'
DOCKER='/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
ENV={'PATH':'/usr/bin:/bin','PYTHONDONTWRITEBYTECODE':'1'}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def source(base):
 result={}
 for rel in PLAN['sources']:
  p=base/rel;s=p.lstat();assert stat.S_ISREG(s.st_mode) and not p.is_symlink() and s.st_nlink==1
  result[rel]=sha(p)
 return result
def metadata(name,args,accept=(0,)):
 r=subprocess.run(args,cwd=CANDIDATE,env=ENV,capture_output=True,text=True,timeout=15)
 (HERE/(name+'.stdout')).write_text(r.stdout);(HERE/(name+'.stderr')).write_text(r.stderr)
 RECORD['metadata'].append({'name':name,'command':args,'exit_code':r.returncode})
 if r.returncode not in accept:raise RuntimeError('Metadata failed: '+name)
 return r
RECORD={'status':'failed','started_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'whole_deadline_seconds':600,'maintained_mutations':0,'hosted_or_provider_calls':False,'candidate':str(CANDIDATE),'metadata':[]}
start=time.monotonic();child=None
try:
 expected={rel:row['sha256'] for rel,row in PLAN['sources'].items()}
 assert source(CANDIDATE)==expected and source(ROOT)==expected and not OUTPUT.exists()
 RECORD['source_before']=expected
 socket=metadata('local-docker-socket',[DOCKER,'context','inspect','--format','{{.Endpoints.docker.Host}}']).stdout.strip();assert socket.startswith('unix://');ENV['DOCKER_HOST']=socket
 image=metadata('cached-image',[DOCKER,'image','inspect','public.ecr.aws/supabase/postgres:17.6.1.095','--format','{{.Id}}']).stdout.strip();assert image=='sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a'
 command=[sys.executable,'-B',str(HERE/'run_child.py'),str(CANDIDATE),str(OUTPUT),str(HERE/'owned-targets.jsonl')];RECORD['command']=command
 with (HERE/'rehearsal.stdout').open('xb') as stdout,(HERE/'rehearsal.stderr').open('xb') as stderr:
  child=subprocess.Popen(command,cwd=CANDIDATE,env=ENV,stdin=subprocess.DEVNULL,stdout=stdout,stderr=stderr,start_new_session=True)
  RECORD['owned_child_pid']=child.pid
  while child.poll() is None:
   if time.monotonic()-start>=600:
    os.killpg(child.pid,signal.SIGKILL);child.wait(timeout=5);raise RuntimeError('Whole600-second deadline exceeded')
   time.sleep(1)
 RECORD['exit_code']=child.returncode
 result=json.loads((OUTPUT/'result.json').read_bytes());RECORD['rehearsal_status']=result['status'];RECORD['case_count']=len(result['cases'])
 if child.returncode!=0 or result['status']!='pass' or result['all_task_containers_removed'] is not True:raise RuntimeError('Actual complete ordinary rehearsal failed')
 RECORD['status']='pass'
except BaseException as error:
 RECORD['error']=str(error)
 if child is not None and child.poll() is None:os.killpg(child.pid,signal.SIGKILL);child.wait(timeout=5)
finally:
 owned=HERE/'owned-targets.jsonl';RECORD['owned_cleanup']=[]
 if owned.exists():
  for line in owned.read_text().splitlines():
   target=json.loads(line);name=target['name'];assert re.fullmatch(r'collect_current_rehearsal_ordinary_(clean|populated)_[0-9a-f]{12}',name)
   r=metadata('target-'+target['phase']+'-inspect',[DOCKER,'container','inspect',name],accept=(0,1))
   if r.returncode==0:
    value=json.loads(r.stdout)[0];assert value['Config']['Labels']['collect.rehearsal.owner']==name and value['Image']==target['image_id'] and value['HostConfig']['NetworkMode']=='none' and not value['HostConfig']['PortBindings']
    metadata('target-'+target['phase']+'-fallback',[DOCKER,'rm','--force','--volumes',name]);RECORD['status']='failed';RECORD['cleanup_fallback_required']=True
   else:assert ('no such container: '+name) in r.stderr.lower() or ('no such object: '+name) in r.stderr.lower()
   RECORD['owned_cleanup'].append({'name':name,'absent_after_rehearsal':r.returncode==1})
 RECORD['source_after']=source(CANDIDATE);RECORD['private_source_unchanged']=RECORD.get('source_before')==RECORD['source_after']
 maintained=source(ROOT);RECORD['current_source_drift']={rel:h for rel,h in maintained.items() if h!=PLAN['sources'][rel]['sha256']}
 known={rel for rel in PLAN['sources'] if rel.startswith('supabase/migrations/')};RECORD['current_added_migrations']=[str(p.relative_to(ROOT)) for p in (ROOT/'supabase/migrations').glob('*.sql') if str(p.relative_to(ROOT)) not in known]
 if not RECORD['private_source_unchanged']:RECORD['status']='failed'
 RECORD['elapsed_seconds']=time.monotonic()-start;RECORD['finished_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
 (HERE/'execution-result.json').write_text(json.dumps(RECORD,indent=2)+'\n')
print(json.dumps({k:RECORD.get(k) for k in ['status','case_count','elapsed_seconds','error','private_source_unchanged','current_source_drift','current_added_migrations']}))
raise SystemExit(0 if RECORD['status']=='pass' else 1)
