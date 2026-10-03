from pathlib import Path
import hashlib,json,os,signal,subprocess,time
root=Path.cwd();base=root/'docs/release/critical-implementation-2026-10-01/arc09-lint32-tooling-resolution-recovery1';py=Path('/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3');config=json.loads((base.parent/'kotlin-sdk-native-native-stage-preparation1/proposed-commands.json').read_text());java=Path(config['JDK_java_executable'])
dist=Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/gradle-home/wrapper/dists/gradle-9.1.0-all/7wzd0jkjit61aq2p43wpjgij9/gradle-9.1.0')
def sha(raw):return hashlib.sha256(raw).hexdigest()
if sha(java.read_bytes())!=config['JDK_java_SHA256']:raise SystemExit('pinned Java changed')
references=json.loads((base/'reference-source-fences-before.json').read_text())['sources'];external=json.loads((base/'source-fences.json').read_text())['inputs'];classpath=sorted((dist/'lib').glob('*.jar'))+sorted((dist/'lib/plugins').glob('*.jar'));rows=[{'path':str(p),'sha256':sha(p.read_bytes()),'bytes':len(p.read_bytes())} for p in classpath]
(base/'limited-test-classpath-fences-before.json').write_text(json.dumps({'java_path':str(java),'java_sha256':config['JDK_java_SHA256'],'Gradle_invocation':False,'runtime':'standalone Groovy from installed Gradle 9.1.0, imports/compilation and Throwable fixtures only','jar_files':rows},indent=2)+'\n')
def fences():
 for row in [*references,*external,*rows]:
  if sha(Path(row['path']).read_bytes())!=row['sha256']:raise SystemExit('limited-test source drift: '+row['path'])
def run(name,argv):
 fences();t0=time.monotonic();p=subprocess.Popen(argv,cwd=base,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True);timed_out=False
 try:stdout,stderr=p.communicate(timeout=30)
 except subprocess.TimeoutExpired:
  timed_out=True;os.killpg(p.pid,signal.SIGTERM)
  try:stdout,stderr=p.communicate(timeout=3)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);stdout,stderr=p.communicate()
 result={'argv':argv,'cwd':str(base),'exit_code':p.returncode,'actual_seconds':time.monotonic()-t0,'deadline_seconds':30,'timed_out':timed_out,'owned_group_id':p.pid,'Gradle_invoked':False,'network_invoked':False,'stdout_sha256':sha(stdout),'stderr_sha256':sha(stderr)}
 try:os.killpg(p.pid,0);result['owned_group_absent']=False
 except ProcessLookupError:result['owned_group_absent']=True
 fences();result['all_reference_external_and_classpath_fences_match_after']=True
 for suffix,data in [('stdout.txt',stdout),('stderr.txt',stderr)]:(base/(name+'.'+suffix)).write_bytes(data)
 (base/(name+'.json')).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result),flush=True);print(stdout.decode()+stderr.decode(),flush=True)
 if p.returncode or timed_out or not result['owned_group_absent']:raise SystemExit(1)
run('python-limited-checks',[str(py),'-I','-B',str(base/'limited_preparation_test.py')])
(base/'test-home').mkdir();(base/'test-tmp').mkdir()
argv=[str(java),'-Duser.home='+str(base/'test-home'),'-Djava.io.tmpdir='+str(base/'test-tmp'),'-cp',str(dist/'lib/*')+':'+str(dist/'lib/plugins/*'),'groovy.ui.GroovyMain',str(base/'limited_groovy_checks.groovy'),str(base/'minimal-project/build.gradle')]
run('groovy-limited-checks',argv)
(base/'limited-test-classpath-fences-after.json').write_text(json.dumps({'jar_files':rows,'references_and_inputs_unchanged':True,'all_jars_unchanged':True,'Gradle_invocation':False},indent=2)+'\n')
