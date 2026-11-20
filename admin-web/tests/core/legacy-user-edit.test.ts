import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PENDING_KEY, readPending, retainPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { currentLegacyPerson, lookupLegacyUserEdit, parseLegacyUserEditIntent, restoreLegacyUserEdit, retryLegacyUserEdit, submitLegacyUserEdit, type LegacyPersonSnapshot, type LegacyUserEditContext } from '../../src/features/core/legacyUserEdit';

const actor = '11111111-1111-4111-8111-111111111111', key = '22222222-2222-4222-8222-222222222222', requestId = '33333333-3333-4333-8333-333333333333', userId = '44444444-4444-4444-8444-444444444444', operatorId = '55555555-5555-4555-8555-555555555555';
const person: LegacyPersonSnapshot = {id: userId, publicId: '123456', displayName: 'Recorded Person', nameRecorded: true, memberType: 'app', momoProvider: 'mtn_momo', momoNumber: '0788123456', momoCode: '0009', email: 'person@example.test', phone: '+250788123456', status: 'active', operatorId: null, version: 1};
const detail = {resource_type: 'users', current_actor_id: actor, can_manage: true, resource: {id: userId, collect_user_id: userId, public_id: '123456', display_name: 'Recorded Person', display_name_recorded: true, member_type: 'app', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '0009', email: 'person@example.test', phone_e164: '+250788123456', status: 'active', operator_admin_id: null, version: 1}};
const intent = {display_name: 'Updated Person', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '0009', expected_version: 1, reason: 'Review recorded profile'};
const receipt = {request_id: requestId, resource_type: 'users', resource_id: userId, version: 2, status: 'succeeded'}, found = {status: 'succeeded', request_id: requestId, receipt};
function identity(role: PendingIdentity['role'] = 'admin'): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'operator@example.test', role, permissions: ['users.read', 'users.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: LegacyUserEditContext['request'], role: PendingIdentity['role'] = 'admin'): LegacyUserEditContext {const user = identity(role); return {request, identity: user, actorId: actor, userId, permissions: user.permissions, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: LegacyUserEditContext) {const state = await restoreLegacyUserEdit(ctx); if (state.kind !== 'ready') throw new Error('Expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('legacy person profile editing', () => {
  it('validates provider-number matching, Direct contact, version and exact editable fields', () => {
    expect(parseLegacyUserEditIntent(intent, 'app')).toEqual(intent);
    for (const invalid of [{...intent, momo_provider: 'airtel_money'}, {...intent, momo_pay_code: '09'}, {...intent, expected_version: Number.MAX_SAFE_INTEGER}, {...intent, status: 'suspended'}, {...intent, reason: 'short'}]) expect(() => parseLegacyUserEditIntent(invalid, 'app')).toThrow();
    expect(() => parseLegacyUserEditIntent({...intent, momo_number: ''}, 'direct')).toThrow();
  });
  it('requires legacy model, manager, read permissions and the default-off write gate', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitLegacyUserEdit({...ctx, enabled: false}, intent, person, '')).rejects.toThrow('not enabled');
    await expect(restoreLegacyUserEdit({...ctx, financialModel: 'canonical_evidence_ledger'})).rejects.toThrow('unavailable');
    await expect(restoreLegacyUserEdit(context(request, 'staff'))).rejects.toThrow('unavailable');
    await expect(restoreLegacyUserEdit({...ctx, permissions: ['users.manage']})).rejects.toThrow('unavailable');
    expect(request).not.toHaveBeenCalled();
  });
  it('checks current identity and version, then verifies the direct result against the actor-scoped request receipt', async () => {
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'PATCH') {expect(path).toBe(`operations/users/${userId}`); expect(options.body).toEqual(intent); expect(options.idempotencyKey).toBe(key); expect(await readPending(identity(), 'operating-updateuser', userId)).toMatchObject({request_key: key, intent}); return receipt;}
      return path.startsWith('operations/requests/') ? found : detail;
    });
    const ctx = context(request), observed = await revision(ctx);
    expect(await currentLegacyPerson(ctx)).toEqual(person);
    expect(await submitLegacyUserEdit(ctx, intent, person, observed)).toEqual({status: 'succeeded', receipt: {requestId, userId, version: 2}});
    expect(request).toHaveBeenCalledTimes(4); expect(await readPending(identity(), 'operating-updateuser', userId)).toBeNull();
  });
  it('fails before dispatch for stale version, changed identity, closed or operator-linked accounts', async () => {
    for (const changed of [
      {...detail, resource: {...detail.resource, version: 2}}, {...detail, resource: {...detail.resource, public_id: '999999'}},
      {...detail, resource: {...detail.resource, status: 'closed'}}, {...detail, resource: {...detail.resource, operator_admin_id: operatorId}},
    ]) {
      sessionStorage.clear(); localStorage.clear(); const request = vi.fn().mockResolvedValue(changed), ctx = context(request), observed = await revision(ctx);
      await expect(submitLegacyUserEdit(ctx, intent, person, observed)).rejects.toThrow(); expect(request).toHaveBeenCalledOnce(); expect(await readPending(identity(), 'operating-updateuser', userId)).toBeNull();
    }
  });
  it('preserves unknown outcomes and explicitly retries the exact original key, body and source', async () => {
    const request = vi.fn().mockResolvedValueOnce(detail).mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(detail).mockResolvedValueOnce(receipt).mockResolvedValueOnce(found);
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitLegacyUserEdit(ctx, intent, person, observed)).toEqual({status: 'unknown', requestKey: key}); const pending = await restoreLegacyUserEdit(ctx);
    expect(await lookupLegacyUserEdit(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true}); expect(request).toHaveBeenCalledTimes(3);
    expect((await retryLegacyUserEdit(ctx, pending)).status).toBe('succeeded'); expect(request).toHaveBeenNthCalledWith(6, `operations/users/${userId}`, {method: 'PATCH', body: intent, idempotencyKey: key});
  });
  it('blocks retry if the original person has changed since the unknown outcome', async () => {
    const request = vi.fn().mockResolvedValueOnce(detail).mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({...detail, resource: {...detail.resource, version: 2}});
    const ctx = context(request), observed = await revision(ctx); await submitLegacyUserEdit(ctx, intent, person, observed); const pending = await restoreLegacyUserEdit(ctx);
    await expect(retryLegacyUserEdit(ctx, pending)).rejects.toThrow('person changed'); expect(request).toHaveBeenCalledTimes(4);
  });
  it('recovers committed requests without replay and keeps mismatched receipts unresolved', async () => {
    const request = vi.fn().mockResolvedValueOnce(detail).mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce(found), ctx = context(request), observed = await revision(ctx);
    await submitLegacyUserEdit(ctx, intent, person, observed); const pending = await restoreLegacyUserEdit(ctx);
    expect(await lookupLegacyUserEdit(ctx, pending)).toEqual({status: 'succeeded', receipt: {requestId, userId, version: 2}}); expect(request).toHaveBeenCalledTimes(3);
    sessionStorage.clear(); localStorage.clear();
    const badRequest = vi.fn().mockResolvedValueOnce(detail).mockResolvedValueOnce(receipt).mockResolvedValueOnce({...found, receipt: {...receipt, version: 3}}), bad = context(badRequest), next = await revision(bad);
    expect(await submitLegacyUserEdit(bad, intent, person, next)).toEqual({status: 'unknown', requestKey: key}); expect((await restoreLegacyUserEdit(bad)).kind).toBe('owned');
  });
  it('checks unbound Flutter intents but never replays them', async () => {
    await retainPending(identity(), 'operating-updateuser', userId, key, 'users.manage', {...intent, status: 'suspended'});
    const request = vi.fn().mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(found), ctx = context(request), pending = await restoreLegacyUserEdit(ctx);
    expect(await lookupLegacyUserEdit(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false}); await expect(retryLegacyUserEdit(ctx, pending)).rejects.toThrow('remains unresolved');
    expect((await lookupLegacyUserEdit(ctx, pending)).status).toBe('succeeded'); expect(request).toHaveBeenCalledTimes(3);
  });
  it('keeps crash references, blocks other sessions and refuses a modified retained intent', async () => {
    const request = vi.fn().mockResolvedValueOnce(detail).mockRejectedValueOnce(new Error('lost')).mockResolvedValue({status: 'not_found'}), ctx = context(request), observed = await revision(ctx);
    await submitLegacyUserEdit(ctx, intent, person, observed); expect(await restoreLegacyUserEdit({...ctx, identity: {...ctx.identity, sessionId: 'other'}})).toEqual({kind: 'foreign'});
    const envelope = JSON.parse(sessionStorage.getItem(PENDING_KEY)!) as {entries: Array<{intent: {reason: string}}>}; envelope.entries[0].intent.reason = 'Changed retained explanation'; sessionStorage.setItem(PENDING_KEY, JSON.stringify(envelope));
    const changed = await restoreLegacyUserEdit(ctx); expect(await lookupLegacyUserEdit(ctx, changed)).toEqual({status: 'not_found', retryAvailable: false});
    sessionStorage.clear(); const crash = await restoreLegacyUserEdit(ctx); expect(crash).toEqual({kind: 'owned', requestKey: key, attempt: null}); await expect(retryLegacyUserEdit(ctx, crash)).rejects.toThrow('intent is unavailable');
  });
  it('refuses stale review revisions and a gate that closes while rechecking the person', async () => {
    let enabled = true; const request = vi.fn().mockImplementation(async () => {enabled = false; return detail;}), ctx = {...context(request), isEnabled: () => enabled}, observed = await revision(ctx);
    await expect(submitLegacyUserEdit(ctx, intent, person, observed)).rejects.toThrow('not enabled'); expect(request).toHaveBeenCalledOnce();
    enabled = true; const fresh = await revision(ctx);
    await withPendingFence({identity: ctx.identity, family: 'operating-updateuser', resourceId: userId, isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async access => {access.reserve(key, access.read().revision); access.clear(key);});
    const stable = {...ctx, request: vi.fn().mockResolvedValue(detail)};
    await expect(submitLegacyUserEdit(stable, intent, person, fresh)).rejects.toThrow('Shared request recovery');
  });
});
