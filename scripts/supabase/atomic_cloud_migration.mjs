// Library-only, narrowly pinned migration primitive. This module neither opens a
// connection nor authorizes a deployment. The caller must exclusively own a
// fresh, TLS-verified direct or session-pooled pg Client and stop independent
// migration actors first. Backend identity is read from PostgreSQL itself.
// The original SQL is recorded in history; only its outer BEGIN/COMMIT are
// removed from the body executed inside this module's transaction.
import {createHash} from 'node:crypto';
import {open,realpath} from 'node:fs/promises';
import {constants} from 'node:fs';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {hasPinnedProviderSSL} from './managed-cloud-migrations/provider-ca.mjs';

const PROJECT='rrlduytparvsjfmegalh';
const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const entries=[
 ['20261020134444','collect_curated_platform_baseline','0d943d17ddd92e809856831427cfc81b1264301dabdb867e1c90322d46b5a6f0'],
 ['20261020135932','collect_runtime_role_and_function_paths','59e4b13ddc81abeb39fb59b005c71a29f947023502727c118c9eb00b479e08a1'],
 ['20261020174856','collect_retention_retry_authority','d3ba38736fa46b70a0bb66520deffa56fd6f7317deb7c0144f8e06d791f8808c'],
 ['20261020184012','collect_admin_invitation_attempts','c6dc8aa6ac5130162c6e69904aae7221edde6dcb0c898af2cf9e10dba444b665'],
 ['20261020190301','collect_rls_helper_permissions','dccb79af17182164dc6afe0b8339b70bd35a80fc4a1c1fa7df1a09408310a645'],
 ['20261020191847','collect_privacy_email_reauthentication','d6f002a6e904226a88e666c70937a142f06aa5a7e29874c6edb564d59c5fcab4'],
 ['20261020193752','collect_admin_invitation_access_notice_v2','b48a381169e777160a37396539248325e40b331a61db986622514724517f8467'],
 ['20261020195249','collect_admin_invitation_public_id_preservation','78f8c454a9825b0d9e25622b0659245d9568e7b95f637d3e20160a945b4e0850'],
 ['20261022195747','collect_application_mutation_fence','714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497'],
 ['20261022200028','collect_private_member_realtime','ebfd0389e6ba3aa5fe1595f854b25c69b9b31a0500f202b8e0643209ab0ef6e4'],
 ['20261023002500','collect_admin_recent_email_source_upgrade','02c93209f546880032cf38382c61e78a3de0b0073dd2cb88699319afc6f0f185'],
 ['20261023072038','collect_admin_initial_email_proof_ack','2c31440ae10176e7e9e5f0befefce8e1ca44e06149d3cc4471119920b3abf6df'],
 ['20261023102707','collect_retire_admin_mfa_enrollment','e11ee7110cc2eb3a8a6cf571532966711b6a9b737537b5b893c61d2b48d8e834'],
 ['20261023174000','collect_stopped_admission_lifecycle','db6f2f23ae1ae5a7de01d8145e84b0429717e73628443ff58054f29aab451e25'],
 ['20261029120000','collect_client_diagnostics','6f7c1e537a3c7d114417cfa79bd7b545bbfd17c69ab1d643c806eeb457c81e3f'],
 ['20261029130000','collect_notification_delivery','2d5904d5aaae917715c6ff5b996ce5b7395864fc5e225f5aaa67ec7d931a6792'],
].map(([version,name,sha256])=>Object.freeze({version,name,sha256}));
const BASELINE=14;
const activeClients=new WeakSet();
const discardClients=new WeakSet();
const CONTROL_TIMEOUT_MS=15000,BODY_TIMEOUT_MS=65000;
export class AtomicMigrationError extends Error {
 constructor(code){super(code);this.name='AtomicMigrationError';this.code=code;}
}
const fail=code=>{throw new AtomicMigrationError(code);};
export function pinnedMigrationIdentities(){return entries.map(x=>({...x}));}

