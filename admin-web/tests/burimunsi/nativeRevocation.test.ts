import {webcrypto} from 'node:crypto';
import {beforeEach, describe, expect, it, vi} from 'vitest';
import type {AdminRequest} from '../../src/api/client';
import {readPending, retainPending} from '../../src/features/core/pendingAttempt';
import {cancelNativeRevocation, checkNativeRevocation, reviewNativeRevocation, submitNativeRevocation, type NativeRevokeContext} from '../../src/features/burimunsi/nativeRevocation';
import {accountId, collectionId, grantId, installationId, operatorIntent, owner, provisioning, requestId, sessionId, staffPrincipal} from './fixture';

function storage(): Storage {
  const values = new Map<string, string>();
  return {get length() {return values.size;}, clear() {values.clear();}, getItem(key) {return values.get(key) ?? null;}, key(index) {return [...values.keys()][index] ?? null;}, removeItem(key) {values.delete(key);}, setItem(key, value) {values.set(key, String(value));}};
}
function locks() {
  let prior = Promise.resolve();
  return async <T,>(_name: string, work: () => Promise<T>): Promise<T> => {
    let release!: () => void; const next = new Promise<void>(resolve => {release = resolve;}), before = prior; prior = next;
    await before; try {return await work();} finally {release();}
  };
}
function fixture() {
  const tab = storage(), shared = storage(), lock = locks(), receipts = new Map<string, Record<string, unknown>>();
  let current = true, fresh = true, allowed = true, loseApply = false, dropApply = false, loseCancel = false, corruptReceipt = false;
  let source: Record<string, unknown> = structuredClone(provisioning), captureSession = '', captureShared = '';
  const request = vi.fn<AdminRequest>(async (path, options = {}) => {
    if (path.startsWith('burimunsi/provisioning?') && options.method !== 'POST') {
      expect(new URLSearchParams(path.split('?')[1]).get('provisioningContract')).toBe('2');
      return {provisioningContract: 2, ...source};
    }
    if (path === 'burimunsi/provisioning?provisioningContract=2' && options.method === 'POST') {
      const b = options.body!;
      captureSession = JSON.stringify([...Array(tab.length)].map((_, index) => tab.getItem(tab.key(index)!)));
      captureShared = JSON.stringify([...Array(shared.length)].map((_, index) => [shared.key(index), shared.getItem(shared.key(index)!)]));
      expect(options.idempotencyKey).toBe(requestId); expect(b.requestId).toBe(requestId);
      expect(Object.keys(b).sort()).toEqual(['accountId', 'approvalVersion', 'collectionId', 'expectedAccountVersion', 'expectedGrantVersion', 'grantId', 'installationId', 'operation', 'principalId', 'profile', 'reason', 'requestId', 'scopeVersion'].sort());
      if (!dropApply) receipts.set(requestId, {contractVersion: 1, collectionId, requestId, operation: 'revoke_installation', principalId: b.principalId,
        accountId: b.accountId, accountVersion: b.expectedAccountVersion, credentialVersion: 1, approvalVersion: b.approvalVersion, scopeVersion: b.scopeVersion,
        applied: true, grantId: b.grantId, installationId: b.installationId, profile: b.profile, grantVersion: Number(b.expectedGrantVersion) + 1, active: false, deliveryExpiresAt: null});
      if (loseApply || dropApply) throw new Error('synthetic response lost');
      return receipts.get(requestId)!;
    }
    if (path.endsWith(`/requests/${requestId}/cancel?provisioningContract=2`) && options.method === 'POST') {
      expect(options.body).toEqual({collectionId}); expect(options.idempotencyKey).toBe(requestId);
      if (!receipts.has(requestId)) receipts.set(requestId, {contractVersion: 1, collectionId, requestId, operation: 'cancelled', applied: false});
      if (loseCancel) throw new Error('synthetic cancellation response lost');
      return receipts.get(requestId)!;
    }
    if (path.startsWith(`burimunsi/provisioning/requests/${requestId}?`)) {
      const receipt = receipts.get(requestId);
      return receipt ? {contractVersion: 1, collectionId, requestId, found: true, receipt: corruptReceipt ? {...receipt, grantId: accountId} : receipt} : {contractVersion: 1, collectionId, requestId, found: false};
    }
    throw new Error(`Unexpected synthetic request: ${path}`);
  });
  const identity = {id: owner.id, sessionId, email: owner.email, role: owner.role, permissions: owner.permissions, expiresAt: owner.expiresAt};
  const context: NativeRevokeContext = {request, user: {...owner}, identity, collectionId, enabled: true, isEnabled: () => allowed, isCurrent: () => current, verifyFresh: async () => fresh,
    storage: tab, sharedStorage: shared, lock, createKey: () => requestId};
  return {context, request, tab, shared, receipts, identity,
    setCurrent(value: boolean) {current = value;}, setFresh(value: boolean) {fresh = value;}, setAllowed(value: boolean) {allowed = value;},
    setLoseApply(value: boolean) {loseApply = value;}, setDropApply(value: boolean) {dropApply = value;}, setLoseCancel(value: boolean) {loseCancel = value;},
    setCorruptReceipt(value: boolean) {corruptReceipt = value;}, setSource(value: Record<string, unknown>) {source = value;}, captures: () => ({captureSession, captureShared})};
}
beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true});});

