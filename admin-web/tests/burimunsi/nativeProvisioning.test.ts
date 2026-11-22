import {webcrypto} from 'node:crypto';
import {beforeEach, describe, expect, it} from 'vitest';
import type {AdminRequest} from '../../src/api/client';
import {readPending, retainPending} from '../../src/features/core/pendingAttempt';
import {cancelNativeProvisioning, checkNativeProvisioning, closeNativeDelivery, openNativeDelivery, reviewNativeProvisioning, submitNativeProvisioning, type NativeProvisionContext} from '../../src/features/burimunsi/nativeProvisioning';
import {reviewNativeRevocation} from '../../src/features/burimunsi/nativeRevocation';
import {account, accountId, collectionId, grantId, installationId, owner, provisioning, requestId, sessionId, staffPrincipal} from './fixture';

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
  const pin = String(1000 + webcrypto.getRandomValues(new Uint16Array(1))[0] % 9000), deviceSecret = Array.from(webcrypto.getRandomValues(new Uint8Array(32)), n => n.toString(16).padStart(2, '0')).join('');
  let current = true, fresh = true, visible = true, allowed = true, loseApply = false, dropApply = false, loseCancel = false, hideDuringDelivery = false, corruptDelivery = false;
  let source: Record<string, unknown> = structuredClone(provisioning), submitted = 0, cancellations = 0, lookups = 0, deliveries = 0;
  let capturedPinWasValid = false, durableHadSecret = false, lastDelivery: Record<string, unknown> | null = null;
  const request: AdminRequest = async (path, options = {}) => {
    if (path.startsWith('burimunsi/provisioning?') && options.method !== 'POST') {
      expect(new URLSearchParams(path.split('?')[1]).get('provisioningContract')).toBe('2');
      return {provisioningContract: 2, ...source};
    }
    if (path === 'burimunsi/provisioning?provisioningContract=2' && options.method === 'POST') {
      submitted++; const body = options.body!;
      if (options.idempotencyKey !== requestId || body.requestId !== requestId) throw new Error('Unexpected synthetic request identity.');
      if (body.operation === 'set_pin') {
        capturedPinWasValid = body.pin === pin;
        const values = [...Array(tab.length)].map((_, i) => JSON.parse(tab.getItem(tab.key(i)!)!)).concat([...Array(shared.length)].map((_, i) => JSON.parse(shared.getItem(shared.key(i)!)!)));
        const containsSecret = (value: unknown): boolean => value === pin || value === deviceSecret || !!value && typeof value === 'object' && Object.values(value).some(containsSecret);
        durableHadSecret = values.some(containsSecret);
      }
      if (!dropApply) {
        const pinSetup = body.operation === 'set_pin';
        receipts.set(requestId, {contractVersion: 1, collectionId, requestId, operation: body.operation, principalId: body.principalId,
          accountId: pinSetup ? accountId : body.accountId, accountVersion: Number(body.expectedAccountVersion) + (pinSetup ? 1 : 0), credentialVersion: 1,
          approvalVersion: body.approvalVersion, scopeVersion: body.scopeVersion, applied: true,
          ...(pinSetup ? {} : {grantId: body.grantId ?? grantId, installationId: body.installationId, profile: body.profile, grantVersion: Number(body.expectedGrantVersion) + 1, active: true, deliveryExpiresAt: Date.now() + 120_000})});
      }
      if (loseApply || dropApply) throw new Error('Synthetic lost response.');
      return {...receipts.get(requestId)!};
    }
    if (path.endsWith(`/requests/${requestId}/cancel?provisioningContract=2`) && options.method === 'POST') {
      cancellations++; if (!receipts.has(requestId)) receipts.set(requestId, {contractVersion: 1, collectionId, requestId, operation: 'cancelled', applied: false});
      if (loseCancel) throw new Error('Synthetic lost cancellation.'); return {...receipts.get(requestId)!};
    }
    if (path.includes(`/requests/${requestId}/delivery`) && options.method === 'POST') {
      deliveries++; const prior = receipts.get(requestId)!;
      if (hideDuringDelivery) visible = false;
      lastDelivery = {contractVersion: 1, collectionId, requestId, installationId: prior.installationId, profile: corruptDelivery ? 'internal_receiver' : prior.profile,
        grantVersion: prior.grantVersion, expiresAt: prior.deliveryExpiresAt, installationToken: deviceSecret};
      return lastDelivery;
    }
    if (path.startsWith(`burimunsi/provisioning/requests/${requestId}?`)) {
      lookups++; const receipt = receipts.get(requestId); return receipt ? {contractVersion: 1, collectionId, requestId, found: true, receipt: {...receipt}} : {contractVersion: 1, collectionId, requestId, found: false};
    }
    throw new Error('Unexpected synthetic path.');
  };
  const identity = {id: owner.id, sessionId, email: owner.email, role: owner.role, permissions: owner.permissions, expiresAt: owner.expiresAt};
  const context: NativeProvisionContext = {request, user: {...owner}, identity, collectionId, enabled: true, isEnabled: () => allowed,
    isCurrent: () => current, isVisible: () => visible, verifyFresh: async () => fresh, storage: tab, sharedStorage: shared, lock, createKey: () => requestId};
  return {context, tab, shared, identity, pin, request,
    setCurrent(value: boolean) {current = value;}, setFresh(value: boolean) {fresh = value;}, setVisible(value: boolean) {visible = value;}, setAllowed(value: boolean) {allowed = value;},
    setLoseApply(value: boolean) {loseApply = value;}, setDropApply(value: boolean) {dropApply = value;}, setLoseCancel(value: boolean) {loseCancel = value;},
    setHideDelivery(value: boolean) {hideDuringDelivery = value;}, setCorruptDelivery(value: boolean) {corruptDelivery = value;}, setSource(value: Record<string, unknown>) {source = value;},
    setOriginalReceipt(value: Record<string, unknown>) {receipts.set(requestId, value);},
    state: () => ({submitted, cancellations, lookups, deliveries, capturedPinWasValid, durableHadSecret, deliverySecretCleared: !lastDelivery || !Object.hasOwn(lastDelivery, 'installationToken')})};
}
const pinRequest = {operation: 'set_pin' as const, principalId: staffPrincipal, installationId: null, profile: null};
const grantRequest = {operation: 'grant_installation' as const, principalId: staffPrincipal, installationId, profile: 'staff' as const};
beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true});});