// Pure lexical guard, not a general PostgreSQL parser. Only the exact pinned
// files can reach the executor. It rejects unclosed literals/comments, unknown
// top-level statements, and all transaction control inside the outer pair.
export function extractSupportedBody(sql){
 if(typeof sql!=='string'||!sql||sql.includes('\0')||/[^\x09\x0a\x0d\x20-\x7e]/.test(sql))fail('unsupported_sql');
 const statements=[];let start=0,i=0,tokens=[];
 while(i<sql.length){
  const c=sql[i],next=sql[i+1];
  if(c==='-'&&next==='-'){i+=2;while(i<sql.length&&sql[i]!=='\n')i++;continue;}
  if(c==='/'&&next==='*'){
   i+=2;let depth=1;while(i<sql.length&&depth){if(sql[i]==='/'&&sql[i+1]==='*'){depth++;i+=2;}else if(sql[i]==='*'&&sql[i+1]==='/'){depth--;i+=2;}else i++;}
   if(depth)fail('unsupported_sql');continue;
  }
  if(c==="'"||c==='"'){
   const quote=c,escaped=quote==="'"&&i>0&&/[eE]/.test(sql[i-1])&&(i<2||!/\w|\$/.test(sql[i-2]));
   i++;let closed=false;while(i<sql.length){if(escaped&&sql[i]==='\\'){i+=2;continue;}if(sql[i]===quote){if(sql[i+1]===quote){i+=2;continue;}i++;closed=true;break;}i++;}
   if(!closed)fail('unsupported_sql');continue;
  }
  if(c==='$'){
   const m=/^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i));
   if(!m)fail('unsupported_sql');const end=sql.indexOf(m[0],i+m[0].length);if(end<0)fail('unsupported_sql');
   // Conservatively reject procedural transaction and role control, even in
   // a comment or literal within a dollar body. The fixed hashes are the
   // separate control against concealed dynamic SQL or unreviewed bodies.
   const body=sql.slice(i+m[0].length,end);
   if(/\b(?:COMMIT|ROLLBACK|ABORT|START\s+TRANSACTION|PREPARE\s+TRANSACTION|SET\s+TRANSACTION|SET\s+ROLE|RESET\s+ROLE)\b/i.test(body))fail('unsupported_sql');
   i=end+m[0].length;continue;
  }
  if(/[A-Za-z_]/.test(c)){const m=/^[A-Za-z_][A-Za-z0-9_$]*/.exec(sql.slice(i));tokens.push(m[0].toUpperCase());i+=m[0].length;continue;}
  if(c===';'){if(!tokens.length)fail('unsupported_sql');statements.push({start,end:i+1,tokens});tokens=[];start=++i;continue;}
  i++;
 }
 if(tokens.length||statements.length<3)fail('unsupported_sql');
 const first=statements[0],last=statements.at(-1);
 if(first.tokens.join(' ')!=='BEGIN'||last.tokens.join(' ')!=='COMMIT')fail('unsupported_sql');
 const pairs=new Set(['CREATE TABLE','CREATE INDEX','CREATE FUNCTION','CREATE TRIGGER','CREATE POLICY','ALTER TABLE']);
 for(const s of statements.slice(1,-1))if(!pairs.has(s.tokens.slice(0,2).join(' '))&&!['REVOKE','GRANT','DO'].includes(s.tokens[0]))fail('unsupported_sql');
 return sql.slice(first.end,last.start);
}

function selected(version,expectedSha){
 const index=entries.findIndex(x=>x.version===version);
 if(index<BASELINE||index<0||entries[index].sha256!==expectedSha)fail('unapproved_migration_identity');
 return {entry:entries[index],index};
}
async function source(entry){
 const directory=join(ROOT,'supabase','migrations'),name=`${entry.version}_${entry.name}.sql`;
 let handle;
 try{
  const dir=await realpath(directory),path=join(dir,name);
  handle=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);
  const before=await handle.stat();if(!before.isFile()||before.size>1024*1024)fail('source_invalid');
  const bytes=await handle.readFile(),after=await handle.stat();
  if(before.dev!==after.dev||before.ino!==after.ino||before.size!==after.size||before.mtimeMs!==after.mtimeMs||
    createHash('sha256').update(bytes).digest('hex')!==entry.sha256)fail('source_mismatch');
  const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
  return {text,body:extractSupportedBody(text)};
 }catch(e){if(e instanceof AtomicMigrationError)throw e;fail('source_unavailable');}
 finally{await handle?.close().catch(()=>{});}
}

function validateConnection(client){
 const cp=client?.connectionParameters,stream=client?.connection?.stream;
 const host=cp?.host,user=cp?.user,port=Number(cp?.port);
 const direct=host===`db.${PROJECT}.supabase.co`&&port===5432&&user==='postgres';
 const pooler=host==='aws-0-eu-north-1.pooler.supabase.com'&&port===5432&&user===`postgres.${PROJECT}`;
 if(typeof client?.query!=='function'||!client.connection?.once||!client.connection?.removeListener||
   cp?.database!=='postgres'||(!direct&&!pooler)||!hasPinnedProviderSSL(cp.ssl)||
   stream?.encrypted!==true||stream.authorized!==true||stream.servername!==host||typeof stream.destroy!=='function')fail('unverified_database_connection');
}
function destroy(client){discardClients.add(client);try{client.connection.stream.destroy();}catch{/* Keep the outcome unconfirmed. */}}
async function query(client,sql,values,timeout=CONTROL_TIMEOUT_MS){
 let timer;
 try{return await Promise.race([
  Promise.resolve().then(()=>client.query(sql,values)),
  new Promise((_,reject)=>{timer=setTimeout(()=>reject(new AtomicMigrationError('query_timeout')),timeout);}),
 ]);}catch(error){if(error instanceof AtomicMigrationError&&error.code==='query_timeout')destroy(client);throw error;}
 finally{clearTimeout(timer);}
}
async function idleProbe(client){
 let timer,onReady;
 try{
  const ready=new Promise((resolve,reject)=>{onReady=msg=>resolve(msg?.status);client.connection.once('readyForQuery',onReady);timer=setTimeout(()=>reject(new Error()),5000);});
  const [result,status]=await Promise.all([query(client,'SELECT 1 AS collect_migration_idle_probe,pg_catalog.pg_backend_pid() AS backend_pid'),ready]);
  const pid=Number(result.rows?.[0]?.backend_pid);
  if(status!=='I'||result.rows?.[0]?.collect_migration_idle_probe!==1||!Number.isSafeInteger(pid)||pid<1)fail('connection_not_idle');
  return pid;
 }catch(e){destroy(client);if(e instanceof AtomicMigrationError)throw e;fail('connection_probe_failed');}
 finally{clearTimeout(timer);if(onReady)client.connection.removeListener('readyForQuery',onReady);}
}
const historySql=`SELECT version,name,pg_catalog.cardinality(statements) AS statement_count,
 pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(statements[1],'UTF8')),'hex') AS source_sha256
 FROM supabase_migrations.schema_migrations ORDER BY version`;
