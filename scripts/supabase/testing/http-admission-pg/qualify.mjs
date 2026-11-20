// Run owned PostgreSQL tests directly and require every named case. Wait for
// fixture cleanup on TERM/INT; forced kill or host loss can still leave evidence.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {assertCompleteTap} from '../managed-nonce-pg/report.mjs';
const root=fileURLToPath(new URL('../../../..',import.meta.url));
const suites=[
 {file:'scripts/supabase/testing/http-admission-pg/native.test.mjs',expected:[
  'real PostgreSQL: cancellation after register COMMIT closes the exact pre-work row once',
  'real PostgreSQL: timeout with late original COMMIT acknowledgement is retained and closed once',
  'real PostgreSQL: lost registration acknowledgement is not guessed, closed or retried',
  'real PostgreSQL: cancelled close with lost acknowledgement is read back and never repeated',
  'real PostgreSQL: duplicate registration cannot close a pre-existing admission',
  'real PostgreSQL: acknowledgement after the bounded cleanup window leaves the original admission active']},
 {file:'scripts/supabase/testing/http-admission-pg/interrupt.test.mjs',expected:[
  'TERM to the active parent stops its owned cluster',
  'TERM to the parent during initdb waits for owned cleanup',
  'TERM to the parent during pg_ctl waits for owned cleanup',
  'TERM to the active process group stops its owned cluster',
  'TERM to the process group during initdb waits for owned cleanup',
  'TERM to the process group during pg_ctl waits for owned cleanup',
  'unconfirmed init retains its owned data directory',
  'unconfirmed startup retains its owned data directory',
  'unconfirmed stop retains its owned data directory']}
];
let active=null,interrupted=null;
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>{if(!interrupted)interrupted=signal;active?.kill('SIGTERM');});
for(const suite of suites){
 if(interrupted)throw Error('HTTP_PG_QUALIFICATION_INTERRUPTED: '+interrupted);
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
  const timer=setTimeout(()=>{failed=true;child.kill('SIGTERM');},240000);
  child.once('error',error=>{failed=true;stderr+=String(error);});
  child.once('close',(code,signal)=>{clearTimeout(timer);active=null;resolve({code,signal,stdout,stderr,failed});});
 });
 if(interrupted||outcome.failed||outcome.signal||outcome.code!==0){
  // Preserve bounded fixture diagnostics, including paths retained on uncertain cleanup.
  process.stderr.write(outcome.stdout+outcome.stderr);
  throw Error(interrupted?'HTTP_PG_QUALIFICATION_INTERRUPTED: '+interrupted:'HTTP_PG_QUALIFICATION_FAILED: '+suite.file);
 }
 const count=assertCompleteTap(outcome.stdout,suite.expected);
 console.log(`Synthetic HTTP admission passed: ${suite.file} (${count}, no skips)`);
}
