// Exact archive migration engine. The managed apply gate remains closed until
// an independently reviewed post-16 plan and external exclusion are bound.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pinnedMigrationIdentities} from '../atomic_cloud_migration.mjs';
import {isManagedReconciliationPeer} from '../current-pg-transfer/managed-target.mjs';
import {isSyntheticReconciliationSocket} from '../current-pg-transfer/reconcile.mjs';
const PATH=resolve(import.meta.dirname,'../../../supabase/migrations/20261101012309_collect_admission_archive.sql');
const VERSION='20261101012309', NAME='collect_admission_archive';
const SHA='82b09d4d2abd5994429a978ccf80daa796fd83e5dc5d29bc54076f2b7565ad84';
const MAX_JSON_BYTES=8*1024*1024;
const hash=x=>createHash('sha256').update(x).digest('hex');
const need=(ok,code)=>{if(!ok)throw Object.assign(Error(code),{archiveCode:code});};
const own=(obj,key)=>Object.prototype.hasOwnProperty.call(obj,key);
// Keep PostgreSQL's JSONB text exact. Parsing arbitrary JSON numbers through
// JavaScript Number could collapse two distinct bigint/numeric values.
const boundedJson=sql=>`WITH bounded AS MATERIALIZED (${sql}) SELECT CASE WHEN pg_catalog.octet_length(value::text)<=${MAX_JSON_BYTES} THEN value::text ELSE NULL END value FROM bounded`;
function pinnedArchiveSource(bytes){
 need(Buffer.isBuffer(bytes)&&bytes.length<1024*1024&&hash(bytes)===SHA,'ARCHIVE_SOURCE_CHANGED');
 const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes),start='\nBEGIN;\n',end='\nCOMMIT;\n',pos=text.indexOf(start);
 need(pos>=0&&text.indexOf(start,pos+1)<0&&text.endsWith(end)&&text.indexOf(end)===text.length-end.length,'ARCHIVE_FRAMING_CHANGED');
 return {text,body:text.slice(0,pos+1)+text.slice(pos+start.length,-end.length)+'\n'};
}
// No magic caller assertion can open the managed apply path in these bytes.
export const MANAGED_REVIEWED_APPLY_PLAN_SHA256=null;
function targetRoutineHashes(text){
 const names=['_collect_archive_guard','_collect_working_guard','_collect_archive_totals_guard','_collect_archive_recorded',
  '_collect_admission_archive_track','_collect_fence_resources','collect_fence_archive_settled_v4','collect_fence_archive_status_v4',
  'collect_fence_release_v3','_collect_fence_upgrade_insert'];
 return Object.fromEntries(names.map(name=>{
  const match=new RegExp('CREATE (?:OR REPLACE )?FUNCTION private\\.'+name+'\\([\\s\\S]*?\\) RETURNS [\\s\\S]*? AS \\$fn\\$([\\s\\S]*?)\\$fn\\$;').exec(text);
  need(match,'ROUTINE_SOURCE_NOT_FOUND');return [name,hash(match[1])];
 }));
}
const catalogSql=`SELECT jsonb_build_object(
 'schemas',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.n),'[]') FROM (SELECT nspname n,nspowner::text owner,coalesce(nspacl::text,'') acl FROM pg_namespace WHERE nspname IN('app','private','auth','supabase_migrations')) q),
 'relations',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.n,q.r),'[]') FROM (
  SELECT n.nspname n,c.relname r,c.oid::text oid,c.relkind::text k,c.relowner::text owner,c.relrowsecurity rls,c.relforcerowsecurity forced,
   c.relpersistence::text persistence,c.relreplident::text replident,coalesce(c.reloptions::text,'') options,coalesce(c.relacl::text,'') acl,
   coalesce((SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,a.atttypid::text,a.atttypmod,a.attnotnull,a.attisdropped,a.attidentity::text,a.attgenerated::text,coalesce(a.attacl::text,''),coalesce(pg_get_expr(d.adbin,d.adrelid),'')) ORDER BY a.attnum)
    FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0),'[]') cols,
   coalesce((SELECT jsonb_agg(jsonb_build_array(k.conname,k.contype::text,k.convalidated,pg_get_constraintdef(k.oid)) ORDER BY k.conname) FROM pg_constraint k WHERE k.conrelid=c.oid),'[]') constraints,
   coalesce((SELECT jsonb_agg(jsonb_build_array(i.indexrelid::regclass::text,pg_get_indexdef(i.indexrelid),i.indisvalid,i.indisready) ORDER BY i.indexrelid::regclass::text) FROM pg_index i WHERE i.indrelid=c.oid),'[]') indexes,
   coalesce((SELECT jsonb_agg(jsonb_build_array(t.tgname,t.tgenabled::text,pg_get_triggerdef(t.oid)) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),'[]') triggers,
   coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.policyname) FROM pg_policies p WHERE p.schemaname=n.nspname AND p.tablename=c.relname),'[]') policies
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('app','private','auth','supabase_migrations')) q),
 'routines',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.sig),'[]') FROM (
  SELECT p.oid::regprocedure::text sig,p.oid::text oid,p.proowner::text owner,p.prosecdef sec,p.provolatile::text volatility,
   coalesce(p.proconfig::text,'') config,coalesce(p.proacl::text,'') acl,encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex') def
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('app','private','auth','supabase_migrations') AND p.prokind='f') q),
 'roles',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.oid),'[]') FROM (SELECT oid::text oid,rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls FROM pg_roles) q),
 'members',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.roleid,q.member,q.grantor),'[]') FROM (SELECT roleid::text roleid,member::text member,grantor::text grantor,admin_option,inherit_option,set_option FROM pg_auth_members) q),
 'default_acl',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.role,q.ns,q.kind),'[]') FROM (SELECT defaclrole::text role,defaclnamespace::text ns,defaclobjtype::text kind,defaclacl::text acl FROM pg_default_acl) q),
 'event_triggers',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.name),'[]') FROM (SELECT e.evtname name,e.evtevent event,e.evtenabled::text enabled,e.evtowner::text owner,e.evttags::text tags,e.evtfoid::regprocedure::text handler,encode(sha256(convert_to(pg_get_functiondef(e.evtfoid),'UTF8')),'hex') def FROM pg_event_trigger e) q)) AS value`;

