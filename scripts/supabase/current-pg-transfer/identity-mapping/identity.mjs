// Explicit, transaction-bound verification of one owner-approved principal
// mapping. It reads no tokens, makes no business writes and preserves both
// existing Auth links. Real transfer callers must independently qualify every
// historical reference and re-check the binding in their own write transaction.
import {createHash,createHmac,timingSafeEqual} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {performance} from 'node:perf_hooks';
import {types as utilTypes} from 'node:util';
import pg from '../../node_modules/pg/lib/index.js';
import {isSyntheticReconciliationSocket} from '../reconcile.mjs';

const {Client}=pg, PROJECT='rrlduytparvsjfmegalh';
const FORMAT='collect.current-pg-identity-mapping.v1';
const HEX=/^[a-f0-9]{64}$/, UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[0-9a-f]{4}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const ROLE=/^[a-z_][a-z0-9_]{0,62}$/, TEXT=/^[^\u0000-\u001f\u007f\ud800-\udfff]{1,128}$/u;
const active=new WeakSet(), caps=new WeakMap(), internal=new WeakSet();
const TYPE_PARSER={getTypeParser(_oid,format){if(format!=='text')fail('invalid_result');return value=>value;}};
export class IdentityMappingError extends Error {constructor(code){super(code);this.name='IdentityMappingError';this.code=code;}}
function fail(code){const e=new IdentityMappingError(code);Object.freeze(e);internal.add(e);throw e;}
function trusted(e){return !!e&&typeof e==='object'&&!utilTypes.isProxy(e)&&internal.has(e);}
function ownBuffer(value){
 if(!Buffer.isBuffer(value)||utilTypes.isProxy(value))fail('invalid_key');
 const typed=Object.getPrototypeOf(Uint8Array.prototype);
 const get=name=>Object.getOwnPropertyDescriptor(typed,name).get.call(value);
 const buffer=get('buffer'),offset=get('byteOffset'),length=get('byteLength');
 if(utilTypes.isSharedArrayBuffer(buffer)||Object.getOwnPropertyDescriptor(ArrayBuffer.prototype,'resizable')?.get.call(buffer)||length!==32)fail('invalid_key');
 const copy=Buffer.alloc(32);Uint8Array.prototype.set.call(copy,new Uint8Array(buffer,offset,length));return copy;
}
function clone(value,depth=0){
 if(depth>12)fail('invalid_plan');
 if(value===null||typeof value==='string'||typeof value==='boolean')return value;
 if(typeof value==='number'&&Number.isSafeInteger(value))return value;
 if(!value||typeof value!=='object'||utilTypes.isProxy(value))fail('invalid_plan');
 if(Array.isArray(value))fail('invalid_plan');
 if(Object.getPrototypeOf(value)!==Object.prototype||Object.getOwnPropertySymbols(value).length)fail('invalid_plan');
 const d=Object.getOwnPropertyDescriptors(value),out={};
 for(const [k,v] of Object.entries(d)){
  if(!v.enumerable||!Object.hasOwn(v,'value')||k==='__proto__')fail('invalid_plan');
  Object.defineProperty(out,k,{value:clone(v.value,depth+1),enumerable:true,writable:true,configurable:true});
 }
 return out;
}
function canonical(v){
 if(v===null||typeof v==='string'||typeof v==='boolean'||typeof v==='number')return JSON.stringify(v);
 if(Array.isArray(v))return '['+v.map(canonical).join(',')+']';
 return '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}';
}
const exact=(o,keys)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).sort().join('\0')===[...keys].sort().join('\0');
const integer=(n,min,max)=>Number.isSafeInteger(n)&&n>=min&&n<=max;
export function identityPlanDigest(value){try{return createHash('sha256').update(canonical(clone(value)),'utf8').digest('hex');}catch(e){if(trusted(e))throw e;fail('invalid_plan');}}
function digestRecord(key,record){return createHmac('sha256',key).update('collect.identity-record.v1\0','utf8').update(canonical(record),'utf8').digest('hex');}
function normalizedEmail(value){
 if(typeof value!=='string')fail('identity_unavailable');
 const out=value.replace(/^ +| +$/g,'').replace(/[A-Z]/g,c=>c.toLowerCase());
 if(out.length<3||out.length>254||! /^[\x21-\x7e]+$/.test(out)||! /^[^@]+@[^@]+$/.test(out))fail('identity_unavailable');
 return out;
}
function validIdentity(e,source){
 if(!exact(e,['transport','database','session_user','current_user','project_ref','baseline_manifest_sha256','source_sha256','epoch','mode','operation_id','profile_sha256'])||
  !exact(e.transport,['kind','host','port'])||typeof e.transport.host!=='string'||!integer(e.transport.port,1,65535)||
  typeof e.database!=='string'||!ROLE.test(e.database)||!ROLE.test(e.session_user??'')||!ROLE.test(e.current_user??'')||
  e.project_ref!==PROJECT||!HEX.test(e.baseline_manifest_sha256??'')||!HEX.test(e.source_sha256??'')||
  !/^[1-9][0-9]{0,15}$/.test(e.epoch??'')||e.mode!=='fenced'||!UUID.test(e.operation_id??'')||
  (source?!HEX.test(e.profile_sha256??''):e.profile_sha256!==null))fail('invalid_identity');
}
function validPlan(p,pin,mode){
 if(!exact(p,['format','project_ref','source_set_sha256','decision_reference_sha256','owner_decision','read_strategy','max_accounts','source','target','statement_timeout_ms','total_timeout_ms'])||
  p.format!==FORMAT||p.project_ref!==PROJECT||!HEX.test(p.source_set_sha256??'')||!HEX.test(p.decision_reference_sha256??'')||
  p.owner_decision!=='same_person_keep_cloud_primary'||!['strict_parameter_redaction','bounded_zero_bind'].includes(p.read_strategy)||!integer(p.max_accounts,1,32)||!HEX.test(pin??'')||identityPlanDigest(p)!==pin||
  !integer(p.statement_timeout_ms,250,30000)||!integer(p.total_timeout_ms,p.statement_timeout_ms,120000))fail('invalid_plan');
 for(const side of ['source','target']){
  const v=p[side];if(!exact(v,['identity','auth_user_id','app_user_id','record_hmac'])||!UUID.test(v.auth_user_id??'')||
   typeof v.app_user_id!=='string'||!TEXT.test(v.app_user_id)||Buffer.byteLength(v.app_user_id,'utf8')>128||
   (mode==='capture'?v.record_hmac!==null:!HEX.test(v.record_hmac??'')))fail('invalid_plan');
  validIdentity(v.identity,side==='source');
 }
 const a=p.source.identity,b=p.target.identity;
 if(a.transport.host===b.transport.host&&a.transport.port===b.transport.port&&a.database===b.database)fail('distinct_databases_required');
}
function validateClient(client,identity,source){
 try{
  if(!client||utilTypes.isProxy(client)||!(client instanceof Client)||active.has(client)||!client.connection?.once||
   !client.connection?.removeListener||!client.connection?.stream?.destroy)fail('invalid_client');
  const cp=client.connectionParameters,stream=client.connection.stream,t=identity.transport;
  if(cp?.host!==t.host||Number(cp.port)!==t.port||cp.database!==identity.database)fail('connection_mismatch');
  if(source){if(t.kind!=='local'||!(t.host==='127.0.0.1'||(isAbsolute(t.host)&&!t.host.split('/').includes('..'))))fail('connection_mismatch');}
  else if(t.kind==='managed'){
   const direct=t.host===`db.${PROJECT}.supabase.co`&&t.port===5432;
   const pooler=/^aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com$/.test(t.host)&&t.port===5432&&
    typeof cp.user==='string'&&cp.user.endsWith('.'+PROJECT);
   if(identity.database!=='postgres'||(!direct&&!pooler)||!cp.ssl||cp.ssl.rejectUnauthorized===false||cp.ssl.ca!==undefined||
    cp.ssl.checkServerIdentity!==undefined||stream.encrypted!==true||stream.authorized!==true||stream.servername!==t.host)fail('connection_mismatch');
  }else if(t.kind==='synthetic'){
   if(!/^collect_fixture_[a-z0-9_]+$/.test(identity.database)||!isSyntheticReconciliationSocket(t.host))fail('connection_mismatch');
  }else fail('connection_mismatch');
 }catch(e){if(trusted(e))throw e;fail('invalid_client');}
}
function destroy(client){try{client.connection.stream.destroy();}catch{}}
async function bounded(client,text,values,ms){
 if(ms<=0)fail('deadline_exceeded');let timer,timeoutError;
 try{return await Promise.race([
  Promise.resolve().then(()=>client.query({text,values,types:TYPE_PARSER})),
  new Promise((_,reject)=>{timer=setTimeout(()=>{destroy(client);timeoutError=new IdentityMappingError('deadline_exceeded');Object.freeze(timeoutError);internal.add(timeoutError);reject(timeoutError);},ms);})
 ]);}catch(e){if(e===timeoutError)throw e;fail('database_read_failed');}finally{clearTimeout(timer);}
}
async function idle(client,run,ms){
 let ready,timer;try{
  const status=new Promise((resolve,reject)=>{ready=m=>resolve(m?.status);client.connection.once('readyForQuery',ready);timer=setTimeout(()=>reject(Error()),ms);});
  const [res,tx]=await Promise.all([run(client,'SELECT pg_catalog.pg_backend_pid()::text AS pid'),status]);
  if(tx!=='I'||res.rows?.length!==1||!/^[1-9][0-9]*$/.test(res.rows[0].pid??''))fail('connection_not_idle');
  return res.rows[0].pid;
 }catch(e){if(trusted(e))throw e;fail('connection_not_idle');}finally{clearTimeout(timer);if(ready)client.connection.removeListener('readyForQuery',ready);}
}
function oneJson(res){if(res.rows?.length!==1||typeof res.rows[0].v!=='string'||Buffer.byteLength(res.rows[0].v,'utf8')>8192)fail('identity_unavailable');try{return JSON.parse(res.rows[0].v);}catch{fail('identity_unavailable');}}
// The table locks must already be held and no snapshot established before
// acquiring them. Reject inheritance in either direction: the verifier is
// deliberately qualified for ordinary, standalone baseline relations only.
async function verifyRelationTopology(client,source,run){
 const names=["'app.users'::regclass","'auth.users'::regclass","'private.auth_principal_links'::regclass",
  "'private.collect_fence_admissions'::regclass","'private.collect_fence_control'::regclass"];
 if(source)names.push("'private.collect_deployment_identity'::regclass");
 const q=await run(client,`WITH relations AS (SELECT pg_catalog.unnest(ARRAY[${names.join(',')}])::oid AS oid)
  SELECT count(*)::text AS n,pg_catalog.bool_and(c.relkind='r')::text AS ordinary,
   (NOT EXISTS (SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhparent IN (SELECT oid FROM relations)
     OR i.inhrelid IN (SELECT oid FROM relations)))::text AS standalone
  FROM relations r JOIN pg_catalog.pg_class c ON c.oid=r.oid`);
 if(q.rows?.length!==1||q.rows[0].n!==String(names.length)||q.rows[0].ordinary!=='true'||q.rows[0].standalone!=='true')fail('inherited_relation_unsupported');
}
async function verifyDatabase(client,expected,pid,source,run){
 const result=await run(client,`SELECT pg_catalog.json_build_object('database',pg_catalog.current_database(),'session_user',session_user,'current_user',current_user,
  'pid',pg_catalog.pg_backend_pid()::text,'isolation',pg_catalog.current_setting('transaction_isolation'),'read_only',pg_catalog.current_setting('transaction_read_only'),
  'server_encoding',pg_catalog.current_setting('server_encoding'),'client_encoding',pg_catalog.current_setting('client_encoding'),'version',pg_catalog.current_setting('server_version_num'),
  'replication_role',pg_catalog.current_setting('session_replication_role'),
  'project_ref',project_ref,'baseline_manifest_sha256',baseline_manifest_sha256,'source_sha256',source_sha256,'epoch',epoch::text,'mode',mode,'operation_id',operation_id::text)::text AS v
  FROM ONLY private.collect_fence_control WHERE singleton IS TRUE AND pg_catalog.octet_length(project_ref)<=20
   AND pg_catalog.octet_length(baseline_manifest_sha256)=64 AND pg_catalog.octet_length(source_sha256)=64`);
 const row=oneJson(result);
 if(row.pid!==pid||row.isolation!=='repeatable read'||row.read_only!=='on'||row.replication_role!=='origin'||row.server_encoding!=='UTF8'||row.client_encoding!=='UTF8'||!/^17[0-9]{4}$/.test(row.version)||
  ['database','session_user','current_user','project_ref','baseline_manifest_sha256','source_sha256','epoch','mode','operation_id'].some(k=>row[k]!==expected[k]))fail('identity_mismatch');
 const open=await run(client,"SELECT (NOT EXISTS(SELECT 1 FROM ONLY private.collect_fence_admissions WHERE state<>'settled' OR uncertain_dispatches IS NULL OR uncertain_dispatches<>0))::text AS clean");
 if(open.rows?.length!==1||open.rows[0].clean!=='true')fail('unsettled_work');
 if(source){const q=await run(client,"SELECT (profile_sha256=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(profile_raw,'UTF8')),'hex'))::text AS valid,profile_sha256 FROM ONLY private.collect_deployment_identity WHERE singleton IS TRUE AND octet_length(profile_raw)<=8192 AND octet_length(profile_sha256)=64");
  if(q.rows?.length!==1||q.rows[0].valid!=='true'||q.rows[0].profile_sha256!==expected.profile_sha256)fail('identity_mismatch');}
 const permissions=await run(client,`SELECT pg_catalog.bool_and(c.relkind='r' AND NOT pg_catalog.row_security_active(c.oid) AND pg_catalog.has_table_privilege(c.oid,'SELECT'))::text AS ok,
  count(*)::text AS n FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE (n.nspname,c.relname) IN (('auth','users'),('app','users'),('private','auth_principal_links'))`);
 if(permissions.rows?.[0]?.ok!=='true'||permissions.rows[0].n!=='3')fail('insufficient_visibility');
 // Confirm the baseline no-update/no-delete principal-link trigger and body.
 const guard=await run(client,`SELECT t.tgenabled::text AS enabled,t.tgtype::text AS kind,pg_catalog.pg_get_userbyid(p.proowner) AS owner,
  p.prosecdef::text AS definer,p.provolatile::text AS volatility,p.proconfig::text AS config,l.lanname AS language,
  pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc,'UTF8')),'hex') AS body
  FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid JOIN pg_catalog.pg_language l ON l.oid=p.prolang
  WHERE t.tgrelid='private.auth_principal_links'::regclass AND t.tgname='auth_principal_link_identity' AND NOT t.tgisinternal
  AND t.tgqual IS NULL AND t.tgnargs=0 AND t.tgattr::text='' AND t.tgconstraint=0 AND t.tgoldtable IS NULL AND t.tgnewtable IS NULL
  AND octet_length(coalesce(p.proconfig::text,''))<=256 AND octet_length(p.prosrc)<=16384 AND p.oid='private.trg_auth_principal_link_identity()'::regprocedure`);
 const g=guard.rows?.[0];if(guard.rows?.length!==1||!['O','A'].includes(g.enabled)||g.kind!=='27'||g.owner!=='postgres'||g.definer!=='false'||
  g.volatility!=='v'||g.config!=='{"search_path=pg_catalog, app"}'||g.language!=='plpgsql'||
  g.body!=='4359d94126c214d111d248515ca98da2c60b3b2d48ac2eb1bdb8359de5633435')fail('principal_guard_changed');
}
const RECORD_SELECT=`SELECT pg_catalog.json_build_object('auth_user_id',a.id::text,'auth_email',a.email,'auth_email_confirmed',a.email_confirmed_at IS NOT NULL,
  'auth_deleted',a.deleted_at IS NOT NULL,'auth_banned',coalesce(a.banned_until>statement_timestamp(),false),
  'app_user_id',u.id,'phone',u.phone,'email',u.email,'public_id',u.public_id,'access_status',u.access_status,'revision',u.revision::text)::text AS v
  FROM ONLY private.auth_principal_links l JOIN ONLY auth.users a ON a.id=l.auth_user_id JOIN ONLY app.users u ON u.id=l.user_id`;
