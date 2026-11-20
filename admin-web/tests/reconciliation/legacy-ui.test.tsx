import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { retainPending } from '../../src/features/core/pendingAttempt';
import { LegacyReconciliationActions } from '../../src/features/reconciliation/LegacyReconciliationActions';
import { parseReconciliationDetail } from '../../src/features/reconciliation/contracts';
import { makeLegacyProposal, searchLegacyReconciliationMembers } from '../../src/features/reconciliation/legacyActions';
import { access, actor, approvedReceipt, context, identity, key, memberId, mockApi, payment, permissions, proposedReceipt, response, saved, transactionId } from './legacy-fixture';

const snapshot = () => parseReconciliationDetail(response(), 'transaction_journals', transactionId, actor, null, permissions, 'admin'), locks = Object.getOwnPropertyDescriptor(navigator, 'locks');
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {if (locks) Object.defineProperty(navigator, 'locks', locks); else Reflect.deleteProperty(navigator, 'locks');});

describe('legacy reconciliation interface', () => {
  it('keeps proposals and reviews disabled by default', async () => {
    const request = mockApi(); render(<LegacyReconciliationActions detail={snapshot()} access={access(request)} identity={identity} verifyFresh={async () => true} onCompleted={vi.fn()} />);
    expect(await screen.findByText('Reconciliation changes are not enabled for this workspace.')).toBeVisible(); expect(screen.queryByRole('button', {name: 'Search members'})).not.toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
  it('searches and explicitly confirms a proposal before sending its exact financial intent', async () => {
    const user = userEvent.setup(), request = mockApi({write: async (_path, options) => options?.method ? proposedReceipt : saved(proposedReceipt)}), completed = vi.fn();
    render(<LegacyReconciliationActions detail={snapshot()} access={access(request)} identity={identity} allowMutations verifyFresh={async () => true} onCompleted={completed} />);
    await user.type(await screen.findByLabelText('Search eligible members'), '123456'); await user.click(screen.getByRole('button', {name: 'Search members'}));
    await user.selectOptions(await screen.findByLabelText('Member'), memberId); await user.type(screen.getByLabelText('Amount (RWF)'), '400'); await user.type(screen.getByLabelText('Reason'), 'Review member attribution');
    await user.click(screen.getByRole('button', {name: 'Review proposal'})); expect(await screen.findByText(/Source: public_reference/)).toBeVisible(); expect(screen.getByRole('button', {name: 'Confirm reconciliation'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the evidence, member, receiver, amount and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm reconciliation'}));
    expect(await screen.findByText('The proposal was recorded for independent review.')).toBeVisible(); expect(completed).toHaveBeenCalledOnce();
    const write = request.mock.calls.find(([, options]) => options?.method); expect(write?.[1]?.body).toMatchObject({member_user_id: memberId, amount_rwf: 400, expected_transaction_version: 2});
  });
  it('requires independent review and labels approval as an allocation rather than settlement', async () => {
    const user = userEvent.setup(), request = mockApi({write: async (_path, options) => options?.method ? approvedReceipt : saved(approvedReceipt)});
    render(<LegacyReconciliationActions detail={snapshot()} access={access(request)} identity={identity} allowMutations verifyFresh={async () => true} onCompleted={vi.fn()} />);
    await user.click(await screen.findByRole('button', {name: 'Load independent proposals'})); await user.selectOptions(await screen.findByLabelText('Proposal'), '77777777-7777-4777-8777-777777777777');
    await user.type(screen.getByLabelText('Reason'), 'Independent reconciliation review'); await user.click(screen.getByRole('button', {name: 'Review approval'}));
    await user.click(await screen.findByRole('checkbox', {name: 'I reviewed the evidence, member, receiver, amount and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm reconciliation'}));
    expect(await screen.findByText('The independent approval and allocation were recorded. Provider settlement is not asserted.')).toBeVisible();
  });
  it('checks an old Flutter request with writes disabled and never offers an unbound retry', async () => {
    const initial = context(mockApi()), member = (await searchLegacyReconciliationMembers(initial, '123456')).rows[0], intent = makeLegacyProposal(initial, payment, member, 400, 'Review member attribution');
    const oldBody = {...intent.body}; delete oldBody.expected_source_state;
    await retainPending(identity, 'reconciliation', transactionId, key, 'reconciliations.propose', {...intent, body: oldBody});
    const user = userEvent.setup(), request = mockApi({write: async () => ({status: 'not_found'})}); render(<LegacyReconciliationActions detail={snapshot()} access={access(request)} identity={identity} verifyFresh={async () => true} onCompleted={vi.fn()} />);
    expect(await screen.findByText(key)).toBeVisible(); await user.click(screen.getByRole('button', {name: 'Check request'}));
    expect(await screen.findByText(/original intent cannot be verified for retry/)).toBeVisible(); expect(screen.queryByRole('button', {name: 'Review same request'})).not.toBeInTheDocument();
  });
});