async function rowsDigest(c){
 const bounded=(await c.query(`SELECT count(*)::int n,
  coalesce(sum(octet_length(to_jsonb(a)::text)),0)::bigint::text bytes,
  coalesce(max(octet_length(to_jsonb(a)::text)),0)::int largest
  FROM private.collect_fence_admissions a`)).rows[0];
 const count=bounded.n;
 need(count<=10000&&Number(bounded.bytes)<=MAX_JSON_BYTES&&bounded.largest<=32768,'ADMISSION_CAP');
 const sha=(await c.query(`SELECT encode(sha256(convert_to(coalesce(jsonb_agg(to_jsonb(a) ORDER BY admission_id),'[]')::text,'UTF8')),'hex') sha FROM private.collect_fence_admissions a`)).rows[0].sha;
 return {count,sha};
}
async function lockSession(ctx){
 const {owner:c,database,backendPid,mode}=ctx;
 await c.query("SET LOCAL search_path=pg_catalog,pg_temp; SET LOCAL timezone='UTC'; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='60s'; SET LOCAL row_security=off");
 await c.query('SELECT pg_advisory_xact_lock(7346371,11)');
 await c.query('LOCK TABLE supabase_migrations.schema_migrations IN ACCESS EXCLUSIVE MODE');
 await c.query('SELECT pg_advisory_xact_lock(7346371,1)');
 await c.query('SELECT pg_advisory_xact_lock(7346371,2)');
 await c.query(`LOCK TABLE private.collect_fence_control,private.collect_fence_admissions,private.collect_fence_operations,
  private.collect_fence_source_upgrades,private.collect_fence_scheduler_lifecycle,private.collect_fence_stopped_admissions IN SHARE ROW EXCLUSIVE MODE`);
 // READ COMMITTED takes a new statement snapshot after every lock has been
 // acquired. This is deliberately not a REPEATABLE READ transaction.
 const id=(await c.query(`SELECT current_database() d,session_user s,current_user u,current_setting('transaction_isolation') iso,
  current_setting('transaction_read_only') ro,current_setting('cluster_name') cluster,inet_server_addr() IS NULL socket,pg_backend_pid() pid,
  current_setting('server_version_num')::int/10000 major`)).rows[0];
 need(id.d===database&&id.s==='postgres'&&id.u==='postgres'&&id.iso==='read committed'&&id.ro===(ctx.readOnly?'on':'off')&&
  (mode==='synthetic'?(id.cluster==='collect_archive_next_fixture'&&id.socket):(id.d==='postgres'&&!id.socket))&&id.pid===backendPid&&id.major===17,'OWNED_SESSION_CHANGED');
 const names=['supabase_migrations.schema_migrations','private.collect_fence_control','private.collect_fence_admissions',
  'private.collect_fence_operations','private.collect_fence_source_upgrades','private.collect_fence_scheduler_lifecycle','private.collect_fence_stopped_admissions'];
 const visibility=(await c.query(`WITH named AS (SELECT name,to_regclass(name) oid FROM unnest($1::text[]) name)
  SELECT count(*)::int n,count(*) FILTER(WHERE r.oid IS NOT NULL AND c.relkind='r'
   AND has_schema_privilege(current_user,c.relnamespace,'USAGE') AND has_table_privilege(current_user,r.oid,'SELECT')
   AND NOT row_security_active(r.oid) AND NOT EXISTS(SELECT 1 FROM pg_inherits i WHERE i.inhrelid=r.oid OR i.inhparent=r.oid))::int safe
  FROM named r LEFT JOIN pg_class c ON c.oid=r.oid`,[names])).rows[0];
 need(visibility?.n===names.length&&visibility.safe===names.length,'VISIBILITY_REFUSED');
}
async function lockAndInspect(ctx){
 const {owner:c,executed,mode}=ctx;
 await lockSession(ctx);
 const history=(await c.query(`SELECT version,name,cardinality(statements) count,encode(sha256(convert_to(statements[1],'UTF8')),'hex') sha FROM supabase_migrations.schema_migrations ORDER BY version`)).rows;
 need(history.length===16&&history.every((x,i)=>x.version===executed[i].version&&x.name===executed[i].name&&Number(x.count)===1&&x.sha===executed[i].sha256),'SYNTHETIC_HISTORY_MISMATCH');
 const control=(await c.query("SELECT mode,project_ref FROM private.collect_fence_control WHERE singleton")).rows;
 need(control.length===1&&control[0].mode==='fenced'&&control[0].project_ref==='rrlduytparvsjfmegalh','SYNTHETIC_FENCE_NOT_FENCED');
 const absent=(await c.query(`SELECT to_regclass('private.collect_fence_working_admissions') IS NULL AND to_regclass('private.collect_fence_admission_archive') IS NULL AND to_regclass('private.collect_fence_admission_totals') IS NULL ok`)).rows[0].ok;
 need(absent,'ARCHIVE_OBJECT_ALREADY_PRESENT');
 const catalog=(await c.query(boundedJson(catalogSql))).rows[0].value;need(catalog!==null,'CATALOG_TOO_LARGE');
 if(mode==='synthetic')need((await c.query('SELECT count(*)::int n FROM pg_event_trigger')).rows[0]?.n===0,'UNREVIEWED_EVENT_TRIGGER');
 const admissions=await rowsDigest(c);
 const limits=(await c.query(`SELECT (SELECT count(*) FROM private.collect_fence_operations)<=10000
  AND (SELECT count(*) FROM private.collect_fence_source_upgrades)<=10000
  AND (SELECT count(*) FROM private.collect_fence_stopped_admissions)<=10000
  AND (SELECT count(*) FROM private.collect_fence_scheduler_lifecycle)<=10000 ok`)).rows[0].ok;
 need(limits,'SYNTHETIC_FENCE_DATA_CAP');
 const fence=(await c.query(boundedJson(`SELECT jsonb_build_object('control',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY singleton),'[]') FROM private.collect_fence_control x),
  'operations',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY operation_id,action),'[]') FROM private.collect_fence_operations x),
  'stopped',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY admission_id),'[]') FROM private.collect_fence_stopped_admissions x),
  'upgrades',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY operation_id),'[]') FROM private.collect_fence_source_upgrades x),
  'scheduler',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY dispatch_id),'[]') FROM private.collect_fence_scheduler_lifecycle x)) value`))).rows[0].value;need(fence!==null,'FENCE_TOO_LARGE');
 const value={format:'collect.archive-preimage.v2',history,catalog_json:catalog,admissions,fence_json:fence};
 const serialized=JSON.stringify(value);
 need(Buffer.byteLength(serialized)<=2*MAX_JSON_BYTES+65536,'PREIMAGE_TOO_LARGE');
 return {sha256:hash(serialized),admissions,preimage:value};
}

