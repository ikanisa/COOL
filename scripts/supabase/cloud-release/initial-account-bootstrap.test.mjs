// Test the reviewed bootstrap on a synthetic graph, entirely offline. The
// fixture supplies only its dependencies; bootstrap SQL is loaded and SHA
// checked by the real application helper. This is not a transfer rehearsal.
import assert from 'node:assert/strict';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {PinHasher} from '../../../supabase/functions/_shared/domain/burimunsi/pin.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {prepareInitialBootstrap,applyInitialBootstrapInFencedTransaction} from './initial-account-bootstrap.mjs';

const sha=x=>createHash('sha256').update(x).digest('hex');

// Synthetic dependency graph for the initial-account bootstrap test only.
// Exact table/function statements are loaded from checked-in migrations. Minimal
// evidence-anchor tables stand in for unrelated SMS/storage/transfer graphs;
// they are not a transfer rehearsal and contain no captured business data.
const migrations = new URL('../../../supabase/migrations/', import.meta.url);
const lineage = new URL('../cloud-data-transfer/lineage.sql', import.meta.url);
async function source(file) { return readFile(new URL(file, migrations), 'utf8'); }
function statement(text, head) {
  const start = text.indexOf(head);
  if (start < 0 || text.indexOf(head, start + head.length) >= 0) throw Error('fixture_source_statement_missing_or_ambiguous');
  const end = text.indexOf(';', start);
  if (end < 0) throw Error('fixture_source_statement_incomplete');
  return text.slice(start, end + 1);
}
function fn(text, name) {
  const pattern = new RegExp(`CREATE (?:OR REPLACE )?FUNCTION private\\.${name}\\(`, 'g');
  const matches = [...text.matchAll(pattern)];
  if (matches.length !== 1) throw Error('fixture_source_function_missing_or_ambiguous');
  const start = matches[0].index;
  const marker = text.indexOf('$fn$', start);
  const end = text.indexOf('$fn$;', marker + 4);
  if (marker < 0 || end < 0) throw Error('fixture_source_function_incomplete');
  return text.slice(start, end + 5);
}
async function installInitialAccountFixture(db) {
  const [base, native, pin, owner, fence, cloud, retirement, receipt, transfer] = await Promise.all([
    source('20261020134444_collect_curated_platform_baseline.sql'),
    source('20261109234517_burimunsi_native_operator_schema.sql'),
    source('20261110143000_burimunsi_native_phone_pin.sql'),
    source('20261111121400_collect_protected_owner_identity.sql'),
    source('20261022195747_collect_application_mutation_fence.sql'),
    source('20261117065536_collect_cloud_runtime_binding.sql'),
    source('20261117064828_collect_managed_executor_retirement.sql'),
    source('20261112200100_burimunsi_native_auto_transactions.sql'),
    readFile(lineage,'utf8'),
  ]);
  // The release qualification hashes this test file. Pin every extracted
  // migration too, so modified support bytes cannot silently change its result.
  const expected=[
    '0d943d17ddd92e809856831427cfc81b1264301dabdb867e1c90322d46b5a6f0',
    'c28ec95df7296052d911219c64a8a3d3fbbd60d77cfc222bd2f5de3590dfff2f',
    'bc2a6989b309258838966707548c588ff27bde6900c96d120b4d75e31c95d365',
    '8330530ee441825f4d06f4ba1d8664b81f50472502593c9d84592bd8cccded14',
    '714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497',
    'dbaf8ae6900c8da298a857d6710f71feda9f803f8afc8493d222b7366de51343',
    'af8317f31d9e92824114577c169bc0e99530384c3b6ee53724bf6cb1b5f22019',
    '50a995e709607c7fe794bb946e3f479ae1659a6a59633b93294f52bb0a9f54c8',
    'c20b8a8a0ae13498c285643ea8f284cf55c720ed5ba955048aebd48f988fae5c',
  ];
  if (![base,native,pin,owner,fence,cloud,retirement,receipt,transfer].every((v,i)=>sha(v)===expected[i]))
    throw Error('fixture_migration_source_changed');
  await db.query(`CREATE SCHEMA app; CREATE SCHEMA private; CREATE SCHEMA auth;
    CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,email_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz);
    CREATE TABLE app.sms_receipts(id text PRIMARY KEY);
    CREATE TABLE app.momo_transactions(id text PRIMARY KEY);
    CREATE TABLE private.burimunsi_unresolved_observations(source_id text PRIMARY KEY);
    -- Minimal stopped-evidence dependencies for the actual Cloud matcher.
    CREATE TABLE private.collect_fence_stopped_admissions(admission_id uuid,epoch bigint,source_sha256 text,kind text,project_ref text);
    CREATE TABLE private.collect_fence_local_stopped_admissions(admission_id uuid,epoch bigint,source_sha256 text,kind text,project_ref text);
    CREATE TABLE private.collect_managed_executor_retirements(admission_id uuid,epoch bigint,source_sha256 text,kind text);
    GRANT USAGE ON SCHEMA app,private,auth TO collect_runtime`);
  // The exact baseline definitions assume the app search path.
  const jsonValid = base.match(/CREATE FUNCTION app\.json_valid\(value text\)[^\n]+/);
  if (!jsonValid) throw Error('fixture_json_valid_missing');
  await db.query(jsonValid[0]);
  await db.query('SET search_path=app,pg_catalog');
  for (const name of ['users','collections','audit_log','admin_users','admin_principal_links','momo_receiving_accounts','momo_gateway_bindings']) {
    await db.query(statement(base, `CREATE TABLE ${name} (`));
  }
  // The protected owner migration removes this historical email constraint.
  await db.query('ALTER TABLE app.admin_users DROP CONSTRAINT admin_users_check');
  await db.query('SET search_path=pg_catalog');
  for (const name of ['auth_principal_links']) await db.query(statement(base,`CREATE TABLE private.${name} (`));
  for (const name of ['collect_fence_control','collect_fence_admissions']) await db.query(statement(fence,`CREATE TABLE private.${name}(`));
  for (const name of ['burimunsi_scopes','burimunsi_accounts','burimunsi_device_grants','burimunsi_device_accounts','burimunsi_sessions','burimunsi_operator_approvals']) {
    const prefix = name === 'burimunsi_operator_approvals' ? `CREATE TABLE private.${name}(` : `CREATE TABLE private.${name} (`;
    await db.query(statement(native,prefix));
  }
  await db.query(statement(pin,'CREATE TABLE private.burimunsi_native_staff_delegations('));
  await db.query(statement(receipt,'CREATE TABLE private.burimunsi_native_receipt_origins('));
  for (const name of ['collect_migration_actor_lineage','collect_imported_native_history']) await db.query(statement(transfer,`CREATE TABLE private.${name} (`));
  for (const name of ['collect_owner_id_valid','collect_owner_email_valid']) await db.query(fn(owner,name));
  await db.query(statement(owner,'CREATE TABLE private.collect_owner_identity('));
  for (const name of ['_collect_fence_operator','_collect_fence_require_operator','_collect_fence_require_runtime']) await db.query(fn(fence,name));
  await db.query(fn(retirement,'_collect_managed_retirement_matches'));
  await db.query(fn(cloud,'_collect_stopped_matches'));
  for (const name of ['collect_owner_binding','collect_owner_is']) await db.query(fn(owner,name));
  for (const name of ['burimunsi_pin_root_snapshot','burimunsi_pin_authority_snapshot','burimunsi_pin_account_version']) await db.query(fn(pin,name));
  await db.query(`CREATE TRIGGER burimunsi_pin_account_version BEFORE UPDATE ON private.burimunsi_accounts
      FOR EACH ROW EXECUTE FUNCTION private.burimunsi_pin_account_version();
    ALTER TABLE private.burimunsi_operator_approvals ENABLE ROW LEVEL SECURITY;
    ALTER TABLE private.burimunsi_operator_approvals FORCE ROW LEVEL SECURITY;
    ALTER TABLE private.burimunsi_native_staff_delegations ENABLE ROW LEVEL SECURITY;
    ALTER TABLE private.burimunsi_native_staff_delegations FORCE ROW LEVEL SECURITY;
    REVOKE ALL ON private.burimunsi_operator_approvals,private.burimunsi_native_staff_delegations FROM PUBLIC,collect_runtime;
    GRANT SELECT,UPDATE(lock_anchor) ON private.burimunsi_operator_approvals TO collect_runtime;
    CREATE POLICY burimunsi_scoped_runtime ON private.burimunsi_operator_approvals TO collect_runtime
      USING(collection_id=current_setting('burimunsi.collection_id',true))
      WITH CHECK(collection_id=current_setting('burimunsi.collection_id',true));
    CREATE POLICY burimunsi_pin_owner_frame ON private.burimunsi_native_staff_delegations TO postgres
      USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
        AND current_setting('burimunsi.pin_frame',true)='1')
      WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
        AND current_setting('burimunsi.pin_frame',true)='1');
    REVOKE ALL ON FUNCTION private.collect_owner_binding(),private.collect_owner_is(text,text,text),
      private.burimunsi_pin_root_snapshot(text,text,text,text,text[]),
      private.burimunsi_pin_authority_snapshot(text,text,text,text,text[]) FROM PUBLIC,collect_runtime`);
}

