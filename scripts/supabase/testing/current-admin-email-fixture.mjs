// Current Admin email tests use a successor to the retained curated fixture.
// Reuse the reviewed migration bodies and execute their real fence protocol.
import {randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {EXACT_CURRENT13, EXACT_CURRENT16} from './curated-platform-fixture.mjs';
import {applyRetainedFixtureMigration, loadRetainedMigrationPrefix} from './retained-postgres-history.mjs';

const emailMigration = '20261111043455_collect_admin_email_otp_lifetime.sql';
const baseline = 'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const fixtureNames = new Set([
  'collect_admin_history_test', 'collect_edge_test',
  'collect_edge_ci_test', 'collect_edge_storage_test',
]);
const need = (condition, code) => { if (!condition) throw new Error(code); };

/** Extend a fresh curated 13-migration fixture using its reserved bootstrap connection. */
export async function installCurrentAdminEmailFixture(connection, root, sourceSha256) {
  need(/^[a-f0-9]{64}$/.test(sourceSha256 ?? ''), 'SYNTHETIC_ADMIN_EMAIL_SOURCE_REQUIRED');
  const migrations = await loadRetainedMigrationPrefix(root instanceof URL ? fileURLToPath(root) : root);
  const emailIndex = migrations.findIndex(({name}) => name === emailMigration);
  const prefix = migrations.slice(0, EXACT_CURRENT16.length).map(({name}) => name);
  need(emailIndex >= EXACT_CURRENT16.length && JSON.stringify(prefix) === JSON.stringify(EXACT_CURRENT16),
    'EXACT_REVIEWED_ADMIN_EMAIL_PREFIX_REQUIRED');
  const [identity] = await connection.unsafe(`
    SELECT current_database() AS database, current_user AS role, session_user AS bootstrap,
      host(inet_server_addr()) AS host, current_setting('server_version_num')::integer / 10000 AS major,
      pg_get_userbyid(datdba) AS owner,
      (SELECT rolsuper AND rolbypassrls FROM pg_roles WHERE rolname = current_user) AS fixture_bootstrap
    FROM pg_database WHERE datname = current_database()`);
  need(identity && fixtureNames.has(identity.database) && identity.role === 'collect_test' &&
    identity.bootstrap === 'collect_test' && identity.owner === 'collect_test' &&
    identity.host === '127.0.0.1' && identity.major === 17 && identity.fixture_bootstrap === true,
    'OWNED_ADMIN_EMAIL_LOOPBACK_FIXTURE_REQUIRED');

  const [fresh] = await connection.unsafe(`
    SELECT NOT EXISTS (SELECT 1 FROM private.collect_fence_control)
      AND NOT EXISTS (SELECT 1 FROM private.collect_fence_admissions)
      AND NOT EXISTS (SELECT 1 FROM private.collect_fence_operations)
      AND to_regclass('private.collect_fence_stopped_admissions') IS NULL
      AND to_regprocedure('private.admin_email_prepare(text,text,text,text,text)') IS NOT NULL
      AND to_regprocedure('private.admin_email_prepare(text,text,text,text,text,integer)') IS NULL AS allowed`);
  need(fresh?.allowed === true, 'FRESH_CURATED_ADMIN_EMAIL_PREFIX_REQUIRED');

  // Add only the native GoTrue columns missing from the retained Auth double.
  // Move only ownership in this disposable database to the normal definer role.
  await connection.unsafe(`
    ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz;
    ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS is_anonymous boolean NOT NULL DEFAULT false;
    DO $fixture_owner$
    DECLARE item record; fixture_schemas CONSTANT text[] := ARRAY['app', 'private', 'auth', 'api', 'realtime', 'public'];
    BEGIN
      -- The reviewed gateway migration uses this restricted cluster role.
      -- Seed it in the bootstrap session so the fixture owner remains NO CREATEROLE.
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'collect_sms_runtime') THEN
        CREATE ROLE collect_sms_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
          NOINHERIT NOREPLICATION NOBYPASSRLS;
      END IF;
      FOR item IN SELECT nspname FROM pg_namespace
        WHERE nspname = ANY(fixture_schemas)
          AND nspowner = (SELECT oid FROM pg_roles WHERE rolname = 'collect_test')
      LOOP EXECUTE format('ALTER SCHEMA %I OWNER TO postgres', item.nspname); END LOOP;
      FOR item IN SELECT c.oid::regclass AS name, c.relkind FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = ANY(fixture_schemas)
          AND c.relowner = (SELECT oid FROM pg_roles WHERE rolname = 'collect_test')
          AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
      LOOP EXECUTE format('ALTER %s %s OWNER TO postgres',
        CASE item.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW'
          WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END, item.name); END LOOP;
      FOR item IN SELECT c.oid::regclass AS name FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = ANY(fixture_schemas) AND c.relkind = 'S'
          AND c.relowner = (SELECT oid FROM pg_roles WHERE rolname = 'collect_test')
      LOOP EXECUTE format('ALTER SEQUENCE %s OWNER TO postgres', item.name); END LOOP;
      FOR item IN SELECT p.oid::regprocedure AS name FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = ANY(fixture_schemas) AND p.prokind = 'f'
          AND p.proowner = (SELECT oid FROM pg_roles WHERE rolname = 'collect_test')
      LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres', item.name); END LOOP;
      EXECUTE format('ALTER DATABASE %I OWNER TO postgres', current_database());
    END;
    $fixture_owner$;`);

  await connection.unsafe('SET SESSION AUTHORIZATION postgres');
  try {
    for (const item of migrations.slice(EXACT_CURRENT13.length, EXACT_CURRENT16.length)) {
      await connection.unsafe(item.sql);
    }
    await connection.unsafe('SELECT private.collect_fence_initialize($1::uuid,$2::text,$3::text)',
      [randomUUID(), sourceSha256, baseline]);
    for (const item of migrations.slice(EXACT_CURRENT16.length, emailIndex + 1)) {
      await applyRetainedFixtureMigration(connection, item);
    }
    const [installed] = await connection.unsafe(`
      SELECT to_regprocedure('private.admin_email_prepare(text,text,text,text,text,integer)') IS NOT NULL
        AND (SELECT mode = 'open' AND source_sha256 = $1 FROM private.collect_fence_control WHERE singleton)
        AS allowed`, [sourceSha256]);
    need(installed?.allowed === true, 'CURRENT_ADMIN_EMAIL_INSTALLATION_UNCONFIRMED');
  } catch (error) {
    // Whole-file migration SQL manages its own transactions.
    await connection.unsafe('ROLLBACK');
    throw error;
  } finally {
    await connection.unsafe('RESET SESSION AUTHORIZATION');
  }
}
