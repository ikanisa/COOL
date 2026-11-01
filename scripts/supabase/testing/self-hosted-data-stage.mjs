// Real current-chain staging qualification. The historical first-import tool
// is deliberately not promoted into a current migration capability: its exact
// original table contract must refuse the newer target before changing rows.
import assert from 'node:assert/strict';
import {readFile,writeFile,realpath,lstat,mkdir} from 'node:fs/promises';
import {resolve,join,dirname} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {DatabaseSync} from 'node:sqlite';
import {readSnapshot,stageSnapshot,verifyStage,reconcileStage} from '../data_stage.mjs';
import {catalogIdentity,promoteSnapshot} from '../data_promote.mjs';
import {validateCurrentFixtureDescriptor,installCurrentFixtureAdditions,reviewedCurrentMigrations} from './self-hosted-current-schema.mjs';

const ROOT=resolve(import.meta.dirname,'../../..');
const {Client}=createRequire(import.meta.url)('pg');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const need=(value,code)=>{if(!value)throw Error(code);};
const passed=[];
let stage='invocation',failure=null,client=null,currentSchema=null,fixtureDigest=null,sourceDigest=null;
const observed={provider_calls:0,actual_postgres:true,actual_sqlite:true,synthetic_source:true,
 current_first_import_supported:false,production_acceptance:false};
