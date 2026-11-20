import type {FinancialModel} from '../core/types';

/** The legacy request service scopes reads to the current actor; canonical reads also require account.manage. */
export function canReadRequestHistory(model: FinancialModel, permissions: readonly string[]): boolean {
  return permissions.includes('overview.read') &&
    (model === 'transaction_journals' || model === 'canonical_evidence_ledger' && permissions.includes('account.manage'));
}
