import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {rehearseMaintenance} from './maintenance.mjs';

test('actual source schema keeps always-on fence and restores owner policies after rehearsal', {timeout:120000}, async () => {
  // The dump contains schema definitions only; no source rows or credentials.
  const dump=spawnSync('docker',['--context','colima-supabase-local','exec','supabase_db_local-app','pg_dump',
    '-U','postgres','-d','postgres','--schema-only','--no-owner','--no-privileges','--schema=app','--schema=private'],{maxBuffer:16*1024*1024,timeout:30000});
  assert.equal(dump.status,0,'schema-only source capture unavailable');
  const schema=dump.stdout.toString('utf8').split('\n').filter(line=>!line.startsWith('\\')).join('\n');
  const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_transfer_schema_fixture'});
  const bootstrap=new pg.Client({host:f.socket,port:f.port,database:'postgres',user:'fixture_bootstrap'});
  let client;
  try {
    await bootstrap.connect();
    await bootstrap.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS; CREATE ROLE anon; CREATE ROLE authenticated;
      CREATE ROLE service_role; CREATE ROLE collect_runtime; CREATE ROLE collect_importer;`);
    await bootstrap.query('CREATE DATABASE collect_transfer_schema_fixture OWNER postgres');
    client=new pg.Client({host:f.socket,port:f.port,database:'collect_transfer_schema_fixture',user:'postgres'}); await client.connect();
    await client.query('CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY)');
    await client.query(schema);
    await client.query('SET row_security=on');
    const op='398d98d7-18a8-4cba-89ba-f7b01632b1b6',fenceOp='c9cf1edc-2c63-4e46-9d6f-d1537f9c7416',src='a'.repeat(64);
    await client.query(`INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id)
      VALUES(true,'rrlduytparvsjfmegalh','dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',$1,1,'fenced',$2)`,[src,fenceOp]);
    await assert.rejects(client.query("INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES('outside','123456','2026-01-01','2026-01-01')"),/collect_fence_closed/);
    const identity={operationId:op,fenceOperationId:fenceOp,epoch:'1',sourceSha256:src};
    const result=await rehearseMaintenance(client,identity,async c=>{
      await c.query("INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES('historical','234567','2026-01-01','2026-01-01')");
    },async c=>(await c.query("SELECT count(*)::int n FROM app.users WHERE id='historical'")).rows[0].n===1);
    assert.equal(result.guardAndPoliciesRestored,true);
    await assert.rejects(client.query("INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES('after','345678','2026-01-01','2026-01-01')"),/collect_fence_closed/);
    await assert.rejects(rehearseMaintenance(client,{...identity,epoch:'2'},async()=>{},async()=>true),/target_fence_changed/);
  } finally { await client?.end().catch(()=>{}); await bootstrap.end().catch(()=>{}); await f.close(); }
});