async function lockAndInspect(client,index,requireFenced,backendPid){
 await query(client,'SET LOCAL search_path=pg_catalog,pg_temp');
 await query(client,"SET LOCAL lock_timeout='5s'");
 await query(client,"SET LOCAL statement_timeout='60s'");
 await query(client,'SET LOCAL standard_conforming_strings=on');
 // Advisory lock coordinates this primitive; the table lock also blocks other
 // history readers/writers once acquired. Other migration actors must already
 // be stopped: a non-cooperating actor can start DDL before acquiring either.
 await query(client,'SELECT pg_catalog.pg_advisory_xact_lock(7346371,11)');
 await query(client,'LOCK TABLE supabase_migrations.schema_migrations IN ACCESS EXCLUSIVE MODE');
 const target=await query(client,`SELECT pg_catalog.current_database() AS database,pg_catalog.current_setting('server_version_num') AS server_version_num,pg_catalog.pg_backend_pid() AS backend_pid,
  session_user AS session_role,current_user AS active_role,project_ref,mode,source_sha256,epoch::text AS epoch,operation_id::text AS operation_id
  FROM private.collect_fence_control WHERE singleton=true FOR SHARE`);
 const row=target.rows?.[0];
 if(target.rows?.length!==1||row.database!=='postgres'||row.project_ref!==PROJECT||
   !/^17\d{4}$/.test(String(row.server_version_num))||!['open','quiescing','fenced'].includes(row.mode)||
   !/^[a-f0-9]{64}$/.test(row.source_sha256??'')||!/^[1-9][0-9]*$/.test(row.epoch??'')||
   !/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(row.operation_id??''))fail('target_identity_mismatch');
 if(row.session_role!=='postgres'||row.active_role!=='postgres')fail('unreviewed_database_role');
 if(Number(row.backend_pid)!==backendPid)fail('backend_changed');
 if(requireFenced&&row.mode!=='fenced')fail('target_not_fenced');
 const got=(await query(client,historySql)).rows;
 const compare=count=>got.length===count&&got.every((r,i)=>r.version===entries[i].version&&r.name===entries[i].name&&
  Number(r.statement_count)===1&&r.source_sha256===entries[i].sha256);
 if(compare(index))return {state:'not_recorded',target:row};
 if(compare(index+1))return {state:'recorded',target:row};
 fail('migration_history_mismatch');
}
// This is an exact, reviewable catalog preimage for the two allowed files;
// it is not a complete catalog audit or proof of data/backup readiness.
async function catalogPreimage(client,entry,index,target){
 const schemas=(await query(client,`SELECT n.nspname AS name,pg_catalog.pg_get_userbyid(n.nspowner) AS owner,coalesce(n.nspacl::text,'') AS acl
  FROM pg_catalog.pg_namespace n WHERE n.nspname IN ('app','private','supabase_migrations') ORDER BY n.nspname`)).rows;
 if(schemas.length!==3||schemas.some(s=>s.owner!=='postgres'))fail('unreviewed_schema_owner');
 const relations=(await query(client,`SELECT n.nspname AS schema,c.relname AS name,c.relkind::text AS kind,
  pg_catalog.pg_get_userbyid(c.relowner) AS owner,coalesce(c.relacl::text,'') AS acl,c.relrowsecurity::text AS rls,c.relforcerowsecurity::text AS forced,
  coalesce((SELECT pg_catalog.string_agg(a.attnum::text||':'||a.attname||':'||pg_catalog.format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull::text||':'||a.attidentity::text||':'||coalesce(pg_catalog.pg_get_expr(d.adbin,d.adrelid),''),',' ORDER BY a.attnum)
   FROM pg_catalog.pg_attribute a LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'') AS columns,
  coalesce((SELECT pg_catalog.string_agg(x.conname||':'||pg_catalog.pg_get_constraintdef(x.oid),E'\\n' ORDER BY x.conname)
   FROM pg_catalog.pg_constraint x WHERE x.conrelid=c.oid),'') AS constraints,
  coalesce((SELECT pg_catalog.string_agg(t.tgname||':'||t.tgenabled::text||':'||pg_catalog.pg_get_triggerdef(t.oid),E'\\n' ORDER BY t.tgname)
   FROM pg_catalog.pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),'') AS triggers,
  coalesce((SELECT pg_catalog.string_agg(p.policyname||':'||p.roles::text||':'||p.cmd||':'||coalesce(p.qual,'')||':'||coalesce(p.with_check,''),E'\\n' ORDER BY p.policyname)
   FROM pg_catalog.pg_policies p WHERE p.schemaname=n.nspname AND p.tablename=c.relname),'') AS policies,
  coalesce((SELECT pg_catalog.string_agg(ix.indexname||':'||ix.indexdef,E'\\n' ORDER BY ix.indexname)
   FROM pg_catalog.pg_indexes ix WHERE ix.schemaname=n.nspname AND ix.tablename=c.relname),'') AS indexes
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE (n.nspname='app' AND c.relname IN ('users','auth_sessions','notification_events','notification_devices','memberships','collections','notification_preferences','privacy_retention_barriers','client_diagnostic_reports','notification_deliveries'))
   OR (n.nspname='private' AND c.relname IN ('collect_fence_control','auth_principal_links'))
   OR (n.nspname='auth' AND c.relname IN ('users','sessions'))
   OR (n.nspname='supabase_migrations' AND c.relname='schema_migrations')
  ORDER BY n.nspname,c.relname`)).rows;
 const functions=(await query(client,`SELECT n.nspname AS schema,p.proname AS name,pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_catalog.pg_get_userbyid(p.proowner) AS owner,p.prosecdef::text AS security_definer,coalesce(p.proacl::text,'') AS acl,coalesce(p.proconfig::text,'') AS settings,
  pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_functiondef(p.oid),'UTF8')),'hex') AS definition_sha256
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE (n.nspname='app' AND p.proname='unixepoch') OR (n.nspname='private' AND p.proname IN ('_collect_fence_statement','notification_delivery_eligible','notification_delivery_guard'))
  ORDER BY n.nspname,p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid)`)).rows;
 const fence=functions.filter(f=>f.schema==='private'&&f.name==='_collect_fence_statement');
 const clocks=functions.filter(f=>f.schema==='app'&&f.name==='unixepoch');
 if(fence.length!==1||fence[0].owner!=='postgres'||fence[0].security_definer!=='true'||!clocks.length||clocks.some(f=>f.owner!=='postgres'))fail('unreviewed_function_owner');
 const targetTable=entry.version===entries[14].version?'client_diagnostic_reports':'notification_deliveries';
 if(relations.some(r=>r.schema==='app'&&r.name===targetTable))fail('preexisting_target_object');
 // A role outside the initially named application roles may receive a
 // default privilege or inherit one through an arbitrary membership chain.
 // Bind the entire non-secret role graph and every applicable default ACL;
 // these are review evidence, not evidence that their contents are safe.
 const roles=(await query(client,`SELECT r.oid::text AS oid,r.rolname AS name,r.rolsuper::text AS superuser,r.rolcanlogin::text AS login,
  r.rolbypassrls::text AS bypass_rls,r.rolinherit::text AS inherit,r.rolcreaterole::text AS create_role,
  r.rolcreatedb::text AS create_database,r.rolreplication::text AS replication
  FROM pg_catalog.pg_roles r ORDER BY r.rolname`)).rows;
 const required=['postgres','collect_runtime','collect_importer','anon','authenticated','service_role',
  'pg_read_all_data','pg_write_all_data','pg_maintain'];
 if(required.some(name=>!roles.some(r=>r.name===name))||roles.filter(r=>r.name==='collect_runtime').some(r=>r.superuser!=='false'||r.login!=='false'||r.bypass_rls!=='false'))fail('unreviewed_database_roles');
 const memberships=(await query(client,`SELECT pg_catalog.pg_get_userbyid(m.roleid) AS role_name,pg_catalog.pg_get_userbyid(m.member) AS member_name,
  pg_catalog.pg_get_userbyid(m.grantor) AS grantor,m.admin_option::text AS admin_option,m.inherit_option::text AS inherit_option,m.set_option::text AS set_option
  FROM pg_catalog.pg_auth_members m ORDER BY role_name,member_name,grantor`)).rows;
 const defaultAcls=(await query(client,`SELECT pg_catalog.pg_get_userbyid(d.defaclrole) AS owner,
  CASE WHEN d.defaclnamespace=0 THEN '' ELSE n.nspname END AS schema,d.defaclobjtype::text AS object_type,d.defaclacl::text AS acl
  FROM pg_catalog.pg_default_acl d LEFT JOIN pg_catalog.pg_namespace n ON n.oid=d.defaclnamespace
  WHERE d.defaclrole=(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')
   AND (d.defaclnamespace=0 OR n.nspname IN ('app','private'))
  ORDER BY schema,object_type`)).rows;
 // Event triggers affect DDL regardless of the target schema. Capture every
 // enabled or disabled trigger and its handler in one catalogue snapshot.
 // Values are review evidence, not an allowlist or a safety determination.
 const eventTriggers=(await query(client,`SELECT e.oid::text AS oid,e.evtname AS name,e.evtevent AS event,
  e.evtenabled::text AS enabled,e.evttags AS tags,e.evtowner::text AS owner_oid,
  pg_catalog.pg_get_userbyid(e.evtowner) AS owner,
  p.oid::text AS handler_oid,n.nspname AS handler_schema,p.proname AS handler_name,
  pg_catalog.pg_get_function_identity_arguments(p.oid) AS handler_arguments,
  p.proowner::text AS handler_owner_oid,pg_catalog.pg_get_userbyid(p.proowner) AS handler_owner,
  p.prosecdef::text AS handler_security_definer,
  ARRAY(SELECT setting FROM pg_catalog.unnest(p.proconfig) WITH ORDINALITY AS cfg(setting,ordinal)
   WHERE pg_catalog.split_part(setting,'=',1)='search_path' ORDER BY ordinal) AS handler_search_path,
  pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_functiondef(p.oid),'UTF8')),'hex') AS handler_definition_sha256
  FROM pg_catalog.pg_event_trigger e JOIN pg_catalog.pg_proc p ON p.oid=e.evtfoid
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  ORDER BY e.evtname COLLATE pg_catalog."C",e.oid`)).rows;
 const preimage={format:'collect.atomic-cloud-preimage.v3',projectRef:PROJECT,version:entry.version,sourceSha256:entry.sha256,
  history:entries.slice(0,index).map(x=>({...x})),database:target.database,serverVersion:target.server_version_num,
  sessionRole:target.session_role,activeRole:target.active_role,fence:{mode:target.mode,sourceSha256:target.source_sha256,epoch:target.epoch,operationId:target.operation_id},
  schemas,relations,functions,roles,memberships,defaultAcls,eventTriggers};
 return {preimage,sha256:createHash('sha256').update(JSON.stringify(preimage)).digest('hex')};
}

