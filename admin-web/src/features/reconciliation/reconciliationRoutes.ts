import {containsControl} from '../core/contracts';
import type {FinancialModel} from '../core/types';

export const queuePath = '/admin/reconciliations';
export const reconciliationPageSize = 25;

export function reconciliationStatuses(model: FinancialModel): readonly string[] {
  return model === 'canonical_evidence_ledger' ?
    ['recorded', 'ambiguous', 'reconciled', 'confirmed', 'corrected', 'reversed'] :
    ['pending', 'confirmation_recorded', 'evidence_conflict'];
}

export function safeReconciliationSearch(value: string): string {
  return value.length <= 200 && !containsControl(value) ? value : '';
}

export function reconciliationFilters(locationSearch: string, model: FinancialModel) {
  const query = new URLSearchParams(locationSearch);
  const status = query.get('status') ?? '';
  const page = Number(query.get('page') ?? 1);
  return {
    search: safeReconciliationSearch(query.get('search') ?? ''),
    status: reconciliationStatuses(model).includes(status) ? status : '',
    page: Number.isSafeInteger(page) && page >= 1 && page <= 85899346 ? page : 1,
  };
}

export function reconciliationQueueLocation(search: string, status: string, page: number): string {
  const query = new URLSearchParams();
  if (search) query.set('search', search);
  if (status) query.set('status', status);
  if (page > 1) query.set('page', String(page));
  const suffix = query.toString();
  return suffix ? `${queuePath}?${suffix}` : queuePath;
}

export function reconciliationReturnLocation(raw?: string | null): string {
  if (!raw || raw.length > 2000 || containsControl(raw, true) || raw.includes('\\') ||
      raw.includes('#') || !raw.startsWith('/') || raw.startsWith('//')) return queuePath;
  try {
    const url = new URL(raw, 'https://collect.invalid');
    const keys = [...url.searchParams.keys()];
    if (url.origin !== 'https://collect.invalid' || url.pathname !== queuePath || url.hash ||
        keys.some(key => !['search', 'status', 'page'].includes(key)) || new Set(keys).size !== keys.length) return queuePath;
    return `${url.pathname}${url.search}`;
  } catch {
    return queuePath;
  }
}
