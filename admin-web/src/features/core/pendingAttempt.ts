import {isAdminIdentityId} from '../../session/ownerIdentity';
import {custodyKey} from '../../custodyRealm';

/** Compatible with the retained Flutter Admin per-tab pending-attempt envelope.
 * It never replays a request: callers must check the original server key. */
export const PENDING_KEY = custodyKey('collect.admin.pending-attempts.v1');
export const EVIDENCE_CONTEXT_KEY = custodyKey('collect.admin.evidence-context.v1');
const MAX_AGE = 8 * 60 * 60 * 1000;
const MAX_BYTES = 65536;
const MAX_INTENT_BYTES = 16384;
const SECRET = /password|passwd|secret|token|cookie|authorization|credential|session/i;

export interface PendingIdentity {
  id: string;
  sessionId: string;
  email: string;
  role: 'owner' | 'admin' | 'staff';
  permissions: readonly string[];
  expiresAt: string;
}

export interface PendingAttempt {
  family: string;
  resource_id: string;
  request_key: string;
  permission: string;
  intent: Record<string, unknown>;
  created_at: number;
  expires_at: number;
}

interface Envelope { version: 1; authority: string; entries: PendingAttempt[] }
export interface EvidenceContext { version: 1; authority: string; request_key: string; group_id: string; payee_id: string; group_version: number; receiver_sha256: string }

