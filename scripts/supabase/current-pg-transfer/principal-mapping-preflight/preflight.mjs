// Read-only, aggregate-only observation for one explicitly owner-approved pair.
// No account is created, merged or inferred from matching keys or emails.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {performance} from 'node:perf_hooks';
import {types as utilTypes} from 'node:util';
import pg from '../../node_modules/pg/lib/index.js';
import {isManagedReconciliationPeer} from '../managed-target.mjs';
import {isSyntheticReconciliationSocket} from '../reconcile.mjs';
const {Client}=pg,PROJECT='rrlduytparvsjfmegalh',FORMAT='collect.principal-mapping-preflight.v1';
const HEX=/^[0-9a-f]{64}$/,UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const ROLE=/^[a-z_][a-z0-9_]{0,62}$/,SAFE=/^[^\u0000-\u001f\u007f\ud800-\udfff]{1,128}$/u,active=new WeakSet(),internal=new WeakSet();
const TYPES={getTypeParser(_oid,format){if(format!=='text')fail('result_refused');return value=>value;}};
export class PreflightError extends Error{constructor(code){super(code);this.name='PreflightError';this.code=code;}}
const makeError=c=>{const e=new PreflightError(c);Object.freeze(e);internal.add(e);return e;},trusted=e=>!!e&&typeof e==='object'&&!utilTypes.isProxy(e)&&internal.has(e);
const fail=c=>{throw makeError(c);},exact=(o,k)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).sort().join('\0')===[...k].sort().join('\0');
function copy(v,depth=0){
 if(depth>8)fail('plan_refused');if(v===null||typeof v==='string'||typeof v==='boolean'||typeof v==='number'&&Number.isSafeInteger(v))return v;
 if(!v||typeof v!=='object'||utilTypes.isProxy(v)||Array.isArray(v)||Object.getPrototypeOf(v)!==Object.prototype||Object.getOwnPropertySymbols(v).length)fail('plan_refused');
 const out={};for(const [k,d] of Object.entries(Object.getOwnPropertyDescriptors(v))){if(k==='__proto__'||!d.enumerable||!Object.hasOwn(d,'value'))fail('plan_refused');Object.defineProperty(out,k,{value:copy(d.value,depth+1),enumerable:true});}return out;
}
function canonical(v){if(v===null||typeof v==='string'||typeof v==='boolean'||typeof v==='number')return JSON.stringify(v);return '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}';}
export function preflightPlanDigest(plan){try{return createHash('sha256').update(canonical(copy(plan)),'utf8').digest('hex');}catch(e){if(trusted(e))throw e;fail('plan_refused');}}
function planCheck(p,pin){
 if(!exact(p,['format','project_ref','owner_decision','decision_reference_sha256','source_set_sha256','max_rows','statement_timeout_ms','total_timeout_ms','source','target'])||p.format!==FORMAT||p.project_ref!==PROJECT||
  p.owner_decision!=='same_person_keep_cloud_primary'||!HEX.test(p.decision_reference_sha256??'')||!HEX.test(p.source_set_sha256??'')||!HEX.test(pin??'')||preflightPlanDigest(p)!==pin||
  !Number.isSafeInteger(p.max_rows)||p.max_rows<1||p.max_rows>64||!Number.isSafeInteger(p.statement_timeout_ms)||p.statement_timeout_ms<250||p.statement_timeout_ms>30000||
  !Number.isSafeInteger(p.total_timeout_ms)||p.total_timeout_ms<p.statement_timeout_ms||p.total_timeout_ms>120000)fail('plan_refused');
 for(const [side,source] of [[p.source,true],[p.target,false]]){
  if(!exact(side,['kind','host','port','database','session_user','current_user','profile_sha256','auth_user_id','app_user_id'])||
   !['local','managed','synthetic'].includes(side.kind)||typeof side.host!=='string'||!Number.isSafeInteger(side.port)||side.port<1||side.port>65535||
   !ROLE.test(side.database??'')||!ROLE.test(side.session_user??'')||!ROLE.test(side.current_user??'')||!UUID.test(side.auth_user_id??'')||
   typeof side.app_user_id!=='string'||!SAFE.test(side.app_user_id)||Buffer.byteLength(side.app_user_id)>128||
   (source?!HEX.test(side.profile_sha256??''):side.profile_sha256!==null))fail('plan_refused');
 }
 if(!['local','synthetic'].includes(p.source.kind)||!['managed','synthetic'].includes(p.target.kind)||
  (p.source.kind==='synthetic')!==(p.target.kind==='synthetic')||
  (p.source.host===p.target.host&&p.source.port===p.target.port&&p.source.database===p.target.database))fail('plan_refused');
}
function validateClient(c,s,source){
 if(!c||utilTypes.isProxy(c)||!(c instanceof Client)||active.has(c)||!c.connection?.stream?.destroy||!c.connection?.once||!c.connection?.removeListener)fail('client_refused');
 const cp=c.connectionParameters,t=c.connection.stream;
 if(cp?.host!==s.host||Number(cp.port)!==s.port||cp.database!==s.database||cp.user!==s.session_user||cp.replication||cp.options||cp.binary)fail('client_refused');
 if(s.kind==='synthetic'){
  if(!isSyntheticReconciliationSocket(s.host)||!/^collect_fixture_[a-z0-9_]+$/.test(s.database))fail('client_refused');
 }else if(source){
  if(s.kind!=='local'||!(s.host==='127.0.0.1'||isAbsolute(s.host)&&!s.host.split('/').includes('..')))fail('client_refused');
 }else if(s.kind!=='managed'||s.host!==`db.${PROJECT}.supabase.co`||s.port!==5432||s.database!=='postgres'||s.session_user!=='postgres'||s.current_user!=='postgres'||
  !isManagedReconciliationPeer(cp,t))fail('client_refused');
}
function destroy(c){try{c.connection.stream.destroy();}catch{}}
async function query(c,text,ms){
 if(ms<=0)fail('deadline_exceeded');let timer;
 try{return await Promise.race([c.query({text,values:[],types:TYPES}),new Promise((_,reject)=>{timer=setTimeout(()=>{destroy(c);reject(makeError('deadline_exceeded'));},ms);})]);}
 catch(e){if(trusted(e)&&e.code==='deadline_exceeded')throw e;fail('database_read_refused');}finally{clearTimeout(timer);}
}
async function idle(c,run,ms){let listener,timer;try{
 const ready=new Promise((resolve,reject)=>{listener=m=>resolve(m?.status);c.connection.once('readyForQuery',listener);timer=setTimeout(()=>reject(Error()),ms);});
 const [r,state]=await Promise.all([run(c,'SELECT pg_catalog.pg_backend_pid()::text AS pid'),ready]);
 if(state!=='I'||r.rows?.length!==1||!/^[1-9][0-9]*$/.test(r.rows[0].pid??''))fail('client_not_idle');return r.rows[0].pid;
 }catch(e){if(trusted(e))throw e;fail('client_not_idle');}finally{clearTimeout(timer);if(listener)c.connection.removeListener('readyForQuery',listener);}}
