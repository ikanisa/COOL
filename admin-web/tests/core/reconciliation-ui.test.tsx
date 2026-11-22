import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import fixture from './canonical-reconciliation-fixture.json';
import { canonicalRequestId, PENDING_KEY, retainPending } from '../../src/features/core/pendingAttempt';
import type { PendingIdentity } from '../../src/features/core/pendingAttempt';
import type { FeatureAccess } from '../../src/features/core/types';
import { parseReconciliationDetail } from '../../src/features/reconciliation/contracts';
import { CanonicalReconciliationActions } from '../../src/features/reconciliation/CanonicalActions';
import { ReconciliationDetailPage } from '../../src/features/reconciliation/ReconciliationPages';
import { parseReconciliationMembers, prepareProposal, RECONCILIATION_FAMILY } from '../../src/features/reconciliation/actions';

const permissions = ['users.read', 'ledger.read', 'account.manage', 'reconciliations.read', 'reconciliations.propose', 'reconciliations.review'];
const actorId = fixture.detail.current_actor_id, principalId = fixture.detail.current_principal_id, id = fixture.detail.resource.id;
const identity: PendingIdentity = { id: actorId, sessionId: 'synthetic-session', email: 'operator@example.test', role: 'admin', permissions, expiresAt: '2100-01-01T00:00:00.000Z' };
const detail = () => parseReconciliationDetail(fixture.detail, 'canonical_evidence_ledger', id, actorId, principalId, permissions, 'admin');

beforeEach(() => {
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
  Object.defineProperty(navigator, 'locks', { value: { request: async (_name: string, _options: unknown, callback: (lock: object) => unknown) => callback({}) }, configurable: true });
  sessionStorage.clear();
});

describe('reconciliation action review', () => {
  it('loads managed text principals and checks the original request from the read-only detail route', async () => {
    const managedPrincipal = 'collect-admin-principal-a';
    const key = '44444444-4444-4444-8444-444444444444';
    const data = structuredClone(fixture.detail);
    data.current_principal_id = managedPrincipal;
    data.related.proposals.rows[0].proposed_by_principal_id = 'collect-admin-principal-b';
    const intent = prepareProposal(detail(), parseReconciliationMembers(fixture.members, detail(), 25, 0).rows[0], 'Review the recorded member identity', permissions);
    await retainPending(identity, RECONCILIATION_FAMILY, id, key, 'reconciliations.propose', intent as unknown as Record<string, unknown>);
    const requestId = await canonicalRequestId(managedPrincipal, key);
    const request = vi.fn(async (path: string, options?: {method?: string}) => {
      expect(options?.method).toBeUndefined();
      if (path.startsWith(`reconciliations/${id}?`)) return data;
      if (path === `operations/requests/${key}`) return {contract_version: 2, model: 'canonical_evidence_ledger', status: 'succeeded',
        request_id: requestId, receipt: {...fixture.proposal_receipt, request_id: requestId}};
      throw new Error('Unexpected request');
    });
    render(<ReconciliationDetailPage id={id} request={request} permissions={permissions} actorId={actorId} principalId={managedPrincipal}
      authorityKey="managed-session" financialModel="canonical_evidence_ledger" navigate={vi.fn()} role="admin" identity={identity} verifyFresh={async () => true} />);
    fireEvent.click(await screen.findByRole('button', {name: 'Check original request'}));
    await waitFor(() => expect(sessionStorage.getItem(PENDING_KEY)).toBeNull());
    expect(request.mock.calls.filter(([path]) => path.startsWith('operations/'))).toEqual([[`operations/requests/${key}`]]);
    expect(screen.queryByRole('button', {name: 'Review same request'})).not.toBeInTheDocument();
  });

  it('rechecks the selected member and retains the request before submission', async () => {
    const request = vi.fn(async (path: string, options?: { method?: string; idempotencyKey?: string }) => {
      if (path.startsWith('reconciliations/members?')) return fixture.members;
      if (path.startsWith(`reconciliations/${id}?`)) return fixture.detail;
      if (path === `reconciliations/${id}/proposals` && options?.method === 'POST') {
        expect(JSON.parse(sessionStorage.getItem(PENDING_KEY)!).entries[0].request_key).toBe(options.idempotencyKey);
        return { ...fixture.proposal_receipt, request_id: await canonicalRequestId(principalId, options.idempotencyKey!) };
      }
      throw new Error('Unexpected request');
    });
    const access: FeatureAccess = { request, permissions, actorId, principalId, role: 'admin', authorityKey: 'scope-1', financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
    const completed = vi.fn(), verifyFresh = vi.fn(async () => true);
    render(<CanonicalReconciliationActions detail={detail()} access={access} identity={identity} allowMutations verifyFresh={verifyFresh} onCompleted={completed} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Find members' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Select' }));
    fireEvent.change(screen.getByLabelText('Reason'), { target: { value: 'Review the recorded member identity' } });
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getByRole('button', { name: 'Review attribution' }));
    expect(screen.getByText('Recorded Member')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Confirm reviewed request' }));
    await waitFor(() => expect(completed).toHaveBeenCalledTimes(1));
    expect(verifyFresh).toHaveBeenCalled();
    expect(request.mock.calls.filter(([path]) => path.startsWith('reconciliations/members?'))).toHaveLength(2);
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });

  it('requires explicit same-request review after lookup and reuses the original key', async () => {
    const key = '44444444-4444-4444-8444-444444444444';
    const selected = parseReconciliationMembers(fixture.members, detail(), 25, 0).rows[0];
    const original = prepareProposal(detail(), selected, 'Review the recorded member identity', permissions);
    await retainPending(identity, RECONCILIATION_FAMILY, id, key, 'reconciliations.propose', original as unknown as Record<string, unknown>);
    const request = vi.fn(async (path: string, options?: { method?: string; idempotencyKey?: string }) => {
      if (path === `operations/requests/${key}`) return { contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found' };
      if (path.startsWith('reconciliations/members?')) return fixture.members;
      if (path.startsWith(`reconciliations/${id}?`)) return fixture.detail;
      if (path === `reconciliations/${id}/proposals` && options?.method === 'POST') {
        expect(options.idempotencyKey).toBe(key);
        return { ...fixture.proposal_receipt, request_id: await canonicalRequestId(principalId, key) };
      }
      throw new Error('Unexpected request');
    });
    const access: FeatureAccess = { request, permissions, actorId, principalId, role: 'admin', authorityKey: 'scope-1', financialModel: 'canonical_evidence_ledger', navigate: vi.fn() };
    const completed = vi.fn();
    render(<CanonicalReconciliationActions detail={detail()} access={access} identity={identity} allowMutations verifyFresh={async () => true} onCompleted={completed} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Check original request' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Review same request' }));
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getByRole('button', { name: 'Confirm same request' }));
    await waitFor(() => expect(completed).toHaveBeenCalledTimes(1));
    expect(request.mock.calls.filter(([path]) => path === `operations/requests/${key}`)).toHaveLength(2);
    expect(request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });
});
