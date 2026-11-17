// Rehearses against the captured source schema and a fresh socket-only PG17.
// The source graph is processed in memory and never written to Cloud.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {PinHasher} from '../../../supabase/functions/_shared/domain/burimunsi/pin.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {captureLocalSource} from './source-reader.mjs';
import {compileTransfer,sourceSnapshotHmac} from './compile.mjs';
import {rehearseMaintenance,rehearseBootstrapMaintenance} from './maintenance.mjs';
import {prepareInitialBootstrap} from '../cloud-release/initial-account-bootstrap.mjs';

const sha=x=>createHash('sha256').update(x).digest('hex');
const capture=captureLocalSource(),dump=spawnSync('docker',['--context','colima-supabase-local','exec','supabase_db_local-app','pg_dump',
 '-U','postgres','-d','postgres','--schema-only','--no-owner','--no-privileges','--schema=app','--schema=private'],{maxBuffer:16*1024*1024,timeout:30000});
assert.equal(dump.status,0,'fixture_source_schema_unavailable');
const schema=dump.stdout.toString('utf8').split('\n').filter(line=>!line.startsWith('\\')).join('\n');
const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_initial_account_fixture'});
const bootstrap=new pg.Client({host:f.socket,port:f.port,database:'postgres',user:'fixture_bootstrap'}),custody=randomBytes(32),pepper=randomBytes(32);
let c,observer;let checks=0,phase='setup';
try{
 await bootstrap.connect();await bootstrap.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS;CREATE ROLE anon;CREATE ROLE authenticated;
  CREATE ROLE service_role;CREATE ROLE collect_runtime;CREATE ROLE collect_importer`);
 await bootstrap.query('CREATE DATABASE collect_transfer_schema_fixture OWNER postgres');
 c=new pg.Client({host:f.socket,port:f.port,database:'collect_transfer_schema_fixture',user:'postgres'});await c.connect();
 observer=new pg.Client({host:f.socket,port:f.port,database:'collect_transfer_schema_fixture',user:'fixture_bootstrap'});await observer.connect();
 await c.query('CREATE SCHEMA auth;CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,email_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz)');
 await c.query(schema);await c.query("SET row_security=on;SET TIME ZONE 'UTC'");
 await c.query(await readFile(new URL('./lineage.sql',import.meta.url),'utf8'));
 const fenceOp=randomUUID(),primary=randomUUID(),authId=randomUUID(),adminId=randomUUID(),src='a'.repeat(64);
 await c.query(`INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id)
  VALUES(true,'rrlduytparvsjfmegalh','dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',$1,1,'fenced',$2)`,[src,fenceOp]);
 const used=new Set(capture.snapshot.tables['app.users'].map(r=>r.public_id));let alias=100000;while(used.has(String(alias)))alias++;
 let primaryPublic=alias+1;while(used.has(String(primaryPublic)))primaryPublic++;
 const graphOperation=randomUUID(),targetUsers=[{id:primary,phone:null,email:null,public_id:String(primaryPublic)}];
 const verifiedTargetObjects=Object.fromEntries(capture.snapshot.tables['private.storage_objects'].map(o=>[o.object_key,{sha256:o.sha256,size:o.size,etag:'synthetic-etag'}]));
 const plan=compileTransfer({snapshot:capture.snapshot,sourceCatalog:capture.sourceCatalog,targetCatalog:capture.sourceCatalog,targetUsers,
  sourceOwnerId:capture.sourceOwnerId,cloudPrimaryId:primary,aliasPublicId:String(alias),operationId:graphOperation,custodyKey:custody,
  expectedSourceHmac:sourceSnapshotHmac(capture.snapshot,custody,graphOperation),verifiedTargetObjects});
 phase='import';await rehearseMaintenance(c,{operationId:graphOperation,fenceOperationId:fenceOp,epoch:'1',sourceSha256:src},async db=>{
  await db.query('INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES($1,$2,$3,$3)',[primary,String(primaryPublic),'2026-01-01T00:00:00.000Z']);
  await db.query("INSERT INTO auth.users(id,email,email_confirmed_at) VALUES($1,'synthetic@example.invalid',now())",[authId]);
  await db.query("INSERT INTO private.collect_owner_identity(operation_id,admin_user_id,principal_user_id,owner_email,approval_reference) VALUES($1,$2,$3,'synthetic@example.invalid','fixture owner approval')",[randomUUID(),adminId,primary]);
  await db.query("INSERT INTO app.admin_users(id,email,role,status,display_name,password_hash,created_at,updated_at) VALUES($1,'synthetic@example.invalid','owner','active','Synthetic','fixture-password-hash',1,1)",[adminId]);
  await db.query("INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES($1,$2,$2,'2026-01-01')",[adminId,primary]);
  await db.query("INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES($1,$2,'synthetic-proof')",[authId,primary]);
  for(const cmd of plan.commands){if(cmd.context)await db.query("SELECT set_config('burimunsi.collection_id',$1,true)",[cmd.context.collectionId]);await db.query(cmd.sql,cmd.params);}
 },async db=>(await db.query('SELECT count(*)::int n FROM private.collect_imported_native_history')).rows[0].n===plan.summary.sms);
 const accounts=capture.snapshot.tables['private.burimunsi_accounts'],admin=accounts.find(x=>x.principal_user_id===capture.sourceOwnerId&&x.role==='admin'),
  staff=accounts.find(x=>x.role==='staff'&&x.collection_id===admin?.collection_id);
 assert(admin&&staff&&accounts.filter(x=>x.role==='staff'&&x.collection_id===admin.collection_id).length===1);
 const pepperText=pepper.toString('base64'),pepperId='synthetic-pepper',cloudRows=[{name:'BURIMUNSI_PIN_PEPPER_BASE64',value:sha(pepperText)},
  {name:'BURIMUNSI_PIN_PEPPER_ID',value:sha(pepperId)}];
 async function prepared(op,adminPhone=admin.phone){return prepareInitialBootstrap({operationId:op,fenceOperationId:fenceOp,epoch:1,
  sourceSha256:src,authorizationSha256:'b'.repeat(64),ownerPrincipalId:primary,collectionId:admin.collection_id,
  adminAccountId:admin.id,staffAccountId:staff.id,adminPhone,staffPhone:staff.phone,adminPin:'4321',staffPin:'4321'},
  {cloudRows,pepperRecord:{pepper:pepperText,pepperId}});}
 async function execute(op,input){return rehearseBootstrapMaintenance(c,{operationId:op,fenceOperationId:fenceOp,epoch:'1',sourceSha256:src},input);}
 phase='negative';const wrongOp=randomUUID(),wrong=await prepared(wrongOp,'+250780000000');
 await assert.rejects(()=>execute(wrongOp,wrong),e=>e.message==='initial_account_bootstrap_failed');checks++;
 assert.equal((await observer.query('SELECT count(*)::int n FROM private.burimunsi_accounts WHERE active')).rows[0].n,0);checks++;
 phase='bootstrap';const op=randomUUID(),ready=await prepared(op);assert(!JSON.stringify(ready).includes('4321'));checks++;
 await execute(op,ready);checks++;
 const rows=(await observer.query('SELECT id::text,phone,pin_hash,active,role,principal_user_id FROM private.burimunsi_accounts ORDER BY role')).rows;
 assert.equal(rows.length,2);assert(rows.every(r=>r.active));checks++;
 const hasher=new PinHasher({pepper,pepperId});
 for(const row of rows){assert.equal(await hasher.verify(row.phone,'4321',row.pin_hash),true);assert.equal(await hasher.verify(row.phone,'1234',row.pin_hash),false);checks+=2;}
 const counts=(await observer.query(`SELECT (SELECT count(*)::int FROM private.burimunsi_operator_approvals WHERE active) approvals,
  (SELECT count(*)::int FROM private.burimunsi_native_staff_delegations WHERE active) delegations,
  (SELECT count(*)::int FROM app.audit_log WHERE action='burimunsi.migration.initial_accounts' AND actor_session_id IS NULL) audit,
  (SELECT count(*)::int FROM private.burimunsi_device_grants WHERE active) grants,
  (SELECT count(*)::int FROM private.burimunsi_sessions WHERE NOT revoked) sessions`)).rows[0];
 assert.deepEqual(counts,{approvals:1,delegations:1,audit:1,grants:0,sessions:0});checks++;
 const info=(await observer.query("SELECT count(*)::int n FROM pg_policy WHERE polname='collect_transfer_maintenance'")).rows[0].n;
 assert.equal(info,0);checks++;
 console.log(JSON.stringify({status:'PASS',checks,fixture:'source-schema-owned-socket-pg17',oldGrantsRevived:false,productionDispatched:false}));
}catch(error){const safe=(error?.message??'').match(/^(?:[a-z_]{2,100}|permission denied for (?:table|schema|function) [a-z_]+)$/)?.[0]??'redacted';
 const functions=[...(error?.where??'').matchAll(/PL\/pgSQL function ([a-z0-9_.]+)\(/g)].map(x=>x[1]).join(',');
 const clean=Error('initial_account_fixture_failed:'+phase+':'+safe+':'+functions+':'+(error?.schema??'')+':'+(error?.table??'')+':'+(error?.constraint??''));clean.code=error?.code;throw clean;}
finally{custody.fill(0);pepper.fill(0);await observer?.end().catch(()=>{});await c?.end().catch(()=>{});await bootstrap.end().catch(()=>{});const result=await f.close();assert.equal(result.removed,true);}
