#!/usr/bin/env python3
"""Real Linux sandbox/HTTP malicious corpus; no DB/provider/hosted operations."""
from __future__ import annotations
import argparse,base64,hashlib,hmac,json,os,re,secrets,signal,subprocess,sys,time,uuid
from pathlib import Path
from urllib.request import Request,urlopen
from urllib.error import HTTPError

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/qa'))
from roster_wheelhouse import prepare_build_context,verify_prepared_context
SOURCES=[*sorted((ROOT/'tools/roster-decoder').glob('*.py')),*sorted((ROOT/'tools/roster-decoder').glob('requirements.*')),
 ROOT/'tools/roster-decoder/Dockerfile',Path(__file__),ROOT/'scripts/qa/roster_wheelhouse.py',
 ROOT/'scripts/tests/roster_wheelhouse_test.py',
 *[ROOT/p for p in [
 'supabase/functions/_shared/roster_decoder.ts','supabase/functions/_shared/roster_decoder_test.ts',
 'supabase/functions/_shared/roster_decoder_integration_test.ts','supabase/functions/_shared/roster_resource_budget.ts',
 'supabase/functions/_shared/roster_import.ts','supabase/functions/_shared/roster_import_test.ts',
 'supabase/functions/_shared/roster_provenance.ts','supabase/functions/_shared/roster_file_policy.ts',
 'supabase/functions/_shared/roster_file_policy_test.ts','supabase/functions/_shared/roster_response_policy.ts',
 'supabase/functions/_shared/roster_response_policy_test.ts','supabase/functions/_shared/openai_roster.ts',
 'supabase/functions/_shared/openai_roster_test.ts','supabase/functions/_shared/production_contract.ts',
 'supabase/functions/_shared/cors.ts','supabase/functions/_shared/test_assert.ts',
 'supabase/functions/prepare-roster-import/handler.ts','supabase/functions/prepare-roster-import/handler_test.ts',
 'supabase/functions/prepare-roster-import/index.ts','supabase/migrations/20260930140000_roster_resource_integrity.sql',
 'scripts/tests/roster_resource_integrity_uat.sql','scripts/tests/roster_resource_final_compatibility_uat.sql',
 'scripts/tests/roster_resource_concurrency_uat.rb','scripts/tests/roster_extraction_evaluation.ts',
 'scripts/tests/roster_extraction_evaluation_test.ts']]]
def hashes():return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES}
def docker_build_command(image,context):
 return ['docker','build','--network=none','--no-cache','-t',image,str(context)]
