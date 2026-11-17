// Supervised worker: errors are fixed codes and never include SQL or passwords.
import {readPrivateInput} from './input.mjs';
import {captureManagedArchive,applyManagedArchive,reconcileManagedArchive} from './operator.mjs';
import {cleanEnvironment} from '../current-pg-transfer/principal-mapping-operator/protocol.mjs';
const safe=new Set(['PRIVATE_INPUT_REFUSED','MANAGED_CONNECTION_UNAVAILABLE','MANAGED_TRANSPORT_REFUSED','MANAGED_APPLY_UNQUALIFIED',
 'QUERY_TIMEOUT_UNKNOWN','SYNTHETIC_HISTORY_MISMATCH','SYNTHETIC_FENCE_NOT_FENCED','ARCHIVE_OBJECT_ALREADY_PRESENT',
 'CATALOG_TOO_LARGE','FENCE_TOO_LARGE','PREIMAGE_TOO_LARGE','ADMISSION_CAP','OWNED_SESSION_CHANGED']);
const stop=()=>process.exit(143);process.once('SIGTERM',stop);process.once('SIGINT',stop);
let r;
try{
 if(process.argv.length!==2||!cleanEnvironment())throw Error();const v=await readPrivateInput();
 if(v.action==='capture')r=await captureManagedArchive({secret:v.password,timeoutMs:v.timeoutMs});
 else if(v.action==='apply')r=await applyManagedArchive({secret:v.password,root:v.journalRoot,plan:v.plan,timeoutMs:v.timeoutMs});
 else if(v.action==='reconcile')r=await reconcileManagedArchive({secret:v.password,root:v.journalRoot,plan:v.plan,timeoutMs:v.timeoutMs});
 else throw Error();
}catch(e){r={status:'refused',code:safe.has(e?.archiveCode)?e.archiveCode:'OPERATION_UNCONFIRMED',writeAuthorized:false};process.exitCode=1;}
try{await new Promise((resolve,reject)=>process.stdout.write(JSON.stringify(r)+'\n',e=>e?reject(e):resolve()));}catch{process.exitCode=1;}
