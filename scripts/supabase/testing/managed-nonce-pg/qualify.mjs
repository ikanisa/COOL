// Run the two owned PostgreSQL fixtures directly and verify all named cases.
// On cancellation, wait for the active fixture's own verified cleanup before
// exiting. A forced kill or host failure can still leave a directory behind.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {assertCompleteTap} from './report.mjs';

const root=fileURLToPath(new URL('../../../..',import.meta.url));
const suites=[
 {file:'supabase/managed-native-ingress/nonce-ledger-pg.test.mjs',expected:[
  'a competing session waits for commit and then denies the duplicate',
  'a rolled-back claim can be claimed by a later transaction',
  'expired signatures and non-runtime callers cannot add claims',
  'a fenced application denies a previously admitted caller',
  'retention authority accepts the exact nonce ledger and rejects privilege drift',
  'nonce ledger uses the real fence SQL and serializes concurrent claims']},
 {file:'supabase/managed-native-ingress/nonce-ledger-lifecycle.test.mjs',expected:[
  'TERM to the fixture parent stops its owned PostgreSQL cluster',
  'an unconfirmed startup retains its owned data directory',
  'TERM during blocked initdb retains its unconfirmed data directory',
  'an unconfirmed stop retains its owned data directory']},
 {file:'scripts/supabase/testing/managed-nonce-pg/interrupted-diagnostics.test.mjs',expected:[
  'nonce wrapper reports an interrupted unconfirmed initdb path',
  'http wrapper reports an interrupted unconfirmed initdb path']}
];
let active=null,interrupted=null;
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>{if(!interrupted)interrupted=signal;active?.kill('SIGTERM');});
for(const suite of suites){
 if(interrupted)throw Error('NONCE_QUALIFICATION_INTERRUPTED: '+interrupted);
 const outcome=await new Promise(resolve=>{
  const child=spawn(process.execPath,['--test-reporter=tap',suite.file],{cwd:root,env:process.env,stdio:['ignore','pipe','pipe']});
  active=child;if(interrupted)child.kill('SIGTERM');
  let stdout='',stderr='',failed=false;
  const collect=which=>chunk=>{
   if(stdout.length+stderr.length+chunk.length>1024*1024){failed=true;child.kill('SIGTERM');return;}
   if(which==='out')stdout+=chunk;else stderr+=chunk;
  };
  child.stdout.setEncoding('utf8');child.stderr.setEncoding('utf8');
  child.stdout.on('data',collect('out'));child.stderr.on('data',collect('err'));
  const timer=setTimeout(()=>{failed=true;child.kill('SIGTERM');},120000);
  child.once('error',error=>{failed=true;stderr+=String(error);});
  child.once('close',(code,signal)=>{clearTimeout(timer);active=null;resolve({code,signal,stdout,stderr,failed});});
 });
 if(interrupted||outcome.failed||outcome.signal||outcome.code!==0){
  // Preserve bounded fixture diagnostics, including paths retained on uncertain cleanup.
  process.stderr.write(outcome.stdout+outcome.stderr);
  throw Error(interrupted?'NONCE_QUALIFICATION_INTERRUPTED: '+interrupted:'NONCE_QUALIFICATION_FAILED: '+suite.file);
 }
 const count=assertCompleteTap(outcome.stdout,suite.expected);
 console.log(`Synthetic nonce qualification passed: ${suite.file} (${count}, no skips)`);
}
