import {createHash, webcrypto} from 'node:crypto';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {parseSmsDecision, parseSmsPolicy, parseSmsPolicyReceipt} from '../../src/features/assisted/smsControlContracts';
import {checkSmsPolicyOriginal, disableSmsPolicy, enableSmsPolicy, listSmsControlPending, replaySmsPolicy, SmsPolicyOutcomeUnknown, type SmsPolicyContext} from '../../src/features/assisted/smsPolicyMutations';

const ownerId = 'cdd3c1c0-c124-4c8a-9719-bd2435d198d1', principalId = '53c51330-f311-4519-977b-30f67b47c1f1', sessionId = '0f689afa-5a45-4fb5-a147-9aff36f137dd', groupId = '6ea1b44a-25b7-4f2a-9d20-5829675211bc';
const timestamp = '2026-10-18T12:34:56.000Z', marker = {contract_version: 1, legal_release_approved: false, provider_approved: false, delivery_confirmed: false};
const policy = {ok: true, result: {...marker, scope: 'owner_receipt_sms_configuration', collection_id: groupId, configured: true, enabled: true, revision: 3, template_key: 'collect.recorded_contribution.v1', recorded_owner_decision_sha256: 'a'.repeat(64), recorded_at: timestamp, collection_active: true}};
const expected = parseSmsPolicy(policy, groupId);
const storageKey = `collect.admin.notification-management.${ownerId}.${sessionId}.${principalId}.collect.admin.pending-attempts.v1`;
const hash = (value: Record<string, unknown>) => createHash('sha256').update(JSON.stringify(Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b))))).digest('hex');
function receipt(requestId: string, enabled = false, revision = 4) {
  const decision = {kind: 'authenticated_owner_receipt_sms_policy', request_id: requestId, collection_id: groupId, revision, enabled, template_key: 'collect.recorded_contribution.v1', owner_user_id: principalId, originating_session_id: groupId, public_session_id: sessionId, recorded_at: timestamp, legal_release_approved: false, provider_approved: false};
  return {ok: true, result: {...marker, scope: 'owner_receipt_sms_configuration', ...decision, recorded_owner_decision_sha256: hash(decision)}};
}
function missing(requestId: string) {return {ok: true, result: {...marker, scope: 'owner_receipt_sms_policy_operation', request_id: requestId, observed: false, status: 'not_recorded', may_be_in_flight: true, recorded_decision: null, recorded_state_only: true, may_send: false, replay_authorized: false}};}
let current = true;
const ctx = (request: SmsPolicyContext['request'], enabled = true): SmsPolicyContext => ({allowPolicyChanges: enabled, authorityEpoch: 1, identity: {id: ownerId, email: 'info@ikanisa.com', role: 'owner', sessionId, principalId, expiresAt: new Date(Date.now() + 3_600_000).toISOString(), permissions: ['admin_users.manage', 'assisted_sms.manage']}, request, verifyFresh: vi.fn(async () => true), isCurrent: () => current, parsePolicy: parseSmsPolicy, parseReceipt: (body, requestId) => parseSmsPolicyReceipt(body, requestId, principalId, sessionId), parseStatus: (body, requestId) => parseSmsDecision(body, 'policy', requestId, ownerId, principalId, sessionId)});
beforeEach(() => {vi.stubGlobal('crypto', webcrypto); sessionStorage.clear(); current = true;});
afterEach(() => {sessionStorage.clear(); vi.unstubAllGlobals(); vi.restoreAllMocks();});

