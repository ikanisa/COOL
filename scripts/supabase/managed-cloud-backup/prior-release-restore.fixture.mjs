// Local rehearsal only. Every database, private object and identity is created by this fixture.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createDecipheriv, createHash, randomBytes, randomUUID } from 'node:crypto';
import { closeSync } from 'node:fs';
import { copyFile, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import pg from '../node_modules/pg/lib/index.js';
import { decrypt, encrypt } from '../../../supabase/functions/_shared/domain/encryption.js';
import { PostgresStorageJournal } from '../../../supabase/functions/_shared/storage/postgres-journal.js';
import { canonical, ProtectedStorageProtocol } from '../../../supabase/functions/_shared/storage/protocol.js';
import { startOwnedPg17 } from '../current-pg-transfer/test-support/owned-pg17.mjs';
import { FORMAT, planDigest, transferObject } from '../current-pg-transfer/object-transfer/transfer.mjs';
import {
  EXACT_CURRENT16,
  loadReviewedPlatformFixture,
  renderSyntheticSql,
} from '../testing/curated-platform-fixture.mjs';
import { createSyntheticEncryptedBackup, inspectSyntheticEncryptedBackup } from './synthetic-backup.mjs';

const repository = new URL('../../../', import.meta.url);
const sourceBytes = (path) => readFile(new URL(path, repository));
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
const json = (value) => Buffer.from(JSON.stringify(value));
const uid = 'a1000000-0000-4000-8000-000000000001';
const otherUid = 'a1000000-0000-4000-8000-000000000002';
const objectId = 'a2000000-0000-4000-8000-000000000001';
const bucket = 'collect-private-evidence', key = 'synthetic/payment-evidence';
const namespace = { origin: 'https://127.0.0.1:31001', bucket };
const roleNames = ['anon', 'authenticated', 'collect_importer', 'collect_runtime', 'postgres'];
const baseline = 'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';

async function reviewedInputs(root) {
  const staged = join(root, 'reviewed-release');
  await mkdir(join(staged, 'supabase/migrations'), { recursive: true });
  await mkdir(join(staged, 'supabase/tests/sql'), { recursive: true });
  for (const name of EXACT_CURRENT16) {
    await copyFile(new URL('supabase/migrations/' + name, repository), join(staged, 'supabase/migrations', name));
  }
  const auth = 'supabase/tests/sql/00_local_auth_fixture.sql';
  await copyFile(new URL(auth, repository), join(staged, auth));
  return loadReviewedPlatformFixture(staged, { includeStoppedAdmissionLifecycleMigration: true });
}

async function connect(fixture, database, user = 'collect_test') {
  const client = new pg.Client({
    host: fixture.socket,
    port: fixture.port,
    database,
    user,
    connectionTimeoutMillis: 5000,
  });
  await client.connect();
  const identity = (await client.query(
    "SELECT inet_server_addr() IS NULL AS socket, current_database() AS db, current_setting('cluster_name') AS name",
  )).rows[0];
  assert.deepEqual(identity, { socket: true, db: database, name: fixture.clusterName });
  return client;
}

async function initializeBootstrapRole(fixture) {
  // The reviewed Realtime fixture includes the original role grantor in its
  // catalog hash. Establish that same bootstrap identity on each empty peer.
  const bootstrap = await connect(fixture, 'postgres', fixture.initialUser);
  try {
    await bootstrap.query('CREATE ROLE fixture_custodian LOGIN SUPERUSER');
  } finally {
    await bootstrap.end();
  }
  const custodian = await connect(fixture, 'postgres', 'fixture_custodian');
  try {
    await custodian.query('ALTER ROLE fixture_bootstrap RENAME TO collect_test');
  } finally {
    await custodian.end();
  }
  const admin = await connect(fixture, 'postgres');
  try {
    await admin.query('DROP ROLE fixture_custodian');
  } finally {
    await admin.end();
  }
}

async function roles(db) {
  const profiles = (await db.query(
    `SELECT rolname,rolinherit,rolcanlogin,rolsuper,rolbypassrls,rolcreaterole,rolcreatedb,rolreplication
    FROM pg_roles WHERE rolname=ANY($1) ORDER BY rolname`,
    [roleNames],
  )).rows;
  const membership = (await db.query(
    `SELECT r.rolname AS granted,m.rolname AS member,pg_get_userbyid(a.grantor) AS grantor,a.admin_option,a.inherit_option,a.set_option
    FROM pg_auth_members a JOIN pg_roles r ON r.oid=a.roleid JOIN pg_roles m ON m.oid=a.member
    WHERE m.rolname=ANY($1) ORDER BY r.rolname,m.rolname`,
    [roleNames],
  )).rows;
  return { profiles, membership };
}

async function restoreRoles(db, snapshot) {
  assert.deepEqual(snapshot.profiles.map((row) => row.rolname), roleNames);
  for (const r of snapshot.profiles) {
    assert.equal(
      r.rolcanlogin || r.rolsuper || r.rolbypassrls || r.rolcreaterole || r.rolcreatedb || r.rolreplication,
      false,
    );
    await db.query(
      `CREATE ROLE ${r.rolname} NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOREPLICATION ${
        r.rolinherit ? 'INHERIT' : 'NOINHERIT'
      }`,
    );
  }
  assert.deepEqual(snapshot.membership, [{
    granted: 'collect_runtime',
    member: 'postgres',
    grantor: 'collect_test',
    admin_option: false,
    inherit_option: false,
    set_option: true,
  }]);
  await db.query('GRANT collect_runtime TO postgres WITH ADMIN FALSE, INHERIT FALSE, SET TRUE');
  assert.deepEqual(await roles(db), snapshot);
}

async function seed(db, inputs, cipher, plain, journal, sourcePath, keyId, aad) {
  await db.query(inputs.auth);
  for (const step of inputs.rawMigrations.slice(0, 8)) await db.query(step.sql);
  await db.query(`CREATE SCHEMA storage;
    CREATE TABLE storage.buckets(id text PRIMARY KEY, public boolean NOT NULL);
    CREATE TABLE storage.objects(id uuid PRIMARY KEY, bucket_id text REFERENCES storage.buckets, name text, owner_id uuid REFERENCES auth.users,
      version text NOT NULL, ciphertext_sha256 text NOT NULL, size_bytes integer NOT NULL, UNIQUE(bucket_id,name));
    ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
    CREATE POLICY private_owner_read ON storage.objects FOR SELECT TO authenticated USING (owner_id::text=current_setting('request.jwt.claims',true)::jsonb->>'sub');
    GRANT USAGE ON SCHEMA storage TO authenticated; GRANT SELECT ON storage.objects TO authenticated;
    CREATE SCHEMA supabase_migrations;
    CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY, name text NOT NULL, statements text[] NOT NULL)`);
  await db.query('BEGIN');
  await db.query('INSERT INTO auth.users(id,email) VALUES($1,$2),($3,$4)', [
    uid,
    'owner@example.invalid',
    otherUid,
    'other@example.invalid',
  ]);
  await db.query(
    "INSERT INTO app.users(id,email,public_id,created_at,updated_at) VALUES('fixture-owner','owner@example.invalid','fixture-public','2026-01-01','2026-01-01')",
  );
  await db.query(
    "INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES($1,'fixture-owner','synthetic-proof')",
    [uid],
  );
  await db.query(
    "INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES('fixture-group','fixture-group','fixture-owner','Fixture','group','2026-01-01','2026-01-01')",
  );
  await db.query('INSERT INTO storage.buckets VALUES($1,false)', [bucket]);
  await db.query("INSERT INTO storage.objects VALUES($1,$2,$3,$4,'fixture-version', $5,$6)", [
    objectId,
    bucket,
    key,
    uid,
    sha(cipher),
    cipher.length,
  ]);
  const scope = { ownerId: 'fixture-owner', entityId: 'fixture-evidence', purpose: 'payment_evidence' };
  const httpMetadata = { contentType: 'application/octet-stream' },
    customMetadata = { sha256: sha(plain), key_id: keyId };
  const descriptor = {
    scope,
    aad,
    keyId,
    plaintextSha256: sha(plain),
    requestDigest: sha('synthetic payment request'),
    httpMetadata,
    customMetadata,
  };
  const fingerprint = sha(canonical(descriptor));
  await db.query(
    `INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
    VALUES($1,$2,$3,$4,$5,$6,$7)`,
    [key, fingerprint, scope, aad, keyId, sha(plain), cipher.toString('utf8')],
  );
  await db.query('COMMIT');
  const transport = {
    async uploadImmutable(objectKey, bytes) {
      assert.equal(objectKey, key);
      await writeFile(sourcePath, bytes, { flag: 'wx', mode: 0o600 });
      return { status: 201 };
    },
    async probe(objectKey) {
      assert.equal(objectKey, key);
      return { headStatus: 200, getStatus: 200, etag: 'fixture-version', bytes: await readFile(sourcePath) };
    },
  };
  const protocol = new ProtectedStorageProtocol({ transport, journal });
  const receipt = await protocol.put(key, cipher, {
    scope,
    httpMetadata,
    customMetadata: { ...customMetadata, source_fingerprint: fingerprint },
  });
  assert.equal(receipt.metadataCommitted, true);
  assert.equal(receipt.sha256, sha(cipher));
  await db.query('BEGIN');
  await db.query(
    `INSERT INTO app.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,observed_at,created_at)
    VALUES('fixture-evidence','fixture-group','fixture-owner',$1,$2,$3,'application/octet-stream','operator_recorded','2026-01-01','2026-01-01')`,
    [key, sha(plain), plain.length],
  );
  await db.query(`INSERT INTO app.payments(id,collection_id,evidence_id,amount_minor,status,created_at)
    VALUES('fixture-payment','fixture-group','fixture-evidence',7250,'recorded','2026-01-01');
    INSERT INTO app.ledger_entries(id,payment_id,collection_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at)
    VALUES('fixture-entry','fixture-payment','fixture-group',7250,'contribution','fixture-evidence','fixture-owner','fixture-request','2026-01-01')`);
  await db.query('COMMIT');
  await db.query(inputs.rawMigrations[8].sql);
  for (const step of inputs.rawMigrations.slice(0, 9)) {
    await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2,ARRAY[$3::text])', [
      step.name.slice(0, 14),
      step.name,
      step.sql,
    ]);
  }
  const release = sha(json(inputs.rawMigrations.slice(0, 9).map((step) => [step.name, step.sha256])));
  await db.query('SELECT private.collect_fence_initialize($1,$2,$3)', [randomUUID(), release, baseline]);
  const operation = randomUUID();
  await db.query('SELECT private.collect_fence_begin_quiesce($1,1,$2)', [operation, release]);
  await db.query('SELECT private.collect_fence_drain($1,1,$2)', [operation, release]);
}