function validateRecord(r,side){
 if(!r||r.auth_user_id!==side.auth_user_id||r.app_user_id!==side.app_user_id||r.auth_deleted!==false||r.auth_banned!==false||r.access_status!=='active'||
  typeof r.public_id!=='string'||r.public_id.length<1||r.public_id.length>128||!/^\d{1,20}$/.test(r.revision??'')||
  !(r.phone===null||typeof r.phone==='string')||!(r.email===null||typeof r.email==='string'))fail('identity_unavailable');
 normalizedEmail(r.auth_email);return r;
}
const USER_RAW_BYTES=`coalesce(pg_catalog.octet_length(u.id)::bigint,0)+coalesce(pg_catalog.octet_length(u.phone)::bigint,0)+
 coalesce(pg_catalog.octet_length(u.email)::bigint,0)+coalesce(pg_catalog.octet_length(u.public_id)::bigint,0)`;
const LINKED_RAW_BYTES=`${USER_RAW_BYTES}+coalesce(pg_catalog.octet_length(a.id::text)::bigint,0)+coalesce(pg_catalog.octet_length(a.email)::bigint,0)+
 coalesce(pg_catalog.octet_length(u.access_status)::bigint,0)+coalesce(pg_catalog.octet_length(u.revision::text)::bigint,0)`;
