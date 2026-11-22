// Test helper; inputs contain only synthetic root and operation ID.
import {recordDispatchIntent} from './journal.mjs';
let s='';process.stdin.setEncoding('utf8');process.stdin.on('data',x=>s+=x);process.stdin.on('end',()=>{try{const o=JSON.parse(s);const r=recordDispatchIntent({mode:'synthetic',root:o.root,operationId:o.id,planSha256:o.planSha256});process.stdout.write(r.status+'\n');}catch(e){process.stdout.write((e.code??'error')+'\n');process.exitCode=1;}});
