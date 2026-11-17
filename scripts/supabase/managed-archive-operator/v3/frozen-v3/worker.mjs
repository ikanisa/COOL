// V3 owned-fixture worker. Managed mode remains hard closed.
import pg from '../../node_modules/pg/lib/index.js';
import {readPrivateInput} from '../input.mjs';
import {captureArchivePreimage} from '../archive-core.mjs';
import {verifyV3} from './source.mjs';
import {recordBackend} from './journal.mjs';
import {identifyCaptureBackend} from './identity.mjs';
const fail=code=>{throw Object.assign(Error(code),{captureCode:code});};
let client;
const stop=()=>{try{client?.connection?.stream?.destroy();}catch{}process.exit(143);};process.once('SIGTERM',stop);process.once('SIGINT',stop);
let result;
try{
 if(process.argv.length!==4||process.argv[3]!=='synthetic')fail('MANAGED_CAPTURE_UNQUALIFIED');
 await verifyV3(process.argv[2]);const v=await readPrivateInput();
 if(v?.mode!=='synthetic'||!v.job||!v.fixture||!Number.isSafeInteger(v.holdMs)||v.holdMs<0||v.holdMs>5000)fail('INPUT_REFUSED');
 const f=v.fixture;client=new pg.Client({host:f.host,port:f.port,database:f.database,user:'postgres',application_name:v.job.intent.applicationName,connectionTimeoutMillis:3000});
 client.on('error',()=>{});await client.connect();
 const identity=await identifyCaptureBackend(client,{mode:'synthetic',database:f.database,applicationName:v.job.intent.applicationName});
 await recordBackend(v.job,identity); // fsynced before the first admission/WORK lock.
 if(v.holdMs){
  await client.query('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');await client.query("SET LOCAL statement_timeout='6s'");
  await client.query('SELECT pg_advisory_xact_lock(7346371,1)');
  if(process.send)process.send({status:'fixture_lock_held'});
  await client.query('SELECT pg_sleep($1)',[v.holdMs/1000]);await client.query('ROLLBACK');
  result={status:'fixture_hold_finished'};
 }else{
  const captured=await captureArchivePreimage({mode:'synthetic',client,database:f.database,backendPid:identity.pid,executed:f.executed,timeoutMs:30000});
  result={status:'preimage_captured_session_unreconciled',capture:captured};
 }
}catch(e){result={status:'worker_unconfirmed',code:['MANAGED_CAPTURE_UNQUALIFIED','INPUT_REFUSED','SOURCE_MANIFEST_REFUSED','BACKEND_IDENTITY_REFUSED'].includes(e?.captureCode)?e.captureCode:'WORKER_UNKNOWN'};process.exitCode=1;}
finally{try{await client?.end();}catch{try{client?.connection?.stream?.destroy();}catch{}}}
try{await new Promise((resolve,reject)=>process.stdout.write(JSON.stringify(result)+'\n',e=>e?reject(e):resolve()));}catch{process.exitCode=1;}