const LINKED_FROM='FROM ONLY private.auth_principal_links l JOIN ONLY auth.users a ON a.id=l.auth_user_id JOIN ONLY app.users u ON u.id=l.user_id';
const MAX_RAW_ROW=1024,MAX_RAW_TOTAL=16384;
function measurement(result,maximum){
 if(result.rows?.length!==1)fail('identity_unavailable');
 const r=result.rows[0];if(!['n','max_bytes','total_bytes'].every(k=>/^[0-9]+$/.test(r[k]??'')))fail('identity_unavailable');
 const count=Number(r.n),max=Number(r.max_bytes),total=Number(r.total_bytes);
 if(!Number.isSafeInteger(count)||!Number.isSafeInteger(max)||!Number.isSafeInteger(total))fail('identity_data_too_large');
 if(count>maximum)fail('account_capacity_or_link_mismatch');
 if(max>MAX_RAW_ROW||total>MAX_RAW_TOTAL)fail('identity_data_too_large');
 return {count,total};
}
async function record(client,side,run){
 // Measure selected raw bytes on the server before fetching any identity row.
 const preflight=await run(client,`SELECT count(*)::text AS n,coalesce(max(bytes),0)::text AS max_bytes,coalesce(sum(bytes),0)::text AS total_bytes FROM
  (SELECT ${LINKED_RAW_BYTES} AS bytes ${LINKED_FROM} WHERE l.auth_user_id=$1::uuid AND l.user_id=$2 LIMIT 2) AS measured`,[side.auth_user_id,side.app_user_id]);
 if(measurement(preflight,1).count!==1)fail('identity_unavailable');
 const links=await run(client,'SELECT count(*)::text AS n FROM ONLY private.auth_principal_links WHERE auth_user_id=$1::uuid OR user_id=$2',[side.auth_user_id,side.app_user_id]);
 if(links.rows?.length!==1||links.rows[0].n!=='1')fail('identity_unavailable');
 const result=await run(client,RECORD_SELECT+' WHERE l.auth_user_id=$1::uuid AND l.user_id=$2 LIMIT 2',[side.auth_user_id,side.app_user_id]);
 return validateRecord(oneJson(result),side);
}
// Exact byte equality is sufficient only for text keys with deterministic
// collations and these exact baseline unique indexes; refuse any extra index.
async function zeroBindKeyCatalog(client,run){
 const cols=await run(client,`SELECT a.attname AS name,pg_catalog.format_type(a.atttypid,a.atttypmod) AS type,
  coalesce(c.collisdeterministic,false)::text AS deterministic
  FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class t ON t.oid=a.attrelid JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
  LEFT JOIN pg_catalog.pg_collation c ON c.oid=a.attcollation
  WHERE n.nspname='app' AND t.relname='users' AND a.attnum>0 AND NOT a.attisdropped AND a.attname IN ('id','phone','email','public_id') ORDER BY a.attname`);
 const names=['email','id','phone','public_id'];
 if(cols.rows?.length!==names.length||cols.rows.some((x,i)=>x.name!==names[i]||x.type!=='text'||x.deterministic!=='true'))fail('target_key_catalog_changed');
 const indexes=await run(client,`SELECT i.relname AS name,
  CASE WHEN pg_catalog.octet_length(pg_catalog.pg_get_indexdef(i.oid))<=256 THEN pg_catalog.pg_get_indexdef(i.oid) ELSE NULL END AS definition,
  x.indisvalid::text AS valid,x.indisready::text AS ready
  FROM pg_catalog.pg_class t JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace JOIN pg_catalog.pg_index x ON x.indrelid=t.oid
  JOIN pg_catalog.pg_class i ON i.oid=x.indexrelid WHERE n.nspname='app' AND t.relname='users' AND x.indisunique ORDER BY i.relname LIMIT 5`);
 const expected=[['users_email_key','email'],['users_phone_key','phone'],['users_pkey','id'],['users_public_id_key','public_id']];
 if(indexes.rows?.length!==expected.length||indexes.rows.some((x,i)=>x.name!==expected[i][0]||x.valid!=='true'||x.ready!=='true'||
  x.definition!==`CREATE UNIQUE INDEX ${expected[i][0]} ON app.users USING btree (${expected[i][1]})`))fail('target_key_catalog_changed');
}
async function scanPreflight(client,maximum,run){
 const limit=maximum+1;
 const users=await run(client,`SELECT count(*)::text AS n,coalesce(max(bytes),0)::text AS max_bytes,coalesce(sum(bytes),0)::text AS total_bytes FROM
  (SELECT ${USER_RAW_BYTES} AS bytes FROM ONLY app.users u ORDER BY u.id LIMIT ${limit}) AS measured`);
 const linked=await run(client,`SELECT count(*)::text AS n,coalesce(max(bytes),0)::text AS max_bytes,coalesce(sum(bytes),0)::text AS total_bytes FROM
  (SELECT ${LINKED_RAW_BYTES} AS bytes ${LINKED_FROM} ORDER BY l.auth_user_id,l.user_id LIMIT ${limit}) AS measured`);
 const totalLinks=await run(client,`SELECT count(*)::text AS n FROM (SELECT 1 FROM ONLY private.auth_principal_links LIMIT ${limit}) AS bounded_links`);
 const u=measurement(users,maximum),l=measurement(linked,maximum);
 if(totalLinks.rows?.length!==1||!/^\d+$/.test(totalLinks.rows[0].n??'')||Number(totalLinks.rows[0].n)!==l.count)fail('account_capacity_or_link_mismatch');
 return u.total+l.total;
}
async function scan(client,side,maximum,run){
 const limit=maximum+1;
 const users=await run(client,`SELECT pg_catalog.json_build_object('app_user_id',id,'phone',phone,'email',email,'public_id',public_id)::text AS v FROM ONLY app.users ORDER BY id LIMIT ${limit}`);
 const linked=await run(client,RECORD_SELECT+` ORDER BY l.auth_user_id,l.user_id LIMIT ${limit}`);
 const n=await run(client,`SELECT count(*)::text AS n FROM (SELECT 1 FROM ONLY private.auth_principal_links LIMIT ${limit}) AS bounded_links`);
 if(!Array.isArray(users.rows)||!Array.isArray(linked.rows)||users.rows.length>maximum||linked.rows.length>maximum||
  n.rows?.length!==1||!/^\d+$/.test(n.rows[0].n??'')||Number(n.rows[0].n)!==linked.rows.length)fail('account_capacity_or_link_mismatch');
 const userRows=users.rows.map(row=>oneJson({rows:[row]}));
 if(userRows.some(u=>!exact(u,['app_user_id','phone','email','public_id'])||typeof u.app_user_id!=='string'||typeof u.public_id!=='string'||
  !(u.phone===null||typeof u.phone==='string')||!(u.email===null||typeof u.email==='string')))fail('identity_unavailable');
 const identities=linked.rows.map(row=>oneJson({rows:[row]}));
 const matches=identities.filter(r=>r.auth_user_id===side.auth_user_id&&r.app_user_id===side.app_user_id);
 const touches=identities.filter(r=>r.auth_user_id===side.auth_user_id||r.app_user_id===side.app_user_id);
 if(matches.length!==1||touches.length!==1)fail('identity_unavailable');
 return {record:validateRecord(matches[0],side),users:userRows};
}
function collisionInMemory(source,target,users){
 if(users.some(u=>u.app_user_id!==target.app_user_id&&(
  (source.phone!==null&&u.phone===source.phone)||(source.email!==null&&u.email===source.email)||
  u.public_id===source.public_id||u.app_user_id===source.app_user_id)))fail('target_user_collision');
}
async function collision(client,source,target,run){
 const q=await run(client,`SELECT count(*)::text AS n FROM ONLY app.users WHERE id<>$1 AND
  (($2::text IS NOT NULL AND phone=$2) OR ($3::text IS NOT NULL AND email=$3) OR public_id=$4 OR id=$5)`,
  [target.app_user_id,source.phone,source.email,source.public_id,source.app_user_id]);
 if(q.rows?.length!==1||q.rows[0].n!=='0')fail('target_user_collision');
}
/** Only valid synchronously while the trusted callback runs under both locks. */
export function translateOwnerAppUserId(capability,sourceId){
 const value=capability&&typeof capability==='object'?caps.get(capability):null;
 if(!value||value.closed||typeof sourceId!=='string'||sourceId!==value.source)fail('identity_mapping_unavailable');
 return value.target;
}
/** Consumes/ends dedicated clients after admission. Returns no principal IDs or email. */
export async function inspectOwnerIdentity({sourceClient,targetClient,plan,expectedPlanSha256,key,mode='verify',onVerified}){
 let ownedKey,cap;
 try{
  ownedKey=ownBuffer(key);const p=clone(plan);
  if(!['capture','verify'].includes(mode)||(onVerified!==undefined&&typeof onVerified!=='function')||(mode==='capture'&&onVerified!==undefined))fail('invalid_plan');
  validPlan(p,expectedPlanSha256,mode);
  if(sourceClient===targetClient)fail('distinct_databases_required');
  validateClient(sourceClient,p.source.identity,true);validateClient(targetClient,p.target.identity,false);
  active.add(sourceClient);active.add(targetClient);
  const clients=[sourceClient,targetClient],deadline=performance.now()+p.total_timeout_ms;
  const run=(c,sql,values=[])=>{
   if(p.read_strategy==='bounded_zero_bind'&&values.length)fail('zero_bind_required');
   return bounded(c,sql,values,Math.min(p.statement_timeout_ms+1000,deadline-performance.now()));
  };
  try{
   const pids=[];for(const c of clients)pids.push(await idle(c,run,Math.min(5000,Math.max(1,deadline-performance.now()))));
   for(const [i,c] of clients.entries()){
    const begun=await run(c,'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');if(begun.command!=='BEGIN')fail('transaction_failed');
    await run(c,`SET LOCAL statement_timeout = '${p.statement_timeout_ms}ms'`);await run(c,"SET LOCAL lock_timeout = '1000ms'");
    await run(c,"SET LOCAL idle_in_transaction_session_timeout = '35s'");await run(c,'SET LOCAL search_path = pg_catalog');await run(c,'SET LOCAL row_security = off');
    // The zero-bind path sends no identifying values to PostgreSQL. The
    // parameterized path fails closed unless both bind-log controls are set.
    if(p.read_strategy==='strict_parameter_redaction')await run(c,'SET LOCAL log_parameter_max_length = 0');
    await run(c,'SET LOCAL log_parameter_max_length_on_error = 0');
    // Acquire the whole ordered lock set before the first SELECT in this
    // transaction. A prior SELECT would anchor a repeatable-read snapshot
    // that could hide fence, admission or identity changes committed while
    // this multi-table LOCK is waiting.
    // Lock recursively so an existing inherited relation cannot be modified
    // while its presence is being checked. Parent SHARE locks also exclude
    // concurrent attach/inherit DDL until transaction end.
    const tables=['app.users','auth.users','private.auth_principal_links','private.collect_fence_admissions','private.collect_fence_control'];
    if(i===0)tables.push('private.collect_deployment_identity');tables.sort();
    await run(c,'LOCK TABLE '+tables.join(',')+' IN SHARE MODE');
    await verifyRelationTopology(c,i===0,run);
    const logging=await run(c,p.read_strategy==='strict_parameter_redaction'
      ?"SELECT (current_setting('log_parameter_max_length')='0' AND current_setting('log_parameter_max_length_on_error')='0')::text AS safe"
      :"SELECT (current_setting('log_parameter_max_length_on_error')='0')::text AS safe");
    if(logging.rows?.length!==1||logging.rows[0].safe!=='true')fail('logging_unverified');
    await verifyDatabase(c,i===0?p.source.identity:p.target.identity,pids[i],i===0,run);
   }
   // PostgreSQL assigns an XID even to these read-only transactions. Pin it so
   // an accidental COMMIT/restart in the trusted callback cannot be accepted.
   const txids=[];
   for(const c of clients){const x=await run(c,'SELECT pg_catalog.pg_current_xact_id()::text AS xid');if(x.rows?.length!==1||!/^\d+$/.test(x.rows[0].xid??''))fail('transaction_failed');txids.push(x.rows[0].xid);}
   let a,b;
   if(p.read_strategy==='bounded_zero_bind'){
    await zeroBindKeyCatalog(sourceClient,run);await zeroBindKeyCatalog(targetClient,run);
    // Both preflights run under the locked snapshots before either side's
    // selected identity payload is returned to the application.
    const sourceBytes=await scanPreflight(sourceClient,p.max_accounts,run),targetBytes=await scanPreflight(targetClient,p.max_accounts,run);
    if(sourceBytes+targetBytes>MAX_RAW_TOTAL)fail('identity_data_too_large');
    const sourceScan=await scan(sourceClient,p.source,p.max_accounts,run),targetScan=await scan(targetClient,p.target,p.max_accounts,run);
    a=sourceScan.record;b=targetScan.record;collisionInMemory(a,b,targetScan.users);
   }else{a=await record(sourceClient,p.source,run);b=await record(targetClient,p.target,run);await collision(targetClient,a,b,run);}
   if(normalizedEmail(a.auth_email)!==normalizedEmail(b.auth_email))fail('identity_evidence_changed');
   const sourceHmac=digestRecord(ownedKey,a),targetHmac=digestRecord(ownedKey,b);
   if(mode==='verify'){
    const same=(x,y)=>timingSafeEqual(Buffer.from(x,'hex'),Buffer.from(y,'hex'));
    if(!same(sourceHmac,p.source.record_hmac)||!same(targetHmac,p.target.record_hmac))fail('identity_preimage_changed');
    if(onVerified){
     cap=Object.freeze(Object.create(null));caps.set(cap,{source:p.source.app_user_id,target:p.target.app_user_id,closed:false});
     let timer;try{
      await Promise.race([Promise.resolve().then(()=>onVerified(cap)),new Promise((_,reject)=>{timer=setTimeout(()=>{for(const c of clients)destroy(c);reject(Error());},Math.max(1,deadline-performance.now()));})]);
     }catch{fail('callback_failed');}finally{clearTimeout(timer);const state=caps.get(cap);if(state)state.closed=true;}
    }
   }
   for(const [i,c] of clients.entries()){
    const after=await run(c,"SELECT pg_catalog.pg_backend_pid()::text AS pid,pg_catalog.pg_current_xact_id()::text AS xid,pg_catalog.current_setting('transaction_read_only') AS read_only");
    if(after.rows?.length!==1||after.rows[0].pid!==pids[i]||after.rows[0].xid!==txids[i]||after.rows[0].read_only!=='on')fail('transaction_changed');
    const r=await run(c,'ROLLBACK');if(r.command!=='ROLLBACK')fail('transaction_failed');
   }
   return {format:FORMAT,status:mode==='capture'?'fingerprints_captured':'selected_identity_snapshot_verified',plan_sha256:expectedPlanSha256,
    source_set_sha256:p.source_set_sha256,source_record_hmac:sourceHmac,target_record_hmac:targetHmac,
    owner_decision:'same_person_keep_cloud_primary',read_strategy:p.read_strategy,existing_target_link_unchanged_in_snapshot:true,
    schema_actor_exclusion_verified:false,quiescence_proven:false,historical_reference_mapping_verified:false,business_rows_migrated:0,write_authorized:false};
  }catch(e){if(trusted(e))throw e;fail('verification_failed');}
  finally{for(const c of clients){destroy(c);active.delete(c);}for(const c of clients){try{void c.end().catch(()=>{});}catch{}}}
 }catch(e){if(trusted(e))throw e;fail('verification_failed');}
 finally{if(cap){const state=caps.get(cap);if(state)state.closed=true;}ownedKey?.fill(0);}
}
