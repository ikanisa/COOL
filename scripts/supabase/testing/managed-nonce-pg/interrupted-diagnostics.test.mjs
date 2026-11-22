// Both qualifier wrappers must expose retained-path diagnostics on cancellation.
// Every PostgreSQL-named binary below is an owned stub; no server is started.
import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {existsSync,mkdirSync,mkdtempSync,readFileSync,readdirSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';

const root=fileURLToPath(new URL('../../../..',import.meta.url));
const temporary=realpathSync('/tmp');
let activeChild=null,releasePath=null,interrupted=null;
function interrupt(signal){
 if(interrupted)return;
 interrupted=signal;
 if(releasePath)try{writeFileSync(releasePath,'release');}catch{}
 activeChild?.kill('SIGTERM');
}
const onTerm=()=>interrupt('SIGTERM'),onInt=()=>interrupt('SIGINT');
process.on('SIGTERM',onTerm);process.on('SIGINT',onInt);
test.afterEach(()=>{if(interrupted)throw Error('QUALIFIER_DIAGNOSTIC_TEST_INTERRUPTED: '+interrupted);});
test.after(()=>{process.off('SIGTERM',onTerm);process.off('SIGINT',onInt);});

function alive(pid){
 try{process.kill(pid,0);return true;}catch(error){if(error.code==='ESRCH')return false;throw error;}
}

async function verifyInterruptedDiagnostic(kind){
 if(interrupted)throw Error('QUALIFIER_DIAGNOSTIC_TEST_INTERRUPTED: '+interrupted);
 const task=mkdtempSync(join(temporary,'qdi-')),bin=join(task,'bin'),fixtures=join(task,'pg');
 const marker=join(task,'init-ready'),pidFile=join(task,'init-pid'),release=join(task,'release'),stopMarker=join(task,'pg-ctl-called');
 mkdirSync(bin);mkdirSync(fixtures);releasePath=release;
 for(const name of ['postgres','initdb','pg_ctl','psql']){
  let body='exit 1';
  if(name==='pg_ctl')body=`touch "${stopMarker}"; exit 1`;
  if(name==='initdb')body=`mkdir -p "$2"; printf '%s' "$$" > "${pidFile}"; touch "${marker}"; while [ ! -f "${release}" ]; do sleep 0.1; done; exit 1`;
  writeFileSync(join(bin,name),`#!/bin/sh\nif [ "$1" = --version ]; then echo '${name} (PostgreSQL) 17.1'; exit 0; fi\n${body}\n`,{mode:0o700});
 }
 const nonce=kind==='nonce';
 const wrapper=nonce?'scripts/supabase/testing/managed-nonce-pg/qualify.mjs':'scripts/supabase/testing/http-admission-pg/qualify.mjs';
 const env=nonce?{COLLECT_INGRESS_TEST_PG_BIN_DIR:bin,COLLECT_INGRESS_TEST_TMP_ROOT:fixtures}:{
  COLLECT_HTTP_ADMISSION_PG_QUALIFY:'true',COLLECT_HTTP_ADMISSION_PG_BIN_DIR:bin,COLLECT_HTTP_ADMISSION_PG_TMP_ROOT:fixtures};
 const child=spawn(process.execPath,[wrapper],{cwd:root,env:{PATH:'/usr/bin:/bin',LC_ALL:'C',...env},stdio:['ignore','pipe','pipe'],detached:true});
 activeChild=child;let output='';
 child.stdout.setEncoding('utf8');child.stderr.setEncoding('utf8');
 const collect=chunk=>{output+=chunk;if(output.length>1024*1024)child.kill('SIGTERM');};
 child.stdout.on('data',collect);child.stderr.on('data',collect);
 const closed=new Promise(resolve=>{
  child.once('error',error=>resolve({error}));
  child.once('close',(code,signal)=>{if(activeChild===child)activeChild=null;resolve({code,signal});});
 });
 let fakePid=null;
 try{
  const deadline=Date.now()+15000;
  while(!existsSync(marker)&&Date.now()<deadline&&child.exitCode===null&&child.signalCode===null)await delay(25);
  assert.ok(existsSync(marker),'owned fake initdb did not start: '+output);
  fakePid=Number(readFileSync(pidFile,'utf8'));
  assert.ok(Number.isSafeInteger(fakePid)&&fakePid>1);
  assert.equal(readdirSync(fixtures).length,1);
  child.kill('SIGTERM');
  // HTTP waits for its detached initdb; nonce interrupts its task-owned group.
  await delay(250);writeFileSync(release,'release');
  const result=await Promise.race([closed,delay(20000,undefined,{ref:false}).then(()=>{throw Error('qualifier did not stop after interruption');})]);
  assert.notEqual(result.code,0,output);assert.equal(result.signal,null,output);
  const names=readdirSync(fixtures);assert.equal(names.length,1,'the unconfirmed fixture must remain');
  const retained=join(fixtures,names[0]);
  assert.equal(realpathSync(retained),retained);
  assert.ok(names[0].startsWith(nonce?'collect-ingress-pg-':'collect-http-admission-pg-'));
  assert.equal(existsSync(join(retained,nonce?'db':'data')),true);
  assert.equal(existsSync(stopMarker),false,'the fake pg_ctl must not be invoked');
  const diagnostic=nonce?'SYNTHETIC_INGRESS_INIT_UNCONFIRMED':'HTTP_ADMISSION_INIT_UNCONFIRMED';
  assert.ok(output.includes(diagnostic+': '+retained),'wrapper omitted retained-path diagnostic: '+output);
  assert.ok(output.includes(nonce?'NONCE_QUALIFICATION_INTERRUPTED':'HTTP_PG_QUALIFICATION_INTERRUPTED'));
 }finally{
  // Releasing this test-owned stub cannot start a server; it merely exits 1.
  writeFileSync(release,'release');
  if(child.exitCode===null&&child.signalCode===null){
   child.kill('SIGTERM');
   await Promise.race([closed,delay(20000,undefined,{ref:false}).then(()=>{throw Error('qualifier cleanup did not finish');})]);
  }
  releasePath=null;
  if(fakePid===null&&existsSync(pidFile)){
   const candidate=Number(readFileSync(pidFile,'utf8'));
   if(Number.isSafeInteger(candidate)&&candidate>1)fakePid=candidate;
  }
  if(fakePid!==null){
   const deadline=Date.now()+5000;
   while(alive(fakePid)&&Date.now()<deadline)await delay(25);
  }
  // Only delete this task's stubs and fixture after its fake initdb has exited.
  const noUnknownInit=fakePid===null?readdirSync(fixtures).length===0:!alive(fakePid);
  if((child.exitCode!==null||child.signalCode!==null)&&noUnknownInit)rmSync(task,{recursive:true,force:true});
  else{
   console.error('Owned synthetic diagnostic evidence retained:',task);
   throw Error('QUALIFIER_DIAGNOSTIC_TEST_CLEANUP_UNCONFIRMED');
  }
 }
}

for(const kind of ['nonce','http'])test(kind+' wrapper reports an interrupted unconfirmed initdb path',
 {timeout:45000},()=>verifyInterruptedDiagnostic(kind));
