import { createHash } from 'node:crypto';

const BASELINE = '20261020134444_collect_curated_platform_baseline.sql';
const PROJECT = 'rrlduytparvsjfmegalh';
const SHA256 = /^[a-f0-9]{64}$/;
const MIGRATION = /^[0-9]{14}_[a-z0-9_]+\.sql$/;
const FIELDS = ['backend', 'authentication', 'notifications', 'data_strategy', 'legacy_data_import_required',
  'minimum_core_schema_migration', 'operating_actions_available', 'operational_migration_complete', 'financial_model',
  'financial_contract_version', 'provider_settlement_available', 'supabase_project_ref', 'supabase_schema_sha256',
  'admin_transport', 'supabase_qualification_complete', 'supabase_migrations', 'supabase_migration_chain_sha256'].sort();
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value) &&
  [Object.prototype, null].includes(Object.getPrototypeOf(value));
const exactKeys = (value, fields) => object(value) && Object.keys(value).sort().join(',') === fields.join(',');
const fail = () => { throw Error('Supply complete unqualified public Supabase metadata from the current build-config producer; credentials and release admission are not fixture metadata'); };

/** Pure validation of public synthetic-fixture input, never schema/hosted proof. */
export function validateAdminPwaFixtureMetadata(value) {
  if (!exactKeys(value, FIELDS) || value.backend !== 'supabase' ||
      value.authentication !== 'supabase_auth_cookie_with_email_verification' ||
      value.notifications !== 'provider_configuration_required' || value.data_strategy !== 'preserve_existing_source' ||
      value.legacy_data_import_required !== true || value.minimum_core_schema_migration !== BASELINE ||
      value.admin_transport !== 'same_origin_static_proxy' || value.supabase_project_ref !== PROJECT ||
      value.financial_model !== 'canonical_evidence_ledger' || value.financial_contract_version !== 2 ||
      typeof value.supabase_schema_sha256 !== 'string' || !SHA256.test(value.supabase_schema_sha256) ||
      typeof value.supabase_migration_chain_sha256 !== 'string' || !SHA256.test(value.supabase_migration_chain_sha256) ||
      ['supabase_qualification_complete', 'operating_actions_available', 'operational_migration_complete',
        'provider_settlement_available'].some(key => value[key] !== false)) fail();
  const chain = value.supabase_migrations;
  if (!Array.isArray(chain) || chain.length < 1 || chain.length > 128) fail();
  let previous = '';
  const canonical = [];
  for (const migration of chain) {
    if (!exactKeys(migration, ['name', 'sha256']) || typeof migration.name !== 'string' ||
        !MIGRATION.test(migration.name) || migration.name <= previous ||
        typeof migration.sha256 !== 'string' || !SHA256.test(migration.sha256)) fail();
    previous = migration.name;
    // Producer uses Python json.dumps(sort_keys=True, separators=(',', ':')).
    // Validated names/hashes are ASCII, so this exact key order is equivalent.
    canonical.push({ name: migration.name, sha256: migration.sha256 });
  }
  if (chain[0].name !== value.minimum_core_schema_migration ||
      chain[0].sha256 !== value.supabase_schema_sha256 ||
      createHash('sha256').update(JSON.stringify(canonical)).digest('hex') !== value.supabase_migration_chain_sha256) fail();
  return value;
}