async function observation(db) {
  const point =
    (await db.query('SELECT operation_id,epoch,mode,source_sha256 FROM private.collect_fence_control WHERE singleton'))
      .rows[0];
  assert.equal(point.mode, 'fenced');
  const money = (await db.query(
    `SELECT (SELECT count(*)::int FROM app.payments) payments,(SELECT sum(amount_minor)::text FROM app.payments) payment_minor,
    (SELECT min(currency) FROM app.payments) currency,
    (SELECT count(*)::int FROM app.ledger_entries) entries,(SELECT sum(amount_minor)::text FROM app.ledger_entries) ledger_minor,
    (SELECT count(*)::int FROM app.payment_evidence) evidence,(SELECT count(*)::int FROM auth.users) auth_users`,
  )).rows[0];
  const identities =
    (await db.query(`SELECT a.id,a.email,l.user_id FROM auth.users a LEFT JOIN private.auth_principal_links l
    ON l.auth_user_id=a.id ORDER BY a.id`)).rows;
  assert.deepEqual(identities, [
    { id: uid, email: 'owner@example.invalid', user_id: 'fixture-owner' },
    { id: otherUid, email: 'other@example.invalid', user_id: null },
  ]);
  const object = (await db.query(
    `SELECT o.id,o.bucket_id,o.name,o.owner_id,o.version,o.ciphertext_sha256,o.size_bytes,b.public,e.object_sha256 AS plain_sha256,
    r.aad,r.key_id, r.sealed_body IS NULL AND r.cleared_at IS NOT NULL AS reservation_cleared, i.operation_id
    FROM storage.objects o JOIN storage.buckets b ON b.id=o.bucket_id JOIN auth.users a ON a.id=o.owner_id
    JOIN private.auth_principal_links l ON l.auth_user_id=a.id JOIN app.payment_evidence e ON e.owner_user_id=l.user_id AND e.object_key=o.name
    JOIN private.storage_objects s ON s.object_key=o.name AND s.sha256=o.ciphertext_sha256 AND s.size=o.size_bytes
    JOIN private.storage_put_intents i ON i.operation_id=s.operation_id AND i.state='committed' AND NOT i.delete_tombstone AND i.fingerprint=s.fingerprint
    JOIN private.storage_payload_reservations r ON r.object_key=i.object_key AND r.scope=i.scope AND r.plaintext_sha256=e.object_sha256
    JOIN app.payments p ON p.evidence_id=e.id JOIN app.ledger_entries g ON g.payment_id=p.id AND g.evidence_id=e.id`,
  )).rows;
  assert.equal(object.length, 1);
  assert.equal(object[0].public, false);
  assert.equal(object[0].reservation_cleared, true);
  const history = (await db.query(
    "SELECT version,encode(sha256(convert_to(statements[1],'UTF8')),'hex') sha256 FROM supabase_migrations.schema_migrations ORDER BY version",
  )).rows;
  const relations = [
    'auth.users',
    'private.auth_principal_links',
    'storage.buckets',
    'storage.objects',
    'app.payments',
    'app.payment_evidence',
    'app.ledger_entries',
  ];
  const privileges = (await db.query(
    `SELECT n.nspname,c.relname,pg_get_userbyid(c.relowner) AS owner,c.relrowsecurity,c.relforcerowsecurity,
    ARRAY(SELECT jsonb_build_array(pg_get_userbyid(a.grantor),CASE WHEN a.grantee=0 THEN 'public' ELSE pg_get_userbyid(a.grantee) END,a.privilege_type,a.is_grantable)
      FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a ORDER BY 1) AS grants
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname||'.'||c.relname=ANY($1) ORDER BY n.nspname,c.relname`,
    [relations],
  )).rows;
  assert.equal(privileges.length, relations.length);
  return {
    point,
    money,
    identitiesSha256: sha(json(identities)),
    object: object[0],
    history,
    privilegesSha256: sha(json(privileges)),
    roles: await roles(db),
  };
}

