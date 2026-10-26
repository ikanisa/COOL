// Offline, first-import operator tool. Never exposed to collect_runtime or HTTP.
// Every original row remains in the separately permissioned quarantine schema.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {open,realpath} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {decodeCell,encodeCell,rowDigest,verifyStage,readSnapshot,databaseConnectionOptions} from './data_stage.mjs';

const digest=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const ident=value=>{if(!/^[a-z][a-z0-9_]*$/.test(value))throw new Error('Invalid identifier');return '"'+value+'"';};
const manifestBytes=readFileSync(new URL('../../supabase/schema-src/source_manifest.json',import.meta.url));
const manifest=JSON.parse(manifestBytes);
export const reviewedTables=Object.freeze([...manifest.source_table_names].sort());
if(manifest.format!=='collect.supabase.baseline.v1'||manifest.source_migrations.length!==17||reviewedTables.length!==97||new Set(reviewedTables).size!==97)throw new Error('Unreviewed source baseline manifest');
const manifestSha256=createHash('sha256').update(manifestBytes).digest('hex');
// Old provider credentials, session proofs, reservations and mutation guards
// cannot become managed Auth authority. Historical business/audit rows retain
// their original identifiers; fresh sessions must come from Supabase Auth.
export function disposition(name){
 if(!reviewedTables.includes(name))throw new Error('Unknown table has no reviewed disposition');
 if(name==='auth_sessions')return 'historical_revoked';
 if(name.startsWith('auth_')||name.startsWith('native_')||[
  'admin_sessions','admin_challenges','admin_email_otp_challenges','admin_rate_limits',
  'mutation_guards','admin_account_guards','admin_bridge_guards',
  'momo_processing_guards','roster_commit_guards','privacy_retention_guards',
  'momo_gateway_credentials','momo_gateway_pairings',
 ].includes(name))return 'archive_only';
 return 'business_exact';
}
export function projectedTable(table,migrationEpoch){
 if(table.name!=='auth_sessions')return table;
 const rows=table.rows.map(row=>{
  const cells=row.cells.map(cell=>{
   let value=decodeCell(cell);
   if(cell.name==='revoked_at')value=BigInt(migrationEpoch);
   if(cell.name==='revocation_reason')value='supabase_migration_historical_reference';
   if(cell.name==='assurance_level')value=1n;
   if(['mfa_at','mfa_factor_id'].includes(cell.name))value=null;
   return {name:cell.name,...encodeCell(value)};
  });
  return {...row,cells,sha256:rowDigest(cells)};
 }).sort((a,b)=>a.sha256.localeCompare(b.sha256));
 return {...table,rows,sha256:createHash('sha256').update(rows.map(r=>r.sha256).join('\n')).digest('hex')};
}
export function makePromotionPlan(snapshot,approvedTables,migrationEpoch){
 if(!Number.isSafeInteger(migrationEpoch)||migrationEpoch<=0)throw new Error('Fixed reviewed migration epoch required');
 if(!Array.isArray(approvedTables)||new Set(approvedTables).size!==approvedTables.length||
  JSON.stringify([...approvedTables].sort())!==JSON.stringify(reviewedTables)||
  JSON.stringify(reviewedTables)!==JSON.stringify(snapshot.tables.map(t=>t.name).sort()))throw new Error('Source table set differs from the reviewed baseline');
 const sessions=snapshot.tables.find(t=>t.name==='auth_sessions');
 if(sessions.rows.some(row=>row.cells.some(cell=>cell.name==='created_at'&&decodeCell(cell)>BigInt(migrationEpoch))))throw new Error('Migration epoch predates source sessions');
 const tables=snapshot.tables.map(t=>({name:t.name,disposition:disposition(t.name),row_count:t.row_count,sha256:t.sha256,target_sha256:projectedTable(t,migrationEpoch).sha256}));
 // Device sessions/capabilities need a separately qualified rebind/ACK plan.
 // Refuse to silently invalidate a populated native/gateway workflow.
 if(tables.some(t=>t.row_count&&t.disposition==='archive_only'&&(t.name.startsWith('native_')||t.name.startsWith('momo_gateway_'))))throw new Error('Populated native/device credentials require a reviewed rebind plan');
 return {format:'collect.first-import.plan.v1',source_sha256:snapshot.source_sha256,source_manifest_sha256:manifestSha256,migration_epoch:migrationEpoch,tables,
  business_rows:tables.filter(t=>t.disposition==='business_exact').reduce((n,t)=>n+t.row_count,0),
  archived_rows:tables.filter(t=>t.disposition==='archive_only').reduce((n,t)=>n+t.row_count,0),
  historical_revoked_rows:tables.filter(t=>t.disposition==='historical_revoked').reduce((n,t)=>n+t.row_count,0),
  legacy_sessions_restored:false,managed_principals_created:0,cutover_authorized:false};
}
export async function catalogIdentity(client){
 const result=await client.query(`SELECT category,identity,definition FROM (
  SELECT 'table' category,n.nspname||'.'||c.relname identity,
   jsonb_build_object('owner',pg_get_userbyid(c.relowner),'options',c.reloptions,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl,'columns',
    (SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'identity',a.attidentity,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum)
     FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped))::text definition
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('app','private','api') AND c.relkind IN('r','p')
  UNION ALL SELECT 'constraint',n.nspname||'.'||c.relname||'.'||x.conname,pg_get_constraintdef(x.oid)
   FROM pg_constraint x JOIN pg_class c ON c.oid=x.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('app','private','api')
  UNION ALL SELECT 'trigger',n.nspname||'.'||c.relname||'.'||t.tgname,pg_get_triggerdef(t.oid)||':'||t.tgenabled::text
   FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('app','private','api') AND NOT t.tgisinternal
  UNION ALL SELECT 'function',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',pg_get_functiondef(p.oid)||coalesce(p.proacl::text,'')||':'||pg_get_userbyid(p.proowner)
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('app','private','api')
  UNION ALL SELECT 'index',n.nspname||'.'||c.relname,pg_get_indexdef(c.oid)
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('app','private','api') AND c.relkind='i'
  UNION ALL SELECT 'view',n.nspname||'.'||c.relname,pg_get_viewdef(c.oid)||':'||pg_get_userbyid(c.relowner)||coalesce(c.relacl::text,'')||coalesce(c.reloptions::text,'')
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('app','private','api') AND c.relkind='v'
  UNION ALL SELECT 'policy',schemaname||'.'||tablename||'.'||policyname,concat_ws('|',permissive,roles::text,cmd,qual,with_check)
   FROM pg_policies WHERE schemaname IN('app','private','api')
  UNION ALL SELECT 'schema',nspname,pg_get_userbyid(nspowner)||coalesce(nspacl::text,'') FROM pg_namespace WHERE nspname IN('app','private','api')
  UNION ALL SELECT 'sequence',n.nspname||'.'||c.relname,jsonb_build_object('owner',pg_get_userbyid(c.relowner),'acl',c.relacl,'type',format_type(s.seqtypid,NULL),'start',s.seqstart,'increment',s.seqincrement,'min',s.seqmin,'max',s.seqmax,'cache',s.seqcache,'cycle',s.seqcycle)::text
   FROM pg_sequence s JOIN pg_class c ON c.oid=s.seqrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('app','private','api')
  UNION ALL SELECT 'role',rolname,jsonb_build_object('login',rolcanlogin,'inherit',rolinherit,'super',rolsuper,'bypass',rolbypassrls,'create_role',rolcreaterole,'create_db',rolcreatedb,'replication',rolreplication)::text FROM pg_roles WHERE rolname IN('collect_runtime','collect_importer')
  UNION ALL SELECT 'membership',r.rolname||':'||m.rolname||':'||pg_get_userbyid(a.grantor),jsonb_build_object('grantor',pg_get_userbyid(a.grantor),'admin',a.admin_option,'inherit',a.inherit_option,'set',a.set_option)::text FROM pg_auth_members a JOIN pg_roles r ON r.oid=a.roleid JOIN pg_roles m ON m.oid=a.member WHERE r.rolname IN('collect_runtime','collect_importer') OR m.rolname IN('collect_runtime','collect_importer')
 ) items ORDER BY category,identity,definition`);
 return digest(result.rows);
}
async function checkQuarantineCustody(client,schema){
 const result=await client.query(`SELECT r.rolname,has_schema_privilege(r.oid,$1,'USAGE') AS exposed,
  EXISTS(SELECT 1 FROM pg_tables t WHERE t.schemaname=$1 AND has_table_privilege(r.oid,format('%I.%I',t.schemaname,t.tablename),'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')) AS data_exposed
  FROM pg_roles r WHERE r.rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer')`,[schema]);
 if(result.rows.some(r=>r.exposed||r.data_exposed))throw new Error('Quarantine custody is exposed');
}
async function readTargetTable(client,table){
 const metadata=await client.query(`SELECT a.attname AS name,format_type(a.atttypid,a.atttypmod) AS type
 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='app' AND c.relname=$1 AND a.attnum>0 AND NOT a.attisdropped ORDER BY a.attnum`,[table.name]);
 if(JSON.stringify(metadata.rows.map(c=>c.name))!==JSON.stringify(table.columns.map(c=>c.name)))throw new Error('Target column set differs: '+table.name);
 const types=new Map(metadata.rows.map(c=>[c.name,c.type]));
 if(metadata.rows.some(c=>!['text','bigint','numeric','double precision','bytea'].includes(c.type)))throw new Error('Unreviewed target type');
 const result=await client.query('SELECT '+table.columns.map(c=>ident(c.name)).join(',')+' FROM app.'+ident(table.name));
 const hashes=result.rows.map(row=>rowDigest(table.columns.map(c=>{
  let value=row[c.name];const type=types.get(c.name);
  if(value!==null&&type==='bigint')value=BigInt(value);
  if(value!==null&&['numeric','double precision'].includes(type)){value=Number(value);if(!Number.isFinite(value))throw new Error('Invalid target numeric');}
  return {name:c.name,...encodeCell(value)};
 }))).sort();
 return {row_count:hashes.length,sha256:createHash('sha256').update(hashes.join('\n')).digest('hex')};
}
async function verifyRows(client,snapshot,plan){
 for(const table of snapshot.tables){
  const actual=await readTargetTable(client,table),entry=plan.tables.find(t=>t.name===table.name),promoted=entry.disposition!=='archive_only';
  if(actual.row_count!==(promoted?table.row_count:0)||promoted&&actual.sha256!==entry.target_sha256)throw new Error('Promoted data differs: '+table.name);
 }
 return true;
}
export async function reconcilePromotion(client,snapshot,{schema,plan,catalogSha256}){
 if(!/^collect_stage_[a-f0-9]{32}$/.test(schema))throw new Error('Invalid quarantine schema');
 const exists=await client.query('SELECT to_regclass($1) AS present',[schema+'.promotion_receipt']);
 if(!exists.rows[0].present)return {committed:false};
 const receipt=await client.query('SELECT receipt FROM '+ident(schema)+'.promotion_receipt');
 if(receipt.rows.length!==1||receipt.rows[0].receipt.source_sha256!==snapshot.source_sha256||receipt.rows[0].receipt.plan_sha256!==digest(plan)||receipt.rows[0].receipt.catalog_sha256!==catalogSha256)throw new Error('Promotion receipt identity differs');
 await checkQuarantineCustody(client,schema);
 await verifyStage(client,schema,snapshot);
 if(await catalogIdentity(client)!==catalogSha256)throw new Error('Post-import schema differs');
 await verifyRows(client,snapshot,plan);
 return {committed:true,verified:true,receipt:receipt.rows[0].receipt};
}
export async function promoteSnapshot(client,snapshot,{schema,approvedTables,catalogSha256,migrationEpoch}){
 const plan=makePromotionPlan(snapshot,approvedTables,migrationEpoch);
 if(!/^[a-f0-9]{64}$/.test(catalogSha256)||!/^collect_stage_[a-f0-9]{32}$/.test(schema))throw new Error('Reviewed catalog and quarantine identity required');
 // Always reconcile an uncertain prior commit before executing an insert.
 const prior=await reconcilePromotion(client,snapshot,{schema,plan,catalogSha256});
 if(prior.committed)return {...prior,replayed:false};
 // READ COMMITTED intentionally refreshes the pristine-check snapshot AFTER
 // all table locks. SERIALIZABLE could retain a pre-lock snapshot and miss a
 // writer that committed while we were waiting to acquire those locks.
 await client.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 try{
  await client.query("SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='60s'");
  await client.query('SELECT pg_advisory_xact_lock(734636924058501::bigint)');
  const names=(await client.query("SELECT tablename FROM pg_tables WHERE schemaname='app' ORDER BY tablename")).rows.map(r=>r.tablename);
  if(JSON.stringify(names)!==JSON.stringify([...approvedTables].sort()))throw new Error('Target table set differs');
  // Fence application, managed-projection/storage work and staged source
  // writers before reading any row data. Managed Auth itself is never altered.
  const boundaries=(await client.query("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN('app','private',$1) ORDER BY schemaname,tablename",[schema])).rows;
  await client.query('LOCK TABLE '+boundaries.map(t=>ident(t.schemaname)+'.'+ident(t.tablename)).join(',')+' IN ACCESS EXCLUSIVE MODE');
  // These are temporary read fences, never provider-schema DDL/data writes.
  // Refuse if the operator cannot exclude concurrent identity creation.
  await client.query('LOCK TABLE auth.users,auth.sessions IN SHARE MODE');
  if((await client.query('SELECT 1 FROM auth.users LIMIT 1')).rowCount||(await client.query('SELECT 1 FROM auth.sessions LIMIT 1')).rowCount)throw new Error('First-import target already contains managed Auth records');
  await checkQuarantineCustody(client,schema);
  await verifyStage(client,schema,snapshot);
  await client.query('SET CONSTRAINTS ALL DEFERRED');
  if(await catalogIdentity(client)!==catalogSha256)throw new Error('Target schema differs from approved catalog');
  const triggers=await client.query("SELECT t.tgenabled FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND NOT t.tgisinternal");
  if(triggers.rows.some(t=>t.tgenabled!=='O'))throw new Error('Unexpected disabled or replica trigger');
  const privateNames=(await client.query("SELECT tablename FROM pg_tables WHERE schemaname='private' ORDER BY tablename")).rows.map(r=>r.tablename);
  for(const name of privateNames){if((await client.query('SELECT 1 FROM private.'+ident(name)+' LIMIT 1')).rowCount)throw new Error('Target already contains managed authority or private work');}
  const insert=[];
  for(const table of snapshot.tables){
   const actual=await readTargetTable(client,table);
   // Only the curated, byte-identical role capability seed may pre-exist.
   if(actual.row_count){if(table.name==='admin_account_role_capabilities'&&actual.row_count===table.row_count&&actual.sha256===table.sha256)continue;throw new Error('Target already contains application records: '+table.name);}
   if(disposition(table.name)!=='archive_only'&&table.row_count)insert.push(projectedTable(table,migrationEpoch));
  }
  for(const table of insert)await client.query('ALTER TABLE app.'+ident(table.name)+' DISABLE TRIGGER USER');
  for(const table of insert){
   for(const row of table.rows){
    const values=row.cells.map(cell=>{const value=decodeCell(cell);return typeof value==='bigint'?value.toString():value;});
    await client.query('INSERT INTO app.'+ident(table.name)+' ('+table.columns.map(c=>ident(c.name)).join(',')+') VALUES ('+values.map((_,i)=>'$'+(i+1)).join(',')+')',values);
   }
  }
  // Flush deferred FK events before ALTER TABLE reenables USER triggers.
  // Internal FK triggers and CHECK constraints were never disabled.
  await client.query('SET CONSTRAINTS ALL IMMEDIATE');
  for(const table of insert)await client.query('ALTER TABLE app.'+ident(table.name)+' ENABLE TRIGGER USER');
  // Identity values are source values. Set the next sequence value above MAX.
  const sequences=await client.query(`SELECT c.relname AS table_name,a.attname AS column_name,pg_get_serial_sequence(format('%I.%I',n.nspname,c.relname),a.attname) AS sequence_name
   FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND a.attidentity<>'' AND a.attnum>0 AND NOT a.attisdropped`);
  for(const s of sequences.rows){
   const max=(await client.query('SELECT max('+ident(s.column_name)+')::text AS value FROM app.'+ident(s.table_name))).rows[0].value;
   if(max!==null){const next=BigInt(max)+1n;if(next<1n||next>9223372036854775807n||!/^app\.[a-z][a-z0-9_]*$/.test(s.sequence_name))throw new Error('Unreviewed or exhausted sequence');await client.query('ALTER SEQUENCE '+s.sequence_name.split('.').map(ident).join('.')+' RESTART WITH '+next);}
  }
  await client.query('SET CONSTRAINTS ALL IMMEDIATE');
  if(await catalogIdentity(client)!==catalogSha256)throw new Error('Import changed the approved schema or trigger state');
  await verifyRows(client,snapshot,plan);
  const receipt={format:'collect.first-import.receipt.v1',source_sha256:snapshot.source_sha256,plan_sha256:digest(plan),catalog_sha256:catalogSha256,business_rows:plan.business_rows,archived_rows:plan.archived_rows,historical_revoked_rows:plan.historical_revoked_rows,verified:true,legacy_sessions_restored:false,cutover_authorized:false};
  await client.query('CREATE TABLE '+ident(schema)+'.promotion_receipt (singleton boolean PRIMARY KEY CHECK(singleton),receipt jsonb NOT NULL)');
  await client.query('REVOKE ALL ON '+ident(schema)+'.promotion_receipt FROM PUBLIC');
  await client.query('INSERT INTO '+ident(schema)+'.promotion_receipt VALUES(true,$1)',[JSON.stringify(receipt)]);
  await client.query('COMMIT');return {committed:true,verified:true,receipt,replayed:false};
 }catch(error){await client.query('ROLLBACK').catch(()=>{});throw error;}
}

