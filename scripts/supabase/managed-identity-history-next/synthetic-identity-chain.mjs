// TEST ONLY. No managed host, credentials, external client, network or write
// dispatcher is accepted. All calls use an owned socket-only PG17 cluster.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {withOwnedIdentityFixture} from './synthetic-identity-fixture.mjs';
import {pinnedArchiveSource} from '../managed-migration-next/synthetic-archive.mjs';
const ROOT=resolve(import.meta.dirname,'../../..');
const IDENT='916a7b3012135484c74f0a6b4707cdda39c637959f8564233fc8f6a8f5adbdc1';
const ARCHIVE='82b09d4d2abd5994429a978ccf80daa796fd83e5dc5d29bc54076f2b7565ad84';
const hash=x=>createHash('sha256').update(x).digest('hex');
const need=(ok,code)=>{if(!ok)throw Error(code);};
const target={version:'20261101013157',name:'collect_deployment_identity',sha:IDENT};
const archive={version:'20261101012309',name:'collect_admission_archive',sha:ARCHIVE};
function identitySource(bytes){
 need(Buffer.isBuffer(bytes)&&bytes.length<1024*1024&&hash(bytes)===IDENT,'IDENTITY_SOURCE_CHANGED');
 const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes),start='\nBEGIN;\n',end='\nCOMMIT;\n',i=text.indexOf(start);
 need(i>=0&&text.indexOf(start,i+1)<0&&text.endsWith(end)&&text.indexOf(end)===text.length-end.length,'IDENTITY_FRAMING_CHANGED');
 return {text,body:text.slice(0,i+1)+text.slice(i+start.length,-end.length)+'\n'};
}
const histSql=`SELECT version,name,cardinality(statements)::int count,encode(sha256(convert_to(statements[1],'UTF8')),'hex') sha FROM supabase_migrations.schema_migrations ORDER BY version`;
const expectedHistory=(ctx,n)=>[...ctx.executed.map(x=>({version:x.version,name:x.name,count:1,sha:x.sha256})),...(n>=17?[{...archive,count:1}]:[]),...(n>=18?[{...target,count:1}]:[])].map(({version,name,count,sha})=>({version,name,count,sha}));
async function history(ctx,n){const h=(await ctx.owner.query(histSql)).rows;need(JSON.stringify(h)===JSON.stringify(expectedHistory(ctx,n)),'IDENTITY_HISTORY_MISMATCH');}
async function tx(c,fn){await c.query('BEGIN ISOLATION LEVEL READ COMMITTED READ WRITE');try{const r=await fn();await c.query('COMMIT');return r;}catch(e){try{await c.query('ROLLBACK');}catch{}throw e;}}
async function locks(ctx){
 const c=ctx.owner;await c.query("SET LOCAL search_path=pg_catalog,pg_temp; SET LOCAL timezone='UTC'; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='60s'");
 await c.query('SELECT pg_advisory_xact_lock(7346371,11)');await c.query('LOCK TABLE supabase_migrations.schema_migrations IN ACCESS EXCLUSIVE MODE');
 await c.query('SELECT pg_advisory_xact_lock(7346371,1)');await c.query('SELECT pg_advisory_xact_lock(7346371,2)');
 await c.query(`LOCK TABLE private.collect_fence_control,private.collect_fence_admissions,private.collect_fence_operations,
  private.collect_fence_stopped_admissions,private.collect_fence_source_upgrades,private.collect_fence_scheduler_lifecycle IN SHARE ROW EXCLUSIVE MODE`);
 const i=(await c.query(`SELECT current_database() d,session_user s,current_user u,current_setting('transaction_isolation') iso,current_setting('transaction_read_only') ro,
  current_setting('cluster_name') cluster,inet_server_addr() IS NULL sock,pg_backend_pid() pid,current_setting('server_version_num')::int/10000 major`)).rows[0];
 need(i.d==='postgres'&&i.s==='postgres'&&i.u==='postgres'&&i.iso==='read committed'&&i.ro==='off'&&i.sock&&i.cluster==='collect_identity_next_fixture'&&i.pid===ctx.backendPid&&i.major===17,'OWNED_SESSION_CHANGED');
}
const catalogSql=`SELECT jsonb_build_object(
 'relations',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.name),'[]') FROM (SELECT c.oid::regclass::text name,c.oid::text oid,c.relkind::text kind,c.relowner::text owner,c.relrowsecurity rls,c.relforcerowsecurity forced,coalesce(c.relacl::text,'') acl,
  coalesce((SELECT jsonb_agg(jsonb_build_array(a.attnum,a.attname,a.atttypid::text,a.atttypmod,a.attnotnull,a.attisdropped,coalesce(a.attacl::text,''),coalesce(pg_get_expr(d.adbin,d.adrelid),'')) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0),'[]') columns,
  coalesce((SELECT jsonb_agg(jsonb_build_array(k.conname,pg_get_constraintdef(k.oid)) ORDER BY k.conname) FROM pg_constraint k WHERE k.conrelid=c.oid),'[]') constraints,
  coalesce((SELECT jsonb_agg(jsonb_build_array(t.tgname,t.tgenabled::text,pg_get_triggerdef(t.oid)) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),'[]') triggers
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('private','supabase_migrations')) q),
 'functions',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.sig),'[]') FROM (SELECT p.oid::regprocedure::text sig,p.proowner::text owner,p.prosecdef sec,p.provolatile::text vol,coalesce(p.proconfig::text,'') config,coalesce(p.proacl::text,'') acl,encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex') def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('private','supabase_migrations') AND p.prokind='f') q),
 'roles',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.oid),'[]') FROM (SELECT oid::text oid,rolname,rolsuper,rolinherit,rolcanlogin,rolcreaterole,rolcreatedb,rolreplication,rolbypassrls FROM pg_roles) q),
 'members',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.roleid,q.member,q.grantor),'[]') FROM (SELECT roleid::text roleid,member::text member,grantor::text grantor,admin_option,inherit_option,set_option FROM pg_auth_members) q),
 'events',(SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.name),'[]') FROM (SELECT evtname name,evtevent event,evtenabled::text enabled,evtfoid::regprocedure::text fn FROM pg_event_trigger) q)) value`;
