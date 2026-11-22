import type {JsonObject} from '../../api/client';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH = /^[0-9a-f]{64}$/;
const TEMPLATE = 'collect.recorded_contribution.v1';
export const SMS_HISTORY_PAGE_SIZE = 25;
const marker = ['contract_version', 'scope', 'legal_release_approved', 'provider_approved', 'delivery_confirmed'];
export type SmsHistoryKind = 'access' | 'policy' | 'materialization';
export interface SmsAccessState {adminId: string; principalId: string; revision: number; readGranted: boolean; manageGranted: boolean; canOperate: boolean}
export interface SmsPolicyState {collectionId: string; configured: boolean; enabled: boolean; revision: number; collectionActive: boolean; decisionHash: string | null; recordedAt: string | null}
export interface SmsHistoryCursor {after_created_at: string; after_request_id: string}
export interface SmsHistoryItem {requestId: string; kind: SmsHistoryKind; recordedAt: string; outcome: string}
export interface SmsHistoryPage {items: SmsHistoryItem[]; next: SmsHistoryCursor | null}
export interface SmsDecisionDetail {kind: 'access' | 'policy'; requestId: string; observed: boolean; decision: {enabled: boolean; revision: number; recordedAt: string; hash: string; collectionId: string | null} | null; currentAccess: SmsAccessState | null}
export interface SmsAccessReceipt {enabled: boolean; revision: number; recordedAt: string; hash: string; replay: boolean}