async function guard(c,source,run){
 const pairs=source?"(('app','users'),('auth','users'),('private','auth_principal_links'),('private','collect_deployment_identity'))":"(('app','users'),('auth','users'),('private','auth_principal_links'))";
 const r=await run(c,`SELECT count(*)::text AS n,count(*) FILTER (WHERE c.relkind<>'r' OR NOT pg_catalog.has_schema_privilege(n.oid,'USAGE') OR NOT pg_catalog.has_table_privilege(c.oid,'SELECT') OR pg_catalog.row_security_active(c.oid) OR EXISTS(SELECT 1 FROM pg_catalog.pg_inherits i WHERE i.inhrelid=c.oid OR i.inhparent=c.oid))::text AS bad FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname,c.relname) IN ${pairs}`);
 if(r.rows?.length!==1||r.rows[0].n!==(source?'4':'3')||r.rows[0].bad!=='0')fail('visibility_or_topology_refused');
 const cols=await run(c,`SELECT n.nspname AS schema,c.relname AS table_name,a.attname AS name,pg_catalog.format_type(a.atttypid,a.atttypmod) AS type,coalesce(k.collisdeterministic,false)::text AS deterministic
  FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class c ON c.oid=a.attrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_catalog.pg_collation k ON k.oid=a.attcollation
  WHERE a.attnum>0 AND NOT a.attisdropped AND ((n.nspname='app' AND c.relname='users' AND a.attname IN ('id','phone','email','public_id')) OR (n.nspname='auth' AND c.relname='users' AND a.attname='email')) ORDER BY n.nspname,c.relname,a.attname`);
 if(cols.rows?.length!==5||cols.rows.some(x=>x.deterministic!=='true'||!(x.type==='text'||/^character varying(?:\([1-9][0-9]{0,4}\))?$/.test(x.type)))||
  cols.rows.map(x=>x.schema+'.'+x.table_name+'.'+x.name).join(',')!=='app.users.email,app.users.id,app.users.phone,app.users.public_id,auth.users.email')fail('key_catalog_refused');
 const core=await run(c,`SELECT n.nspname AS schema,c.relname AS table_name,a.attname AS name,pg_catalog.format_type(a.atttypid,a.atttypmod) AS type
  FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class c ON c.oid=a.attrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE a.attnum>0 AND NOT a.attisdropped AND ((n.nspname='app' AND c.relname='users' AND a.attname='access_status') OR (n.nspname='auth' AND c.relname='users' AND a.attname IN ('id','deleted_at','banned_until')) OR (n.nspname='private' AND c.relname='auth_principal_links' AND a.attname IN ('auth_user_id','user_id'))) ORDER BY n.nspname,c.relname,a.attname`);
 const expected=['app.users.access_status:text','auth.users.banned_until:timestamp with time zone','auth.users.deleted_at:timestamp with time zone','auth.users.id:uuid','private.auth_principal_links.auth_user_id:uuid','private.auth_principal_links.user_id:text'];
 if(core.rows?.length!==expected.length||core.rows.some((x,i)=>x.schema+'.'+x.table_name+'.'+x.name+':'+x.type!==expected[i]))fail('key_catalog_refused');
}
async function identity(c,s,pid,source,run){
 const r=await run(c,"SELECT current_database() AS database,session_user AS session_user,current_user AS current_user,pg_catalog.pg_backend_pid()::text AS pid,current_setting('transaction_read_only') AS ro,current_setting('transaction_isolation') AS isolation,current_setting('server_encoding') AS encoding,current_setting('client_encoding') AS client_encoding,current_setting('server_version_num') AS version");
 const x=r.rows?.[0];if(r.rows?.length!==1||x.database!==s.database||x.session_user!==s.session_user||x.current_user!==s.current_user||x.pid!==pid||x.ro!=='on'||x.isolation!=='repeatable read'||x.encoding!=='UTF8'||x.client_encoding!=='UTF8'||!/^17[0-9]{4}$/.test(x.version??''))fail('database_identity_refused');
 if(source){const p=await run(c,"SELECT profile_sha256,pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(profile_raw,'UTF8')),'hex') AS calculated FROM ONLY private.collect_deployment_identity WHERE singleton IS TRUE AND pg_catalog.octet_length(profile_raw)<=8192 AND pg_catalog.octet_length(profile_sha256)=64");
  if(p.rows?.length!==1||p.rows[0].profile_sha256!==s.profile_sha256||p.rows[0].calculated!==s.profile_sha256)fail('source_profile_refused');}
}
const RAW={
 auth:"coalesce(octet_length(id::text),0)+coalesce(octet_length(email),0)",
 app:"coalesce(octet_length(id),0)+coalesce(octet_length(phone),0)+coalesce(octet_length(email),0)+coalesce(octet_length(public_id),0)+coalesce(octet_length(access_status),0)",
 links:"coalesce(octet_length(auth_user_id::text),0)+coalesce(octet_length(user_id),0)"
},TABLE={auth:'auth.users',app:'app.users',links:'private.auth_principal_links'};
async function measure(c,max,run){let bytes=0;const counts={};for(const kind of ['auth','app','links']){
 const r=await run(c,`SELECT count(*)::text AS n,coalesce(max(bytes),0)::text AS max_bytes,coalesce(sum(bytes),0)::text AS total_bytes FROM (SELECT ${RAW[kind]} AS bytes FROM ONLY ${TABLE[kind]} LIMIT ${max+1}) AS bounded`);
 const x=r.rows?.[0];if(r.rows?.length!==1||!['n','max_bytes','total_bytes'].every(k=>/^[0-9]+$/.test(x[k]??'')))fail('data_bound_refused');
 const n=Number(x.n),m=Number(x.max_bytes),total=Number(x.total_bytes);if(![n,m,total].every(Number.isSafeInteger)||n>max||m>1024||total>32768)fail('data_bound_refused');counts[kind]=n;bytes+=total;
 }return {counts,bytes};}