def run(command,log,timeout=120,input=None):
 # Stream output to owned evidence before a real command deadline can expire.
 # The isolated process group contains only this invocation's client children.
 with log.open('x') as evidence:
  process=subprocess.Popen(command,cwd=ROOT,text=True,
   stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
   stdout=evidence,stderr=subprocess.STDOUT,start_new_session=True)
  try:
   process.communicate(input=input,timeout=timeout)
  except subprocess.TimeoutExpired as error:
   try:os.killpg(process.pid,signal.SIGTERM)
   except ProcessLookupError:pass
   try:process.communicate(timeout=2)
   except subprocess.TimeoutExpired:
    try:os.killpg(process.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    process.communicate(timeout=2)
   # Reap a client child even when its immediate parent exited after TERM.
   try:os.killpg(process.pid,signal.SIGKILL)
   except ProcessLookupError:pass
   evidence.write(f'\nCOMMAND_TIMEOUT seconds={timeout} owned_parent_reaped={process.poll() is not None}\n')
   evidence.flush()
   raise RuntimeError(f'Command timed out after {timeout}s; inspect {log.name}') from error
 output=log.read_text()
 if process.returncode:raise RuntimeError(f'Command failed; inspect {log.name}')
 return output
def main():
 parser=argparse.ArgumentParser(allow_abbrev=False);parser.add_argument('--output',required=True);parser.add_argument('--python',required=True)
 parser.add_argument('--wheel-source',type=Path,required=True)
 parser.add_argument('--publisher-receipt',type=Path,required=True)
 parser.add_argument('--publisher-sha256',required=True)
 parser.add_argument('--metadata-directory',type=Path,required=True)
 args=parser.parse_args()
 output=Path(args.output).resolve();output.mkdir(parents=True,exist_ok=False)
 before=hashes();name='collect_roster_decoder_'+uuid.uuid4().hex[:12];image=name+':qa'
 secret='synthetic-local-only-'+secrets.token_hex(24)
 result={'passed':False,'synthetic_only':True,'provider_accuracy_verified':False,'source_before':before,'cases':[]}
 started=False
 try:
  result['wheelhouse']=prepare_build_context(decoder_directory=ROOT/'tools/roster-decoder',
   wheel_source=args.wheel_source,publisher_receipt=args.publisher_receipt,
   publisher_sha256=args.publisher_sha256,metadata_directory=args.metadata_directory,
   destination=output/'build-context')
  (output/'prepared-wheelhouse.json').write_text(json.dumps(result['wheelhouse'],indent=2)+'\n')
  run([args.python,'tools/roster-decoder/generate_fixtures.py',str(output/'fixtures')],output/'generation.log')
  verify_prepared_context(result['wheelhouse'])
  result['wheelhouse_rechecked_before_build']=True
  run(docker_build_command(image,output/'build-context'),output/'build.log',300)
  build_sha=hashlib.sha256(json.dumps({name:hashlib.sha256((ROOT/'tools/roster-decoder'/name).read_bytes()).hexdigest() for name in ['decoder.py','server.py','requirements.lock','Dockerfile']},sort_keys=True,separators=(',',':')).encode()).hexdigest()
  result['decoder_build_sha256']=build_sha
  result['image_id']=run(['docker','image','inspect',image,'--format','{{.Id}}'],output/'image.log').strip()
  security_command=['docker','run','--rm','--name',name+'_dependency_security','--network','none',
   '--read-only','--security-opt','no-new-privileges','--cap-drop','ALL','--memory','896m',
   '--cpus','2','--pids-limit','32','--tmpfs','/tmp:rw,noexec,nosuid,size=16m',
   '--mount',f'type=bind,src={ROOT / "tools/roster-decoder/test_dependency_security.py"},dst=/app/test_dependency_security.py,readonly',
   result['image_id'],'python','-I','/app/test_dependency_security.py']
  security_log=output/'dependency-security.log'
  run(security_command,security_log,30)
  security_text=security_log.read_text()
  assert re.search(r'^Ran 6 tests in [0-9.]+s$',security_text,re.M)
  assert re.search(r'^OK$',security_text,re.M) and 'skipped' not in security_text.lower()
  result['dependency_security']={'tests_passed':6,'tests_failed':0,'tests_skipped':0,
   'network_none_requested':True,'image_id':result['image_id'],'command':security_command,
   'log_sha256':hashlib.sha256(security_log.read_bytes()).hexdigest()}
  (output/'state').mkdir()
  run(['docker','run','-d','--name',name,'--read-only','--security-opt','no-new-privileges','--cap-drop','ALL',
   '--memory','896m','--cpus','2','--pids-limit','32','--tmpfs','/tmp:rw,noexec,nosuid,size=16m',
   '--mount',f'type=bind,src={output / "state"},dst=/state','-e',f'ROSTER_DECODER_SECRET={secret}',
   '-p','127.0.0.1::8080',image],output/'start.log');started=True
  port=run(['docker','port',name,'8080/tcp'],output/'port.log').strip().rsplit(':',1)[1]
  endpoint=f'http://127.0.0.1:{port}/decode'
  ready=False
  for _ in range(50):
   try:
    with urlopen(endpoint,timeout=1) as response:ready=True
   except HTTPError:ready=True
   except OSError:time.sleep(.1)
   if ready:break
  assert ready,'Decoder supervisor did not become ready'
  def send(body,signature=None):
   raw=json.dumps(body,ensure_ascii=False,separators=(',',':')).encode()
   signed=signature or hmac.new(secret.encode(),raw,hashlib.sha256).hexdigest()
   request=Request(endpoint,data=raw,headers={'Content-Type':'application/json','Authorization':'Roster-HMAC '+signed})
   try:
    response=urlopen(request,timeout=15)
   except HTTPError as error:response=error
   with response:
    status=response.status;data=json.loads(response.read(550001))
   if status==200:
    assert set(data)=={'payload','signature'}
    assert hmac.compare_digest(data['signature'],hmac.new(secret.encode(),data['payload'].encode(),hashlib.sha256).hexdigest())
    data=json.loads(data['payload'])
    for key in ['request_id','reservation_id','nonce','source_sha256','kind','mime']:assert data[key]==body[key]
    assert data['decoder_build_sha256']==build_sha
    assert data['source_size']==len(base64.b64decode(body['content_base64']))
    assert data['toolchain']=={'python':'3.12','pillow':'12.3.0','pypdfium2':'5.2.0','pypdf':'6.19.0','openpyxl':'3.1.5','defusedxml':'0.7.1'}
    if body['kind']=='xlsx':assert hashlib.sha256(data['derived_content'].encode()).hexdigest()==data['derived_sha256']
   else:assert set(data)=={'error'} and data['error'].startswith('roster_')
   return status,data
  manifest=json.loads((output/'fixtures/manifest.json').read_text())
  last=None
  for fixture in manifest['fixtures']:
   if fixture['kind']=='text':continue
   source=(output/'fixtures'/fixture['path']).read_bytes();suffix=Path(fixture['path']).suffix
   mime={'.png':'image/png','.jpg':'image/jpeg','.webp':'image/webp','.pdf':'application/pdf','.xlsx':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}[suffix]
   body={'request_id':str(uuid.uuid4()),'reservation_id':str(uuid.uuid4()),'source_sha256':fixture['sha256'],'mime':mime,
    'kind':fixture['kind'],'content_base64':base64.b64encode(source).decode(),'policy_version':'collect-roster-decoder-v1',
    'nonce':str(uuid.uuid4()),'issued_at':int(time.time())}
   status,data=send(body);accepted=status==200
   result['cases'].append({'id':fixture['id'],'status':status,'accepted':accepted,'expected_accepted':fixture['accepted'],
    'labels':fixture['labels'],'source_sha256':fixture['sha256'],'error':data.get('error')})
   if accepted!=fixture['accepted']:raise RuntimeError(f"Unexpected decode outcome: {fixture['id']}")
   last=body
  assert last
  status,_=send(last);assert status==409;result['cases'].append({'id':'nonce-replay','status':status})
  last={**last,'nonce':str(uuid.uuid4()),'issued_at':int(time.time())}
  status,_=send(last,'0'*64);assert status==401;result['cases'].append({'id':'bad-signature','status':status})
  status,_=send({**last,'source_sha256':'0'*64});assert status==422;result['cases'].append({'id':'source-substitution','status':status})
  status,_=send({**last,'nonce':str(uuid.uuid4()),'issued_at':int(time.time())-90});assert status==400;result['cases'].append({'id':'expired-request','status':status})
  # Actual Linux enforcement probes, independent of parser return values.
  probe='import decoder,socket;decoder.isolate();\ntry: socket.socket();raise AssertionError("socket allowed")\nexcept PermissionError: print("NETWORK_DENIED")\ntry: bytearray(1024*1024*1024);raise AssertionError("memory unbounded")\nexcept MemoryError: print("MEMORY_DENIED")'
  logged=run(['docker','exec',name,'python','-c',probe],output/'isolation.log')
  assert 'NETWORK_DENIED' in logged and 'MEMORY_DENIED' in logged
  private_probe='import decoder;decoder.isolate();\ntry: open("/proc/1/environ","rb").read();raise AssertionError("parent credentials readable")\nexcept PermissionError: print("PARENT_CREDENTIALS_DENIED")'
  logged=run(['docker','exec',name,'python','-c',private_probe],output/'credential-isolation.log')
  assert 'PARENT_CREDENTIALS_DENIED' in logged
  spin=subprocess.run(['docker','exec',name,'python','-c','import decoder;decoder.isolate();exec("while True: pass")'],capture_output=True,text=True,timeout=9)
  (output/'cpu-limit.log').write_text(f'exit_code={spin.returncode}\n'+spin.stdout+spin.stderr)
  assert spin.returncode!=0
  environment={**os.environ,'ROSTER_DECODER_TEST_URL':endpoint,'ROSTER_DECODER_TEST_SECRET':secret,
   'ROSTER_DECODER_TEST_FIXTURES':str(output/'fixtures'),'ROSTER_DECODER_TEST_BUILD_SHA256':build_sha}
  tested=subprocess.run(['deno','test','--allow-env','--allow-read='+str(output/'fixtures'),'--allow-net=127.0.0.1',
   'supabase/functions/_shared/roster_decoder_integration_test.ts'],cwd=ROOT,env=environment,capture_output=True,text=True,timeout=90)
  (output/'edge-decoder-integration.log').write_text(tested.stdout+tested.stderr)
  assert tested.returncode==0
  regressions=['supabase/functions/_shared/'+n for n in ['roster_decoder_test.ts','roster_file_policy_test.ts','roster_response_policy_test.ts','roster_import_test.ts','openai_roster_test.ts']]+['supabase/functions/prepare-roster-import/handler_test.ts','scripts/tests/roster_extraction_evaluation_test.ts']
  run(['deno','test',*regressions],output/'regressions.log')
  run(['deno','run','--allow-read='+str(output/'fixtures'),'--allow-write='+str(output/'evaluation.json'),
       'scripts/tests/roster_extraction_evaluation.ts',str(output/'fixtures'),str(output/'evaluation.json')],output/'evaluation.log')
  run(['deno','check',*[str(p.relative_to(ROOT)) for p in SOURCES if p.suffix=='.ts']],output/'types.log')
  run(['ruby','-c','scripts/tests/roster_resource_concurrency_uat.rb'],output/'concurrency-syntax.log')
  result['source_after']=hashes();assert result['source_after']==before
  snapshots=output/'source-snapshot';snapshots.mkdir()
  for p in SOURCES:
   target=snapshots/p.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(p.read_bytes())
  result['passed']=True
 except Exception as error:
  result['error']=str(error)
  raise
 finally:
  if started:
   run(['docker','logs',name],output/'supervisor.log')
   run(['docker','rm','-f',name],output/'stop.log')
  result['logs']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in output.glob('*.log')}
  (output/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
 if not result['passed']:raise SystemExit(1)
 print(json.dumps({'passed':True,'decoder_cases':len(result['cases']),'source_files':len(before),'manifest':str(output/'validation.json')}))
if __name__=='__main__':main()
