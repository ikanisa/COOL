import { createHash } from 'node:crypto';

const BASELINE = '20261020134444_collect_curated_platform_baseline.sql';
const PROJECT = 'rrlduytparvsjfmegalh';
// JavaScript's `$` can match before a trailing line terminator. Require the
// true end so fixture source identities cannot include invisible suffixes.
const SHA256 = /^[a-f0-9]{64}(?![\s\S])/;
const MIGRATION = /^[0-9]{14}_[a-z0-9_]+\.sql(?![\s\S])/;
const FIELDS = ['backend', 'authentication', 'notifications', 'data_strategy', 'legacy_data_import_required',
  'minimum_core_schema_migration', 'operating_actions_available', 'operational_migration_complete', 'financial_model',
  'financial_contract_version', 'provider_settlement_available', 'supabase_project_ref', 'supabase_schema_sha256',
  'admin_transport', 'supabase_qualification_complete', 'supabase_migrations', 'supabase_migration_chain_sha256',
  'admin_origin', 'api_origin', 'admin_api_origin', 'public_build_defines_sha256',
  'diagnostics_source_revision', 'diagnostics_build_version'].sort();
const PROFILE_FIELDS = ['format', 'id', 'mode', 'environment', 'supabase_origin', 'member_api_origin',
  'admin_origin', 'public_origin', 'google_callback_origin'].sort();
const PROFILE_METADATA = ['deployment_profile', 'deployment_profile_sha256', 'supabase_hosting', 'supabase_auth_issuer'];
const QUALIFICATION_FIELDS = ['purpose', 'environment', 'qualification_complete', 'shipping_candidate'];
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value) &&
  [Object.prototype, null].includes(Object.getPrototypeOf(value));
const exactKeys = (value, fields) => object(value) && Object.keys(value).sort().join(',') === fields.join(',');
const validOrigin = value => {
  try {
    const url = new URL(value);
    return typeof value === 'string' && url.protocol === 'https:' && url.origin === value &&
      !url.username && !url.password && url.hostname.includes('.') &&
      !/^[0-9.]+$/.test(url.hostname) && !url.hostname.endsWith('.') && url.hostname.length <= 253 &&
      url.hostname.split('.').every(label => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?![\s\S])/.test(label));
  } catch { return false; }
};
const fail = () => { throw Error('Supply complete unqualified public Supabase metadata from the current build-config producer; credentials and release admission are not fixture metadata'); };

/** Pure validation of public synthetic-fixture input, never schema/hosted proof. */
export function validateAdminPwaFixtureMetadata(value, { expectedProfileSha256 } = {}) {
  const profiled = object(value) && Object.hasOwn(value, 'deployment_profile');
  const qualification = object(value) && QUALIFICATION_FIELDS.some(key => Object.hasOwn(value, key));
  const expectedFields = [...FIELDS, ...(profiled ? PROFILE_METADATA : []),
    ...(qualification ? QUALIFICATION_FIELDS : [])].sort();
  if (!exactKeys(value, expectedFields) || value.backend !== 'supabase' ||
      value.authentication !== 'supabase_auth_cookie_with_email_verification' ||
      value.notifications !== 'provider_configuration_required' || value.data_strategy !== 'preserve_existing_source' ||
      value.legacy_data_import_required !== true || value.minimum_core_schema_migration !== BASELINE ||
      value.admin_transport !== 'same_origin_static_proxy' ||
      value.financial_model !== 'canonical_evidence_ledger' || value.financial_contract_version !== 2 ||
      !validOrigin(value.admin_origin) || !validOrigin(value.api_origin) ||
      value.admin_api_origin !== value.admin_origin ||
      typeof value.public_build_defines_sha256 !== 'string' || !SHA256.test(value.public_build_defines_sha256) ||
      typeof value.diagnostics_source_revision !== 'string' || !SHA256.test(value.diagnostics_source_revision) ||
      typeof value.diagnostics_build_version !== 'string' ||
      !/^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\+[1-9][0-9]*(?![\s\S])/.test(value.diagnostics_build_version) ||
      typeof value.supabase_schema_sha256 !== 'string' || !SHA256.test(value.supabase_schema_sha256) ||
      typeof value.supabase_migration_chain_sha256 !== 'string' || !SHA256.test(value.supabase_migration_chain_sha256) ||
      ['supabase_qualification_complete', 'operating_actions_available', 'operational_migration_complete',
        'provider_settlement_available'].some(key => value[key] !== false)) fail();
  if (qualification && (value.purpose !== 'qualification' || value.environment !== 'qualification' ||
      value.qualification_complete !== false || value.shipping_candidate !== false)) fail();
  if (profiled) {
    const p = value.deployment_profile;
    if (!exactKeys(p, PROFILE_FIELDS) || Object.values(p).some(x => typeof x !== 'string') ||
        p.format !== 'collect.deployment.v1' || !/^[a-z][a-z0-9-]{0,62}(?![\s\S])/.test(p.id) ||
        !['managed', 'self_hosted'].includes(p.mode) ||
        p.environment !== (qualification ? 'qualification' : 'production') ||
        PROFILE_FIELDS.filter(k => k.endsWith('_origin')).some(k => !validOrigin(p[k])) ||
        ![p.member_api_origin, p.admin_origin].includes(p.google_callback_origin) ||
        value.admin_origin !== p.admin_origin || value.api_origin !== p.member_api_origin ||
        value.supabase_hosting !== p.mode || value.supabase_auth_issuer !== p.supabase_origin + '/auth/v1' ||
        (p.mode === 'managed' ? (p.supabase_origin !== `https://${PROJECT}.supabase.co` || value.supabase_project_ref !== PROJECT)
          : value.supabase_project_ref !== null)) fail();
    const canonicalProfile = Object.fromEntries(Object.keys(p).sort().map(k => [k, p[k]]));
    if (typeof expectedProfileSha256 !== 'string' || !SHA256.test(expectedProfileSha256) ||
        expectedProfileSha256 !== value.deployment_profile_sha256 ||
        typeof value.deployment_profile_sha256 !== 'string' || !SHA256.test(value.deployment_profile_sha256) ||
        createHash('sha256').update(JSON.stringify(canonicalProfile)).digest('hex') !== value.deployment_profile_sha256) fail();
  } else if (expectedProfileSha256 !== undefined || value.supabase_project_ref !== PROJECT ||
      value.admin_origin !== (qualification ? 'https://admin-supabase-qa.collect.ikanisa.com'
                                            : 'https://platform-admin.collect.ikanisa.com') ||
      value.api_origin !== value.admin_origin) fail();
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
