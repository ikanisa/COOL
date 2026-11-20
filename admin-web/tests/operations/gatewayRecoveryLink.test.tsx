import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterEach, describe, expect, it, vi } from 'vitest';

const mock = vi.hoisted(() => ({request: vi.fn(), session: {status: 'authenticated', epoch: 1, user: {id: '11111111-1111-1111-1111-111111111111', role: 'admin', financialModel: 'transaction_journals', permissions: ['gateway.read', 'gateway.manage', 'overview.read'] as string[]}}}));
vi.mock('../../src/session/SessionProvider', async (importOriginal) => ({...await importOriginal<typeof import('../../src/session/SessionProvider')>(), useSession: () => ({...mock.session, request: mock.request})}));
import { GatewayDevicesPage } from '../../src/features/operations';
afterEach(() => {mock.request.mockReset(); mock.session.user.role = 'admin'; mock.session.user.financialModel = 'transaction_journals'; mock.session.user.permissions = ['gateway.read', 'gateway.manage', 'overview.read'];});

describe('Gateway enrollment recovery entry', () => {
  it('shows the recovery link while enrollment is disabled', async () => {
    mock.request.mockResolvedValue({rows: [], total: 0});
    render(<MemoryRouter><GatewayDevicesPage /></MemoryRouter>);
    expect(await screen.findByRole('link', {name: 'Check gateway enrollment request'})).toHaveAttribute('href', '/admin/gateway/new');
    expect(screen.queryByRole('link', {name: 'Enroll device'})).not.toBeInTheDocument();
  });
  it('hides recovery from accounts lacking the required capability or contract', async () => {
    mock.request.mockResolvedValue({rows: [], total: 0});
    mock.session.user.permissions = ['gateway.read', 'gateway.manage'];
    const {unmount} = render(<MemoryRouter><GatewayDevicesPage /></MemoryRouter>);
    await screen.findByText('No records found');
    expect(screen.queryByRole('link', {name: 'Check gateway enrollment request'})).not.toBeInTheDocument();
    unmount();
    mock.session.user.permissions = ['gateway.read', 'gateway.manage', 'overview.read'];
    mock.session.user.financialModel = 'canonical_evidence_ledger';
    render(<MemoryRouter><GatewayDevicesPage /></MemoryRouter>);
    await screen.findByText('No records found');
    expect(screen.queryByRole('link', {name: 'Check gateway enrollment request'})).not.toBeInTheDocument();
  });
});