const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_initial_account_fixture'});
const bootstrap=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'fixture_bootstrap'});
const pepper=randomBytes(32); let c,observer,runtime,phase='setup',checks=0;
try {
  await bootstrap.connect();
  await bootstrap.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS; CREATE ROLE anon; CREATE ROLE authenticated;
    CREATE ROLE service_role; CREATE ROLE collect_runtime LOGIN NOSUPERUSER NOBYPASSRLS; CREATE ROLE collect_importer`);
  await bootstrap.query('CREATE DATABASE collect_transfer_schema_fixture OWNER postgres');
  const peer={host:fixture.socket,port:fixture.port,database:'collect_transfer_schema_fixture'};
  c=new pg.Client({...peer,user:'postgres'}); observer=new pg.Client({...peer,user:'fixture_bootstrap'});
  runtime=new pg.Client({...peer,user:'collect_runtime'});
  await Promise.all([c.connect(),observer.connect(),runtime.connect()]);
  await installInitialAccountFixture(c);
  await c.query("SET row_security=on; SET TIME ZONE 'UTC'");
  const ids=Object.fromEntries(['fence','owner','staff','legacy','auth','adminUser','adminAccount','staffAccount','grant','session','sourceOperation','request'].map(k=>[k,randomUUID()]));
  const collection='synthetic-collection',source='a'.repeat(64),phoneAdmin='+250780000001',phoneStaff='+250780000002';
  await c.query(`INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id)
    VALUES(true,'rrlduytparvsjfmegalh','dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',$1,1,'fenced',$2)`,[source,ids.fence]);
  await c.query(`INSERT INTO app.users(id,phone,public_id,created_at,updated_at) VALUES
    ($1,NULL,'900001','2026-01-01','2026-01-01'),($2,$4,'900002','2026-01-01','2026-01-01'),
    ($3,NULL,'900003','2026-01-01','2026-01-01')`,[ids.owner,ids.staff,ids.legacy,phoneStaff]);
  await c.query("INSERT INTO auth.users(id,email,email_confirmed_at) VALUES($1,'synthetic@example.invalid',now())",[ids.auth]);
  await c.query("INSERT INTO app.admin_users(id,email,role,status,display_name,password_hash,created_at,updated_at) VALUES($1,'synthetic@example.invalid','owner','active','Synthetic','fixture-only',1,1)",[ids.adminUser]);
  await c.query("INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES($1,$2,$2,'2026-01-01')",[ids.adminUser,ids.owner]);
  await c.query("INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES($1,$2,'fixture-proof')",[ids.auth,ids.owner]);
  await c.query("INSERT INTO private.collect_owner_identity(operation_id,admin_user_id,principal_user_id,owner_email,approval_reference) VALUES($1,$2,$3,'synthetic@example.invalid','fixture approval')",[randomUUID(),ids.adminUser,ids.owner]);
  await c.query("INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES($1,'synthetic',$2,'Synthetic','group','2026-01-01','2026-01-01')",[collection,ids.owner]);
  await c.query("INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,timezone,created_at) VALUES('synthetic-receiver','mtn_momo','fixture','Fixture',$1,'Africa/Kigali','2026-01-01')",['a'.repeat(64)]);
  await c.query("INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at) VALUES($1,'synthetic-receiver',true,1)",[collection]);
  await c.query(`INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,active,created_at,updated_at)
    VALUES($1,$3,$4,$6,'Synthetic Admin','admin',ARRAY['records.read'],'{}',false,1,1),
          ($2,$3,$5,$7,'Synthetic Staff','staff',ARRAY['records.read'],'{}',false,1,1)`,[ids.adminAccount,ids.staffAccount,collection,ids.owner,ids.staff,phoneAdmin,phoneStaff]);
  // Minimal, historical synthetic evidence ensures an old grant/session exists
  // and cannot be reactivated by bootstrap. It never represents a real person.
  await c.query(`INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,active,created_at)
    VALUES($1,$2,$3,$4,'staff',false,1)`,[ids.grant,collection,randomUUID(),'b'.repeat(64)]);
  await c.query(`INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,credential_version,grant_version,token_hash,created_at,expires_at,revoked)
    VALUES($1,$2,$3,$4,$5,1,1,$6,1,2,true)`,[ids.session,collection,ids.adminAccount,ids.grant,randomUUID(),'c'.repeat(64)]);
  await c.query("INSERT INTO app.sms_receipts VALUES('synthetic-source'); INSERT INTO private.burimunsi_unresolved_observations VALUES('synthetic-source')");
  await c.query(`INSERT INTO private.burimunsi_native_receipt_origins(source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,capture_session_id,admission_kind,request_id,fingerprint,body_sha256,object_sha256)
    VALUES('synthetic-source',$1,$2,$3,$4,$5,1,$6,'jobs',$7,$8,$8,$8)`,[collection,ids.adminAccount,ids.legacy,randomUUID(),ids.grant,ids.session,ids.request,'d'.repeat(64)]);
  await c.query(`INSERT INTO private.collect_migration_actor_lineage(source_actor_id,cloud_primary_id,operation_id,snapshot_hmac,envelope)
    VALUES($1,$2,$3,$4,'{"version":"1","algorithm":"AES-256-GCM","nonce":"fixture","ciphertext":"fixture","tag":"fixture"}')`,[ids.legacy,ids.owner,ids.sourceOperation,'e'.repeat(64)]);
  await c.query(`INSERT INTO private.collect_imported_native_history(source_id,collection_id,request_id,body_sha256,object_sha256,source_fingerprint,operation_id)
    VALUES('synthetic-source',$1,$2,$3,$3,$3,$4)`,[collection,ids.request,'f'.repeat(64),ids.sourceOperation]);
  const pepperText=pepper.toString('base64'),pepperId='synthetic-pepper',cloudRows=[{name:'BURIMUNSI_PIN_PEPPER_BASE64',value:sha(pepperText)},
    {name:'BURIMUNSI_PIN_PEPPER_ID',value:sha(pepperId)}];
  async function prepared(op,overrides={}) { return prepareInitialBootstrap({operationId:op,fenceOperationId:ids.fence,epoch:1,sourceSha256:source,
    authorizationSha256:'b'.repeat(64),ownerPrincipalId:ids.owner,collectionId:collection,adminAccountId:ids.adminAccount,
    staffAccountId:ids.staffAccount,adminPhone:phoneAdmin,staffPhone:phoneStaff,adminPin:'4321',staffPin:'4321',...overrides},
    {cloudRows,pepperRecord:{pepper:pepperText,pepperId}}); }
  async function execute(op,input,{locks=true,client=c}={}) {
    await client.query('BEGIN');
    try {
      if(locks) await client.query('SELECT pg_advisory_xact_lock(7346371,1),pg_advisory_xact_lock(7346371,2)');
      await client.query("SELECT set_config('collect.graph_import_operation',$1,true)",[op]);
      if(client===c) for(const rel of ['private.burimunsi_operator_approvals','private.burimunsi_native_staff_delegations']) {
        await client.query(`LOCK TABLE ${rel} IN ACCESS EXCLUSIVE MODE`);
        await client.query(`CREATE POLICY collect_transfer_maintenance ON ${rel} TO postgres USING
          (session_user='postgres' AND current_setting('collect.graph_import_operation',true)='${op}') WITH CHECK
          (session_user='postgres' AND current_setting('collect.graph_import_operation',true)='${op}')`);
      }
      await applyInitialBootstrapInFencedTransaction(client,input);
      if(client===c) for(const rel of ['private.burimunsi_operator_approvals','private.burimunsi_native_staff_delegations'])
        await client.query(`DROP POLICY collect_transfer_maintenance ON ${rel}`);
      await client.query('COMMIT');
    } catch(e) { await client.query('ROLLBACK'); throw e; }
  }
  async function rejected(label,options={},overrides={},code='55000') {
    phase=label; const op=randomUUID(),input=await prepared(op,overrides);
    await assert.rejects(()=>execute(op,input,options),e=>e.message==='initial_account_bootstrap_failed' && e.code===code);
    assert.equal((await observer.query('SELECT count(*)::int n FROM private.burimunsi_accounts WHERE active')).rows[0].n,0);
    checks+=2;
  }
  await rejected('wrong-phone',{}, {adminPhone:'+250780000003'});
  await rejected('wrong-owner',{}, {ownerPrincipalId:randomUUID()});
  await rejected('wrong-fence',{}, {fenceOperationId:randomUUID()});
  await rejected('missing-locks',{locks:false});
  await rejected('wrong-role',{client:runtime});
  phase='malformed-pin-hash';
  const badOp=randomUUID(),badPinHash=await prepared(badOp);
  badPinHash.row().adminPinHash.iterations=1;
  await assert.rejects(()=>execute(badOp,badPinHash),e=>e.message==='initial_account_bootstrap_failed' && e.code==='55000');
  assert.equal((await observer.query('SELECT count(*)::int n FROM private.burimunsi_accounts WHERE active')).rows[0].n,0);checks+=2;
  phase='runtime-permissions';
  assert.equal((await runtime.query('SELECT count(*)::int n FROM private.burimunsi_operator_approvals')).rows[0].n,0);checks++;
  await assert.rejects(()=>runtime.query('INSERT INTO private.burimunsi_operator_approvals DEFAULT VALUES'),e=>e.code==='42501');checks++;
  await assert.rejects(()=>runtime.query('SELECT private.collect_owner_binding()'),e=>e.code==='42501');checks++;
  await observer.query("UPDATE auth.users SET email_confirmed_at=NULL WHERE id=$1",[ids.auth]);
  await rejected('unverified-owner',{}, {},'P0002');
  await observer.query('UPDATE auth.users SET email_confirmed_at=now() WHERE id=$1',[ids.auth]);
  const admission=randomUUID();
  await observer.query("INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state) VALUES($1,1,$2,'jobs','active')",[admission,source]);
  await rejected('unresolved-admission');
  await observer.query('DELETE FROM private.collect_fence_admissions WHERE admission_id=$1',[admission]);
  // Force authority to disappear after both account updates. The production
  // postcondition must reject and PostgreSQL must roll back every write.
  phase='atomic-rollback';
  await c.query(`CREATE FUNCTION pg_temp.fixture_interrupt_authority() RETURNS trigger LANGUAGE plpgsql AS $fn$
    BEGIN UPDATE auth.users SET email_confirmed_at=NULL; RETURN NEW; END $fn$;
    CREATE TRIGGER fixture_interrupt_authority AFTER INSERT ON private.burimunsi_native_staff_delegations
      FOR EACH ROW EXECUTE FUNCTION pg_temp.fixture_interrupt_authority()`);
  await rejected('lost-authority-after-writes');
  const rolledBack=(await observer.query(`SELECT
    (SELECT count(*)::int FROM private.burimunsi_operator_approvals) approvals,
    (SELECT count(*)::int FROM private.burimunsi_native_staff_delegations) delegations,
    (SELECT count(*)::int FROM app.audit_log) audit,
    (SELECT count(*)::int FROM auth.users WHERE email_confirmed_at IS NOT NULL) confirmed`)).rows[0];
  assert.deepEqual(rolledBack,{approvals:0,delegations:0,audit:0,confirmed:1});checks++;
  await c.query('DROP TRIGGER fixture_interrupt_authority ON private.burimunsi_native_staff_delegations');
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
  assert.equal((await observer.query("SELECT count(*)::int n FROM pg_policy WHERE polname='collect_transfer_maintenance'")).rows[0].n,0);checks++;
  assert.equal((await runtime.query('SELECT count(*)::int n FROM private.burimunsi_operator_approvals')).rows[0].n,0);
  await runtime.query("SELECT set_config('burimunsi.collection_id',$1,false)",[collection]);
  assert.equal((await runtime.query('SELECT count(*)::int n FROM private.burimunsi_operator_approvals')).rows[0].n,1);checks+=2;
  phase='authority';
  await c.query('BEGIN');
  try {
    for (const rel of ['private.burimunsi_operator_approvals','private.burimunsi_native_staff_delegations'])
      await c.query(`CREATE POLICY fixture_authority_check ON ${rel} TO postgres USING(true)`);
    const authority=(await c.query(`SELECT
      private.burimunsi_pin_authority_snapshot($1,$2,$3,'admin',ARRAY['records.read']) IS NOT NULL admin_allowed,
      private.burimunsi_pin_authority_snapshot($1,$2,$4,'admin',ARRAY['records.read']) IS NULL wrong_phone_denied,
      private.burimunsi_pin_authority_snapshot($1,$5,$4,'staff',ARRAY['records.read']) IS NOT NULL staff_allowed,
      private.burimunsi_pin_authority_snapshot($1,$5,$4,'staff',ARRAY['records.read','gateway.manage']) IS NULL staff_escalation_denied`,
      [collection,ids.owner,phoneAdmin,phoneStaff,ids.staff])).rows[0];
    assert.deepEqual(authority,{admin_allowed:true,wrong_phone_denied:true,staff_allowed:true,staff_escalation_denied:true});checks+=4;
  } finally { await c.query('ROLLBACK'); }
  phase='replay';const repeatOp=randomUUID(),repeat=await prepared(repeatOp);
  await assert.rejects(()=>execute(repeatOp,repeat),e=>e.message==='initial_account_bootstrap_failed' && e.code==='55000');checks++;
  console.log(JSON.stringify({status:'PASS',checks,fixture:'synthetic-production-shaped-socket-pg17',oldGrantsRevived:false,productionDispatched:false}));
} catch(error) {
  const safe=(error?.message??'').match(/^(?:[a-z_]{2,100}|permission denied for (?:table|schema|function) [a-z_]+)$/)?.[0]??'redacted';
  const functions=[...(error?.where??'').matchAll(/PL\/pgSQL function ([a-z0-9_.]+)\(/g)].map(x=>x[1]).join(',');
  const clean=Error('initial_account_fixture_failed:'+phase+':'+safe+':'+functions+':'+(error?.schema??'')+':'+(error?.table??'')+':'+(error?.constraint??''));clean.code=error?.code;throw clean;
} finally {
  pepper.fill(0);await runtime?.end().catch(()=>{});await observer?.end().catch(()=>{});await c?.end().catch(()=>{});await bootstrap.end().catch(()=>{});
  const result=await fixture.close();assert.equal(result.removed,true);
}