describe('default-off SMS group policy changes', () => {
  it('fails before any request without explicit activation and current owner permission', () => {
    const request = vi.fn(async () => ({}));
    expect(() => disableSmsPolicy(ctx(request, false), expected)).toThrow();
    expect(() => disableSmsPolicy({...ctx(request), identity: {...ctx(request).identity, permissions: ['admin_users.manage']}}, expected)).toThrow();
    expect(request).not.toHaveBeenCalled();
    expect(sessionStorage.getItem(storageKey)).toBeNull();
  });

  it('checks current policy and persists the Flutter-compatible reference before the exact POST', async () => {
    const request = vi.fn(async (_path, options) => {
      if (options.method === 'GET') return policy;
      const raw = sessionStorage.getItem(storageKey);
      expect(raw).not.toBeNull();
      const saved = JSON.parse(raw!).entries[0];
      expect(saved.intent).toEqual({action: 'policy', resource_id: groupId});
      expect(options.body).toEqual({request_id: saved.request_key, expected_revision: 3, enabled: false, owner_confirmation: false});
      expect(options.idempotencyKey).toBeUndefined();
      return receipt(saved.request_key);
    });
    await expect(disableSmsPolicy(ctx(request), expected)).resolves.toMatchObject({enabled: false, revision: 4, collectionId: groupId});
    expect(request).toHaveBeenCalledTimes(2);
    expect(sessionStorage.getItem(storageKey)).toBeNull();
  });

  it('does not dispatch when the current revision changed or reference storage fails', async () => {
    const stale = vi.fn(async () => ({ok: true, result: {...policy.result, revision: 4}}));
    await expect(disableSmsPolicy(ctx(stale), expected)).rejects.toThrow(/policy changed/);
    expect(stale).toHaveBeenCalledOnce();
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {throw new Error('unavailable');});
    const request = vi.fn(async () => policy);
    await expect(disableSmsPolicy(ctx(request), expected)).rejects.toThrow();
    expect(request).toHaveBeenCalledOnce();
  });

  it('retains an unknown outcome, requires an original status read, then replays the exact request only by explicit action', async () => {
    const posts: JsonBody[] = [];
    type JsonBody = Record<string, unknown>;
    const request = vi.fn(async (path, options) => {
      if (path.endsWith(`/policies/${groupId}`) && options.method === 'GET') return policy;
      if (path.includes('/policies/operations/')) return missing(path.split('/').at(-1)!);
      if (options.method === 'POST') {posts.push(options.body); if (posts.length === 1) throw new Error('connection lost'); return receipt(String(options.body.request_id));}
      throw new Error('Unexpected request');
    });
    const context = ctx(request);
    let failure: SmsPolicyOutcomeUnknown | null = null;
    try {await disableSmsPolicy(context, expected);} catch (error) {if (error instanceof SmsPolicyOutcomeUnknown) failure = error; else throw error;}
    expect(failure).not.toBeNull();
    const {checkpoint, original} = failure!;
    expect((await listSmsControlPending(context))).toHaveLength(1);
    await expect(replaySmsPolicy(context, checkpoint, original)).rejects.toThrow(/Check the original/);
    expect(posts).toHaveLength(1);
    await expect(checkSmsPolicyOriginal(context, checkpoint, original)).resolves.toMatchObject({observed: false});
    await expect(replaySmsPolicy(context, checkpoint, original)).resolves.toMatchObject({enabled: false, revision: 4});
    expect(posts).toHaveLength(2);
    expect(posts[1]).toEqual(posts[0]);
    expect(sessionStorage.getItem(storageKey)).toBeNull();
  });

  it('clears restored metadata only after a verified matching original receipt, without reconstructing a replay', async () => {
    let status = false;
    const request = vi.fn(async (path, options) => {
      if (path.endsWith(`/policies/${groupId}`) && options.method === 'GET') return policy;
      if (options.method === 'POST') throw new Error('connection lost');
      if (path.includes('/policies/operations/')) {
        const key = path.split('/').at(-1)!;
        if (!status) return missing(key);
        return {ok: true, result: {...missing(key).result, observed: true, status: 'recorded', may_be_in_flight: false, recorded_decision: receipt(key).result}};
      }
      throw new Error('Unexpected request');
    });
    const context = ctx(request);
    await expect(disableSmsPolicy(context, expected)).rejects.toBeInstanceOf(SmsPolicyOutcomeUnknown);
    const [saved] = await listSmsControlPending(context);
    await checkSmsPolicyOriginal(context, saved, null);
    expect(sessionStorage.getItem(storageKey)).not.toBeNull();
    status = true;
    await expect(checkSmsPolicyOriginal(context, saved, null)).resolves.toMatchObject({observed: true});
    expect(sessionStorage.getItem(storageKey)).toBeNull();
    expect(request.mock.calls.filter(([, options]) => options.method === 'POST')).toHaveLength(1);
  });

  it('keeps a lost result on authority change and rejects the in-memory original under a new epoch', async () => {
    let finish!: (value: ReturnType<typeof receipt>) => void, sentId = '';
    const request = vi.fn(async (_path, options) => {
      if (options.method === 'GET') return policy;
      sentId = String(options.body.request_id);
      return new Promise<ReturnType<typeof receipt>>((resolve) => {finish = resolve;});
    });
    const context = ctx(request), pending = disableSmsPolicy(context, expected);
    await vi.waitFor(() => expect(sentId).not.toBe(''));
    current = false; finish(receipt(sentId));
    let failure: SmsPolicyOutcomeUnknown | null = null;
    try {await pending;} catch (error) {if (error instanceof SmsPolicyOutcomeUnknown) failure = error; else throw error;}
    expect(failure).not.toBeNull();
    expect(sessionStorage.getItem(storageKey)).not.toBeNull();
    current = true;
    const next = {...context, authorityEpoch: 2};
    await expect(checkSmsPolicyOriginal(next, failure!.checkpoint, failure!.original)).rejects.toThrow(/original policy reference/i);
    expect(request).toHaveBeenCalledTimes(2);
    expect(sessionStorage.getItem(storageKey)).not.toBeNull();
  });
});

