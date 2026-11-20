// Child-process fixture: no socket is permitted, and only a private synthetic
// plan referencing the same test root can reach the live gate.
import https from 'node:https';
import {syncBuiltinESMExports} from 'node:module';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
const [planPath,planSha256,pinsSha256,livePinsSha256,archiveDirectory,keyDirectory]=process.argv.slice(2);
const prefix='/private/tmp/collect-component-capture-test-',end=planPath?.indexOf('/',prefix.length)??-1;
if(!planPath?.startsWith(prefix)||end<=prefix.length)throw Error('SYNTHETIC_PATH_REQUIRED');
const root=planPath.slice(0,end),plan=JSON.parse(await readFile(resolve(planPath),'utf8'));
for(const path of [planPath,plan.preflight_result_path,archiveDirectory,keyDirectory])if(typeof path!=='string'||!path.startsWith(root+'/'))throw Error('SYNTHETIC_PATH_REQUIRED');
let calls=0;https.request=()=>{calls++;throw Error('NETWORK_FORBIDDEN');};syncBuiltinESMExports();
const {executeLive}=await import('./capture-live.mjs');let code;
try{await executeLive({planPath,planSha256,pinsSha256,livePinsSha256,archiveDirectory,keyDirectory,dispatch:'READ_ONLY_CAPTURE'});}
catch(error){code=error?.code;}
if(code!=='COUNT_AUTHORITY_INVALID'||calls!==0)throw Error('SYNTHETIC_EXPECTATION_FAILED');
process.stdout.write(JSON.stringify({status:'rejected_synthetic_count',network_calls:calls})+'\n');
