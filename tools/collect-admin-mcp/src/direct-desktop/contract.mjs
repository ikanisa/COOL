import { createHash } from 'node:crypto';

export class DesktopError extends Error {
  constructor(code, message = 'The local desktop operation could not be verified. No action was retried.') {
    super(message); this.code = code;
  }
}
export const fail = code => { throw new DesktopError(code); };
const text = (maxLength = 128) => ({ type: 'string', minLength: 1, maxLength, pattern: '^[^\\u0000-\\u001f\\u007f]+$' });
const object = (properties, required = Object.keys(properties)) => ({ type: 'object', properties, required, additionalProperties: false });
const list = (items, maxItems = 100) => ({ type: 'array', items, maxItems, uniqueItems: true });
const yes = { const: true };
const instant = { type: 'string', format: 'date-time', maxLength: 24 };
export const CHANNELS = ['messages_native', 'whatsapp_native'];
export const SOURCE_SCHEMA = object({
  source_namespace: text(), tenant_id: text(), transaction_reference: text(200),
  notification_kind: { const: 'payment_receipt' }, source_version: text(), observed_at: instant,
  payment_state: { const: 'confirmed' }, amount_label: text(), balance_label: text(),
});
export const RECIPIENT_SCHEMA = object({
  recipient_key: text(), channel: { enum: CHANNELS },
  destination_e164: { type: 'string', pattern: '^\\+[1-9][0-9]{7,14}$' },
  country_context: { type: 'string', pattern: '^[A-Z]{2}$' }, single_recipient: yes, recipient_visible: yes,
});
export const PREPARE_SCHEMA = object({
  source: SOURCE_SCHEMA, recipient: RECIPIENT_SCHEMA,
  message: object({ template_key: { const: 'payment_receipt_v1' }, purpose: { const: 'payment_receipt' }, body: text(2048), source_derived: yes }),
  checks: object({ source_visible: yes, previous_attempt_checked: yes, consent_or_authority_visible: yes }),
});
const account = object({ app_id: text(), app_version: text(), account_key: text(), sending_line_key: text() });
export const POLICY_SCHEMA = object({
  contract_version: { const: 1 }, policy_revision: text(),
  mode: { enum: ['dry_run', 'assisted', 'approved_autonomous'] }, live_dispatch_enabled: { type: 'boolean' },
  native_adapter: { enum: ['unconfigured', 'computer_use', 'mock'] },
  approved_channels: list({ enum: CHANNELS }, 2), approved_purposes: list({ const: 'payment_receipt' }, 1),
  excluded_recipient_keys: list(text()),
  channel_accounts: object({ messages_native: account, whatsapp_native: account }, []),
  admin_browser: { anyOf: [object({ origin: { const: 'https://platform-admin.collect.ikanisa.com' }, account_key: text() }), { const: null }] },
  max_source_age_seconds: { type: 'integer', minimum: 1, maximum: 300 },
  lease_seconds: { type: 'integer', minimum: 1, maximum: 120 },
  test_gate: object({ enabled: { type: 'boolean' }, owner_designated_recipient_keys: list(text()), expires_at: { anyOf: [instant, { const: null }] } }),
});
export const EMPTY_SCHEMA = object({});
export const EXECUTE_SCHEMA = object({ ticket_id: text(), executor_id: text() });
export const ATTEMPT_SCHEMA = object({ attempt_id: text(), executor_id: text() });
export const RECONCILE_SCHEMA = object({ attempt_id: text(), executor_id: text(), recovery: object({
  lease_token: text(), lease_fence: { type: 'integer', minimum: 1, maximum: Number.MAX_SAFE_INTEGER }, owner_review_ref: text(512),
}) }, ['attempt_id', 'executor_id']);
export const STOP_SCHEMA = object({ reason: text(200) });
export const EXCEPTIONS_SCHEMA = object({ limit: { type: 'integer', minimum: 1, maximum: 100 } }, []);

// This validator implements only the schema vocabulary used by these contracts.
export function validate(schema, value, code = 'invalid_arguments') {
  const bad = () => fail(code);
  if (schema.anyOf) {
    if (!schema.anyOf.some(candidate => { try { validate(candidate, value, code); return true; } catch { return false; } })) bad();
  }
  if (Object.hasOwn(schema, 'const') && value !== schema.const) bad();
  if (schema.enum && !schema.enum.includes(value)) bad();
  if (schema.type === 'object') {
    if (!value || typeof value !== 'object' || Array.isArray(value) || ![Object.prototype, null].includes(Object.getPrototypeOf(value))) bad();
    if (schema.required.some(key => !Object.hasOwn(value, key)) || Object.keys(value).some(key => !Object.hasOwn(schema.properties, key))) bad();
    for (const [key, item] of Object.entries(value)) validate(schema.properties[key], item, code);
  }
  if (schema.type === 'array') {
    if (!Array.isArray(value) || value.length > schema.maxItems || new Set(value.map(canonical)).size !== value.length) bad();
    for (const item of value) validate(schema.items, item, code);
  }
  if (schema.type === 'boolean' && typeof value !== 'boolean') bad();
  if (schema.type === 'integer' && (!Number.isSafeInteger(value) || value < schema.minimum || value > schema.maximum)) bad();
  if (schema.type === 'string') {
    if (typeof value !== 'string' || value.length < (schema.minLength ?? 0) || value.length > (schema.maxLength ?? 4096) || schema.pattern && !new RegExp(schema.pattern).test(value)) bad();
    if (schema.format === 'date-time' && (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(value) ||
        !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().replace('.000Z', 'Z') !== value.replace('.000Z', 'Z'))) bad();
  }
  return structuredClone(value);
}
export function canonical(value) {
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
  return JSON.stringify(value);
}
export const digest = value => createHash('sha256').update(canonical(value)).digest('hex');
export const receiptBody = source => `Payment confirmed. Reference: ${source.transaction_reference}. Amount: ${source.amount_label}. Balance: ${source.balance_label}.`;
export const operationKey = source => digest([source.source_namespace, source.tenant_id, source.transaction_reference, source.notification_kind]);
export const sourceFacts = source => { const { observed_at, ...facts } = source; return facts; };
export const DEFAULT_POLICY = Object.freeze({
  contract_version: 1, policy_revision: 'direct-desktop-dry-run-v1', mode: 'dry_run', live_dispatch_enabled: false,
  native_adapter: 'unconfigured', approved_channels: ['messages_native'], approved_purposes: ['payment_receipt'],
  excluded_recipient_keys: [], channel_accounts: {}, max_source_age_seconds: 300, lease_seconds: 60,
  admin_browser: null,
  test_gate: { enabled: false, owner_designated_recipient_keys: [], expires_at: null },
});
export function policySnapshot(value) {
  const policy = validate(POLICY_SCHEMA, value, 'invalid_policy');
  if (policy.test_gate.enabled && (!policy.test_gate.expires_at || !policy.test_gate.owner_designated_recipient_keys.length)) fail('invalid_policy');
  return { policy, hash: digest(policy) };
}