// The source is already bounded and verified against the pinned migration hash.
// These are the only two fixed dollar-quoted bodies needed by this executor;
// this is deliberately not a general SQL parser.
function notificationFunctionBodies(text){
 const result={};
 for(const name of ['notification_delivery_eligible','notification_delivery_guard']){
  const pattern=new RegExp(`^CREATE FUNCTION private\\.${name}\\([^\\n]*\\)\\s*RETURNS [^\\n]*? AS \\$\\$([\\s\\S]*?)\\$\\$;`,'gm');
  const matches=[...text.matchAll(pattern)];if(matches.length!==1)fail('source_invalid');
  result[name]=createHash('sha256').update(matches[0][1],'utf8').digest('hex');
 }
 return result;
}

async function verifyPostcondition(client,entry,preimage,notificationBodies){
 const notification=entry.version===entries[15].version;
 const table=notification?'notification_deliveries':'client_diagnostic_reports';
 const runtimeTablePrivileges=notification?['SELECT','INSERT','UPDATE']:['SELECT','INSERT','DELETE'];
 // Object and namespace owners are checked explicitly below. Their intrinsic
 // privileges are not outsider grants. Superusers, the built-in data/maintenance roles,
 // and inherited runtime/data-role privileges require separate review of the
 // captured membership graph, including roles that can SET ROLE without
 // inheriting. These predicates do not establish that graph is authorized.
 const result=await query(client,`SELECT pg_catalog.pg_get_userbyid(c.relowner) AS owner,
  pg_catalog.pg_get_userbyid(n.nspowner) AS schema_owner,c.relrowsecurity AS rls,c.relforcerowsecurity AS forced,
  EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
   WHERE a.grantee NOT IN (c.relowner,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='collect_runtime'))
    OR a.grantor<>c.relowner OR (a.grantee<>c.relowner AND a.is_grantable)
    OR (a.grantee=(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='collect_runtime')
     AND NOT (a.privilege_type=ANY($2::text[])))) AS unexpected_acl,
  EXISTS(SELECT 1 FROM pg_catalog.pg_roles role WHERE NOT role.rolsuper AND role.oid<>c.relowner
   AND NOT pg_catalog.pg_has_role(role.oid,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='collect_runtime'),'USAGE')
   AND NOT pg_catalog.pg_has_role(role.oid,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='pg_read_all_data'),'USAGE')
   AND NOT pg_catalog.pg_has_role(role.oid,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='pg_write_all_data'),'USAGE')
   AND NOT pg_catalog.pg_has_role(role.oid,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='pg_maintain'),'USAGE')
   AND pg_catalog.has_table_privilege(role.oid,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')) AS unexpected_effective_privilege,
  EXISTS(SELECT 1 FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) AS unexpected_column_acl,
  pg_catalog.has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') AS anon_any,
  pg_catalog.has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') AS authenticated_any,
  pg_catalog.has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE') AS service_any,
  pg_catalog.has_table_privilege('collect_runtime',c.oid,'SELECT') AS runtime_select,
  pg_catalog.has_table_privilege('collect_runtime',c.oid,'INSERT') AS runtime_insert,
  pg_catalog.has_table_privilege('collect_runtime',c.oid,'UPDATE') AS runtime_update,
  pg_catalog.has_table_privilege('collect_runtime',c.oid,'DELETE') AS runtime_delete,
  pg_catalog.has_table_privilege('collect_runtime',c.oid,'TRUNCATE,REFERENCES,TRIGGER,MAINTAIN') AS runtime_extra
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND c.relname=$1`,[table,runtimeTablePrivileges]);
 const r=result.rows?.[0];
 if(result.rows?.length!==1||r.owner!=='postgres'||r.schema_owner!=='postgres'||r.rls!==true||r.forced!==true||r.unexpected_acl||r.unexpected_column_acl||r.unexpected_effective_privilege||r.anon_any||r.authenticated_any||r.service_any||
  !r.runtime_select||!r.runtime_insert||r.runtime_update!==notification||r.runtime_delete===notification||r.runtime_extra)fail('postcondition_mismatch');
 // The only policy on either new relation must be the migration's exact
 // permissive ALL policy for collect_runtime. Extra policies can broaden RLS.
 const policies=(await query(client,`SELECT p.polname AS name,p.polcmd::text AS command,p.polpermissive AS permissive,
  p.polroles=ARRAY[(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='collect_runtime')]::oid[] AS exact_role,
  pg_catalog.pg_get_expr(p.polqual,p.polrelid) AS using_expression,
  pg_catalog.pg_get_expr(p.polwithcheck,p.polrelid) AS check_expression
  FROM pg_catalog.pg_policy p WHERE p.polrelid=pg_catalog.to_regclass('app.'||$1) ORDER BY p.polname COLLATE pg_catalog."C"`,[table])).rows;
 if(policies.length!==1||policies[0].name!==(notification?'notification_delivery_runtime':'client_diagnostic_runtime')||
  policies[0].command!=='*'||policies[0].permissive!==true||policies[0].exact_role!==true||
  policies[0].using_expression!=='true'||policies[0].check_expression!=='true')fail('postcondition_mismatch');
 // User triggers must be an exact set, ALWAYS enabled and without trigger
 // arguments, column filters, WHEN predicates, transitions or constraint mode.
 const triggers=(await query(client,`SELECT t.tgname AS name,t.tgenabled::text AS enabled,t.tgtype::integer AS event_type,
  CASE WHEN t.tgname='collect_fence_statement_v1' THEN t.tgfoid=pg_catalog.to_regprocedure('private._collect_fence_statement()')::oid
   WHEN t.tgname='notification_delivery_identity' THEN t.tgfoid=pg_catalog.to_regprocedure('private.notification_delivery_guard()')::oid
   ELSE false END AS exact_handler,
  (t.tgnargs=0 AND pg_catalog.octet_length(t.tgargs)=0 AND t.tgqual IS NULL AND t.tgattr=''::pg_catalog.int2vector
   AND t.tgconstraint=0 AND t.tgparentid=0 AND NOT t.tgdeferrable AND NOT t.tginitdeferred
   AND t.tgoldtable IS NULL AND t.tgnewtable IS NULL) AS exact_shape
  FROM pg_catalog.pg_trigger t WHERE t.tgrelid=pg_catalog.to_regclass('app.'||$1) AND NOT t.tgisinternal
  ORDER BY t.tgname COLLATE pg_catalog."C"`,[table])).rows;
 const expectedTriggers=notification?[['collect_fence_statement_v1',62],['notification_delivery_identity',31]]:[['collect_fence_statement_v1',62]];
 if(triggers.length!==expectedTriggers.length||triggers.some((t,i)=>t.name!==expectedTriggers[i][0]||t.event_type!==expectedTriggers[i][1]||
  t.enabled!=='A'||t.exact_handler!==true||t.exact_shape!==true))fail('postcondition_mismatch');
 // Compare the existing fence routine's complete captured entry again after
 // the migration body and after the history write; its digest is review
 // evidence, not an assertion that its earlier body was intrinsically safe.
 const fenceBefore=preimage.functions.filter(f=>f.schema==='private'&&f.name==='_collect_fence_statement');
 const fenceAfter=(await query(client,`SELECT n.nspname AS schema,p.proname AS name,pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments,
  pg_catalog.pg_get_userbyid(p.proowner) AS owner,p.prosecdef::text AS security_definer,coalesce(p.proacl::text,'') AS acl,coalesce(p.proconfig::text,'') AS settings,
  pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_functiondef(p.oid),'UTF8')),'hex') AS definition_sha256
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname='_collect_fence_statement'
  ORDER BY n.nspname,p.proname,pg_catalog.pg_get_function_identity_arguments(p.oid)`)).rows;
 if(fenceBefore.length!==1||fenceAfter.length!==1||JSON.stringify(fenceBefore[0])!==JSON.stringify(fenceAfter[0]))fail('postcondition_mismatch');
 if(notification){
  const fn=await query(client,`SELECT p.proname AS name,pg_catalog.pg_get_userbyid(p.proowner) AS owner,
   pg_catalog.pg_get_userbyid(n.nspowner) AS schema_owner,p.prosecdef AS security_definer,
   p.proconfig @> ARRAY['search_path=pg_catalog']::text[] AS safe_path,
   pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p.prosrc,'UTF8')),'hex') AS body_sha256,
   (p.prokind='f' AND NOT p.proisstrict AND NOT p.proretset AND NOT p.proleakproof AND p.provariadic=0
    AND p.pronargdefaults=0 AND p.proargdefaults IS NULL AND p.proallargtypes IS NULL AND p.proargmodes IS NULL
    AND p.proparallel='u' AND p.prosupport=0 AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
    AND ((p.proname='notification_delivery_eligible' AND p.provolatile='s' AND l.lanname='sql' AND p.prorettype='boolean'::regtype
      AND p.proargnames=ARRAY['p_event_id','p_device_id','p_user_id','p_session_id','p_token_sha256','p_event_sha256']::text[])
     OR (p.proname='notification_delivery_guard' AND p.provolatile='v' AND l.lanname='plpgsql' AND p.prorettype='trigger'::regtype
      AND p.proargnames IS NULL))) AS exact_shape,
   pg_catalog.has_function_privilege('collect_runtime',p.oid,'EXECUTE') AS runtime_execute,
   pg_catalog.has_schema_privilege('collect_runtime',n.oid,'USAGE') AS runtime_schema_usage,
   EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
    WHERE a.grantee NOT IN (p.proowner,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='collect_runtime'))
     OR a.grantor<>p.proowner OR (a.grantee<>p.proowner AND a.is_grantable)) AS unexpected_acl,
   EXISTS(SELECT 1 FROM pg_catalog.pg_roles role WHERE NOT role.rolsuper AND role.oid<>p.proowner
    AND NOT pg_catalog.pg_has_role(role.oid,(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='collect_runtime'),'USAGE')
    AND pg_catalog.has_function_privilege(role.oid,p.oid,'EXECUTE')) AS unexpected_execute,
   EXISTS(SELECT 1 FROM pg_catalog.pg_roles role WHERE NOT role.rolsuper AND role.oid<>n.nspowner
    AND pg_catalog.has_schema_privilege(role.oid,n.oid,'CREATE')) AS unexpected_schema_create,
   EXISTS(SELECT 1 FROM pg_catalog.aclexplode(coalesce(n.nspacl,pg_catalog.acldefault('n',n.nspowner))) a
    WHERE a.grantee=0 AND a.privilege_type='CREATE') AS public_schema_create
   FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace JOIN pg_catalog.pg_language l ON l.oid=p.prolang
   WHERE p.oid IN (pg_catalog.to_regprocedure('private.notification_delivery_eligible(text,text,text,text,text,text)'),
    pg_catalog.to_regprocedure('private.notification_delivery_guard()')) ORDER BY p.proname`);
  if(fn.rows?.length!==2||fn.rows.some(f=>f.owner!=='postgres'||f.schema_owner!=='postgres'||f.security_definer!==(f.name==='notification_delivery_eligible')||
   f.safe_path!==true||f.exact_shape!==true||f.body_sha256!==notificationBodies?.[f.name]||f.runtime_execute!==true||f.runtime_schema_usage!==true||f.unexpected_acl||f.unexpected_execute||
   f.unexpected_schema_create||f.public_schema_create))fail('postcondition_mismatch');
 }
}
async function exclusive(client,run){
 validateConnection(client);if(discardClients.has(client))fail('client_discard_required');
 if(activeClients.has(client))fail('client_already_in_use');activeClients.add(client);
 try{const backendPid=await idleProbe(client);return await run(backendPid);}finally{activeClients.delete(client);}
}
function uncertain(client,code,backendPid){destroy(client);const error=new AtomicMigrationError(code);error.backendPid=backendPid;throw error;}