async function main(args){
 const options={};
 for(let i=0;i<args.length;i+=2){if(!['--source','--sha256','--receipt','--epoch','--stage-run-id','--catalog-sha256','--mode'].includes(args[i])||options[args[i]]!==undefined||args[i+1]===undefined)throw new Error('Unique explicit named options required');options[args[i]]=args[i+1];}
 const mode=options['--mode'],epoch=Number(options['--epoch']),runId=options['--stage-run-id'];
 if(!['plan','apply','reconcile'].includes(mode)||!options['--source']||!options['--receipt']||!/^\d+$/.test(options['--epoch']??'')||!/^[a-f0-9-]{36}$/.test(runId??'')||!/^[a-f0-9]{64}$/.test(options['--catalog-sha256']??''))throw new Error('Explicit mode/source/digest/receipt/epoch/stage identity/catalog required');
 const snapshot=await readSnapshot(resolve(options['--source']),options['--sha256']);
 const plan=makePromotionPlan(snapshot,reviewedTables,epoch),schema='collect_stage_'+runId.replaceAll('-','');
 const receiptPath=resolve(options['--receipt']),parent=await realpath(dirname(receiptPath)),repo=await realpath(resolve(import.meta.dirname,'../..'));
 if(parent===repo||parent.startsWith(repo+'/'))throw new Error('Private import receipt must remain outside public Git');
 const file=await open(receiptPath,'wx',0o600);
 let receipt={format:'collect.first-import.journal.v1',mode,status:'prepared',schema,source_sha256:snapshot.source_sha256,plan,catalog_sha256:options['--catalog-sha256'],cutover_authorized:false};
 const persist=async()=>{await file.truncate(0);await file.write(JSON.stringify(receipt,null,2)+'\n',0,'utf8');await file.sync();};
 try{
  await persist();
  if(mode==='plan'){receipt.status='preview_only';await persist();}
  else{
   const connectionOptions=databaseConnectionOptions(process.env.COLLECT_SUPABASE_DB_URL,'rrlduytparvsjfmegalh');
   const {Client}=createRequire(import.meta.url)(process.env.COLLECT_PG_MODULE??'pg');
   const client=new Client(connectionOptions);
   try{
    await client.connect();
    const input={schema,approvedTables:reviewedTables,migrationEpoch:epoch,catalogSha256:options['--catalog-sha256']};
    const result=mode==='reconcile'?await reconcilePromotion(client,snapshot,{...input,plan}):await promoteSnapshot(client,snapshot,input);
    receipt={...receipt,status:result.verified?'verified_import':result.committed===false?'not_committed':'unconfirmed',result};await persist();
   }catch(error){receipt.status='unconfirmed_reconcile_before_retry';await persist();throw error;}
   finally{await client.end();}
  }
 }finally{await file.close();}
 console.log(JSON.stringify({status:receipt.status,source_tables:plan.tables.length,business_rows:plan.business_rows,archived_rows:plan.archived_rows,historical_revoked_rows:plan.historical_revoked_rows,legacy_sessions_restored:false,cutover_authorized:false}));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main(process.argv.slice(2)).catch(()=>{console.error('First import refused or unconfirmed. Preserve the journal and reconcile this exact stage/source before retry; routing was not changed.');process.exitCode=1;});
