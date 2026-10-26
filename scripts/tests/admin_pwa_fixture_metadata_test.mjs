// Public producer-shaped synthetic metadata only; no real schema attestation.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
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
  };
}
function refused(value) {
  assert.throws(() => validateAdminPwaFixtureMetadata(value), error => error instanceof Error &&
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

const malformed = [
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
  ['uppercase digest', value => { value.supabase_migrations[1].sha256 = 'B'.repeat(64); }],
  ['short digest', value => { value.supabase_migrations[1].sha256 = 'b'.repeat(63); }],
  ['nonstr digest', value => { value.supabase_migrations[1].sha256 = 1; }],
  ['duplicate migration', value => { value.supabase_migrations[1] = { ...value.supabase_migrations[0] }; }],
  ['unordered chain', value => { value.supabase_migrations.reverse(); }],
  ['different first migration', value => { value.supabase_migrations[0].name = '20261020134443_not_baseline.sql'; }],
  ['minimum migration mismatch', value => { value.minimum_core_schema_migration = '20261020150000_synthetic_qa_followup.sql'; }],
  ['schema digest mismatch', value => { value.supabase_schema_sha256 = 'c'.repeat(64); }],
  ['wrong chain digest', value => { value.supabase_migration_chain_sha256 = 'c'.repeat(64); }],
  ['uppercase chain digest', value => { value.supabase_migration_chain_sha256 = 'C'.repeat(64); }],
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