function admit(trusted, parts) {
  assert.equal(sha(json(parts.manifest)), trusted, 'restore point manifest mismatch');
  for (const name of ['database', 'roles', 'object']) {
    assert.ok(Buffer.isBuffer(parts[name]), 'required restore component missing: ' + name);
    assert.equal(sha(parts[name]), parts.manifest.components[name], 'restore component digest mismatch: ' + name);
  }
}

function openDatabase(bytes, keyBytes) {
  assert.equal(bytes.subarray(0, 13).toString(), 'COLLECTPGGCM1');
  const decipher = createDecipheriv('aes-256-gcm', keyBytes, bytes.subarray(13, 25));
  decipher.setAAD(bytes.subarray(0, 25));
  decipher.setAuthTag(bytes.subarray(-16));
  return Buffer.concat([decipher.update(bytes.subarray(25, -16)), decipher.final()]);
}

async function restoreObject(root, parts, metadata, targetData) {
  const zone = join(root, 'object-journal');
  await mkdir(zone, { mode: 0o700 });
  const binding = sha(json(metadata)),
    point = sha(json(parts.manifest.point)),
    targetPath = join(root, 'restored-evidence.bin');
  const source = {
    origin: 'http://127.0.0.1:31001',
    bucket: metadata.bucket_id,
    key: metadata.name,
    object_id: metadata.id,
    version: metadata.version,
    etag: metadata.version,
    bytes: metadata.size_bytes,
    ciphertext_sha256: metadata.ciphertext_sha256,
    namespace_sha256: sha(json(namespace)),
    binding_sha256: binding,
    key_aad_sha256: sha(metadata.aad),
  };
  const target = {
    origin: 'http://127.0.0.1:31002',
    bucket: metadata.bucket_id,
    key: metadata.name,
    namespace_sha256: source.namespace_sha256,
    key_aad_sha256: sha(metadata.aad),
  };
  const authority = {
    source_identity_sha256: sha('owned source'),
    target_identity_sha256: sha('owned destination'),
    source_fence_sha256: point,
    target_fence_sha256: point,
    mapping_sha256: binding,
  };
  const plan = { format: FORMAT, operation_id: randomUUID(), mode: 'synthetic', source, target, authority };
  const sourceMeta = { ...source, identity_sha256: authority.source_identity_sha256, fence_sha256: point };
  const targetMeta = {
    origin: target.origin,
    bucket: target.bucket,
    key: target.key,
    namespace_sha256: target.namespace_sha256,
    identity_sha256: authority.target_identity_sha256,
    fence_sha256: point,
    private_bucket: true,
  };
  const targetStore = {
    async inspect() {
      assert.deepEqual((await observation(targetData)).object, metadata);
      try {
        return {
          ...targetMeta,
          state: 'present',
          object_id: metadata.id,
          version: metadata.version,
          etag: metadata.version,
          body: await readFile(targetPath),
        };
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
        return { ...targetMeta, state: 'absent', absence_verified: true };
      }
    },
    async createOnly(body) {
      await writeFile(targetPath, body, { flag: 'wx', mode: 0o600 });
      return { accepted: true };
    },
  };
  const journalKey = randomBytes(32);
  try {
    const result = await transferObject({
      plan,
      expectedPlanSha256: planDigest(plan),
      journalRoot: zone,
      journalKey,
      source: {
        read: async () => ({ ...sourceMeta, body: Buffer.from(parts.object) }),
        inspect: async () => ({ ...sourceMeta }),
      },
      target: targetStore,
    });
    assert.equal(result.status, 'content_verified', JSON.stringify(result));
    assert.equal((await stat(targetPath)).mode & 0o777, 0o600);
    return targetPath;
  } finally {
    journalKey.fill(0);
  }
}