function invalid(): never {throw new Error('The receipt SMS configuration could not be verified.');}
function object(value: unknown): value is JsonObject {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function keys(value: JsonObject, fields: string[]) {if (Object.keys(value).length !== fields.length || fields.some((field) => !Object.hasOwn(value, field))) invalid();}
export function isSmsControlId(value: unknown): value is string {return typeof value === 'string' && UUID.test(value);}
function id(value: unknown): string {if (!isSmsControlId(value)) return invalid(); return value.toLowerCase();}
function integer(value: unknown, max = Number.MAX_SAFE_INTEGER): number {if (!Number.isSafeInteger(value) || (value as number) < 0 || (value as number) > max) return invalid(); return value as number;}
function boolean(value: unknown): boolean {if (typeof value !== 'boolean') return invalid(); return value;}
function timestamp(value: unknown): string {
  if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)) return invalid();
  const date = new Date(value); if (!Number.isFinite(date.getTime()) || date.toISOString() !== value) return invalid(); return value;
}
function envelope(body: JsonObject, scope: string, fields: string[]): JsonObject {
  keys(body, ['ok', 'result']);
  if (body.ok !== true || !object(body.result)) return invalid();
  const row = body.result; keys(row, [...marker, ...fields]);
  if (row.contract_version !== 1 || row.scope !== scope || row.legal_release_approved !== false || row.provider_approved !== false || row.delivery_confirmed !== false) return invalid();
  return row;
}
export function parseSmsAccess(body: JsonObject, actorId: string, principalId: string): SmsAccessState {
  const row = envelope(body, 'owner_receipt_sms_access', ['current_admin_id', 'current_principal_id', 'decision_revision', 'read_granted', 'manage_granted', 'can_operate', 'permissions']);
  const adminId = id(row.current_admin_id), principal = id(row.current_principal_id), readGranted = boolean(row.read_granted), manageGranted = boolean(row.manage_granted), canOperate = boolean(row.can_operate);
  if (adminId !== id(actorId) || principal !== id(principalId) || !Array.isArray(row.permissions) || row.permissions.length !== 2 || row.permissions[0] !== 'assisted_sms.read' || row.permissions[1] !== 'assisted_sms.manage' || canOperate !== (readGranted && manageGranted)) return invalid();
  return {adminId, principalId: principal, revision: integer(row.decision_revision), readGranted, manageGranted, canOperate};
}
export function parseSmsPolicy(body: JsonObject, collectionId: string): SmsPolicyState {
  const row = envelope(body, 'owner_receipt_sms_configuration', ['collection_id', 'configured', 'enabled', 'revision', 'template_key', 'recorded_owner_decision_sha256', 'recorded_at', 'collection_active']);
  const collection = id(row.collection_id), configured = boolean(row.configured), enabled = boolean(row.enabled), revision = integer(row.revision, 999_999_999), active = boolean(row.collection_active);
  const hash = row.recorded_owner_decision_sha256 === null ? null : typeof row.recorded_owner_decision_sha256 === 'string' && HASH.test(row.recorded_owner_decision_sha256) ? row.recorded_owner_decision_sha256 : invalid();
  const recordedAt = row.recorded_at === null ? null : timestamp(row.recorded_at);
  if (collection !== id(collectionId) || row.template_key !== TEMPLATE || (configured ? revision < 1 || hash === null || recordedAt === null : revision !== 0 || enabled || hash !== null || recordedAt !== null)) return invalid();
  return {collectionId: collection, configured, enabled, revision, collectionActive: active, decisionHash: hash, recordedAt};
}
function parseCursor(value: unknown): SmsHistoryCursor {
  if (!object(value)) return invalid(); keys(value, ['after_created_at', 'after_request_id']);
  const requestId = id(value.after_request_id); if (requestId !== value.after_request_id) return invalid();
  return {after_created_at: timestamp(value.after_created_at), after_request_id: requestId};
}
export function parseSmsHistory(body: JsonObject, after: SmsHistoryCursor | null = null, limit = SMS_HISTORY_PAGE_SIZE): SmsHistoryPage {
  if (!Number.isInteger(limit) || limit < 1 || limit > 25) return invalid();
  const row = envelope(body, 'own_receipt_sms_request_history', ['items', 'next_cursor', 'original_session_only', 'recorded_state_only', 'may_send', 'replay_authorized']);
  if (row.original_session_only !== true || row.recorded_state_only !== true || row.may_send !== false || row.replay_authorized !== false || !Array.isArray(row.items) || row.items.length > limit) return invalid();
  const prefixes = {access: '/api/admin/notification-operator/access/operations/', policy: '/api/admin/notification-operator/policies/operations/', materialization: '/api/admin/notification-operator/materialize/'} as const;
  const seen = new Set<string>(); let boundary = after ? parseCursor(after) : null;
  const items = row.items.map((value): SmsHistoryItem => {
    if (!object(value)) return invalid(); keys(value, ['request_id', 'kind', 'recorded_at', 'recorded_outcome', 'status_path', 'recorded_state_only', 'may_send']);
    const requestId = id(value.request_id), recordedAt = timestamp(value.recorded_at);
    if (requestId !== value.request_id || !['access', 'policy', 'materialization'].includes(String(value.kind))) return invalid();
    const kind = value.kind as SmsHistoryKind, outcome = kind === 'materialization' ? 'plan_recorded' : 'decision_recorded';
    if (value.recorded_outcome !== outcome || value.status_path !== prefixes[kind] + requestId || value.recorded_state_only !== true || value.may_send !== false || seen.has(requestId)) return invalid();
    if (boundary && (recordedAt > boundary.after_created_at || (recordedAt === boundary.after_created_at && requestId >= boundary.after_request_id))) return invalid();
    seen.add(requestId); boundary = {after_created_at: recordedAt, after_request_id: requestId};
    return {requestId, recordedAt, kind, outcome};
  });
  const next = row.next_cursor === null ? null : parseCursor(row.next_cursor);
  if (next && (items.length !== limit || !boundary || next.after_created_at !== boundary.after_created_at || next.after_request_id !== boundary.after_request_id)) return invalid();
  return {items, next};
}

function stableJson(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  const row = value as JsonObject;
  return `{${Object.keys(row).sort().map((key) => `${JSON.stringify(key)}:${stableJson(row[key])}`).join(',')}}`;
}
async function decisionHash(row: JsonObject, fields: string[], expected: unknown) {
  if (typeof expected !== 'string' || !HASH.test(expected) || !globalThis.crypto?.subtle) invalid();
  const body = Object.fromEntries(fields.map((field) => [field, row[field]]));
  const digest = await globalThis.crypto.subtle.digest('SHA-256', new TextEncoder().encode(stableJson(body)));
  if ([...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, '0')).join('') !== expected) invalid();
}

