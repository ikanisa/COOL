import { describe, expect, it } from 'vitest';
import fixture from './canonical-core-fixtures.json';
import reconciliationFixture from './canonical-reconciliation-fixture.json';
import { formatMoney, parseCorePage } from '../../src/features/core/contracts';
import { parseReconciliationDetail, parseReconciliationPage } from '../../src/features/reconciliation/contracts';
import type { CoreArea } from '../../src/features/core/types';

describe('core records', () => {
  it('accepts the existing synthetic canonical DTOs for all six areas', () => {
    for (const area of ['groups', 'users', 'members', 'payees', 'transactions', 'ledgers'] as const satisfies readonly CoreArea[]) {
      const parsed = parseCorePage(fixture[area], area, 'canonical_evidence_ledger', 25, 0);
      expect(parsed.total).toBe(fixture[area].total);
      expect(parsed.rows).toHaveLength(fixture[area].rows.length);
    }
  });

  it('refuses duplicate records, model confusion, incorrect window and invented settlement', () => {
    const duplicate = structuredClone(fixture.transactions);
    duplicate.rows.push(structuredClone(duplicate.rows[0]));
    duplicate.total = 2;
    expect(() => parseCorePage(duplicate, 'transactions', 'canonical_evidence_ledger', 25, 0)).toThrow();
    expect(() => parseCorePage(fixture.transactions, 'transactions', 'transaction_journals', 25, 0)).toThrow();
    expect(() => parseCorePage({ ...fixture.transactions, total: 2 }, 'transactions', 'canonical_evidence_ledger', 25, 0)).toThrow();
    const settled = structuredClone(fixture.transactions);
    settled.rows[0].settlement_status = 'settled';
    expect(() => parseCorePage(settled, 'transactions', 'canonical_evidence_ledger', 25, 0)).toThrow();
  });

  it('refuses over-allocation and unsafe numeric amounts', () => {
    const overallocated = structuredClone(fixture.transactions);
    overallocated.rows[0].allocated_amount_rwf = overallocated.rows[0].amount_rwf + 1;
    expect(() => parseCorePage(overallocated, 'transactions', 'canonical_evidence_ledger', 25, 0)).toThrow();
    expect(formatMoney(Number.MAX_SAFE_INTEGER + 1)).toBe('Unavailable');
    expect(formatMoney('9007199254740992')).toBe('Unavailable');
    expect(formatMoney('1000')).toBe('RWF 1,000');
    expect(formatMoney(-1000, true)).toBe('RWF -1,000');
  });

  it('refuses missing recorded names and accepts a valid reversal ledger', () => {
    const broken = structuredClone(fixture.users);
    broken.rows[0].display_name_recorded = false;
    expect(() => parseCorePage(broken, 'users', 'canonical_evidence_ledger', 25, 0)).toThrow();
    expect(parseCorePage(fixture.reversal_ledger, 'ledgers', 'canonical_evidence_ledger', 25, 0).rows[0].status).toBe('reversal');
  });
});

describe('reconciliation contract', () => {
  const transaction = fixture.transactions.rows[0];
  const page = { ...fixture.transactions, limit: 25, offset: 0, next_offset: null };
  const actorId = '11111111-1111-4111-8111-111111111111';
  const principalId = '22222222-2222-4222-8222-222222222222';
  const blank = () => ({ rows: [], total: 0, limit: 25, offset: 0, next_offset: null });
  const detail = () => ({
    contract_version: 2, model: 'canonical_evidence_ledger', resource_type: 'reconciliations',
    resource: transaction, current_actor_id: actorId, current_principal_id: principalId,
    can_propose: false, can_review: false,
    group_state: { id: transaction.group_id, status: 'active', version: 1, receiver: { momo_number_or_code: '0788123456', network: 'mtn_momo', label: 'Recorded receiver' } },
    related: { evidence: blank(), proposals: blank(), ledger_entries: blank() },
  });

  it('validates the queue window and independent evidence model', () => {
    expect(parseReconciliationPage(page, 'canonical_evidence_ledger', 25, 0).rows).toHaveLength(1);
    expect(() => parseReconciliationPage({ ...page, next_offset: 1 }, 'canonical_evidence_ledger', 25, 0)).toThrow();
    expect(() => parseReconciliationPage(page, 'canonical_evidence_ledger', 25, 0, 'recorded')).toThrow();
  });

  it('requires the active actor, principal and server-granted review authority', () => {
    const permissions = ['reconciliations.read', 'ledger.read'];
    expect(parseReconciliationDetail(detail(), 'canonical_evidence_ledger', transaction.id, actorId, principalId, permissions, 'admin').resource.id).toBe(transaction.id);
    expect(() => parseReconciliationDetail(detail(), 'canonical_evidence_ledger', transaction.id, actorId, actorId, permissions, 'admin')).toThrow();
    const unauthorized = { ...detail(), can_review: true };
    expect(() => parseReconciliationDetail(unauthorized, 'canonical_evidence_ledger', transaction.id, actorId, principalId, permissions, 'admin')).toThrow();
    expect(() => parseReconciliationDetail(unauthorized, 'canonical_evidence_ledger', transaction.id, actorId, principalId, [...permissions, 'reconciliations.review'], 'staff')).toThrow();
  });

  it('accepts receiver pay codes while rejecting malformed identities', () => {
    const response = structuredClone(reconciliationFixture.detail);
    response.group_state.receiver.momo_number_or_code = '41258';
    response.related.proposals.rows[0].receiver_identity.momo_number_or_code = '0041258';
    const actor = response.current_actor_id, principal = response.current_principal_id;
    const grants = ['ledger.read', 'reconciliations.read', 'reconciliations.propose', 'reconciliations.review'];
    expect(parseReconciliationDetail(response, 'canonical_evidence_ledger', response.resource.id, actor, principal, grants, 'admin').resource.id).toBe(response.resource.id);
    response.group_state.receiver.momo_number_or_code = '123';
    expect(() => parseReconciliationDetail(response, 'canonical_evidence_ledger', response.resource.id, actor, principal, grants, 'admin')).toThrow();
    response.group_state.receiver.momo_number_or_code = '41258';
    response.related.proposals.rows[0].receiver_identity.momo_number_or_code = '1234567890';
    expect(() => parseReconciliationDetail(response, 'canonical_evidence_ledger', response.resource.id, actor, principal, grants, 'admin')).toThrow();
  });
});
