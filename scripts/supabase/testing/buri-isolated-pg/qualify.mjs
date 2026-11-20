// Run the retained BuriMunsi PostgreSQL tests against disposable local PG17.
// The private `docker` shim only translates their fixed synthetic invocations
// to this process's own Unix socket; no Docker daemon or existing DB is used.
import {execFileSync,spawn,spawnSync} from 'node:child_process';
import {chmodSync,mkdirSync,mkdtempSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import {randomInt} from 'node:crypto';
import {isAbsolute,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {assertCompleteTap} from './report.mjs';
import {setImmediate as yieldToSignals} from 'node:timers/promises';

const bin=process.env.COLLECT_BURI_TEST_PG_BIN_DIR,qualify=process.env.COLLECT_BURI_TEST_PG_QUALIFY;
if(qualify!=='true'||!bin||!isAbsolute(bin)||realpathSync(bin)!==bin||!/^\/[A-Za-z0-9_./-]+$/.test(bin))throw Error('EXPLICIT_PHYSICAL_POSTGRES_17_REQUIRED');
if(typeof process.getuid!=='function'||process.getuid()===0)throw Error('SYNTHETIC_FIXTURE_REQUIRES_NONROOT');
const parent=realpathSync(process.env.COLLECT_BURI_TEST_TMP_ROOT??tmpdir());
if(!/^\/[A-Za-z0-9_./-]+$/.test(parent))throw Error('SYNTHETIC_FIXTURE_TEMP_PATH_REQUIRED');
const repo=resolve(fileURLToPath(new URL('../../../..',import.meta.url)));
if(parent===repo||parent.startsWith(repo+'/')||repo.startsWith(parent+'/'))throw Error('SYNTHETIC_FIXTURE_TEMP_MUST_BE_SEPARATE');
let interrupted=null,activeChild=null,killTimer=null;
function stopChild(signal='SIGTERM'){
 if(!activeChild?.pid)return;
 try{process.kill(-activeChild.pid,signal);}catch{}
}
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>{
 interrupted=signal;stopChild();
 if(activeChild&&!killTimer){killTimer=setTimeout(()=>stopChild('SIGKILL'),3000);killTimer.unref();}
});
const requireRunning=()=>{if(interrupted)throw Error('SYNTHETIC_BURI_INTERRUPTED: '+interrupted);};
async function runSuite(suite,env){
 return await new Promise((resolvePromise,reject)=>{
  const child=spawn(process.execPath,['--test','--test-reporter=tap','--test-concurrency=1',...suite.files],
   {cwd:repo,env,detached:true,stdio:['ignore','pipe','pipe']});activeChild=child;
  const chunks=[],errors=[];let size=0,failed=false;
  const collect=dest=>data=>{size+=data.length;if(size>1024*1024){failed=true;stopChild('SIGKILL');}else dest.push(data);};
  child.stdout.on('data',collect(chunks));child.stderr.on('data',collect(errors));
  const timer=setTimeout(()=>{failed=true;stopChild('SIGKILL');},120000);
  child.once('error',()=>{failed=true;});
  child.once('close',(code,signal)=>{
   clearTimeout(timer);if(killTimer){clearTimeout(killTimer);killTimer=null;}activeChild=null;
   const stdout=Buffer.concat(chunks).toString('utf8'),stderr=Buffer.concat(errors).toString('utf8');
   if(interrupted||failed||signal||code!==0){if(!interrupted)process.stderr.write(stdout+stderr);reject(Error(interrupted?'SYNTHETIC_BURI_INTERRUPTED: '+interrupted:'SYNTHETIC_BURI_SUITE_FAILED: '+suite.label));return;}
   try{resolvePromise(assertCompleteTap(stdout,suite.expected));}catch(error){reject(error);}
  });
 });
}
const suites=[
 {label:'read-only-ctes',container:'supabase_db_local-app',context:'collect-synthetic-only',files:[
  'supabase/functions/_shared/tests/burimunsi/smart-onboarding-postgres-fixture.test.mjs',
  'supabase/functions/_shared/tests/burimunsi/command-outcome-conflict-postgres.test.mjs',
  'supabase/functions/_shared/tests/burimunsi/payment-conflict-read-model-postgres.test.mjs'],variable:'BURI_POSTGRES_FIXTURE_CONTEXT',value:'collect-synthetic-only',expected:[
  'Postgres suggestions preserve managed phones and native name/masked-suffix identity',
  'a conflicting cross-source receipt prevents clean financial outcome on PostgreSQL',
  'conflicting sources disappear from unallocated counts and change the page revision']},
 {label:'observation-dedup',container:'codex-burimunsi-sms-dedup-fixture',context:'colima-supabase-local',files:[
  'supabase/functions/_shared/tests/burimunsi/observation-source-keys-postgres.test.mjs'],variable:'BURI_DEDUP_TEST_CONTAINER',value:'codex-burimunsi-sms-dedup-fixture',expected:[
  'real PostgreSQL source reservation preserves exact replay, distinct rows and authorization']},
 {label:'observation-history',container:'codex-burimunsi-sms-history-fixture',context:'colima-supabase-local',files:[
  'supabase/functions/_shared/tests/burimunsi/observation-history-postgres.test.mjs'],variable:'BURI_HISTORY_TEST_CONTAINER',value:'codex-burimunsi-sms-history-fixture',expected:[
  'account SMS history preserves scope, audit, consent, grant and retained-object boundaries',
  'historical authorization rows stay locked until a disclosure transaction ends']}
];
for(const name of ['postgres','initdb','pg_ctl','psql']){
 const path=join(bin,name),out=execFileSync(path,['--version'],{encoding:'utf8',env:{PATH:'/usr/bin:/bin',LC_ALL:'C'},timeout:15000});
 if(!new RegExp('^'+name+' \\(PostgreSQL\\) 17\\.').test(out))throw Error('POSTGRES_17_BINARIES_REQUIRED');
}
for(const suite of suites){
 await yieldToSignals();requireRunning();
 const root=mkdtempSync(join(parent,'collect-buri-fixture-')),data=join(root,'data'),socket=join(root,'socket'),log=join(root,'postgres.log'),shims=join(root,'bin');
 chmodSync(root,0o700);mkdirSync(socket,{mode:0o700});mkdirSync(shims,{mode:0o700});
 const port=randomInt(20000,60000),toolEnv={PATH:'/usr/bin:/bin',LC_ALL:'C',TMPDIR:root};
 const run=(name,args,extra={})=>execFileSync(join(bin,name),args,{env:toolEnv,stdio:'ignore',timeout:30000,...extra});
 let startAttempted=false,stopped=false;
 try{
  run('initdb',['-D',data,'--username=postgres','--auth-local=trust','--auth-host=reject','--encoding=UTF8','--no-instructions']);
  await yieldToSignals();requireRunning();
  startAttempted=true;run('pg_ctl',['-D',data,'-l',log,'-o',`-k ${socket} -p ${port} -c listen_addresses='' -c unix_socket_permissions=0700`,'-w','start']);
  await yieldToSignals();requireRunning();
  const psql=join(bin,'psql'),baseArgs=['-h',socket,'-p',String(port),'-U','postgres','-d','postgres','-XAtq','-v','ON_ERROR_STOP=1'];
  const identity=execFileSync(psql,[...baseArgs,'-c',"SELECT (inet_server_addr() IS NULL)::text||':'||current_setting('data_directory')||':'||(current_setting('server_version_num')::int/10000)::text"],{env:toolEnv,encoding:'utf8',timeout:10000}).trim();
  if(identity!==`true:${data}:17`)throw Error('SYNTHETIC_POSTGRES_IDENTITY_MISMATCH');
  await yieldToSignals();requireRunning();
  execFileSync(psql,[...baseArgs,'-c','CREATE ROLE supabase_admin SUPERUSER LOGIN; CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; CREATE ROLE service_role NOLOGIN'],{env:toolEnv,stdio:'ignore',timeout:10000});
  await yieldToSignals();requireRunning();
  // This shim accepts only the exact docker-exec-shaped command of the current
  // test group. It cannot address another host, port, user or database.
  const shim=`#!/usr/bin/python3\nimport os,sys\na=sys.argv[1:]\nexpected=${JSON.stringify(suite.context)}\ncontainer=${JSON.stringify(suite.container)}\nif len(a)<6 or a[:3]!=['--context',expected,'exec']:sys.exit(91)\ni=3\nif a[i]=='-i':i+=1\nif a[i:i+2]!=[container,'psql']:sys.exit(92)\na=a[i+2:]\nif len(a)<4 or a[0]!='-U' or a[1] not in ('postgres','supabase_admin') or a[2:4]!=['-d','postgres']:sys.exit(93)\nj=4\nwhile j<len(a):\n if a[j] in ('-X','-A','-t','-q','-XAtq'):j+=1\n elif a[j]=='-v' and j+1<len(a) and a[j+1]=='ON_ERROR_STOP=1':j+=2\n elif a[j]=='-c' and j+1<len(a):j+=2\n else:sys.exit(94)\np=${JSON.stringify(psql)}\nos.execve(p,[p,'-h',${JSON.stringify(socket)},'-p',${JSON.stringify(String(port))}]+a,{'PATH':'/usr/bin:/bin','LC_ALL':'C'})\n`;
  const executable=join(shims,'docker');writeFileSync(executable,shim,{mode:0o700});
  const env={PATH:shims+':/usr/bin:/bin',LC_ALL:'C',TMPDIR:root,[suite.variable]:suite.value};
  await yieldToSignals();requireRunning();
  console.log(`Synthetic PostgreSQL suite started: ${suite.label}`);
  const passed=await runSuite(suite,env);
  console.log(`Synthetic PostgreSQL suite passed: ${suite.label} (${passed}, no skips)`);
 }finally{
  if(startAttempted){
   let status=spawnSync(join(bin,'pg_ctl'),['-D',data,'status'],{env:toolEnv,stdio:'ignore',timeout:15000});
   if(status.status===0){run('pg_ctl',['-D',data,'-m','fast','-w','stop']);status=spawnSync(join(bin,'pg_ctl'),['-D',data,'status'],{env:toolEnv,stdio:'ignore',timeout:15000});}
   if(status.error||status.status!==3)throw Error('SYNTHETIC_POSTGRES_CLEANUP_UNCONFIRMED: '+root);
   stopped=true;
  }
  if(!startAttempted||stopped)rmSync(root,{recursive:true,force:true});
 }
 await yieldToSignals();requireRunning();
}