/** Verify a recorded decision separately from current access or policy. */
export async function parseSmsDecision(body: JsonObject, kind: 'access' | 'policy', requestId: string, actorId: string, principalId: string, sessionId: string): Promise<SmsDecisionDetail> {
  const rid = id(requestId), access = kind === 'access';
  const row = envelope(body, access ? 'owner_receipt_sms_access_operation' : 'owner_receipt_sms_policy_operation', ['request_id', 'observed', 'status', 'may_be_in_flight', 'recorded_decision', 'recorded_state_only', 'may_send', 'replay_authorized', ...(access ? ['current_access'] : [])]);
  const observed = boolean(row.observed);
  if (row.request_id !== rid || row.status !== (observed ? 'recorded' : 'not_recorded') || row.may_be_in_flight !== !observed || (row.recorded_decision !== null) !== observed || row.recorded_state_only !== true || row.may_send !== false || row.replay_authorized !== false) return invalid();
  const currentAccess = access ? parseSmsAccess({ok: true, result: row.current_access}, actorId, principalId) : null;
  if (!observed) return {kind, requestId: rid, observed, decision: null, currentAccess};
  const receipt = row.recorded_decision;
  if (!object(receipt)) return invalid();
  const fields = access ? ['kind', 'request_id', 'grant_transaction_id', 'current_admin_id', 'current_principal_id', 'decision_revision', 'originating_session_id', 'public_session_id', 'enabled', 'permissions', 'recorded_at', 'read_granted', 'manage_granted', 'can_operate', 'decision_sha256', 'recorded_state_only', 'replay'] : ['kind', 'request_id', 'collection_id', 'revision', 'enabled', 'template_key', 'owner_user_id', 'originating_session_id', 'public_session_id', 'recorded_at', 'recorded_owner_decision_sha256'];
  keys(receipt, [...marker, ...fields]);
  if (receipt.contract_version !== 1 || receipt.scope !== (access ? 'owner_receipt_sms_access' : 'owner_receipt_sms_configuration') || receipt.legal_release_approved !== false || receipt.provider_approved !== false || receipt.delivery_confirmed !== false || id(receipt.request_id) !== rid || id(receipt.public_session_id) !== id(sessionId)) return invalid();
  id(receipt.originating_session_id);
  const enabled = boolean(receipt.enabled), recordedAt = timestamp(receipt.recorded_at);
  if (access) {
    if (receipt.kind !== 'authenticated_owner_receipt_sms_access' || id(receipt.current_admin_id) !== id(actorId) || id(receipt.current_principal_id) !== id(principalId) || !Array.isArray(receipt.permissions) || receipt.permissions.length !== 2 || receipt.permissions[0] !== 'assisted_sms.read' || receipt.permissions[1] !== 'assisted_sms.manage' || receipt.recorded_state_only !== true || receipt.replay !== false || boolean(receipt.read_granted) !== enabled || boolean(receipt.manage_granted) !== enabled || boolean(receipt.can_operate) !== enabled) return invalid();
    id(receipt.grant_transaction_id);
    const revision = integer(receipt.decision_revision);
    if (revision < 1 || !currentAccess || currentAccess.revision < revision) return invalid();
    await decisionHash(receipt, ['kind', 'request_id', 'grant_transaction_id', 'current_admin_id', 'current_principal_id', 'decision_revision', 'originating_session_id', 'public_session_id', 'enabled', 'permissions', 'recorded_at'], receipt.decision_sha256);
    return {kind, requestId: rid, observed, currentAccess, decision: {enabled, revision, recordedAt, hash: receipt.decision_sha256 as string, collectionId: null}};
  }
  if (receipt.kind !== 'authenticated_owner_receipt_sms_policy' || receipt.template_key !== TEMPLATE || id(receipt.owner_user_id) !== id(principalId)) return invalid();
  const collectionId = id(receipt.collection_id), revision = integer(receipt.revision, 999_999_999);
  if (revision < 1) return invalid();
  await decisionHash(receipt, ['kind', 'request_id', 'collection_id', 'revision', 'enabled', 'template_key', 'owner_user_id', 'originating_session_id', 'public_session_id', 'recorded_at', 'legal_release_approved', 'provider_approved'], receipt.recorded_owner_decision_sha256);
  return {kind, requestId: rid, observed, currentAccess, decision: {enabled, revision, recordedAt, hash: receipt.recorded_owner_decision_sha256 as string, collectionId}};
}

