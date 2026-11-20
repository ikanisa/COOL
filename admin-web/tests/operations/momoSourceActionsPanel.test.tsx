import {webcrypto} from 'node:crypto';
import {render, screen, waitFor, within} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {MemoryRouter} from 'react-router';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {id: '22222222-2222-4222-8222-222222222222', principalId: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'operator@example.test', role: 'staff' as const, permissions: ['sms.read', 'sms.extract', 'receivers.read'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'canonical_evidence_ledger' as const, assuranceLevel: 2 as const, mfaAt: new Date().toISOString()}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request, verificationMode: 'authenticator', isCurrentAuthority: () => true})}));
import {MomoSourceActionsPanel, MomoSourceRecoveryPanel} from '../../src/features/operations/MomoSourceActionsPanel';
import {nonPaymentExtraction} from '../../src/features/operations/momoSourceActions';
import type {MomoSourceJob} from '../../src/features/operations/momoContracts';

const sourceId = '11111111-1111-4111-8111-111111111111', account = '33333333-3333-4333-8333-333333333333', attemptId = '55555555-5555-4555-8555-555555555555';
const source: MomoSourceJob = {raw_sms_id: sourceId, state: 'needs_review', binding_id: null, receiving_account_id: account, received_at: '2026-10-18T08:00:00.000Z', last_error: 'schema_mismatch', body_sha256: 'a'.repeat(64), attempt_count: 2, latest_attempt_id: attemptId, latest_attempt_outcome: 'needs_review'};
const unresolved: MomoSourceJob = {...source, state: 'source_unresolved', receiving_account_id: null, latest_attempt_id: null, latest_attempt_outcome: null};
const receipt = {raw_sms_id: sourceId, parse_attempt_id: attemptId, status: 'review_recorded', financial_effects: 0};
beforeEach(() => {
  vi.stubGlobal('crypto', webcrypto); sessionStorage.clear(); localStorage.clear();
  Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (_name: string, _options: unknown, callback: (lock: unknown) => Promise<unknown>) => callback({name: 'synthetic'})}});
  mock.request.mockReset();
});
afterEach(() => {vi.unstubAllGlobals(); Reflect.deleteProperty(navigator, 'locks');});
function mount(element: React.ReactNode) {return render(<MemoryRouter>{element}</MemoryRouter>);}

async function prepareNonPayment() {
  const user = userEvent.setup();
  await user.click(screen.getByRole('button', {name: 'Classify non-payment'}));
  const section = screen.getByRole('region', {name: 'Classify non-payment'});
  await within(section).findByLabelText('Classification');
  await user.selectOptions(within(section).getByLabelText('Classification'), 'failed');
  await user.type(within(section).getByLabelText('Exact classification excerpt'), 'Payment failed.');
  await user.type(within(section).getByLabelText('Supporting evidence reference'), 'Synthetic evidence reference');
  await user.type(within(section).getByLabelText('Reason'), 'Reviewed synthetic source');
  await user.click(within(section).getByRole('button', {name: 'Review source request'}));
  return user;
}