describe('BuriMunsi protected native provisioning', () => {
  it('rejects an opaque directory principal before requesting or submitting native setup', async () => {
    const f = fixture(), paths: string[] = [];
    const context = {...f.context, request: async (path: string, options?: Parameters<AdminRequest>[1]) => {paths.push(path); return f.request(path, options);}};
    await expect(reviewNativeProvisioning(context, {...pinRequest, principalId: 'Legacy-Principal-47'})).rejects.toThrow(/Select a current approved account/);
    expect(paths).toEqual([]); expect(f.state().submitted).toBe(0);
  });
  it('fails closed when gated off, hidden, unverified, or without owner identity', async () => {
    const f = fixture(); await expect(reviewNativeProvisioning({...f.context, enabled: false}, pinRequest)).rejects.toThrow(/not enabled/);
    f.setVisible(false); await expect(reviewNativeProvisioning(f.context, pinRequest)).rejects.toThrow(/Return to this owner session/);
    f.setVisible(true); f.setFresh(false); await expect(reviewNativeProvisioning(f.context, pinRequest)).rejects.toThrow(/Verify your current owner email/);
    f.setFresh(true); await expect(reviewNativeProvisioning({...f.context, user: {...owner, ownerIdentity: null}}, pinRequest)).rejects.toThrow(/owner session/);
    expect(f.state().submitted).toBe(0);
  });
  it('issues a transient PIN only after review and never retains it in recovery storage', async () => {
    const f = fixture(); f.setSource({...provisioning, accounts: [{...account, accountId: null, version: 0, credentialVersion: 0, active: false}]});
    const review = await reviewNativeProvisioning(f.context, pinRequest); if (review.status !== 'ready') throw new Error('expected review');
    let used = false; expect(await submitNativeProvisioning(f.context, review, () => {used = true; return f.pin;})).toEqual({status: 'recorded'});
    expect(used && f.state().capturedPinWasValid).toBe(true); expect(f.state().durableHadSecret).toBe(false); expect(f.state().submitted).toBe(1);
    expect(await readPending(f.identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, f.tab)).toBeNull();
  });
  it('keeps an uncertain PIN request, does not replay it, and cancels the same key', async () => {
    const f = fixture(); f.setDropApply(true);
    const review = await reviewNativeProvisioning(f.context, pinRequest); if (review.status !== 'ready') throw new Error('expected review');
    expect(await submitNativeProvisioning(f.context, review, () => f.pin)).toEqual({status: 'unknown', requestKey: requestId, operation: 'set_pin'});
    expect(f.state().durableHadSecret).toBe(false); expect(await checkNativeProvisioning(f.context)).toEqual({status: 'not_found', requestKey: requestId, operation: 'set_pin'});
    await expect(cancelNativeProvisioning(f.context, grantId, 'set_pin')).rejects.toThrow(/original request changed/i);
    await expect(cancelNativeProvisioning(f.context, requestId, 'grant_installation')).rejects.toThrow(/original request changed/i);
    expect(f.state().cancellations).toBe(0);
    f.setLoseCancel(true); expect(await cancelNativeProvisioning(f.context, requestId, 'set_pin')).toEqual({status: 'unknown', requestKey: requestId, operation: 'set_pin'});
    expect(await checkNativeProvisioning(f.context)).toEqual({status: 'cancelled'}); expect(f.state().submitted).toBe(1); expect(f.state().cancellations).toBe(1);
  });
  it('does not dispatch a PIN if visibility changes while the fields are read', async () => {
    const f = fixture(), review = await reviewNativeProvisioning(f.context, pinRequest); if (review.status !== 'ready') throw new Error('expected review');
    await expect(submitNativeProvisioning(f.context, review, () => {f.setVisible(false); return f.pin;})).rejects.toThrow(/Return to this owner session/);
    expect(f.state().submitted).toBe(0); expect(await readPending(f.identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, f.tab)).toBeNull();
  });
  it('prevents another session or a mismatched receipt from settling an original PIN request', async () => {
    const f = fixture(); f.setLoseApply(true); const review = await reviewNativeProvisioning(f.context, pinRequest); if (review.status !== 'ready') throw new Error('expected review');
    await submitNativeProvisioning(f.context, review, () => f.pin); const before = f.state().lookups;
    const changed = {...owner, sessionId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'};
    expect(await checkNativeProvisioning({...f.context, user: changed, identity: {...f.identity, sessionId: changed.sessionId}, storage: storage()})).toEqual({status: 'pending', pending: {kind: 'foreign'}});
    expect(f.state().lookups).toBe(before);
    f.setOriginalReceipt({contractVersion: 1, collectionId, requestId, operation: 'set_pin', principalId: owner.principalId, accountId,
      accountVersion: 2, credentialVersion: 1, approvalVersion: 1, scopeVersion: 2, applied: true});
    await expect(checkNativeProvisioning(f.context)).rejects.toThrow(/could not be verified/);
    expect((await readPending(f.identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, f.tab))?.request_key).toBe(requestId);
  });
  it('rejects a stale confirmation after another tab completes the original request', async () => {
    const f = fixture(), other = {...f.context, storage: storage()};
    const first = await reviewNativeProvisioning(f.context, pinRequest), stale = await reviewNativeProvisioning(other, pinRequest);
    if (first.status !== 'ready' || stale.status !== 'ready') throw new Error('expected review');
    expect(await submitNativeProvisioning(f.context, first, () => f.pin)).toEqual({status: 'recorded'});
    await expect(submitNativeProvisioning(other, stale, () => f.pin)).rejects.toThrow(/Shared request recovery/); expect(f.state().submitted).toBe(1);
  });
  it('blocks new grants and delivery even if the optional feature gate is enabled', async () => {
    const f = fixture(); await expect(reviewNativeProvisioning(f.context, grantRequest)).rejects.toThrow(/delivery is unavailable/);
    const fakeReview = {status: 'ready' as const, revision: requestId, snapshot: {...grantRequest, collectionId, scopeVersion: 2, approvalVersion: 1,
      expectedAccountVersion: 1, accountId, grantId, expectedGrantVersion: 1}};
    await expect(submitNativeProvisioning(f.context, fakeReview)).rejects.toThrow(/delivery is unavailable/);
    let shown = false; await expect(openNativeDelivery(f.context, requestId, () => {shown = true;})).rejects.toThrow(/delivery is unavailable/);
    expect(shown).toBe(false); expect(f.state().submitted).toBe(0); expect(f.state().deliveries).toBe(0);
  });
  it('checks an unchanged Flutter grant, fences revocation and can explicitly close the original checkpoint', async () => {
    const f = fixture(); const intent = {operation: 'grant_installation', requestId, collectionId, principalId: staffPrincipal, scopeVersion: 2,
      approvalVersion: 1, expectedAccountVersion: 1, accountId, grantId, installationId, profile: 'staff', expectedGrantVersion: 1, reason: 'Owner approved managed installation'};
    await retainPending(f.identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, requestId, 'admin_users.manage', intent, f.tab);
    f.setOriginalReceipt({contractVersion: 1, collectionId, requestId, operation: intent.operation, principalId: staffPrincipal, accountId, accountVersion: 1, credentialVersion: 1,
      approvalVersion: 1, scopeVersion: 2, applied: true, grantId, installationId, profile: 'staff', grantVersion: 2, active: true, deliveryExpiresAt: Date.now() + 120_000});
    expect((await checkNativeProvisioning(f.context)).status).toBe('delivery');
    const other = {...f.context, storage: storage()}; expect((await checkNativeProvisioning(other)).status).toBe('delivery');
    expect(await reviewNativeRevocation(other, grantId)).toEqual({status: 'pending', pending: {kind: 'unbound', requestKey: requestId}});
    await expect(closeNativeDelivery(other, grantId)).rejects.toThrow(/original request changed/i);
    const beforeClose = f.state().lookups;
    await closeNativeDelivery({...other, enabled: false}, requestId);
    expect(f.state().lookups).toBe(beforeClose + 1);
    expect((await checkNativeProvisioning(f.context)).status).toBe('delivery');
    await closeNativeDelivery(f.context, requestId);
    expect(await readPending(f.identity, 'burimunsi.provisioning', `${collectionId}:${staffPrincipal}`, f.tab)).toBeNull();
    expect(f.state().submitted).toBe(0); expect(f.state().deliveries).toBe(0);
  });
  it('blocks invalid targets, stale versions and loss of authority or live gate', async () => {
    const f = fixture(); await expect(reviewNativeProvisioning(f.context, {...pinRequest, principalId: 'not-a-person'})).rejects.toThrow(/current approved account/);
    const review = await reviewNativeProvisioning(f.context, pinRequest); if (review.status !== 'ready') throw new Error('expected review');
    f.setSource({...provisioning, accounts: [{...account, version: 2}]}); await expect(submitNativeProvisioning(f.context, review, () => f.pin)).rejects.toThrow(/changed/);
    f.setSource(provisioning); f.setAllowed(false); await expect(submitNativeProvisioning(f.context, review, () => f.pin)).rejects.toThrow(/not enabled/);
    f.setAllowed(true); f.setCurrent(false); await expect(submitNativeProvisioning(f.context, review, () => f.pin)).rejects.toThrow(/owner session/);
    expect(f.state().submitted).toBe(0);
  });
});
