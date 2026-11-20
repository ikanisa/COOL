import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';

test('historical markers are immutable, visible to runtime, and checked at commit', {timeout:120000}, async () => {
  const f = await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_lineage_fixture'});
  const client = new pg.Client({host:f.socket,port:f.port,database:'postgres',user:'fixture_bootstrap'});
  await client.connect();
  try {
    await client.query(`CREATE ROLE postgres NOSUPERUSER NOBYPASSRLS;
      CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
      CREATE ROLE collect_runtime; CREATE ROLE collect_importer;
      CREATE SCHEMA app AUTHORIZATION postgres; CREATE SCHEMA private AUTHORIZATION postgres;
      GRANT USAGE ON SCHEMA private TO collect_runtime; SET ROLE postgres;
      CREATE TABLE app.users(id text PRIMARY KEY);
      CREATE TABLE private.burimunsi_scopes(collection_id text PRIMARY KEY);
      CREATE TABLE app.momo_transactions(id text PRIMARY KEY);
      CREATE TABLE private.burimunsi_native_receipt_origins(source_id text PRIMARY KEY,collection_id text,
        request_id uuid,body_sha256 text,object_sha256 text,fingerprint text,principal_user_id text);
      CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text PRIMARY KEY,collection_id text,source_fingerprint text,transaction_id text);
      CREATE TABLE app.sms_receipts(id text PRIMARY KEY,owner_user_id text,client_envelope_id text,body_sha256 text,
        object_sha256 text,object_key text,originating_session_id text,receiver_hash text,evidence_level text);`);
    await client.query(await readFile(new URL('./lineage.sql',import.meta.url),'utf8'));
    const request='2f6d281a-21ab-45ba-8299-fda59d00e272', op='35f55737-73de-4adc-b46a-c024c50270d4';
    const a='a'.repeat(64), b='b'.repeat(64), c='c'.repeat(64);
    await client.query("INSERT INTO app.users VALUES('old'),('cloud'); INSERT INTO private.burimunsi_scopes VALUES('group'); INSERT INTO app.momo_transactions VALUES('transaction')");
    await client.query("INSERT INTO private.burimunsi_native_receipt_origins VALUES('source','group',$1,$2,$3,$4,'old')",[request,a,b,c]);
    await client.query("INSERT INTO private.burimunsi_auto_sms_jobs VALUES('source','group',$1,'transaction')",[c]);
    await client.query("INSERT INTO app.sms_receipts VALUES('source','old',$1::text,$2,$3,'sms/source',NULL,NULL,'client_received')",[request,a,b]);
    await client.query('BEGIN');
    await client.query(`INSERT INTO private.collect_imported_native_history
      (source_id,collection_id,request_id,transaction_id,body_sha256,object_sha256,source_fingerprint,operation_id) VALUES('source','group',$1,'transaction',$2,$3,$4,$5)`,[request,a,b,c,op]);
    await client.query(`INSERT INTO private.collect_migration_actor_lineage(source_actor_id,cloud_primary_id,operation_id,snapshot_hmac,envelope)
      VALUES('old','cloud',$1,$2,'{"version":1,"algorithm":"AES-256-GCM","nonce":"n","ciphertext":"c","tag":"t"}')`,[op,a]);
    await client.query(`INSERT INTO private.collect_migration_import_receipts
      (operation_id,source_actor_id,cloud_primary_id,snapshot_hmac,object_proof_hmac,counts)
      VALUES($1,'old','cloud',$2,$3,'{"objects":48}')`,[op,a,b]);
    await client.query('COMMIT');
    assert.equal((await client.query('SELECT count(*)::int n FROM private.collect_imported_native_history')).rows[0].n,1);
    await assert.rejects(client.query("UPDATE private.collect_imported_native_history SET body_sha256=repeat('d',64)"),/imported_native_history_immutable/);
    await assert.rejects(client.query('DELETE FROM private.collect_migration_actor_lineage'),/migration_actor_lineage_immutable/);
    await assert.rejects(client.query('DELETE FROM private.collect_migration_import_receipts'),/migration_import_receipts_immutable/);
    await client.query('RESET ROLE; SET ROLE collect_runtime');
    assert.equal((await client.query('SELECT count(*)::int n FROM private.collect_imported_native_history')).rows[0].n,1);
    await assert.rejects(client.query('DELETE FROM private.collect_imported_native_history'),/permission denied/);
    await assert.rejects(client.query('SELECT * FROM private.collect_migration_actor_lineage'),/permission denied/);
    await assert.rejects(client.query('SELECT * FROM private.collect_migration_import_receipts'),/permission denied/);
    await client.query('RESET ROLE; SET ROLE postgres');
    await client.query("INSERT INTO private.burimunsi_native_receipt_origins VALUES('bad','group',$1,$2,$3,$4,'old')",[request,a,b,c]);
    await client.query("INSERT INTO private.burimunsi_auto_sms_jobs VALUES('bad','group',$1,'transaction')",[c]);
    await client.query("INSERT INTO app.sms_receipts VALUES('bad','old',$1::text,$2,$3,'sms/bad',NULL,NULL,'client_received')",[request,a,b]);
    await client.query('BEGIN');
    await client.query(`INSERT INTO private.collect_imported_native_history
      (source_id,collection_id,request_id,transaction_id,body_sha256,object_sha256,source_fingerprint,operation_id) VALUES('bad','group',$1,'transaction',$2,$3,$4,$5)`,[request,a,b,'d'.repeat(64),op]);
    await assert.rejects(client.query('COMMIT'),/imported_native_history_mismatch/);
    assert.equal((await client.query('SELECT count(*)::int n FROM private.collect_imported_native_history')).rows[0].n,1);
  } finally { await client.end().catch(()=>{}); await f.close(); }
});