describe('separately gated SMS policy enablement', () => {
  const disabled = {ok: true, result: {...policy.result, configured: false, enabled: false, revision: 0, recorded_owner_decision_sha256: null, recorded_at: null}};
  const expectedDisabled = parseSmsPolicy(disabled, groupId);
  it('requires the extra gate, explicit confirmation, current authority and fresh proof', async () => {
    const request = vi.fn(async () => disabled);
    await expect(enableSmsPolicy(ctx(request), expectedDisabled, true)).rejects.toThrow(/Confirm/);
    await expect(enableSmsPolicy({...ctx(request), allowPolicyEnabling: true}, expectedDisabled, false)).rejects.toThrow(/Confirm/);
    await expect(enableSmsPolicy({...ctx(request), allowPolicyEnabling: true, verifyFresh: async () => false}, expectedDisabled, true)).rejects.toThrow(/Verify/);
    expect(request).not.toHaveBeenCalled(); expect(sessionStorage.getItem(storageKey)).toBeNull();
  });
  it('requires a fresh active group and exact unchanged policy revision', async () => {
    const changed = vi.fn(async () => ({ok: true, result: {...disabled.result, collection_active: false}}));
    await expect(enableSmsPolicy({...ctx(changed), allowPolicyEnabling: true}, expectedDisabled, true)).rejects.toThrow(/policy changed/i);
    expect(changed).toHaveBeenCalledOnce(); expect(sessionStorage.getItem(storageKey)).toBeNull();
    const request = vi.fn(async () => disabled);
    await expect(enableSmsPolicy({...ctx(request), allowPolicyEnabling: true}, {...expectedDisabled, collectionActive: false}, true)).rejects.toThrow(/active group/i);
    expect(request).not.toHaveBeenCalled();
  });
  it('records the confirmed owner decision with Flutter-compatible metadata and exact receipt', async () => {
    const request = vi.fn(async (_path, options) => {
      if (options.method === 'GET') return disabled;
      const saved = JSON.parse(sessionStorage.getItem(storageKey)!).entries[0];
      expect(saved.intent).toEqual({action: 'policy', resource_id: groupId});
      expect(options.body).toEqual({request_id: saved.request_key, expected_revision: 0, enabled: true, owner_confirmation: true});
      return receipt(saved.request_key, true, 1);
    });
    await expect(enableSmsPolicy({...ctx(request), allowPolicyEnabling: true}, expectedDisabled, true)).resolves.toMatchObject({enabled: true, revision: 1, collectionId: groupId});
    expect(request).toHaveBeenCalledTimes(2); expect(sessionStorage.getItem(storageKey)).toBeNull();
  });
  it('retries only the original in-memory enable decision after lookup and while its gate remains active', async () => {
    const posts: Record<string, unknown>[] = [];
    const request = vi.fn(async (path, options) => {
      if (path.endsWith(`/policies/${groupId}`) && options.method === 'GET') return disabled;
      if (path.includes('/policies/operations/')) return missing(path.split('/').at(-1)!);
      if (options.method === 'POST') {posts.push(options.body); if (posts.length === 1) throw new Error('connection lost'); return receipt(String(options.body.request_id), true, 1);}
      throw new Error('Unexpected request');
    });
    const context = {...ctx(request), allowPolicyEnabling: true}; let failure: SmsPolicyOutcomeUnknown | null = null;
    try {await enableSmsPolicy(context, expectedDisabled, true);} catch (error) {if (error instanceof SmsPolicyOutcomeUnknown) failure = error; else throw error;}
    expect(failure).not.toBeNull(); await checkSmsPolicyOriginal(context, failure!.checkpoint, failure!.original);
    await expect(replaySmsPolicy({...context, allowPolicyEnabling: false}, failure!.checkpoint, failure!.original)).rejects.toThrow(/unavailable/i);
    expect(posts).toHaveLength(1); await expect(replaySmsPolicy(context, failure!.checkpoint, failure!.original)).resolves.toMatchObject({enabled: true, revision: 1});
    expect(posts).toHaveLength(2); expect(posts[1]).toEqual(posts[0]); expect(sessionStorage.getItem(storageKey)).toBeNull();
  });
  it('retains the original reference if the enablement gate closes before a response is verified', async () => {
    let finish!: (value: ReturnType<typeof receipt>) => void, sentId = '', gate = true;
    const request = vi.fn(async (_path, options) => {if (options.method === 'GET') return disabled; sentId = String(options.body.request_id); return new Promise<ReturnType<typeof receipt>>(resolve => {finish = resolve;});});
    const context = {...ctx(request), allowPolicyEnabling: true, enablementCurrent: () => gate}; const pending = enableSmsPolicy(context, expectedDisabled, true);
    await vi.waitFor(() => expect(sentId).not.toBe('')); gate = false; finish(receipt(sentId, true, 1));
    await expect(pending).rejects.toBeInstanceOf(SmsPolicyOutcomeUnknown); expect(sessionStorage.getItem(storageKey)).not.toBeNull();
  });
});
