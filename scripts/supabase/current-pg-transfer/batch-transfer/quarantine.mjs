// Encrypted quarantine and receipt only; never imports application rows.
import {createCipheriv,createDecipheriv,createHash,createHmac,randomBytes,timingSafeEqual} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {types as utilTypes} from 'node:util';
import pg from '../../node_modules/pg/lib/index.js';

const {Client} = pg;
const FORMAT = 'collect.pg-quarantine-plan.v1', PROJECT = 'rrlduytparvsjfmegalh';
const MAGIC = Buffer.from('CQ01','ascii');
const HASH = /^[a-f0-9]{64}$/, NAME = /^[a-z_][a-z0-9_]{0,62}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SCHEMAS = new Set(['app','private','collect_sms','auth']);
// Fixture naming is an accidental-use guard, not attestation of a local host.
export function isSyntheticQuarantineSocket(host,platform=process.platform){
 if(typeof host!=='string')return false;
 return platform==='darwin'?/^\/private\/tmp\/collect-quarantine-[A-Za-z0-9]+\/s$/.test(host):
  platform==='linux'?/^\/tmp\/collect-quarantine-[A-Za-z0-9]+\/s$/.test(host):false;
}
// Bound to candidate-schema.sql's exact PG17 column and constraint descriptors.
// This is populated from the independently exercised synthetic schema, never
// from the target database being admitted.
const CATALOGUE_SHA256 = '411f09487c43c0cd4b033e10f8d8e6c574b648f0d068f029c6629bdb38e52b56';
const active = new WeakSet();
export class QuarantineError extends Error { constructor(code) { super(code); this.name='QuarantineError'; this.code=code; } }
// An exported error class is not proof of origin: callers can construct or
// subclass it. Only immutable instances created here carry internal provenance.
const trustedErrors=new WeakSet();
const ERROR_CODES=new Set(['invalid_envelope','invalid_plan','unexpected_result_format','database_error','source_commitment_mismatch',
 'envelope_authentication_failed','invalid_client','connection_mismatch','deadline_exceeded','database_timeout','connection_not_idle',
 'parameter_logging_uncontrolled','identity_mismatch','fence_not_quiescent','quarantine_catalogue_mismatch','batch_collision',
 'begin_unconfirmed','insert_unconfirmed','postimage_mismatch','commit_unconfirmed','rollback_unconfirmed','quarantine_failed']);