async function verifyPost(ctx,source,before,historyExpected){
 const c=ctx.owner,checks=(await c.query(`SELECT count(*)::int tables,
  count(*) FILTER(WHERE c.relkind='r' AND c.relrowsecurity AND NOT c.relforcerowsecurity AND pg_get_userbyid(c.relowner)='postgres'
   AND NOT has_table_privilege('collect_runtime',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
   AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE a.grantee<>c.relowner))::int safe
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private' AND c.relname=ANY($1::text[])`,[['collect_fence_working_admissions','collect_fence_admission_archive','collect_fence_admission_totals']])).rows[0];
 need(checks.tables===3&&checks.safe===3,'POST_TABLE_CONTRACT_FAILED');
 const triggers=(await c.query(`SELECT t.tgname,t.tgenabled::text enabled FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='private' AND NOT t.tgisinternal AND t.tgname=ANY($1::text[]) ORDER BY t.tgname`,[['collect_archive_guard','collect_archive_immutable','collect_working_guard','collect_working_no_truncate','collect_archive_totals_guard','collect_archive_totals_no_truncate','collect_archive_recorded','collect_admission_archive_track']])).rows;
 need(triggers.length===8&&triggers.every(x=>x.enabled==='A'),'POST_TRIGGER_CONTRACT_FAILED');
 const expected=targetRoutineHashes(source),fns=(await c.query(`SELECT p.proname,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') sha,
  pg_get_userbyid(p.proowner) owner,p.prosecdef sec,p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[] config,
  has_function_privilege('collect_runtime',p.oid,'EXECUTE') runtime,
  EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee<>p.proowner AND a.privilege_type='EXECUTE') outsider
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname=ANY($1::text[])`,[Object.keys(expected)])).rows;
 need(fns.length===10&&new Set(fns.map(x=>x.proname)).size===10&&
  fns.every(x=>own(expected,x.proname)&&x.sha===expected[x.proname]&&x.owner==='postgres'&&x.sec&&x.config),'POST_ROUTINE_CONTRACT_FAILED');
 const newFns=new Set(['_collect_archive_guard','_collect_working_guard','_collect_archive_totals_guard','_collect_archive_recorded','_collect_admission_archive_track','collect_fence_archive_settled_v4','collect_fence_archive_status_v4']);
 need(fns.filter(x=>newFns.has(x.proname)).every(x=>!x.runtime&&!x.outsider),'POST_ROUTINE_PRIVILEGE_FAILED');
 const rows=await rowsDigest(c);need(JSON.stringify(rows)===JSON.stringify(before),'POST_ADMISSIONS_CHANGED');
 const state=(await c.query(`SELECT (SELECT count(*) FROM private.collect_fence_working_admissions)::int working,
  (SELECT count(*) FROM private.collect_fence_admission_archive)::int archived,
  (SELECT retained_total FROM private.collect_fence_admission_totals WHERE singleton)::int retained,
  (SELECT archived_total FROM private.collect_fence_admission_totals WHERE singleton)::int archived_total,
  NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions a FULL JOIN private.collect_fence_working_admissions w USING(admission_id) WHERE a.admission_id IS NULL OR w.admission_id IS NULL) maps`)).rows[0];
 need(state.working===before.count&&state.retained===before.count&&state.archived===0&&state.archived_total===0&&state.maps,'POST_BACKFILL_FAILED');
 const history=(await c.query(`SELECT version,name,cardinality(statements)::int count,
  encode(sha256(convert_to(statements[1],'UTF8')),'hex') sha FROM supabase_migrations.schema_migrations ORDER BY version`)).rows;
 const expectedHistory=ctx.executed.map(x=>({version:x.version,name:x.name,count:1,sha:x.sha256}));
 if(historyExpected===17)expectedHistory.push({version:VERSION,name:NAME,count:1,sha:SHA});
 need(historyExpected===expectedHistory.length&&JSON.stringify(history)===JSON.stringify(expectedHistory),'POST_HISTORY_CONTENT_FAILED');
 const catalog=(await c.query(boundedJson(catalogSql))).rows[0].value;
 need(catalog!==null,'POST_CATALOG_TOO_LARGE');return hash(JSON.stringify(catalog));
}


