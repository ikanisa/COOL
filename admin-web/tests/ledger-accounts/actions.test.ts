import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import { withPendingFence } from '../../src/features/operations/pendingFence';
import { parseLedgerAccountDetail } from '../../src/features/ledger-accounts/contracts';
import { lookupLedgerAccountChange, restoreLedgerAccountChange, retryLedgerAccountChange, submitLedgerAccountChange, type LedgerAccountChangeContext, type LedgerAccountIntent } from '../../src/features/ledger-accounts/actions';

const id = '11111111-1111-4111-8111-111111111111', actor = '22222222-2222-4222-8222-222222222222', group = '33333333-3333-4333-8333-333333333333', key = '44444444-4444-4444-8444-444444444444', operation = '55555555-5555-4555-8555-555555555555';
const account = {id, group_id: group, code: '1000', name: 'Recorded funds', account_type: 'asset', normal_side: 'debit', currency: 'RWF', status: 'active', created_by_admin_id: actor, created_at: 1794816000, version: 1};
const detail = {resource_type: 'accounts', resource: account, current_actor_id: actor, can_manage: true, related: {}, related_pages: {}, related_truncated: false};
const receipt = {request_id: operation, resource_type: 'accounts', resource_id: id, version: 2, status: 'succeeded'};
const intent: LedgerAccountIntent = {name: 'Updated funds', status: 'closed', expected_version: 1, reason: 'Review account change'};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.com', role: 'admin', permissions: ['ledger.read', 'ledger.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: LedgerAccountChangeContext['request']): LedgerAccountChangeContext {return {request, identity: identity(), account: parseLedgerAccountDetail(detail, id, actor, 'admin').account, canManage: true, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: LedgerAccountChangeContext) {const state = await restoreLedgerAccountChange(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('Legacy ledger account contract', () => {
  it('requires an exact current-account response and rejects other models or wrong actors', () => {
    expect(parseLedgerAccountDetail(detail, id, actor, 'admin').account.code).toBe('1000');
    expect(() => parseLedgerAccountDetail({...detail, model: 'canonical_evidence_ledger'}, id, actor, 'admin')).toThrow();
    expect(() => parseLedgerAccountDetail({...detail, current_actor_id: group}, id, actor, 'admin')).toThrow();
    expect(() => parseLedgerAccountDetail(detail, id, actor, 'staff')).toThrow();
    expect(() => parseLedgerAccountDetail({...detail, resource: {...account, currency: 'USD'}}, id, actor, 'admin')).toThrow();
    expect(() => parseLedgerAccountDetail({...detail, resource: {...account, version: 0}}, id, actor, 'admin')).toThrow();
    expect(() => parseLedgerAccountDetail({...detail, related: {entries: []}}, id, actor, 'admin')).toThrow();
  });
  it('gates writes by role, read/manage/history permission, server authority and model', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitLedgerAccountChange({...ctx, enabled: false}, intent, '')).rejects.toThrow('not enabled');
    await expect(submitLedgerAccountChange({...ctx, identity: {...ctx.identity, role: 'staff'}}, intent, '')).rejects.toThrow('unavailable');
    await expect(submitLedgerAccountChange({...ctx, identity: {...ctx.identity, permissions: ['ledger.read', 'ledger.manage']}}, intent, '')).rejects.toThrow('unavailable');
    await expect(submitLedgerAccountChange({...ctx, canManage: false}, intent, '')).rejects.toThrow('unavailable');
    await expect(submitLedgerAccountChange({...ctx, financialModel: 'canonical_evidence_ledger'}, intent, '')).rejects.toThrow('unavailable');
    expect(request).not.toHaveBeenCalled();
  });
  it('rechecks the account, retains its original key and intent, and validates the versioned receipt', async () => {
    const request = vi.fn(async (_path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'PATCH') {
        expect(options).toEqual({method: 'PATCH', body: intent, idempotencyKey: key});
        expect(await readPending(identity(), 'operating-updateaccount', id)).toMatchObject({request_key: key, intent});
        return receipt;
      }
      return detail;
    });
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitLedgerAccountChange(ctx, intent, observed)).toEqual({status: 'succeeded', receipt: {requestId: operation, accountId: id, version: 2}});
    expect(await readPending(identity(), 'operating-updateaccount', id)).toBeNull();
    expect(await restoreLedgerAccountChange(ctx)).toMatchObject({kind: 'ready'});
    expect(request).toHaveBeenNthCalledWith(1, `operations/accounts/${id}`);
    expect(request).toHaveBeenNthCalledWith(2, `operations/accounts/${id}`, {method: 'PATCH', body: intent, idempotencyKey: key});
  });
  it('does not dispatch if the write gate closes during the fresh-account check', async () => {
    let enabled = true;
    const request = vi.fn(async () => {enabled = false; return detail;});
    const ctx = {...context(request), isEnabled: () => enabled}, observed = await revision(ctx);
    await expect(submitLedgerAccountChange(ctx, intent, observed)).rejects.toThrow('not enabled');
    expect(request).toHaveBeenCalledTimes(1);
    expect(await readPending(identity(), 'operating-updateaccount', id)).toBeNull();
  });
  it('recovers a lost response using only the original key and never automatically resends', async () => {
    const request = vi.fn().mockResolvedValueOnce(detail).mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'succeeded', request_id: operation, receipt});
    const ctx = context(request), observed = await revision(ctx);
    expect(await submitLedgerAccountChange(ctx, intent, observed)).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreLedgerAccountChange(ctx);
    expect(await lookupLedgerAccountChange(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect((await lookupLedgerAccountChange(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(3, `operations/requests/${key}`);
    expect(request).toHaveBeenNthCalledWith(4, `operations/requests/${key}`);
    expect(request).toHaveBeenCalledTimes(4);
    expect(await restoreLedgerAccountChange(ctx)).toMatchObject({kind: 'ready'});
  });
  it('retries only after explicit review, a fresh original-key lookup and a current version check', async () => {
    const request = vi.fn().mockResolvedValueOnce(detail).mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(detail).mockResolvedValueOnce(receipt);
    const ctx = context(request), observed = await revision(ctx);
    await submitLedgerAccountChange(ctx, intent, observed);
    const pending = await restoreLedgerAccountChange(ctx);
    expect(await lookupLedgerAccountChange(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect((await retryLedgerAccountChange(ctx, pending)).status).toBe('succeeded');
    expect(request).toHaveBeenNthCalledWith(4, `operations/requests/${key}`);
    expect(request).toHaveBeenNthCalledWith(5, `operations/accounts/${id}`);
    expect(request).toHaveBeenNthCalledWith(6, `operations/accounts/${id}`, {method: 'PATCH', body: intent, idempotencyKey: key});
  });
  it('rejects changed state and invalid acknowledgements without losing the request', async () => {
    const changed = {...detail, resource: {...account, version: 2, name: 'Different name'}};
    const request = vi.fn().mockResolvedValueOnce(detail).mockRejectedValueOnce(new Error('lost')).mockResolvedValueOnce({status: 'not_found'}).mockResolvedValueOnce(changed).mockResolvedValueOnce({status: 'succeeded', request_id: operation, receipt: {...receipt, version: 3}});
    const ctx = context(request), observed = await revision(ctx);
    await submitLedgerAccountChange(ctx, intent, observed);
    const pending = await restoreLedgerAccountChange(ctx);
    await expect(retryLedgerAccountChange(ctx, pending)).rejects.toThrow('account changed');
    await expect(lookupLedgerAccountChange(ctx, pending)).rejects.toThrow();
    expect(request).toHaveBeenCalledTimes(5);
    expect((await restoreLedgerAccountChange(ctx)).kind).toBe('owned');
  });
  it('blocks stale reviews, other sessions and retries when the original intent is missing', async () => {
    const request = vi.fn(), ctx = context(request), observed = await revision(ctx);
    await withPendingFence({identity: ctx.identity, family: 'operating-updateaccount', resourceId: id, isCurrent: () => true, storage: localStorage, lock: ctx.lock}, async (access) => {access.reserve(key, access.read().revision); access.clear(key);});
    request.mockResolvedValueOnce(detail);
    await expect(submitLedgerAccountChange(ctx, intent, observed)).rejects.toThrow('Shared request recovery');
    const next = await revision(ctx), original = {...ctx, request: vi.fn().mockResolvedValueOnce(detail).mockRejectedValueOnce(new Error('lost'))};
    await submitLedgerAccountChange(original, intent, next);
    const other = {...ctx, identity: {...ctx.identity, sessionId: 'other'}};
    expect(await restoreLedgerAccountChange(other)).toEqual({kind: 'foreign'});
    const blank: Storage = {length: 0, clear() {}, getItem() {return null;}, key() {return null;}, removeItem() {}, setItem() {}};
    const crash = {...ctx, storage: blank, request: vi.fn().mockResolvedValue({status: 'not_found'})};
    const pending = await restoreLedgerAccountChange(crash);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    expect(await lookupLedgerAccountChange(crash, pending)).toEqual({status: 'not_found', retryAvailable: false});
    await expect(retryLedgerAccountChange(crash, pending)).rejects.toThrow('intent is unavailable');
  });
});