function txt(x,nullable=false){return nullable&&x===null||typeof x==='string'&&x.length>0&&Buffer.byteLength(x)<=1024&&!/[\u0000-\u001f\u007f\ud800-\udfff]/u.test(x);}
async function scan(c,max,expected,run){
 const auth=await run(c,`SELECT id::text AS id,email,(deleted_at IS NOT NULL)::text AS deleted,coalesce(banned_until>statement_timestamp(),false)::text AS banned FROM ONLY auth.users ORDER BY id LIMIT ${max+1}`);
 const app=await run(c,`SELECT id,phone,email,public_id,access_status FROM ONLY app.users ORDER BY id LIMIT ${max+1}`);
 const links=await run(c,`SELECT auth_user_id::text AS auth_id,user_id FROM ONLY private.auth_principal_links ORDER BY auth_user_id,user_id LIMIT ${max+1}`);
 if(![auth,app,links].every(x=>Array.isArray(x.rows))||auth.rows.length!==expected.auth||app.rows.length!==expected.app||links.rows.length!==expected.links||
  auth.rows.some(x=>!UUID.test(x.id??'')||!txt(x.email,true)||!['true','false'].includes(x.deleted)||!['true','false'].includes(x.banned))||
  app.rows.some(x=>!txt(x.id)||!txt(x.phone,true)||!txt(x.email,true)||!txt(x.public_id)||!txt(x.access_status))||
  links.rows.some(x=>!UUID.test(x.auth_id??'')||!txt(x.user_id)))fail('data_shape_refused');
 return {auth:auth.rows,app:app.rows,links:links.rows};
}
function email(v){if(typeof v!=='string')return null;const x=v.replace(/^ +| +$/g,'').replace(/[A-Z]/g,c=>c.toLowerCase());return x.length>=3&&x.length<=254&&/^[\x21-\x7e]+$/.test(x)&&/^[^@]+@[^@]+$/.test(x)?x:null;}
function summarize(data,expected){const a=data.auth.filter(x=>x.id===expected.auth_user_id),u=data.app.filter(x=>x.id===expected.app_user_id),l=data.links.filter(x=>x.auth_id===expected.auth_user_id&&x.user_id===expected.app_user_id),touch=data.links.filter(x=>x.auth_id===expected.auth_user_id||x.user_id===expected.app_user_id);
 const authIds=new Set(data.auth.map(x=>x.id)),appIds=new Set(data.app.map(x=>x.id));
 return {counts:{auth_users:data.auth.length,app_users:data.app.length,principal_links:data.links.length,selected_auth_rows:a.length,selected_app_rows:u.length,selected_exact_links:l.length,selected_link_touches:touch.length,
  dangling_links:data.links.filter(x=>!authIds.has(x.auth_id)||!appIds.has(x.user_id)).length,selected_auth_inactive:a.filter(x=>x.deleted==='true'||x.banned==='true').length,selected_app_inactive:u.filter(x=>x.access_status!=='active').length},auth:a.length===1?a[0]:null,app:u.length===1?u[0]:null};
}
function cross(source,target,sourceData,targetData,sourceExpected,targetExpected){
 const x=source.app,otherTarget=targetData.app.filter(u=>u.id!==targetExpected.app_user_id),otherSource=sourceData.app.filter(u=>u.id!==sourceExpected.app_user_id),same=(a,b)=>a!==null&&b!==null&&a===b;
 const ownerEmail=email(source.auth?.email),cloudEmail=email(target.auth?.email);
 const result={selected_auth_email_matches:ownerEmail===null||cloudEmail===null?null:ownerEmail===cloudEmail,cloud_auth_emails_uncomparable:targetData.auth.filter(a=>email(a.email)===null).length,
  selected_auth_ids_equal:sourceExpected.auth_user_id===targetExpected.auth_user_id,other_cloud_auth_id_conflicts:targetData.auth.filter(a=>a.id!==targetExpected.auth_user_id&&a.id===sourceExpected.auth_user_id).length,
  other_cloud_auth_email_matches:ownerEmail===null?null:targetData.auth.filter(a=>a.id!==targetExpected.auth_user_id&&email(a.email)===ownerEmail).length,
  selected_source_app_key_conflicts:x?{id:otherTarget.filter(t=>same(x.id,t.id)).length,phone:otherTarget.filter(t=>same(x.phone,t.phone)).length,email:otherTarget.filter(t=>same(x.email,t.email)).length,public_id:otherTarget.filter(t=>same(x.public_id,t.public_id)).length}:null,
  unselected_source_app_key_conflicts:{id:0,phone:0,email:0,public_id:0}};
 for(const s of otherSource)for(const t of targetData.app)for(const k of ['id','phone','email','public_id'])if(same(s[k],t[k]))result.unselected_source_app_key_conflicts[k]++;
 return result;
}
// The caller supplies fresh dedicated connected pg clients; admitted clients
// are consumed and closed. Plan IDs never appear in SQL or the returned object.
export async function observePrincipalMapping(options){
 let p,admitted=false,sourceClient,targetClient,plan,expectedPlanSha256;try{
  if(!options||typeof options!=='object'||utilTypes.isProxy(options)||Object.getPrototypeOf(options)!==Object.prototype||!exact(options,['sourceClient','targetClient','plan','expectedPlanSha256'])||Object.getOwnPropertySymbols(options).length)fail('plan_refused');
  const d=Object.getOwnPropertyDescriptors(options);if(Object.values(d).some(x=>!x.enumerable||!Object.hasOwn(x,'value')))fail('plan_refused');
  ({sourceClient,targetClient,plan,expectedPlanSha256}=Object.fromEntries(Object.entries(d).map(([k,v])=>[k,v.value])));
  p=copy(plan);planCheck(p,expectedPlanSha256);if(sourceClient===targetClient)fail('client_refused');validateClient(sourceClient,p.source,true);validateClient(targetClient,p.target,false);
  active.add(sourceClient);active.add(targetClient);admitted=true;const clients=[sourceClient,targetClient],deadline=performance.now()+p.total_timeout_ms;
  const run=(c,sql)=>query(c,sql,Math.min(p.statement_timeout_ms+1000,deadline-performance.now()));
  const pids=[];for(const c of clients)pids.push(await idle(c,run,Math.min(5000,Math.max(1,deadline-performance.now()))));
  const txids=[];for(const [i,c] of clients.entries()){
   const b=await run(c,'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');if(b.command!=='BEGIN')fail('transaction_refused');
   await run(c,`SET LOCAL statement_timeout = '${p.statement_timeout_ms}ms'`);await run(c,"SET LOCAL lock_timeout='1000ms'");await run(c,"SET LOCAL idle_in_transaction_session_timeout='35s'");await run(c,'SET LOCAL search_path=pg_catalog');await run(c,'SET LOCAL row_security=off');
   const tables=['app.users','auth.users','private.auth_principal_links'];if(i===0)tables.push('private.collect_deployment_identity');tables.sort();
   await run(c,'LOCK TABLE '+tables.join(',')+' IN SHARE MODE');await guard(c,i===0,run);await identity(c,i===0?p.source:p.target,pids[i],i===0,run);
   const x=await run(c,'SELECT pg_catalog.pg_current_xact_id()::text AS xid');if(x.rows?.length!==1||!/^[0-9]+$/.test(x.rows[0].xid??''))fail('transaction_refused');txids.push(x.rows[0].xid);
  }
  const a=await measure(sourceClient,p.max_rows,run),b=await measure(targetClient,p.max_rows,run);if(a.bytes+b.bytes>32768)fail('data_bound_refused');
  const source=await scan(sourceClient,p.max_rows,a.counts,run),target=await scan(targetClient,p.max_rows,b.counts,run),ss=summarize(source,p.source),ts=summarize(target,p.target);
  const result={format:FORMAT,status:'aggregate_observation',plan_sha256:expectedPlanSha256,source_set_sha256:p.source_set_sha256,owner_decision:'same_person_keep_cloud_primary',
   source:ss.counts,target:ts.counts,conflicts:cross(ss,ts,source,target,p.source,p.target),email_is_identity_proof:false,other_identity_mappings_inferred:false,
   historical_references_verified:false,provider_or_device_state_verified:false,quiescence_proven:false,write_authorized:false};
  for(const [i,c] of clients.entries()){const r=await run(c,"SELECT pg_catalog.pg_backend_pid()::text AS pid,pg_catalog.pg_current_xact_id()::text AS xid,current_setting('transaction_read_only') AS ro,current_setting('transaction_isolation') AS isolation");if(r.rows?.length!==1||r.rows[0].pid!==pids[i]||r.rows[0].xid!==txids[i]||r.rows[0].ro!=='on'||r.rows[0].isolation!=='repeatable read')fail('transaction_refused');const x=await run(c,'ROLLBACK');if(x.command!=='ROLLBACK')fail('transaction_refused');}
  return result;
 }catch(e){if(trusted(e))throw e;fail('preflight_refused');}
 finally{if(admitted){for(const c of [sourceClient,targetClient]){destroy(c);active.delete(c);}for(const c of [sourceClient,targetClient])try{void c.end().catch(()=>{});}catch{}}}
}
