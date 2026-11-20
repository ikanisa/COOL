// Test helper; inputs contain only synthetic root and operation ID.
import {recordSyntheticDispatchIntent} from './synthetic-journal.mjs';
let s='';process.stdin.setEncoding('utf8');process.stdin.on('data',x=>s+=x);process.stdin.on('end',()=>{try{const o=JSON.parse(s);const r=recordSyntheticDispatchIntent({mode:'synthetic',root:o.root,operationId:o.id});process.stdout.write(r.status+'\n');}catch(e){process.stdout.write((e.code??'error')+'\n');process.exitCode=1;}});