async function verifyScopedObject(db, journal, object, path, encryption, plain) {
  let fileReads = 0;
  const transport = {
    async probe(objectKey) {
      const result = await db.query(
        'SELECT id,version,ciphertext_sha256 FROM storage.objects WHERE bucket_id=$1 AND name=$2',
        [bucket, objectKey],
      );
      if (!result.rowCount) return { absent: true, headStatus: 404, getStatus: 404, bucketVerified: true };
      assert.deepEqual(result.rows[0], {
        id: object.id,
        version: object.version,
        ciphertext_sha256: object.ciphertext_sha256,
      });
      fileReads++;
      return { headStatus: 200, getStatus: 200, bytes: await readFile(path) };
    },
  };
  const protocol = new ProtectedStorageProtocol({ transport, journal });
  const intent = {
    key: object.name,
    operationId: object.operation_id,
    size: object.size_bytes,
    sha256: object.ciphertext_sha256,
  };
  await db.query('SET ROLE authenticated');
  try {
    await db.query("SELECT set_config('request.jwt.claims',$1,false)", [JSON.stringify({ sub: uid })]);
    const { bytes } = await protocol.readAndVerify(intent);
    assert.equal(bytes.length, object.size_bytes);
    const restored = await decrypt(encryption, bytes.toString('utf8'), object.aad);
    assert.equal(sha(restored), object.plain_sha256);
    assert.deepEqual(Buffer.from(restored), plain);
    await db.query("SELECT set_config('request.jwt.claims',$1,false)", [JSON.stringify({ sub: otherUid })]);
    await assert.rejects(protocol.readAndVerify(intent), { code: 'storage_object_not_retained' });
    assert.equal(fileReads, 1);
  } finally {
    await db.query('RESET ROLE');
  }
}

