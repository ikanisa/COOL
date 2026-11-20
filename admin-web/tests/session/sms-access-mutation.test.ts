import {createHash, webcrypto} from 'node:crypto';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {parseSmsAccess, parseSmsAccessReceipt, parseSmsDecision} from '../../src/features/assisted/SmsControlsPage';
import {changeSmsAccess, checkSmsAccessOriginal, listSmsManagementPending, replaySmsAccess, SmsAccessOutcomeUnknown, type SmsAccessContext} from '../../src/features/assisted/smsAccessMutations';

const ownerId = 'cdd3c1c0-c124-4c8a-9719-bd2435d198d1', principalId = '53c51330-f311-4519-977b-30f67b47c1f1', sessionId = '0f689afa-5a45-4fb5-a147-9aff36f137dd', transactionId = '6ea1b44a-25b7-4f2a-9d20-5829675211bc';
const timestamp = '2026-10-18T12:34:56.000Z', marker = {contract_version: 1, legal_release_approved: false, provider_approved: false, delivery_confirmed: false};
const storageKey = `collect.admin.notification-management.${ownerId}.${sessionId}.${principalId}.collect.admin.pending-attempts.v1`;
const hash = (value: Record<string, unknown>) => createHash('sha256').update(JSON.stringify(Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b))))).digest('hex');
function access(enabled: boolean, revision = 3) {return {ok: true, result: {...marker, scope: 'owner_receipt_sms_access', current_admin_id: ownerId, current_principal_id: principalId, decision_revision: revision, read_granted: enabled, manage_granted: enabled, can_operate: enabled, permissions: ['assisted_sms.read', 'assisted_sms.manage']}};}
function receipt(requestId: string, enabled: boolean, replay = false) {
  const decision = {kind: 'authenticated_owner_receipt_sms_access', request_id: requestId, grant_transaction_id: transactionId, current_admin_id: ownerId, current_principal_id: principalId, decision_revision: 4, originating_session_id: transactionId, public_session_id: sessionId, enabled, permissions: ['assisted_sms.read', 'assisted_sms.manage'], recorded_at: timestamp};
  return {ok: true, result: {...marker, scope: 'owner_receipt_sms_access', ...decision, read_granted: enabled, manage_granted: enabled, can_operate: enabled, decision_sha256: hash(decision), recorded_state_only: true, replay}};
}
function status(requestId: string, current: boolean, recorded: boolean, enabled = false) {
  return {ok: true, result: {...marker, scope: 'owner_receipt_sms_access_operation', request_id: requestId, observed: recorded, status: recorded ? 'recorded' : 'not_recorded', may_be_in_flight: !recorded, recorded_decision: recorded ? receipt(requestId, enabled).result : null, current_access: access(current, recorded ? 4 : 3).result, recorded_state_only: true, may_send: false, replay_authorized: false}};
}
let current = true;
const ctx = (request: SmsAccessContext['request'], enabled = true, permissions = ['admin_users.manage', 'assisted_sms.manage']): SmsAccessContext => ({allowAccessChanges: enabled, authorityEpoch: 1, identity: {id: ownerId, email: 'info@ikanisa.com', role: 'owner', sessionId, principalId, expiresAt: new Date(Date.now() + 3_600_000).toISOString(), permissions}, request, verifyFresh: vi.fn(async () => true), isCurrent: () => current, parseAccess: (body) => parseSmsAccess(body, ownerId, principalId), parseReceipt: (body, requestId) => parseSmsAccessReceipt(body, requestId, ownerId, principalId, sessionId), parseStatus: (body, requestId) => parseSmsDecision(body, 'access', requestId, ownerId, principalId, sessionId)});
beforeEach(() => {vi.stubGlobal('crypto', webcrypto); sessionStorage.clear(); current = true;});
afterEach(() => {sessionStorage.clear(); vi.unstubAllGlobals(); vi.restoreAllMocks();});