function internalError(code){
 const e=new QuarantineError(ERROR_CODES.has(code)?code:'quarantine_failed');Object.freeze(e);trustedErrors.add(e);return e;
}
const isInternal=e=>trustedErrors.has(e);
const fail=code=>{throw internalError(code);};
function pgErrorCode(e){
 try{if(!e||typeof e!=='object'||utilTypes.isProxy(e))return null;const d=Object.getOwnPropertyDescriptor(e,'code');return d&&Object.hasOwn(d,'value')&&typeof d.value==='string'?d.value:null;}
 catch{return null;}
}
// Inspect intrinsic typed-array slots, not caller-overridable Buffer methods or
// properties. Shared/resizable backing can change concurrently with a copy.
const typedArrayPrototype=Object.getPrototypeOf(Uint8Array.prototype);
const getBuffer=Object.getOwnPropertyDescriptor(typedArrayPrototype,'buffer').get;
const getByteOffset=Object.getOwnPropertyDescriptor(typedArrayPrototype,'byteOffset').get;
const getByteLength=Object.getOwnPropertyDescriptor(typedArrayPrototype,'byteLength').get;
const getResizable=Object.getOwnPropertyDescriptor(ArrayBuffer.prototype,'resizable')?.get;
function ownedBytes(value,min,max){
 if(!Buffer.isBuffer(value)||utilTypes.isProxy(value))fail('invalid_envelope');
 try{
  const backing=getBuffer.call(value),offset=getByteOffset.call(value),length=getByteLength.call(value);
  if(!utilTypes.isArrayBuffer(backing)||utilTypes.isSharedArrayBuffer(backing)||getResizable?.call(backing)===true||
     !Number.isSafeInteger(length)||length<min||length>max)fail('invalid_envelope');
  const owned=Buffer.allocUnsafe(length);
  try{Uint8Array.prototype.set.call(owned,new Uint8Array(backing,offset,length));return owned;}
  catch(e){owned.fill(0);throw e;}
 }catch{fail('invalid_envelope');}
}
function inputValues(input){
 if(!input||utilTypes.isProxy(input)||Object.getPrototypeOf(input)!==Object.prototype)fail('invalid_envelope');
 const descriptors=Object.getOwnPropertyDescriptors(input),names=['plan','expectedPlanSha256','envelope','key'];
 if(Object.keys(descriptors).sort().join('\0')!==names.sort().join('\0')||
    names.some(name=>!Object.hasOwn(descriptors[name],'value')))fail('invalid_envelope');
 return Object.fromEntries(names.map(name=>[name,descriptors[name].value]));
}
const QUERY_TYPES={getTypeParser(oid,format){
 if(format!=='text')fail('unexpected_result_format');
 if(oid===16)return v=>{if(v==='t')return true;if(v==='f')return false;fail('database_error');};
 if(oid===23)return v=>{if(!/^-?\d{1,10}$/.test(v))fail('database_error');return Number(v);};
 return v=>v;
}};
const exact = (o,keys) => o && typeof o==='object' && !Array.isArray(o) && Object.keys(o).sort().join('\0')===[...keys].sort().join('\0');
const canonical = value => {
 const chunks=[];let remaining=65536,nodes=0;
 const emit=s=>{remaining-=Buffer.byteLength(s,'utf8');if(remaining<0)fail('invalid_plan');chunks.push(s);};
 const walk=(x,depth)=>{
  if(depth>12||++nodes>20000)fail('invalid_plan');
  if(x===null||typeof x==='boolean'||(typeof x==='number'&&Number.isSafeInteger(x))){emit(JSON.stringify(x));return;}
  if(typeof x==='string'){if(x.length>512)fail('invalid_plan');emit(JSON.stringify(x));return;}
  if(Array.isArray(x)){
   if(x.length>128)fail('invalid_plan');emit('[');for(let i=0;i<x.length;i++){if(i)emit(',');walk(x[i],depth+1);}emit(']');return;
  }
  if(x&&Object.getPrototypeOf(x)===Object.prototype){
   const keys=Object.keys(x).sort();if(keys.length>32)fail('invalid_plan');emit('{');
   for(let i=0;i<keys.length;i++){const k=keys[i];if(k.length>128)fail('invalid_plan');if(i)emit(',');emit(JSON.stringify(k));emit(':');walk(x[k],depth+1);}emit('}');return;
  }
  fail('invalid_plan');
 };
 try{walk(value,0);return chunks.join('');}catch{fail('invalid_plan');}
};
const sha = x => createHash('sha256').update(x).digest('hex');
export function planDigest(plan){
 try{return sha(Buffer.from(canonical(plan),'utf8'));}
 catch(e){if(isInternal(e))throw e;fail('invalid_plan');}
}
function validate(plan,pin){
 if(!exact(plan,['format','project_ref','operation_id','source_batch_id','source_identity_sha256','source_set_sha256',
   'source_snapshot_hmac','target','relations']) || plan.format!==FORMAT || plan.project_ref!==PROJECT ||
   !UUID.test(plan.operation_id??'') || !UUID.test(plan.source_batch_id??'') ||
   ![plan.source_identity_sha256,plan.source_set_sha256,plan.source_snapshot_hmac,pin].every(x=>HASH.test(x??'')) ||
   planDigest(plan)!==pin || Buffer.byteLength(canonical(plan),'utf8')>65536 || !Array.isArray(plan.relations) ||
   plan.relations.length<1 || plan.relations.length>32) fail('invalid_plan');
 const t=plan.target;
 if(!exact(t,['kind','host','port','database','baseline_manifest_sha256','source_sha256','epoch','fence_operation_id','profile_sha256']) ||
   !['managed','synthetic'].includes(t.kind) || typeof t.host!=='string' || !Number.isSafeInteger(t.port) || t.port<1 || t.port>65535 ||
   typeof t.database!=='string' || !NAME.test(t.database) ||
   ![t.baseline_manifest_sha256,t.source_sha256,t.profile_sha256].every(x=>HASH.test(x??'')) ||
   typeof t.epoch!=='string' || !/^[1-9][0-9]{0,15}$/.test(t.epoch) || !UUID.test(t.fence_operation_id??'')) fail('invalid_plan');
 const seen = new Set();
 for(const r of plan.relations){
  if(!exact(r,['source_schema','source_table','target_schema','target_table','columns','key','mapping_sha256']) ||
    !SCHEMAS.has(r.source_schema) || !SCHEMAS.has(r.target_schema) || !NAME.test(r.source_table??'') || !NAME.test(r.target_table??'') ||
    !HASH.test(r.mapping_sha256??'') || !Array.isArray(r.columns) || r.columns.length<1 || r.columns.length>64 ||
    !Array.isArray(r.key) || r.key.length<1 || r.key.length>8) fail('invalid_plan');
  const n=r.source_schema+'.'+r.source_table+'>'+r.target_schema+'.'+r.target_table;if(seen.has(n))fail('invalid_plan');seen.add(n);
  const sources=new Set(),targets=new Set();
  for(const c of r.columns){
   if(!exact(c,['source','target','type']) || !NAME.test(c.source??'') || !NAME.test(c.target??'') ||
     typeof c.type!=='string' || c.type.length<1 || Buffer.byteLength(c.type,'utf8')>128 || /[\u0000-\u001f\u007f]/.test(c.type) ||
     sources.has(c.source) || targets.has(c.target))fail('invalid_plan');sources.add(c.source);targets.add(c.target);
  }
  const keys=new Set();for(const k of r.key){
   if(!exact(k,['source','target']) || !sources.has(k.source) || !targets.has(k.target) ||
     !r.columns.some(c=>c.source===k.source && c.target===k.target) || keys.has(k.source))fail('invalid_plan');keys.add(k.source);
  }
 }
}

