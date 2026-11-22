import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { retainPending } from '../../src/features/core/pendingAttempt';
import { parseMomoDetail } from '../../src/features/operations/momoContracts';
import { restoreMomoAssignment, submitMomoAssignment, type MomoAssignmentContext } from '../../src/features/operations/momoAssignment';
import coreFixture from '../core/canonical-core-fixtures.json';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {id: '22222222-2222-4222-8222-222222222222', principalId: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.com', role: 'admin' as const, permissions: ['payments.read', 'payments.write', 'users.read', 'collections.read', 'reconciliations.read'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'canonical_evidence_ledger' as const, assuranceLevel: 2 as const, mfaAt: new Date().toISOString()}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request, verificationMode: 'authenticator', isCurrentAuthority: () => true, recheckSensitiveEmailVerification: async () => false})}));
import { MomoAssignmentPanel } from '../../src/features/operations/MomoAssignmentPanel';

const txId = '11111111-1111-4111-8111-111111111111', account = '33333333-3333-4333-8333-333333333333', group = '44444444-4444-4444-8444-444444444444', member = '55555555-5555-4555-8555-555555555555', sourceId = '66666666-6666-4666-8666-666666666666', key = '77777777-7777-4777-8777-777777777777', payment = '88888888-8888-4888-8888-888888888888';
const time = '2026-10-18T08:00:00.000Z', originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
const tx = {id: txId, receiving_account_id: account, provider_transaction_id: 'MOMO-SYNTHETIC-001', recipient_name: 'Synthetic receiver', public_code: '123456', payer_name: 'Synthetic payer', payer_last3: '007', member_name: null, group_name: null, group_id: null, beneficiary_member_id: null, payment_id: null, amount_minor: 5000, has_conflict: 0, credited_amount_minor: 0, version: 1, currency: 'RWF', status: 'needs_allocation', event_kind: 'incoming_receipt', allocation_state: 'unallocated', transaction_at: time, created_at: time};
const source = {raw_sms_id: sourceId, relation: 'accepted', outcome: 'accepted', parser_version: 'v1', created_at: time};
const rawDetail = {transaction: tx, sources: [source], conflicting_attempt_ids: []}, detail = parseMomoDetail(rawDetail, txId);
const candidate = {group_id: group, group_name: 'Synthetic group', member_id: member, member_name: 'Synthetic member', member_public_id: '123456'}, page = {rows: [candidate], total: 1, limit: 25, offset: 0};
const receipt = {transaction_id: txId, payment_id: payment, status: 'awaiting_review', version: 2, requires_independent_review: true};
const paymentReference = '100000000123';
const paymentDetail = {contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'transactions', current_actor_id: mock.user.id,
  resource: {...coreFixture.transactions.rows[0], id: payment, payment_reference: paymentReference}};
const intent = {group_id: group, member_id: member, expected_version: 1, reason: 'Review source attribution'};
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {mock.request.mockReset(); mock.user.sessionId = 'session-1'; mock.user.permissions = ['payments.read', 'payments.write', 'users.read', 'collections.read', 'reconciliations.read']; if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('MoMo assignment panel', () => {
  it('does not expose assignment while the gate is closed', async () => {
    render(<MemoryRouter><MomoAssignmentPanel detail={detail} onUpdated={() => {}} /></MemoryRouter>);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(screen.queryByRole('button', {name: 'Search destinations'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('requires a reviewed source, eligible destination, reason, confirmation and fresh verification', async () => {
    const user = userEvent.setup();
    mock.request.mockImplementation(async (path: string, options?: {method?: string}) => options?.method === 'POST' ? receipt : path === `operations/transactions/${payment}` ? paymentDetail : path.includes('/candidates?') ? page : rawDetail);
    const {rerender} = render(<MemoryRouter><MomoAssignmentPanel detail={detail} enabled onUpdated={() => {}} /></MemoryRouter>);
    expect(await screen.findByText(/Accepted source:/)).toBeVisible();
    await user.click(screen.getByRole('button', {name: 'Search destinations'}));
    const table = await screen.findByRole('table', {name: ''});
    expect(within(table).getByText('Synthetic member')).toBeVisible();
    await user.click(within(table).getByRole('button', {name: 'Select'}));
    await user.type(screen.getByLabelText('Reason for assignment'), intent.reason);
    await user.click(screen.getByRole('button', {name: 'Review assignment'}));
    const review = screen.getByRole('region', {name: 'Reviewed assignment'});
    expect(within(review).getByText('Synthetic group')).toBeVisible();
    expect(within(review).getByRole('button', {name: 'Confirm assignment'})).toBeDisabled();
    expect(mock.request).toHaveBeenCalledTimes(1);
    await user.click(within(review).getByRole('checkbox', {name: 'I reviewed the accepted source, destination and original request.'}));
    await user.click(within(review).getByRole('button', {name: 'Confirm assignment'}));
    expect(await screen.findByText('Assignment recorded for independent financial review. Provider settlement is not asserted.')).toBeVisible();
    expect(await screen.findByText(paymentReference)).toBeVisible();
    expect(screen.getByText(/Payment ID:/)).toHaveTextContent(payment);
    expect(screen.getByRole('link', {name: 'Open financial review'})).toHaveAttribute('href', `/admin/reconciliations/${payment}`);
    expect(mock.request).toHaveBeenCalledTimes(5);
    const originalPermissions = [...mock.user.permissions];
    mock.user.permissions = originalPermissions.filter(permission => permission !== 'reconciliations.read');
    rerender(<MemoryRouter><MomoAssignmentPanel detail={detail} enabled onUpdated={() => {}} /></MemoryRouter>);
    expect(screen.getByText(paymentReference)).toBeVisible();
    expect(screen.queryByRole('link', {name: 'Open financial review'})).not.toBeInTheDocument();
    mock.user.permissions = originalPermissions.filter(permission => permission !== 'payments.read');
    rerender(<MemoryRouter><MomoAssignmentPanel detail={detail} enabled onUpdated={() => {}} /></MemoryRouter>);
    expect(screen.queryByText(paymentReference)).not.toBeInTheDocument();
    expect(screen.queryByText(payment)).not.toBeInTheDocument();
    mock.user.permissions = originalPermissions;
    rerender(<MemoryRouter><MomoAssignmentPanel detail={detail} enabled onUpdated={() => {}} /></MemoryRouter>);
    expect(await screen.findByText(paymentReference)).toBeVisible();
    mock.user.sessionId = 'session-2';
    rerender(<MemoryRouter><MomoAssignmentPanel detail={detail} enabled onUpdated={() => {}} /></MemoryRouter>);
    expect(screen.queryByText(paymentReference)).not.toBeInTheDocument();
    expect(screen.queryByText(payment)).not.toBeInTheDocument();
  });
  it('shows the original reference without fabricating a lookup while writes are disabled', async () => {
    await retainPending(mock.user, 'momo-assign', txId, key, 'payments.write', intent);
    render(<MemoryRouter><MomoAssignmentPanel detail={detail} onUpdated={() => {}} /></MemoryRouter>);
    expect(await screen.findByText(key)).toBeVisible();
    expect(screen.getByText(/There is no read-only status lookup/)).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review original assignment'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it.each([
    ['an older server', {...paymentDetail, resource: {...coreFixture.transactions.rows[0], id: payment}}],
    ['another actor', {...paymentDetail, current_actor_id: '99999999-9999-4999-8999-999999999999'}],
    ['another payment', {...paymentDetail, resource: {...paymentDetail.resource, id: '99999999-9999-4999-8999-999999999999'}}],
    ['a malformed reference', {...paymentDetail, resource: {...paymentDetail.resource, payment_reference: 'not-a-reference'}}],
    ['a failed lookup', null],
  ])('requires explicit retry and does not invent a payment reference for %s', async (_label, readback) => {
    const user = userEvent.setup();
    const previousRequest = vi.fn().mockResolvedValueOnce(rawDetail).mockResolvedValueOnce(page).mockRejectedValueOnce(new Error('lost'));
    const previous: MomoAssignmentContext = {request: previousRequest, identity: mock.user, principalId: mock.user.principalId, financialModel: 'canonical_evidence_ledger', detail, enabled: true, isCurrent: () => true, verifyFresh: async () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};
    const observed = await restoreMomoAssignment(previous);
    if (observed.kind !== 'ready') throw new Error('Expected ready');
    expect((await submitMomoAssignment(previous, candidate, intent.reason, observed.revision)).status).toBe('unknown');
    const updated = parseMomoDetail({...rawDetail, transaction: {...tx, status: 'awaiting_review', payment_id: payment, version: 2, allocation_state: 'linked'}}, txId);
    mock.request.mockImplementation(async (_path: string, options?: {method?: string}) => {
      if (options?.method === 'POST') return receipt;
      if (readback === null) throw new Error('Payment detail unavailable');
      return readback;
    });
    render(<MemoryRouter><MomoAssignmentPanel detail={updated} enabled onUpdated={() => {}} /></MemoryRouter>);
    await user.click(await screen.findByRole('button', {name: 'Review original assignment'}));
    const review = screen.getByRole('region', {name: 'Reviewed assignment'});
    expect(within(review).getByText(/Retrying may make this assignment/)).toBeVisible();
    expect(within(review).getByRole('button', {name: 'Retry original assignment'})).toBeDisabled();
    expect(mock.request).not.toHaveBeenCalled();
    await user.click(within(review).getByRole('checkbox', {name: 'I reviewed the accepted source, destination and original request.'}));
    await user.click(within(review).getByRole('button', {name: 'Retry original assignment'}));
    expect(await screen.findByText('Assignment recorded for independent financial review. Provider settlement is not asserted.')).toBeVisible();
    await waitFor(() => expect(mock.request).toHaveBeenCalledTimes(2));
    expect(screen.getByText('Not available')).toBeVisible();
    expect(screen.getByText(/Payment ID:/)).toHaveTextContent(payment);
    expect(screen.queryByText(paymentReference)).not.toBeInTheDocument();
    expect(screen.getByRole('link', {name: 'Open financial review'})).toHaveAttribute('href', `/admin/reconciliations/${payment}`);
    expect(mock.request).toHaveBeenCalledWith(`momo/transactions/${txId}/assign`, {method: 'POST', body: intent, idempotencyKey: key});
  });
});
