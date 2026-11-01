// Public producer-shaped synthetic metadata only; no real schema attestation.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { validateAdminPwaFixtureMetadata } from '../qa/admin_pwa_fixture_metadata.mjs';

const BASELINE = '20261020134444_collect_curated_platform_baseline.sql';
const digest = chain => createHash('sha256').update(JSON.stringify(chain.map(row => ({ name: row.name, sha256: row.sha256 })))).digest('hex');
function fixture() {
  return {
    backend: 'supabase', authentication: 'supabase_auth_cookie_with_email_verification',
    notifications: 'provider_configuration_required', data_strategy: 'preserve_existing_source',
    legacy_data_import_required: true, minimum_core_schema_migration: BASELINE,
    operating_actions_available: false, operational_migration_complete: false,
    financial_model: 'canonical_evidence_ledger', financial_contract_version: 2,
    provider_settlement_available: false, supabase_project_ref: 'rrlduytparvsjfmegalh',
    supabase_schema_sha256: 'a'.repeat(64), admin_transport: 'same_origin_static_proxy',
    supabase_qualification_complete: false,
    supabase_migrations: [{ name: BASELINE, sha256: 'a'.repeat(64) },
      { name: '20261020150000_synthetic_qa_followup.sql', sha256: 'b'.repeat(64) }],
    // Independently calculated with Python's producer sort_keys/separators.
    supabase_migration_chain_sha256: '6998c67dceae08b673f3fa1a50c2031997612896ab07718f51f4bed7d45e9f76',
    admin_origin: 'https://platform-admin.collect.ikanisa.com',
    api_origin: 'https://platform-admin.collect.ikanisa.com',
    admin_api_origin: 'https://platform-admin.collect.ikanisa.com',
    public_build_defines_sha256: 'c'.repeat(64),
    diagnostics_source_revision: 'd'.repeat(64), diagnostics_build_version: '1.0.8+65',
  };
}
function refused(value, options) {
  assert.throws(() => validateAdminPwaFixtureMetadata(value, options), error => error instanceof Error &&
    error.message.includes('current build-config producer') && !error.message.includes('SYNTHETIC_PRIVATE'));
}
test('accepts complete current-producer-shaped public metadata and retains every chain field', () => {
  const value = fixture(), before = JSON.stringify(value);
  assert.equal(validateAdminPwaFixtureMetadata(value), value);
  assert.equal(JSON.stringify(value), before);
  assert.equal(value.supabase_migrations.length, 2);
});
test('migration property insertion order does not change Python canonical digest', () => {
  const value = fixture();
  value.supabase_migrations = value.supabase_migrations.map(row => ({ sha256: row.sha256, name: row.name }));
  assert.equal(validateAdminPwaFixtureMetadata(value), value);
});
test('a single baseline is an admitted complete chain shape', () => {
  const value = fixture(); value.supabase_migrations.pop();
  value.supabase_migration_chain_sha256 = digest(value.supabase_migrations);
  assert.equal(validateAdminPwaFixtureMetadata(value), value);
});
test('accepts the explicit 128-entry bound without truncating the chain', () => {
  const value = fixture();
  value.supabase_migrations = [value.supabase_migrations[0], ...Array.from({ length: 127 }, (_, i) => ({
    name: `20261021${String(i).padStart(6, '0')}_synthetic_qa.sql`, sha256: 'b'.repeat(64),
  }))];
  value.supabase_migration_chain_sha256 = digest(value.supabase_migrations);
  assert.equal(validateAdminPwaFixtureMetadata(value).supabase_migrations.length, 128);
});

