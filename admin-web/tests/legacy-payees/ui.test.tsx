import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { retainPending } from '../../src/features/core/pendingAttempt';
import { LegacyPayeeEditPage } from '../../src/features/legacy-payees';
import { access, found, identity, intent, key, mockApi, payeeId, receipt } from './fixture';

const locks = Object.getOwnPropertyDescriptor(navigator, 'locks');
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {if (locks) Object.defineProperty(navigator, 'locks', locks); else Reflect.deleteProperty(navigator, 'locks');});

describe('legacy receiver edit page', () => {
  it('keeps receiver changes disabled by default', async () => {
    const request = mockApi(); render(<LegacyPayeeEditPage {...access(request)} id={payeeId} identity={identity} verifyFresh={async () => true} />);
    expect(await screen.findByText('Receiver changes are not enabled for this workspace.')).toBeVisible(); expect(screen.queryByRole('button', {name: 'Review receiver'})).not.toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('shows the immutable route, requires confirmation and sends only the guarded receiver edit', async () => {
    const user = userEvent.setup(), verifyFresh = vi.fn().mockResolvedValue(true), request = mockApi({write: async (_path, args) => {if (args?.method) {expect(args.body).toEqual(intent); return receipt;} return found();}});
    render(<LegacyPayeeEditPage {...access(request)} id={payeeId} identity={identity} allowMutations verifyFresh={verifyFresh} />);
    const name = await screen.findByLabelText('Receiver name'); await user.clear(name); await user.type(name, intent.label); await user.type(screen.getByLabelText('Reason'), intent.reason);
    expect(screen.getByText(/Recorded route: mtn_momo · 0041258/)).toBeVisible(); expect(screen.queryByLabelText('MoMo number or code')).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', {name: 'Review receiver'})); expect(screen.getByRole('button', {name: 'Confirm receiver'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the group, receiver, route, status and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm receiver'}));
    expect(await screen.findByText('The receiver change was recorded.')).toBeVisible(); expect(verifyFresh).toHaveBeenCalledOnce();
  });
  it('blocks deactivation of the active receiver of an active group', async () => {
    const user = userEvent.setup(), request = mockApi(); render(<LegacyPayeeEditPage {...access(request)} id={payeeId} identity={identity} allowMutations verifyFresh={async () => true} />);
    await user.selectOptions(await screen.findByLabelText('Receiver status'), 'inactive'); await user.type(screen.getByLabelText('Reason'), intent.reason); await user.click(screen.getByRole('button', {name: 'Review receiver'}));
    expect(await screen.findByText(/active group must retain its active receiver/)).toBeVisible(); expect(request.mock.calls.every(([, args]) => !args?.method)).toBe(true);
  });
  it('checks an older Flutter request while writes are disabled without offering a retry', async () => {
    await retainPending(identity, 'operating-updatepayee', payeeId, key, 'receivers.manage', {label: intent.label, status: intent.status, expected_version: intent.expected_version, reason: intent.reason});
    const user = userEvent.setup(), request = mockApi({write: async () => ({status: 'not_found'})}); render(<LegacyPayeeEditPage {...access(request)} id={payeeId} identity={identity} verifyFresh={async () => false} />);
    expect(await screen.findByText(key)).toBeVisible(); await user.click(screen.getByRole('button', {name: 'Check request'}));
    expect(await screen.findByText(/original intent cannot be verified for retry/)).toBeVisible(); expect(screen.queryByRole('button', {name: 'Review same request'})).not.toBeInTheDocument();
  });
  it('requires lookup and a fresh confirmation before retrying an unconfirmed request', async () => {
    const user = userEvent.setup(); let writes = 0, originalKey = '', originalBody: unknown;
    const request = mockApi({write: async (_path, args) => {if (args?.method) {writes++; if (writes === 1) {originalKey = args.idempotencyKey!; originalBody = args.body; throw new Error('lost');} expect(args.idempotencyKey).toBe(originalKey); expect(args.body).toEqual(originalBody); return receipt;} return writes === 1 ? {status: 'not_found'} : found();}});
    render(<LegacyPayeeEditPage {...access(request)} id={payeeId} identity={identity} allowMutations verifyFresh={async () => true} />);
    const name = await screen.findByLabelText('Receiver name'); await user.clear(name); await user.type(name, intent.label); await user.type(screen.getByLabelText('Reason'), intent.reason);
    await user.click(screen.getByRole('button', {name: 'Review receiver'})); await user.click(screen.getByRole('checkbox', {name: 'I reviewed the group, receiver, route, status and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm receiver'}));
    expect(await screen.findByText(/result is unconfirmed/)).toBeVisible(); expect(writes).toBe(1);
    await waitFor(() => expect(screen.getByRole('button', {name: 'Check request'})).toBeEnabled()); await user.click(screen.getByRole('button', {name: 'Check request'}));
    await user.click(await screen.findByRole('button', {name: 'Review same request'})); expect(screen.getByRole('button', {name: 'Confirm same request'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the group, receiver, route, status and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm same request'}));
    expect(await screen.findByText('The receiver change was recorded.')).toBeVisible(); expect(writes).toBe(2);
  });
});