describe('BuriMunsi native installation revocation', () => {
  it('fails closed when the independent gate, owner proof, or fresh verification is absent', async () => {
    const f = fixture(); await expect(reviewNativeRevocation({...f.context, enabled: false}, grantId)).rejects.toThrow(/not enabled/);
    await expect(reviewNativeRevocation({...f.context, user: {...owner, ownerIdentity: null}}, grantId)).rejects.toThrow(/owner session/);
    f.setFresh(false); await expect(reviewNativeRevocation(f.context, grantId)).rejects.toThrow(/Verify your current owner email/);
    expect(f.request).not.toHaveBeenCalled();
  });
  it('submits only the verified versioned revocation and validates the original server receipt', async () => {
    const f = fixture(), review = await reviewNativeRevocation(f.context, grantId); if (review.status !== 'ready') throw new Error('expected review');
    expect(review.snapshot).toMatchObject({principalId: staffPrincipal, accountId, grantId, installationId, expectedAccountVersion: 1, expectedGrantVersion: 1, scopeVersion: 2, approvalVersion: 1});
    expect(await submitNativeRevocation(f.context, review)).toEqual({status: 'recorded'});
    expect(await readPending(f.identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, f.tab)).toBeNull();
    const calls = f.request.mock.calls; expect(calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
    expect(calls.some(([path]) => path.startsWith(`burimunsi/provisioning/requests/${requestId}?`))).toBe(true);
    const {captureSession, captureShared} = f.captures();
    expect(captureSession).not.toMatch(/"pin"|"token"|"credential"/i); expect(captureShared).not.toContain(staffPrincipal); expect(captureShared).not.toContain(accountId);
  });
  it('retains the exact original key after a lost response and only looks it up', async () => {
    const f = fixture(); f.setLoseApply(true); const review = await reviewNativeRevocation(f.context, grantId); if (review.status !== 'ready') throw new Error('expected review');
    expect(await submitNativeRevocation(f.context, review)).toEqual({status: 'unknown', requestKey: requestId});
    expect((await readPending(f.identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, f.tab))?.request_key).toBe(requestId);
    expect(await checkNativeRevocation(f.context)).toEqual({status: 'recorded'});
    expect(f.request.mock.calls.filter(([path, options]) => path === 'burimunsi/provisioning?provisioningContract=2' && options?.method === 'POST')).toHaveLength(1);
    expect(await readPending(f.identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, f.tab)).toBeNull();
  });
  it('holds a missing receipt and uses only the original cancellation tombstone', async () => {
    const f = fixture(); f.setDropApply(true); const review = await reviewNativeRevocation(f.context, grantId); if (review.status !== 'ready') throw new Error('expected review');
    expect(await submitNativeRevocation(f.context, review)).toEqual({status: 'unknown', requestKey: requestId});
    expect(await checkNativeRevocation(f.context)).toEqual({status: 'not_found', requestKey: requestId});
    expect((await readPending(f.identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, f.tab))?.request_key).toBe(requestId);
    await expect(cancelNativeRevocation(f.context, grantId)).rejects.toThrow(/original request changed/i);
    expect(f.request.mock.calls.filter(([path]) => path.includes('/cancel'))).toHaveLength(0);
    f.setLoseCancel(true); expect(await cancelNativeRevocation(f.context, requestId)).toEqual({status: 'unknown', requestKey: requestId});
    expect(await checkNativeRevocation(f.context)).toEqual({status: 'cancelled'});
    expect(f.request.mock.calls.filter(([path, options]) => path === 'burimunsi/provisioning?provisioningContract=2' && options?.method === 'POST')).toHaveLength(1);
  });
  it('recovers across tabs after the original per-tab intent is lost without storing account data in shared storage', async () => {
    const f = fixture(); f.setLoseApply(true); const review = await reviewNativeRevocation(f.context, grantId); if (review.status !== 'ready') throw new Error('expected review');
    expect(await submitNativeRevocation(f.context, review)).toEqual({status: 'unknown', requestKey: requestId});
    const other = {...f.context, storage: storage()};
    expect(await reviewNativeRevocation(other, grantId)).toEqual({status: 'pending', pending: {kind: 'owned', requestKey: requestId}});
    expect(await checkNativeRevocation(other)).toEqual({status: 'recorded'});
    expect(f.request.mock.calls.filter(([path, options]) => path === 'burimunsi/provisioning?provisioningContract=2' && options?.method === 'POST')).toHaveLength(1);
  });
  it('retains a mismatching outcome and refuses a different owner session', async () => {
    const f = fixture(); f.setLoseApply(true); const review = await reviewNativeRevocation(f.context, grantId); if (review.status !== 'ready') throw new Error('expected review');
    await submitNativeRevocation(f.context, review); f.setCorruptReceipt(true);
    await expect(checkNativeRevocation(f.context)).rejects.toThrow(/could not be verified/);
    expect((await readPending(f.identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, f.tab))?.request_key).toBe(requestId);
    const changed = {...owner, sessionId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}, foreign = {...f.context, user: changed, identity: {...f.identity, sessionId: changed.sessionId}, storage: storage()};
    expect(await checkNativeRevocation(foreign)).toEqual({status: 'pending', pending: {kind: 'foreign'}});
  });
  it('blocks a retained Flutter request, a changed reviewed grant, or a stale tab revision', async () => {
    const f = fixture(); await retainPending(f.identity, 'burimunsi.operator', `${collectionId}:${staffPrincipal}`, requestId, 'admin_users.manage', operatorIntent, f.tab);
    expect(await reviewNativeRevocation(f.context, grantId)).toEqual({status: 'pending', pending: {kind: 'external'}});
    f.tab.clear(); const review = await reviewNativeRevocation(f.context, grantId); if (review.status !== 'ready') throw new Error('expected review');
    f.setSource({...provisioning, grants: [{...provisioning.grants[0], version: 2}]});
    await expect(submitNativeRevocation(f.context, review)).rejects.toThrow(/changed/); expect(f.request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
    f.setSource(provisioning); const stale = await reviewNativeRevocation(f.context, grantId); if (stale.status !== 'ready') throw new Error('expected review');
    const otherReview = await reviewNativeRevocation({...f.context, storage: storage()}, grantId); if (otherReview.status !== 'ready') throw new Error('expected review');
    expect(await submitNativeRevocation(f.context, review)).toEqual({status: 'recorded'});
    await expect(submitNativeRevocation({...f.context, storage: storage()}, stale)).rejects.toThrow(/Shared request recovery/);
    await expect(submitNativeRevocation({...f.context, storage: storage()}, otherReview)).rejects.toThrow(/Shared request recovery/);
    expect(f.request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
  });
  it('does not dispatch when current authority or the live gate is lost before sending', async () => {
    const f = fixture(), review = await reviewNativeRevocation(f.context, grantId); if (review.status !== 'ready') throw new Error('expected review');
    f.setAllowed(false); await expect(submitNativeRevocation(f.context, review)).rejects.toThrow(/not enabled/);
    f.setAllowed(true); f.setCurrent(false); await expect(submitNativeRevocation(f.context, review)).rejects.toThrow(/owner session/);
    expect(f.request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
  });
});
