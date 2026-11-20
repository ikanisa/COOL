import {useEffect, useLayoutEffect, useRef, useState, type FormEvent} from 'react';
import type {JsonObject} from '../../api/client';
import {sensitiveVerificationDeadline, useSession} from '../../session/SessionProvider';
import type {PendingAttempt} from '../core/pendingAttempt';
import {Button, Card, Dialog, EmptyState, ErrorState, Field, LoadingState, PageHeader, StatusBadge} from '../../ui';
import {checkSmsPolicyOriginal, disableSmsPolicy, enableSmsPolicy, replaySmsPolicy, SmsPolicyOutcomeUnknown, type SmsPolicyContext, type SmsPolicyOriginal} from './smsPolicyMutations';
import {changeSmsAccess, checkSmsAccessOriginal, listSmsManagementPending, replaySmsAccess, SmsAccessOutcomeUnknown, type SmsAccessContext, type SmsAccessOriginal} from './smsAccessMutations';
import {parseSmsMaterializationStatus, type SmsMaterializationStatus} from './smsMaterializationStatus';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH = /^[0-9a-f]{64}$/;
const TEMPLATE = 'collect.recorded_contribution.v1';
const LIMIT = 25;
const marker = ['contract_version', 'scope', 'legal_release_approved', 'provider_approved', 'delivery_confirmed'];
type HistoryKind = 'access' | 'policy' | 'materialization';
export interface SmsAccessState {adminId: string; principalId: string; revision: number; readGranted: boolean; manageGranted: boolean; canOperate: boolean}
export interface SmsPolicyState {collectionId: string; configured: boolean; enabled: boolean; revision: number; collectionActive: boolean; decisionHash: string | null; recordedAt: string | null}
export interface SmsHistoryCursor {after_created_at: string; after_request_id: string}
export interface SmsHistoryItem {requestId: string; kind: HistoryKind; recordedAt: string; outcome: string}
export interface SmsHistoryPage {items: SmsHistoryItem[]; next: SmsHistoryCursor | null}
export interface SmsDecisionDetail {kind: 'access' | 'policy'; requestId: string; observed: boolean; decision: {enabled: boolean; revision: number; recordedAt: string; hash: string; collectionId: string | null} | null; currentAccess: SmsAccessState | null}
export interface SmsAccessReceipt {enabled: boolean; revision: number; recordedAt: string; hash: string; replay: boolean}

