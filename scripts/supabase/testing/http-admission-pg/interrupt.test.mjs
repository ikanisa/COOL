// Exercise parent TERM only against owned local PostgreSQL and task-owned wrappers.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {existsSync,mkdirSync,mkdtempSync,readFileSync,readdirSync,realpathSync,rmSync,rmdirSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';

const target=fileURLToPath(new URL('./native.test.mjs',import.meta.url));
const temporary=realpathSync('/tmp'),binary=process.env.COLLECT_HTTP_ADMISSION_PG_BIN_DIR;
let activeChild=null,interrupted=null;
const onSignal=signal=>{if(!interrupted){interrupted=signal;activeChild?.kill('SIGTERM');}};
const onTerm=()=>onSignal('SIGTERM'),onInt=()=>onSignal('SIGINT');
process.on('SIGTERM',onTerm);process.on('SIGINT',onInt);
test.afterEach(()=>{if(interrupted)throw Error('HTTP_ADMISSION_INTERRUPT_TEST_INTERRUPTED: '+interrupted);});
test.after(()=>{process.off('SIGTERM',onTerm);process.off('SIGINT',onInt);});

function start(env){
 if(interrupted)throw Error('HTTP_ADMISSION_INTERRUPT_TEST_INTERRUPTED: '+interrupted);
 const child=spawn(process.execPath,['--test-reporter=tap',target],{
  env:{PATH:'/usr/bin:/bin',LC_ALL:'C',COLLECT_HTTP_ADMISSION_PG_QUALIFY:'true',...env},stdio:['ignore','pipe','pipe'],detached:true});
 activeChild=child;let output='';
 child.stdout.setEncoding('utf8');child.stderr.setEncoding('utf8');
 const collect=chunk=>{output+=chunk;if(output.length>1024*1024)child.kill('SIGTERM');};
 child.stdout.on('data',collect);child.stderr.on('data',collect);
 const closed=new Promise(resolve=>{child.once('error',error=>resolve({error}));child.once('close',(code,signal)=>{if(activeChild===child)activeChild=null;resolve({code,signal});});});
 return {child,closed,output:()=>output};
}
async function waitFor(run,predicate){
 const end=Date.now()+45000;
 while(Date.now()<end){
  if(predicate())return;
  if(run.child.exitCode!==null||run.child.signalCode!==null)throw Error('fixture exited before readiness: '+run.output());
  await delay(25);
 }
 throw Error('fixture readiness timed out: '+run.output());
}
async function stopIfRunning(run){
 if(run.child.exitCode!==null||run.child.signalCode!==null)return;
 run.child.kill('SIGTERM');
 let timer;
 try{await Promise.race([run.closed,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('fixture did not exit after TERM')),180000);})]);}
 finally{clearTimeout(timer);}
}
function removeOnlyStoppedTask(temp,fixtures){
 try{
  if(readdirSync(fixtures).length!==0)throw Error('owned fixture evidence remains');
  rmSync(temp,{recursive:true,force:true});
 }catch{console.error('HTTP admission interrupt-test evidence retained:',temp);}
}

async function checkActiveParent(group){
 assert.ok(binary,'Set COLLECT_HTTP_ADMISSION_PG_BIN_DIR to PostgreSQL 17 tools');
 const temp=mkdtempSync(join(temporary,'http-parent-')),fixtures=join(temp,'pg');mkdirSync(fixtures);
 const run=start({COLLECT_HTTP_ADMISSION_PG_BIN_DIR:binary,COLLECT_HTTP_ADMISSION_PG_TMP_ROOT:fixtures,COLLECT_HTTP_ADMISSION_TEST_HOLD_READY:'true'});
 try{
  await waitFor(run,()=>run.output().includes('COLLECT_HTTP_ADMISSION_FIXTURE_READY'));
  const names=readdirSync(fixtures);assert.equal(names.length,1);
  const root=join(fixtures,names[0]),pid=Number(readFileSync(join(root,'data','postmaster.pid'),'utf8').split('\n')[0]);
  assert.ok(Number.isSafeInteger(pid)&&pid>1);
  if(group)process.kill(-run.child.pid,'SIGTERM');else run.child.kill('SIGTERM');
  const result=await run.closed;
  assert.notEqual(result.code,0,run.output());assert.equal(result.signal,null,run.output());
  assert.match(run.output(),/HTTP_ADMISSION_TEST_INTERRUPTED/);
  assert.deepEqual(readdirSync(fixtures),[]);assert.throws(()=>process.kill(pid,0),{code:'ESRCH'});
 }finally{try{await stopIfRunning(run);}finally{removeOnlyStoppedTask(temp,fixtures);}}
}

