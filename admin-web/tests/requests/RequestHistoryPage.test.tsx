import {render, screen, waitFor} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {describe, expect, it, vi} from 'vitest';
import type {AdminRequestOptions} from '../../src/api/client';
import {RequestHistoryPage} from '../../src/features/requests/RequestHistoryPage';

describe('request history', () => {
  it('checks only the original reference and explains that not found is inconclusive', async () => {
    const request = vi.fn(async (path: string, _options?: AdminRequestOptions) => path.startsWith('operations/requests?') ?
      {contract_version: 2, model: 'canonical_evidence_ledger', rows: [], total: 0} :
      {contract_version: 2, model: 'canonical_evidence_ledger', status: 'not_found'});
    render(<RequestHistoryPage request={request} permissions={['overview.read', 'account.manage']} actorId="actor" principalId="12345678-1234-4123-8123-123456789012"
      authorityKey="session-a" financialModel="canonical_evidence_ledger" role="admin" navigate={() => undefined} />);
    await screen.findByText('No requests found');
    await userEvent.type(screen.getByLabelText('Request reference'), 'request-original-001');
    await userEvent.click(screen.getByRole('button', {name: 'Check request'}));
    await screen.findByText(/does not prove that an attempted change failed/i);
    await waitFor(() => expect(request.mock.calls.filter(([path]) => path === 'operations/requests/request-original-001')).toHaveLength(1));
    expect(request.mock.calls.every(([, options]) => !options || !('body' in options))).toBe(true);
  });
  it('does not request history without the backend-required account permission', () => {
    const request = vi.fn();
    render(<RequestHistoryPage request={request} permissions={['overview.read']} actorId="actor" principalId="12345678-1234-4123-8123-123456789012"
      authorityKey="session-a" financialModel="canonical_evidence_ledger" role="admin" navigate={() => undefined} />);
    expect(screen.getByRole('alert')).toHaveTextContent('cannot view');
    expect(request).not.toHaveBeenCalled();
  });
  it('allows the legacy actor-scoped lookup with overview permission without enabling cancellation', async () => {
    const request = vi.fn(async (path: string, _options?: AdminRequestOptions) => path.startsWith('operations/requests?') ?
      {rows: [], total: 0} : {status: 'not_found'});
    render(<RequestHistoryPage request={request} permissions={['overview.read']} actorId="actor" principalId={null}
      authorityKey="session-a" financialModel="transaction_journals" role="staff" navigate={() => undefined} />);
    await screen.findByText('No requests found');
    await userEvent.type(screen.getByLabelText('Request reference'), 'request-original-001');
    await userEvent.click(screen.getByRole('button', {name: 'Check request'}));
    await screen.findByText(/does not prove that an attempted change failed/i);
    expect(request.mock.calls.map(([path]) => path)).toContain('operations/requests/request-original-001');
    expect(request.mock.calls.every(([, options]) => !options || !('body' in options))).toBe(true);
    expect(screen.queryByText('Cancellation recovery')).not.toBeInTheDocument();
  });
});
