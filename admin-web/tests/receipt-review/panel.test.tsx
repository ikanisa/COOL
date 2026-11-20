import {fireEvent, render, screen, within} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {retainPending, sha256Text} from '../../src/features/core/pendingAttempt';
import type {MemberReceipt} from '../../src/features/operations/contracts';

const mock = vi.hoisted(() => ({request: vi.fn(), epoch: 1, user: {id: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.test', role: 'admin' as const, permissions: ['payments.read', 'payments.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'transaction_journals' as const}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: mock.epoch, status: 'authenticated', request: mock.request, isCurrentAuthority: () => true})}));
import {ReceiptReviewPanel} from '../../src/features/receipt-review';

const id = '11111111-1111-4111-8111-111111111111', key = '33333333-3333-4333-8333-333333333333', operation = '44444444-4444-4444-8444-444444444444', reviewId = '88888888-8888-4888-8888-888888888888';
const hash = 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9', time = '2026-10-18T08:00:00.000Z', why = 'Check this submitted receipt';
const receipt: MemberReceipt = {id, user_id: mock.user.id, body_sha256: hash, status: 'needs_review', version: 1, received_at: time, created_at: time, public_id: '123456', display_name: 'Synthetic member', transaction_id: null, reviewed_at: null};
const source = {submission_id: id, raw_sender: 'MTN MoMo', raw_body: 'hello world', body_sha256: hash, evidence_level: 'member_submitted'};
const serverReceipt = {request_id: operation, resource_type: 'member_receipts', resource_id: id, version: 2, status: 'succeeded'};
function detail(reviewed = false) {return {resource_type: 'member_receipts', resource: reviewed ? {...receipt, status: 'reviewed', version: 2, reviewed_at: time} : receipt, current_actor_id: mock.user.id, can_manage: true, related_truncated: false, related: {reviews: reviewed ? [{id: reviewId, outcome: 'reviewed', transaction_id: null, evidence_id: null, actor_admin_id: mock.user.id, reason: why, reviewed_at: time}] : []}};}
const originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {mock.request.mockReset(); mock.epoch = 1; mock.user.permissions = ['payments.read', 'payments.manage', 'overview.read']; if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});
async function reveal() {
  const user = userEvent.setup();
  await user.type(await screen.findByLabelText('Reason to review the submitted receipt'), 'Review the submitted receipt');
  await user.click(screen.getByRole('button', {name: 'Review receipt access'}));
  expect(screen.getByRole('button', {name: 'View submitted receipt'})).toBeDisabled();
  expect(mock.request).not.toHaveBeenCalledWith(expect.stringContaining('/content'), expect.anything());
  await user.click(screen.getByRole('checkbox', {name: 'I confirm this receipt review.'})); await user.click(screen.getByRole('button', {name: 'View submitted receipt'}));
  expect(await screen.findByText('hello world')).toBeVisible(); return user;
}

