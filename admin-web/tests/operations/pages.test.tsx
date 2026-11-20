import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { StrictMode } from 'react';
import { MemoryRouter, Route, Routes } from 'react-router';
import { afterEach, describe, expect, it, vi } from 'vitest';

const mock = vi.hoisted(() => ({
  request: vi.fn(),
  session: {status: 'authenticated', epoch: 1, user: {id: '11111111-1111-1111-1111-111111111111', role: 'admin', financialModel: 'canonical_evidence_ledger', permissions: ['email.read'] as string[]}},
}));
vi.mock('../../src/session/SessionProvider', async (importOriginal) => {
  const original = await importOriginal<typeof import('../../src/session/SessionProvider')>();
  return {...original, useSession: () => ({...mock.session, request: mock.request})};
});

import { EmailEventsPage, SmsReceiptDetailPage, SmsReceiptsPage } from '../../src/features/operations';

const epoch = Date.parse('2026-11-16T08:00:00.000Z') / 1000;
function row(index: number) {
  return {id: `11111111-1111-1111-1111-${String(index).padStart(12, '0')}`, recipient_masked: 'a•••@example.com', notification_type: 'notice', status: 'accepted', attempt_count: 1, created_at: epoch, updated_at: epoch, accepted_at: epoch, delivered_at: null};
}
function capture(index: number, displayName = 'Captured user') {
  return {source_kind: 'capture', id: `aaaaaaaa-aaaa-4aaa-8aaa-${String(index).padStart(12, '0')}`,
    user_id: mock.session.user.id, payee_id: null, source_sha256: 'a'.repeat(64), status: 'received', version: 1,
    received_at: epoch, created_at: epoch, public_id: '123456', display_name: displayName, transaction_id: null,
    evidence_level: 'client_received', source_fact_id: null, parser_version: null, extraction_status: 'not_extracted',
    source_body_sha256: null, source_payload_sha256: null, parsed_at: null, payer_name: null, payer_phone: null,
    payer_masked_phone: null, payer_last3: null, payee_momo_number: null, payee_momo_code: null,
    momo_transaction_reference: null, momo_timestamp_local: null, momo_timezone_offset: null, amount_rwf: null,
    wallet_balance_rwf: null, network: null, direction: null, is_payment: null, transaction_reference: null,
    duplicate_reference_count: 0, conflicting_reference_count: 0, provider_confirmation: false,
    settlement_status: 'not_asserted', timezone_known: false, payer_last3_known: false,
    source_content_reveal_required: true, received_at_device: '2026-11-16T10:00:00+02:00'};
}
function receiver(index: number) {
  const {received_at_device: _deviceTime, ...common} = capture(index);
  return {...common, source_kind: 'receiver', user_id: null, payee_id: mock.session.user.id, public_id: null,
    evidence_level: 'receiver_ingress_unverified', status: 'parsed', source_fact_id: `bbbbbbbb-bbbb-4bbb-8bbb-${String(index).padStart(12, '0')}`,
    parser_version: 'collect-admin-source-facts-v1', source_body_sha256: 'b'.repeat(64), source_payload_sha256: 'a'.repeat(64),
    parsed_at: epoch, extraction_status: 'parsed', momo_transaction_reference: 'RECORDED-MOMO-REFERENCE',
    amount_rwf: 1000, network: 'mtn_momo', direction: 'incoming', is_payment: 1,
    duplicate_reference_count: 1, conflicting_reference_count: 0};
}
afterEach(() => { mock.request.mockReset(); mock.session.user.permissions = ['email.read']; mock.session.user.financialModel = 'canonical_evidence_ledger'; mock.session.epoch = 1; });

