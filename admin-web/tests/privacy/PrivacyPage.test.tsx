import {render, screen, waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {describe, expect, it, vi} from 'vitest';
import type {AdminRequest} from '../../src/api/client';
import type {AdminUser} from '../../src/session/SessionProvider';
import {PrivacyPage} from '../../src/features/privacy/PrivacyPage';

const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const sessionId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const principalId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const flags = {policy_acceptance_granted: false, destructive_execution_available: false, erasure_completed: false,
  account_access_restricted: false, auth_removed: false, processor_operation_started: false};

describe('privacy review page', () => {
  it('requires fresh proof, then loads only the protected read operations and detail', async () => {
    const now = Date.now(), iso = (value: number) => new Date(value).toISOString();
    const user: AdminUser = {id, email: 'owner@example.test', role: 'owner', sessionId, principalId,
      expiresAt: iso(now + 600_000), permissions: ['privacy.review'], assuranceLevel: 2, mfaAt: iso(now - 10_000),
      emailVerifiedAt: null, financialModel: 'canonical_evidence_ledger'};
    const item = {request_id: id, accepted_at: iso(now - 60_000), revision: 0, review_state: 'awaiting_review', claim_expires_at: null, outcome_code: null, outcome_recorded_at: null};
    const envelope = {contract_version: 1, scope: 'account_privacy_review_only', checked_at: iso(now - 1000),
      completion: 'blocked', blocking_reason: 'policy_authority_unavailable', ...flags};
    const operation = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
    const key = `collect.privacy-review.v1.${principalId}.${sessionId}`;
    const checkpoint = JSON.stringify({version: 1, generation: 1, actor_id: principalId, session_id: sessionId, pending: {kind: 'claim',
      operation_id: operation, actor_id: principalId, session_id: sessionId, request_id: id, parameters: {p_request_id: id,
        p_claim_request_id: operation, p_expected_revision: 0, p_lease_seconds: 60}}});
    localStorage.setItem(key, checkpoint);
    const request = vi.fn<AdminRequest>(async path => {
      if (path.endsWith('retention_context_v1')) return {contract_version: 1, scope: 'account_retention_inspection_context', source_id: 'a'.repeat(64), checked_at: iso(now - 1000), valid_until: iso(now + 60_000), approval_granted: false, erasure_completed: false};
      if (path.endsWith('deletion_reviews_v1')) return {...envelope, items: [item], limit: 25, next_cursor: null};
      if (path === 'privacy/admin_get_account_deletion_review_v1') return {...envelope, item, own_claim_receipt: null, own_outcome_receipt: null, own_claim_authority_current: false};
      if (path.endsWith('retention_scope_v1')) return {contract_version: 1, request_id: id, subject_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', source_id: 'a'.repeat(64), schema_sha256: 'b'.repeat(64), snapshot_sha256: 'c'.repeat(64), table_counts: {payments: 2}, object_count: 0, active_hold_count: 1, in_flight_unresolved: true, approval_granted: false, erasure_completed: false};
      if (path.endsWith('review_operation_v1')) return {...envelope, operation_kind: 'claim', operation_id: operation, observed: false, receipt: null, claim_authority_current: false};
      throw new Error('Unexpected request');
    });
    const props = {user, epoch: 1, verificationMode: 'authenticator' as const, request, verifyFresh: vi.fn().mockResolvedValue(true),
      isCurrentAuthority: () => true, onVerify: vi.fn()};
    const view = render(<PrivacyPage {...props} />);
    await userEvent.click(await screen.findByRole('button', {name: 'Open privacy reviews'}));
    await userEvent.click(await screen.findByRole('button', {name: 'Check original operation'}));
    await screen.findByText(/does not prove the original operation failed/i);
    await userEvent.click(await screen.findByRole('button', {name: 'Open request'}));
    await screen.findByRole('heading', {name: 'Request details'});
    expect(screen.queryByRole('button', {name: 'Start review'})).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', {name: 'Inspect retained scope'}));
    await screen.findByText('Active legal holds');
    expect(request.mock.calls.map(([path]) => path)).toEqual(['privacy/admin_get_account_retention_context_v1',
      'privacy/admin_list_account_deletion_reviews_v1', 'privacy/admin_get_account_deletion_review_operation_v1',
      'privacy/admin_get_account_deletion_review_v1', 'privacy/admin_inspect_account_retention_scope_v1']);
    expect(localStorage.getItem(key)).toBe(checkpoint);
    expect(screen.getByText(/Reviews do not delete accounts or data/)).toBeInTheDocument();
    view.rerender(<PrivacyPage {...props} user={{...user, mfaAt: null, assuranceLevel: 1}} />);
    await waitFor(() => expect(screen.queryByRole('heading', {name: 'Request details'})).not.toBeInTheDocument());
    localStorage.removeItem(key);
  });

  it('never reads the queue without fresh verification', async () => {
    const now = Date.now();
    const user: AdminUser = {id, email: 'owner@example.test', role: 'owner', sessionId, principalId,
      expiresAt: new Date(now + 600_000).toISOString(), permissions: ['privacy.review'], assuranceLevel: 1, mfaAt: null,
      emailVerifiedAt: null, financialModel: 'canonical_evidence_ledger'};
    const request = vi.fn<AdminRequest>();
    render(<PrivacyPage user={user} epoch={1} verificationMode="email" request={request} verifyFresh={async () => false}
      isCurrentAuthority={() => true} onVerify={() => undefined} />);
    expect(screen.getByRole('button', {name: 'Verify account'})).toBeInTheDocument();
    expect(request).not.toHaveBeenCalled();
  });

  it('requires both proofs when the server policy requires an authenticator', async () => {
    const now = Date.now(), iso = (value: number) => new Date(value).toISOString();
    const user: AdminUser = {id, email: 'owner@example.test', role: 'owner', sessionId, principalId,
      expiresAt: iso(now + 600_000), permissions: ['privacy.review'], assuranceLevel: 2, mfaAt: iso(now - 301_000),
      emailVerifiedAt: iso(now - 1_000), mfaRequired: true, financialModel: 'canonical_evidence_ledger'};
    const request = vi.fn<AdminRequest>();
    render(<PrivacyPage user={user} epoch={1} verificationMode="email" request={request} verifyFresh={async () => true}
      isCurrentAuthority={() => true} onVerify={() => undefined} />);
    expect(await screen.findByRole('button', {name: 'Verify account'})).toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Open privacy reviews'})).not.toBeInTheDocument();
    expect(request).not.toHaveBeenCalled();
  });

  it('retains an unconfirmed review and checks its original operation without replay', async () => {
    const now = Date.now(), iso = (value: number) => new Date(value).toISOString();
    const user: AdminUser = {id, email: 'owner@example.test', role: 'owner', sessionId, principalId,
      expiresAt: iso(now + 600_000), permissions: ['privacy.review'], assuranceLevel: 2, mfaAt: iso(now - 10_000),
      emailVerifiedAt: null, financialModel: 'canonical_evidence_ledger'};
    const item = {request_id: id, accepted_at: iso(now - 60_000), revision: 0, review_state: 'awaiting_review', claim_expires_at: null, outcome_code: null, outcome_recorded_at: null};
    const envelope = {contract_version: 1, scope: 'account_privacy_review_only', checked_at: iso(now - 1000),
      completion: 'blocked', blocking_reason: 'policy_authority_unavailable', ...flags};
    const key = `collect.privacy-review.v1.${principalId}.${sessionId}`;
    localStorage.removeItem(key);
    const priorLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
    Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (_name: string, _options: unknown, work: (lock: object) => Promise<unknown>) => work({})}});
    let attempts = 0;
    const request = vi.fn<AdminRequest>(async (path, options) => {
      if (path.endsWith('retention_context_v1')) return {contract_version: 1, scope: 'account_retention_inspection_context', source_id: 'a'.repeat(64), checked_at: iso(now - 1000), valid_until: iso(now + 60_000), approval_granted: false, erasure_completed: false};
      if (path.endsWith('deletion_reviews_v1')) return {...envelope, items: [item], limit: 25, next_cursor: null};
      if (path === 'privacy/admin_get_account_deletion_review_v1') return {...envelope, item, own_claim_receipt: null, own_outcome_receipt: null, own_claim_authority_current: false};
      if (path.endsWith('claim_account_deletion_review_v1')) {
        if (++attempts === 1) throw new Error('Synthetic lost response');
        return {contract_version: 1, scope: 'account_privacy_review_only', request_id: id, claim_request_id: options?.body?.p_claim_request_id,
          claim_id: 'ffffffff-ffff-4fff-8fff-ffffffffffff', revision: 1, fence: 1, claimed_at: iso(now - 1000), expires_at: iso(now + 59_000),
          policy_acceptance_granted: false, destructive_execution_available: false, erasure_completed: false};
      }
      if (path.endsWith('review_operation_v1')) return {...envelope, operation_kind: 'claim', operation_id: options?.body?.p_operation_id,
        observed: false, receipt: null, claim_authority_current: false};
      throw new Error('Unexpected request');
    });
    try {
      render(<PrivacyPage user={user} epoch={1} verificationMode="authenticator" request={request} verifyFresh={async () => true}
        isCurrentAuthority={() => true} onVerify={() => undefined} allowActions />);
      await userEvent.click(await screen.findByRole('button', {name: 'Open privacy reviews'}));
      await userEvent.click(await screen.findByRole('button', {name: 'Open request'}));
      await userEvent.click(await screen.findByRole('button', {name: 'Start review'}));
      await userEvent.click(screen.getByRole('button', {name: 'Confirm review action'}));
      await screen.findByRole('button', {name: 'Check original operation'});
      const original = localStorage.getItem(key);
      expect(original).toContain('claim_request_id');
      await userEvent.click(screen.getByRole('button', {name: 'Check original operation'}));
      await screen.findByText(/does not prove the original operation failed/i);
      expect(localStorage.getItem(key)).toBe(original);
      expect(request.mock.calls.filter(([path]) => path.endsWith('claim_account_deletion_review_v1'))).toHaveLength(1);
      await userEvent.click(screen.getByRole('button', {name: 'Review same operation'}));
      await userEvent.click(await screen.findByRole('button', {name: 'Confirm same operation'}));
      await screen.findByText(/Review start recorded/);
      const sends = request.mock.calls.filter(([path]) => path.endsWith('claim_account_deletion_review_v1'));
      expect(sends).toHaveLength(2);
      expect(sends[1][1]?.body).toEqual(sends[0][1]?.body);
      expect(JSON.parse(localStorage.getItem(key)!).pending).toBeNull();
    } finally {
      localStorage.removeItem(key);
      if (priorLocks) Object.defineProperty(navigator, 'locks', priorLocks); else Reflect.deleteProperty(navigator, 'locks');
    }
  });
});