async function step(name,operation){stage=name;await operation();passed.push(name);}
async function fingerprints(db){
 const tables=(await db.query("SELECT schemaname,tablename FROM pg_tables WHERE schemaname IN('app','private') ORDER BY schemaname,tablename")).rows;
 const values=[];
 for(const item of tables){
  need(/^[a-z][a-z0-9_]+$/.test(item.schemaname)&&/^[a-z][a-z0-9_]+$/.test(item.tablename),'BOUNDED_FIXTURE_RELATION_REQUIRED');
  const value=(await db.query(`SELECT count(*)::text AS rows,encode(sha256(convert_to(coalesce(string_agg(to_jsonb(t)::text,E'\\n' ORDER BY to_jsonb(t)::text),''),'UTF8')),'hex') AS sha256 FROM "${item.schemaname}"."${item.tablename}" t`)).rows[0];
  values.push({...item,...value});
 }
 return {relations:values.length,sha256:sha(JSON.stringify(values))};
}
try{
 need(process.env.COLLECT_CI_SYNTHETIC==='true'&&/^24\./.test(process.versions.node)&&process.argv.length===2,'EXPLICIT_NODE24_SYNTHETIC_INVOCATION_REQUIRED');
 const file=process.env.COLLECT_DATA_STAGE_FIXTURE_DESCRIPTOR,output=process.env.COLLECT_DATA_STAGE_OUTPUT_DIR;
 need(typeof file==='string'&&resolve(file)===file&&await realpath(file)===file,'PHYSICAL_CURRENT_FIXTURE_REQUIRED');
 const info=await lstat(file);need(info.isFile()&&!info.isSymbolicLink()&&(info.mode&0o777)===0o600&&info.size<65536,'PRIVATE_CURRENT_FIXTURE_REQUIRED');
 const fixture=JSON.parse(await readFile(file,'utf8'));validateCurrentFixtureDescriptor(fixture,{purpose:'backend'});
 need(typeof output==='string'&&resolve(output)===output&&await realpath(dirname(output))===dirname(output),'PHYSICAL_CURRENT_STAGE_OUTPUT_REQUIRED');
 await mkdir(output,{mode:0o700});
 const originalFetch=globalThis.fetch;globalThis.fetch=()=>{observed.provider_calls++;throw Error('NO_EXTERNAL_STAGING_CALLS');};
 const manifest=JSON.parse(await readFile(join(ROOT,'supabase/schema-src/source_manifest.json'),'utf8'));
 need(manifest.format==='collect.supabase.baseline.v1'&&manifest.source_migrations.length===17,'EXACT_HISTORICAL_SOURCE_BASELINE_REQUIRED');
 const files=[
  'scripts/supabase/testing/self-hosted-data-stage.mjs','scripts/supabase/testing/self-hosted-current-schema.mjs',
  'scripts/supabase/testing/reviewed-self-hosted-migrations.mjs','scripts/supabase/data_stage.mjs','scripts/supabase/data_promote.mjs',
  'supabase/schema-src/source_manifest.json','deploy/self-hosted/migrations.lock.json',
  ...manifest.source_migrations.map(row=>row.path),...(await reviewedCurrentMigrations()).map(row=>'supabase/migrations/'+row.name),
 ];
 const inputs=[];for(const path of [...new Set(files)].sort()){const bytes=await readFile(join(ROOT,path));inputs.push({path,sha256:sha(bytes)});}
 sourceDigest=sha(JSON.stringify(inputs));await writeFile(join(output,'INPUTS.json'),JSON.stringify({files:inputs,source_sha256:sourceDigest},null,2)+'\n',{flag:'wx',mode:0o600});
 client=new Client({connectionString:fixture.url,connectionTimeoutMillis:5000,statement_timeout:60000});await client.connect();
 let snapshot;
 await step('fresh normal-owner PostgreSQL installs the exact reviewed current chain',async()=>{
  const state=(await client.query('SELECT private.collect_fence_owner_status_v3() AS value')).rows[0].value;
  assert.equal(state.mode,'open');assert.equal(state.sourceSha256,fixture.source_sha256);assert.equal(state.rawActiveAdmissions,0);
  currentSchema=await installCurrentFixtureAdditions({unsafe:async(sql,values=[])=>(await client.query(sql,values)).rows});
  const sourcePath=join(output,'SOURCE.sqlite'),db=new DatabaseSync(sourcePath);
  try{for(const item of manifest.source_migrations){const bytes=await readFile(join(ROOT,item.path));assert.equal(sha(bytes),item.sha256);db.exec(bytes.toString('utf8'));}}
  finally{db.close();}
  fixtureDigest=sha(await readFile(sourcePath));snapshot=await readSnapshot(sourcePath,fixtureDigest);
  assert.equal(snapshot.tables.length,97);observed.source_tables=snapshot.tables.length;
  observed.source_rows=snapshot.tables.reduce((total,table)=>total+table.row_count,0);
 });
 await step('exact original cells stage into quarantined real SQL with denied client access',async()=>{
  const typedPath=join(output,'TYPED.sqlite'),typedDb=new DatabaseSync(typedPath);
  try{
   typedDb.exec('CREATE TABLE evidence(id TEXT PRIMARY KEY,amount INTEGER NOT NULL,body BLOB,note TEXT,ratio REAL,absent TEXT);CREATE TABLE empty(id TEXT)');
   typedDb.prepare('INSERT INTO evidence VALUES(?,?,?,?,?,?)').run('fixture',9007199254740993n,Buffer.from([0,1,255]),'French / Kinyarwanda 😃\n',1.25,null);
  }finally{typedDb.close();}
  observed.typed_sqlite_sha256=sha(await readFile(typedPath));
  const typed=await readSnapshot(typedPath,observed.typed_sqlite_sha256);
  assert.equal(typed.tables.find(table=>table.name==='evidence').rows[0].cells.find(cell=>cell.name==='amount').value,'9007199254740993');
  const typedStaged=await stageSnapshot(client,typed,{runId:randomUUID()});
  assert.equal(await verifyStage(client,typedStaged.schema,typed),true);
  const runId=randomUUID(),staged=await stageSnapshot(client,snapshot,{runId});
  assert.equal(staged.verified,true);assert.equal(staged.promoted,false);
  assert.equal(await verifyStage(client,staged.schema,snapshot),true);
  for(const role of ['anon','authenticated','service_role','collect_runtime','collect_importer']){
   const access=(await client.query("SELECT has_schema_privilege($1,$2,'USAGE') AS schema,has_table_privilege($1,$2||'.rows','SELECT,INSERT,UPDATE,DELETE') AS rows",[role,staged.schema])).rows[0];
   assert.equal(access.schema,false);assert.equal(access.rows,false);
  }
  // The normal owner deliberately has no SET membership in anon. Preserve
  // that boundary; native has_*_privilege above proves anon's object denial.
  await assert.rejects(client.query('SET ROLE anon'),error=>error.code==='42501');
  await client.query('SET ROLE collect_runtime');
  try{await assert.rejects(client.query('SELECT * FROM "'+staged.schema+'".rows'),error=>error.code==='42501');}
  finally{await client.query('RESET ROLE');}
 });
 await step('lost real COMMIT acknowledgement reconciles the same stage and forbids duplicate replay',async()=>{
  const runId=randomUUID();let lost=false;
  const transport={query:async(...args)=>{const result=await client.query(...args);if(args[0]==='COMMIT'&&!lost){lost=true;throw Error('synthetic lost staging COMMIT acknowledgement');}return result;}};
  await assert.rejects(stageSnapshot(transport,snapshot,{runId}),/synthetic lost staging COMMIT/);
  assert.equal(lost,true);const receipt=await reconcileStage(client,snapshot,runId);
  assert.equal(receipt.exists,true);assert.equal(receipt.verified,true);assert.equal(receipt.promoted,false);
  await assert.rejects(stageSnapshot(client,snapshot,{runId}),error=>error.code==='42P06');
  assert.deepEqual(await reconcileStage(client,snapshot,runId),receipt);
 });
 await step('tampered staged cells refuse exact readback without changing application authority',async()=>{
  const before=await fingerprints(client),staged=await stageSnapshot(client,snapshot,{runId:randomUUID()});
  const changed=await client.query('UPDATE "'+staged.schema+'".rows SET sha256=$1 WHERE table_name=(SELECT table_name FROM "'+staged.schema+'".rows LIMIT 1) AND ordinal=0',['0'.repeat(64)]);
  assert.equal(changed.rowCount,1);await assert.rejects(verifyStage(client,staged.schema,snapshot),/identity mismatch/);
  assert.deepEqual(await fingerprints(client),before);
 });
 await step('historical97-table promotion refuses current target before writes and preserves every app/private row',async()=>{
  const staged=await stageSnapshot(client,snapshot,{runId:randomUUID()}),before=await fingerprints(client),catalog=await catalogIdentity(client);
  await assert.rejects(promoteSnapshot(client,snapshot,{schema:staged.schema,approvedTables:snapshot.tables.map(row=>row.name),catalogSha256:catalog,migrationEpoch:1792497600}),/Target table set differs/);
  assert.deepEqual(await fingerprints(client),before);assert.equal(await catalogIdentity(client),catalog);
  assert.equal((await client.query('SELECT to_regclass($1) AS receipt',[staged.schema+'.promotion_receipt'])).rows[0].receipt,null);
  observed.target_relations=before.relations;observed.unchanged_target_sha256=before.sha256;
 });
 for(const item of inputs)assert.equal(sha(await readFile(join(ROOT,item.path))),item.sha256,'Qualification source changed');
 assert.equal(observed.provider_calls,0);globalThis.fetch=originalFetch;
}catch(error){failure={stage,code:typeof error?.code==='string'&&/^[A-Za-z0-9_]{1,80}$/.test(error.code)?error.code:'CURRENT_STAGE_QUALIFICATION_FAILED',message:typeof error?.message==='string'&&/^[A-Z0-9_]{1,100}$/.test(error.message)?error.message:null};}
finally{if(client)await client.end().catch(()=>{});}
const result={format:'collect.selfhost.data-stage.native.v1',status:!failure&&passed.length===5?'PASS':'FAIL',cases:passed,current_schema:currentSchema,
 source_sha256:sourceDigest,sqlite_sha256:fixtureDigest,observed,failure,provider_calls:observed.provider_calls,current_first_import_supported:false,
 historical_positive_import_acceptance:false,hosted_acceptance:false,production_acceptance:false};
console.log(JSON.stringify(result));process.exitCode=result.status==='PASS'?0:1;
