// Exercises only fresh local clusters and test-owned fake PostgreSQL tools.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {existsSync,mkdirSync,mkdtempSync,readFileSync,realpathSync,rmSync,rmdirSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const fixture=fileURLToPath(new URL('./nonce-ledger-pg.test.mjs',import.meta.url));
const physicalTmp=realpathSync('/tmp');
const binary=process.env.COLLECT_INGRESS_TEST_PG_BIN_DIR;
let activeChild=null,interrupted=null;
const interrupt=sig=>{if(!interrupted){interrupted=sig;activeChild?.kill('SIGTERM');}};
const onTerm=()=>interrupt('SIGTERM'),onInt=()=>interrupt('SIGINT');
process.on('SIGTERM',onTerm);process.on('SIGINT',onInt);
test.afterEach(()=>{if(interrupted)throw Error('SYNTHETIC_INGRESS_LIFECYCLE_INTERRUPTED: '+interrupted);});
test.after(()=>{process.off('SIGTERM',onTerm);process.off('SIGINT',onInt);});

function startFixture(env){
 if(interrupted)throw Error('SYNTHETIC_INGRESS_LIFECYCLE_INTERRUPTED: '+interrupted);
 const child=spawn(process.execPath,[fixture],{env:{PATH:'/usr/bin:/bin',LC_ALL:'C',...env},stdio:['ignore','pipe','pipe']});
 activeChild=child;
 let output='',notify;
 child.stdout.setEncoding('utf8');child.stderr.setEncoding('utf8');
 const collect=chunk=>{output+=chunk;if(output.length>1024*1024)child.kill('SIGTERM');notify?.();};
 child.stdout.on('data',collect);child.stderr.on('data',collect);
 const closed=new Promise(resolve=>{child.once('error',error=>resolve({error}));child.once('close',(code,signal)=>{if(activeChild===child)activeChild=null;resolve({code,signal});});});
 async function marker(pattern,timeout=30000){
  const end=Date.now()+timeout;
  while(Date.now()<end){
   const match=output.match(pattern);if(match)return match;
   if(child.exitCode!==null||child.signalCode!==null)throw Error('fixture exited before marker: '+output);
   await Promise.race([new Promise(resolve=>{notify=resolve;}),new Promise(resolve=>setTimeout(resolve,50))]);notify=undefined;
  }
  throw Error('fixture marker timeout: '+output);
 }
 return {child,closed,marker,output:()=>output};
}

async function stopIfRunning(run){
 if(run.child.exitCode!==null||run.child.signalCode!==null)return;
 run.child.kill('SIGTERM');
 let timer;
 try{await Promise.race([run.closed,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('fixture did not exit after TERM')),40000);})]);}
 finally{clearTimeout(timer);}
}

test('TERM to the fixture parent stops its owned PostgreSQL cluster', {timeout:60000},async()=>{
 assert.ok(binary,'Set COLLECT_INGRESS_TEST_PG_BIN_DIR to PostgreSQL 17 tools');
 const temp=mkdtempSync(join(physicalTmp,'collect-ingress-lifecycle-'));
 const run=startFixture({COLLECT_INGRESS_TEST_PG_BIN_DIR:binary,COLLECT_INGRESS_TEST_TMP_ROOT:temp,COLLECT_INGRESS_TEST_HOLD_READY:'true'});
 let root;
 try{
  const [,json]=await run.marker(/COLLECT_INGRESS_FIXTURE_READY (\{[^\r\n]+\})/);
  const ready=JSON.parse(json);root=ready.root;
  assert.equal(realpathSync(root),root);assert.equal(root.startsWith(temp+'/collect-ingress-pg-'),true);
  assert.equal(Number(readFileSync(join(root,'db','postmaster.pid'),'utf8').split('\n')[0]),ready.serverPid);
  run.child.kill('SIGTERM');const result=await run.closed;
  assert.notEqual(result.code,0,run.output());
  assert.equal(existsSync(root),false,'the stopped, owned cluster must be removed');
  assert.throws(()=>process.kill(ready.serverPid,0),{code:'ESRCH'});
 }finally{
  try{await stopIfRunning(run);}
  finally{try{rmdirSync(temp);}catch{console.error('Synthetic lifecycle directory retained:',temp);}}
 }
});

