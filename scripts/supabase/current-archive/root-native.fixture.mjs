// ROOT ONLY. Author has NOT executed or connected this file.
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtemp,mkdir,chmod,readdir} from 'node:fs/promises';
import {resolve,isAbsolute} from 'node:path';
import {migrations as fixtureMigrations} from './fixtures.mjs';
import {identifier,sha} from './codec.mjs';
import {compilePlanningRequest,decodeManagementResult,preparePlanCandidate,compileCaptureRequest,assembleManagementSnapshot,sealManagementResponse} from './capture.mjs';
import {readEncryptedBundle,privateDirectory} from './bundle.mjs';
import {restoreInertArchive,localAdminUrl} from './restore.mjs';
const raw=process.env.COLLECT_ARCHIVE_TEST_ADMIN_URL;
if(!raw)throw Error('Root must explicitly supply loopback synthetic admin URL; no silent skip.');
const artifactParent=process.env.COLLECT_ARCHIVE_FIXTURE_OUTPUT_PARENT;
if(!artifactParent||!isAbsolute(artifactParent)||resolve(artifactParent)!==artifactParent)throw Error('Root must explicitly supply an absolute physical private fixture output parent.');
await privateDirectory(artifactParent);
const count=Number(process.env.COLLECT_ARCHIVE_FIXTURE_MIGRATIONS??'8');assert([8,9,10].includes(count));
const adminUri=localAdminUrl(raw),{Client}=await import('pg');
const makeClient=connectionString=>{const c=new Client({connectionString,ssl:false,options:'-c statement_timeout=30000',connectionTimeoutMillis:5000,statement_timeout:30000});c.on('error',()=>{});return c;};
// This remains the synthetic three-table/five-row native-type fixture, not the curated schema.
test('Root synthetic three-table nativePG17 Management SQL fixture, simulated API shape only, exact encrypted inert restore and migration-tamper refusal',async()=>{
 const sourceName='collect_archive_source_'+randomUUID().replaceAll('-','')+'_test',admin=makeClient(adminUri.href);await admin.connect();
 try{const id=(await admin.query('SELECT current_database()::text AS database,pg_catalog.host(pg_catalog.inet_server_addr()) AS address')).rows[0];assert.equal(id.database,'postgres');assert(['127.0.0.1','::1'].includes(id.address));await admin.query('CREATE DATABASE '+identifier(sourceName)+" TEMPLATE template0 ENCODING 'UTF8'");}finally{await admin.end();}
 const sourceUri=new URL(adminUri);sourceUri.pathname='/'+sourceName;const source=makeClient(sourceUri.href);await source.connect();let sealed,snapshot,nativeRollbackTags=0,artifacts;
 const all=[...fixtureMigrations,...[{version:'20261021120000',name:'synthetic_8',sha256:sha('-- synthetic source bytes 8\nSELECT 8;\n')},{version:'20261022120000',name:'synthetic_9',sha256:sha('-- synthetic source bytes 9\nSELECT 9;\n')}]];const sourceMigrations=all.slice(0,count).map(({observed_record_sha256,...m})=>m);
 // Only the HTTP response shape/status is simulated. Every generated SQL batch,
 // native output function, cap/hash guard and ROLLBACK actually runs on nativePG.
 async function localManagementShape(compiled){assert.equal(compiled.method,'LOCAL_NATIVE_FIXTURE');assert.equal(compiled.url,null);assert.equal(compiled.fixture_database,sourceName);const all=await source.query(compiled.body.query);assert(Array.isArray(all));assert.equal(all.at(-1).command,'ROLLBACK');nativeRollbackTags++;const selects=all.filter(r=>r.fields?.length);assert.equal(selects.length,1);return {status:201,body:Buffer.from(JSON.stringify(selects[0].rows))};}
 try{
  await source.query('CREATE SCHEMA app; CREATE SCHEMA private; CREATE SCHEMA supabase_migrations; CREATE TABLE supabase_migrations.schema_migrations(version text,name text,statements text[]);');
  for(const m of sourceMigrations)await source.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2,$3)',[m.version,m.name,['synthetic-only-not-real-migration']]);
  await source.query('CREATE TABLE app.sample(big bigint,n numeric(40,12),neg numeric(2,-3),v varchar(12),c char(4),j json,jb jsonb,raw bytea,b boolean,at timestamp(6),tz timestamptz(6),u uuid,t text,f real,d double precision); CREATE TABLE private.journal(id uuid,detail jsonb,revoked_at bigint); CREATE TABLE private.time_edges(at timestamp(6),tz timestamptz(6),d date,n numeric); CREATE SEQUENCE app.sample_seq START 9007199254740993;');
  const cells=['9007199254740993','12345678901234567890.123456789012','99000','x  ','x   ',' {"a": 1, "a": 2} ','{"a": 9007199254740993,"s":"é"}','\\x00017fff','true','2026-10-21 00:01:02.123456','2026-10-21 00:01:02.654321+00','00000000-0000-0000-0000-000000000001','a\n\r\t\u0001\\"é','-0','1.7976931348623157e+308'];
  await source.query('INSERT INTO app.sample VALUES('+cells.map((_,i)=>'$'+(i+1)).join(',')+')',cells);await source.query('INSERT INTO app.sample VALUES('+cells.map(()=> 'NULL').join(',')+')');
  await source.query('INSERT INTO private.journal VALUES($1,$2,$3)',['00000000-0000-0000-0000-000000000002','{"state":"unknown","may_send":false}','1792500000']);
  await source.query('INSERT INTO private.time_edges VALUES($1,$2,$3,$4),($5,$6,$7,$8)',['0001-01-01 00:00:00.123456 BC','0001-01-01 00:00:00.654321+00 BC','infinity','Infinity','infinity','-infinity','-infinity','NaN']);
  const planning=compilePlanningRequest({fixtureDatabase:sourceName,expectedMigrationCount:sourceMigrations.length}),metadata=decodeManagementResult(await localManagementShape(planning),planning);
  assert.equal(metadata.postgres.database,sourceName);assert(['127.0.0.1','::1'].includes(metadata.postgres.server_address));assert.equal(metadata.relations.length,3);
  for(const [i,m]of metadata.migrations.entries())assert.deepEqual(JSON.parse(m.observed_record),{version:sourceMigrations[i].version,name:sourceMigrations[i].name,statements:['synthetic-only-not-real-migration']});
  // Distinct source-file hashes remain provenance only; exact stored-record pins
  // are independently derived from the preceding known-setup metadata snapshot.
  const plan=preparePlanCandidate(metadata,{runtimeSourceSha256:'a'.repeat(64),sourceMigrations,fixtureDatabase:sourceName,expectedMigrationCount:sourceMigrations.length}),compiled=compileCaptureRequest(plan),capture=await localManagementShape(compiled);
  snapshot=assembleManagementSnapshot(capture,plan,compiled);assert.equal(snapshot.fixture,true);assert.equal(snapshot.management_provenance.endpoint,'synthetic-local-node-pg');assert.equal(snapshot.management_provenance.response_shape_simulated,true);assert.equal(snapshot.management_provenance.native_rollback_command_complete_observed,false);
  const row=snapshot.tables.find(t=>t.name==='sample').rows.find(r=>r.cells[0]!==null);assert.equal(row.cells[0],cells[0]);assert.equal(row.cells[1],cells[1]);assert.equal(row.cells[2],cells[2]);assert.equal(row.cells[4],'x   ');assert.equal(row.cells[5],cells[5]);assert.equal(row.cells[7],cells[7]);assert.equal(row.cells[9],cells[9]);assert.equal(row.cells[10],cells[10]);assert.equal(row.cells[12],cells[12]);assert.equal(snapshot.sequences[0].last_value,'9007199254740993');
  const edges=snapshot.tables.find(t=>t.name==='time_edges').rows;assert(edges.some(r=>r.cells[0].endsWith(' BC')&&r.cells[1].endsWith(' BC')&&r.cells[2]==='infinity'&&r.cells[3]==='Infinity'));assert(edges.some(r=>r.cells[0]==='infinity'&&r.cells[1]==='-infinity'&&r.cells[2]==='-infinity'&&r.cells[3]==='NaN'));
  artifacts=await mkdtemp(resolve(artifactParent,'root-synthetic-'));await chmod(artifacts,0o700);const archiveDirectory=resolve(artifacts,'encrypted'),keyDirectory=resolve(artifacts,'separate-keys');await mkdir(archiveDirectory,{mode:0o700});await mkdir(keyDirectory,{mode:0o700});sealed=await sealManagementResponse(capture,plan,compiled,{archiveDirectory,keyDirectory});assert.equal((await readdir(archiveDirectory)).length,1);
  await source.query('UPDATE supabase_migrations.schema_migrations SET statements=$1::text[] WHERE version=$2',[['synthetic-mutated-same-version-name'],sourceMigrations[0].version]);const changed=(await source.query('SELECT version::text,name::text,statements[1]::text AS statement FROM supabase_migrations.schema_migrations WHERE version=$1',[sourceMigrations[0].version])).rows[0];assert.deepEqual(changed,{version:sourceMigrations[0].version,name:sourceMigrations[0].name,statement:'synthetic-mutated-same-version-name'});
  const refused=await localManagementShape(compiled);assert.throws(()=>assembleManagementSnapshot(refused,plan,compiled),{code:'MANAGEMENT_CAPTURE_REFUSED'});assert.equal((await readdir(archiveDirectory)).length,1);
 }finally{await source.end();}
 const {snapshot:back}=await readEncryptedBundle({archivePath:sealed.archive_path,keyPath:sealed.key_path,expectedArchiveSha256:sealed.archive_sha256});const restored=await restoreInertArchive(back,{adminUrl:adminUri.href,makeClient});assert.equal(restored.tables.length,3);assert.equal(restored.tables.reduce((n,t)=>n+t.rows,0),5);assert.equal(restored.columns_and_native_cells_exact,true);assert.equal(restored.operational_functions_triggers,false);assert.equal(restored.managed_auth_storage_ddl_dml,false);assert.equal(nativeRollbackTags,3);
 console.log(JSON.stringify({source_database:sourceName,inert_database:restored.database,synthetic_only:true,management_http_response_shape_and_status_simulated:true,real_generated_sql_and_native_cells:true,native_rollback_tags_observed_in_local_test:nativeRollbackTags,management_api_real_data_capture:false,archive_sha256:sealed.archive_sha256,synthetic_artifact_directory:artifacts,exact_native_roundtrip:true,same_version_name_statement_mutation_refused:true,full_recovery_acceptance:false}));
 // Both new databases and encrypted/key fixture files remain for Root review.
});