// Capturing is read-only apart from locks. Review the returned preimage outside
// this module; the caller must later supply its exact digest for execution.
// This comparison binds a review but does not itself attest human approval.
export async function capturePinnedPreimage(client,{version,expectedSha}={}){
 const {entry,index}=selected(version,expectedSha);await source(entry);
 return exclusive(client,async backendPid=>{
  let begun;try{begun=await query(client,'BEGIN');}catch{uncertain(client,'begin_unconfirmed',backendPid);}
  if(begun.command!=='BEGIN')uncertain(client,'begin_unconfirmed',backendPid);
  let committing=false;
  try{
   const inspection=await lockAndInspect(client,index,true,backendPid);
   if(inspection.state!=='not_recorded')fail('already_recorded_reconcile_first');
   const result=await catalogPreimage(client,entry,index,inspection.target);
   committing=true;const committed=await query(client,'COMMIT');if(committed.command!=='COMMIT')fail('preimage_unconfirmed');
   return result;
  }catch(e){
   if(committing)uncertain(client,'preimage_unconfirmed',backendPid);
   if(discardClients.has(client))uncertain(client,'rollback_unconfirmed',backendPid);
   try{const result=await query(client,'ROLLBACK');if(result.command!=='ROLLBACK')fail('rollback_unconfirmed');}catch{uncertain(client,'rollback_unconfirmed',backendPid);}
   if(e instanceof AtomicMigrationError&&e.code==='backend_changed')uncertain(client,'backend_changed',backendPid);
   if(e instanceof AtomicMigrationError)throw e;fail('preimage_unconfirmed');
  }
 });
}