async function checkStartupParent(group,stage){
 assert.ok(binary,'Set COLLECT_HTTP_ADMISSION_PG_BIN_DIR to PostgreSQL 17 tools');
 const temp=mkdtempSync(join(temporary,'http-start-')),fixtures=join(temp,'pg'),wrappers=join(temp,'bin'),marker=join(temp,'startup-ready');
 mkdirSync(fixtures);mkdirSync(wrappers);
 for(const name of ['postgres','initdb','pg_ctl','psql']){
  const extra=name===stage?(stage==='initdb'
   ?`if [ "$1" != --version ]; then touch "${marker}"; sleep 2; fi\n`
   :`case " $* " in *" start "*) touch "${marker}"; sleep 2 ;; esac\n`):'';
  writeFileSync(join(wrappers,name),`#!/bin/sh\n${extra}exec "${binary}/${name}" "$@"\n`,{mode:0o700});
 }
 const run=start({COLLECT_HTTP_ADMISSION_PG_BIN_DIR:wrappers,COLLECT_HTTP_ADMISSION_PG_TMP_ROOT:fixtures});
 try{
  await waitFor(run,()=>existsSync(marker));
  assert.equal(readdirSync(fixtures).length,1);
  if(group)process.kill(-run.child.pid,'SIGTERM');else run.child.kill('SIGTERM');
  await delay(250);
  assert.equal(run.child.exitCode,null,'parent must wait while startup is still running');
  const result=await run.closed;assert.notEqual(result.code,0,run.output());assert.equal(result.signal,null,run.output());
  assert.match(run.output(),/HTTP_ADMISSION_TEST_INTERRUPTED/);assert.deepEqual(readdirSync(fixtures),[]);
 }finally{try{await stopIfRunning(run);}finally{removeOnlyStoppedTask(temp,fixtures);}}
}

for(const group of [false,true]){
 const label=group?'process group':'parent';
 test('TERM to the active '+label+' stops its owned cluster',{timeout:180000},()=>checkActiveParent(group));
 for(const stage of ['initdb','pg_ctl'])test('TERM to the '+label+' during '+stage+' waits for owned cleanup',
  {timeout:180000},()=>checkStartupParent(group,stage));
}

async function checkUnconfirmed(stage){
 const temp=mkdtempSync(join(temporary,'http-fake-')),fixtures=join(temp,'pg'),bin=join(temp,'bin'),stopMarker=join(temp,'stop-called');
 mkdirSync(fixtures);mkdirSync(bin);
 const script=(name,body)=>writeFileSync(join(bin,name),`#!/bin/sh\nif [ "$1" = --version ]; then echo '${name} (PostgreSQL) 17.1'; exit 0; fi\n${body}\n`,{mode:0o700});
 script('postgres','exit 1');script('psql','exit 1');script('initdb','mkdir -p "$2"; exit '+(stage==='init'?1:0));
 // These owned stubs never start or signal a server. The synthetic PID is not
 // used as a process target; startup/stop failures must preserve the directory.
 const startExit=stage==='startup'?1:0;
 script('pg_ctl',`case " $* " in *" start "*) printf "2147483647\\n%s\\n" "$2" > "$2/postmaster.pid"; exit ${startExit} ;; *" stop "*) touch "${stopMarker}"; exit 1 ;; *) exit 3 ;; esac`);
 const run=start({COLLECT_HTTP_ADMISSION_PG_BIN_DIR:bin,COLLECT_HTTP_ADMISSION_PG_TMP_ROOT:fixtures});
 try{
  const result=await run.closed;assert.notEqual(result.code,0,run.output());
  const expected=stage==='init'?'HTTP_ADMISSION_INIT_UNCONFIRMED':stage==='startup'?'HTTP_ADMISSION_START_UNCONFIRMED':'HTTP_ADMISSION_SERVER_STOP_UNCONFIRMED';
  assert.ok(run.output().includes(expected),run.output());
  const names=readdirSync(fixtures);assert.equal(names.length,1);
  assert.equal(existsSync(join(fixtures,names[0],'data')),true);
  assert.equal(existsSync(join(fixtures,names[0],'data','postmaster.pid')),stage!=='init');
  assert.equal(existsSync(stopMarker),stage==='stop');
 }finally{
  await stopIfRunning(run);
  // The exact binaries above are test-owned stubs and never created a server.
  rmSync(temp,{recursive:true,force:true});
 }
}
for(const stage of ['init','startup','stop'])test('unconfirmed '+stage+' retains its owned data directory',
 {timeout:60000},()=>checkUnconfirmed(stage));
