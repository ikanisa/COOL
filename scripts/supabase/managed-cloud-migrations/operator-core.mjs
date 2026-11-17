// Bound operator for the two reviewed, exact-version migrations only.
// A private, durable, one-use journal is written before any migration SQL.
import {constants} from 'node:fs';
import {lstat, mkdir, open, realpath} from 'node:fs/promises';
import {isAbsolute,join,normalize} from 'node:path';
import {randomUUID} from 'node:crypto';
import pg from '../node_modules/pg/lib/index.js';
import {hasPinnedProviderSSL,loadProviderRoot,validateProviderRoot} from './provider-ca.mjs';
import {AtomicMigrationError,pinnedMigrationIdentities,capturePinnedPreimage,
 executePinnedMigration,reconcilePinnedMigration} from '../atomic_cloud_migration.mjs';

export const FORMAT='collect.atomic-cloud-operator.v1';
const PROJECT='rrlduytparvsjfmegalh',HASH=/^[0-9a-f]{64}$/,VERSION=/^[0-9]{14}$/;
const IDENTITIES=new Map(pinnedMigrationIdentities().slice(14).map(x=>[x.version,x.sha256]));
const CODES=new Set(['unsupported_sql','unapproved_migration_identity','source_invalid','source_mismatch',
 'source_unavailable','unverified_database_connection','connection_not_idle','connection_probe_failed',
 'already_recorded_reconcile_first','backend_changed','backend_pin_invalid','begin_unconfirmed',
 'preimage_unconfirmed','target_identity_mismatch','unreviewed_database_role','target_not_fenced',
 'migration_history_mismatch','unreviewed_schema_owner','unreviewed_function_owner','preexisting_target_object',
 'unreviewed_database_roles','postcondition_mismatch','target_preimage_required','target_preimage_mismatch',
 'commit_unconfirmed','rollback_unconfirmed','migration_rolled_back','fresh_connection_required',
 'reconciliation_unconfirmed','client_discard_required','client_already_in_use','query_timeout']);
const UNCERTAIN=new Set(['begin_unconfirmed','preimage_unconfirmed','commit_unconfirmed','rollback_unconfirmed',
 'backend_changed','reconciliation_unconfirmed','query_timeout','operator_unconfirmed']);
const exact=(o,keys)=>o!==null&&typeof o==='object'&&!Array.isArray(o)&&Object.getPrototypeOf(o)===Object.prototype&&
 Object.keys(o).sort().join('\0')===[...keys].sort().join('\0');
const deny=code=>{throw new OperatorError(code);};
export class OperatorError extends Error {constructor(code){super(code);this.code=code;}}
function journalOutcomeUnconfirmed(version,backendPid){
 const error=new OperatorError('journal_outcome_unconfirmed');
 error.version=version;error.backendPid=backendPid;throw error;
}
const safeError=e=>e instanceof AtomicMigrationError&&CODES.has(e.code)?e.code:'operator_unconfirmed';

export function validateRequest(r){
 if(!exact(r,['format','action','connection','migration'])||r.format!==FORMAT||
  !['capture','apply','reconcile'].includes(r.action)||!exact(r.connection,['host','user','password'])||
  !exact(r.migration,['version','sourceSha256','preimageSha256']))deny('invalid_request');
 const {host,user,password}=r.connection,{version,sourceSha256,preimageSha256}=r.migration;
 const direct=host===`db.${PROJECT}.supabase.co`&&user==='postgres';
 const pooler=host==='aws-0-eu-north-1.pooler.supabase.com'&&user===`postgres.${PROJECT}`;
 if((!direct&&!pooler)||typeof password!=='string'||!password||Buffer.byteLength(password,'utf8')>1024||password.includes('\0')||
  typeof version!=='string'||!VERSION.test(version)||IDENTITIES.get(version)!==sourceSha256||
  (r.action==='capture'?preimageSha256!==null:!HASH.test(preimageSha256??'')))deny('invalid_request');
 return {host,user,password,version,sourceSha256,preimageSha256};
}
export function assertCleanEnvironment(env){
 // pg applies PGOPTIONS/PG* defaults when explicit values are empty. Node/TLS
 // preload, custom trust and key logging settings are also refused. This check
 // does not attest the Node binary, OS, system trust store or same-user processes.
 const forbidden=/^(?:PG[A-Z0-9_]*|NODE_OPTIONS|NODE_PATH|NODE_EXTRA_CA_CERTS|NODE_TLS_REJECT_UNAUTHORIZED|NODE_USE_SYSTEM_CA|SSL_[A-Z0-9_]*|OPENSSL_[A-Z0-9_]*|LD_[A-Z0-9_]*|DYLD_[A-Z0-9_]*)$/i;
 if(Object.keys(env).some(key=>forbidden.test(key)))deny('unclean_environment');
}
export function parseCanonicalInput(raw){
 if(typeof raw!=='string'||Buffer.byteLength(raw,'utf8')>16384)deny('invalid_request');
 let value;try{value=JSON.parse(raw);}catch{deny('invalid_request');}
 // One compact JSON serialization rejects duplicate keys, noncanonical aliases
 // and trailing content; credential producers must JSON.stringify the object.
 if(raw!==JSON.stringify(value))deny('invalid_request');
 validateRequest(value);return value;
}

