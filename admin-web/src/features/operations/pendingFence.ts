import { pendingAuthority, type PendingIdentity } from '../core/pendingAttempt';

const STORAGE_KEY = 'collect.admin.pending-fence.v2';
const LEGACY_PREFIX = 'collect.admin.pending-fence.v1:';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const DIGEST = /^[a-f0-9]{64}$/;
export type FenceLock = <T>(name: string, work: () => Promise<T>) => Promise<T>;
export interface FenceContext {
  identity: PendingIdentity;
  family: string;
  resourceId: string;
  isCurrent: () => boolean;
  storage?: Storage;
  lock?: FenceLock;
}
export type FenceState = {kind: 'empty'; revision: string} | {kind: 'owned'; requestKey: string; revision: string} | {kind: 'foreign'; revision: string};
export interface FenceAccess {
  read: () => FenceState;
  reserve: (requestKey: string, observedRevision: string) => void;
  clear: (requestKey: string) => void;
}
interface FenceEntry {scope: string; authority: string; request_key: string; created_at: number;}
interface FenceEnvelope {version: 2; revision: string; entries: FenceEntry[];}

function fail(): never { throw new Error('Shared request recovery is unavailable. Check the original request before continuing.'); }
function object(value: unknown): value is Record<string, unknown> {return value !== null && typeof value === 'object' && !Array.isArray(value);}
function revision(previous?: string): string {
  const value = globalThis.crypto?.randomUUID?.();
  if (!value || !UUID.test(value) || value === previous) return fail();
  return value;
}
async function sha256(value: string): Promise<string> {
  if (!globalThis.crypto?.subtle) return fail();
  const digest = await globalThis.crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
async function browserLock<T>(name: string, work: () => Promise<T>): Promise<T> {
  if (!navigator.locks) return fail();
  return navigator.locks.request(name, {mode: 'exclusive', ifAvailable: true}, async (lock) => lock ? work() : fail());
}

/**
 * A same-origin cross-tab fence. It stores no review reason, raw SMS or account
 * identifiers. It never expires or clears an unresolved request automatically.
 * Terminal cleanup removes request data but keeps a random revision so stale
 * confirmations cannot submit after another tab has completed an action.
 */
export async function withPendingFence<T>(context: FenceContext, work: (access: FenceAccess) => Promise<T>): Promise<T> {
  if (!/^[a-z][a-z0-9_.-]{1,63}$/.test(context.family) || !/^[A-Za-z0-9._:-]{1,200}$/.test(context.resourceId) || !context.isCurrent()) return fail();
  const scope = await sha256(`collect-admin-pending-fence-v1\u0000${context.family}\u0000${context.resourceId}`);
  const authority = await pendingAuthority(context.identity);
  if (!context.isCurrent()) return fail();
  const lock = context.lock ?? browserLock;
  return lock(STORAGE_KEY, async () => {
    if (!context.isCurrent()) return fail();
    let storage: Storage;
    try {storage = context.storage ?? localStorage;} catch {return fail();}
    const save = (envelope: FenceEnvelope) => {
      if (!context.isCurrent()) return fail();
      const raw = JSON.stringify(envelope);
      if (new TextEncoder().encode(raw).length > 32768) return fail();
      try {storage.setItem(STORAGE_KEY, raw); if (storage.getItem(STORAGE_KEY) !== raw) return fail();} catch {return fail();}
      if (!context.isCurrent()) return fail();
    };
    const envelope = (): FenceEnvelope => {
      if (!context.isCurrent()) return fail();
      let raw: string | null;
      try {if (storage.getItem(LEGACY_PREFIX + scope) !== null) return fail(); raw = storage.getItem(STORAGE_KEY);} catch {return fail();}
      if (raw === null) {const fresh: FenceEnvelope = {version: 2, revision: revision(), entries: []}; save(fresh); return fresh;}
      if (new TextEncoder().encode(raw).length > 32768) return fail();
      let value: unknown;
      try {value = JSON.parse(raw);} catch {return fail();}
      if (!object(value) || Object.keys(value).length !== 3 || value.version !== 2 || typeof value.revision !== 'string' || !UUID.test(value.revision) || !Array.isArray(value.entries) || value.entries.length > 128) return fail();
      const entries: FenceEntry[] = [];
      const seen = new Set<string>();
      for (const item of value.entries) {
        if (!object(item) || Object.keys(item).length !== 4 || typeof item.scope !== 'string' || !DIGEST.test(item.scope) ||
            typeof item.authority !== 'string' || !DIGEST.test(item.authority) || typeof item.request_key !== 'string' || !UUID.test(item.request_key) ||
            !Number.isSafeInteger(item.created_at) || (item.created_at as number) < 1 || seen.has(item.scope)) return fail();
        seen.add(item.scope);
        entries.push({scope: item.scope, authority: item.authority, request_key: item.request_key, created_at: item.created_at as number});
      }
      return {version: 2, revision: value.revision, entries};
    };
    const read = (): FenceState => {
      const value = envelope(), entry = value.entries.find((item) => item.scope === scope);
      if (!entry) return {kind: 'empty', revision: value.revision};
      return entry.authority === authority ? {kind: 'owned', requestKey: entry.request_key, revision: value.revision} : {kind: 'foreign', revision: value.revision};
    };
    const reserve = (requestKey: string, observedRevision: string) => {
      const value = envelope();
      if (!UUID.test(requestKey) || value.revision !== observedRevision || value.entries.length >= 128 || value.entries.some((item) => item.scope === scope)) return fail();
      save({version: 2, revision: revision(value.revision), entries: [...value.entries, {scope, authority, request_key: requestKey, created_at: Date.now()}]});
    };
    const clear = (requestKey: string) => {
      const value = envelope(), entry = value.entries.find((item) => item.scope === scope);
      if (!entry || entry.authority !== authority || entry.request_key !== requestKey) return fail();
      save({version: 2, revision: revision(value.revision), entries: value.entries.filter((item) => item.scope !== scope)});
    };
    return work({read, reserve, clear});
  });
}
