// Private child: input contains only paths, pins and non-secret configuration.
import {executeReadOnlyDump} from './execute.mjs';
import {readAttempt} from './journal.mjs';
import {verifyCompletedBundle} from './verify.mjs';
import {planDigest} from './supervisor.mjs';
import {fstatSync,writeSync} from 'node:fs';
import {cleanDiagnostic} from './diagnostics.mjs';
// Stay as the original group leader after TERM so the supervisor can safely
// escalate while that leader is still alive. An unexpected leader exit still
// leaves cleanup unconfirmed; no stale group ID is signalled on that path.
let terminationHold;process.on('SIGTERM',()=>{terminationHold??=setInterval(()=>{},1000);});
function progress(event){const safe=cleanDiagnostic(event);if(!safe)return;try{const s=fstatSync(3);if(!s.isSocket()&&!s.isFIFO())return;writeSync(3,JSON.stringify(safe)+'\n');}catch{}}
let raw='',size=0;process.stdin.setEncoding('utf8');process.stdin.on('data',s=>{size+=Buffer.byteLength(s);if(size>65536)process.exit(2);raw+=s;});
process.stdin.on('end',async()=>{try{const q=JSON.parse(raw);raw='';let r;
 if(q.action==='dump'){if(!q.plan||planDigest(q.plan)!==q.planSha256)throw Error();r=await executeReadOnlyDump(q.plan.request,q.planSha256,progress);}
 else if(q.action==='status')r=readAttempt({mode:q.mode,root:q.root,operationId:q.operationId,planSha256:q.expectedPlanSha256});
 else if(q.action==='verify')r=await verifyCompletedBundle(q.request);
 else throw Error();process.stdout.write(JSON.stringify(r));
 }catch{raw='';process.stdout.write(JSON.stringify({status:'worker_outcome_unconfirmed'}));process.exitCode=1;}});