for (const mode of ['managed', 'explicit_managed', 'self_hosted']) for (const qualification of [false, true])
  test(`accepts exact ${mode} ${qualification ? 'qualification' : 'production'} producer envelope and public input digest`, () => {
  const root = mkdtempSync(join(tmpdir(), 'admin-producer-envelope-'));
  try {
    const migrations = join(root, 'supabase', 'migrations');
    mkdirSync(migrations, { recursive: true });
    writeFileSync(join(migrations, BASELINE), '-- synthetic fixture\nselect 1;\n');
    const python = String.raw`import json,sys,base64
from pathlib import Path
from scripts.supabase.admin_build_config import configuration, verify_public_inputs
from scripts.supabase.deployment_profile import canonical_profile,profile_sha256
env={'COLLECT_BACKEND':'supabase','SUPABASE_PUBLISHABLE_KEY':'sb_publishable_public_fixture_only'}
qa=sys.argv[3]=='qa'; expected=None
if sys.argv[2]!='managed':
 selfhost=sys.argv[2]=='self_hosted'; admin='https://admin.example.test' if selfhost else ('https://admin-supabase-qa.collect.ikanisa.com' if qa else 'https://platform-admin.collect.ikanisa.com')
 p={'format':'collect.deployment.v1','id':'synthetic-local','mode':'self_hosted' if selfhost else 'managed','environment':'qualification' if qa else 'production','supabase_origin':'https://supabase.example.test' if selfhost else 'https://rrlduytparvsjfmegalh.supabase.co','member_api_origin':'https://api.example.test' if selfhost else admin,'admin_origin':admin,'public_origin':'https://collect.example.test' if selfhost else 'https://collect.ikanisa.com','google_callback_origin':admin}
 expected=profile_sha256(p); env.update(COLLECT_DEPLOYMENT_PROFILE=canonical_profile(p),COLLECT_DEPLOYMENT_PROFILE_SHA256=expected)
else:
 env['SUPABASE_URL']='https://rrlduytparvsjfmegalh.supabase.co'
 if qa: env.update(ADMIN_APP_URL='https://admin-supabase-qa.collect.ikanisa.com',SUPABASE_API_URL='https://admin-supabase-qa.collect.ikanisa.com',SUPABASE_ADMIN_API_URL='https://admin-supabase-qa.collect.ikanisa.com')
if qa: env.update(AUTH_CAPTCHA_ENABLED='true',AUTH_CAPTCHA_SITE_KEY='synthetic_qualification_public_key')
d,m=configuration(env,Path(sys.argv[1]),qualification=qa);d.update(COLLECT_BUILD_SOURCE_ID='d'*64,COLLECT_BUILD_VERSION='1.0.8+65')
m.update(diagnostics_source_revision='d'*64,diagnostics_build_version='1.0.8+65')
enc=lambda x:(json.dumps(x,indent=2)+'\n').encode()
b=enc(d); sealed=verify_public_inputs(b,enc(m),env,Path(sys.argv[1]),qualification=qa,binding=True)
print(json.dumps({'metadata':sealed,'defines':base64.b64encode(b).decode(),'expected':expected}))`;
    const result = spawnSync('python3', ['-c', python, root, mode, qualification ? 'qa' : 'production'], { encoding:'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const { metadata, defines, expected } = JSON.parse(result.stdout);
    const bytes = Buffer.from(defines, 'base64'), values = JSON.parse(bytes.toString('utf8'));
    const options = expected ? { expectedProfileSha256:expected } : {};
    assert.equal(validateAdminPwaFixtureMetadata(metadata, options), metadata);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), metadata.public_build_defines_sha256);
    assert.equal(values.ADMIN_APP_URL, metadata.admin_origin);
    assert.equal(values.SUPABASE_API_URL, metadata.api_origin);
    assert.equal(values.SUPABASE_ADMIN_API_URL, metadata.admin_api_origin);
    const changed = structuredClone(metadata); changed.admin_origin = 'https://wrong.example.test';
    refused(changed, options);
    if (qualification) {
      assert.equal(metadata.shipping_candidate, false);
      assert.equal(metadata.qualification_complete, false);
      for (const changes of [{shipping_candidate:true}, {qualification_complete:true},
                             {purpose:'production'}, {environment:'production'}]) {
        refused({ ...metadata, ...changes }, options);
      }
    }
    if (expected) {
      refused(metadata);
      refused(metadata, { expectedProfileSha256:'0'.repeat(64) });
      for (const changes of [{admin_origin:'https://other.example.test'},
                             {environment:qualification ? 'production' : 'qualification'},
                             {google_callback_origin:'https://other.example.test'}]) {
        const altered = structuredClone(metadata);
        Object.assign(altered.deployment_profile, changes);
        const canonical = Object.fromEntries(Object.keys(altered.deployment_profile).sort().map(k => [k, altered.deployment_profile[k]]));
        altered.deployment_profile_sha256 = createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
        refused(altered, options);
      }
    }
  } finally { rmSync(root, { recursive:true, force:true }); }
});

