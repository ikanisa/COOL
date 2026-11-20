import type {JsonObject} from '../../api/client';
import type {FinancialModel} from '../core/types';

const sharedCounts: Record<string, string> = {
  users: 'Users', groups: 'Groups', active_members: 'Active members', payees: 'Payees',
  transactions: 'Transactions', app_users: 'App users', direct_users: 'Direct users',
  admin_users: 'Admin users', staff_users: 'Staff users', active_payees: 'Active payees',
  unallocated_transactions: 'Unallocated transactions',
};
const countsByModel: Record<FinancialModel, Record<string, string>> = {
  canonical_evidence_ledger: {...sharedCounts, ledger_entries: 'Ledger entries',
    reversed_entries: 'Reversal entries', payment_evidence: 'Retained payment evidence'},
  transaction_journals: {...sharedCounts, draft_journals: 'Draft journals',
    posted_journals: 'Posted journals', sms_receipts: 'SMS receipts',
    receipts_needing_review: 'Receipts needing review'},
};
const amountsByModel: Record<FinancialModel, Record<string, string>> = {
  canonical_evidence_ledger: {total_recorded_rwf: 'Recorded evidence amount',
    total_reconciled_rwf: 'Reconciled evidence amount', total_unallocated_rwf: 'Unallocated evidence amount',
    total_net_contributions_rwf: 'Net recorded contributions'},
  transaction_journals: {total_collected_rwf: 'Total collected', total_allocated_rwf: 'Total allocated',
    total_unallocated_rwf: 'Total unallocated', total_posted_contributions_rwf: 'Posted contributions'},
};

function object(value: unknown): value is JsonObject {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value: JsonObject, keys: readonly string[]): boolean {
  return Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

export interface OverviewMetric {key: string; label: string; value: string; monetary: boolean}
export interface OverviewData {measuredAt: string; metrics: OverviewMetric[]; model: FinancialModel}

/** Validate the server's model, basis and exact metrics before presenting totals. */
export function parseOverview(input: unknown, model: FinancialModel): OverviewData {
  if (!object(input)) throw new Error('The workspace totals could not be verified.');
  const canonical = model === 'canonical_evidence_ledger';
  const fields = ['country_code', 'measured_at', 'counts', 'amounts', 'metrics',
    'contribution_basis', 'collected_basis', 'reconciliations_available',
    ...(canonical ? ['contract_version', 'model'] : [])];
  if (!exactKeys(input, fields) || input.country_code !== 'RW' ||
      typeof input.measured_at !== 'string' ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(input.measured_at) ||
      !Number.isFinite(Date.parse(input.measured_at)) ||
      new Date(input.measured_at).toISOString() !== input.measured_at ||
      !object(input.counts) || !object(input.amounts) || !Array.isArray(input.metrics) ||
      typeof input.reconciliations_available !== 'boolean' ||
      (canonical && (input.contract_version !== 2 || input.model !== model ||
        input.reconciliations_available !== true)) ||
      input.contribution_basis !== (canonical ? 'reconciled_evidence_entries' : 'confirmation_recorded_allocations') ||
      input.collected_basis !== (canonical ? 'retained_received_evidence' : 'confirmation_recorded_transactions')) {
    throw new Error('The workspace totals could not be verified.');
  }
  const counts = input.counts, amounts = input.amounts;
  const countLabels = countsByModel[model], amountLabels = amountsByModel[model];
  if (!exactKeys(counts, Object.keys(countLabels)) || !exactKeys(amounts, Object.keys(amountLabels)) ||
      Object.values(counts).some((value) => !Number.isSafeInteger(value) || (value as number) < 0) ||
      Object.values(amounts).some((value) => typeof value !== 'string' || !/^(0|[1-9][0-9]*)$/.test(value))) {
    throw new Error('The workspace totals could not be verified.');
  }
  const labels = {...countLabels, ...amountLabels};
  if (input.metrics.length !== Object.keys(labels).length) throw new Error('The workspace totals could not be verified.');
  const seen = new Set<string>();
  for (const entry of input.metrics) {
    if (!object(entry) || !exactKeys(entry, ['key', 'label', 'status', 'value']) ||
        typeof entry.key !== 'string' || !Object.hasOwn(labels, entry.key) || seen.has(entry.key) ||
        entry.label !== labels[entry.key] || entry.status !== 'measured' || typeof entry.value !== 'string' ||
        entry.value !== String(counts[entry.key] ?? amounts[entry.key])) {
      throw new Error('The workspace totals could not be verified.');
    }
    seen.add(entry.key);
  }
  return {measuredAt: input.measured_at, model, metrics: Object.entries(labels).map(([key, label]) => ({
    key, label, value: String(counts[key] ?? amounts[key]), monetary: Object.hasOwn(amountLabels, key),
  }))};
}

export function formatOverviewValue(metric: OverviewMetric): string {
  const value = BigInt(metric.value).toLocaleString('en-US');
  return metric.monetary ? `RWF ${value}` : value;
}