function mac(key,plaintext){
 if(!Buffer.isBuffer(key)||key.length!==32||!Buffer.isBuffer(plaintext)||plaintext.length<1||plaintext.length>4194304)fail('invalid_envelope');
 const derived=createHmac('sha256',key).update('collect.pg-quarantine.source-hmac-key.v1','ascii').digest();
 try{return createHmac('sha256',derived).update(plaintext).digest('hex');}finally{derived.fill(0);}
}
export function sourceSnapshotHmac(key,plaintext){
 let ownedKey,ownedPlaintext;
 try{ownedKey=ownedBytes(key,32,32);ownedPlaintext=ownedBytes(plaintext,1,4194304);return mac(ownedKey,ownedPlaintext);}
 catch(e){if(isInternal(e))throw e;fail('invalid_envelope');}
 finally{ownedKey?.fill(0);ownedPlaintext?.fill(0);}
}
function equalHex(a,b){return HASH.test(a??'')&&HASH.test(b??'')&&timingSafeEqual(Buffer.from(a,'hex'),Buffer.from(b,'hex'));}
export function sealBatch(plan,pin,plaintext,key){
 let ownedKey,ownedPlaintext;
 try{
  ownedPlaintext=ownedBytes(plaintext,1,4194304);ownedKey=ownedBytes(key,32,32);
  plan=JSON.parse(canonical(plan));validate(plan,pin);
  if(!equalHex(mac(ownedKey,ownedPlaintext),plan.source_snapshot_hmac))fail('source_commitment_mismatch');
  const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',ownedKey,iv,{authTagLength:16});
  cipher.setAAD(Buffer.from(FORMAT+'|'+pin,'ascii'));
  const body=Buffer.concat([cipher.update(ownedPlaintext),cipher.final()]);
  return Buffer.concat([MAGIC,iv,cipher.getAuthTag(),body]);
 }catch(e){if(isInternal(e))throw e;fail('invalid_plan');}
 finally{ownedKey?.fill(0);ownedPlaintext?.fill(0);}
}
function authenticate(plan,pin,envelope,key){
 if(!Buffer.isBuffer(envelope)||envelope.length<33||envelope.length>4194336||!envelope.subarray(0,4).equals(MAGIC)||
   !Buffer.isBuffer(key)||key.length!==32)fail('invalid_envelope');
 let update,final,raw;
 try{
  const decipher=createDecipheriv('aes-256-gcm',key,envelope.subarray(4,16),{authTagLength:16});
  decipher.setAAD(Buffer.from(FORMAT+'|'+pin,'ascii'));decipher.setAuthTag(envelope.subarray(16,32));
  update=decipher.update(envelope.subarray(32));final=decipher.final();raw=Buffer.concat([update,final]);
  if(!equalHex(mac(key,raw),plan.source_snapshot_hmac))fail('source_commitment_mismatch');
 }catch(e){if(isInternal(e))throw e;fail('envelope_authentication_failed');}
 finally{update?.fill(0);final?.fill(0);raw?.fill(0);}
}
function clientAllowed(client,plan){
 // A Proxy can run getPrototypeOf during instanceof and throw a captured
 // internal error. Reject it before admission and normalize the whole check.
 let eligible;
 try{eligible=!utilTypes.isProxy(client)&&client instanceof Client&&!active.has(client);}
 catch{fail('invalid_client');}
 if(!eligible)fail('invalid_client');
 let cp,s,available,host,port,database,ssl,user,encrypted,authorized,servername;
 // Client properties are caller-owned; never trust an exception emitted by a
 // getter, even if it rethrows an error obtained from a previous API call.
 try{
  available=!!client.connection?.once&&!!client.connection?.removeListener&&!!client.connection?.stream?.destroy;
  cp=client.connectionParameters;s=client.connection.stream;
  host=cp.host;port=Number(cp.port);database=cp.database;ssl=cp.ssl;user=cp.user;
  encrypted=s.encrypted;authorized=s.authorized;servername=s.servername;
 }catch{fail('invalid_client');}
 if(!available)fail('invalid_client');
 const t=plan.target;
 if(host!==t.host||port!==t.port||database!==t.database)fail('connection_mismatch');
 if(t.kind==='synthetic'){
  if(!/^collect_fixture_[a-z0-9_]+$/.test(t.database)||!isSyntheticQuarantineSocket(t.host))fail('connection_mismatch');
 }else{
  const direct=t.host===`db.${PROJECT}.supabase.co`&&t.port===5432;
  const pooler=/^aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com$/.test(t.host)&&t.port===5432&&typeof user==='string'&&user.endsWith('.'+PROJECT);
  let tlsAllowed;try{tlsAllowed=!!ssl&&ssl.rejectUnauthorized!==false&&ssl.ca===undefined&&ssl.checkServerIdentity===undefined;}catch{fail('invalid_client');}
  if(t.database!=='postgres'||(!direct&&!pooler)||!tlsAllowed||encrypted!==true||authorized!==true||servername!==t.host)fail('connection_mismatch');
 }
}
function destroy(client){try{client.connection.stream.destroy();}catch{}}
async function query(client,sql,values,ms){
 if(ms<=0)fail('deadline_exceeded');let timer;
 // A caller controls the Client object. Sanitize every error crossing its query
 // boundary, including a previously captured internal error rethrown by it.
 const sent=Promise.resolve().then(()=>client.query({text:sql,values,types:QUERY_TYPES})).catch(e=>{
  const code=pgErrorCode(e);throw internalError(code==='57014'||code==='55P03'?'database_timeout':'database_error');
 });
 try{return await Promise.race([sent,new Promise((_,reject)=>{timer=setTimeout(()=>{destroy(client);reject(internalError('deadline_exceeded'));},ms);})]);}
 catch(e){if(isInternal(e))throw e;fail('database_error');}
 finally{clearTimeout(timer);}
}
async function idle(client,deadline){
 let listener,timer;
 try{
  const status=new Promise((resolve,reject)=>{listener=x=>resolve(x?.status);try{client.connection.once('readyForQuery',listener);}catch{reject(internalError('invalid_client'));return;}timer=setTimeout(()=>reject(new Error()),Math.max(1,Math.min(5000,deadline-performance.now())));});
  const [r,s]=await Promise.all([query(client,'SELECT pg_catalog.pg_backend_pid() AS pid',[],Math.min(5000,deadline-performance.now())),status]);
  if(s!=='I'||!Number.isSafeInteger(r.rows?.[0]?.pid)||r.rows[0].pid<1)fail('connection_not_idle');return r.rows[0].pid;
 }catch(e){if(isInternal(e))throw e;fail('connection_not_idle');}
 finally{clearTimeout(timer);if(listener){try{client.connection.removeListener('readyForQuery',listener);}catch{}}}
}
const catalogueSql=`SELECT pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.jsonb_build_object(
 'columns',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_array(a.attname,pg_catalog.format_type(a.atttypid,a.atttypmod),a.attnotnull,
  a.attidentity::text,a.attgenerated::text,pg_catalog.pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum)
  FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_array(x.conname,x.contype::text,pg_catalog.pg_get_constraintdef(x.oid),x.condeferrable,x.condeferred,x.convalidated) ORDER BY x.conname)
  FROM pg_catalog.pg_constraint x WHERE x.conrelid=c.oid))::text,'UTF8')),'hex') AS descriptor,
 pg_catalog.pg_get_userbyid(c.relowner)='postgres' AS owner_ok,c.relkind='r' AS ordinary,
 c.relpersistence='p' AS logged,NOT c.relispartition AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhrelid=c.oid OR i.inhparent=c.oid) AS unpartitioned,
 NOT EXISTS(SELECT 1 FROM pg_catalog.pg_rewrite w WHERE w.ev_class=c.oid) AS no_rules,
 ((SELECT pg_catalog.count(*) FROM pg_catalog.pg_index i WHERE i.indrelid=c.oid)=2 AND
  NOT EXISTS(SELECT 1 FROM pg_catalog.pg_index i WHERE i.indrelid=c.oid AND
   NOT(i.indisvalid AND i.indisready AND i.indislive AND i.indisunique AND i.indimmediate AND i.indpred IS NULL AND i.indexprs IS NULL))) AS indexes_ok,
 c.relrowsecurity AND NOT c.relforcerowsecurity AS rls_ok,
 NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) a WHERE a.grantee<>c.relowner) AS table_acl_ok,
 (SELECT pg_catalog.count(*) FROM pg_catalog.pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal)=1 AS trigger_count_ok,
 EXISTS(SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal AND t.tgname='collect_pg_quarantine_immutable'
  AND t.tgenabled='A' AND t.tgtype=58 AND t.tgfoid='private._collect_pg_quarantine_immutable()'::regprocedure AND t.tgqual IS NULL AND t.tgnargs=0) AS trigger_ok,
 EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid=p.prolang
  WHERE p.oid='private._collect_pg_quarantine_immutable()'::regprocedure AND pg_catalog.pg_get_userbyid(p.proowner)='postgres'
  AND l.lanname='plpgsql' AND NOT p.prosecdef AND p.provolatile='v' AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
  AND pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc,'UTF8')),'hex')=$1
  AND NOT EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a WHERE a.grantee<>p.proowner)) AS function_ok
 FROM pg_catalog.pg_class c WHERE c.oid='private.collect_pg_transfer_quarantine'::regclass`;