async function directory(path){
 if(typeof path!=='string'||!isAbsolute(path)||normalize(path)!==path||path==='/'||path.includes('\0'))deny('journal_unavailable');
 let s,resolved;
 try{s=await lstat(path);resolved=await realpath(path);}catch{deny('journal_unavailable');}
 if(!s.isDirectory()||s.isSymbolicLink()||resolved!==path||typeof process.getuid!=='function'||
  s.uid!==process.getuid()||(s.mode&0o077)!==0||(s.mode&0o700)!==0o700)deny('journal_unavailable');
 return path;
}
async function syncDirectory(path){
 let h;try{h=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);await h.sync();}
 catch{deny('journal_unavailable');}finally{await h?.close().catch(()=>{});}
}
async function writeRecord(dir,name,value){
 const text=JSON.stringify(value);if(Buffer.byteLength(text)>8192)deny('journal_unavailable');
 let h;try{
  h=await open(join(dir,name),constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,0o600);
  await h.writeFile(text,'utf8');await h.sync();
 }catch{deny('journal_unavailable');}finally{await h?.close().catch(()=>{});}
 await syncDirectory(dir);
}
async function readRecord(dir,name){
 let h;try{
  h=await open(join(dir,name),constants.O_RDONLY|constants.O_NOFOLLOW);const before=await h.stat();
  if(!before.isFile()||before.uid!==process.getuid()||(before.mode&0o077)!==0||before.size<2||before.size>8192)deny('journal_unavailable');
  const text=await h.readFile('utf8'),after=await h.stat();
  if(before.dev!==after.dev||before.ino!==after.ino||before.size!==after.size||before.mtimeMs!==after.mtimeMs)deny('journal_unavailable');
  const result=JSON.parse(text);if(JSON.stringify(result)!==text)deny('journal_unavailable');return result;
 }catch{deny('journal_unavailable');}finally{await h?.close().catch(()=>{});}
}
function intentFor(v){return {format:FORMAT,projectRef:PROJECT,version:v.version,sourceSha256:v.sourceSha256,
 preimageSha256:v.preimageSha256,host:v.host,user:v.user,port:5432,database:'postgres'};}
function equalIntent(a,b){return exact(a,Object.keys(b))&&JSON.stringify(a)===JSON.stringify(b);}
function connectionOptions(v,providerRoot){return {host:v.host,port:5432,database:'postgres',user:v.user,password:v.password,
 ssl:{rejectUnauthorized:true,ca:providerRoot},connectionTimeoutMillis:10000,application_name:'collect_atomic_cloud_migration'};}
function defaultClient(options){return new pg.Client(options);}
async function connect(v,makeClient,providerRoot){
 let client;
 try{
  client=makeClient(connectionOptions(v,providerRoot));client.on('error',()=>{});await client.connect();
  const cp=client.connectionParameters,stream=client.connection?.stream;
  if(cp?.host!==v.host||Number(cp?.port)!==5432||cp?.database!=='postgres'||cp?.user!==v.user||
   !hasPinnedProviderSSL(cp.ssl,providerRoot)||
   stream?.encrypted!==true||stream.authorized!==true||stream.servername!==v.host)throw Error('unverified connection');
  return client;
 }catch{try{client?.connection?.stream?.destroy();}catch{}try{void client?.end()?.catch(()=>{});}catch{}deny('connection_unavailable');}
}
function close(client){try{client?.connection?.stream?.destroy();}catch{}try{void client?.end()?.catch(()=>{});}catch{}}
async function boundedQuery(client,sql,values){
 let timer;
 try{return await Promise.race([client.query(sql,values),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('timeout')),10000);})]);}
 catch{close(client);deny('connection_unavailable');}finally{clearTimeout(timer);}
}
async function backendPid(client){
 const r=await boundedQuery(client,'SELECT pg_catalog.pg_backend_pid()::integer AS pid');
 const pid=r.rows?.[0]?.pid;if(r.rows?.length!==1||!Number.isSafeInteger(pid)||pid<1)deny('connection_unavailable');return pid;
}
async function priorBackendGone(client,pid){
 const r=await boundedQuery(client,'SELECT NOT EXISTS (SELECT 1 FROM pg_catalog.pg_stat_activity WHERE pid=$1) AS gone',[pid]);
 if(r.rows?.length!==1||r.rows[0]?.gone!==true)deny('prior_backend_still_present');
}

