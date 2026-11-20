import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { StrictMode } from 'react';
import { MemoryRouter } from 'react-router';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { parseMomoDetail, parseMomoMemberChecks, parseMomoPage, parseMomoSources, type MomoFilters } from '../../src/features/operations/momoContracts';

const mock = vi.hoisted(() => ({request: vi.fn(), session: {status: 'authenticated', epoch: 1, user: {id: '11111111-1111-1111-1111-111111111111', role: 'admin', permissions: ['payments.read'] as string[]}}}));
vi.mock('../../src/session/SessionProvider', async (importOriginal) => ({...await importOriginal<typeof import('../../src/session/SessionProvider')>(), useSession: () => ({...mock.session, request: mock.request})}));
import { MomoReceiptsPage } from '../../src/features/operations';

const id = '11111111-1111-4111-8111-111111111111', account = '22222222-2222-4222-8222-222222222222', smsId = '66666666-6666-4666-8666-666666666666';
const time = '2026-10-18T08:00:00.000Z';
const tx = {id, receiving_account_id: account, provider_transaction_id: 'MOMO-SYNTHETIC-001', recipient_name: 'Synthetic receiver', public_code: '123456', payer_name: 'Synthetic payer', payer_last3: '007', member_name: null, group_name: null, group_id: null, beneficiary_member_id: null, payment_id: null, amount_minor: 5000, has_conflict: 0, credited_amount_minor: 0, version: 1, currency: 'RWF', status: 'needs_allocation', transaction_at: time, created_at: time, provider_confirmation: false, settlement_status: 'not_asserted'};
const page = {contract_version: 1, currency: 'RWF', date_basis: 'provider_transaction_time', rows: [tx], total: 1, offset: 0, limit: 25, totals: {received_minor: 5000, credited_minor: 0, unallocated_minor: 5000}, as_of: time};
const filters: MomoFilters = {search: '', status: '', account: '', group: '', from: '', to: ''};
const source = {raw_sms_id: smsId, relation: 'accepted', outcome: 'accepted', parser_version: 'v1', created_at: time};
const detail = {transaction: tx, sources: [source], conflicting_attempt_ids: []};
const checkRow = {id, member_id: account, group_id: smsId, intent_id: id, member_public_id: '123456', member_name: 'Synthetic member', group_name: 'Synthetic group', expected_amount_minor: 5000, currency: 'RWF', requested_at: time, request_status: 'received', provider_reference: 'MOMO-SYNTHETIC-001', evidence_note: 'Please review', source: 'member_request', provider_reference_verified: false, financial_effects: 0};
const checks = {contract_version: 1, rows: [checkRow], total: 1, offset: 0, limit: 25, next_offset: null};
const job = {raw_sms_id: smsId, state: 'needs_review', binding_id: null, receiving_account_id: null, received_at: time, last_error: 'schema_mismatch'};
afterEach(() => {mock.request.mockReset(); mock.session.user.permissions = ['payments.read'];});

describe('MoMo read contracts', () => {
  it('validates totals, filtered scope, currency, statuses and receipt identity', () => {
    expect(parseMomoPage(page, 0, filters).rows[0].id).toBe(id);
    expect(() => parseMomoPage({...page, totals: {...page.totals, credited_minor: 5001}}, 0, filters)).toThrow();
    expect(() => parseMomoPage({...page, rows: [{...tx, provider_confirmation: true}]}, 0, filters)).toThrow();
    expect(() => parseMomoPage({...page, rows: [{...tx, provider_confirmation: undefined, settlement_status: undefined}]}, 0, filters)).toThrow();
    expect(() => parseMomoPage(page, 0, {...filters, account: id})).toThrow();
    expect(() => parseMomoPage(page, 0, {...filters, status: 'credited'})).toThrow();
    expect(() => parseMomoPage(page, 0, {...filters, from: '2026-10-19T00:00:00.000Z'})).toThrow();
    expect(() => parseMomoPage({...page, rows: [{...tx, currency: 'USD'}]}, 0, filters)).toThrow();
    expect(() => parseMomoPage({...page, rows: [{...tx, transaction_at: '2026-02-30T08:00:00.000Z'}]}, 0, filters)).toThrow();
    expect(() => parseMomoPage({...page, rows: [{...tx, status: 'credited'}]}, 0, filters)).toThrow();
  });
  it('verifies transaction detail and keeps source jobs distinct from payments', () => {
    expect(parseMomoDetail(detail, id).sources[0].raw_sms_id).toBe(smsId);
    expect(() => parseMomoDetail(detail, account)).toThrow();
    expect(() => parseMomoDetail({...detail, sources: [{...source, relation: 'invented'}]}, id)).toThrow();
    const jobs = {rows: [job], total: 1, limit: 25, offset: 0};
    expect(parseMomoSources(jobs, 0, 'needs_review').rows[0].raw_sms_id).toBe(smsId);
    expect(() => parseMomoSources(jobs, 0, 'retry')).toThrow();
    expect(() => parseMomoSources({...jobs, rows: [{...job, binding_id: 'invalid'}]}, 0, 'needs_review')).toThrow();
    expect(parseMomoMemberChecks(checks, 0).rows[0].source).toBe('member_request');
    expect(() => parseMomoMemberChecks({...checks, rows: [{...checkRow, provider_reference_verified: true}]}, 0)).toThrow();
    expect(() => parseMomoMemberChecks({...checks, rows: [{...checkRow, financial_effects: 1}]}, 0)).toThrow();
  });
});