describe('MoMo source action controls', () => {
  it('does not expose source writes by default', () => {
    mount(<MomoSourceActionsPanel source={source} onUpdated={() => undefined} />);
    expect(screen.queryByRole('button', {name: /Correct extraction|Classify non-payment|Reparse source/})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('confirms a guarded reparse and retains its exact version for explicit same-key recovery', async () => {
    mock.request.mockRejectedValueOnce(new Error('lost reply')).mockResolvedValueOnce({raw_sms_id: sourceId, status: 'pending'});
    const first = mount(<MomoSourceActionsPanel source={source} enabled onUpdated={() => undefined} />), user = userEvent.setup();
    await user.click(screen.getByRole('button', {name: 'Reparse source'}));
    const section = screen.getByRole('region', {name: 'Reparse source'});
    await user.type(await within(section).findByLabelText('Reason'), 'Review synthetic source again');
    await user.click(within(section).getByRole('button', {name: 'Review source request'}));
    const confirm = screen.getByRole('region', {name: 'Confirm source request'});
    expect(mock.request).not.toHaveBeenCalled();
    expect(within(confirm).getByText(/expected_receiving_account_id/)).toBeInTheDocument();
    await user.click(within(confirm).getByRole('checkbox', {name: /I reviewed this source/}));
    await user.click(within(confirm).getByRole('button', {name: 'Confirm source request'}));
    await screen.findByText(/result is unknown/i); expect(mock.request).toHaveBeenCalledOnce();
    expect(mock.request).toHaveBeenCalledWith(`momo/sources/${sourceId}/reparse`, expect.objectContaining({method: 'POST', body: {
      reason: 'Review synthetic source again', expected_state: 'needs_review', expected_attempt_count: 2, expected_body_sha256: 'a'.repeat(64), expected_receiving_account_id: account,
    }}));
    first.unmount(); mount(<MomoSourceRecoveryPanel enabled onUpdated={() => undefined} />);
    await user.click(screen.getByRole('button', {name: 'Review original source requests'}));
    await user.click(await screen.findByRole('button', {name: 'Review original request'}));
    const recovered = await screen.findByRole('region', {name: 'Reparse source'});
    await user.click(await within(recovered).findByRole('button', {name: 'Review original request'}));
    const retry = screen.getByRole('region', {name: 'Confirm source request'});
    expect(mock.request).toHaveBeenCalledOnce();
    await user.click(within(retry).getByRole('checkbox', {name: /I reviewed this source/}));
    await user.click(within(retry).getByRole('button', {name: 'Retry original request'}));
    expect(await screen.findByText(/Source queued for extraction/)).toBeInTheDocument();
    expect(mock.request.mock.calls[1]).toEqual(mock.request.mock.calls[0]);
  });
  it('prefills a verified source suggestion only as unverified editable fields', async () => {
    const candidate = {...nonPaymentExtraction('failed', 'Payment failed.'), event_kind: 'incoming_receipt' as const, payment_outcome: 'successful' as const, transaction_id_raw: 'ABC123'};
    mount(<MomoSourceActionsPanel source={source} candidate={candidate} enabled onUpdated={() => undefined} />);
    const user = userEvent.setup(); await user.click(screen.getByRole('button', {name: 'Correct extraction'}));
    expect(await screen.findByLabelText('Provider transaction ID')).toHaveValue('ABC123');
    expect(screen.getByText(/Suggested fields are unverified/)).toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('requires a second explicit confirmation before recording a classification', async () => {
    mock.request.mockResolvedValue(receipt); mount(<MomoSourceActionsPanel source={source} enabled onUpdated={() => undefined} />);
    const user = await prepareNonPayment(), confirm = screen.getByRole('region', {name: 'Confirm source request'});
    expect(mock.request).not.toHaveBeenCalled();
    expect(within(confirm).getByRole('button', {name: 'Confirm source request'})).toBeDisabled();
    await user.click(within(confirm).getByRole('checkbox', {name: /I reviewed this source/}));
    await user.click(within(confirm).getByRole('button', {name: 'Confirm source request'}));
    expect(await screen.findByText('Source review recorded. No contribution was credited.')).toBeInTheDocument();
    expect(mock.request).toHaveBeenCalledOnce();
    expect(mock.request).toHaveBeenCalledWith(`momo/sources/${sourceId}/classify-non-payment`, expect.objectContaining({method: 'POST', body: expect.objectContaining({classification_evidence: 'Payment failed.', expected_attempt_count: 2})}));
  });
  it('records the exact corrected fields and supporting excerpts only after confirmation', async () => {
    mock.request.mockResolvedValue(receipt); mount(<MomoSourceActionsPanel source={source} enabled onUpdated={() => undefined} />);
    const user = userEvent.setup(); await user.click(screen.getByRole('button', {name: 'Correct extraction'}));
    const section = screen.getByRole('region', {name: 'Correct extraction'});
    await user.type(await within(section).findByLabelText('Provider transaction ID'), 'ABC123');
    await user.type(within(section).getByLabelText('Principal amount'), '5000');
    await user.type(within(section).getByLabelText('Currency'), 'RWF');
    await user.click(within(section).getByText('Exact supporting excerpts'));
    await user.type(within(section).getByLabelText('Success excerpt'), 'You have received RWF 5000');
    await user.type(within(section).getByLabelText('Principal excerpt'), 'RWF 5000');
    await user.type(within(section).getByLabelText('Transaction ID excerpt'), 'Transaction ABC123');
    await user.type(within(section).getByLabelText('Supporting evidence reference'), 'Synthetic evidence reference');
    await user.type(within(section).getByLabelText('Reason'), 'Reviewed synthetic source');
    await user.click(within(section).getByRole('button', {name: 'Review source request'}));
    const confirmation = screen.getByRole('region', {name: 'Confirm source request'});
    expect(within(confirmation).getByText(/ABC123/)).toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
    await user.click(within(confirmation).getByRole('checkbox', {name: /I reviewed this source/}));
    await user.click(within(confirmation).getByRole('button', {name: 'Confirm source request'}));
    expect(await screen.findByText('Source review recorded. No contribution was credited.')).toBeInTheDocument();
    expect(mock.request).toHaveBeenCalledWith(`momo/sources/${sourceId}/correct-extraction`, expect.objectContaining({body: expect.objectContaining({extraction: expect.objectContaining({transaction_id_raw: 'ABC123', principal_amount_raw: '5000', currency_raw: 'RWF'})})}));
  });
  it('recovers an unknown source request after the source moved away, with an explicitly confirmed same-key retry', async () => {
    mock.request.mockRejectedValueOnce(new Error('lost reply')).mockResolvedValueOnce(receipt);
    const first = mount(<MomoSourceActionsPanel source={source} enabled onUpdated={() => undefined} />), user = await prepareNonPayment();
    const confirm = screen.getByRole('region', {name: 'Confirm source request'});
    await user.click(within(confirm).getByRole('checkbox', {name: /I reviewed this source/}));
    await user.click(within(confirm).getByRole('button', {name: 'Confirm source request'}));
    await screen.findByText(/result is unknown/i); await waitFor(() => expect(mock.request).toHaveBeenCalledTimes(1));
    const firstKey = mock.request.mock.calls[0][1].idempotencyKey; first.unmount();
    mount(<MomoSourceRecoveryPanel enabled onUpdated={() => undefined} />);
    await user.click(screen.getByRole('button', {name: 'Review original source requests'}));
    await user.click(await screen.findByRole('button', {name: 'Review original request'}));
    const section = await screen.findByRole('region', {name: 'Classify non-payment'});
    await user.click(await within(section).findByRole('button', {name: 'Review original request'}));
    const retry = screen.getByRole('region', {name: 'Confirm source request'});
    expect(within(retry).getByText(/may record the action/)).toBeInTheDocument();
    expect(mock.request).toHaveBeenCalledTimes(1);
    await user.click(within(retry).getByRole('checkbox', {name: /I reviewed this source/}));
    await user.click(within(retry).getByRole('button', {name: 'Retry original request'}));
    await waitFor(() => expect(mock.request).toHaveBeenCalledTimes(2));
    expect(mock.request.mock.calls[1][1]).toEqual(mock.request.mock.calls[0][1]);
    expect(mock.request.mock.calls[1][1].idempotencyKey).toBe(firstKey);
  });
  it('loads active receiving accounts and confirms an exact historical resolution', async () => {
    mock.request.mockImplementation(async (path: string) => path === 'momo/accounts' ? {rows: [{id: account, provider: 'mtn_momo', public_code: '123456', recipient_name: 'Synthetic account', status: 'active'}]} : {raw_sms_id: sourceId, receiving_account_id: account, status: 'pending', mode: 'historical', financial_effects: 0});
    mount(<MomoSourceActionsPanel source={unresolved} enabled onUpdated={() => undefined} />);
    const user = userEvent.setup(); await user.click(screen.getByRole('button', {name: 'Resolve historical source'}));
    const section = screen.getByRole('region', {name: 'Resolve historical source'});
    const select = await within(section).findByLabelText('Receiving account');
    await user.selectOptions(select, account);
    await user.type(within(section).getByLabelText('Supporting evidence reference'), 'Synthetic historical evidence');
    await user.type(within(section).getByLabelText('Reason'), 'Reviewed original receiving source');
    await user.click(within(section).getByRole('button', {name: 'Review source request'}));
    expect(mock.request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(0);
    const confirm = screen.getByRole('region', {name: 'Confirm source request'});
    await user.click(within(confirm).getByRole('checkbox', {name: /I reviewed this source/}));
    await user.click(within(confirm).getByRole('button', {name: 'Confirm source request'}));
    expect(await screen.findByText('Historical source queued. No contribution was credited.')).toBeInTheDocument();
    expect(mock.request.mock.calls.filter(([, options]) => options?.method === 'POST')).toHaveLength(1);
  });
});
