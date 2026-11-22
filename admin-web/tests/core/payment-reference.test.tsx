import { webcrypto } from 'node:crypto';
import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import coreFixture from './canonical-core-fixtures.json';
import reconciliationFixture from './canonical-reconciliation-fixture.json';
import { CoreListPage } from '../../src/features/core/CoreListPage';
import { CoreRecordPage } from '../../src/features/core/CoreRecordPage';
import { TransactionReversePage } from '../../src/features/core/TransactionReversePage';
import { parseCoreRow } from '../../src/features/core/contracts';
import type { FeatureAccess } from '../../src/features/core/types';
import { ReconciliationDetailPage, ReconciliationQueuePage } from '../../src/features/reconciliation';
import { parseReconciliationDetail } from '../../src/features/reconciliation/contracts';
import { actor as legacyActor, paged, payment as legacyPayment } from '../reconciliation/legacy-fixture';

const internalReference = `sms:${'a'.repeat(64)}:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`;
const otherInternalReference = `sms:${'b'.repeat(64)}:bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`;
const reference = '100000000123';
const actorId = reconciliationFixture.detail.current_actor_id;
const principalId = reconciliationFixture.detail.current_principal_id;
const base: Omit<FeatureAccess, 'request'> = {
  actorId, principalId, authorityKey: 'reference-test', role: 'admin',
  permissions: ['payments.read', 'reconciliations.read', 'reconciliations.propose', 'reconciliations.review', 'ledger.read'],
  financialModel: 'canonical_evidence_ledger', navigate: vi.fn(),
};

function corePage(paymentReference?: string | null) {
  return {...coreFixture.transactions, rows: [{...coreFixture.transactions.rows[0], title: internalReference,
    provider_reference: internalReference, ...(paymentReference === undefined ? {} : {payment_reference: paymentReference})}]};
}

function reconciliationDetail(paymentReference?: string | null) {
  const data = structuredClone(reconciliationFixture.detail);
  return {...data, resource: {...data.resource, title: internalReference, provider_reference: internalReference,
    ...(paymentReference === undefined ? {} : {payment_reference: paymentReference})},
  related: {...data.related, evidence: {...data.related.evidence,
    rows: data.related.evidence.rows.map(row => ({...row, reference: internalReference}))}}};
}

