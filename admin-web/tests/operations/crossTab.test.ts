import { describe, expect, it, vi } from 'vitest';
import type { PendingIdentity } from '../../src/features/core';
import type { SmsReceipt } from '../../src/features/operations/contracts';
import { lookupEmailDispatch, restoreEmailDispatch, submitEmailDispatch, type EmailDispatchContext } from '../../src/features/operations/emailActions';
import { withPendingFence, type FenceLock } from '../../src/features/operations/pendingFence';
import { lookupSmsExtraction, restoreSmsExtraction, submitSmsExtraction, type SmsActionContext } from '../../src/features/operations/smsActions';

class MemoryStorage implements Storage {
  private values = new Map<string, string>();
  get length() {return this.values.size;}
  clear() {this.values.clear();}
  getItem(key: string) {return this.values.get(key) ?? null;}
  key(index: number) {return [...this.values.keys()][index] ?? null;}
  removeItem(key: string) {this.values.delete(key);}
  setItem(key: string, value: string) {this.values.set(key, value);}
}
function lockManager(): FenceLock {
  const active = new Set<string>();
  return async (name, work) => {
    if (active.has(name)) throw new Error('locked');
    active.add(name);
    try {return await work();} finally {active.delete(name);}
  };
}
const actorId = '22222222-2222-2222-2222-222222222222';
const id = '11111111-1111-1111-1111-111111111111';
const key = '33333333-3333-4333-8333-333333333333';
const requestId = '44444444-4444-4444-8444-444444444444';
const factId = '55555555-5555-4555-8555-555555555555';
const hash = 'a'.repeat(64);
const source = {source_kind: 'capture', id, source_sha256: hash, evidence_level: 'client_received'} as SmsReceipt;
const smsReceipt = {request_id: requestId, status: 'succeeded', resource_type: 'sms_facts', resource_id: factId, source_kind: 'capture', source_id: id, parser_version: 'collect-admin-source-facts-v1'};
const emailReceipt = {request_id: requestId, status: 'succeeded', resource_type: 'email_dispatch', resource_id: requestId, version: 1, accepted: 2, uncertain: 1, suppressed: 0};
function identity(): PendingIdentity {return {id: actorId, sessionId: 'session-1', email: 'operator@example.com', role: 'admin', permissions: ['sms.read', 'sms.extract', 'email.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function sms(request: SmsActionContext['request'], storage: Storage, sharedStorage: Storage, lock: FenceLock): SmsActionContext {
  return {request, identity: identity(), source, enabled: true, isCurrent: () => true, storage, sharedStorage, lock, createKey: () => key};
}
function email(request: EmailDispatchContext['request'], storage: Storage, sharedStorage: Storage, lock: FenceLock): EmailDispatchContext {
  return {request, identity: identity(), financialModel: 'transaction_journals', principalId: null, enabled: true, isCurrent: () => true, storage, sharedStorage, lock, createKey: () => key};
}

const fenceKey = 'collect.admin.pending-fence.v2';
function expectEmpty(shared: Storage) {
  const raw = shared.getItem(fenceKey);
  expect(raw).not.toBeNull();
  expect(JSON.parse(raw!).entries).toEqual([]);
  expect(raw).not.toContain(key);
  expect(raw).not.toContain('operator@example.com');
  expect(raw).not.toContain(id);
}
async function smsRevision(ctx: SmsActionContext): Promise<string> {const state = await restoreSmsExtraction(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
async function emailRevision(ctx: EmailDispatchContext): Promise<string> {const state = await restoreEmailDispatch(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}

describe('Durable cross-tab request fences', () => {
  it('blocks concurrent SMS sends, recovers an unknown original key in another tab, and reconciles a stale tab', async () => {
    const shared = new MemoryStorage(), tabA = new MemoryStorage(), tabB = new MemoryStorage(), lock = lockManager();
    let release!: () => void, started!: () => void;
    const entered = new Promise<void>((resolve) => {started = resolve;});
    const wait = new Promise<never>((_resolve, reject) => {release = () => reject(new Error('response lost'));});
    const requestA = vi.fn<SmsActionContext['request']>(async () => {started(); return wait;});
    const requestB = vi.fn();
    const a = sms(requestA, tabA, shared, lock), b = sms(requestB, tabB, shared, lock);
    const observedA = await smsRevision(a), observedB = await smsRevision(b);
    const sending = submitSmsExtraction(a, 'Review source evidence', observedA);
    await entered;
    await expect(submitSmsExtraction(b, 'Another review reason', observedB)).rejects.toThrow('locked');
    expect(requestB).not.toHaveBeenCalled();
    release();
    expect((await sending).status).toBe('unknown');
    const record = shared.getItem(shared.key(0)!)!;
    expect(record).not.toContain('Review source evidence');
    expect(record).not.toContain('operator@example.com');
    expect(record).not.toContain(id);
    const pendingB = await restoreSmsExtraction(b);
    expect(pendingB).toEqual({kind: 'owned', requestKey: key, attempt: null});
    expect(await submitSmsExtraction(b, 'Another review reason', observedB)).toEqual({status: 'existing', pending: pendingB});
    expect(requestB).not.toHaveBeenCalled();
    requestB.mockResolvedValueOnce({status: 'not_found'});
    expect(await lookupSmsExtraction(b, pendingB!)).toEqual({status: 'not_found'});
    expect(shared.length).toBe(1);
    requestB.mockResolvedValueOnce({status: 'succeeded', request_id: requestId, receipt: smsReceipt});
    expect((await lookupSmsExtraction(b, pendingB!)).status).toBe('succeeded');
    expectEmpty(shared);
    const staleA = await restoreSmsExtraction(a);
    expect(staleA).toMatchObject({kind: 'owned', requestKey: key});
    requestA.mockResolvedValueOnce({status: 'succeeded', request_id: requestId, receipt: smsReceipt});
    expect((await lookupSmsExtraction(a, staleA!)).status).toBe('succeeded');
    expectEmpty(shared);
  });

  it('keeps an unknown SMS request blocked across an actor or session change without revealing the key', async () => {
    const shared = new MemoryStorage(), lock = lockManager(), request = vi.fn().mockRejectedValue(new Error('lost'));
    const a = sms(request, new MemoryStorage(), shared, lock);
    const observed = await smsRevision(a);
    await submitSmsExtraction(a, 'Review source evidence', observed);
    const other = {...sms(vi.fn(), new MemoryStorage(), shared, lock), identity: {...identity(), id: '66666666-6666-4666-8666-666666666666', sessionId: 'different'}};
    const blocked = await restoreSmsExtraction(other);
    expect(blocked).toEqual({kind: 'foreign'});
    expect(await submitSmsExtraction(other, 'Review source evidence', observed)).toEqual({status: 'existing', pending: {kind: 'foreign'}});
    expect(other.request).not.toHaveBeenCalled();
    await expect(lookupSmsExtraction(other, blocked!)).rejects.toThrow('original account');
  });

  it('recovers a crash after the shared fence was reserved but before a tab checkpoint existed', async () => {
    const shared = new MemoryStorage(), lock = lockManager(), user = identity();
    await withPendingFence({identity: user, family: 'sms-extraction', resourceId: `capture:${id}`, isCurrent: () => true, storage: shared, lock}, async (access) => access.reserve(key, access.read().revision));
    const request = vi.fn().mockResolvedValue({status: 'not_found'});
    const next = sms(request, new MemoryStorage(), shared, lock);
    const pending = await restoreSmsExtraction(next);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    expect(await lookupSmsExtraction(next, pending!)).toEqual({status: 'not_found'});
    expect(shared.length).toBe(1);
    expect(request).toHaveBeenCalledTimes(1);
  });

  it('fails closed when shared recovery storage is corrupt or unavailable', async () => {
    const shared = new MemoryStorage(), lock = lockManager(), user = identity();
    await withPendingFence({identity: user, family: 'sms-extraction', resourceId: `capture:${id}`, isCurrent: () => true, storage: shared, lock}, async (access) => access.reserve(key, access.read().revision));
    shared.setItem(shared.key(0)!, '{broken');
    const request = vi.fn();
    await expect(submitSmsExtraction(sms(request, new MemoryStorage(), shared, lock), 'Review source evidence', '')).rejects.toThrow('Shared request recovery');
    expect(request).not.toHaveBeenCalled();
    const unavailable = {getItem: () => {throw new Error('blocked');}, setItem: () => {}, removeItem: () => {}, clear: () => {}, key: () => null, length: 0} satisfies Storage;
    await expect(submitSmsExtraction(sms(request, new MemoryStorage(), unavailable, lock), 'Review source evidence', '')).rejects.toThrow('Shared request recovery');
    expect(request).not.toHaveBeenCalled();
  });

  it('retains an email fence after an unknown outcome and another tab checks the same key', async () => {
    const shared = new MemoryStorage(), lock = lockManager();
    const requestA = vi.fn().mockRejectedValueOnce(new Error('response lost'));
    const a = email(requestA, new MemoryStorage(), shared, lock);
    const observed = await emailRevision(a);
    expect((await submitEmailDispatch(a, 'Review queued notifications', observed)).status).toBe('unknown');
    const requestB = vi.fn().mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'succeeded', request_id: requestId, receipt: emailReceipt});
    const b = email(requestB, new MemoryStorage(), shared, lock);
    const pending = await restoreEmailDispatch(b);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    expect(await submitEmailDispatch(b, 'Review queued notifications', observed)).toEqual({status: 'existing', pending});
    expect(await lookupEmailDispatch(b, pending!)).toEqual({status: 'not_found'});
    expect((await lookupEmailDispatch(b, pending!)).status).toBe('succeeded');
    expectEmpty(shared);
    const stale = await restoreEmailDispatch(a);
    expect(stale).toMatchObject({kind: 'owned', requestKey: key});
    requestA.mockResolvedValueOnce({status: 'succeeded', request_id: requestId, receipt: emailReceipt});
    expect((await lookupEmailDispatch(a, stale!)).status).toBe('succeeded');
    expectEmpty(shared);
    expect(requestA).toHaveBeenCalledTimes(2);
    expect(requestB).toHaveBeenCalledTimes(2);
  });

  it('blocks concurrent email batches and prevents a different account from clearing an unknown result', async () => {
    const shared = new MemoryStorage(), lock = lockManager();
    let release!: () => void, started!: () => void;
    const entered = new Promise<void>((resolve) => {started = resolve;});
    const wait = new Promise<never>((_resolve, reject) => {release = () => reject(new Error('response lost'));});
    const requestA = vi.fn<EmailDispatchContext['request']>(async () => {started(); return wait;});
    const a = email(requestA, new MemoryStorage(), shared, lock);
    const requestB = vi.fn(), b = email(requestB, new MemoryStorage(), shared, lock);
    const observed = await emailRevision(a);
    const sending = submitEmailDispatch(a, 'Review queued notifications', observed);
    await entered;
    await expect(submitEmailDispatch(b, 'Review queued notifications', observed)).rejects.toThrow('locked');
    release();
    expect((await sending).status).toBe('unknown');
    const other = {...b, identity: {...identity(), id: '66666666-6666-4666-8666-666666666666', sessionId: 'different'}};
    const blocked = await restoreEmailDispatch(other);
    expect(blocked).toEqual({kind: 'foreign'});
    expect(await submitEmailDispatch(other, 'Review queued notifications', observed)).toEqual({status: 'existing', pending: {kind: 'foreign'}});
    await expect(lookupEmailDispatch(other, blocked!)).rejects.toThrow('original account');
    expect(requestB).not.toHaveBeenCalled();
    expect(shared.length).toBe(1);
  });

  it('restores an email fence left by a crash before the per-tab checkpoint', async () => {
    const shared = new MemoryStorage(), lock = lockManager();
    await withPendingFence({identity: identity(), family: 'email-dispatch', resourceId: 'queue', isCurrent: () => true, storage: shared, lock}, async (access) => access.reserve(key, access.read().revision));
    const request = vi.fn().mockResolvedValue({status: 'not_found'});
    const next = email(request, new MemoryStorage(), shared, lock);
    const pending = await restoreEmailDispatch(next);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    expect(await lookupEmailDispatch(next, pending!)).toEqual({status: 'not_found'});
    expect(shared.length).toBe(1);
    expect(request).toHaveBeenCalledTimes(1);
  });

  it('preserves the fence if authority changes while a request is in flight', async () => {
    const shared = new MemoryStorage(), lock = lockManager(), storage = new MemoryStorage();
    let current = true;
    const request = vi.fn(async () => {current = false; return smsReceipt;});
    const original = {...sms(request, storage, shared, lock), isCurrent: () => current};
    const observed = await smsRevision(original);
    expect((await submitSmsExtraction(original, 'Review source evidence', observed)).status).toBe('unknown');
    const reconnected = {...original, isCurrent: () => true};
    expect(await restoreSmsExtraction(reconnected)).toMatchObject({kind: 'owned', requestKey: key});
    expect(shared.length).toBe(1);
  });
  it('rejects an SMS confirmation opened before another tab finished, without a second post', async () => {
    const shared = new MemoryStorage(), lock = lockManager();
    const requestA = vi.fn<SmsActionContext['request']>().mockResolvedValue(smsReceipt);
    const requestB = vi.fn<SmsActionContext['request']>();
    const a = sms(requestA, new MemoryStorage(), shared, lock), b = sms(requestB, new MemoryStorage(), shared, lock);
    const observedA = await smsRevision(a), observedB = await smsRevision(b);
    expect(observedA).toBe(observedB);
    expect((await submitSmsExtraction(a, 'Review source evidence', observedA)).status).toBe('succeeded');
    expectEmpty(shared);
    await expect(submitSmsExtraction(b, 'Review source evidence', observedB)).rejects.toThrow('Shared request recovery');
    expect(requestB).not.toHaveBeenCalled();
    expect(await smsRevision(b)).not.toBe(observedB);
  });

  it('rejects an email confirmation opened before another tab finished, without sending a second batch', async () => {
    const shared = new MemoryStorage(), lock = lockManager();
    const requestA = vi.fn<EmailDispatchContext['request']>().mockResolvedValue(emailReceipt);
    const requestB = vi.fn<EmailDispatchContext['request']>();
    const a = email(requestA, new MemoryStorage(), shared, lock), b = email(requestB, new MemoryStorage(), shared, lock);
    const observedA = await emailRevision(a), observedB = await emailRevision(b);
    expect(observedA).toBe(observedB);
    expect((await submitEmailDispatch(a, 'Review queued notifications', observedA)).status).toBe('succeeded');
    expectEmpty(shared);
    await expect(submitEmailDispatch(b, 'Review queued notifications', observedB)).rejects.toThrow('Shared request recovery');
    expect(requestB).not.toHaveBeenCalled();
    expect(await emailRevision(b)).not.toBe(observedB);
  });

});
