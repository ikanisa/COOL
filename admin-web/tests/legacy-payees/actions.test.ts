import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PENDING_KEY, readPending, retainPending } from '../../src/features/core/pendingAttempt';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { currentLegacyPayee, lookupLegacyPayee, parseLegacyPayeeIntent, restoreLegacyPayee, retryLegacyPayee, submitLegacyPayee } from '../../src/features/legacy-payees/actions';
import { context, found, groupDetail, groupId, groupRow, identity, intent, key, mockApi, otherPayee, payeeId, payeeRow, receipt } from './fixture';

beforeEach(() => {sessionStorage.clear(); localStorage.clear();});
async function ready(ctx: ReturnType<typeof context>) {const value = await restoreLegacyPayee(ctx); if (value.kind !== 'ready') throw new Error('Expected ready'); return value.revision;}
describe('legacy receiver actions', () => {
  it('validates only name/status with exact group and receiver versions, and requires role, permissions and write gate', async () => {
    expect(parseLegacyPayeeIntent(intent)).toEqual(intent);
    for (const value of [{...intent, network: 'airtel_money'}, {...intent, expected_group_version: 0}, {...intent, expected_version: Number.MAX_SAFE_INTEGER}, {...intent, reason: 'short'}, {...intent, status: 'unknown'}]) expect(() => parseLegacyPayeeIntent(value)).toThrow();
    const ctx = context(mockApi()); await expect(restoreLegacyPayee({...ctx, financialModel: 'canonical_evidence_ledger'})).rejects.toThrow('unavailable');
    await expect(restoreLegacyPayee({...ctx, identity: {...identity, role: 'staff'}})).rejects.toThrow('unavailable');
    await expect(restoreLegacyPayee({...ctx, permissions: ['receivers.manage']})).rejects.toThrow('unavailable');
    const source = await currentLegacyPayee(ctx), revision = await ready(ctx); await expect(submitLegacyPayee({...ctx, enabled: false}, intent, source, revision)).rejects.toThrow('not enabled');
  });
  it('rechecks complete group and receiver state, sends the exact body and verifies the actor-scoped receipt', async () => {
    const request = mockApi({write: async (_path, args) => {if (args?.method) {expect(args.body).toEqual(intent); expect(args.idempotencyKey).toBe(key); return receipt;} return found();}}), ctx = context(request), source = await currentLegacyPayee(ctx), revision = await ready(ctx);
    expect(source.activePayeeId).toBe(payeeId); expect(source.group.version).toBe(3); expect(source.payee.route).toBe('0041258');
    expect(await submitLegacyPayee(ctx, intent, source, revision)).toEqual({status: 'succeeded', receipt: {requestId: receipt.request_id, payeeId, version: 3}});
    expect(request).toHaveBeenCalledWith(`operations/payees/${payeeId}`, {method: 'PATCH', body: intent, idempotencyKey: key}); expect((await restoreLegacyPayee(ctx)).kind).toBe('ready');
  });
  it('prevents deactivating the only active receiver of an active group or activating while another receiver is active', async () => {
    const ctx = context(mockApi()), source = await currentLegacyPayee(ctx), revision = await ready(ctx);
    await expect(submitLegacyPayee(ctx, {...intent, status: 'inactive'}, source, revision)).rejects.toThrow('changed');
    sessionStorage.clear(); localStorage.clear(); const inactive = {...payeeRow, status: 'inactive'}, other = {...payeeRow, id: otherPayee}, otherCtx = context(mockApi({payee: inactive, rows: [inactive, other]})), otherSource = await currentLegacyPayee(otherCtx), next = await ready(otherCtx);
    await expect(submitLegacyPayee(otherCtx, intent, otherSource, next)).rejects.toThrow('changed');
  });
  it('allows deactivation in a suspended group while keeping the recorded route unchanged', async () => {
    const suspended = {...groupRow, status: 'suspended'}, changed = {...intent, status: 'inactive' as const}, request = mockApi({group: suspended, write: async (_path, args) => args?.method ? receipt : found()}), ctx = context(request), source = await currentLegacyPayee(ctx), revision = await ready(ctx);
    expect((await submitLegacyPayee(ctx, changed, source, revision)).status).toBe('succeeded'); expect(request).toHaveBeenCalledWith(`operations/payees/${payeeId}`, {method: 'PATCH', body: changed, idempotencyKey: key});
  });
  it('fails closed on archived groups, duplicate/mismatched receiver rows and more than 1,000 payees', async () => {
    const fixtures = [mockApi({group: {...groupRow, status: 'archived'}}), mockApi({rows: [payeeRow, payeeRow]}), mockApi({rows: [{...payeeRow, label: 'Other route owner'}]}), mockApi({rows: []})];
    for (const request of fixtures) await expect(currentLegacyPayee(context(request))).rejects.toThrow();
    const huge = vi.fn(async (path: string) => path.startsWith('operations/groups/') ? groupDetail(Array.from({length: 100}, () => payeeRow), groupRow, 1001) : {resource_type: 'payees', current_actor_id: identity.id, can_manage: true, resource: payeeRow});
    await expect(currentLegacyPayee(context(huge))).rejects.toThrow();
  });
  it('reads all pages and detects a receiver outside the first page', async () => {
    const makeId = (n: number) => `aaaaaaaa-aaaa-4aaa-8aaa-${String(n).padStart(12, '0')}`;
    const first = Array.from({length: 100}, (_, index) => ({...payeeRow, id: makeId(index), status: 'inactive'}));
    const request = vi.fn(async (path: string) => path.startsWith('operations/payees/') ? {resource_type: 'payees', current_actor_id: identity.id, can_manage: true, resource: payeeRow} : path.includes('offset=0') ? groupDetail(first, groupRow, 101) : groupDetail([payeeRow], groupRow, 101, 100));
    expect((await currentLegacyPayee(context(request))).total).toBe(101); expect(request).toHaveBeenCalledTimes(3);
    const bad = vi.fn(async (path: string) => path.startsWith('operations/payees/') ? {resource_type: 'payees', current_actor_id: identity.id, can_manage: true, resource: payeeRow} : path.includes('offset=0') ? groupDetail(first, groupRow, 101) : groupDetail([payeeRow], {...groupRow, version: 4}, 101, 100));
    await expect(currentLegacyPayee(context(bad))).rejects.toThrow('changed');
  });
  it('never replays unknown outcomes automatically and retries the exact body and original key after explicit recovery', async () => {
    let writes = 0, original: unknown; const request = mockApi({write: async (_path, args) => {if (args?.method) {writes++; expect(args.idempotencyKey).toBe(key); if (writes === 1) {original = args.body; throw new Error('lost');} expect(args.body).toEqual(original); return receipt;} return writes === 1 ? {status: 'not_found'} : found();}}), ctx = context(request), source = await currentLegacyPayee(ctx), revision = await ready(ctx);
    expect(await submitLegacyPayee(ctx, intent, source, revision)).toEqual({status: 'unknown', requestKey: key}); expect((await readPending(identity, 'legacy-payee-update-guarded', payeeId))?.request_key).toBe(key);
    const pending = await restoreLegacyPayee(ctx); expect(await lookupLegacyPayee(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true}); expect(writes).toBe(1);
    expect((await retryLegacyPayee(ctx, pending)).status).toBe('succeeded'); expect(writes).toBe(2);
  });
  it('checks older Flutter requests without retry and blocks a new guarded action in the same tab', async () => {
    const request = mockApi({write: async () => ({status: 'not_found'})}), ctx = context(request), source = await currentLegacyPayee(ctx), revision = await ready(ctx), old = {label: intent.label, status: intent.status, expected_version: intent.expected_version, reason: intent.reason};
    await retainPending(identity, 'operating-updatepayee', payeeId, key, 'receivers.manage', old);
    const result = await submitLegacyPayee(ctx, intent, source, revision); expect(result.status).toBe('existing'); const pending = await restoreLegacyPayee(ctx);
    expect(await lookupLegacyPayee(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false}); await expect(retryLegacyPayee(ctx, pending)).rejects.toThrow('unresolved');
    expect(await readPending(identity, 'legacy-payee-update-guarded', payeeId)).toBeNull(); expect(request.mock.calls.every(([, args]) => !args?.method)).toBe(true);
  });
  it('keeps both original references and fails closed if Flutter and guarded requests coexist', async () => {
    const request = mockApi({write: async (_path, args) => args?.method ? Promise.reject(new Error('lost')) : {status: 'not_found'}}), ctx = context(request), source = await currentLegacyPayee(ctx), revision = await ready(ctx);
    await submitLegacyPayee(ctx, intent, source, revision);
    await retainPending(identity, 'operating-updatepayee', payeeId, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'receivers.manage', {label: intent.label, status: intent.status, expected_version: intent.expected_version, reason: intent.reason});
    await expect(restoreLegacyPayee(ctx)).rejects.toThrow('Multiple original');
    expect(await readPending(identity, 'operating-updatepayee', payeeId)).not.toBeNull(); expect(await readPending(identity, 'legacy-payee-update-guarded', payeeId)).not.toBeNull();
  });
  it('blocks changed group, tampered intent, foreign session and stale confirmations', async () => {
    const request = mockApi({write: async (_path, args) => args?.method ? Promise.reject(new Error('lost')) : {status: 'not_found'}}), ctx = context(request), source = await currentLegacyPayee(ctx), revision = await ready(ctx); await submitLegacyPayee(ctx, intent, source, revision);
    let pending = await restoreLegacyPayee(ctx); const changed = mockApi({group: {...groupRow, version: 4}, write: async () => ({status: 'not_found'})});
    await expect(retryLegacyPayee({...ctx, request: changed}, pending)).rejects.toThrow('changed');
    const envelope = JSON.parse(sessionStorage.getItem(PENDING_KEY)!) as {entries: Array<{intent: {reason: string}}>}; envelope.entries[0].intent.reason = 'Altered retained reason'; sessionStorage.setItem(PENDING_KEY, JSON.stringify(envelope)); pending = await restoreLegacyPayee(ctx);
    expect(await lookupLegacyPayee(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false});
    const fakeSuccess = mockApi({write: async () => found()}); await expect(lookupLegacyPayee({...ctx, request: fakeSuccess}, pending)).rejects.toThrow('receipt');
    expect(await restoreLegacyPayee({...ctx, identity: {...identity, sessionId: 'another-session'}})).toEqual({kind: 'foreign'});
    sessionStorage.clear(); localStorage.clear(); const old = await ready(ctx);
    await withPendingFence({identity, family: 'operating-updatepayee', resourceId: payeeId, isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async access => {access.reserve(key, access.read().revision); access.clear(key);});
    await expect(submitLegacyPayee(ctx, intent, source, old)).rejects.toThrow('Shared request recovery');
  });
  it('keeps crash references and requires fresh verification before dispatch', async () => {
    const request = mockApi({write: async (_path, args) => args?.method ? Promise.reject(new Error('lost')) : {status: 'not_found'}}), ctx = context(request), source = await currentLegacyPayee(ctx), revision = await ready(ctx);
    await expect(submitLegacyPayee({...ctx, verifyFresh: async () => false}, intent, source, revision)).rejects.toThrow('verification'); expect((await restoreLegacyPayee(ctx)).kind).toBe('ready');
    await submitLegacyPayee(ctx, intent, source, revision); sessionStorage.clear(); const crash = await restoreLegacyPayee(ctx); expect(crash).toEqual({kind: 'owned', requestKey: key, attempt: null});
    await expect(retryLegacyPayee(ctx, crash)).rejects.toThrow('intent is unavailable'); expect(groupId).toBe(source.group.id);
  });
  it('rechecks the write gate after fresh verification and does not reserve or dispatch if it closes', async () => {
    let enabled = true; const request = mockApi(), ctx = {...context(request), isEnabled: () => enabled, verifyFresh: async () => {enabled = false; return true;}}, source = await currentLegacyPayee(ctx), revision = await ready(ctx);
    await expect(submitLegacyPayee(ctx, intent, source, revision)).rejects.toThrow('not enabled'); expect(request.mock.calls.every(([, args]) => !args?.method)).toBe(true);
    enabled = true; expect((await restoreLegacyPayee(ctx)).kind).toBe('ready');
  });
});