describe('persisted payment references', () => {
  it('validates the optional server field without changing the source identifier or coercing its digits', () => {
    const row = corePage('000000000123').rows[0];
    expect(parseCoreRow('transactions', 'canonical_evidence_ledger', row)).toMatchObject({
      payment_reference: '000000000123', title: internalReference, provider_reference: internalReference,
    });
    expect(parseCoreRow('transactions', 'canonical_evidence_ledger', corePage().rows[0]).title).toBe(internalReference);
    expect(parseCoreRow('transactions', 'canonical_evidence_ledger', corePage(null).rows[0]).payment_reference).toBeNull();
    for (const value of [123456789012, '12345678901', '1234567890123', ' 123456789012', '１２３４５６７８９０１２', '123456789012\n']) {
      expect(() => parseCoreRow('transactions', 'canonical_evidence_ledger', {...row, payment_reference: value})).toThrow();
    }
  });

  it('uses the server reference for the payment list, search, accessible name and UUID-based navigation', async () => {
    const page = corePage(reference), request = vi.fn(async (_path: string) => page), navigate = vi.fn();
    render(<CoreListPage {...base} request={request} navigate={navigate} area="transactions" locationSearch={`?search=${reference}`} />);
    fireEvent.click(await screen.findByRole('button', {name: `View ${reference}`}));
    expect(screen.getByText(reference)).toBeVisible();
    expect(document.body.textContent).not.toContain(internalReference);
    expect(new URLSearchParams(request.mock.calls[0][0].split('?')[1]).get('search')).toBe(reference);
    const query = new URLSearchParams({returnTo: `/admin/transactions?search=${reference}`});
    expect(navigate).toHaveBeenCalledWith(`/admin/transactions/${page.rows[0].id}?${query}`);
  });

  it.each([undefined, null])('shows unavailable for an SMS source when the real field is %s', async missing => {
    const page = corePage(missing), request = vi.fn(async () => page);
    render(<CoreListPage {...base} request={request} area="transactions" />);
    expect(await screen.findByText('Not available')).toBeVisible();
    expect(screen.getByRole('button', {name: 'View Not available'})).toBeVisible();
    expect(document.body.textContent).not.toContain(internalReference);
  });

  it('keeps a distinct existing reference when an older server has no new field', async () => {
    const page = corePage();
    page.rows[0].title = 'MOMO-RECORDED-123';
    const request = vi.fn(async () => page);
    render(<CoreListPage {...base} request={request} area="transactions" />);
    expect(await screen.findByText('MOMO-RECORDED-123')).toBeVisible();
  });

  it('shows the persisted reference in transaction details without changing the requested UUID', async () => {
    const row = corePage(reference).rows[0];
    const request = vi.fn(async (_path: string) => ({contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'transactions',
      resource: row, current_actor_id: actorId, can_manage: false, related: {}, related_truncated: false}));
    render(<CoreRecordPage {...base} request={request} area="transactions" id={row.id} />);
    expect(await screen.findByText(reference)).toBeVisible();
    expect(request.mock.calls[0][0]).toBe(`operations/transactions/${row.id}`);
    expect(document.body.textContent).not.toContain(internalReference);
  });

  it('uses the same reference and server-side search in the reconciliation queue', async () => {
    const page = {...reconciliationFixture.queue, rows: reconciliationFixture.queue.rows.map(row => ({...row,
      title: internalReference, provider_reference: internalReference, payment_reference: reference}))};
    const request = vi.fn(async (_path: string) => page), navigate = vi.fn();
    render(<ReconciliationQueuePage {...base} request={request} navigate={navigate} locationSearch={`?search=${reference}`} />);
    fireEvent.click(await screen.findByRole('button', {name: `View ${reference}`}));
    expect(new URLSearchParams(request.mock.calls[0][0].split('?')[1]).get('search')).toBe(reference);
    const query = new URLSearchParams({returnTo: `/admin/reconciliations?search=${reference}`});
    expect(navigate).toHaveBeenCalledWith(`/admin/reconciliations/${page.rows[0].id}?${query}`);
    expect(document.body.textContent).not.toContain(internalReference);
  });

  it('keeps legacy provider references unchanged', async () => {
    const request = vi.fn(async () => paged([legacyPayment]));
    render(<ReconciliationQueuePage {...base} actorId={legacyActor} principalId={null} financialModel="transaction_journals" request={request} />);
    expect(await screen.findByText(legacyPayment.provider_reference)).toBeVisible();
  });

  it('separates payment and evidence references in reconciliation detail while preserving the original data', async () => {
    const data = reconciliationDetail(reference), request = vi.fn(async () => data);
    const parsed = parseReconciliationDetail(data, 'canonical_evidence_ledger', data.resource.id, actorId, principalId, base.permissions, 'admin');
    expect(parsed.resource.provider_reference).toBe(internalReference);
    expect(parsed.related.evidence.rows[0].reference).toBe(internalReference);
    render(<ReconciliationDetailPage {...base} request={request} id={data.resource.id} />);
    expect(await screen.findByText(reference)).toBeVisible();
    expect(screen.getAllByText('Source identifier retained')).toHaveLength(2);
    expect(screen.getAllByText('Evidence reference').length).toBeGreaterThan(0);
    expect(document.body.textContent).not.toContain(internalReference);
  });

  it('keeps SMS evidence private from reference fields while a real payment reference is unavailable', async () => {
    const data = reconciliationDetail(null), request = vi.fn(async () => data);
    render(<ReconciliationDetailPage {...base} request={request} id={data.resource.id} />);
    expect(await screen.findByText('Not available')).toBeVisible();
    expect(screen.getAllByText('Source identifier retained')).toHaveLength(2);
    expect(document.body.textContent).not.toContain(internalReference);
  });

  it('continues to show a distinct recorded non-SMS evidence reference', async () => {
    const original = reconciliationDetail(reference), recorded = 'RECORDED-PROVIDER-REFERENCE';
    const data = {...original, resource: {...original.resource, provider_reference: recorded},
      related: {...original.related, evidence: {...original.related.evidence,
        rows: original.related.evidence.rows.map(row => ({...row, reference: recorded}))}}};
    render(<ReconciliationDetailPage {...base} request={vi.fn(async () => data)} id={data.resource.id} />);
    expect(await screen.findByText(reference)).toBeVisible();
    expect(screen.getAllByText(recorded)).toHaveLength(2);
  });

  it('still rejects a reversal when the underlying evidence changes but the visible payment reference does not', async () => {
    const priorCrypto = Object.getOwnPropertyDescriptor(globalThis, 'crypto'), priorLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
    Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true});
    Object.defineProperty(navigator, 'locks', {value: {request: async (_: string, __: unknown, fn: (lock: object) => unknown) => fn({})}, configurable: true});
    sessionStorage.clear();
    try {
      const data = reconciliationFixture.after, row = data.resource, entry = data.related.ledger_entries.rows[0];
      const identity = {id: data.current_actor_id, sessionId: 'reference-test', email: 'operator@example.test', role: 'admin' as const,
        permissions: ['payments.read', 'payments.reconcile', 'ledger.read', 'overview.read', 'account.manage'], expiresAt: '2100-01-01T00:00:00.000Z'};
      let reads = 0, writes = 0;
      const request = vi.fn(async (_path: string, options?: {method?: string}) => {
        if (options?.method) {writes++; throw new Error('Unexpected write');}
        const raw = reads++ === 0 ? internalReference : otherInternalReference;
        return {contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'transactions',
          resource: {...row, title: raw, provider_reference: raw, payment_reference: reference}, current_actor_id: identity.id,
          can_manage: true, allowed_operations: ['reverseTransaction'], related: {ledger_entries: [entry]},
          related_pages: {ledger_entries: {total: 1, limit: 100, offset: 0, next_offset: null}}, related_truncated: false};
      });
      render(<TransactionReversePage {...base} actorId={identity.id} principalId={data.current_principal_id} permissions={identity.permissions}
        request={request} id={row.id} identity={identity} allowMutations verifyFresh={async () => true} />);
      fireEvent.change(await screen.findByLabelText('Reason for reversal'), {target: {value: 'Reverse reviewed contribution'}});
      fireEvent.click(screen.getByRole('button', {name: 'Review reversal'}));
      expect(screen.getByText(new RegExp(`Reference: ${reference}`))).toBeVisible();
      expect(document.body.textContent).not.toContain(internalReference);
      fireEvent.click(screen.getByRole('checkbox'));
      fireEvent.click(screen.getByRole('button', {name: 'Confirm reversal'}));
      expect(await screen.findByText(/No reversal was submitted/i)).toBeVisible();
      expect(writes).toBe(0);
    } finally {
      if (priorCrypto) Object.defineProperty(globalThis, 'crypto', priorCrypto);
      if (priorLocks) Object.defineProperty(navigator, 'locks', priorLocks); else Reflect.deleteProperty(navigator, 'locks');
      sessionStorage.clear();
    }
  });
});