function invalid(): never {throw new Error('The receipt SMS configuration could not be verified.');}
function object(value: unknown): value is JsonObject {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function keys(value: JsonObject, fields: string[]) {if (Object.keys(value).length !== fields.length || fields.some((field) => !Object.hasOwn(value, field))) invalid();}
function id(value: unknown): string {if (typeof value !== 'string' || !UUID.test(value)) return invalid(); return value.toLowerCase();}
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
export function parseSmsHistory(body: JsonObject, after: SmsHistoryCursor | null = null, limit = LIMIT): SmsHistoryPage {
  if (!Number.isInteger(limit) || limit < 1 || limit > 25) return invalid();
  const row = envelope(body, 'own_receipt_sms_request_history', ['items', 'next_cursor', 'original_session_only', 'recorded_state_only', 'may_send', 'replay_authorized']);
  if (row.original_session_only !== true || row.recorded_state_only !== true || row.may_send !== false || row.replay_authorized !== false || !Array.isArray(row.items) || row.items.length > limit) return invalid();
  const prefixes = {access: '/api/admin/notification-operator/access/operations/', policy: '/api/admin/notification-operator/policies/operations/', materialization: '/api/admin/notification-operator/materialize/'} as const;
  const seen = new Set<string>(); let boundary = after ? parseCursor(after) : null;
  const items = row.items.map((value): SmsHistoryItem => {
    if (!object(value)) return invalid(); keys(value, ['request_id', 'kind', 'recorded_at', 'recorded_outcome', 'status_path', 'recorded_state_only', 'may_send']);
    const requestId = id(value.request_id), recordedAt = timestamp(value.recorded_at);
    if (requestId !== value.request_id || !['access', 'policy', 'materialization'].includes(String(value.kind))) return invalid();
    const kind = value.kind as HistoryKind, outcome = kind === 'materialization' ? 'plan_recorded' : 'decision_recorded';
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

function showTime(value: string) {return new Intl.DateTimeFormat('en-GB', {timeZone: 'Africa/Kigali', dateStyle: 'medium', timeStyle: 'short'}).format(new Date(value));}
function historyKind(value: HistoryKind) {return value === 'access' ? 'Account access' : value === 'policy' ? 'Group policy' : 'Job preparation';}

/** Changes require explicit deployment qualification; all gates default off. */
export function SmsControlsPage({onVerify, allowPolicyChanges = false, allowPolicyEnabling = false, allowAccessChanges = false}: {onVerify: () => void; allowPolicyChanges?: boolean; allowPolicyEnabling?: boolean; allowAccessChanges?: boolean}) {
  const session = useSession(), user = session.user;
  if (!user || user.role !== 'owner' || user.email !== 'info@ikanisa.com' || !user.permissions.includes('admin_users.manage') || !UUID.test(user.id) || !user.principalId || !UUID.test(user.principalId) || !UUID.test(user.sessionId)) return <><PageHeader title="SMS controls" /><ErrorState title="Access unavailable" message="This page requires current owner access." /></>;
  return <Controls key={JSON.stringify([session.epoch, user.id, user.sessionId, user.principalId])} onVerify={onVerify} allowPolicyChanges={allowPolicyChanges} allowPolicyEnabling={allowPolicyEnabling} allowAccessChanges={allowAccessChanges} />;
}

interface Loaded {access: SmsAccessState; history: SmsHistoryPage | null; historyError: string; policy: SmsPolicyState | null; policyError: string; detail: SmsDecisionDetail | SmsMaterializationStatus | null; detailError: string}
function Controls({onVerify, allowPolicyChanges, allowPolicyEnabling, allowAccessChanges}: {onVerify: () => void; allowPolicyChanges: boolean; allowPolicyEnabling: boolean; allowAccessChanges: boolean}) {
  const session = useSession(), user = session.user!;
  const {epoch, request, recheckSensitiveEmailVerification, isRecentSensitiveVerification, verificationMode} = session;
  const actorId = user.id, principalId = user.principalId!, sessionId = user.sessionId, canReadPolicy = user.permissions.includes('assisted_sms.manage');
  const deadline = sensitiveVerificationDeadline(user, verificationMode === 'email' ? 'supabase' : 'cloudflare') ?? 0;
  const [clock, setClock] = useState(() => Date.now()), [foreground, setForeground] = useState(() => document.visibilityState === 'visible');
  const [revision, setRevision] = useState(0), [groupInput, setGroupInput] = useState(''), [group, setGroup] = useState<string | null>(null), [inputError, setInputError] = useState('');
  const [selected, setSelected] = useState<SmsHistoryItem | null>(null);
  const [pageCursor, setPageCursor] = useState<SmsHistoryCursor | null>(null), [previous, setPrevious] = useState<(SmsHistoryCursor | null)[]>([]);
  const [result, setResult] = useState<{key: string; data: Loaded} | {key: string; error: string} | null>(null);
  const [pending, setPending] = useState<PendingAttempt[] | null>(null), [original, setOriginal] = useState<SmsPolicyOriginal | null>(null), [accessOriginal, setAccessOriginal] = useState<SmsAccessOriginal | null>(null);
  const [busy, setBusy] = useState(false), [actionError, setActionError] = useState(''), [actionMessage, setActionMessage] = useState(''), [retryReady, setRetryReady] = useState('');
  const [confirm, setConfirm] = useState<'disable-policy' | 'enable-policy' | 'retry-policy' | 'enable-access' | 'disable-access' | 'retry-access' | null>(null), [accessConfirmed, setAccessConfirmed] = useState(false), [policyConfirmed, setPolicyConfirmed] = useState(false), [reopenRequired, setReopenRequired] = useState(false), lifecycle = useRef(0);
  const policyGates = useRef({changes: allowPolicyChanges, enabling: allowPolicyEnabling});
  useLayoutEffect(() => {policyGates.current = {changes: allowPolicyChanges, enabling: allowPolicyEnabling}; return () => {policyGates.current = {changes: false, enabling: false};};}, [allowPolicyChanges, allowPolicyEnabling]);
  const key = `${epoch}:${pageCursor?.after_created_at ?? ''}:${pageCursor?.after_request_id ?? ''}:${group ?? ''}:${selected?.requestId ?? ''}:${revision}`;
  const allowed = foreground && clock <= deadline && isRecentSensitiveVerification(epoch, actorId, sessionId);
  const context = (): SmsPolicyContext => ({allowPolicyChanges, allowPolicyEnabling, mutationCurrent: () => policyGates.current.changes, enablementCurrent: () => policyGates.current.enabling, authorityEpoch: epoch, identity: {id: user.id, sessionId: user.sessionId, email: user.email, role: user.role, permissions: user.permissions, expiresAt: user.expiresAt, principalId}, request, verifyFresh: verificationMode === 'email' ? recheckSensitiveEmailVerification : async () => isRecentSensitiveVerification(epoch, actorId, sessionId), isCurrent: () => document.visibilityState === 'visible' && isRecentSensitiveVerification(epoch, actorId, sessionId), parsePolicy: parseSmsPolicy, parseReceipt: (body, requestId) => parseSmsPolicyReceipt(body, requestId, principalId, sessionId), parseStatus: (body, requestId) => parseSmsDecision(body, 'policy', requestId, actorId, principalId, sessionId)});
  const accessContext = (): SmsAccessContext => ({allowAccessChanges, authorityEpoch: epoch, identity: {id: user.id, sessionId: user.sessionId, email: user.email, role: user.role, permissions: user.permissions, expiresAt: user.expiresAt, principalId}, request, verifyFresh: verificationMode === 'email' ? recheckSensitiveEmailVerification : async () => isRecentSensitiveVerification(epoch, actorId, sessionId), isCurrent: () => document.visibilityState === 'visible' && isRecentSensitiveVerification(epoch, actorId, sessionId), parseAccess: (body) => parseSmsAccess(body, actorId, principalId), parseReceipt: (body, requestId) => parseSmsAccessReceipt(body, requestId, actorId, principalId, sessionId), parseStatus: (body, requestId) => parseSmsDecision(body, 'access', requestId, actorId, principalId, sessionId)});
  useEffect(() => {
    const changed = () => {const visible = document.visibilityState === 'visible'; if (!visible) {lifecycle.current++; setOriginal(null); setAccessOriginal(null); setRetryReady(''); setPending(null); setConfirm(null); setAccessConfirmed(false); setPolicyConfirmed(false); setBusy(false); setRevision((value) => value + 1);} setForeground(visible);};
    document.addEventListener('visibilitychange', changed); return () => document.removeEventListener('visibilitychange', changed);
  }, []);
  useEffect(() => {
    if (!deadline) return;
    const timer = setTimeout(() => {lifecycle.current++; setOriginal(null); setAccessOriginal(null); setRetryReady(''); setPending(null); setConfirm(null); setAccessConfirmed(false); setPolicyConfirmed(false); setBusy(false); setClock(Date.now());}, Math.max(0, deadline - Date.now() + 1)); return () => clearTimeout(timer);
  }, [deadline]);
  useEffect(() => () => {lifecycle.current++;}, []);
  useEffect(() => {
    if (!allowed) return;
    let active = true;
    const current = () => active && isRecentSensitiveVerification(epoch, actorId, sessionId);
    void (async () => {
      try {
        if (verificationMode === 'email' && !(await recheckSensitiveEmailVerification())) throw new Error('Verify your email before continuing.');
        if (!current()) return;
        const access = parseSmsAccess(await request('notification-operator/access', {method: 'GET', authenticated: true}), actorId, principalId);
        if (!current()) return;
        let history: SmsHistoryPage | null = null, historyError = '', policy: SmsPolicyState | null = null, policyError = '', detail: SmsDecisionDetail | SmsMaterializationStatus | null = null, detailError = '';
        try {
          const query = new URLSearchParams({limit: String(LIMIT)});
          if (pageCursor) {query.set('after_created_at', pageCursor.after_created_at); query.set('after_request_id', pageCursor.after_request_id);}
          history = parseSmsHistory(await request(`notification-operator/operations?${query}`, {method: 'GET', authenticated: true}), pageCursor);
        } catch {historyError = 'Recorded requests could not be loaded.';}
        if (!current()) return;
        if (group && canReadPolicy) {
          try {policy = parseSmsPolicy(await request(`notification-operator/policies/${group}`, {method: 'GET', authenticated: true}), group);}
          catch {policyError = 'The group policy could not be loaded.';}
        }
        if (!current()) return;
        if (selected && (selected.kind === 'access' || canReadPolicy)) {
          if (!history?.items.some((item) => item.requestId === selected.requestId && item.kind === selected.kind)) detailError = 'The recorded request is no longer on this history page.';
          else {
            try {
              if (selected.kind === 'materialization') {
                detail = parseSmsMaterializationStatus(await request(`notification-operator/materialize/${selected.requestId}`, {method: 'GET', authenticated: true}), selected.requestId, sessionId);
              } else {
                const path = selected.kind === 'access' ? `notification-operator/access/operations/${selected.requestId}` : `notification-operator/policies/operations/${selected.requestId}`;
                detail = await parseSmsDecision(await request(path, {method: 'GET', authenticated: true}), selected.kind, selected.requestId, actorId, principalId, sessionId);
              }
            } catch {detailError = 'The recorded request status could not be verified.';}
          }
        }
        if (current()) setResult({key, data: {access, history, historyError, policy, policyError, detail, detailError}});
      } catch {if (current()) setResult({key, error: 'Current receipt SMS access could not be loaded.'});}
    })();
    return () => {active = false;};
  }, [actorId, allowed, canReadPolicy, epoch, group, isRecentSensitiveVerification, key, pageCursor, principalId, recheckSensitiveEmailVerification, request, selected, sessionId, verificationMode]);
  const current = result?.key === key ? result : null;
  function searchGroup(event: FormEvent) {
    event.preventDefault(); if (busy) return; const value = groupInput.trim();
    if (!UUID.test(value)) {setInputError('Enter a valid group UUID.'); return;}
    setInputError(''); setGroup(value.toLowerCase()); setRevision((value) => value + 1);
  }
  async function disable(expected: SmsPolicyState) {
    if (busy || !allowPolicyChanges) return;
    const task = lifecycle.current; setBusy(true); setActionError(''); setActionMessage(''); setConfirm(null); setRetryReady('');
    try {
      await disableSmsPolicy(context(), expected);
      if (task === lifecycle.current) {setPending(null); setOriginal(null); setActionMessage('The policy decision was recorded. Review the current policy after refresh.'); setRevision((value) => value + 1);}
    } catch (failure) {
      if (task === lifecycle.current) {
        if (failure instanceof SmsPolicyOutcomeUnknown) {setPending([failure.checkpoint]); setOriginal(failure.original);}
        setActionError(failure instanceof Error ? failure.message : 'The policy change could not be confirmed.');
      }
    } finally {if (task === lifecycle.current) setBusy(false);}
  }
  async function enable(expected: SmsPolicyState) {
    if (busy || !allowPolicyChanges || !allowPolicyEnabling || !policyConfirmed) return;
    const task = lifecycle.current; setBusy(true); setActionError(''); setActionMessage(''); setConfirm(null); setRetryReady(''); setPolicyConfirmed(false);
    try {
      await enableSmsPolicy(context(), expected, true);
      if (task === lifecycle.current) {setPending(null); setOriginal(null); setActionMessage('The policy decision was recorded. Review the current policy after refresh.'); setRevision((value) => value + 1);}
    } catch (failure) {
      if (task === lifecycle.current) {
        if (failure instanceof SmsPolicyOutcomeUnknown) {setPending([failure.checkpoint]); setOriginal(failure.original);}
        setActionError(failure instanceof Error ? failure.message : 'The policy change could not be confirmed.');
      }
    } finally {if (task === lifecycle.current) setBusy(false);}
  }
  async function reviewPending() {
    if (busy) return; const task = lifecycle.current; setBusy(true); setActionError(''); setRetryReady('');
    try {const values = await listSmsManagementPending(accessContext()); if (task === lifecycle.current) setPending(values);}
    catch (failure) {if (task === lifecycle.current) setActionError(failure instanceof Error ? failure.message : 'Original requests could not be loaded.');}
    finally {if (task === lifecycle.current) setBusy(false);}
  }
  async function checkOriginal(saved: PendingAttempt) {
    if (busy) return; const task = lifecycle.current; setBusy(true); setActionError(''); setActionMessage(''); setRetryReady('');
    try {
      const isAccess = saved.intent.action === 'access';
      const same = isAccess ? accessOriginal?.requestId === saved.request_key ? accessOriginal : null : original?.requestId === saved.request_key ? original : null;
      const status = isAccess ? await checkSmsAccessOriginal(accessContext(), saved, same as SmsAccessOriginal | null) : await checkSmsPolicyOriginal(context(), saved, same as SmsPolicyOriginal | null);
      if (task !== lifecycle.current) return;
      if (status.observed) {
        setPending((values) => values?.filter((value) => value.request_key !== saved.request_key) ?? null); setOriginal(null); setAccessOriginal(null);
        if (isAccess) await refreshAfterAccess(status.currentAccess, task);
        else {setActionMessage('The original policy decision was recorded. Review the current policy separately.'); setRevision((value) => value + 1);}
      } else {setActionMessage('No recorded result was observed. The original request may still be in flight.'); if (same && (isAccess ? allowAccessChanges : allowPolicyChanges && (!(same as SmsPolicyOriginal).enabled || allowPolicyEnabling))) setRetryReady(saved.request_key);}
    } catch (failure) {if (task === lifecycle.current) setActionError(failure instanceof Error ? failure.message : 'The original request could not be checked.');}
    finally {if (task === lifecycle.current) setBusy(false);}
  }
  async function retryOriginal() {
    const saved = pending?.find((value) => value.request_key === retryReady);
    if (busy || !saved) return;
    const task = lifecycle.current; setBusy(true); setConfirm(null); setRetryReady(''); setActionError(''); setActionMessage('');
    try {
      if (saved.intent.action === 'access' && accessOriginal && allowAccessChanges) {
        const result = await replaySmsAccess(accessContext(), saved, accessOriginal);
        if (task === lifecycle.current) {setPending(null); setAccessOriginal(null); await refreshAfterAccess(result.currentAccess, task);}
      } else if (saved.intent.action === 'policy' && original && allowPolicyChanges && (!original.enabled || allowPolicyEnabling)) {
        await replaySmsPolicy(context(), saved, original);
        if (task === lifecycle.current) {setPending(null); setOriginal(null); setActionMessage('The original policy decision was recorded. Review the current policy after refresh.'); setRevision((value) => value + 1);}
      } else throw new Error('Reopen the original request before retrying.');
    }
    catch (failure) {if (task === lifecycle.current) {if (failure instanceof SmsPolicyOutcomeUnknown) {setPending([failure.checkpoint]); setOriginal(failure.original);} if (failure instanceof SmsAccessOutcomeUnknown) {setPending([failure.checkpoint]); setAccessOriginal(failure.original);} setActionError(failure instanceof Error ? failure.message : 'The original request could not be retried.');}}
    finally {if (task === lifecycle.current) setBusy(false);}
  }
  async function refreshAfterAccess(access: SmsAccessState | null, task: number) {
    if (task !== lifecycle.current) return;
    setReopenRequired(true); setActionMessage(access ? 'The access decision was recorded and current grants were checked. Reopen controls after refreshing your sign-in.' : 'The access decision was recorded, but current grants could not be confirmed. Reopen controls after refreshing your sign-in.');
    try {await session.refresh();} catch {if (task === lifecycle.current) setActionError('Your sign-in could not be refreshed. Check the session before continuing.');}
  }
  async function changeAccess(expected: SmsAccessState, enabled: boolean) {
    if (busy || !allowAccessChanges || (enabled && !accessConfirmed)) return;
    const task = lifecycle.current; setBusy(true); setActionError(''); setActionMessage(''); setConfirm(null); setRetryReady(''); setAccessConfirmed(false);
    try {
      const result = await changeSmsAccess(accessContext(), expected, enabled, true);
      if (task === lifecycle.current) {setPending(null); setAccessOriginal(null); await refreshAfterAccess(result.currentAccess, task);}
    } catch (failure) {
      if (task === lifecycle.current) {if (failure instanceof SmsAccessOutcomeUnknown) {setPending([failure.checkpoint]); setAccessOriginal(failure.original);} setActionError(failure instanceof Error ? failure.message : 'The access change could not be confirmed.');}
    } finally {if (task === lifecycle.current) setBusy(false);}
  }
  return <><PageHeader title="SMS controls" subtitle="Review current receipt SMS access and group policy." actions={<Button icon="refresh" disabled={!allowed || !current || busy || reopenRequired} onClick={() => setRevision((value) => value + 1)}>Refresh</Button>} />
    {!foreground ? <Card><p>Controls are hidden while this tab is inactive.</p></Card> : !allowed ? <Card><h2>Verification required</h2><p>{verificationMode === 'email' ? 'Verify your email to open these controls.' : 'Verify your authenticator to open these controls.'}</p><Button onClick={onVerify}>{verificationMode === 'email' ? 'Verify email' : 'Verify authenticator'}</Button></Card> : reopenRequired ? <Card><h2>Reopen SMS controls</h2><p>{actionMessage}</p>{actionError && <p role="alert">{actionError}</p>}<Button disabled={busy} onClick={() => {setReopenRequired(false); setActionMessage(''); setRevision((value) => value + 1);}}>Reopen controls</Button></Card> :
      <>{!current ? <LoadingState label="Loading SMS controls" /> : 'error' in current ? <ErrorState message={current.error} onRetry={() => setRevision((value) => value + 1)} /> : <>
        {actionError && <p role="alert">{actionError}</p>}{actionMessage && <p role="status">{actionMessage}</p>}
        <Card><h2>Current account access</h2><p><StatusBadge tone={current.data.access.canOperate ? 'success' : 'neutral'}>{current.data.access.canOperate ? 'Operator access available' : 'Operator access unavailable'}</StatusBadge></p><p>Read access: {current.data.access.readGranted ? 'Granted' : 'Not granted'}<br />Manage access: {current.data.access.manageGranted ? 'Granted' : 'Not granted'}<br />Recorded decision revision: {current.data.access.revision}</p>{allowAccessChanges ? <>{!current.data.access.canOperate && <Button disabled={busy} onClick={() => {setAccessConfirmed(false); setConfirm('enable-access');}}>Enable my SMS access</Button>}{(current.data.access.readGranted || current.data.access.manageGranted) && <Button variant="danger" disabled={busy} onClick={() => setConfirm('disable-access')}>Remove my SMS access</Button>}</> : <p>Changes to account access are currently unavailable.</p>}</Card>
        <Card><h2>Group policy</h2>{canReadPolicy ? <><form onSubmit={searchGroup}><Field label="Group UUID" htmlFor="sms-control-group" error={inputError}><input className="admin-input" id="sms-control-group" value={groupInput} onChange={(event) => setGroupInput(event.target.value)} disabled={busy} /></Field><Button type="submit" disabled={busy}>View policy</Button></form>{current.data.policyError && <p role="alert">{current.data.policyError}</p>}{current.data.policy && <div><p>Group: {current.data.policy.collectionId}<br />Group status: {current.data.policy.collectionActive ? 'Active' : 'Not active'}<br />Policy: {current.data.policy.configured ? current.data.policy.enabled ? 'Enabled' : 'Disabled' : 'Not configured'}<br />Revision: {current.data.policy.revision}<br />Recorded: {current.data.policy.recordedAt ? showTime(current.data.policy.recordedAt) : 'Not recorded'}</p>{allowPolicyChanges && allowPolicyEnabling && !current.data.policy.enabled && current.data.policy.collectionActive && <Button disabled={busy} onClick={() => {setPolicyConfirmed(false); setConfirm('enable-policy');}}>Enable receipt SMS policy</Button>}{allowPolicyChanges && current.data.policy.enabled && <Button variant="danger" disabled={busy} onClick={() => setConfirm('disable-policy')}>Disable current group policy</Button>}</div>}</> : <p>Current access does not include permission to view group policy.</p>}</Card>
        <Card><h2>Original SMS control requests</h2><p>Check retained requests in this tab before making another change.</p><Button disabled={busy} onClick={() => void reviewPending()}>Review pending requests</Button>{pending?.length === 0 && <p>No pending control requests were found in this tab.</p>}{pending?.map((saved) => <div key={saved.request_key}><p>{saved.intent.action === 'policy' ? 'Group policy' : 'Account access'} request: {saved.request_key}</p>{saved.intent.action === 'access' || canReadPolicy ? <Button disabled={busy} onClick={() => void checkOriginal(saved)}>Check original request</Button> : <p>Current access does not permit checking this policy request.</p>}{retryReady === saved.request_key && <Button disabled={busy || !(saved.intent.action === 'access' ? allowAccessChanges : allowPolicyChanges && (!original?.enabled || allowPolicyEnabling))} onClick={() => setConfirm(saved.intent.action === 'access' ? 'retry-access' : 'retry-policy')}>Retry same request</Button>}</div>)}</Card>
        <Card><h2>Recorded requests</h2><p>These records belong to this sign-in and do not authorize sending or replay.</p>{current.data.historyError ? <p role="alert">{current.data.historyError}</p> : current.data.history?.items.length ? <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th scope="col">Request ID</th><th scope="col">Type</th><th scope="col">Recorded</th><th scope="col">Status</th><th scope="col">Details</th></tr></thead><tbody>{current.data.history.items.map((item) => <tr key={item.requestId}><td>{item.requestId}</td><td>{historyKind(item.kind)}</td><td>{showTime(item.recordedAt)}</td><td>{item.outcome === 'plan_recorded' ? 'Plan recorded' : 'Decision recorded'}</td><td>{(item.kind === 'access' || canReadPolicy) ? <Button disabled={busy} onClick={() => setSelected(item)}>View recorded status</Button> : 'Unavailable'}</td></tr>)}</tbody></table></div> : <EmptyState title="No recorded requests" />}{current.data.history && <div><Button disabled={busy || previous.length === 0} onClick={() => {setSelected(null); setPageCursor(previous[previous.length - 1]); setPrevious((value) => value.slice(0, -1));}}>Previous requests</Button> <Button disabled={busy || !current.data.history.next} onClick={() => {const next = current.data.history?.next; if (next) {setSelected(null); setPrevious((value) => [...value, pageCursor]); setPageCursor(next);}}}>Next requests</Button></div>}
          {current.data.detailError && <p role="alert">{current.data.detailError}</p>}{current.data.detail && (current.data.detail.kind === 'materialization' ? <div><h3>Recorded job preparation status</h3><p>Original request: {current.data.detail.requestId}</p>{current.data.detail.observed ? <><p>Group: {current.data.detail.collectionId}<br />Status: {current.data.detail.status.replaceAll('_', ' ')}<br />Planned sources: {current.data.detail.plannedCount}<br />Recorded jobs: {current.data.detail.materializedCount}<br />Recorded: {current.data.detail.recordedAt ? showTime(current.data.detail.recordedAt) : 'Not recorded'}<br />More sources observed: {current.data.detail.hasMore ? 'Yes' : 'No'}</p>{current.data.detail.items.length > 0 && <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th scope="col">Source entry</th><th scope="col">Payment</th><th scope="col">Status</th><th scope="col">Job</th><th scope="col">Reason</th></tr></thead><tbody>{current.data.detail.items.map((item) => <tr key={item.entryId}><td>{item.entryId}</td><td>{item.paymentId}</td><td>{item.status}</td><td>{item.jobId ?? '—'}</td><td>{item.code ?? '—'}</td></tr>)}</tbody></table></div>}<p>This is the recorded bounded plan; it does not establish that all source events are complete.</p></> : <p>No recorded plan was observed. The request may still be in flight.</p>}<p>This status does not authorize a retry or sending. Job preparation did not start transport.</p></div> : <div><h3>Recorded request status</h3>{current.data.detail.decision ? <><p>Original request: {current.data.detail.requestId}<br />Recorded decision: {current.data.detail.decision.enabled ? 'Enabled' : 'Disabled'}<br />Recorded revision: {current.data.detail.decision.revision}<br />Recorded: {showTime(current.data.detail.decision.recordedAt)}</p>{current.data.detail.decision.collectionId && <><p>Group: {current.data.detail.decision.collectionId}. This historical decision is not the current group policy.</p><Button disabled={busy} onClick={() => {const detail = current.data.detail; const collectionId = detail?.kind !== 'materialization' ? detail?.decision?.collectionId : null; if (collectionId) {setGroupInput(collectionId); setGroup(collectionId); setRevision((value) => value + 1);}}}>Check current group policy</Button></>}</> : <p>No recorded result was observed. The request may still be in flight.</p>}{current.data.detail.currentAccess && <p>Current access revision: {current.data.detail.currentAccess.revision}. Both operational grants: {current.data.detail.currentAccess.canOperate ? 'Present' : 'Not present'}.</p>}</div>)}
        </Card>
        <p>These records do not confirm provider approval or delivery.</p>
        <Dialog open={confirm !== null} title={confirm === 'retry-policy' ? 'Retry original policy request?' : confirm === 'retry-access' ? 'Retry original access request?' : confirm === 'enable-access' ? 'Enable my SMS access?' : confirm === 'enable-policy' ? 'Enable group policy?' : confirm === 'disable-access' ? 'Remove my SMS access?' : 'Disable group policy?'} onClose={() => {if (!busy) setConfirm(null);}} footer={<><Button disabled={busy} onClick={() => setConfirm(null)}>Cancel</Button><Button variant={confirm === 'enable-access' || confirm === 'enable-policy' ? 'primary' : 'danger'} disabled={busy || (confirm === 'enable-access' && !accessConfirmed) || (confirm === 'enable-policy' && !policyConfirmed)} onClick={() => {if (confirm === 'retry-policy' || confirm === 'retry-access') void retryOriginal(); else if (confirm === 'enable-access' || confirm === 'disable-access') void changeAccess(current.data.access, confirm === 'enable-access'); else if (confirm === 'enable-policy' && current.data.policy) void enable(current.data.policy); else if (current.data.policy) void disable(current.data.policy);}}>{confirm === 'retry-policy' || confirm === 'retry-access' ? 'Retry same request' : confirm === 'enable-access' ? 'Enable access' : confirm === 'enable-policy' ? 'Enable policy' : confirm === 'disable-access' ? 'Remove access' : 'Disable policy'}</Button></>}>
          {confirm === 'retry-policy' ? <p>Retry the original {original?.enabled ? 'enable' : 'disable'} request for group {original?.collectionId}, using its original reference and revision {original?.expectedRevision}.</p> : confirm === 'retry-access' ? <p>Retry the original {accessOriginal?.enabled ? 'enable' : 'remove'} decision for your account using its original reference and revision {accessOriginal?.expectedRevision}.</p> : confirm === 'enable-access' ? <><p>Allow your account to view jobs and manage assisted SMS. This does not approve sending or delivery.</p><label><input type="checkbox" checked={accessConfirmed} onChange={(event) => setAccessConfirmed(event.target.checked)} /> I confirm access for my current account.</label></> : confirm === 'enable-policy' ? <><p>Enable receipt SMS policy for group {current.data.policy?.collectionId} at revision {current.data.policy?.revision}. This records a policy decision; provider approval and delivery are not confirmed.</p><label><input type="checkbox" checked={policyConfirmed} onChange={(event) => setPolicyConfirmed(event.target.checked)} /> I confirm enabling policy for this group and revision.</label></> : confirm === 'disable-access' ? <p>Remove your account’s assisted SMS read and management grants at revision {current.data.access.revision}.</p> : <p>Disable receipt SMS for group {current.data.policy?.collectionId} at revision {current.data.policy?.revision}.</p>}
        </Dialog>
      </>}</>}
  </>;
}
