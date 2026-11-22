import { webcrypto } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './canonical-reconciliation-fixture.json';
import { canonicalRequestId, clearPending, readPending, retainPending } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';
import { parseReconciliationDetail } from '../../src/features/reconciliation/contracts';
import { lookupFinancialAttempt, parseReconciliationMembers, prepareProposal, prepareReview, RECONCILIATION_FAMILY, retryFinancialAttempt, submitFinancialAttempt } from '../../src/features/reconciliation/actions';

const permissions = ['users.read', 'ledger.read', 'account.manage', 'reconciliations.read', 'reconciliations.propose', 'reconciliations.review'];
const actorId = fixture.detail.current_actor_id;
const principalId = fixture.detail.current_principal_id;
const id = fixture.detail.resource.id;
const key = '44444444-4444-4444-8444-444444444444';
const identity: PendingIdentity = { id: actorId, sessionId: 'synthetic-session', email: 'operator@example.test', role: 'admin', permissions, expiresAt: '2100-01-01T00:00:00.000Z' };
const snapshot = () => parseReconciliationDetail(fixture.detail, 'canonical_evidence_ledger', id, actorId, principalId, permissions, 'admin');
const member = () => parseReconciliationMembers(fixture.members, snapshot(), 25, 0).rows[0];
const access = (request: FeatureAccess['request']): FeatureAccess => ({ request, permissions, actorId, principalId, role: 'admin', authorityKey: 'session-a', financialModel: 'canonical_evidence_ledger', navigate: vi.fn() });
const lock = async <T,>(_name: string, operation: () => Promise<T>): Promise<T> => operation();

beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  sessionStorage.clear();
});

