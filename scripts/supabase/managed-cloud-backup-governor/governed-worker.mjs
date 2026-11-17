// Child of the synthetic supervisor. Inputs contain paths and public fixture CA,
// never password/key bytes. No managed execution path exists.
import {prepareSyntheticAttempt,readSyntheticAttempt,recordSyntheticDispatchIntent,recordSyntheticOutcome} from './synthetic-journal.mjs';
import {createSyntheticBoundBackup} from './synthetic-bound-with-block-map.mjs';
import {spawn} from 'node:child_process';
import {realpathSync} from 'node:fs';
let data='';process.stdin.setEncoding('utf8');process.stdin.on('data',x=>{data+=x;if(data.length>131072)process.exit(2);});
process.stdin.on('end',async()=>{try{const q=JSON.parse(data);data='';if(q.mode!=='synthetic')process.exit(2);const journal={mode:'synthetic',root:q.root,operationId:q.operationId};
 if(q.action==='read'){process.stdout.write(JSON.stringify(readSyntheticAttempt(journal)));return;}
 if(q.action==='hang_before_prepare'){setInterval(()=>{},1000);return;}
 if(q.action==='blocked_before_prepare'){Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,60000);return;}
 if(q.action==='synthetic_backup'||q.action==='synthetic_backup_missing_ack'){
  const root=realpathSync(q.root),scratch=realpathSync(q.config.scratchPath);
  if(root===scratch||root.startsWith(scratch+'/')||scratch.startsWith(root+'/'))throw Error('fixture_roots_overlap');
 }
 prepareSyntheticAttempt(journal);recordSyntheticDispatchIntent(journal);
 if(q.action==='hang_after_dispatch'){process.on('SIGTERM',()=>{});setInterval(()=>{},1000);return;}
 if(q.action==='hang_with_child'){process.on('SIGTERM',()=>{});spawn(process.execPath,['-e','process.on("SIGTERM",()=>{});setInterval(()=>{},1000)'],{stdio:'ignore'});setInterval(()=>{},1000);return;}
 if(q.action==='fixture_complete'||q.action==='fixture_missing_ack'){
  recordSyntheticOutcome({...journal,outcome:'completed',artifactSha256:'f'.repeat(64)});
  if(q.action==='fixture_complete')process.stdout.write(JSON.stringify({status:'completed',artifactSha256:'f'.repeat(64)}));return;
 }
 if(q.action==='synthetic_backup'||q.action==='synthetic_backup_missing_ack'){
  const c=q.config;c.fixtureCa=Buffer.from(c.fixtureCaBase64,'base64');delete c.fixtureCaBase64;c.signal=null;c.mode='synthetic';
  try{const r=await createSyntheticBoundBackup(c);if(r.status!=='synthetic_bound_backup_inspected')throw Error('unconfirmed');
   recordSyntheticOutcome({...journal,outcome:'completed',artifactSha256:r.ciphertextSha256});if(q.action==='synthetic_backup')process.stdout.write(JSON.stringify({status:'completed',artifactSha256:r.ciphertextSha256}));
  }catch{try{recordSyntheticOutcome({...journal,outcome:'outcome_unknown',artifactSha256:null});}catch{}process.stdout.write(JSON.stringify({status:'outcome_unknown'}));}
  return;
 }
 process.exitCode=2;
 }catch{process.stdout.write(JSON.stringify({status:'worker_refused_or_unconfirmed'}));process.exitCode=1;}});
