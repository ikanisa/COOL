import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PENDING_KEY, retainPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { currentLegacyGroup, lookupLegacyGroupAction, parseLegacyGroupIntent, restoreLegacyGroupAction, retryLegacyGroupAction, searchLegacyOwners, submitLegacyGroupAction, type LegacyGroupContext, type LegacyGroupSnapshot, type LegacyOwner } from '../../src/features/core/legacyGroupActions';

const actor = '11111111-1111-4111-8111-111111111111', key = '22222222-2222-4222-8222-222222222222', requestId = '33333333-3333-4333-8333-333333333333', groupId = '44444444-4444-4444-8444-444444444444', ownerId = '55555555-5555-4555-8555-555555555555';
const owner: LegacyOwner = {id: ownerId, publicId: '123456', displayName: 'Recorded owner', memberType: 'app', momoNumber: '0788123456', version: 2};
const ownerRow = {id: ownerId, public_id: '123456', display_name: 'Recorded owner', member_type: 'app', momo_number: '0788123456', version: 2, label: 'Recorded owner · 123456 · 0788123456'};
const ownerDetail = {resource_type: 'users', current_actor_id: actor, can_manage: false, resource: {...ownerRow, collect_user_id: ownerId, status: 'active', display_name_recorded: true}};
const group: LegacyGroupSnapshot = {id: groupId, slug: 'test-group', title: 'Test group', type: 'ikimina', description: '', category: null, purpose: null, cadence: null, amount: null, status: 'draft', visibility: 'private', sponsored: 0, version: 1};
const groupDetail = {resource_type: 'groups', current_actor_id: actor, can_manage: true, resource: {id: groupId, slug: group.slug, title: group.title, collection_type: group.type, description: group.description, category_subtype: null, purpose_label: null, recurring_cadence: null, suggested_amount_rwf: null, status: group.status, visibility: group.visibility, is_platform_sponsored: 0, country_code: 'RW', currency: 'RWF', version: 1}};
const base = {title: 'Test group', collection_type: 'ikimina', description: '', category_subtype: null, purpose_label: null, recurring_cadence: null, suggested_amount_rwf: null, reason: 'Review group details'};
const draft = {...base, slug: 'test-group', visibility: 'private', is_platform_sponsored: false, status: 'draft'};
const active = {...draft, status: 'active', owner_user_id: ownerId, receiver: {label: 'Recorded receiver', network: 'mtn_momo', momo_number_or_code: '008000'}};
const edit = {...base, title: 'Updated group', expected_version: 1};
const createReceipt = {request_id: requestId, resource_type: 'groups', resource_id: groupId, version: 1, status: 'succeeded'}, editReceipt = {...createReceipt, version: 2};
const found = (receipt: typeof createReceipt) => ({status: 'succeeded', request_id: requestId, receipt});
function identity(role: PendingIdentity['role'] = 'admin'): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'operator@example.test', role, permissions: ['collections.create', 'collections.manage', 'collections.read', 'users.read', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: LegacyGroupContext['request'], mode: 'create' | 'edit' = 'create', role: PendingIdentity['role'] = 'admin'): LegacyGroupContext {const user = identity(role); return {mode, groupId: mode === 'edit' ? groupId : undefined, request, identity: user, actorId: actor, permissions: user.permissions, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: LegacyGroupContext) {const state = await restoreLegacyGroupAction(ctx); if (state.kind !== 'ready') throw new Error('Expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('legacy group actions', () => {
  it('allows private draft or active creation with a complete owner and receiver; metadata edits preserve status and visibility', () => {
    expect(parseLegacyGroupIntent(draft, 'create')).toEqual(draft); expect(parseLegacyGroupIntent(active, 'create')).toEqual(active); expect(parseLegacyGroupIntent(edit, 'edit')).toEqual(edit);
    for (const invalid of [{...active, owner_user_id: undefined}, {...active, receiver: undefined}, {...draft, visibility: 'public_approved'}, {...draft, suggested_amount_rwf: 0}, {...draft, slug: 'Bad Slug'}, {...edit, status: 'active'}, {...edit, expected_version: Number.MAX_SAFE_INTEGER}]) {
      expect(() => parseLegacyGroupIntent(invalid, 'expected_version' in invalid ? 'edit' : 'create')).toThrow();
    }
  });
  it('requires the gate and current role/permissions; staff can create but cannot edit', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitLegacyGroupAction({...ctx, enabled: false}, draft, null, '')).rejects.toThrow('not enabled');
    await expect(restoreLegacyGroupAction({...ctx, financialModel: 'canonical_evidence_ledger'})).rejects.toThrow('unavailable');
    await expect(restoreLegacyGroupAction(context(request, 'edit', 'staff'))).rejects.toThrow('unavailable');
    await expect(restoreLegacyGroupAction({...ctx, permissions: ['collections.create']})).rejects.toThrow('unavailable');
    const restricted = ['collections.create', 'overview.read'];
    await expect(restoreLegacyGroupAction({...ctx, permissions: restricted, identity: {...ctx.identity, permissions: restricted}})).rejects.toThrow('unavailable');
    const staff = context(request, 'create', 'staff'); expect((await restoreLegacyGroupAction({...staff, permissions: restricted, identity: {...staff.identity, permissions: restricted}})).kind).toBe('ready');
    expect(request).not.toHaveBeenCalled();
  });
  it('loads active owner choices and rechecks the selected identity before creating an active group', async () => {
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (path.startsWith('operations/lookups?')) return {rows: [ownerRow]};
      if (path === `operations/users/${ownerId}`) return ownerDetail;
      if (options?.method === 'POST') {expect(options.body).toEqual(active); expect(options.idempotencyKey).toBe(key); return createReceipt;}
      return found(createReceipt);
    });
    const ctx = context(request, 'create', 'staff'), observed = await revision(ctx);
    expect(await searchLegacyOwners(ctx, 'Recorded')).toEqual([owner]);
    expect(await submitLegacyGroupAction(ctx, active, owner, observed)).toEqual({status: 'succeeded', receipt: {requestId, groupId, version: 1}});
    expect(request).toHaveBeenCalledTimes(4);
  });
  it('rejects a changed owner or group snapshot before dispatch', async () => {
    const changedOwner = {...ownerDetail, resource: {...ownerDetail.resource, version: 3}};
    const createRequest = vi.fn().mockResolvedValue(changedOwner), create = context(createRequest), createRevision = await revision(create);
    await expect(submitLegacyGroupAction(create, active, owner, createRevision)).rejects.toThrow('changed'); expect(createRequest).toHaveBeenCalledTimes(1);
    sessionStorage.clear(); localStorage.clear();
    const changedGroup = {...groupDetail, resource: {...groupDetail.resource, version: 2}}, editRequest = vi.fn().mockResolvedValue(changedGroup), updating = context(editRequest, 'edit'), editRevision = await revision(updating);
    await expect(submitLegacyGroupAction(updating, edit, group, editRevision)).rejects.toThrow('changed'); expect(editRequest).toHaveBeenCalledTimes(1);
  });
  it('submits only group metadata with the exact expected version and verifies the original server receipt', async () => {
    const request = vi.fn(async (_path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'PATCH') {expect(options.body).toEqual(edit); expect(options.idempotencyKey).toBe(key); return editReceipt;}
      return _path.startsWith('operations/requests/') ? found(editReceipt) : groupDetail;
    });
    const ctx = context(request, 'edit'), observed = await revision(ctx);
    expect(await currentLegacyGroup(ctx)).toEqual(group);
    expect(await submitLegacyGroupAction(ctx, edit, group, observed)).toEqual({status: 'succeeded', receipt: {requestId, groupId, version: 2}});
    expect(request).toHaveBeenCalledTimes(4);
  });
  it('never automatically replays an unknown result; a reviewed retry retains the original body and key', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(createReceipt).mockResolvedValueOnce(found(createReceipt));
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitLegacyGroupAction(ctx, draft, null, observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreLegacyGroupAction(ctx);
    expect(await lookupLegacyGroupAction(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true}); expect(request).toHaveBeenCalledTimes(2);
    expect((await retryLegacyGroupAction(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(4, 'operations/groups', {method: 'POST', body: draft, idempotencyKey: key});
  });
  it('does not retry if the original owner or group changed during recovery', async () => {
    const request = vi.fn().mockResolvedValueOnce(ownerDetail).mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({...ownerDetail, resource: {...ownerDetail.resource, version: 3}});
    const ctx = context(request), observed = await revision(ctx); await submitLegacyGroupAction(ctx, active, owner, observed);
    const pending = await restoreLegacyGroupAction(ctx);
    await expect(retryLegacyGroupAction(ctx, pending)).rejects.toThrow('owner changed'); expect(request).toHaveBeenCalledTimes(4);
  });
  it('recovers a saved receipt without replay and keeps invalid response data unresolved', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce(found(createReceipt)), ctx = context(request), observed = await revision(ctx);
    await submitLegacyGroupAction(ctx, draft, null, observed); const pending = await restoreLegacyGroupAction(ctx);
    expect(await lookupLegacyGroupAction(ctx, pending)).toEqual({status: 'succeeded', receipt: {requestId, groupId, version: 1}}); expect(request).toHaveBeenCalledTimes(2);
    sessionStorage.clear(); localStorage.clear();
    const badRequest = vi.fn().mockResolvedValueOnce(createReceipt).mockResolvedValueOnce(found({...createReceipt, resource_id: ownerId})), bad = context(badRequest), next = await revision(bad);
    expect(await submitLegacyGroupAction(bad, draft, null, next)).toEqual({status: 'unknown', requestKey: key}); expect((await restoreLegacyGroupAction(bad)).kind).toBe('owned');
  });
  it('checks old Flutter checkpoints but refuses to replay without a model and intent binding', async () => {
    await retainPending(identity(), 'operating-creategroup', 'new', key, 'collections.create', {...draft, visibility: 'public_approved'});
    const request = vi.fn().mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(found(createReceipt)), ctx = context(request), pending = await restoreLegacyGroupAction(ctx);
    expect(await lookupLegacyGroupAction(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false});
    await expect(retryLegacyGroupAction(ctx, pending)).rejects.toThrow('remains unresolved');
    expect((await lookupLegacyGroupAction(ctx, pending)).status).toBe('succeeded');
  });
  it('keeps a crash reference, blocks foreign sessions and refuses tampered intents', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('lost')).mockResolvedValue({status: 'not_found'}), ctx = context(request), observed = await revision(ctx);
    await submitLegacyGroupAction(ctx, draft, null, observed);
    expect(await restoreLegacyGroupAction({...ctx, identity: {...ctx.identity, sessionId: 'other'}})).toEqual({kind: 'foreign'});
    const envelope = JSON.parse(sessionStorage.getItem(PENDING_KEY)!) as {entries: Array<{intent: {reason: string}}>}; envelope.entries[0].intent.reason = 'Changed retained explanation'; sessionStorage.setItem(PENDING_KEY, JSON.stringify(envelope));
    const changed = await restoreLegacyGroupAction(ctx); expect(await lookupLegacyGroupAction(ctx, changed)).toEqual({status: 'not_found', retryAvailable: false});
    sessionStorage.clear(); const crash = await restoreLegacyGroupAction(ctx); expect(crash).toEqual({kind: 'owned', requestKey: key, attempt: null}); await expect(retryLegacyGroupAction(ctx, crash)).rejects.toThrow('intent is unavailable');
  });
  it('blocks stale confirmations and a gate that closes during source revalidation', async () => {
    let enabled = true; const request = vi.fn().mockImplementation(async () => {enabled = false; return ownerDetail;}), ctx = {...context(request), isEnabled: () => enabled}, observed = await revision(ctx);
    await expect(submitLegacyGroupAction(ctx, active, owner, observed)).rejects.toThrow('not enabled'); expect(request).toHaveBeenCalledTimes(1);
    enabled = true; const fresh = await revision(ctx);
    await withPendingFence({identity: ctx.identity, family: 'operating-creategroup', resourceId: 'new', isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async access => {access.reserve(key, access.read().revision); access.clear(key);});
    await expect(submitLegacyGroupAction(ctx, draft, null, fresh)).rejects.toThrow('Shared request recovery');
  });
});