function clientGuard(ctx){
 const c=ctx?.client;need(c&&typeof c.query==='function'&&c.connection?.once&&c.connection?.removeListener&&c.connection?.stream?.destroy,'CLIENT_REFUSED');
 need(['synthetic','managed'].includes(ctx.mode),'MODE_REFUSED');
 if(ctx.mode==='managed')need(isManagedReconciliationPeer(c.connectionParameters,c.connection.stream),'MANAGED_TRANSPORT_REFUSED');
 else need(isSyntheticReconciliationSocket(c.connectionParameters?.host),'FIXTURE_SOCKET_REFUSED');
}
function boundedClient(client,deadline){
 return {async query(...args){
  const remaining=deadline-Date.now();if(remaining<=0){client.connection.stream.destroy();need(false,'QUERY_TIMEOUT_UNKNOWN');}
  let timer;try{return await Promise.race([Promise.resolve().then(()=>client.query(...args)),new Promise((_,reject)=>{timer=setTimeout(()=>{client.connection.stream.destroy();reject(Object.assign(Error('QUERY_TIMEOUT_UNKNOWN'),{archiveCode:'QUERY_TIMEOUT_UNKNOWN'}));},Math.min(65000,remaining));})]);}
  finally{clearTimeout(timer);}
 }};
}
async function idle(c,q){
 let listener;try{
  const ready=new Promise(resolve=>{listener=x=>resolve(x?.status);c.connection.once('readyForQuery',listener);});
  const [probe,status]=await Promise.all([q.query('SELECT 1 AS ok,pg_catalog.pg_backend_pid() AS pid'),ready]);
  need(status==='I'&&probe.rows?.length===1&&probe.rows[0].ok===1&&Number.isSafeInteger(probe.rows[0].pid)&&probe.rows[0].pid>0,'CLIENT_NOT_IDLE');
  return probe.rows[0].pid;
 }finally{if(listener)c.connection.removeListener('readyForQuery',listener);}
}
function expectation(ctx){
 if(ctx.mode==='managed')return pinnedMigrationIdentities();
 need(Array.isArray(ctx.executed)&&ctx.executed.length===16&&typeof ctx.database==='string'&&/^collect_archive_[a-f0-9]{24}_test$/.test(ctx.database),'FIXTURE_CONTEXT_REFUSED');
 return ctx.executed;
}
async function startContext(ctx,readOnly){
 clientGuard(ctx);need(Number.isSafeInteger(ctx.timeoutMs)&&ctx.timeoutMs>=1000&&ctx.timeoutMs<=120000,'TIMEOUT_REFUSED');
 const q=boundedClient(ctx.client,Date.now()+ctx.timeoutMs),pid=await idle(ctx.client,q),executed=expectation(ctx);
 if(ctx.backendPid!==undefined)need(pid===ctx.backendPid,'BACKEND_CHANGED');
 if(ctx.mode==='synthetic')need(Number.isSafeInteger(ctx.backendPid),'BACKEND_CHANGED');
 const inner={owner:q,database:ctx.mode==='managed'?'postgres':ctx.database,backendPid:pid,executed,mode:ctx.mode,readOnly};
 return {q,inner,pid};
}
export async function reconcileArchive(ctx,{priorBackendPid,expectedAdmissions}={}){
 need(Number.isSafeInteger(priorBackendPid)&&priorBackendPid>0&&expectedAdmissions&&
  Number.isSafeInteger(expectedAdmissions.count)&&expectedAdmissions.count>=0&&expectedAdmissions.count<=10000&&
  /^[a-f0-9]{64}$/.test(expectedAdmissions.sha??''),'RECONCILE_INPUT_REFUSED');
 const source=pinnedArchiveSource(await readFile(PATH)),{q,inner,pid}=await startContext(ctx,true);let begun=false;
 try{
  need(pid!==priorBackendPid,'PRIOR_BACKEND_STILL_PRESENT');
  const start=await q.query('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');begun=true;need(start.command==='BEGIN','BEGIN_UNKNOWN');
  await lockSession(inner);
  const gone=(await q.query('SELECT NOT EXISTS(SELECT 1 FROM pg_catalog.pg_stat_activity WHERE pid=$1) AS gone',[priorBackendPid])).rows[0]?.gone;
  need(gone===true,'PRIOR_BACKEND_STILL_PRESENT');
  const history=(await q.query(`SELECT version,name,cardinality(statements)::int count,
   encode(sha256(convert_to(statements[1],'UTF8')),'hex') sha FROM supabase_migrations.schema_migrations ORDER BY version`)).rows;
  const expected=inner.executed.map(x=>({version:x.version,name:x.name,count:1,sha:x.sha256}));
  let status;
  if(JSON.stringify(history)===JSON.stringify(expected)){
   const absent=(await q.query(`SELECT to_regclass('private.collect_fence_working_admissions') IS NULL AND
    to_regclass('private.collect_fence_admission_archive') IS NULL AND to_regclass('private.collect_fence_admission_totals') IS NULL ok`)).rows[0]?.ok;
   need(absent===true,'RECONCILIATION_INCONSISTENT');status='not_recorded_do_not_retry';
  }else{
   expected.push({version:VERSION,name:NAME,count:1,sha:SHA});
   need(JSON.stringify(history)===JSON.stringify(expected),'RECONCILIATION_INCONSISTENT');
   await verifyPost(inner,source.text,expectedAdmissions,17);status='recorded_selected_postconditions_verified';
  }
  need((await q.query('ROLLBACK')).command==='ROLLBACK','ROLLBACK_UNKNOWN');begun=false;return {status,writeAuthorized:false};
 }catch(e){if(begun)try{await q.query('ROLLBACK');}catch{}throw e;}
}
export async function captureArchivePreimage(ctx){
 pinnedArchiveSource(await readFile(PATH));
 const {q,inner}=await startContext(ctx,true);let begun=false;
 try{
  const start=await q.query('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');begun=true;need(start.command==='BEGIN','BEGIN_UNKNOWN');
  const seen=await lockAndInspect(inner);
  need((await q.query('ROLLBACK')).command==='ROLLBACK','ROLLBACK_UNKNOWN');begun=false;
  return {status:'preimage_captured',sha256:seen.sha256,preimage:seen.preimage,productionAuthorized:false};
 }catch(e){if(begun)try{await q.query('ROLLBACK');}catch{}throw e;}
}
export async function applyArchiveInTransaction(ctx,{expectedPreimageSha256,expectedAdmissions,reviewedPlanSha256,fault='none'}={}){
 if(ctx?.mode==='managed')need(MANAGED_REVIEWED_APPLY_PLAN_SHA256!==null&&reviewedPlanSha256===MANAGED_REVIEWED_APPLY_PLAN_SHA256,'MANAGED_APPLY_UNQUALIFIED');
 need(/^[a-f0-9]{64}$/.test(expectedPreimageSha256??'')&&expectedAdmissions&&
  Number.isSafeInteger(expectedAdmissions.count)&&expectedAdmissions.count>=0&&expectedAdmissions.count<=10000&&
  /^[a-f0-9]{64}$/.test(expectedAdmissions.sha??''),'PREIMAGE_REQUIRED');
 need(['none','after-body','after-history'].includes(fault)&&(ctx?.mode==='synthetic'||fault==='none'),'FAULT_REFUSED');
 const source=pinnedArchiveSource(await readFile(PATH)),{q,inner}=await startContext(ctx,false);let begun=false,commitSent=false;
 try{
  const start=await q.query('BEGIN ISOLATION LEVEL READ COMMITTED READ WRITE');begun=true;need(start.command==='BEGIN','BEGIN_UNKNOWN');
  const seen=await lockAndInspect(inner);need(seen.sha256===expectedPreimageSha256,'PREIMAGE_CHANGED');
  need(seen.admissions.count===expectedAdmissions.count&&seen.admissions.sha===expectedAdmissions.sha,'PREIMAGE_ADMISSIONS_CHANGED');
  await q.query(source.body);const postCatalog=await verifyPost(inner,source.text,seen.admissions,16);
  if(fault==='after-body')need(false,'SYNTHETIC_AFTER_BODY');
  await q.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[VERSION,NAME,[source.text]]);
  need(await verifyPost(inner,source.text,seen.admissions,17)===postCatalog,'POST_HISTORY_CATALOG_CHANGED');
  if(fault==='after-history')need(false,'SYNTHETIC_AFTER_HISTORY');
  commitSent=true;need((await q.query('COMMIT')).command==='COMMIT','COMMIT_UNKNOWN');begun=false;
  return {status:'committed',version:VERSION,sourceSha256:SHA,preimageSha256:seen.sha256};
 }catch(e){
  if(commitSent)throw Object.assign(Error('COMMIT_UNKNOWN'),{archiveCode:'COMMIT_UNKNOWN'});
  if(begun){try{need((await q.query('ROLLBACK')).command==='ROLLBACK','ROLLBACK_UNKNOWN');}catch{throw Object.assign(Error('ROLLBACK_UNKNOWN'),{archiveCode:'ROLLBACK_UNKNOWN'});}}
  throw e;
 }
}
export const archiveIdentity=Object.freeze({version:VERSION,name:NAME,sourceSha256:SHA});