// Dependency injection is only for local tests. The CLI always uses the pinned
// pg package and the production API defaults below, not caller-provided code.
export async function runRequest(request,{journalRoot,makeClient=defaultClient,api={capturePinnedPreimage,executePinnedMigration,reconcilePinnedMigration},environment=process.env,rootLoader=loadProviderRoot}={}){
 assertCleanEnvironment(environment);const v=validateRequest(request);let client;
 try{
  const root=await directory(journalRoot);
  // Reject absent, changed or expired trust material before creating the
  // one-use apply journal. Carry these validated bytes through the connection.
  let providerRoot;try{providerRoot=validateProviderRoot(rootLoader());}catch{deny('connection_unavailable');}
  const intent=intentFor(v),job=join(root,v.version);
  if(request.action==='capture'){
   client=await connect(v,makeClient,providerRoot);
   const result=await api.capturePinnedPreimage(client,{version:v.version,expectedSha:v.sourceSha256});
   return {format:FORMAT,action:'capture',status:'captured',result};
  }
  if(request.action==='apply'){
   // Only one apply for a version is admitted under this trusted journal root.
   // A crash at any point leaves an existing directory and blocks a new apply.
   try{await mkdir(job,{mode:0o700});}catch{deny('apply_already_attempted');}
   await syncDirectory(root);await writeRecord(job,'intent.json',intent);
   client=await connect(v,makeClient,providerRoot);const pid=await backendPid(client);
   await writeRecord(job,'backend.json',{format:FORMAT,backendPid:pid});
   let outcome;
   try{
    const result=await api.executePinnedMigration(client,{version:v.version,expectedSha:v.sourceSha256,
     expectedPreimageSha:v.preimageSha256,expectedBackendPid:pid});
    if(result?.status!=='committed'||result.projectRef!==PROJECT||result.version!==v.version||result.sourceSha256!==v.sourceSha256)
     outcome={format:FORMAT,state:'unconfirmed',code:'operator_unconfirmed',backendPid:pid};
    else outcome={format:FORMAT,state:'committed',code:null,backendPid:pid};
   }catch(e){const code=safeError(e);outcome={format:FORMAT,state:UNCERTAIN.has(code)?'unconfirmed':'refused',code,backendPid:pid};}
   // If this fsync fails after COMMIT, never print a committed result. The
   // surviving intent/backend pair requires read-only reconciliation.
   try{await writeRecord(job,'outcome.json',outcome);}catch{journalOutcomeUnconfirmed(v.version,pid);}
   return {format:FORMAT,action:'apply',status:outcome.state,code:outcome.code,version:v.version,backendPid:pid};
  }
  const jobPath=await directory(job),existing=await readRecord(jobPath,'intent.json'),record=await readRecord(jobPath,'backend.json');
  if(!equalIntent(existing,intent)||!exact(record,['format','backendPid'])||record.format!==FORMAT||
   !Number.isSafeInteger(record.backendPid)||record.backendPid<1)deny('journal_mismatch');
  const attempt=randomUUID(),name='reconcile-'+attempt;
  await writeRecord(jobPath,name+'.intent.json',{format:FORMAT,attempt,priorBackendPid:record.backendPid});
  client=await connect(v,makeClient,providerRoot);await priorBackendGone(client,record.backendPid);
  let outcome;
  try{
   const result=await api.reconcilePinnedMigration(client,{version:v.version,expectedSha:v.sourceSha256,priorBackendPid:record.backendPid});
   if(result?.projectRef!==PROJECT||result.version!==v.version||result.sourceSha256!==v.sourceSha256||!['recorded','not_recorded'].includes(result.status))
    outcome={format:FORMAT,state:'unconfirmed',code:'operator_unconfirmed'};
   else outcome={format:FORMAT,state:result.status,code:null};
  }catch(e){const code=safeError(e);outcome={format:FORMAT,state:UNCERTAIN.has(code)?'unconfirmed':'refused',code};}
  try{await writeRecord(jobPath,name+'.outcome.json',outcome);}catch{journalOutcomeUnconfirmed(v.version,record.backendPid);}
  return {format:FORMAT,action:'reconcile',status:outcome.state,code:outcome.code,version:v.version,attempt};
 }finally{close(client);request.connection.password='';v.password='';}
}