/** The policy POST returns a receipt, not a current-policy read or replay authority. */
export async function parseSmsPolicyReceipt(body: JsonObject, requestId: string, principalId: string, sessionId: string): Promise<NonNullable<SmsDecisionDetail['decision']>> {
  const receipt = envelope(body, 'owner_receipt_sms_configuration', ['kind', 'request_id', 'collection_id', 'revision', 'enabled', 'template_key', 'owner_user_id', 'originating_session_id', 'public_session_id', 'recorded_at', 'recorded_owner_decision_sha256']);
  if (receipt.kind !== 'authenticated_owner_receipt_sms_policy' || id(receipt.request_id) !== id(requestId) || receipt.template_key !== TEMPLATE || id(receipt.owner_user_id) !== id(principalId) || id(receipt.public_session_id) !== id(sessionId)) return invalid();
  id(receipt.originating_session_id);
  const collectionId = id(receipt.collection_id), revision = integer(receipt.revision, 999_999_999), enabled = boolean(receipt.enabled), recordedAt = timestamp(receipt.recorded_at);
  if (revision < 1) return invalid();
  await decisionHash(receipt, ['kind', 'request_id', 'collection_id', 'revision', 'enabled', 'template_key', 'owner_user_id', 'originating_session_id', 'public_session_id', 'recorded_at', 'legal_release_approved', 'provider_approved'], receipt.recorded_owner_decision_sha256);
  return {enabled, revision, recordedAt, hash: receipt.recorded_owner_decision_sha256 as string, collectionId};
}

/** A write receipt is historical evidence; it is never the current grant state. */
export async function parseSmsAccessReceipt(body: JsonObject, requestId: string, actorId: string, principalId: string, sessionId: string): Promise<SmsAccessReceipt> {
  const receipt = envelope(body, 'owner_receipt_sms_access', ['kind', 'request_id', 'grant_transaction_id', 'current_admin_id', 'current_principal_id', 'decision_revision', 'originating_session_id', 'public_session_id', 'enabled', 'permissions', 'recorded_at', 'read_granted', 'manage_granted', 'can_operate', 'decision_sha256', 'recorded_state_only', 'replay']);
  if (receipt.kind !== 'authenticated_owner_receipt_sms_access' || id(receipt.request_id) !== id(requestId) || id(receipt.current_admin_id) !== id(actorId) || id(receipt.current_principal_id) !== id(principalId) || id(receipt.public_session_id) !== id(sessionId) || !Array.isArray(receipt.permissions) || receipt.permissions.length !== 2 || receipt.permissions[0] !== 'assisted_sms.read' || receipt.permissions[1] !== 'assisted_sms.manage' || receipt.recorded_state_only !== true) return invalid();
  id(receipt.grant_transaction_id); id(receipt.originating_session_id);
  const enabled = boolean(receipt.enabled), revision = integer(receipt.decision_revision), recordedAt = timestamp(receipt.recorded_at), replay = boolean(receipt.replay);
  if (revision < 1 || boolean(receipt.read_granted) !== enabled || boolean(receipt.manage_granted) !== enabled || boolean(receipt.can_operate) !== enabled) return invalid();
  await decisionHash(receipt, ['kind', 'request_id', 'grant_transaction_id', 'current_admin_id', 'current_principal_id', 'decision_revision', 'originating_session_id', 'public_session_id', 'enabled', 'permissions', 'recorded_at'], receipt.decision_sha256);
  return {enabled, revision, recordedAt, hash: receipt.decision_sha256 as string, replay};
}
