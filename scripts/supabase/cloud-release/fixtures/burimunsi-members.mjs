import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const migration = name => readFile(new URL('../../../../supabase/migrations/' + name, import.meta.url), 'utf8');
const baseline = await migration('20261020134444_collect_curated_platform_baseline.sql');
const history = await migration('20261101012310_collect_member_history_pagination.sql');
const keyset = await migration('20261119114500_burimunsi_members_keyset.sql');

export const memberId = n => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
export const fixtureRoles = 'CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE ROLE collect_runtime; CREATE ROLE collect_importer;';

export async function seedMemberListing(client, sizes) {
  assert.ok(sizes.length && sizes.every(size => [1000, 10000, 100000].includes(size)));
  const tables = ['users','collections','memberships','payments','payment_evidence','ledger_entries',
    'admin_users','admin_principal_links','admin_grants','admin_sessions','auth_sessions','auth_mfa_factors','admin_account_role_capabilities'];
  const indexes = ['membership_actor','ledger_actor_history'];
  const definitions = [...tables.map(name => 'CREATE TABLE ' + name + ' '), ...indexes.map(name => 'CREATE INDEX ' + name + ' ')]
    .map(prefix => {
      const lines = baseline.split('\n').filter(line => line.startsWith(prefix));
      assert.equal(lines.length, 1, prefix);
      return lines[0];
    });
  await client.query(`
    CREATE SCHEMA app; CREATE SCHEMA private; SET search_path=app,public,pg_catalog;
    CREATE FUNCTION app.unixepoch() RETURNS bigint LANGUAGE sql STABLE AS $$SELECT extract(epoch FROM now())::bigint$$;
    CREATE FUNCTION app.json_valid(value text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$SELECT pg_input_is_valid(value,'jsonb')$$;
    ${definitions.join('\n')}
    CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,mode text);
    INSERT INTO private.collect_fence_control VALUES(true,'fenced');
    CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE sql AS $$SELECT$$;
    CREATE FUNCTION private._collect_fence_no_erasure() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'no erasure';END$$;
    CREATE FUNCTION private.fixture_member_id(n integer) RETURNS text IMMUTABLE LANGUAGE sql AS $$
      SELECT '00000000-0000-4000-8000-'||lpad(n::text,12,'0')$$;`);
  await client.query(`INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)
    SELECT 'group-'||s,'group-'||s,'fixture',s::text,'savings','2026-11-01T16:00:00.000Z','2026-11-01T16:00:00.000Z'
    FROM unnest($1::int[]) s`, [sizes]);
  const largest = Math.max(...sizes);
  await client.query(`INSERT INTO app.users(id,public_id,full_name,phone,momo_number,access_status,member_type,created_at,updated_at)
    SELECT private.fixture_member_id(i),lpad(i::text,6,'0'),'Élise '||lpad(i::text,6,'0'),
      '+25078'||lpad(i::text,7,'0'),'+25078'||lpad(i::text,7,'0'),CASE WHEN i%40=0 THEN 'suspended' ELSE 'active' END,
      CASE WHEN i%3=0 THEN 'direct' ELSE 'app' END,'2026-11-01T16:00:00.000Z','2026-11-01T16:00:00.000Z'
    FROM generate_series(1,$1::integer) i`, [largest]);
  await client.query(`INSERT INTO app.memberships(id,collection_id,user_id,joined_at,active)
    SELECT c.id||'-'||i,c.id,private.fixture_member_id(i),'2026-11-01T18:00:00.123+02:00',CASE WHEN i%100=0 THEN 0 ELSE 1 END
    FROM app.collections c CROSS JOIN LATERAL generate_series(1,substring(c.id,7)::int) i`);
  await client.query(`INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at)
    SELECT 'entry-'||i,'payment-'||i,$2,private.fixture_member_id(i),i,'contribution','evidence-'||i,'fixture','request-'||i,
      '2026-11-01T16:20:00.000Z' FROM generate_series(1,$1::integer,10) i`, [largest, 'group-' + largest]);
  await client.query('GRANT USAGE ON SCHEMA app,private TO collect_runtime; GRANT SELECT ON ALL TABLES IN SCHEMA app TO collect_runtime;');
  await client.query(history);
  await client.query(keyset);
  await client.query('VACUUM ANALYZE');
}