const malformed = [
  ...['admin_origin', 'api_origin', 'admin_api_origin', 'public_build_defines_sha256',
    'diagnostics_source_revision', 'diagnostics_build_version'].map(key =>
      [`missing ${key}`, value => { delete value[key]; }]),
  ['mismatched api origin', value => { value.api_origin = 'https://different.example.test'; }],
  ['mismatched admin api origin', value => { value.admin_api_origin = 'https://different.example.test'; }],
  ['origin trailing slash', value => { value.admin_origin += '/'; }],
  ['public defines newline digest', value => { value.public_build_defines_sha256 += '\n'; }],
  ['public defines uppercase digest', value => { value.public_build_defines_sha256 = 'C'.repeat(64); }],
  ['missing chain', value => { delete value.supabase_migrations; }],
  ['missing chain digest', value => { delete value.supabase_migration_chain_sha256; }],
  ['empty chain', value => { value.supabase_migrations = []; }],
  ['overlong chain', value => { value.supabase_migrations = Array(129).fill(value.supabase_migrations[0]); }],
  ['null chain', value => { value.supabase_migrations = null; }],
  ['object chain', value => { value.supabase_migrations = { 0: value.supabase_migrations[0] }; }],
  ['null entry', value => { value.supabase_migrations[1] = null; }],
  ['array entry', value => { value.supabase_migrations[1] = []; }],
  ['missing entry name', value => { delete value.supabase_migrations[1].name; }],
  ['missing entry digest', value => { delete value.supabase_migrations[1].sha256; }],
  ['extra secret in entry', value => { value.supabase_migrations[1].secret = 'SYNTHETIC_PRIVATE'; }],
  ['unsafe path', value => { value.supabase_migrations[1].name = '../20261020150000_secret.sql'; }],
  ['short timestamp', value => { value.supabase_migrations[1].name = '20261020_short.sql'; }],
  ['uppercase filename', value => { value.supabase_migrations[1].name = '20261020150000_UPPER.sql'; }],
  ['whitespace filename', value => { value.supabase_migrations[1].name = '20261020150000_bad name.sql'; }],
  ['wrong extension', value => { value.supabase_migrations[1].name = '20261020150000_wrong.sql.js'; }],
  ...['\n', '\r', '\r\n', '\u2028', '\u2029'].map(suffix =>
    [`trailing line terminator in migration name ${JSON.stringify(suffix)}`, value => { value.supabase_migrations[1].name += suffix; }]),
  ['uppercase digest', value => { value.supabase_migrations[1].sha256 = 'B'.repeat(64); }],
  ['short digest', value => { value.supabase_migrations[1].sha256 = 'b'.repeat(63); }],
  ['newline digest', value => { value.supabase_migrations[1].sha256 += '\n'; }],
  ['nonstr digest', value => { value.supabase_migrations[1].sha256 = 1; }],
  ['duplicate migration', value => { value.supabase_migrations[1] = { ...value.supabase_migrations[0] }; }],
  ['unordered chain', value => { value.supabase_migrations.reverse(); }],
  ['different first migration', value => { value.supabase_migrations[0].name = '20261020134443_not_baseline.sql'; }],
  ['minimum migration mismatch', value => { value.minimum_core_schema_migration = '20261020150000_synthetic_qa_followup.sql'; }],
  ['schema digest mismatch', value => { value.supabase_schema_sha256 = 'c'.repeat(64); }],
  ['newline schema digest', value => { value.supabase_schema_sha256 += '\n'; }],
  ['wrong chain digest', value => { value.supabase_migration_chain_sha256 = 'c'.repeat(64); }],
  ['uppercase chain digest', value => { value.supabase_migration_chain_sha256 = 'C'.repeat(64); }],
  ['newline chain digest', value => { value.supabase_migration_chain_sha256 += '\n'; }],
  ['missing complete producer field', value => { delete value.notifications; }],
  ['extra public credential field', value => { value.SUPABASE_SERVICE_ROLE_KEY = 'SYNTHETIC_PRIVATE'; }],
  ['wrong project', value => { value.supabase_project_ref = 'another_project'; }],
  ['wrong authentication', value => { value.authentication = 'password_cookie_with_totp'; }],
  ['retired authenticator policy', value => { value.authentication = 'supabase_auth_cookie_with_totp'; }],
  ['wrong transport', value => { value.admin_transport = 'arbitrary_redirect'; }],
  ['wrong financial version', value => { value.financial_contract_version = 3; }],
  ['wrong financial model', value => { value.financial_model = 'synthetic_accounting'; }],
  ['wrong data strategy', value => { value.data_strategy = 'replace_source'; }],
  ['import flag false', value => { value.legacy_data_import_required = false; }],
  ['wrong notification state', value => { value.notifications = 'provider_ready'; }],
];
for (const [name, change] of malformed) test(`rejects ${name} without mutating or echoing metadata`, () => {
  const value = fixture(); change(value);
  // Reseal changed arrays where possible: malformed entries/order/cardinality
  // must fail their own contract, not merely a stale outer digest.
  if (!name.includes('chain digest') && Object.hasOwn(value, 'supabase_migration_chain_sha256') &&
      Array.isArray(value.supabase_migrations) && value.supabase_migrations.every(row => row !== null && typeof row === 'object')) {
    value.supabase_migration_chain_sha256 = digest(value.supabase_migrations);
  }
  const before = JSON.stringify(value);
  refused(value); assert.equal(JSON.stringify(value), before);
});
for (const field of ['supabase_qualification_complete', 'operating_actions_available',
  'operational_migration_complete', 'provider_settlement_available']) {
  test(`rejects ${field}=true rather than upgrading fixture qualification`, () => {
    const value = fixture(); value[field] = true; refused(value);
  });
}
for (const value of [null, [], 'SYNTHETIC_PRIVATE']) test('rejects a nonobject public metadata envelope', () => refused(value));
