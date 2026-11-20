import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PENDING_KEY, retainPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { currentLegacyMembership, lookupLegacyMembership, parseLegacyMembershipIntent, restoreLegacyMembership, retryLegacyMembership, searchLegacyMembers, submitLegacyMembership, type LegacyMembershipContext } from '../../src/features/core/legacyMembershipActions';

const actor = '11111111-1111-4111-8111-111111111111', key = '22222222-2222-4222-8222-222222222222', requestId = '33333333-3333-4333-8333-333333333333', groupId = '44444444-4444-4444-8444-444444444444', userId = '55555555-5555-4555-8555-555555555555', otherGroup = '66666666-6666-4666-8666-666666666666';
const identity: PendingIdentity = {id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions: ['collections.read', 'users.read', 'users.manage', 'overview.read'], expiresAt: '2100-01-01T00:00:00.000Z'};
const person = {id: userId, public_id: '123456', display_name: 'Recorded Person', member_type: 'app', momo_number: '0788123456', version: 4};
const detail = {resource_type: 'users', current_actor_id: actor, can_manage: true, resource: {...person, collect_user_id: userId, display_name_recorded: true, status: 'active'}};
const membership = {group_id: groupId, user_id: userId, group_title: 'Test group', public_id: person.public_id, display_name: person.display_name, display_name_recorded: 1, member_type: person.member_type, momo_number: person.momo_number, role: 'member', status: 'active', version: 2};
function group(rows: unknown[] = [], total = rows.length, offset = 0) {return {resource_type: 'groups', current_actor_id: actor, can_manage: true, resource: {id: groupId, title: 'Test group', country_code: 'RW', currency: 'RWF', status: 'active', version: 3}, related: {memberships: rows}, related_pages: {memberships: {total, limit: 100, offset, next_offset: offset + rows.length < total ? offset + rows.length : null}}, related_truncated: total > rows.length};}
const create = {group_id: groupId, user_id: userId, role: 'member', status: 'active', reason: 'Review membership creation'}, edit = {role: 'admin', status: 'active', expected_version: 2, reason: 'Review membership change'};
const created = {request_id: requestId, resource_type: 'memberships', resource_id: `${groupId}/${userId}`, version: 1, status: 'succeeded'}, changed = {...created, version: 3};
const found = (receipt: typeof created) => ({status: 'succeeded', request_id: requestId, receipt});
function context(request: LegacyMembershipContext['request'], mode: 'create' | 'edit' = 'create'): LegacyMembershipContext {return {mode, groupId, userId: mode === 'edit' ? userId : undefined, request, identity, actorId: actor, permissions: identity.permissions, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, verifyFresh: async () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
function api(mode: 'create' | 'edit' = 'create') {const receipt = mode === 'create' ? created : changed; return vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
  if (options?.method) {expect(options.method).toBe(mode === 'create' ? 'POST' : 'PATCH'); expect(options.body).toEqual(mode === 'create' ? create : edit); expect(options.idempotencyKey).toBe(key); return receipt;}
  if (path.startsWith('operations/requests/')) return found(receipt);
  if (path.startsWith('operations/groups/')) return group(mode === 'create' ? [] : [membership]);
  if (path.startsWith('operations/lookups?')) return {rows: [person]};
  return detail;
});}
async function ready(ctx: LegacyMembershipContext) {const state = await restoreLegacyMembership(ctx); if (state.kind !== 'ready') throw new Error('Expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('legacy membership contracts and recovery', () => {
  it('supports only exact bounded non-owner actions and requires current role, permissions and the write gate', async () => {
    const ctx = context(vi.fn()); expect(parseLegacyMembershipIntent(create, ctx)).toEqual(create);
    for (const value of [{...create, group_id: otherGroup}, {...create, role: 'owner'}, {...create, status: 'removed'}, {...create, reason: 'short'}, {...create, extra: true}]) expect(() => parseLegacyMembershipIntent(value, ctx)).toThrow();
    const editing = context(vi.fn(), 'edit'); expect(parseLegacyMembershipIntent(edit, editing)).toEqual(edit);
    for (const value of [{...edit, role: 'owner'}, {...edit, expected_version: 0}, {...edit, expected_version: Number.MAX_SAFE_INTEGER}]) expect(() => parseLegacyMembershipIntent(value, editing)).toThrow();
    await expect(restoreLegacyMembership({...ctx, identity: {...identity, role: 'staff'}})).rejects.toThrow('unavailable');
    await expect(restoreLegacyMembership({...ctx, permissions: ['users.manage']})).rejects.toThrow('unavailable');
    await expect(restoreLegacyMembership({...ctx, financialModel: 'canonical_evidence_ledger'})).rejects.toThrow('unavailable');
    await expect(searchLegacyMembers({...ctx, enabled: false}, 'Person')).rejects.toThrow('not enabled');
    expect(ctx.request).not.toHaveBeenCalled();
  });
  it('searches active people and checks the full group and person before the exact create request and receipt', async () => {
    const request = api(), ctx = context(request), revision = await ready(ctx);
    expect(await searchLegacyMembers(ctx, 'Recorded')).toEqual([{id: userId, publicId: '123456', displayName: 'Recorded Person', memberType: 'app', momoNumber: '0788123456', version: 4}]);
    const source = await currentLegacyMembership(ctx, userId); expect(source.membership).toBeNull();
    expect(await submitLegacyMembership(ctx, create, source, revision)).toEqual({status: 'succeeded', receipt: {requestId, groupId, userId, version: 1}});
    expect(request).toHaveBeenCalledWith('operations/memberships', {method: 'POST', body: create, idempotencyKey: key}); expect((await restoreLegacyMembership(ctx)).kind).toBe('ready');
  });
  it('reads the composite membership and submits its exact expected version', async () => {
    const request = api('edit'), ctx = context(request, 'edit'), revision = await ready(ctx), source = await currentLegacyMembership(ctx, userId);
    expect(source.membership).toEqual({role: 'member', status: 'active', version: 2});
    expect((await submitLegacyMembership(ctx, edit, source, revision)).status).toBe('succeeded');
    expect(request).toHaveBeenCalledWith(`operations/memberships/${groupId}/${userId}`, {method: 'PATCH', body: edit, idempotencyKey: key});
  });
  it('fails closed for owners, duplicates, mismatched identity, archived groups, missing membership and inactive people', async () => {
    for (const bad of [group([membership, membership]), group([{...membership, role: 'owner'}]), group([{...membership, display_name: 'Wrong identity'}]), {...group([membership]), resource: {...group().resource, status: 'archived'}}, group([])]) {
      const request = vi.fn(async (path: string) => path.startsWith('operations/groups/') ? bad : detail);
      await expect(currentLegacyMembership(context(request, 'edit'), userId)).rejects.toThrow();
    }
    const duplicateCreate = vi.fn(async (path: string) => path.startsWith('operations/groups/') ? group([membership]) : detail);
    await expect(currentLegacyMembership(context(duplicateCreate), userId)).rejects.toThrow('unavailable');
    const inactive = vi.fn(async (path: string) => path.startsWith('operations/groups/') ? group() : {...detail, resource: {...detail.resource, status: 'suspended'}});
    await expect(currentLegacyMembership(context(inactive), userId)).rejects.toThrow('unavailable');
  });
  it('reads every membership page and rejects inconsistent counts or changed group snapshots', async () => {
    const makeId = (n: number) => `aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12, '0')}`;
    const first = Array.from({length: 100}, (_, index) => ({...membership, user_id: makeId(index)}));
    const request = vi.fn(async (path: string) => path.startsWith('operations/users/') ? detail : path.includes('offset=0') ? group(first, 101) : group([membership], 101, 100));
    expect((await currentLegacyMembership(context(request, 'edit'), userId)).total).toBe(101); expect(request).toHaveBeenCalledTimes(3);
    const bad = vi.fn(async (path: string) => path.includes('offset=0') ? group(first, 101) : {...group([membership], 101, 100), resource: {...group().resource, version: 4}});
    await expect(currentLegacyMembership(context(bad, 'edit'), userId)).rejects.toThrow('changed');
    const huge = vi.fn().mockResolvedValue(group(first, 1001)); await expect(currentLegacyMembership(context(huge, 'edit'), userId)).rejects.toThrow();
  });
  it('does not send if the source changes between review and dispatch', async () => {
    const request = api('edit'), ctx = context(request, 'edit'), revision = await ready(ctx), source = await currentLegacyMembership(ctx, userId);
    request.mockImplementation(async (path: string) => path.startsWith('operations/groups/') ? group([{...membership, version: 3}]) : detail);
    await expect(submitLegacyMembership(ctx, edit, source, revision)).rejects.toThrow('changed'); expect(request.mock.calls.every(([, options]) => !options?.method)).toBe(true);
  });
  it('never automatically replays an unknown result, then retries only the same body and original key after lookup and review', async () => {
    let writes = 0; const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method) {writes++; expect(options.body).toEqual(edit); expect(options.idempotencyKey).toBe(key); if (writes === 1) throw new Error('lost'); return changed;}
      if (path.startsWith('operations/requests/')) return writes === 1 ? {status: 'not_found'} : found(changed);
      return path.startsWith('operations/groups/') ? group([membership]) : detail;
    });
    const ctx = context(request, 'edit'), revision = await ready(ctx), source = await currentLegacyMembership(ctx, userId);
    expect(await submitLegacyMembership(ctx, edit, source, revision)).toEqual({status: 'unknown', requestKey: key}); const pending = await restoreLegacyMembership(ctx);
    expect(await lookupLegacyMembership(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true}); expect(writes).toBe(1);
    expect((await retryLegacyMembership(ctx, pending)).status).toBe('succeeded'); expect(writes).toBe(2);
  });
  it('refuses retry after source or retained-intent changes, but can still check the original request', async () => {
    let changedSource = false; const request = vi.fn(async (path: string, options?: {method?: string}) => {if (options?.method) throw new Error('lost'); if (path.startsWith('operations/requests/')) return {status: 'not_found'}; return path.startsWith('operations/groups/') ? group([{...membership, version: changedSource ? 3 : 2}]) : detail;});
    const ctx = context(request, 'edit'), revision = await ready(ctx), source = await currentLegacyMembership(ctx, userId); await submitLegacyMembership(ctx, edit, source, revision);
    let pending = await restoreLegacyMembership(ctx); changedSource = true; await expect(retryLegacyMembership(ctx, pending)).rejects.toThrow('changed');
    const envelope = JSON.parse(sessionStorage.getItem(PENDING_KEY)!) as {entries: Array<{intent: {reason: string}}>}; envelope.entries[0].intent.reason = 'Tampered recorded reason'; sessionStorage.setItem(PENDING_KEY, JSON.stringify(envelope));
    pending = await restoreLegacyMembership(ctx); expect(await lookupLegacyMembership(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false});
    request.mockImplementation(async (path: string) => path.startsWith('operations/requests/') ? found(changed) : detail);
    await expect(lookupLegacyMembership(ctx, pending)).rejects.toThrow('could not be verified'); expect((await restoreLegacyMembership(ctx)).kind).toBe('owned');
  });
  it('checks unbound Flutter and crash requests without replay, rejecting a receipt for another group', async () => {
    await retainPending(identity, 'operating-createmembership', 'new', key, 'users.manage', {...create, group_id: otherGroup});
    const request = vi.fn().mockResolvedValue(found(created)), ctx = context(request), pending = await restoreLegacyMembership(ctx);
    await expect(lookupLegacyMembership(ctx, pending)).rejects.toThrow('receipt'); expect((await restoreLegacyMembership(ctx)).kind).toBe('owned');
    request.mockResolvedValue({status: 'not_found'}); expect(await lookupLegacyMembership(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false}); await expect(retryLegacyMembership(ctx, pending)).rejects.toThrow();
    sessionStorage.clear(); const crash = await restoreLegacyMembership(ctx); expect(crash).toEqual({kind: 'owned', requestKey: key, attempt: null}); await expect(retryLegacyMembership(ctx, crash)).rejects.toThrow('intent is unavailable');
  });
  it('keeps a mismatched or unavailable receipt unresolved and blocks another actor or stale review', async () => {
    const request = api(), ctx = context(request), revision = await ready(ctx), source = await currentLegacyMembership(ctx, userId);
    request.mockImplementation(async (path: string, options?: {method?: string}) => options?.method ? created : path.startsWith('operations/requests/') ? found({...created, version: 2}) : path.startsWith('operations/groups/') ? group() : detail);
    expect((await submitLegacyMembership(ctx, create, source, revision)).status).toBe('unknown');
    expect(await restoreLegacyMembership({...ctx, identity: {...identity, sessionId: 'another-session'}})).toEqual({kind: 'foreign'});
    sessionStorage.clear(); localStorage.clear(); const next = await ready(ctx);
    await withPendingFence({identity, family: 'operating-createmembership', resourceId: 'new', isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async access => {access.reserve(key, access.read().revision); access.clear(key);});
    await expect(submitLegacyMembership(ctx, create, source, next)).rejects.toThrow('Shared request recovery');
  });
  it('honors a write gate that closes while the source is rechecked', async () => {
    let enabled = true; const request = vi.fn(async (path: string) => {if (path.startsWith('operations/users/')) enabled = false; return path.startsWith('operations/groups/') ? group() : detail;});
    const ctx = {...context(request), isEnabled: () => enabled}, source = await currentLegacyMembership(ctx, userId); enabled = true; const revision = await ready(ctx);
    await expect(submitLegacyMembership(ctx, create, source, revision)).rejects.toThrow('not enabled'); expect(request.mock.calls.every(([path]) => !path.startsWith('operations/memberships'))).toBe(true);
  });
  it('requires fresh account verification before reserving or sending a change', async () => {
    const request = api(), ctx = {...context(request), verifyFresh: async () => false}, source = await currentLegacyMembership(ctx, userId), revision = await ready(ctx);
    await expect(submitLegacyMembership(ctx, create, source, revision)).rejects.toThrow('verification');
    expect(request.mock.calls.every(([, options]) => !options?.method)).toBe(true); expect((await restoreLegacyMembership(ctx)).kind).toBe('ready');
  });
});
