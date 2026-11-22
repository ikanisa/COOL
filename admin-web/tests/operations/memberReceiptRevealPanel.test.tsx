import {render, screen} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach, describe, expect, it, vi} from 'vitest';
import type {MemberReceipt} from '../../src/features/operations/contracts';

const mock = vi.hoisted(() => ({request: vi.fn(), epoch: 1, user: {id: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.test', role: 'admin' as const, permissions: ['payments.read', 'payments.manage'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'transaction_journals' as const}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: mock.epoch, status: 'authenticated', request: mock.request, isCurrentAuthority: () => true})}));
import {MemberReceiptRevealPanel} from '../../src/features/operations/MemberReceiptRevealPanel';
const id = '11111111-1111-4111-8111-111111111111', hash = 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
const receipt: MemberReceipt = {id, user_id: mock.user.id, body_sha256: hash, status: 'needs_review', version: 1, received_at: '2026-10-18T08:00:00.000Z', created_at: '2026-10-18T08:00:00.000Z', public_id: '123456', display_name: 'Synthetic member', transaction_id: null, reviewed_at: null};
const response = {submission_id: id, raw_sender: 'MTN MoMo', raw_body: 'hello world', body_sha256: hash, evidence_level: 'member_submitted'};
afterEach(() => {mock.request.mockReset(); mock.epoch = 1;});

async function review() {
  const user = userEvent.setup(); await user.type(screen.getByLabelText('Reason to review the submitted receipt'), 'Review the submitted receipt');
  await user.click(screen.getByRole('button', {name: 'Review receipt access'}));
  expect(screen.getByRole('button', {name: 'View submitted receipt'})).toBeDisabled(); expect(mock.request).not.toHaveBeenCalled();
  await user.click(screen.getByRole('checkbox', {name: 'I confirm this receipt review.'})); await user.click(screen.getByRole('button', {name: 'View submitted receipt'})); return user;
}
describe('Member receipt access panel', () => {
  it('does not expose the access action by default or for a read-only account', () => {
    const view = render(<MemberReceiptRevealPanel receipt={receipt} canManage />);
    expect(screen.queryByRole('button', {name: 'Review receipt access'})).not.toBeInTheDocument();
    view.rerender(<MemberReceiptRevealPanel receipt={receipt} canManage={false} enabled />);
    expect(screen.queryByRole('button', {name: 'Review receipt access'})).not.toBeInTheDocument(); expect(mock.request).not.toHaveBeenCalled();
  });
  it('requires confirmation and removes revealed text when the gate or session changes', async () => {
    mock.request.mockResolvedValue(response);
    const view = render(<MemberReceiptRevealPanel receipt={receipt} canManage enabled />); await review();
    expect(await screen.findByText('hello world')).toBeVisible(); expect(mock.request).toHaveBeenCalledOnce();
    mock.epoch = 2; view.rerender(<MemberReceiptRevealPanel receipt={receipt} canManage enabled />); expect(screen.queryByText('hello world')).not.toBeInTheDocument();
    view.rerender(<MemberReceiptRevealPanel receipt={receipt} canManage enabled={false} />); expect(screen.queryByRole('button', {name: 'Review receipt access'})).not.toBeInTheDocument();
  });
  it('reports an unconfirmed access without repeating the audited request', async () => {
    mock.request.mockRejectedValue(new Error('lost reply')); render(<MemberReceiptRevealPanel receipt={receipt} canManage enabled />); await review();
    expect(await screen.findByText(/An access event may have been recorded/)).toBeVisible(); expect(mock.request).toHaveBeenCalledOnce();
    expect(screen.queryByText('hello world')).not.toBeInTheDocument();
  });
});
