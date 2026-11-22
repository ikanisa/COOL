import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PENDING_KEY, readPending, retainPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { lookupLegacyUserCreate, parseLegacyUserIntent, restoreLegacyUserCreate, retryLegacyUserCreate, submitLegacyUserCreate, type LegacyUserCreateContext } from '../../src/features/core/legacyUserCreate';

const actor = '11111111-1111-4111-8111-111111111111', key = '22222222-2222-4222-8222-222222222222', requestId = '33333333-3333-4333-8333-333333333333', personId = '44444444-4444-4444-8444-444444444444';
const app = {display_name: 'Recorded Person', member_type: 'app', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '0009', email: 'person@example.test', phone_e164: null, status: 'invited', reason: 'Record verified form details'};
const direct = {display_name: 'Recorded Person', member_type: 'direct', momo_provider: 'airtel_money', momo_number: '0722123456', momo_pay_code: '', email: null, status: 'active', reason: 'Record verified form details'};
const receipt = {request_id: requestId, resource_type: 'users', resource_id: personId, version: 1, status: 'succeeded'};
const found = {status: 'succeeded', request_id: requestId, receipt};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions: ['users.read', 'users.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: LegacyUserCreateContext['request']): LegacyUserCreateContext {return {request, identity: identity(), actorId: actor, permissions: identity().permissions, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: LegacyUserCreateContext) {const state = await restoreLegacyUserCreate(ctx); if (state.kind !== 'ready') throw new Error('Expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('legacy person creation', () => {
  it('validates the exact App and Direct backend bodies, provider prefix and contact invariants', () => {
    expect(parseLegacyUserIntent(app)).toEqual(app); expect(parseLegacyUserIntent(direct)).toEqual(direct);
    for (const invalid of [
      {...app, momo_provider: 'airtel_money'}, {...app, momo_pay_code: '09'}, {...app, email: null, phone_e164: null}, {...app, email: 'Not An Email'},
      {...direct, momo_number: ''}, {...direct, phone_e164: '+250788123456'}, {...app, reason: 'short'}, {...app, unexpected: true}, {...app, status: 'invented'},
    ]) expect(() => parseLegacyUserIntent(invalid)).toThrow();
  });
  it('requires the legacy model, manager, request-history permission and default-off gate', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitLegacyUserCreate({...ctx, enabled: false}, app, '')).rejects.toThrow('not enabled');
    await expect(restoreLegacyUserCreate({...ctx, financialModel: 'canonical_evidence_ledger'})).rejects.toThrow('unavailable');
    await expect(restoreLegacyUserCreate({...ctx, identity: {...ctx.identity, role: 'staff'}})).rejects.toThrow('unavailable');
    await expect(restoreLegacyUserCreate({...ctx, permissions: ['users.manage']})).rejects.toThrow('unavailable');
    expect(request).not.toHaveBeenCalled();
  });
  it('keeps the original key and verifies the direct receipt against its actor-scoped server lookup', async () => {
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'POST') {
        expect(path).toBe('operations/users'); expect(options).toEqual({method: 'POST', body: app, idempotencyKey: key});
        expect(await readPending(identity(), 'operating-createuser', 'new')).toMatchObject({request_key: key, intent: app}); return receipt;
      }
      expect(path).toBe(`operations/requests/${key}`); return found;
    });
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitLegacyUserCreate(ctx, app, observed)).toEqual({status: 'succeeded', receipt: {requestId, userId: personId, version: 1}});
    expect(request).toHaveBeenCalledTimes(2); expect(await readPending(identity(), 'operating-createuser', 'new')).toBeNull();
  });
  it('never automatically retries a lost response; explicit retry uses the identical key and intent', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(receipt).mockResolvedValueOnce(found);
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitLegacyUserCreate(ctx, direct, observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreLegacyUserCreate(ctx);
    expect(await lookupLegacyUserCreate(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect(request).toHaveBeenCalledTimes(2);
    expect((await retryLegacyUserCreate(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(4, 'operations/users', {method: 'POST', body: direct, idempotencyKey: key});
    expect(request).toHaveBeenCalledTimes(5);
  });
  it('recovers a committed request without another write and retains mismatched receipts', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce(found);
    const ctx = context(request), observed = await revision(ctx);
    await submitLegacyUserCreate(ctx, app, observed); const pending = await restoreLegacyUserCreate(ctx);
    expect(await lookupLegacyUserCreate(ctx, pending)).toEqual({status: 'succeeded', receipt: {requestId, userId: personId, version: 1}});
    expect(request).toHaveBeenCalledTimes(2); expect((await restoreLegacyUserCreate(ctx)).kind).toBe('ready');
    sessionStorage.clear(); localStorage.clear();
    const bad = context(vi.fn().mockResolvedValueOnce(receipt).mockResolvedValueOnce({...found, request_id: personId})), next = await revision(bad);
    expect(await submitLegacyUserCreate(bad, app, next)).toEqual({status: 'unknown', requestKey: key});
    expect((await restoreLegacyUserCreate(bad)).kind).toBe('owned');
  });
  it('checks but never replays unbound Flutter or cross-model checkpoints', async () => {
    await retainPending(identity(), 'operating-createuser', 'new', key, 'users.manage', {...app, unsupported_old_field: 'preserved'});
    const request = vi.fn().mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(found), ctx = context(request), pending = await restoreLegacyUserCreate(ctx);
    expect(pending).toMatchObject({kind: 'owned', requestKey: key});
    expect(await lookupLegacyUserCreate(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false});
    await expect(retryLegacyUserCreate(ctx, pending)).rejects.toThrow();
    expect(await lookupLegacyUserCreate(ctx, pending)).toEqual({status: 'succeeded', receipt: {requestId, userId: personId, version: 1}});
    expect(request).toHaveBeenCalledTimes(3);
  });
  it('allows a status check but blocks retry if the retained original body changes', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValue({status: 'not_found'}), ctx = context(request), observed = await revision(ctx);
    await submitLegacyUserCreate(ctx, app, observed);
    const envelope = JSON.parse(sessionStorage.getItem(PENDING_KEY)!) as {entries: Array<{intent: {reason: string}}>};
    envelope.entries[0].intent.reason = 'Changed retained explanation'; sessionStorage.setItem(PENDING_KEY, JSON.stringify(envelope));
    const pending = await restoreLegacyUserCreate(ctx);
    expect(await lookupLegacyUserCreate(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false});
    await expect(retryLegacyUserCreate(ctx, pending)).rejects.toThrow('remains unresolved');
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
  });
  it('preserves a crashed tab reference, blocks a new key and lets the original account check it', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce(found), ctx = context(request), observed = await revision(ctx);
    await submitLegacyUserCreate(ctx, app, observed); sessionStorage.clear();
    const pending = await restoreLegacyUserCreate(ctx);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryLegacyUserCreate(ctx, pending)).rejects.toThrow('intent is unavailable');
    expect(await lookupLegacyUserCreate(ctx, pending)).toEqual({status: 'succeeded', receipt: {requestId, userId: personId, version: 1}});
  });
  it('blocks foreign sessions and stale reviews after another tab completes', async () => {
    const request = vi.fn().mockRejectedValue(new Error('lost')), ctx = context(request), observed = await revision(ctx);
    await withPendingFence({identity: ctx.identity, family: 'operating-createuser', resourceId: 'new', isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async access => {access.reserve(key, access.read().revision); access.clear(key);});
    await expect(submitLegacyUserCreate(ctx, app, observed)).rejects.toThrow('Shared request recovery');
    const next = await revision(ctx); await submitLegacyUserCreate(ctx, app, next);
    expect(await restoreLegacyUserCreate({...ctx, identity: {...ctx.identity, sessionId: 'new-session'}})).toEqual({kind: 'foreign'});
  });
  it('fails closed if model binding cannot be persisted or the action gate closes before retry', async () => {
    const blocked: Storage = {get length() {return sessionStorage.length;}, clear() {sessionStorage.clear();}, getItem(k) {return sessionStorage.getItem(k);}, key(i) {return sessionStorage.key(i);}, removeItem(k) {sessionStorage.removeItem(k);}, setItem(k, v) {if (k.startsWith('collect.admin.legacy-user-create')) throw new Error('blocked'); sessionStorage.setItem(k, v);}};
    const request = vi.fn(), ctx = {...context(request), storage: blocked}, observed = await revision(ctx);
    await expect(submitLegacyUserCreate(ctx, app, observed)).rejects.toThrow(); expect(request).not.toHaveBeenCalled();
    sessionStorage.clear(); localStorage.clear(); let enabled = true;
    const lost = vi.fn().mockRejectedValueOnce(new Error('lost')).mockImplementationOnce(async () => {enabled = false; return {status: 'not_found'};});
    const retryCtx = {...context(lost), isEnabled: () => enabled}, next = await revision(retryCtx);
    await submitLegacyUserCreate(retryCtx, app, next); const pending = await restoreLegacyUserCreate(retryCtx);
    await expect(retryLegacyUserCreate(retryCtx, pending)).rejects.toThrow('not enabled'); expect(lost).toHaveBeenCalledTimes(2);
  });
});
