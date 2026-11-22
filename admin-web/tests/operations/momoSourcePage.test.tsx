import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';
import { afterEach, expect, it, vi } from 'vitest';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {id: '22222222-2222-4222-8222-222222222222', principalId: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.com', role: 'admin' as const, permissions: ['payments.read', 'sms.read', 'sms.reveal'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'canonical_evidence_ledger' as const, assuranceLevel: 2 as const, mfaAt: new Date().toISOString()}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request, verificationMode: 'authenticator', isCurrentAuthority: () => true, recheckSensitiveEmailVerification: async () => false})}));
import { MomoReceiptsPage } from '../../src/features/operations/MomoReceiptsPage';

const rawId = '11111111-1111-4111-8111-111111111111', hash = 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9', time = '2026-10-18T08:00:00.000Z';
const job = {raw_sms_id: rawId, state: 'needs_review', binding_id: null, receiving_account_id: null, received_at: time, last_error: 'schema_mismatch', body_sha256: hash};
const transactionPage = {contract_version: 1, currency: 'RWF', date_basis: 'provider_transaction_time', rows: [], total: 0, offset: 0, limit: 25, totals: {received_minor: 0, credited_minor: 0, unallocated_minor: 0}, as_of: time};
const response = {raw_sms_id: rawId, body_sha256: hash, raw_sender: 'MTN MoMo', raw_body: 'hello world', latest_attempt: null};
afterEach(() => {mock.request.mockReset();});

it('opens source metadata from the attention list and gates its audited reveal', async () => {
  const user = userEvent.setup();
  mock.request.mockImplementation(async (path: string) => path.startsWith('sms/receipts?') ? {rows: [], total: 0, limit: 25, offset: 0, next_offset: null} : path.startsWith('momo/transactions?') ? transactionPage : path.startsWith('momo/sources?') ? {rows: [job], total: 1, limit: 25, offset: 0} : response);
  const view = render(<MemoryRouter><MomoReceiptsPage /></MemoryRouter>);
  await user.click(screen.getByRole('button', {name: 'Transactions'}));
  await user.selectOptions(screen.getByLabelText('Payment status'), 'needs_attention');
  await user.click(screen.getByRole('button', {name: 'Apply filters'}));
  await user.click(await screen.findByRole('button', {name: rawId}));
  const dialog = screen.getByRole('dialog', {name: 'Source message'});
  expect(within(dialog).getByText(hash)).toBeVisible();
  expect(within(dialog).queryByRole('button', {name: 'Review source access'})).not.toBeInTheDocument();
  expect(mock.request.mock.calls.every(([path]) => path !== `momo/sources/${rawId}/content`)).toBe(true);
  view.unmount();
  render(<MemoryRouter><MomoReceiptsPage allowActions /></MemoryRouter>);
  await user.click(screen.getByRole('button', {name: 'Transactions'}));
  await user.selectOptions(screen.getByLabelText('Payment status'), 'needs_attention');
  await user.click(screen.getByRole('button', {name: 'Apply filters'}));
  await user.click(await screen.findByRole('button', {name: rawId}));
  const enabledDialog = screen.getByRole('dialog', {name: 'Source message'});
  await user.type(within(enabledDialog).getByLabelText('Reason to review the original source'), 'Investigate source evidence');
  await user.click(within(enabledDialog).getByRole('button', {name: 'Review source access'}));
  await user.click(within(enabledDialog).getByRole('checkbox', {name: 'I confirm this source review.'}));
  await user.click(within(enabledDialog).getByRole('button', {name: 'View original SMS'}));
  expect(await within(enabledDialog).findByText('hello world')).toBeVisible();
  expect(mock.request.mock.calls.filter(([path]) => path === `momo/sources/${rawId}/content`)).toHaveLength(1);
  await user.click(within(enabledDialog).getByRole('button', {name: 'Close'}));
  expect(screen.queryByText('hello world')).not.toBeInTheDocument();
});