function fail(): never { throw new Error('Recovery data could not be verified. Check the original request before continuing.'); }
function object(value: unknown): value is Record<string, unknown> { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function bytes(value: string): number { return new TextEncoder().encode(value).byteLength; }
function canonical(value: unknown, depth = 0): unknown {
  if (depth > 8) fail();
  if (value === null || typeof value === 'boolean') return value;
  if (typeof value === 'number' && Number.isSafeInteger(value)) return value;
  if (typeof value === 'string' && value.length <= 4000) return value;
  if (Array.isArray(value) && value.length <= 100) return value.map(item => canonical(item, depth + 1));
  if (!object(value)) fail();
  const keys = Object.keys(value).sort();
  if (keys.length > 100 || keys.some(key => !key || key.length > 80 || SECRET.test(key))) fail();
  return Object.fromEntries(keys.map(key => [key, canonical(value[key], depth + 1)]));
}

export async function sha256Text(text: string): Promise<string> {
  if (!globalThis.crypto?.subtle) fail();
  const digest = await globalThis.crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map(value => value.toString(16).padStart(2, '0')).join('');
}

export async function pendingAuthority(identity: PendingIdentity): Promise<string> {
  return sha256Text(JSON.stringify({
    actor: identity.id, session: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.stringify([...new Set(identity.permissions)].sort()),
  }));
}

export async function canonicalRequestId(principalId: string, key: string): Promise<string> {
  if (!isAdminIdentityId(principalId) || !/^[A-Za-z0-9_.-]{8,200}$/.test(key)) fail();
  const hash = await sha256Text(`collect-admin:${principalId}:${key}`);
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-4${hash.slice(13, 16)}-8${hash.slice(17, 20)}-${hash.slice(20, 32)}`;
}

function decode(storage: Storage, authority: string, now: number, identity: PendingIdentity): Envelope {
  if (!Number.isSafeInteger(now) || !Number.isFinite(Date.parse(identity.expiresAt))) fail();
  let raw: string | null;
  try { raw = storage.getItem(PENDING_KEY); } catch { return fail(); }
  if (raw === null) return { version: 1, authority, entries: [] };
  if (bytes(raw) > MAX_BYTES) fail();
  let data: unknown;
  try { data = JSON.parse(raw); } catch { return fail(); }
  if (!object(data) || Object.keys(data).length !== 3 || data.version !== 1 || data.authority !== authority || !Array.isArray(data.entries) || data.entries.length > 20) fail();
  const entries: PendingAttempt[] = [];
  const seen = new Set<string>();
  for (const rawEntry of data.entries) {
    if (!object(rawEntry) || Object.keys(rawEntry).length !== 7 ||
        typeof rawEntry.family !== 'string' || !/^[a-z][a-z0-9_.-]{1,63}$/.test(rawEntry.family) ||
        typeof rawEntry.resource_id !== 'string' || !/^[A-Za-z0-9._:-]{1,200}$/.test(rawEntry.resource_id) ||
        typeof rawEntry.request_key !== 'string' || !/^[A-Za-z0-9._:-]{8,200}$/.test(rawEntry.request_key) ||
        typeof rawEntry.permission !== 'string' || !/^[a-z][a-z0-9_.]{2,80}$/.test(rawEntry.permission) ||
        !object(rawEntry.intent) || !Number.isSafeInteger(rawEntry.created_at) || !Number.isSafeInteger(rawEntry.expires_at)) fail();
    const created = rawEntry.created_at as number, expires = rawEntry.expires_at as number;
    if (created < 1 || created > now || expires <= created || expires - created > MAX_AGE || expires > 8640000000000000) fail();
    const intent = canonical(rawEntry.intent);
    if (!object(intent) || bytes(JSON.stringify(intent)) > MAX_INTENT_BYTES) fail();
    const pair = JSON.stringify([rawEntry.family, rawEntry.resource_id]);
    if (seen.has(pair)) fail();
    seen.add(pair);
    if (created + MAX_AGE <= now || Date.parse(identity.expiresAt) <= now || !identity.permissions.includes(rawEntry.permission)) continue;
    entries.push({ family: rawEntry.family, resource_id: rawEntry.resource_id, request_key: rawEntry.request_key,
      permission: rawEntry.permission, intent, created_at: created, expires_at: Math.min(Date.parse(identity.expiresAt), created + MAX_AGE) });
  }
  return { version: 1, authority, entries };
}

function persist(storage: Storage, envelope: Envelope): void {
  const raw = JSON.stringify(envelope);
  if (bytes(raw) > MAX_BYTES) fail();
  try {
    if (!envelope.entries.length) {
      storage.removeItem(PENDING_KEY);
      if (storage.getItem(PENDING_KEY) !== null) fail();
    } else {
      storage.setItem(PENDING_KEY, raw);
      if (storage.getItem(PENDING_KEY) !== raw) fail();
    }
  } catch { fail(); }
}

function parseEvidenceContext(raw: string): EvidenceContext {
  if (bytes(raw) > 2048) fail();
  let value: unknown;
  try { value = JSON.parse(raw); } catch { return fail(); }
  if (!object(value) || Object.keys(value).length !== 7 || value.version !== 1 || typeof value.authority !== 'string' || !/^[a-f0-9]{64}$/.test(value.authority) ||
      typeof value.request_key !== 'string' || !/^[A-Za-z0-9_.-]{8,200}$/.test(value.request_key) ||
      typeof value.group_id !== 'string' || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value.group_id) || value.payee_id !== value.group_id ||
      typeof value.group_version !== 'number' || !Number.isSafeInteger(value.group_version) || value.group_version < 1 ||
      typeof value.receiver_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(value.receiver_sha256)) fail();
  return value as unknown as EvidenceContext;
}

export async function readEvidenceContext(identity: PendingIdentity, storage: Storage = sessionStorage): Promise<EvidenceContext | null> {
  const authority = await pendingAuthority(identity);
  let raw: string | null;
  try { raw = storage.getItem(EVIDENCE_CONTEXT_KEY); } catch { return fail(); }
  if (raw === null) return null;
  const context = parseEvidenceContext(raw);
  if (context.authority !== authority) fail();
  return context;
}

export async function retainEvidenceContext(identity: PendingIdentity, value: Omit<EvidenceContext, 'version' | 'authority'>, storage: Storage = sessionStorage): Promise<EvidenceContext> {
  if (!identity.permissions.includes('payments.manage') || !identity.permissions.includes('payments.write') || !Number.isFinite(Date.parse(identity.expiresAt)) || Date.parse(identity.expiresAt) <= Date.now()) fail();
  const authority = await pendingAuthority(identity), raw = JSON.stringify({ version: 1, authority, ...value });
  const context = parseEvidenceContext(raw);
  try {
    const prior = storage.getItem(EVIDENCE_CONTEXT_KEY);
    if (prior !== null && JSON.stringify(parseEvidenceContext(prior)) !== JSON.stringify(context)) fail();
    storage.setItem(EVIDENCE_CONTEXT_KEY, raw);
    if (storage.getItem(EVIDENCE_CONTEXT_KEY) !== raw) fail();
  } catch { fail(); }
  return context;
}

export async function clearEvidenceContext(identity: PendingIdentity, key: string, storage: Storage = sessionStorage): Promise<void> {
  const context = await readEvidenceContext(identity, storage);
  if (!context) return;
  if (context.request_key !== key) fail();
  try { storage.removeItem(EVIDENCE_CONTEXT_KEY); if (storage.getItem(EVIDENCE_CONTEXT_KEY) !== null) fail(); } catch { fail(); }
}

/** Bind only a definitive, generation-fenced session state; do not call while auth is loading or uncertain. */
export async function bindPendingIdentity(identity: PendingIdentity | null, storage: Storage = sessionStorage, now = Date.now(), isCurrent: () => boolean = () => true): Promise<'preserved' | 'cleared' | 'stale'> {
  const authority = identity ? await pendingAuthority(identity) : null;
  if (!isCurrent()) return 'stale';
  let raw: string | null, contextRaw: string | null;
  try { raw = storage.getItem(PENDING_KEY); contextRaw = storage.getItem(EVIDENCE_CONTEXT_KEY); } catch { return fail(); }
  if (raw === null && contextRaw === null) return 'preserved';
  if (identity === null) {
    if (!isCurrent()) return 'stale';
    try { storage.removeItem(PENDING_KEY); storage.removeItem(EVIDENCE_CONTEXT_KEY); if (storage.getItem(PENDING_KEY) !== null || storage.getItem(EVIDENCE_CONTEXT_KEY) !== null) fail(); } catch { fail(); }
    return 'cleared';
  }
  let envelopeAuthority: string | null = null;
  if (raw !== null) {
    if (bytes(raw) > MAX_BYTES) fail();
    let envelope: unknown;
    try { envelope = JSON.parse(raw); } catch { return fail(); }
    if (!object(envelope) || Object.keys(envelope).length !== 3 || envelope.version !== 1 ||
        typeof envelope.authority !== 'string' || !/^[a-f0-9]{64}$/.test(envelope.authority) || !Array.isArray(envelope.entries)) fail();
    decode(storage, envelope.authority, now, identity);
    envelopeAuthority = envelope.authority;
  }
  const context = contextRaw === null ? null : parseEvidenceContext(contextRaw);
  if (!isCurrent()) return 'stale';
  const clearPending = envelopeAuthority !== null && envelopeAuthority !== authority, clearContext = context !== null && context.authority !== authority;
  try {
    if (clearPending) { storage.removeItem(PENDING_KEY); if (storage.getItem(PENDING_KEY) !== null) fail(); }
    if (clearContext) { storage.removeItem(EVIDENCE_CONTEXT_KEY); if (storage.getItem(EVIDENCE_CONTEXT_KEY) !== null) fail(); }
  } catch { fail(); }
  return clearPending || clearContext ? 'cleared' : 'preserved';
}

export async function readPending(identity: PendingIdentity, family: string, resourceId: string, storage: Storage = sessionStorage, now = Date.now()): Promise<PendingAttempt | null> {
  const authority = await pendingAuthority(identity);
  const envelope = decode(storage, authority, now, identity);
  return envelope.entries.find(entry => entry.family === family && entry.resource_id === resourceId) ?? null;
}

export async function listPending(identity: PendingIdentity, family: string, permission: string, storage: Storage = sessionStorage, now = Date.now()): Promise<PendingAttempt[]> {
  if (!/^[a-z][a-z0-9_.-]{1,63}$/.test(family) || !/^[a-z][a-z0-9_.]{2,80}$/.test(permission) || !identity.permissions.includes(permission) ||
      !Number.isFinite(Date.parse(identity.expiresAt)) || Date.parse(identity.expiresAt) <= now) fail();
  const authority = await pendingAuthority(identity);
  return decode(storage, authority, now, identity).entries.filter(entry => entry.family === family && entry.permission === permission);
}

export async function retainPending(identity: PendingIdentity, family: string, resourceId: string, requestKey: string, permission: string, intent: Record<string, unknown>, storage: Storage = sessionStorage, now = Date.now()): Promise<PendingAttempt> {
  if (!/^[a-z][a-z0-9_.-]{1,63}$/.test(family) || !/^[A-Za-z0-9._:-]{1,200}$/.test(resourceId) ||
      !/^[A-Za-z0-9_.-]{8,200}$/.test(requestKey) || !identity.permissions.includes(permission) || !Number.isFinite(Date.parse(identity.expiresAt)) || Date.parse(identity.expiresAt) <= now) fail();
  const authority = await pendingAuthority(identity), envelope = decode(storage, authority, now, identity);
  const normalized = canonical(intent);
  if (!object(normalized) || bytes(JSON.stringify(normalized)) > MAX_INTENT_BYTES) fail();
  const previous = envelope.entries.find(entry => entry.family === family && entry.resource_id === resourceId);
  if (previous && (previous.request_key !== requestKey || previous.permission !== permission || JSON.stringify(previous.intent) !== JSON.stringify(normalized))) fail();
  const created = previous?.created_at ?? now;
  const attempt: PendingAttempt = { family, resource_id: resourceId, request_key: requestKey, permission,
    intent: normalized, created_at: created, expires_at: Math.min(Date.parse(identity.expiresAt), created + MAX_AGE) };
  envelope.entries = [...envelope.entries.filter(entry => entry !== previous), attempt];
  if (envelope.entries.length > 20) fail();
  persist(storage, envelope);
  return attempt;
}

export async function clearPending(identity: PendingIdentity, family: string, resourceId: string, requestKey: string, storage: Storage = sessionStorage, now = Date.now(), matches?: (current: PendingAttempt) => boolean): Promise<void> {
  const authority = await pendingAuthority(identity), envelope = decode(storage, authority, now, identity);
  const current = envelope.entries.find(entry => entry.family === family && entry.resource_id === resourceId);
  if (!current || current.request_key !== requestKey || (matches && !matches(current))) fail();
  envelope.entries = envelope.entries.filter(entry => entry !== current);
  persist(storage, envelope);
}