describe('Operational pages', () => {
  it('uses the authorized endpoint and coalesces the initial StrictMode read', async () => {
    mock.request.mockResolvedValue({rows: [row(1)], total: 1, limit: 25, offset: 0});
    render(<StrictMode><MemoryRouter initialEntries={['/admin/email']}><EmailEventsPage /></MemoryRouter></StrictMode>);
    expect(await screen.findByText('a•••@example.com')).toBeVisible();
    const table = screen.getByRole('table');
    expect(within(table).getByText('Accepted')).toBeVisible();
    expect(mock.request).toHaveBeenCalledTimes(1);
    expect(mock.request).toHaveBeenCalledWith('email/events?limit=25&offset=0');
    expect(within(table).queryByText('Delivered')).not.toBeInTheDocument();
  });

  it('does not request records without the server-granted permission', () => {
    mock.session.user.permissions = [];
    render(<MemoryRouter><EmailEventsPage /></MemoryRouter>);
    expect(screen.getByText('Your current account cannot open these records.')).toBeVisible();
    expect(mock.request).not.toHaveBeenCalled();
  });

  it('fails closed on malformed or unmasked response data', async () => {
    mock.request.mockResolvedValue({rows: [{...row(1), recipient_masked: 'private@example.com'}], total: 1, limit: 25, offset: 0});
    render(<MemoryRouter><EmailEventsPage /></MemoryRouter>);
    expect(await screen.findByText('The workspace response could not be verified.')).toBeVisible();
    expect(screen.queryByText('private@example.com')).not.toBeInTheDocument();
  });

  it('requests the next bounded page when the operator selects Next', async () => {
    const user = userEvent.setup();
    mock.request.mockImplementation(async (path: string) => path.includes('offset=25')
      ? {rows: [row(26)], total: 26, limit: 25, offset: 25}
      : {rows: Array.from({length: 25}, (_, index) => row(index + 1)), total: 26, limit: 25, offset: 0});
    render(<MemoryRouter initialEntries={['/admin/email']}><EmailEventsPage /></MemoryRouter>);
    expect(await screen.findByText('Showing 1–25 of 26')).toBeVisible();
    await user.click(screen.getByRole('button', {name: 'Next'}));
    expect(await screen.findByText('Showing 26–26 of 26')).toBeVisible();
    expect(mock.request).toHaveBeenLastCalledWith('email/events?limit=25&offset=25');
  });

  it('lets an operator recover when a saved page is now beyond the total', async () => {
    const user = userEvent.setup();
    mock.request.mockImplementation(async (path: string) => path.includes('offset=25')
      ? {rows: [], total: 1, limit: 25, offset: 25}
      : {rows: [row(1)], total: 1, limit: 25, offset: 0});
    render(<MemoryRouter initialEntries={['/admin/email?offset=25']}><EmailEventsPage /></MemoryRouter>);
    expect(await screen.findByText('No records found')).toBeVisible();
    await user.click(screen.getByRole('button', {name: 'Previous'}));
    expect(await screen.findByText('Showing 1–1 of 1')).toBeVisible();
  });
});