export async function executePinnedMigration(client,{version,expectedSha,expectedPreimageSha,expectedBackendPid}={}){
 const {entry,index}=selected(version,expectedSha),input=await source(entry);
 const notificationBodies=entry.version===entries[15].version?notificationFunctionBodies(input.text):null;
 if(!/^[a-f0-9]{64}$/.test(expectedPreimageSha??''))fail('target_preimage_required');
 if(expectedBackendPid!==undefined&&(!Number.isSafeInteger(expectedBackendPid)||expectedBackendPid<1))fail('backend_pin_invalid');
 return exclusive(client,async backendPid=>{
  if(expectedBackendPid!==undefined&&backendPid!==expectedBackendPid)fail('backend_changed');
  let begun;try{begun=await query(client,'BEGIN');}catch{uncertain(client,'begin_unconfirmed',backendPid);}
  if(begun.command!=='BEGIN')uncertain(client,'begin_unconfirmed',backendPid);
  let committing=false;
  try{
   const inspection=await lockAndInspect(client,index,true,backendPid);
   if(inspection.state!=='not_recorded')fail('already_recorded_reconcile_first');
   const actual=await catalogPreimage(client,entry,index,inspection.target);
   if(actual.sha256!==expectedPreimageSha)fail('target_preimage_mismatch');
   await query(client,input.body,undefined,BODY_TIMEOUT_MS);
   await verifyPostcondition(client,entry,actual.preimage,notificationBodies);
   await query(client,'INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[entry.version,entry.name,[input.text]]);
   await verifyPostcondition(client,entry,actual.preimage,notificationBodies);
   const finalIdentity=await query(client,'SELECT pg_catalog.pg_backend_pid() AS backend_pid');
   if(Number(finalIdentity.rows?.[0]?.backend_pid)!==backendPid)fail('backend_changed');
   committing=true;const result=await query(client,'COMMIT');
   if(result.command!=='COMMIT')fail('commit_unconfirmed');
   return {status:'committed',projectRef:PROJECT,version:entry.version,sourceSha256:entry.sha256};
  }catch(e){
   if(committing)uncertain(client,'commit_unconfirmed',backendPid);
   if(discardClients.has(client))uncertain(client,'rollback_unconfirmed',backendPid);
   try{const result=await query(client,'ROLLBACK');if(result.command!=='ROLLBACK')fail('rollback_unconfirmed');}
   catch{uncertain(client,'rollback_unconfirmed',backendPid);}
   if(e instanceof AtomicMigrationError&&e.code==='backend_changed')uncertain(client,'backend_changed',backendPid);
   if(e instanceof AtomicMigrationError)throw e;
   fail('migration_rolled_back');
  }
 });
}

// Use a NEW dedicated connection after an unconfirmed commit. Acquiring the
// same locks waits for the original transaction before reading history. A
// timeout or mismatch stays unknown and must never trigger an automatic retry.
export async function reconcilePinnedMigration(client,{version,expectedSha,priorBackendPid}={}){
 const {entry,index}=selected(version,expectedSha);await source(entry);
 if(!Number.isSafeInteger(priorBackendPid)||priorBackendPid<1)fail('fresh_connection_required');
 return exclusive(client,async backendPid=>{
  if(backendPid===priorBackendPid)fail('fresh_connection_required');
  let begun;try{begun=await query(client,'BEGIN');}catch{uncertain(client,'begin_unconfirmed',backendPid);}
  if(begun.command!=='BEGIN')uncertain(client,'begin_unconfirmed',backendPid);
  let committing=false;
  try{
   const inspection=await lockAndInspect(client,index,false,backendPid);
   committing=true;const result=await query(client,'COMMIT');if(result.command!=='COMMIT')fail('reconciliation_unconfirmed');
   return {status:inspection.state,projectRef:PROJECT,version:entry.version,sourceSha256:entry.sha256};
  }catch(e){
   if(committing)uncertain(client,'reconciliation_unconfirmed',backendPid);
   if(discardClients.has(client))uncertain(client,'rollback_unconfirmed',backendPid);
   try{const result=await query(client,'ROLLBACK');if(result.command!=='ROLLBACK')fail('rollback_unconfirmed');}catch{uncertain(client,'rollback_unconfirmed',backendPid);}
   if(e instanceof AtomicMigrationError&&e.code==='backend_changed')uncertain(client,'backend_changed',backendPid);
   if(e instanceof AtomicMigrationError)throw e;fail('reconciliation_unconfirmed');
  }
 });
}