describe('Combined receipt access and review panel', () => {
  it('offers neither reveal nor new writes by default', async () => {
    render(<ReceiptReviewPanel receipt={receipt} canManage onUpdated={() => undefined} />);
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(screen.queryByRole('button', {name: 'Review receipt access'})).not.toBeInTheDocument(); expect(mock.request).not.toHaveBeenCalled();
  });
  it('preserves audited reveal without history permission and removes plaintext on gate or session change', async () => {
    mock.user.permissions = ['payments.read', 'payments.manage']; mock.request.mockResolvedValue(source);
    const view = render(<ReceiptReviewPanel receipt={receipt} canManage enabled onUpdated={() => undefined} />);
    await reveal();
    expect(screen.getByText(/cannot check original requests/)).toBeVisible(); expect(screen.queryByLabelText('Reason for review')).not.toBeInTheDocument();
    expect(JSON.stringify(sessionStorage)).not.toContain('hello world'); expect(JSON.stringify(localStorage)).not.toContain('hello world');
    mock.epoch = 2; view.rerender(<ReceiptReviewPanel receipt={receipt} canManage enabled onUpdated={() => undefined} />);
    expect(screen.queryByText('hello world')).not.toBeInTheDocument();
    view.rerender(<ReceiptReviewPanel receipt={receipt} canManage enabled={false} onUpdated={() => undefined} />);
    expect(screen.queryByRole('button', {name: 'Review receipt access'})).not.toBeInTheDocument();
  });
  it('requires two explicit confirmations and verifies a classification before reporting success', async () => {
    const updated = vi.fn(); let posted = false;
    mock.request.mockImplementation(async (path: string, options?: {method?: string; body?: unknown}) => {
      if (path.endsWith('/content')) return source;
      if (path.includes('operations/requests/')) return {status: 'succeeded', request_id: operation, receipt: serverReceipt};
      if (path.endsWith('/review')) {posted = true; expect(options?.body).toEqual({expected_version: 1, outcome: 'reviewed', transaction_id: null, reason: why}); return serverReceipt;}
      return detail(posted);
    });
    render(<ReceiptReviewPanel receipt={receipt} canManage enabled onUpdated={updated} />);
    const user = await reveal();
    await user.type(await screen.findByLabelText('Reason for review'), why);
    expect(screen.queryByLabelText('Search eligible transactions')).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', {name: 'Review classification'}));
    expect(screen.getByRole('button', {name: 'Confirm review'})).toBeDisabled();
    expect(mock.request.mock.calls.some(call => String(call[0]).endsWith('/review'))).toBe(false);
    fireEvent.change(screen.getByLabelText('Reason for review'), {target: {value: 'Changed after the confirmation opened'}});
    expect(within(screen.getByRole('dialog')).getByText(why)).toBeVisible();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the receipt and classification.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm review'}));
    expect(await screen.findByText(`Receipt review recorded. Request ${operation}.`)).toBeVisible(); expect(updated).toHaveBeenCalledOnce();
    expect(screen.queryByText('hello world')).not.toBeInTheDocument(); expect(JSON.stringify(sessionStorage)).not.toContain('hello world');
  });
  it('checks the original key with writes off and requires a new reveal and explicit identical retry after opt-in', async () => {
    await retainPending(mock.user, 'member-receipt-review-v2', id, key, 'payments.manage', {model: 'transaction_journals', expected_version: 1, outcome: 'reviewed', transaction_id: null, expected_transaction_version: null, source_sha256: hash, source_user_id: mock.user.id, reason_sha256: await sha256Text(why), transaction_sha256: null});
    let posted = false;
    mock.request.mockImplementation(async (path: string, options?: {idempotencyKey?: string}) => {
      if (path.includes('operations/requests/')) return posted ? {status: 'succeeded', request_id: operation, receipt: serverReceipt} : {status: 'not_found'};
      if (path.endsWith('/content')) return source;
      if (path.endsWith('/review')) {expect(options?.idempotencyKey).toBe(key); posted = true; return serverReceipt;}
      return detail(posted);
    });
    const user = userEvent.setup(), view = render(<ReceiptReviewPanel receipt={receipt} canManage onUpdated={() => undefined} />);
    await user.click(await screen.findByRole('button', {name: 'Check original review'}));
    expect(await screen.findByText(/No server receipt was found/)).toBeVisible(); expect(screen.queryByRole('button', {name: 'Review receipt access'})).not.toBeInTheDocument();
    view.rerender(<ReceiptReviewPanel receipt={receipt} canManage enabled onUpdated={() => undefined} />);
    await user.click(await screen.findByRole('button', {name: 'Check original review'}));
    await screen.findByText(/No server receipt was found/);
    // The helper checks for no earlier source call, while the prior lookup is safe and read-only.
    await reveal();
    await user.type(await screen.findByLabelText('Exact original review reason'), why);
    await user.click(screen.getByRole('button', {name: 'Review identical retry'}));
    expect(screen.getByRole('button', {name: 'Confirm identical retry'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the receipt and classification.'})); await user.click(screen.getByRole('button', {name: 'Confirm identical retry'}));
    expect(await screen.findByText(`Receipt review recorded. Request ${operation}.`)).toBeVisible();
  });
  it('presents attachment only with the separate gate and sends the selected reviewed version', async () => {
    const tx = {id: '55555555-5555-4555-8555-555555555555', label: 'TEST-REF · RWF 2400 · Fixture group', version: 9, amount_rwf: 2400, group_id: '66666666-6666-4666-8666-666666666666', group_name: 'Fixture group', provider_reference: 'TEST-REF'};
    let posted = false;
    mock.request.mockImplementation(async (path: string, options?: {body?: unknown}) => {
      if (path.endsWith('/content')) return source;
      if (path.includes('operations/requests/')) return {status: 'succeeded', request_id: operation, receipt: serverReceipt};
      if (path.includes('/transactions?')) return {rows: [tx]};
      if (path.endsWith('/review')) {expect(options?.body).toEqual({expected_version: 1, outcome: 'reviewed', transaction_id: tx.id, expected_transaction_version: 9, reason: why}); posted = true; return serverReceipt;}
      const value = detail(posted);
      return posted ? {...value, resource: {...value.resource, transaction_id: tx.id}, related: {reviews: value.related.reviews.map(row => ({...row, transaction_id: tx.id, evidence_id: '77777777-7777-4777-8777-777777777777'}))}} : value;
    });
    render(<ReceiptReviewPanel receipt={receipt} canManage enabled allowAttachment onUpdated={() => undefined} />);
    const user = await reveal();
    await user.type(await screen.findByLabelText('Search eligible transactions'), 'TEST-REF'); await user.click(screen.getByRole('button', {name: 'Search transactions'}));
    await user.click(await screen.findByLabelText(/TEST-REF · RWF 2400 · Fixture group/));
    await user.type(screen.getByLabelText('Reason for review'), why); await user.click(screen.getByRole('button', {name: 'Review classification'}));
    expect(within(screen.getByRole('dialog')).getByText(/version 9/)).toBeVisible(); await user.click(screen.getByRole('checkbox', {name: 'I reviewed the receipt and classification.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm review'}));
    expect(await screen.findByText(`Receipt review recorded. Request ${operation}.`)).toBeVisible();
  });
});