describe('MoMo receipts page', () => {
  it('can open the transaction view first and can restrict the route to transactions', async () => {
    mock.session.user.permissions = ['payments.read', 'sms.read']; mock.request.mockResolvedValue(page);
    const view = render(<MemoryRouter><MomoReceiptsPage initialView="transactions" transactionsOnly /></MemoryRouter>);
    expect(await screen.findByText('MOMO-SYNTHETIC-001')).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Incoming SMS'})).not.toBeInTheDocument();
    expect(mock.request.mock.calls.every(([path]) => typeof path === 'string' && path.startsWith('momo/transactions?'))).toBe(true);
    view.unmount(); mock.request.mockClear();
    render(<MemoryRouter><MomoReceiptsPage initialView="transactions" /></MemoryRouter>);
    expect(await screen.findByText('MOMO-SYNTHETIC-001')).toBeVisible(); expect(screen.getByRole('button', {name: 'Incoming SMS'})).toBeVisible();
  });
  it('does not fall back to SMS when a transactions-only route lacks payment permission', () => {
    mock.session.user.permissions = ['sms.read']; render(<MemoryRouter><MomoReceiptsPage initialView="transactions" transactionsOnly /></MemoryRouter>);
    expect(screen.getByText('Your current account cannot open these records.')).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Incoming SMS'})).not.toBeInTheDocument(); expect(mock.request).not.toHaveBeenCalled();
  });
  it('reads only permitted transactions, shows measured totals and opens verified source history', async () => {
    const user = userEvent.setup();
    mock.request.mockImplementation(async (path: string) => path.startsWith('momo/transactions?') ? page : detail);
    render(<StrictMode><MemoryRouter><MomoReceiptsPage /></MemoryRouter></StrictMode>);
    expect(await screen.findByText('MOMO-SYNTHETIC-001')).toBeVisible();
    expect(screen.getByText(/Provider confirmation and settlement are not asserted/)).toBeVisible();
    expect(mock.request).toHaveBeenCalledTimes(1);
    expect(mock.request.mock.calls[0][0]).toContain('momo/transactions?');
    expect(screen.queryByRole('button', {name: 'Incoming SMS'})).not.toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Member checks'})).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', {name: 'MOMO-SYNTHETIC-001'}));
    const dialog = await screen.findByRole('dialog', {name: 'Payment details'});
    expect(await within(dialog).findByText(smsId)).toBeVisible();
    expect(within(dialog).getByText('Parsing does not confirm provider API settlement.')).toBeVisible();
    expect(mock.request).toHaveBeenLastCalledWith(`momo/transactions/${id}`);
  });
  it('never requests payments without permission or renders invalid data', async () => {
    mock.session.user.permissions = [];
    const {unmount} = render(<MemoryRouter><MomoReceiptsPage /></MemoryRouter>);
    expect(screen.getByText('Your current account cannot open these records.')).toBeVisible();
    expect(mock.request).not.toHaveBeenCalled();
    unmount();
    mock.session.user.permissions = ['payments.read'];
    mock.request.mockResolvedValue({...page, rows: [{...tx, has_conflict: 3}]});
    render(<MemoryRouter><MomoReceiptsPage /></MemoryRouter>);
    expect(await screen.findByText('The MoMo records could not be verified.')).toBeVisible();
    expect(screen.queryByText('MOMO-SYNTHETIC-001')).not.toBeInTheDocument();
  });
  it('shows captured SMS with an explicit return to MoMo when payment access is absent', async () => {
    mock.session.user.permissions = ['sms.read'];
    const epoch = Date.parse('2026-11-16T08:00:00.000Z') / 1000;
    const capture = {source_kind: 'capture', id, user_id: account, payee_id: null, source_sha256: 'a'.repeat(64), status: 'received', version: 1,
      received_at: epoch, created_at: epoch, public_id: '123456', display_name: null, transaction_id: null, evidence_level: 'client_received',
      source_fact_id: null, parser_version: null, extraction_status: 'not_extracted', source_body_sha256: null, source_payload_sha256: null, parsed_at: null,
      payer_name: null, payer_phone: null, payer_masked_phone: null, payer_last3: null, payee_momo_number: null, payee_momo_code: null,
      momo_transaction_reference: null, momo_timestamp_local: null, momo_timezone_offset: null, amount_rwf: null, wallet_balance_rwf: null,
      network: null, direction: null, is_payment: null, transaction_reference: null, duplicate_reference_count: 0, conflicting_reference_count: 0,
      provider_confirmation: false, settlement_status: 'not_asserted', timezone_known: false, payer_last3_known: false, source_content_reveal_required: true,
      received_at_device: '2026-11-16T10:00:00+02:00'};
    mock.request.mockResolvedValue({rows: [capture], total: 1, limit: 25, offset: 0, next_offset: null});
    render(<MemoryRouter><MomoReceiptsPage /></MemoryRouter>);
    const link = await screen.findByRole('link', {name: 'App user'});
    expect(link).toHaveAttribute('href', `/admin/sms-receipts/capture/${id}?returnTo=%2Fadmin%2Fmomo-receipts`);
    expect(screen.queryByRole('button', {name: 'Transactions'})).not.toBeInTheDocument();
    expect(mock.request.mock.calls.every(([path]) => typeof path === 'string' && path.startsWith('sms/receipts?'))).toBe(true);
  });
  it('provides separate attention source evidence only with SMS permission', async () => {
    const user = userEvent.setup();
    mock.session.user.permissions = ['payments.read', 'sms.read'];
    mock.request.mockImplementation(async (path: string) => path.startsWith('sms/receipts?') ? {rows: [], total: 0, offset: 0, limit: 25, next_offset: null} : path.startsWith('momo/transactions?') ? page : {rows: [job], total: 1, limit: 25, offset: 0});
    render(<MemoryRouter><MomoReceiptsPage /></MemoryRouter>);
    expect(await screen.findByText('No matching records')).toBeVisible();
    expect(mock.request.mock.calls[0][0]).toContain('source_kind=capture');
    await user.click(screen.getByRole('button', {name: 'Transactions'}));
    expect(await screen.findByText('MOMO-SYNTHETIC-001')).toBeVisible();
    await user.selectOptions(screen.getByLabelText('Payment status'), 'needs_attention');
    await user.click(screen.getByRole('button', {name: 'Apply filters'}));
    expect(await screen.findByText('Source messages needing attention')).toBeVisible();
    expect(await screen.findByText(smsId)).toBeVisible();
    expect(screen.getByText(/Unresolved source messages are not validated payments/)).toBeVisible();
    expect(mock.request.mock.calls.some(([path]) => typeof path === 'string' && path.startsWith('momo/sources?'))).toBe(true);
    await user.click(screen.getByRole('button', {name: smsId}));
    const sourceDialog = screen.getByRole('dialog', {name: 'Source message'});
    expect(within(sourceDialog).getByText('schema_mismatch')).toBeVisible();
    expect(within(sourceDialog).getByText('Not recorded')).toBeVisible();
    expect(within(sourceDialog).queryByRole('button', {name: 'Review source access'})).not.toBeInTheDocument();
  });
  it('checks member-supplied context only with all three permissions and searches its unverified reference', async () => {
    const user = userEvent.setup();
    mock.session.user.permissions = ['payments.read', 'users.read', 'collections.read'];
    mock.request.mockImplementation(async (path: string) => path.startsWith('momo/transactions/payment-checks?') ? checks : page);
    render(<MemoryRouter><MomoReceiptsPage /></MemoryRouter>);
    await screen.findByText('MOMO-SYNTHETIC-001');
    await user.click(screen.getByRole('button', {name: 'Member checks'}));
    const dialog = await screen.findByRole('dialog', {name: 'Member payment checks'});
    expect(await within(dialog).findByText('Synthetic member')).toBeVisible();
    expect(within(dialog).getByText(/References and notes are unverified/)).toBeVisible();
    expect(mock.request).toHaveBeenLastCalledWith('momo/transactions/payment-checks?limit=25&offset=0');
    await user.click(within(dialog).getByRole('button', {name: 'Search reference'}));
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(screen.getByLabelText('Search MoMo TX ID or payer')).toHaveValue('MOMO-SYNTHETIC-001');
    await vi.waitFor(() => expect(mock.request.mock.calls.some(([path]) => typeof path === 'string' && path.includes('search=MOMO-SYNTHETIC-001'))).toBe(true));
  });
  it('applies inclusive Kigali date boundaries to the transaction endpoint', async () => {
    const user = userEvent.setup();
    mock.request.mockResolvedValue(page);
    render(<MemoryRouter><MomoReceiptsPage /></MemoryRouter>);
    await screen.findByText('MOMO-SYNTHETIC-001');
    await user.type(screen.getByLabelText('From · Kigali'), '2026-10-18');
    await user.type(screen.getByLabelText('To · Kigali'), '2026-10-18');
    await user.click(screen.getByRole('button', {name: 'Apply filters'}));
    await screen.findByText('MOMO-SYNTHETIC-001');
    const requested = String(mock.request.mock.calls.at(-1)?.[0]);
    const params = new URLSearchParams(requested.split('?')[1]);
    expect(params.get('from')).toBe('2026-10-17T22:00:00.000Z');
    expect(params.get('to')).toBe('2026-10-18T21:59:59.999Z');
  });
});