describe('SMS receipt filters', () => {
  it('requires the existing read permission before requesting or showing filters', () => {
    mock.session.user.permissions = [];
    render(<MemoryRouter><SmsReceiptsPage /></MemoryRouter>);
    expect(screen.getByText('Your current account cannot open these records.')).toBeVisible();
    expect(screen.queryByLabelText('Source')).not.toBeInTheDocument();
    expect(mock.request).not.toHaveBeenCalled();
  });

  it('clears the server search, filters and page and withholds the old response timestamp while loading', async () => {
    const user = userEvent.setup();
    mock.session.user.permissions = ['sms.read'];
    let settlePage!: (value: unknown) => void;
    const waiting = new Promise<unknown>((resolve) => {settlePage = resolve;});
    mock.request
      .mockResolvedValueOnce({rows: [], total: 0, limit: 25, offset: 25, next_offset: null})
      .mockReturnValueOnce(waiting);
    render(<MemoryRouter initialEntries={['/admin/sms-receipts?source=capture&status=received&offset=25&search=missing']}><SmsReceiptsPage /></MemoryRouter>);
    expect(await screen.findByText(/^Loaded .+ Kigali$/)).toBeVisible();
    await user.click(screen.getByRole('button', {name: 'Clear filters'}));
    expect(mock.request).toHaveBeenLastCalledWith('sms/receipts?limit=25&offset=0');
    expect(screen.getByRole('searchbox', {name: 'Search SMS receipts'})).toHaveValue('');
    expect(screen.queryByText(/^Loaded .+ Kigali$/)).not.toBeInTheDocument();
    settlePage({rows: [capture(1)], total: 1, limit: 25, offset: 0, next_offset: null});
    expect(await screen.findByText(/^Loaded .+ Kigali$/)).toBeVisible();
    expect(screen.getByRole('columnheader', {name: 'Masked contact'})).toBeVisible();
    expect(screen.getByRole('columnheader', {name: 'Conflicts'})).toBeVisible();
  });

  it('masks an extracted payer number and expands technical provenance on request', async () => {
    const user = userEvent.setup();
    mock.session.user.permissions = ['sms.read'];
    mock.session.user.financialModel = 'transaction_journals';
    const receipt = {
      ...receiver(1), payer_phone: '0788000123', payer_last3: '123', payer_last3_known: true,
      duplicate_reference_count: 0,
    };
    mock.request.mockResolvedValue({
      resource_type: 'sms_receipts', current_actor_id: mock.session.user.id, resource: receipt, can_extract: false,
      related: {duplicate_references: {rows: [], total: 0, limit: 25, offset: 0, next_offset: null}},
    });
    render(<MemoryRouter initialEntries={['/admin/sms-receipts/receiver/' + receipt.id]}>
      <Routes><Route path="/admin/sms-receipts/:kind/:id" element={<SmsReceiptDetailPage allowRecovery={false} />} /></Routes>
    </MemoryRouter>);
    expect(await screen.findByText('•••• 123')).toBeVisible();
    expect(screen.queryByText('0788000123')).not.toBeInTheDocument();
    const summary = screen.getByText('Technical provenance');
    expect(summary.closest('details')).not.toHaveAttribute('open');
    await user.click(summary);
    expect(summary.closest('details')).toHaveAttribute('open');
    expect(screen.getByText('a'.repeat(64))).toBeVisible();
  });

  it('sends legacy source, extraction and duplicate filters to the server and resets pagination', async () => {
    const user = userEvent.setup();
    mock.session.user.permissions = ['sms.read']; mock.session.user.financialModel = 'transaction_journals';
    mock.request.mockImplementation(async (path: string) => {
      const params = new URLSearchParams(path.split('?')[1]);
      return {rows: [], total: 0, limit: Number(params.get('limit')), offset: Number(params.get('offset')), next_offset: null};
    });
    render(<MemoryRouter initialEntries={['/admin/sms-receipts?offset=25']}><SmsReceiptsPage /></MemoryRouter>);
    expect(await screen.findByText('No records found')).toBeVisible();
    expect(screen.getByRole('button', {name: 'Previous'})).toBeVisible();
    expect(within(screen.getByLabelText('Source')).queryByRole('option', {name: 'Capture'})).not.toBeInTheDocument();
    expect(within(screen.getByLabelText('Status')).queryByRole('option', {name: 'Received'})).not.toBeInTheDocument();
    await user.selectOptions(screen.getByLabelText('Source'), 'receiver');
    await user.selectOptions(screen.getByLabelText('Extraction'), 'parsed');
    await user.selectOptions(screen.getByLabelText('Duplicate references'), 'conflicting');
    await waitFor(() => {
      const params = new URLSearchParams(String(mock.request.mock.calls.at(-1)?.[0]).split('?')[1]);
      expect(Object.fromEntries(params)).toMatchObject({limit: '25', offset: '0', source_kind: 'receiver', extraction_status: 'parsed', duplicates: 'conflicting'});
    });
    expect(screen.getByText('No records found')).toBeVisible();
  });

  it('sanitizes unsupported legacy filters and an invalid saved page size', async () => {
    mock.session.user.permissions = ['sms.read']; mock.session.user.financialModel = 'transaction_journals';
    mock.request.mockResolvedValue({rows: [], total: 0, limit: 25, offset: 0, next_offset: null});
    render(<MemoryRouter initialEntries={['/admin/sms-receipts?source=capture&status=received&limit=0&page=2']}><SmsReceiptsPage /></MemoryRouter>);
    expect(await screen.findByText('No records found')).toBeVisible();
    const params = new URLSearchParams(String(mock.request.mock.calls[0][0]).split('?')[1]);
    expect(Object.fromEntries(params)).toEqual({limit: '25', offset: '0'});
    expect(screen.getByLabelText('Source')).toHaveValue('');
    expect(screen.getByLabelText('Status')).toHaveValue('');
  });

  it('does not navigate beyond the backend offset limit', async () => {
    mock.session.user.permissions = ['sms.read'];
    mock.request.mockResolvedValue({rows: [capture(1), capture(2)], total: 2147483650, limit: 2, offset: 2147483646, next_offset: 2147483648});
    render(<MemoryRouter initialEntries={['/admin/sms-receipts?limit=2&offset=2147483646']}><SmsReceiptsPage /></MemoryRouter>);
    expect(await screen.findByText('Showing 2147483647–2147483648 of 2147483650')).toBeVisible();
    expect(screen.getByRole('button', {name: 'Next'})).toBeDisabled();
    expect(screen.getByRole('button', {name: 'Previous'})).toBeEnabled();
  });

  it('preserves old page and limit links through receipt detail and back', async () => {
    const user = userEvent.setup(), item = capture(3);
    mock.session.user.permissions = ['sms.read'];
    mock.request.mockImplementation(async (path: string) => {
      if (path.startsWith('sms/receipts/capture/')) return {resource_type: 'sms_receipts', resource: item,
        current_actor_id: mock.session.user.id, can_extract: false,
        related: {duplicate_references: {rows: [], total: 0, limit: 25, offset: 0, next_offset: null}}};
      const params = new URLSearchParams(path.split('?')[1]);
      const offset = Number(params.get('offset')), limit = Number(params.get('limit'));
      const rows = offset === 2 ? [item] : [capture(1), capture(2)];
      return {rows, total: 3, limit, offset, next_offset: offset + rows.length < 3 ? offset + rows.length : null};
    });
    const original = '/admin/sms-receipts?source=capture&extraction=not_extracted&page=2&limit=2&search=123456';
    render(<MemoryRouter initialEntries={[original]}><Routes>
      <Route path="/admin/sms-receipts" element={<SmsReceiptsPage />} />
      <Route path="/admin/sms-receipts/:kind/:id" element={<SmsReceiptDetailPage allowRecovery={false} />} />
    </Routes></MemoryRouter>);
    expect(await screen.findByText('Showing 3–3 of 3')).toBeVisible();
    expect(screen.getByText('Source metadata')).toBeVisible();
    const link = screen.getByRole('link', {name: /Capture · aaaaaaaa/});
    expect(new URL(link.getAttribute('href')!, 'https://admin.invalid').searchParams.get('returnTo')).toBe(original);
    await user.click(link);
    expect(await screen.findByText('Receipt details')).toBeVisible();
    await user.click(screen.getByRole('link', {name: /Back to records/}));
    expect(await screen.findByText('Showing 3–3 of 3')).toBeVisible();
    const params = new URLSearchParams(String(mock.request.mock.calls.at(-1)?.[0]).split('?')[1]);
    expect(Object.fromEntries(params)).toMatchObject({limit: '2', offset: '2', source_kind: 'capture', extraction_status: 'not_extracted', search: '123456'});
  });

  it('retains the filtered list return path when opening a related legacy duplicate', async () => {
    const user = userEvent.setup(), first = receiver(1), second = receiver(2);
    mock.session.user.permissions = ['sms.read']; mock.session.user.financialModel = 'transaction_journals';
    mock.request.mockImplementation(async (path: string) => {
      const current = path.includes(first.id) ? first : second, other = current.id === first.id ? second : first;
      return {resource_type: 'sms_receipts', resource: current, current_actor_id: mock.session.user.id, can_extract: false,
        related: {duplicate_references: {rows: [other], total: 1, limit: 25, offset: 0, next_offset: null}}};
    });
    const back = '/admin/sms-receipts?source=receiver&extraction=parsed&duplicates=all&page=2&limit=2';
    const entry = `/admin/sms-receipts/receiver/${first.id}?${new URLSearchParams({returnTo: back})}`;
    render(<MemoryRouter initialEntries={[entry]}><Routes><Route path="/admin/sms-receipts/:kind/:id" element={<SmsReceiptDetailPage allowRecovery={false} />} /></Routes></MemoryRouter>);
    const related = await screen.findByRole('link', {name: `Receiver · ${second.id}`});
    expect(new URL(related.getAttribute('href')!, 'https://admin.invalid').searchParams.get('returnTo')).toBe(back);
    await user.click(related);
    await waitFor(() => expect(mock.request).toHaveBeenCalledWith(`sms/receipts/receiver/${second.id}?limit=25&offset=0`));
    expect(screen.getByRole('link', {name: /Back to records/})).toHaveAttribute('href', back);
  });

  it.each([
    ['/admin/momo-receipts', '/admin/momo-receipts'],
    ['https://outside.invalid/path', '/admin/sms-receipts'],
    ['/admin/admin-users', '/admin/sms-receipts'],
  ])('keeps the canonical receipt return path restricted for %s', async (returnTo, expected) => {
    const item = capture(1);
    mock.session.user.permissions = ['sms.read'];
    mock.request.mockResolvedValue({resource_type: 'sms_receipts', resource: item, current_actor_id: mock.session.user.id,
      can_extract: false, related: {duplicate_references: {rows: [], total: 0, limit: 25, offset: 0, next_offset: null}}});
    const entry = `/admin/sms-receipts/capture/${item.id}?${new URLSearchParams({returnTo})}`;
    render(<MemoryRouter initialEntries={[entry]}><Routes><Route path="/admin/sms-receipts/:kind/:id" element={<SmsReceiptDetailPage allowRecovery={false} />} /></Routes></MemoryRouter>);
    expect(await screen.findByText('Receipt details')).toBeVisible();
    expect(screen.getByRole('link', {name: /Back to records/})).toHaveAttribute('href', expected);
  });

  it('discards an older response when the selected source filter changes', async () => {
    const user = userEvent.setup(); let resolveFirst: ((value: unknown) => void) | undefined;
    mock.session.user.permissions = ['sms.read'];
    mock.request.mockImplementation((path: string) => path.includes('source_kind=capture')
      ? Promise.resolve({rows: [capture(1, 'Current capture')], total: 1, limit: 25, offset: 0, next_offset: null})
      : new Promise(resolve => {resolveFirst = resolve;}));
    render(<MemoryRouter><SmsReceiptsPage /></MemoryRouter>);
    await waitFor(() => expect(resolveFirst).toBeDefined());
    await user.selectOptions(screen.getByLabelText('Source'), 'capture');
    expect(await screen.findByText('Current capture')).toBeVisible();
    await act(async () => {resolveFirst?.({rows: [capture(2, 'Old capture')], total: 1, limit: 25, offset: 0, next_offset: null});});
    expect(screen.queryByText('Old capture')).not.toBeInTheDocument();
    expect(screen.getByText('Current capture')).toBeVisible();
  });

  it('does not display rows that contradict a selected extraction or duplicate filter', async () => {
    mock.session.user.permissions = ['sms.read'];
    mock.request.mockResolvedValue({rows: [capture(1)], total: 1, limit: 25, offset: 0, next_offset: null});
    render(<MemoryRouter initialEntries={['/admin/sms-receipts?extraction=parsed&duplicates=all']}><SmsReceiptsPage /></MemoryRouter>);
    expect(await screen.findByText('The workspace response could not be verified.')).toBeVisible();
    expect(screen.queryByText('Captured user')).not.toBeInTheDocument();
  });

  it('shows the canonical empty result for a duplicate-only filter without inventing facts', async () => {
    mock.session.user.permissions = ['sms.read'];
    mock.request.mockResolvedValue({rows: [], total: 0, limit: 25, offset: 0, next_offset: null});
    render(<MemoryRouter initialEntries={['/admin/sms-receipts?duplicates=all']}><SmsReceiptsPage /></MemoryRouter>);
    expect(await screen.findByText('No records found')).toBeVisible();
    const params = new URLSearchParams(String(mock.request.mock.calls[0][0]).split('?')[1]);
    expect(params.get('duplicates')).toBe('all');
    expect(screen.queryByRole('table')).not.toBeInTheDocument();
  });
});