test('an unconfirmed startup retains its owned data directory', {timeout:30000},async()=>{
 const temp=mkdtempSync(join(physicalTmp,'collect-ingress-fake-start-'));
 const bin=join(temp,'bin'),target=join(temp,'target');mkdirSync(bin);mkdirSync(target);
 const script=(name,body)=>writeFileSync(join(bin,name),`#!/bin/sh\nif [ "$1" = --version ]; then echo '${name} (PostgreSQL) 17.1'; exit 0; fi\n${body}\n`,{mode:0o700});
 script('postgres','exit 1');script('initdb','mkdir -p "$2"');
 // This owned stub creates a marker only; it never starts or signals a server.
 script('pg_ctl',`case " $* " in *" stop "*) touch "${join(temp,'stop-was-called')}" ;; esac\nprintf "2147483647\\n%s\\n" "$2" > "$2/postmaster.pid"; exit 1`);
 const run=startFixture({COLLECT_INGRESS_TEST_PG_BIN_DIR:bin,COLLECT_INGRESS_TEST_TMP_ROOT:target});
 try{
  const result=await run.closed;assert.notEqual(result.code,0,run.output());
  const match=run.output().match(/SYNTHETIC_INGRESS_START_UNCONFIRMED: (\/[A-Za-z0-9_./-]+)/);
  assert.ok(match,run.output());const root=match[1];
  assert.equal(realpathSync(root),root);assert.equal(root.startsWith(target+'/collect-ingress-pg-'),true);
  assert.equal(existsSync(join(root,'db','postmaster.pid')),true);
  assert.equal(existsSync(join(temp,'stop-was-called')),false,'an unconfirmed server must not be signalled');
 }finally{
  await stopIfRunning(run);
  // The binaries above are test-owned stubs and never created a server.
  rmSync(temp,{recursive:true,force:true});
 }
});

test('TERM during blocked initdb retains its unconfirmed data directory', {timeout:30000},async()=>{
 const temp=mkdtempSync(join(physicalTmp,'collect-ingress-fake-init-'));
 const bin=join(temp,'bin'),target=join(temp,'target'),marker=join(temp,'init-ready');mkdirSync(bin);mkdirSync(target);
 const script=(name,body)=>writeFileSync(join(bin,name),`#!/bin/sh\nif [ "$1" = --version ]; then echo '${name} (PostgreSQL) 17.1'; exit 0; fi\n${body}\n`,{mode:0o700});
 script('postgres','exit 1');script('pg_ctl','exit 1');
 script('initdb',`mkdir -p "$2"; touch "${marker}"; exec /bin/sleep 60`);
 const run=startFixture({COLLECT_INGRESS_TEST_PG_BIN_DIR:bin,COLLECT_INGRESS_TEST_TMP_ROOT:target});
 try{
  const deadline=Date.now()+10000;
  while(!existsSync(marker)&&Date.now()<deadline&&run.child.exitCode===null)await new Promise(resolve=>setTimeout(resolve,25));
  assert.equal(existsSync(marker),true,'owned fake initdb must be running');
  run.child.kill('SIGTERM');const result=await run.closed;assert.notEqual(result.code,0,run.output());
  const match=run.output().match(/SYNTHETIC_INGRESS_INIT_UNCONFIRMED: (\/[A-Za-z0-9_./-]+)/);
  assert.ok(match,run.output());const root=match[1];
  assert.equal(realpathSync(root),root);assert.equal(root.startsWith(target+'/collect-ingress-pg-'),true);
  assert.equal(existsSync(join(root,'db')),true);
 }finally{
  await stopIfRunning(run);
  // This exact initdb stub runs only an owned sleep and creates no server.
  rmSync(temp,{recursive:true,force:true});
 }
});

test('an unconfirmed stop retains its owned data directory', {timeout:30000},async()=>{
 const temp=mkdtempSync(join(physicalTmp,'collect-ingress-fake-stop-'));
 const bin=join(temp,'bin'),target=join(temp,'target');mkdirSync(bin);mkdirSync(target);
 const script=(name,body)=>writeFileSync(join(bin,name),`#!/bin/sh\nif [ "$1" = --version ]; then echo '${name} (PostgreSQL) 17.1'; exit 0; fi\n${body}\n`,{mode:0o700});
 script('postgres','exit 1');script('initdb','mkdir -p "$2"');
 // Fake start records a nonexistent PID. The fake stop reports failure, and no
 // stub starts, stops or signals an operating-system process.
 script('pg_ctl','case " $* " in *" start "*) printf "2147483647\\n%s\\n" "$2" > "$2/postmaster.pid"; exit 0 ;; *) exit 1 ;; esac');
 const run=startFixture({COLLECT_INGRESS_TEST_PG_BIN_DIR:bin,COLLECT_INGRESS_TEST_TMP_ROOT:target});
 try{
  const result=await run.closed;assert.notEqual(result.code,0,run.output());
  const match=run.output().match(/SYNTHETIC_INGRESS_STOP_UNCONFIRMED: (\/[A-Za-z0-9_./-]+)/);
  assert.ok(match,run.output());const root=match[1];
  assert.equal(realpathSync(root),root);assert.equal(root.startsWith(target+'/collect-ingress-pg-'),true);
  assert.equal(existsSync(join(root,'db','postmaster.pid')),true);
 }finally{
  await stopIfRunning(run);
  // The binaries above are test-owned stubs and never created a server.
  rmSync(temp,{recursive:true,force:true});
 }
});