async function roleChecks(db) {
  await db.query('SET ROLE collect_runtime');
  await db.query("SELECT set_config('request.jwt.claims',$1,false)", [JSON.stringify({ sub: uid })]);
  assert.equal((await db.query('SELECT api.current_principal_id() AS principal')).rows[0].principal, 'fixture-owner');
  assert.equal((await db.query('SELECT sum(amount_minor)::int AS total FROM app.ledger_entries')).rows[0].total, 7250);
  await assert.rejects(db.query("UPDATE app.payments SET revision=revision+1 WHERE id='fixture-payment'"), {
    code: '55000',
    message: 'collect_fence_unavailable',
  });
  await db.query('RESET ROLE; SET ROLE authenticated');
  await db.query("SELECT set_config('request.jwt.claims',$1,false)", [JSON.stringify({ sub: uid })]);
  assert.equal((await db.query('SELECT id FROM storage.objects')).rows[0].id, objectId);
  await db.query("SELECT set_config('request.jwt.claims',$1,false)", [JSON.stringify({ sub: otherUid })]);
  assert.equal((await db.query('SELECT id FROM storage.objects')).rowCount, 0);
  await db.query('RESET ROLE; SET ROLE anon');
  await assert.rejects(db.query('SELECT id FROM storage.objects'), { code: '42501' });
  await assert.rejects(db.query('SELECT id FROM app.payments'), { code: '42501' });
  await db.query('RESET ROLE');
}

