import {describe, expect, it} from 'vitest';
import {formatOverviewValue, parseOverview} from '../../src/features/overview/overview';

function canonicalFixture() {
  const labels = {
    users: 'Users', groups: 'Groups', active_members: 'Active members', payees: 'Payees',
    transactions: 'Transactions', app_users: 'App users', direct_users: 'Direct users',
    admin_users: 'Admin users', staff_users: 'Staff users', active_payees: 'Active payees',
    unallocated_transactions: 'Unallocated transactions', ledger_entries: 'Ledger entries',
    reversed_entries: 'Reversal entries', payment_evidence: 'Retained payment evidence',
  };
  const amountLabels = {total_recorded_rwf: 'Recorded evidence amount',
    total_reconciled_rwf: 'Reconciled evidence amount', total_unallocated_rwf: 'Unallocated evidence amount',
    total_net_contributions_rwf: 'Net recorded contributions'};
  const counts = Object.fromEntries(Object.keys(labels).map((key) => [key, 1]));
  const amounts = Object.fromEntries(Object.keys(amountLabels).map((key) => [key, '9007199254740993']));
  return {contract_version: 2, model: 'canonical_evidence_ledger', country_code: 'RW',
    measured_at: '2026-11-16T12:00:00.000Z', counts, amounts,
    contribution_basis: 'reconciled_evidence_entries', collected_basis: 'retained_received_evidence',
    reconciliations_available: true, metrics: Object.entries({...labels, ...amountLabels}).map(([key, label]) => ({
      key, label, status: 'measured', value: String(counts[key] ?? amounts[key]),
    }))};
}

describe('workspace overview contracts', () => {
  it('preserves exact recorded amount values without asserting provider settlement', () => {
    const result = parseOverview(canonicalFixture(), 'canonical_evidence_ledger');
    const amount = result.metrics.find((entry) => entry.key === 'total_net_contributions_rwf');
    expect(amount).toBeDefined();
    expect(formatOverviewValue(amount!)).toBe('RWF 9,007,199,254,740,993');
  });

  it('rejects a changed financial basis or inconsistent metric', () => {
    const invalid = canonicalFixture();
    invalid.contribution_basis = 'settled';
    expect(() => parseOverview(invalid, 'canonical_evidence_ledger')).toThrow(/could not be verified/);
    const mismatch = canonicalFixture();
    mismatch.metrics[0].value = '999';
    expect(() => parseOverview(mismatch, 'canonical_evidence_ledger')).toThrow(/could not be verified/);
  });
});