describe('default-off owner SMS access changes', () => {
  it('requires the explicit gate, owner permission and confirmation before dispatch', async () => {
    const request = vi.fn(async () => ({})), expected = parseSmsAccess(access(false), ownerId, principalId);
    expect(() => changeSmsAccess(ctx(request, false), expected, true, true)).toThrow();
    expect(() => changeSmsAccess({...ctx(request), identity: {...ctx(request).identity, role: 'admin'}}, expected, true, true)).toThrow();
    await expect(changeSmsAccess(ctx(request), expected, true, false)).rejects.toThrow(/confirm/);
    expect(request).not.toHaveBeenCalled();
    expect(sessionStorage.getItem(storageKey)).toBeNull();
  });

  it('retains the exact original decision head before enabling, then reads current grants independently', async () => {
    let writes = 0;
    const request = vi.fn(async (_path, options) => {
      if (options.method === 'GET') return access(writes > 0, writes ? 4 : 3);
      const saved = JSON.parse(sessionStorage.getItem(storageKey)!).entries[0];
      expect(saved.intent).toEqual({action: 'access', expected_decision_revision: 3, resource_id: principalId});
      expect(options.body).toEqual({request_id: saved.request_key, expected_read: false, expected_manage: false, expected_decision_revision: 3, enabled: true, owner_confirmation: true});
      expect(options.idempotencyKey).toBeUndefined();
      writes++; return receipt(saved.request_key, true);
    });
    const result = await changeSmsAccess(ctx(request, true, ['admin_users.manage']), parseSmsAccess(access(false), ownerId, principalId), true, true);
    expect(result).toMatchObject({receipt: {enabled: true, revision: 4}, currentAccess: {readGranted: true, manageGranted: true, revision: 4}});
    expect(request).toHaveBeenCalledTimes(3);
    expect(sessionStorage.getItem(storageKey)).toBeNull();
  });

  it('retains an unknown self-disable and permits original lookup after assisted grants are removed', async () => {
    let disabled = false;
    const request = vi.fn(async (path, options) => {
      if (path.includes('/access/operations/')) return status(path.split('/').at(-1)!, false, true, false);
      if (options.method === 'GET') return access(true);
      disabled = true; throw new Error('connection lost');
    });
    const before = ctx(request), expected = parseSmsAccess(access(true), ownerId, principalId);
    await expect(changeSmsAccess(before, expected, false, true)).rejects.toBeInstanceOf(SmsAccessOutcomeUnknown);
    expect(disabled).toBe(true);
    const after = {...ctx(request, false, ['admin_users.manage']), authorityEpoch: 2};
    const [saved] = await listSmsManagementPending(after);
    expect(saved.intent).toMatchObject({action: 'access', expected_decision_revision: 3});
    const result = await checkSmsAccessOriginal(after, saved, null);
    expect(result).toMatchObject({observed: true, decision: {enabled: false, revision: 4}, currentAccess: {readGranted: false, manageGranted: false}});
    expect(sessionStorage.getItem(storageKey)).toBeNull();
    expect(request.mock.calls.filter(([, options]) => options.method === 'POST')).toHaveLength(1);
  });

  it('checks an unresolved original before a deliberate identical same-UUID replay', async () => {
    const posts: Record<string, unknown>[] = [];
    const request = vi.fn(async (path, options) => {
      if (path.includes('/access/operations/')) return status(path.split('/').at(-1)!, true, false);
      if (options.method === 'GET') return access(true, posts.length > 1 ? 4 : 3);
      posts.push(options.body);
      if (posts.length === 1) throw new Error('connection lost');
      return receipt(String(options.body.request_id), false, true);
    });
    const context = ctx(request), expected = parseSmsAccess(access(true), ownerId, principalId);
    let failure: SmsAccessOutcomeUnknown | null = null;
    try {await changeSmsAccess(context, expected, false, true);} catch (error) {if (error instanceof SmsAccessOutcomeUnknown) failure = error; else throw error;}
    expect(failure).not.toBeNull();
    await expect(replaySmsAccess(context, failure!.checkpoint, failure!.original)).rejects.toThrow(/Check the original/);
    await expect(checkSmsAccessOriginal(context, failure!.checkpoint, failure!.original)).resolves.toMatchObject({observed: false});
    await expect(replaySmsAccess(context, failure!.checkpoint, failure!.original)).resolves.toMatchObject({receipt: {enabled: false, replay: true}});
    expect(posts).toHaveLength(2); expect(posts[1]).toEqual(posts[0]);
    expect(sessionStorage.getItem(storageKey)).toBeNull();
  });

  it('returns a recorded decision separately when the subsequent current-access read fails', async () => {
    let reads = 0;
    const request = vi.fn(async (_path, options) => {
      if (options.method === 'GET') {if (++reads === 1) return access(true); throw new Error('offline');}
      return receipt(String(options.body.request_id), false);
    });
    const result = await changeSmsAccess(ctx(request), parseSmsAccess(access(true), ownerId, principalId), false, true);
    expect(result).toMatchObject({receipt: {enabled: false}, currentAccess: null});
    expect(sessionStorage.getItem(storageKey)).toBeNull();
  });
});
