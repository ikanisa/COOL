import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { retainPending } from '../../src/features/core/pendingAttempt';
import { parseMomoDetail } from '../../src/features/operations/momoContracts';
import { restoreMomoConflict, submitMomoConflict, type MomoConflictContext } from '../../src/features/operations/momoConflict';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {id: '22222222-2222-4222-8222-222222222222', principalId: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.com', role: 'admin' as const, permissions: ['payments.read', 'payments.write', 'sms.extract'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'canonical_evidence_ledger' as const, assuranceLevel: 2 as const, mfaAt: new Date().toISOString()}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request, verificationMode: 'authenticator', isCurrentAuthority: () => true, recheckSensitiveEmailVerification: async () => false})}));
import { MomoConflictReviewPanel } from '../../src/features/operations/MomoConflictReviewPanel';

const txId = '11111111-1111-4111-8111-111111111111', account = '33333333-3333-4333-8333-333333333333', original = '44444444-4444-4444-8444-444444444444', conflict = '55555555-5555-4555-8555-555555555555', raw1 = '66666666-6666-4666-8666-666666666666', key = '77777777-7777-4777-8777-777777777777', raw2 = '88888888-8888-4888-8888-888888888888';
const time = '2026-10-18T08:00:00.000Z', originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
const tx = {id: txId, receiving_account_id: account, provider_transaction_id: 'MOMO-SYNTHETIC-001', recipient_name: 'Synthetic receiver', public_code: '123456', payer_name: 'Synthetic payer', payer_last3: '007', member_name: null, group_name: null, group_id: null, beneficiary_member_id: null, payment_id: null, amount_minor: 5000, has_conflict: 1, credited_amount_minor: 0, version: 1, currency: 'RWF', status: 'needs_review', event_kind: 'incoming_receipt', allocation_state: 'needs_review', transaction_at: time, created_at: time};
const accepted = {raw_sms_id: raw1, attempt_id: original, relation: 'accepted', outcome: 'accepted', parser_version: 'v1', created_at: time};
const contradictory = {raw_sms_id: raw2, attempt_id: conflict, relation: 'conflict', outcome: 'conflict', parser_version: 'v1', created_at: time};
const rawDetail = {transaction: tx, sources: [accepted, contradictory], conflicting_attempt_ids: [conflict]}, detail = parseMomoDetail(rawDetail, txId);
const intent = {expected_version: 1, expected_conflicting_attempt_ids: [conflict], decision: 'retain_original', evidence_reference: 'Support evidence 123', reason: 'Reviewed source evidence'};
const receipt = {transaction_id: txId, version: 2, status: 'needs_allocation', financial_effects: 0};
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); mock.user.permissions = ['payments.read', 'payments.write', 'sms.extract']; Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {mock.request.mockReset(); if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('MoMo conflict review panel', () => {
  it('exposes no conflict write while the gate is closed or a required permission is missing', async () => {
    const {unmount} = render(<MemoryRouter><MomoConflictReviewPanel detail={detail} onUpdated={() => {}} /></MemoryRouter>);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(screen.queryByRole('button', {name: 'Review conflict decision'})).not.toBeInTheDocument();
    unmount(); mock.user.permissions = ['payments.read', 'payments.write'];
    render(<MemoryRouter><MomoConflictReviewPanel detail={detail} enabled onUpdated={() => {}} /></MemoryRouter>);
    expect(screen.queryByRole('button', {name: 'Review conflict decision'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('requires source review, supporting evidence, explicit confirmation and fresh verification', async () => {
    const user = userEvent.setup();
    mock.request.mockImplementation(async (_path: string, options?: {method?: string}) => options?.method === 'POST' ? receipt : rawDetail);
    render(<MemoryRouter><MomoConflictReviewPanel detail={detail} enabled onUpdated={() => {}} /></MemoryRouter>);
    expect(await screen.findByText(/Accepted source:/)).toBeVisible();
    const table = screen.getByRole('table');
    expect(within(table).getByText(conflict)).toBeVisible();
    expect(within(table).getByText(raw2)).toBeVisible();
    await user.type(screen.getByLabelText('Supporting evidence reference'), intent.evidence_reference);
    await user.type(screen.getByLabelText('Reason for conflict decision'), intent.reason);
    await user.click(screen.getByRole('button', {name: 'Review conflict decision'}));
    const review = screen.getByRole('region', {name: 'Reviewed conflict decision'});
    expect(within(review).getByRole('button', {name: 'Confirm conflict decision'})).toBeDisabled();
    expect(mock.request).not.toHaveBeenCalled();
    await user.click(within(review).getByRole('checkbox', {name: 'I reviewed the accepted source, every conflicting attempt and the supporting evidence.'}));
    await user.click(within(review).getByRole('button', {name: 'Confirm conflict decision'}));
    expect(await screen.findByText('Conflict review recorded. No contribution was credited and provider settlement is not asserted.')).toBeVisible();
    expect(mock.request).toHaveBeenCalledTimes(2);
    expect(mock.request).toHaveBeenNthCalledWith(2, `momo/transactions/${txId}/review-conflict`, expect.objectContaining({method: 'POST', body: intent}));
  });
  it('does not offer review when source rows are incomplete', async () => {
    const truncated = parseMomoDetail({...rawDetail, sources: [accepted]}, txId);
    render(<MemoryRouter><MomoConflictReviewPanel detail={truncated} enabled onUpdated={() => {}} /></MemoryRouter>);
    expect(await screen.findByText(/complete unlinked conflict and its source evidence are unavailable/)).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review conflict decision'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('shows an older original reference without fabricating a lookup or exposing a retry when writes are off', async () => {
    await retainPending(mock.user, 'momo-review-conflict', txId, key, 'payments.write', intent);
    render(<MemoryRouter><MomoConflictReviewPanel detail={detail} onUpdated={() => {}} /></MemoryRouter>);
    expect(await screen.findByText(key)).toBeVisible();
    expect(screen.getByText(/There is no read-only status lookup/)).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review original conflict request'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('requires explicit review before retrying the identical pending request', async () => {
    const user = userEvent.setup(), previousRequest = vi.fn().mockResolvedValueOnce(rawDetail).mockRejectedValueOnce(new Error('lost'));
    const previous: MomoConflictContext = {request: previousRequest, identity: mock.user, principalId: mock.user.principalId, financialModel: 'canonical_evidence_ledger', detail, enabled: true, isCurrent: () => true, verifyFresh: async () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};
    const observed = await restoreMomoConflict(previous); if (observed.kind !== 'ready') throw new Error('Expected ready');
    expect((await submitMomoConflict(previous, intent.evidence_reference, intent.reason, observed.revision)).status).toBe('unknown');
    const after = {...rawDetail, transaction: {...tx, status: 'needs_allocation', has_conflict: 0, version: 2, allocation_state: 'unallocated'}};
    mock.request.mockResolvedValueOnce(after).mockResolvedValueOnce(receipt);
    render(<MemoryRouter><MomoConflictReviewPanel detail={parseMomoDetail(after, txId)} enabled onUpdated={() => {}} /></MemoryRouter>);
    await user.click(await screen.findByRole('button', {name: 'Review original conflict request'}));
    const review = screen.getByRole('region', {name: 'Reviewed conflict decision'});
    expect(within(review).getByText(/Retrying may record this review/)).toBeVisible();
    expect(within(review).getByRole('button', {name: 'Retry original conflict request'})).toBeDisabled();
    expect(mock.request).not.toHaveBeenCalled();
    await user.click(within(review).getByRole('checkbox', {name: 'I reviewed the accepted source, every conflicting attempt and the supporting evidence.'}));
    await user.click(within(review).getByRole('button', {name: 'Retry original conflict request'}));
    expect(await screen.findByText('Conflict review recorded. No contribution was credited and provider settlement is not asserted.')).toBeVisible();
    expect(mock.request).toHaveBeenNthCalledWith(2, `momo/transactions/${txId}/review-conflict`, {method: 'POST', body: intent, idempotencyKey: key});
  });
});