export async function qualifyPriorReleaseRestore(t, { certificate, proxyFor, inputFd }) {
  const resources = [], clients = [], fds = [];
  let proxy;
  const dbKey = randomBytes(32), objectKey = randomBytes(32), plain = Buffer.from('fixture private receipt bytes');
  const encryption = { DATA_KEY_ID: 'fixture-key', DATA_ENCRYPTION_KEY: objectKey.toString('base64') };
  const aad = 'evidence:fixture-evidence:' + sha(plain);
  const object = Buffer.from(await encrypt(encryption, plain, aad));
  t.after(async () => {
    try {
      for (const fd of fds) closeSync(fd);
      if (proxy) await proxy.close();
    } finally {
      dbKey.fill(0);
      objectKey.fill(0);
      const closed = await Promise.allSettled(clients.map((c) => c.end()));
      const stopped = await Promise.allSettled(resources.map((f) => f.close()));
      for (const result of closed) assert.equal(result.status, 'fulfilled');
      for (const result of stopped) {
        assert.equal(result.status, 'fulfilled');
        assert.equal(result.value.removed, true);
      }
    }
  });
  const createCluster = async (name) => {
    const f = await startOwnedPg17({
      prefix: 'collect-pg-transfer-',
      initialUser: 'fixture_bootstrap',
      clusterName: name,
    });
    resources.push(f);
    return f;
  };
  const tracked = async (f, db) => {
    const client = await connect(f, db);
    clients.push(client);
    return client;
  };
  const scopedJournal = (f, database) => {
    const pool = new pg.Pool({
      host: f.socket,
      port: f.port,
      database,
      user: 'collect_test',
      options: '-c role=collect_runtime',
      max: 1,
      connectionTimeoutMillis: 5000,
    });
    clients.push(pool);
    return new PostgresStorageJournal(pool, { namespace });
  };
  const source = await createCluster('collect_source_restore_fixture'),
    destination = await createCluster('collect_target_restore_fixture');
  await initializeBootstrapRole(source);
  await initializeBootstrapRole(destination);
  const sourceAdmin = await tracked(source, 'postgres'), targetAdmin = await tracked(destination, 'postgres');
  const systemId = async (c) =>
    (await c.query('SELECT system_identifier::text AS id FROM pg_control_system()')).rows[0].id;
  assert.notEqual(await systemId(sourceAdmin), await systemId(targetAdmin));
  await sourceAdmin.query(
    "CREATE ROLE fixture_backup LOGIN BYPASSRLS PASSWORD 'synthetic-backup-fixture'; GRANT pg_read_all_data TO fixture_backup",
  );
  await sourceAdmin.query('CREATE DATABASE collect_backup_fixture TEMPLATE template0');
  await targetAdmin.query('CREATE DATABASE collect_restore_fixture TEMPLATE template0');
  const db = await tracked(source, 'collect_backup_fixture'),
    dest = await tracked(destination, 'collect_restore_fixture');
  const inputs = await reviewedInputs(source.root);
  const sourcePath = join(source.root, 'source-evidence.bin');
  await seed(
    db,
    inputs,
    object,
    plain,
    scopedJournal(source, 'collect_backup_fixture'),
    sourcePath,
    encryption.DATA_KEY_ID,
    aad,
  );
  const folder = join(source.root, 'scratch');
  await mkdir(folder, { mode: 0o700 });
  await writeFile(
    join(source.data, 'pg_hba.conf'),
    'local collect_backup_fixture fixture_backup scram-sha-256\nlocal all all trust\nhost all all 127.0.0.1/32 reject\n',
    { mode: 0o600 },
  );
  await sourceAdmin.query('SELECT pg_reload_conf()');
  const material = certificate(source.root, 'archive-ca', 'localhost');
  proxy = await proxyFor(source, material);
  const fd = (bytes) => {
    const made = inputFd(folder, bytes);
    fds.push(made);
    return made;
  };
  const tool = async (name) => sha(await readFile(join(source.bin, name)));
  const options = {
    mode: 'synthetic',
    scratchPath: folder,
    port: proxy.port,
    passwordFd: fd(Buffer.from('synthetic-backup-fixture')),
    keyFd: fd(dbKey),
    caFd: fd(material.cert),
    caSha256: sha(material.cert),
    dumpToolSha256: await tool('pg_dump'),
    restoreToolSha256: await tool('pg_restore'),
    dumpExecutableSha256: await tool('.pg_dump-wrapped'),
    restoreExecutableSha256: await tool('.pg_restore-wrapped'),
  };
  await db.query(`BEGIN; LOCK TABLE auth.users,private.auth_principal_links,storage.buckets,storage.objects,
    private.storage_namespace,private.storage_payload_reservations,private.storage_put_intents,private.storage_upload_attempts,private.storage_objects,
    app.payments,app.ledger_entries,app.payment_evidence,private.collect_fence_control,supabase_migrations.schema_migrations IN SHARE MODE`);
  let observed, parts, trusted;
  try {
    observed = await observation(db);
    assert.deepEqual(observed.money, {
      payments: 1,
      payment_minor: '7250',
      currency: 'RWF',
      entries: 1,
      ledger_minor: '7250',
      evidence: 1,
      auth_users: 2,
    });
    assert.deepEqual(
      observed.history,
      inputs.rawMigrations.slice(0, 9).map((step) => ({ version: step.name.slice(0, 14), sha256: step.sha256 })),
    );
    const backup = await createSyntheticEncryptedBackup(options);
    await inspectSyntheticEncryptedBackup({ ...options, artifactPath: backup.artifactPath });
    parts = {
      database: await readFile(backup.artifactPath),
      roles: json(observed.roles),
      object: await readFile(sourcePath),
    };
    assert.equal(sha(parts.database), backup.ciphertextSha256);
    parts.manifest = {
      format: 'collect.synthetic.restore-point.v1',
      point: observed.point,
      history: observed.history,
      components: {
        database: backup.ciphertextSha256,
        roles: sha(parts.roles),
        object: observed.object.ciphertext_sha256,
      },
    };
    trusted = sha(json(parts.manifest));
    assert.deepEqual(await observation(db), observed);
  } finally {
    await db.query('ROLLBACK');
  }
  for (const component of ['database', 'roles', 'object']) {
    assert.throws(() => admit(trusted, { ...parts, [component]: undefined }), /required restore component missing/);
    assert.throws(
      () => admit(trusted, { ...parts, [component]: Buffer.from('mismatched capture') }),
      /restore component digest mismatch/,
    );
  }
  const otherPoint = { ...parts.manifest.point, operation_id: randomUUID() };
  assert.throws(
    () => admit(trusted, { ...parts, manifest: { ...parts.manifest, point: otherPoint } }),
    /restore point manifest mismatch/,
  );
  assert.equal((await dest.query("SELECT to_regnamespace('app') IS NULL AS empty")).rows[0].empty, true);
  admit(trusted, parts);
  await restoreRoles(dest, JSON.parse(parts.roles));
  assert.equal(
    (await dest.query("SELECT count(*)::int AS n FROM pg_roles WHERE rolname='fixture_backup'")).rows[0].n,
    0,
  );
  const archive = openDatabase(parts.database, dbKey);
  try {
    execFileSync(join(destination.bin, 'pg_restore'), [
      '--single-transaction',
      '--exit-on-error',
      '-h',
      destination.socket,
      '-p',
      String(destination.port),
      '-U',
      'collect_test',
      '-d',
      'collect_restore_fixture',
    ], { input: archive, env: destination.env, stdio: ['pipe', 'pipe', 'pipe'], timeout: 60000 });
  } finally {
    archive.fill(0);
  }
  assert.deepEqual(await observation(dest), observed);
  const restored = await restoreObject(destination.root, parts, observed.object, dest);
  const restoredJournal = scopedJournal(destination, 'collect_restore_fixture');
  await verifyScopedObject(dest, restoredJournal, observed.object, restored, encryption, plain);
  await roleChecks(dest);
  // Replay the next reviewed Realtime interface against its explicitly synthetic
  // platform binding. Migration history records the bytes actually applied.
  const iface = await sourceBytes('scripts/supabase/testing/member-realtime-interface.sql');
  assert.equal(sha(iface), inputs.binding.interface_sha256);
  await dest.query(iface.toString());
  const next = inputs.rawMigrations[9], sql = renderSyntheticSql(next.sql, inputs.binding);
  assert.equal(sha(sql), inputs.binding.synthetic_sql_sha256);
  await dest.query(sql);
  await dest.query('RESET ROLE');
  await dest.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2,ARRAY[$3::text])', [
    next.name.slice(0, 14),
    next.name,
    sql,
  ]);
  const upgraded = await observation(dest);
  assert.deepEqual(upgraded.money, observed.money);
  assert.deepEqual(upgraded.object, observed.object);
  assert.equal(upgraded.identitiesSha256, observed.identitiesSha256);
  assert.equal(upgraded.privilegesSha256, observed.privilegesSha256);
  assert.deepEqual(upgraded.history.slice(0, 9), observed.history);
  assert.equal(upgraded.history.length, 10);
  await roleChecks(dest);
  await verifyScopedObject(dest, restoredJournal, upgraded.object, restored, encryption, plain);
  t.diagnostic(
    JSON.stringify({
      prior_migrations: 9,
      upgraded_migrations: 10,
      financial: observed.money,
      roles: roleNames.length,
      prior_history_sha256: sha(json(observed.history)),
      scoped_privileges_sha256: observed.privilegesSha256,
      successor: next.name,
      successor_sql_sha256: sha(sql),
      object_count: 1,
      object_bytes: upgraded.object.size_bytes,
      owner_reads: 2,
      other_subject_file_reads: 0,
      component_rejections: 6,
      foreign_point_rejections: 1,
      mode: upgraded.point.mode,
      hosted: false,
    }),
  );
}
