// Isolated PostgreSQL contract test. No network, credentials, or production DB.
// Requires @electric-sql/pglite (or COLLECT_PGLITE_MODULE pointing to its entry).
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.COLLECT_PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const actor = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
const migration = await readFile(new URL('../../supabase/migrations/20260902073741_member_profile_numeric_identity.sql', import.meta.url), 'utf8');
const baseline = await readFile(new URL('../../supabase/migrations/20260831084646_hybrid_geographic_payment_rails.sql', import.meta.url), 'utf8');
const normalizer = baseline.match(/create or replace function public\._rwanda_momo_local\(p_value text\)[\s\S]*?\$\$;/)?.[0];
assert.ok(normalizer);
try {
  // Minimal dependencies of the RPC; this is not a full Supabase migration replay.
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create schema extensions;
    create function auth.uid() returns uuid language sql as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    create table auth.users(id uuid primary key, phone text);
    create function extensions.digest(value text, algorithm text) returns bytea
      language sql immutable as $$ select sha256(convert_to(value, 'UTF8')) $$;
    create table public.profile_country_rules(country_code text primary key, currency_code text, enabled boolean);
    insert into public.profile_country_rules values ('RW','RWF',true), ('GB','GBP',true);
    create table public.profiles(
      id uuid primary key, public_id text, whatsapp_phone text, display_name text,
      country_code text, currency_code text, momo_provider text, momo_number text,
      momo_number_hash text, momo_number_verified_at timestamptz,
      revolut_name text, revolut_link text, revolut_account text, updated_at timestamptz
    );
    create table public.audit_logs(actor_user_id uuid, action text, entity_type text, entity_id uuid, metadata jsonb);
    create function public.update_current_profile(text,text,text,text,text,text,text)
      returns void language sql as $$ select $$;
    grant update(display_name) on public.profiles to authenticated;
    grant execute on function public.update_current_profile(text,text,text,text,text,text,text) to authenticated;
    insert into auth.users values ('${actor}', '250788123456'), ('${other}', '250788654321');
    insert into public.profiles(id,public_id,whatsapp_phone,display_name,country_code,currency_code,revolut_name)
      values ('${actor}','123456','250788123456','Private Admin record','RW','RWF','Private account record'),
             ('${other}','654321','250788654321','Other Admin record','RW','RWF',null);
  `);
  await db.exec(normalizer);
  await db.exec(migration);
  const before = (await db.query(`select * from public.profiles where id='${other}'`)).rows[0];
  await db.exec('set role authenticated');
  await assert.rejects(db.query("select public.update_current_member_profile('RW','mtn_momo','0788123456')"), /Authentication required/);
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [actor]);
  const { rows } = await db.query("select public.update_current_member_profile('RW','mtn_momo','0788123456') as profile");
  assert.equal(rows[0].profile.public_id, '123456');
  assert.equal(rows[0].profile.whatsapp_phone, '250788123456');
  assert.equal(rows[0].profile.momo_number, '0788123456');
  assert.deepEqual(Object.keys(rows[0].profile).sort(), ['id','public_id','whatsapp_phone','country_code','currency_code','momo_provider','momo_number','revolut_link','revolut_account'].sort());
  await assert.rejects(db.query("select public.update_current_member_profile('RW','airtel_money','0788123456')"), /provider does not match/);
  await assert.rejects(db.query("select public.update_current_member_profile('RW',null,'0788123456')"), /Choose MTN/);
  await assert.rejects(db.query("select public.update_current_member_profile('ZZ')"), /Unsupported/);
  await assert.rejects(db.query("select public.update_current_member_profile('GB')"), /Revolut/);
  const diaspora = await db.query("select public.update_current_member_profile('GB',null,null,'https://revolut.me/member123456','EUR account') as profile");
  assert.equal(diaspora.rows[0].profile.currency_code, 'GBP');
  assert.equal(diaspora.rows[0].profile.momo_number, null);
  await assert.rejects(db.query("select public.update_current_profile('Submitted name','RW',null,null,null,null,null)"), /permission denied/);
  await assert.rejects(db.query("update public.profiles set display_name='Submitted name'"), /permission denied/);
  await db.exec('reset role');
  const persisted = (await db.query(`select * from public.profiles where id='${actor}'`)).rows[0];
  assert.equal(persisted.display_name, 'Private Admin record');
  assert.equal(persisted.revolut_name, 'Private account record');
  assert.deepEqual((await db.query(`select * from public.profiles where id='${other}'`)).rows[0], before);
  const logs = await db.query('select metadata from public.audit_logs');
  assert.equal(logs.rows.length, 2);
  assert.equal(JSON.stringify(logs.rows).includes('Private'), false);
  await db.exec('set role anon');
  await assert.rejects(db.query("select public.update_current_member_profile('RW','mtn_momo','0788123456')"), /permission denied/);
  console.log('PASS: name-free Rwanda/diaspora saves, ID/WhatsApp preservation, auth/ownership, legacy name-write denial, private-name preservation, response allowlist and audit metadata.');
} finally {
  await db.close();
}
