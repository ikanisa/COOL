import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { MomoSourceJob } from '../../src/features/operations/momoContracts';

const mock = vi.hoisted(() => ({request: vi.fn(), epoch: 1, user: {id: '22222222-2222-4222-8222-222222222222', principalId: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.com', role: 'admin' as const, permissions: ['sms.read', 'sms.reveal'] as string[], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'canonical_evidence_ledger' as const, assuranceLevel: 2 as 1 | 2, mfaAt: new Date().toISOString() as string | null}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: mock.epoch, status: 'authenticated', request: mock.request, verificationMode: 'authenticator', isCurrentAuthority: (epoch: number, id: string, sessionId: string) => epoch === mock.epoch && id === mock.user.id && sessionId === mock.user.sessionId, recheckSensitiveEmailVerification: async () => false})}));
import { MomoSourceRevealPanel } from '../../src/features/operations/MomoSourceRevealPanel';

const rawId = '11111111-1111-4111-8111-111111111111', hash = 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9', reason = 'Investigate source evidence';
const source: MomoSourceJob = {raw_sms_id: rawId, state: 'needs_review', binding_id: null, receiving_account_id: null, received_at: '2026-10-18T08:00:00.000Z', last_error: 'schema_mismatch', body_sha256: hash};
const response = {raw_sms_id: rawId, body_sha256: hash, raw_sender: 'MTN MoMo', raw_body: 'hello world', latest_attempt: null};
beforeEach(() => {mock.epoch = 1; mock.user.permissions = ['sms.read', 'sms.reveal']; mock.user.assuranceLevel = 2; mock.user.mfaAt = new Date().toISOString(); mock.user.principalId = mock.user.id;});
afterEach(() => {mock.request.mockReset();});
async function confirmAccess(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText('Reason to review the original source'), reason);
  await user.click(screen.getByRole('button', {name: 'Review source access'}));
  const review = screen.getByRole('region', {name: 'Confirm source access'});
  expect(within(review).getByText(/Each access is separately recorded/)).toBeVisible();
  expect(within(review).getByRole('button', {name: 'View original SMS'})).toBeDisabled();
  await user.click(within(review).getByRole('checkbox', {name: 'I confirm this source review.'}));
  await user.click(within(review).getByRole('button', {name: 'View original SMS'}));
}

describe('MoMo audited source access panel', () => {
  it('stays hidden without its default-off gate or required permissions', () => {
    const {unmount} = render(<MemoryRouter><MomoSourceRevealPanel source={source} /></MemoryRouter>);
    expect(screen.queryByRole('button', {name: 'Review source access'})).not.toBeInTheDocument();
    unmount(); mock.user.permissions = ['sms.read'];
    render(<MemoryRouter><MomoSourceRevealPanel source={source} enabled /></MemoryRouter>);
    expect(screen.queryByRole('button', {name: 'Review source access'})).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('blocks a source with no recorded digest', () => {
    render(<MemoryRouter><MomoSourceRevealPanel source={{...source, body_sha256: undefined}} enabled /></MemoryRouter>);
    expect(screen.getByText(/recorded digest is missing/)).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review source access'})).not.toBeInTheDocument();
  });
  it('requires a reason, explicit confirmation and fresh proof before showing verified content', async () => {
    const user = userEvent.setup(); mock.request.mockResolvedValue(response);
    render(<MemoryRouter><MomoSourceRevealPanel source={source} enabled /></MemoryRouter>);
    await confirmAccess(user);
    const disclosed = await screen.findByRole('region', {name: 'Revealed original source'});
    expect(within(disclosed).getByText('hello world')).toBeVisible();
    expect(within(disclosed).getByText('Sender: MTN MoMo')).toBeVisible();
    expect(screen.getByText(/Source access recorded/)).toBeVisible();
    expect(mock.request).toHaveBeenCalledOnce();
    expect(mock.request).toHaveBeenCalledWith(`momo/sources/${rawId}/content`, expect.objectContaining({reviewReason: reason, signal: expect.any(AbortSignal)}));
    await user.click(within(disclosed).getByRole('button', {name: 'Hide message'}));
    expect(screen.queryByText('hello world')).not.toBeInTheDocument();
  });
  it('offers verification without requesting the source when proof is stale', async () => {
    const user = userEvent.setup(); mock.user.assuranceLevel = 1; mock.user.mfaAt = null;
    render(<MemoryRouter><MomoSourceRevealPanel source={source} enabled /></MemoryRouter>);
    await confirmAccess(user);
    expect(await screen.findByText('Complete current verification before viewing this source.')).toBeVisible();
    expect(screen.getByRole('link', {name: 'Verify identity'})).toHaveAttribute('href', '/admin/security/authenticator?returnTo=%2Fadmin%2Fmomo-receipts');
    expect(mock.request).not.toHaveBeenCalled();
  });
  it('reports an uncertain audit and never automatically retries a lost response', async () => {
    const user = userEvent.setup(); mock.request.mockRejectedValueOnce(new Error('lost'));
    render(<MemoryRouter><MomoSourceRevealPanel source={source} enabled /></MemoryRouter>);
    await confirmAccess(user);
    expect(await screen.findByText(/An access event may have been recorded/)).toBeVisible();
    expect(mock.request).toHaveBeenCalledOnce();
    expect(screen.queryByText('hello world')).not.toBeInTheDocument();
  });
  it('aborts an in-flight read and clears plaintext when authority changes', async () => {
    const user = userEvent.setup(); let release!: (value: typeof response) => void;
    mock.request.mockImplementation(() => new Promise((resolve) => {release = resolve;}));
    const view = render(<MemoryRouter><MomoSourceRevealPanel source={source} enabled /></MemoryRouter>);
    await confirmAccess(user);
    const options = mock.request.mock.calls[0][1] as {signal: AbortSignal};
    expect(options.signal.aborted).toBe(false);
    mock.epoch = 2; view.rerender(<MemoryRouter><MomoSourceRevealPanel source={source} enabled /></MemoryRouter>);
    expect(options.signal.aborted).toBe(true); release(response);
    await vi.waitFor(() => expect(screen.queryByText('hello world')).not.toBeInTheDocument());
    mock.request.mockResolvedValue(response);
    await confirmAccess(user);
    expect(await screen.findByText('hello world')).toBeVisible();
    mock.user.permissions = ['sms.read']; view.rerender(<MemoryRouter><MomoSourceRevealPanel source={source} enabled /></MemoryRouter>);
    expect(screen.queryByText('hello world')).not.toBeInTheDocument();
  });
});