async function inspect(ctx){
 const c=ctx.owner;await locks(ctx);await history(ctx,17);
 const result=(await c.query(`SELECT to_regclass('private.collect_deployment_identity') IS NULL absent,to_regprocedure('private.collect_bind_deployment(uuid,text,text)') IS NULL binder_absent,
  (SELECT to_jsonb(x) FROM private.collect_fence_control x WHERE singleton) control,
  (SELECT count(*)::int FROM private.collect_fence_admissions) admissions`)).rows[0];
 need(result.absent&&result.binder_absent&&result.control?.mode==='fenced'&&result.control.project_ref==='rrlduytparvsjfmegalh'&&result.admissions<=10000,'IDENTITY_PREDECESSOR_REFUSED');
 const catalog=(await c.query(catalogSql)).rows[0].value;need(catalog.events.length===0,'SYNTHETIC_EVENT_TRIGGER_REFUSED');
 const rows=(await c.query(`SELECT jsonb_build_object('control',(SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') FROM private.collect_fence_control x),
  'admissions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY admission_id),'[]') FROM private.collect_fence_admissions x),
  'stopped',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY admission_id),'[]') FROM private.collect_fence_stopped_admissions x),
  'working',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY admission_id),'[]') FROM private.collect_fence_working_admissions x),
  'archive',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY admission_id),'[]') FROM private.collect_fence_admission_archive x),
  'totals',(SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') FROM private.collect_fence_admission_totals x)) value`)).rows[0].value;
 return hash(JSON.stringify({catalog,rows}));
}
async function post(ctx,n){
 const c=ctx.owner;await history(ctx,n);
 const r=(await c.query(`SELECT c.relkind='r' AND c.relrowsecurity AND NOT c.relforcerowsecurity AND pg_get_userbyid(c.relowner)='postgres'
  AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE a.grantee<>c.relowner) table_ok,
  (SELECT count(*) FROM private.collect_deployment_identity)=0 empty,
  (SELECT count(*)=1 FROM pg_trigger WHERE tgrelid=c.oid AND NOT tgisinternal AND tgname='collect_deployment_immutable' AND tgenabled='A' AND tgtype=58) trigger_ok,
  encode(sha256(convert_to((SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'notnull',a.attnotnull,'identity',a.attidentity::text,'generated',a.attgenerated::text,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum)::text FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'UTF8')),'hex') cols,
  encode(sha256(convert_to((SELECT jsonb_agg(jsonb_build_object('name',x.conname,'kind',x.contype::text,'definition',pg_get_constraintdef(x.oid),'deferrable',x.condeferrable,'deferred',x.condeferred,'valid',x.convalidated) ORDER BY x.conname)::text FROM pg_constraint x WHERE x.conrelid=c.oid),'UTF8')),'hex') constraints
  FROM pg_class c WHERE c.oid='private.collect_deployment_identity'::regclass`)).rows[0];
 need(r?.table_ok&&r.empty&&r.trigger_ok&&r.cols==='fbd3b36e805d6a2b872a7af68f0eb6bab0675ed1fd36367d95a8969f3af44db0'&&r.constraints==='0b89609c2964471a3f544fe09529155b70992c437e62e1477ce7eb20992d913e','IDENTITY_POSTCONDITION_FAILED');
 const f=(await c.query(`SELECT p.proname,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') sha,pg_get_userbyid(p.proowner) owner,p.prosecdef sec,p.provolatile::text vol,p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[] cfg
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN('_collect_deployment_immutable','collect_assert_deployment','collect_bind_deployment')`)).rows;
 need(f.length===3&&f.every(x=>x.owner==='postgres'&&x.cfg)&&f.find(x=>x.proname==='_collect_deployment_immutable')?.sha==='d210d7cb56bf315f01f48feb31ce1b3e77b0fdc32bffec5c90acfae22ff7878f'&&f.find(x=>x.proname==='collect_assert_deployment')?.sha==='94dd79ac9e0dabb5a5a02057515124e54eba66cf04e3ce2da6f7f0027df88fbd','IDENTITY_FUNCTION_POSTCONDITION_FAILED');
 return hash(JSON.stringify((await c.query(catalogSql)).rows[0].value));
}
export async function withSyntheticIdentityChain(run){
 const identity=identitySource(await readFile(resolve(ROOT,'supabase/migrations/20261101013157_collect_deployment_identity.sql')));
 const arch=pinnedArchiveSource(await readFile(resolve(ROOT,'supabase/migrations/20261101012309_collect_admission_archive.sql')));
 return withOwnedIdentityFixture(async ctx=>{
  const c=ctx.owner;
  const installArchive=()=>tx(c,async()=>{await locks(ctx);await history(ctx,16);await c.query(arch.body);await c.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[archive.version,archive.name,[arch.text]]);await history(ctx,17);return {syntheticOnly:true};});
  const capture=()=>tx(c,async()=>({sha256:await inspect(ctx),syntheticOnly:true}));
  const apply=({expectedPreimageSha256,fault='none'}={})=>{
   need(/^[a-f0-9]{64}$/.test(expectedPreimageSha256??'')&&['none','after-body','after-history'].includes(fault),'IDENTITY_INPUT_REFUSED');
   return tx(c,async()=>{need(await inspect(ctx)===expectedPreimageSha256,'IDENTITY_PREIMAGE_CHANGED');await c.query(identity.body);const fingerprint=await post(ctx,17);
    if(fault==='after-body')throw Error('SYNTHETIC_IDENTITY_FAIL_AFTER_BODY');
    await c.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[target.version,target.name,[identity.text]]);
    need(await post(ctx,18)===fingerprint,'IDENTITY_POST_HISTORY_CATALOG_CHANGED');
    if(fault==='after-history')throw Error('SYNTHETIC_IDENTITY_FAIL_AFTER_HISTORY');
    return {status:'synthetic_identity_committed',sourceSha256:IDENT,productionDispatch:false};});
  };
  return run(Object.freeze({...ctx,installArchive,capture,apply}));
 });
}