const TRIGGER_SHA256=sha(Buffer.from("BEGIN\n  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='quarantine_immutable';\n END",'utf8'));
async function pinParameterLogging(client,run){
 // The latter GUC is normally SUSET: an explicit SET privilege or superuser
 // authority is required. Checking a default alone is insufficient because
 // an administrator could reload that default while this transaction runs.
 try{
  await run(client,"SET LOCAL log_parameter_max_length_on_error='0'");
  await run(client,"SET LOCAL log_parameter_max_length='0'");
  const r=await run(client,`SELECT pg_catalog.current_setting('log_parameter_max_length') AS normal,
   pg_catalog.current_setting('log_parameter_max_length_on_error') AS on_error`);
  if(r.rows?.length!==1||r.rows[0].normal!=='0'||r.rows[0].on_error!=='0')fail('parameter_logging_uncontrolled');
 }catch(e){if(isInternal(e)&&['deadline_exceeded','database_timeout'].includes(e.code))throw e;fail('parameter_logging_uncontrolled');}
}
async function guard(client,plan,pid,run,readOnly){
 await run(client,'SET LOCAL search_path=pg_catalog,pg_temp');await run(client,"SET LOCAL lock_timeout='5s'");
 await run(client,"SET LOCAL statement_timeout='20s'");await run(client,"SET LOCAL synchronous_commit='on'");
 await run(client,'SELECT pg_catalog.pg_advisory_xact_lock(7346371,1)');
 await run(client,'SELECT pg_catalog.pg_advisory_xact_lock(7346371,2)');
 const t=plan.target;
 const c=await run(client,`SELECT pg_catalog.current_database() AS database,session_user AS session_user,current_user AS current_user,
  pg_catalog.pg_backend_pid() AS pid,pg_catalog.current_setting('server_version_num') AS version,
  pg_catalog.current_setting('synchronous_commit') AS synchronous_commit,pg_catalog.current_setting('fsync') AS fsync,
  pg_catalog.current_setting('full_page_writes') AS full_page_writes,project_ref,baseline_manifest_sha256,
  source_sha256,epoch::text,mode,operation_id::text FROM private.collect_fence_control WHERE singleton IS TRUE FOR UPDATE`);
 const x=c.rows?.[0];if(c.rows?.length!==1||x.database!==t.database||x.session_user!=='postgres'||x.current_user!=='postgres'||x.pid!==pid||
  !/^17\d{4}$/.test(x.version)||x.synchronous_commit!=='on'||x.fsync!=='on'||x.full_page_writes!=='on'||
  x.project_ref!==PROJECT||x.baseline_manifest_sha256!==t.baseline_manifest_sha256||
  x.source_sha256!==t.source_sha256||x.epoch!==t.epoch||x.mode!=='fenced'||x.operation_id!==t.fence_operation_id)fail('identity_mismatch');
 const profile=await run(client,`SELECT profile_sha256,pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(profile_raw,'UTF8')),'hex') AS calculated
  FROM private.collect_deployment_identity WHERE singleton IS TRUE AND pg_catalog.octet_length(profile_raw)<=8192`);
 if(profile.rows?.length!==1||profile.rows[0].profile_sha256!==t.profile_sha256||profile.rows[0].calculated!==t.profile_sha256)fail('identity_mismatch');
 const uncertain=await run(client,"SELECT EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE state IS DISTINCT FROM 'settled' OR uncertain_dispatches IS DISTINCT FROM 0) AS found");
 if(uncertain.rows?.length!==1||uncertain.rows[0].found!==false)fail('fence_not_quiescent');
 // Readback also locks the table against DDL. The common exclusive advisory
 // locks serialize this protocol; other owners must be administratively held.
 await run(client,`LOCK TABLE private.collect_pg_transfer_quarantine IN ${readOnly?'ACCESS SHARE':'SHARE ROW EXCLUSIVE'} MODE`);
 const cat=await run(client,catalogueSql,[TRIGGER_SHA256]),d=cat.rows?.[0];
 if(cat.rows?.length!==1||d.descriptor!==CATALOGUE_SHA256||!['owner_ok','ordinary','logged','unpartitioned','no_rules','indexes_ok','rls_ok','table_acl_ok','trigger_count_ok','trigger_ok','function_ok'].every(k=>d[k]===true))fail('quarantine_catalogue_mismatch');
}
async function prior(client,plan,pin,envelopeSha,run){
 const r=await run(client,`SELECT operation_id::text,source_identity_sha256,source_batch_id::text,plan_sha256,envelope_sha256,
  pg_catalog.encode(pg_catalog.sha256(envelope),'hex') AS actual_sha256
  FROM private.collect_pg_transfer_quarantine WHERE operation_id=$1::uuid OR (source_identity_sha256=$2 AND source_batch_id=$3::uuid)`,
  [plan.operation_id,plan.source_identity_sha256,plan.source_batch_id]);
 if(!r.rows.length)return false;
 if(r.rows.length!==1)fail('batch_collision');const x=r.rows[0];
 if(x.operation_id!==plan.operation_id||x.source_identity_sha256!==plan.source_identity_sha256||x.source_batch_id!==plan.source_batch_id||
  x.plan_sha256!==pin||x.envelope_sha256!==envelopeSha||x.actual_sha256!==envelopeSha)fail('batch_collision');
 return true;
}
async function execute(client,input,mode){
 let envelope,key,admitted=false;
 try{
  const values=inputValues(input),pin=values.expectedPlanSha256;
  // Authenticate, hash and send the same owned snapshots. No caller getters,
  // mutable shared backing or later asynchronous changes can alter them.
  envelope=ownedBytes(values.envelope,33,4194336);key=ownedBytes(values.key,32,32);
  const plan=JSON.parse(canonical(values.plan));validate(plan,pin);authenticate(plan,pin,envelope,key);
  key.fill(0);key=undefined;
  clientAllowed(client,plan);const envelopeSha=sha(envelope);active.add(client);admitted=true;
  const deadline=performance.now()+30000,run=(sql,values=[])=>query(client,sql,values,Math.min(21000,deadline-performance.now()));
  let begun=false,committing=false;
  try{
   const pid=await idle(client,deadline),begin=await run('BEGIN ISOLATION LEVEL READ COMMITTED');if(begin.command!=='BEGIN')fail('begin_unconfirmed');begun=true;
   const scopedRun=(_client,sql,values=[])=>run(sql,values);
   await pinParameterLogging(client,scopedRun);
   await guard(client,plan,pid,scopedRun,mode==='readback');const exists=await prior(client,plan,pin,envelopeSha,scopedRun);
   if(mode==='stage'&&!exists){
    const inserted=await run(`INSERT INTO private.collect_pg_transfer_quarantine(operation_id,source_identity_sha256,source_batch_id,plan_sha256,envelope_sha256,envelope)
     VALUES($1::uuid,$2,$3::uuid,$4,$5,$6) RETURNING 1 AS inserted`,[plan.operation_id,plan.source_identity_sha256,plan.source_batch_id,pin,envelopeSha,envelope]);
    if(inserted.rows?.length!==1||inserted.rows[0].inserted!==1)fail('insert_unconfirmed');
    if(!await prior(client,plan,pin,envelopeSha,scopedRun))fail('postimage_mismatch');
   }
   committing=true;const end=await run('COMMIT');if(end.command!=='COMMIT')fail('commit_unconfirmed');
   return {status:mode==='readback'?(exists?'staged_receipt_verified':'receipt_absent_at_readback'):(exists?'exact_replay':'staged'),
    business_rows_imported:false,identities_resolved:false,cutover_authorized:false};
  }catch(e){
   if(committing)fail('commit_unconfirmed');
   if(begun){try{const r=await query(client,'ROLLBACK',[],2000);if(r.command!=='ROLLBACK')fail('rollback_unconfirmed');}catch{fail('rollback_unconfirmed');}}
   if(isInternal(e))throw e;fail('quarantine_failed');
  }
 }catch(e){if(isInternal(e))throw e;fail('quarantine_failed');}
 finally{
  key?.fill(0);envelope?.fill(0);
  if(admitted){destroy(client);active.delete(client);try{void client.end().catch(()=>{});}catch{}}
 }
}
export const stageEncryptedBatch = (client,input)=>execute(client,input,'stage');
export const reconcileEncryptedBatch = (client,input)=>execute(client,input,'readback');
