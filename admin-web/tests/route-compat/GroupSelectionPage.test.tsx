import {fireEvent, render, screen, waitFor} from '@testing-library/react';
import {describe, expect, it, vi} from 'vitest';
import fixture from '../core/canonical-core-fixtures.json';
import {GroupSelectionPage} from '../../src/features/route-compat/GroupSelectionPage';
import type {FeatureAccess} from '../../src/features/core/types';

const group = fixture.groups.rows[0];
const base: FeatureAccess = {request: vi.fn(), permissions: ['collections.read', 'users.manage', 'receivers.manage'], actorId: 'actor', principalId: null,
  role: 'admin', authorityKey: 'authority-a', financialModel: 'transaction_journals', navigate: vi.fn()};

describe('group selection for legacy create links', () => {
  it('opens only the selected legacy group membership workflow using read requests', async () => {
    const navigate = vi.fn(), request = vi.fn(async (_path: string) => ({rows: [{id: group.id, label: group.title, version: 1}]}));
    render(<GroupSelectionPage {...base} request={request} navigate={navigate} action="member" isCurrent={() => true} />);
    fireEvent.change(screen.getByLabelText('Search groups'), {target: {value: 'Controlled'}});
    fireEvent.click(screen.getByRole('button', {name: 'Search'}));
    fireEvent.click(await screen.findByRole('button', {name: `Select ${group.title}`}));
    expect(navigate).toHaveBeenCalledWith(`/admin/groups/${group.id}/members/new`);
    expect(request).toHaveBeenCalledOnce();
    expect(request.mock.calls[0][0]).toBe('operations/lookups?kind=groups&search=Controlled&limit=100');
  });

  it('accepts canonical groups only with the full matching model and active record', async () => {
    const navigate = vi.fn(), request = vi.fn(async () => ({contract_version: 2, model: 'canonical_evidence_ledger', kind: 'groups', group_id: null,
      total: 1, rows: [{...group, label: group.title, name: group.title}]}));
    render(<GroupSelectionPage {...base} financialModel="canonical_evidence_ledger" request={request} navigate={navigate} action="member" isCurrent={() => true} />);
    fireEvent.click(screen.getByRole('button', {name: 'Search'}));
    fireEvent.click(await screen.findByRole('button', {name: `Select ${group.title}`}));
    expect(navigate).toHaveBeenCalledWith(`/admin/groups/${group.id}/members/new`);
  });

  it('does not expose a separate canonical payee creation or search without group access', () => {
    const request = vi.fn();
    const view = render(<GroupSelectionPage {...base} financialModel="canonical_evidence_ledger" request={request} action="payee" isCurrent={() => true} />);
    expect(screen.getByText(/Separate payee creation is unavailable/)).toBeInTheDocument();
    view.rerender(<GroupSelectionPage {...base} permissions={[]} request={request} action="member" isCurrent={() => true} />);
    expect(screen.getByText(/cannot view groups/)).toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });

  it('discards a delayed result when the operator changes the search or authority', async () => {
    let finish!: (value: Record<string, unknown>) => void;
    let current = true;
    const request = vi.fn(() => new Promise<Record<string, unknown>>(resolve => {finish = resolve;}));
    render(<GroupSelectionPage {...base} request={request} action="member" isCurrent={() => current} />);
    fireEvent.click(screen.getByRole('button', {name: 'Search'}));
    fireEvent.change(screen.getByLabelText('Search groups'), {target: {value: 'new search'}});
    current = false; finish({rows: [{id: group.id, label: group.title, version: 1}]});
    await waitFor(() => expect(screen.queryByRole('button', {name: `Select ${group.title}`})).not.toBeInTheDocument());
  });

  it('rejects duplicate or malformed group results', async () => {
    const request = vi.fn(async () => ({rows: [{id: group.id, label: group.title, version: 1}, {id: group.id, label: group.title, version: 1}]}));
    render(<GroupSelectionPage {...base} request={request} action="payee" isCurrent={() => true} />);
    fireEvent.click(screen.getByRole('button', {name: 'Search'}));
    expect(await screen.findByRole('alert')).toHaveTextContent('could not be verified');
    expect(screen.queryByRole('button', {name: `Select ${group.title}`})).not.toBeInTheDocument();
  });
});