describe('canonical reconciliation decisions', () => {
  it('requires the actual group, member version and recorded MoMo identity for attribution', () => {
    const selected = member();
    const intent = prepareProposal(snapshot(), selected, 'Reviewed the recorded member', permissions);
    expect(intent.body.amount_rwf).toBe(fixture.detail.resource.amount_rwf);
    expect(intent.body.expected_payment_identity).toEqual(fixture.members.rows[0].payment_identity);
    expect(() => prepareProposal(snapshot(), { ...selected, group_version: 9 }, 'Reviewed the recorded member', permissions)).toThrow();
    expect(() => prepareProposal(snapshot(), { ...selected, group_id: '99999999-9999-4999-8999-999999999999' }, 'Reviewed the recorded member', permissions)).toThrow();
  });

  it('requires independent approval of a current identity, receiver and event reference', () => {
    const detail = snapshot();
    const proposal = detail.related.proposals.rows[0];
    expect(prepareReview(detail, proposal, 'approved', 'Independent evidence review', principalId, 'admin', permissions, member()).body.outcome).toBe('approved');
    expect(() => prepareReview(detail, proposal, 'approved', 'Independent evidence review', String(proposal.proposed_by_principal_id), 'admin', permissions, member())).toThrow();
    expect(() => prepareReview(detail, proposal, 'approved', 'Independent evidence review', principalId, 'staff', permissions, member())).toThrow();
    expect(() => prepareReview(detail, proposal, 'approved', 'Independent evidence review', principalId, 'admin', permissions, { ...member(), membership_version: 2 })).toThrow();
    const withoutReference = { ...detail, resource: { ...detail.resource, provider_reference: null } };
    expect(() => prepareReview(withoutReference, proposal, 'approved', 'Independent evidence review', principalId, 'admin', permissions, member())).toThrow();
    expect(prepareReview(withoutReference, proposal, 'rejected', 'Independent evidence review', principalId, 'admin', permissions).body.outcome).toBe('rejected');
  });

  it('accepts exact managed text principals and keeps identity and request checks distinct', () => {
    const currentPrincipal = 'collect:operator-a';
    const proposer = 'collect:operator-b';
    const data = structuredClone(fixture.detail);
    data.current_principal_id = currentPrincipal;
    data.related.proposals.rows[0].proposed_by_principal_id = proposer;
    const parse = (input: unknown) => parseReconciliationDetail(input, 'canonical_evidence_ledger', id, actorId, currentPrincipal, permissions, 'admin');
    const detail = parse(data);
    const proposal = detail.related.proposals.rows[0];
    expect(prepareReview(detail, proposal, 'rejected', 'Independent review of the evidence', currentPrincipal, 'admin', permissions).body.outcome).toBe('rejected');
    expect(() => prepareReview(detail, proposal, 'rejected', 'Independent review of the evidence', proposer, 'admin', permissions)).toThrow();
    expect(() => parse({...data, current_principal_id: proposer})).toThrow();

    const row = data.related.proposals.rows[0] as Record<string, unknown>;
    Object.assign(row, {status: 'rejected', version: 2, reviewed_by_principal_id: currentPrincipal, reviewed_at: '2026-11-20T00:00:00.000Z'});
    expect(parse(data).related.proposals.rows[0].reviewed_by_principal_id).toBe(currentPrincipal);
    expect(() => parse({...data, related: {...data.related, proposals: {...data.related.proposals, rows: [{...row, request_id: currentPrincipal}]}}})).toThrow();
  });

  it('keeps a lost proposal under its original key and never replays it automatically', async () => {
    const intent = prepareProposal(snapshot(), member(), 'Reviewed the recorded member', permissions);
    const request = vi.fn(async (path: string) => {
      if (path.startsWith('reconciliations/')) throw new Error('Lost response');
      if (path === `operations/requests/${key}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      throw new Error('Unexpected request');
    });
    await expect(submitFinancialAttempt(access(request), identity, intent, key, true, async () => true, () => true, async () => true, lock)).rejects.toThrow();
    const pending = await readPending(identity, RECONCILIATION_FAMILY, id);
    expect(pending?.request_key).toBe(key);
    expect(await lookupFinancialAttempt(access(request), identity, pending!, () => true)).toBe('not_found');
    await expect(submitFinancialAttempt(access(request), identity, intent, key, true, async () => true, () => true, async () => true, lock)).rejects.toThrow();
    expect(request.mock.calls.filter(([path]) => path.startsWith('reconciliations/'))).toHaveLength(1);
    expect((await readPending(identity, RECONCILIATION_FAMILY, id))?.request_key).toBe(key);
  });

  it('refuses dispatch if the current member or evidence snapshot changed', async () => {
    const intent = prepareProposal(snapshot(), member(), 'Reviewed the recorded member', permissions);
    const request = vi.fn();
    await expect(submitFinancialAttempt(access(request), identity, intent, key, true, async () => true, () => true, async () => false, lock)).rejects.toThrow();
    expect(request).not.toHaveBeenCalled();
    expect(await readPending(identity, RECONCILIATION_FAMILY, id)).toBeNull();
  });

  it('accepts only a matching retained receipt and clears the original key on success', async () => {
    const intent = prepareProposal(snapshot(), member(), 'Reviewed the recorded member', permissions);
    const request = vi.fn(async () => ({ ...fixture.proposal_receipt, request_id: await canonicalRequestId(principalId, key) }));
    await submitFinancialAttempt(access(request), identity, intent, key, true, async () => true, () => true, async () => true, lock);
    expect(await readPending(identity, RECONCILIATION_FAMILY, id)).toBeNull();
    const forged = vi.fn(async () => ({ ...fixture.proposal_receipt, request_id: await canonicalRequestId(principalId, key), settlement_status: 'settled' }));
    await expect(submitFinancialAttempt(access(forged), identity, intent, key, true, async () => true, () => true, async () => true, lock)).rejects.toThrow();
    expect((await readPending(identity, RECONCILIATION_FAMILY, id))?.request_key).toBe(key);
  });

  it('rechecks lookup and current evidence before retrying the exact stored request', async () => {
    const original = prepareProposal(snapshot(), member(), 'Reviewed the recorded member', permissions);
    const pending = await retainPending(identity, RECONCILIATION_FAMILY, id, key, 'reconciliations.propose', original as unknown as Record<string, unknown>);
    const request = vi.fn(async (path: string, options?: { method?: string; body?: Record<string, unknown>; idempotencyKey?: string }) => {
      if (path === `operations/requests/${key}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      expect(path).toBe(`reconciliations${original.path}`); expect(options?.idempotencyKey).toBe(key); expect(options?.body).toEqual(original.body);
      return { ...fixture.proposal_receipt, request_id: await canonicalRequestId(principalId, key) };
    });
    await expect(retryFinancialAttempt(access(request), identity, pending, true, async () => true, () => true, async () => false, lock)).rejects.toThrow();
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
    expect(await retryFinancialAttempt(access(request), identity, pending, true, async () => true, () => true, async () => true, lock)).toBe('retried');
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
    expect(await readPending(identity, RECONCILIATION_FAMILY, id)).toBeNull();
  });

  it('does not retry if lookup reveals an unconfirmed or already successful request', async () => {
    const original = prepareProposal(snapshot(), member(), 'Reviewed the recorded member', permissions);
    const pending = await retainPending(identity, RECONCILIATION_FAMILY, id, key, 'reconciliations.propose', original as unknown as Record<string, unknown>);
    const requestId = await canonicalRequestId(principalId, key);
    const request = vi.fn().mockResolvedValueOnce({ contract_version: 2, model: 'canonical_evidence_ledger', status: 'unconfirmed', request_id: requestId, receipt: null })
      .mockResolvedValueOnce({ contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded', request_id: requestId,
        receipt: { ...fixture.proposal_receipt, request_id: requestId } });
    await expect(retryFinancialAttempt(access(request), identity, pending, true, async () => true, () => true, async () => true, lock)).rejects.toThrow();
    expect(await retryFinancialAttempt(access(request), identity, pending, true, async () => true, () => true, async () => true, lock)).toBe('succeeded');
    expect(request).toHaveBeenCalledTimes(2); expect(await readPending(identity, RECONCILIATION_FAMILY, id)).toBeNull();
  });

  it('keeps a cancelled request available when authority changes during receipt verification', async () => {
    const original = prepareProposal(snapshot(), member(), 'Reviewed the recorded member', permissions);
    const pending = await retainPending(identity, RECONCILIATION_FAMILY, id, key, 'reconciliations.propose', original as unknown as Record<string, unknown>);
    const requestId = await canonicalRequestId(principalId, key);
    let current = true;
    const digest = webcrypto.subtle.digest.bind(webcrypto.subtle);
    const request = vi.fn(async () => {
      vi.spyOn(webcrypto.subtle, 'digest').mockImplementationOnce(async (algorithm, data) => {
        current = false;
        return digest(algorithm, data);
      });
      return {contract_version: 2, model: 'canonical_evidence_ledger', status: 'cancelled', request_id: requestId, receipt: null};
    });
    try {
      await expect(lookupFinancialAttempt(access(request), identity, pending, () => current)).rejects.toThrow();
      expect(await readPending(identity, RECONCILIATION_FAMILY, id)).toEqual(pending);
    } finally { vi.restoreAllMocks(); }
  });

  it.each(['new', 'retry'] as const)('preserves the original key when a %s write loses authority during cleanup', async mode => {
    const original = prepareProposal(snapshot(), member(), 'Reviewed the recorded member', permissions);
    const pending = mode === 'retry' ? await retainPending(identity, RECONCILIATION_FAMILY, id, key, 'reconciliations.propose', original as unknown as Record<string, unknown>) : null;
    const requestId = await canonicalRequestId(principalId, key);
    const digest = webcrypto.subtle.digest.bind(webcrypto.subtle);
    let current = true;
    const request = vi.fn(async (path: string, options?: {method?: string; body?: Record<string, unknown>; idempotencyKey?: string}) => {
      if (path === `operations/requests/${key}`) return {contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found'};
      expect(options).toEqual({method: 'POST', body: original.body, idempotencyKey: key});
      vi.spyOn(webcrypto.subtle, 'digest').mockImplementationOnce(digest).mockImplementationOnce(async (algorithm, data) => {
        current = false;
        return digest(algorithm, data);
      });
      return {...fixture.proposal_receipt, request_id: requestId};
    });
    try {
      const result = pending
        ? retryFinancialAttempt(access(request), identity, pending, true, async () => true, () => current, async () => true, lock)
        : submitFinancialAttempt(access(request), identity, original, key, true, async () => true, () => current, async () => true, lock);
      await expect(result).rejects.toMatchObject({possiblySubmitted: true});
      expect(await readPending(identity, RECONCILIATION_FAMILY, id)).toMatchObject({request_key: key, intent: original});
      expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
    } finally { vi.restoreAllMocks(); }
  });

  it('matches the retained intent again before clearing a request with a verified receipt', async () => {
    const original = prepareProposal(snapshot(), member(), 'Reviewed the recorded member', permissions);
    const revised = {...original, body: {...original.body, reason: 'A later review of the same evidence'}};
    const pending = await retainPending(identity, RECONCILIATION_FAMILY, id, key, 'reconciliations.propose', original as unknown as Record<string, unknown>);
    const requestId = await canonicalRequestId(principalId, key);
    const request = vi.fn(async () => {
      await clearPending(identity, RECONCILIATION_FAMILY, id, key);
      await retainPending(identity, RECONCILIATION_FAMILY, id, key, pending.permission, revised as unknown as Record<string, unknown>);
      return {contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded',
        request_id: requestId, receipt: {...fixture.proposal_receipt, request_id: requestId}};
    });
    await expect(lookupFinancialAttempt(access(request), identity, pending, () => true)).rejects.toThrow();
    expect(await readPending(identity, RECONCILIATION_FAMILY, id)).toMatchObject({request_key: key, intent: revised});
  });
});
