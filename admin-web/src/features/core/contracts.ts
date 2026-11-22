import type { CoreArea, CorePage, DataRow, FinancialModel } from './types';

const idPattern = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const isoPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const decimalPattern = /^(?:0|[1-9]\d*)$/;

export const STATUSES: Record<FinancialModel, Record<CoreArea, readonly string[]>> = {
  canonical_evidence_ledger: {
    groups: ['active', 'suspended', 'archived'], users: ['active', 'suspended', 'deleted'],
    members: ['active', 'suspended', 'deleted'], payees: ['active', 'inactive'],
    transactions: ['recorded', 'reconciled', 'confirmed', 'ambiguous', 'corrected', 'reversed'],
    ledgers: ['contribution', 'reversal', 'correction'],
  },
  transaction_journals: {
    groups: ['draft', 'active', 'suspended', 'archived'], users: ['invited', 'active', 'suspended', 'closed', 'revoked'],
    members: ['invited', 'active', 'suspended', 'closed'], payees: ['active', 'inactive'],
    transactions: ['pending', 'confirmation_recorded', 'rejection_recorded', 'evidence_conflict'],
    ledgers: ['draft', 'posted'],
  },
};

export function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function isId(value: unknown): value is string {
  return typeof value === 'string' && idPattern.test(value);
}

export function isSafeCount(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

export function containsControl(value: string, includeSpace = false): boolean {
  return [...value].some(char => {
    const code = char.codePointAt(0)!;
    return code <= (includeSpace ? 0x20 : 0x1f) || code === 0x7f;
  });
}

function invalid(): never {
  throw new Error('The workspace response could not be verified.');
}

function isTimestamp(value: unknown): value is string {
  if (typeof value !== 'string' || !isoPattern.test(value)) return false;
  const date = new Date(value);
  return Number.isFinite(date.valueOf()) && date.toISOString() === value;
}

function exactMoney(value: unknown, signed = false): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && (signed || value >= 0);
}

function isPaymentReference(value: unknown): value is string {
  return typeof value === 'string' && value.length === 12 && /^[0-9]{12}$/.test(value);
}

export function formatMoney(value: unknown, signed = false): string {
  let integer: bigint;
  if (typeof value === 'number' && exactMoney(value, signed)) integer = BigInt(value);
  else if (typeof value === 'string' && (signed ? /^-?(?:0|[1-9]\d*)$/ : decimalPattern).test(value)) {
    integer = BigInt(value);
    if (integer > BigInt(Number.MAX_SAFE_INTEGER) || integer < -BigInt(Number.MAX_SAFE_INTEGER)) return 'Unavailable';
  } else return 'Unavailable';
  return `RWF ${new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(integer)}`;
}

/** Validate identity, window, visible facts and money before rendering server rows. */
export function parseCoreRow(area: CoreArea, model: FinancialModel, input: unknown): DataRow {
  if (!isObject(input) || !isId(input.id) || typeof input.title !== 'string' || !input.title.trim() ||
      typeof input.subtitle !== 'string' || typeof input.amount !== 'string' ||
      typeof input.status !== 'string' || !STATUSES[model][area].includes(input.status) ||
      input.country_code !== 'RW' || input.currency_code !== 'RWF' || !isTimestamp(input.created_at)) invalid();
  if (area === 'groups') {
    if (!isSafeCount(input.active_members) || input.amount !== `${input.active_members} members` ||
        typeof input.slug !== 'string' || typeof input.collection_type !== 'string' ||
        !['private', 'public_pending', 'public_approved'].includes(String(input.visibility))) invalid();
  }
  if (area === 'users' || area === 'members') {
    if (!isSafeCount(input.active_groups) || input.amount !== `${input.active_groups} groups` ||
        input.account_status !== input.status || !isSafeCount(input.total_contributed_rwf) ||
        typeof input.display_name_recorded !== 'boolean' ||
        (input.display_name_recorded ? typeof input.display_name !== 'string' || !input.display_name.trim() : input.display_name !== null) ||
        input.name_verification !== (input.display_name_recorded ? 'recorded_not_provider_verified' : 'not_recorded') ||
        typeof input.public_id !== 'string' || !/^\d{6}$/.test(input.public_id) || input.title !== input.public_id ||
        input.person_id !== input.id || (area === 'members' && input.active_groups === 0)) invalid();
    if (input.collect_user_id !== null && !isId(input.collect_user_id)) invalid();
    if (input.operator_admin_id !== null && !isId(input.operator_admin_id)) invalid();
    if (input.collect_user_id === null && input.operator_admin_id === null) invalid();
    if (input.id !== (input.collect_user_id ?? input.operator_admin_id)) invalid();
    if (input.momo_number !== null && (typeof input.momo_number !== 'string' || !/^07[2389]\d{7}$/.test(input.momo_number))) invalid();
    if (input.momo_pay_code !== null && (typeof input.momo_pay_code !== 'string' || !/^\d{4,9}$/.test(input.momo_pay_code))) invalid();
    if (model === 'canonical_evidence_ledger' && (input.posted_contributed_rwf !== null || input.contribution_basis !== 'reconciled_evidence_entries')) invalid();
    if (model === 'transaction_journals' && (!isSafeCount(input.posted_contributed_rwf) || input.posted_contributed_rwf > input.total_contributed_rwf || input.contribution_basis !== 'confirmation_recorded_allocations')) invalid();
  }
  if (area === 'payees') {
    if (!isId(input.group_id) || typeof input.group_name !== 'string' ||
        !['mtn_momo', 'airtel_money'].includes(String(input.network)) ||
        typeof input.momo_number_or_code !== 'string' || input.amount !== input.momo_number_or_code ||
        input.momo_number_or_code !== (input.momo_number ?? input.momo_pay_code) ||
        (input.momo_number === null) === (input.momo_pay_code === null)) invalid();
  }
  if (area === 'transactions') {
    if (!isId(input.group_id) || !isId(input.payee_id) || typeof input.group_name !== 'string' ||
        !exactMoney(input.amount_rwf) || input.amount_rwf <= 0 || !exactMoney(input.allocated_amount_rwf) ||
        input.allocated_amount_rwf > input.amount_rwf || input.amount !== String(input.amount_rwf) ||
        input.rail !== 'rwanda_momo' || input.provider_confirmation !== false || input.settlement_status !== 'not_asserted') invalid();
    const allocation = input.allocated_amount_rwf === input.amount_rwf ? 'allocated' : input.allocated_amount_rwf > 0 ? 'partial' : 'unallocated';
    if (input.allocation_status !== allocation) invalid();
    if (model === 'canonical_evidence_ledger' && input.payment_reference !== undefined && input.payment_reference !== null &&
        !isPaymentReference(input.payment_reference)) invalid();
    if (model === 'canonical_evidence_ledger' && (input.contribution_basis !== 'reconciled_evidence_entries' || !isId(input.evidence_id))) invalid();
  }
  if (area === 'ledgers') {
    if (!isId(input.group_id) || typeof input.group_name !== 'string') invalid();
    if (model === 'canonical_evidence_ledger') {
      if (!exactMoney(input.signed_amount_rwf, true) || input.signed_amount_rwf === 0 ||
          !exactMoney(input.amount_rwf) || input.amount_rwf !== Math.abs(input.signed_amount_rwf) ||
          input.amount !== String(input.signed_amount_rwf) || input.kind !== input.status ||
          input.provider_confirmation !== false || input.settlement_status !== 'not_asserted' ||
          input.contribution_basis !== 'reconciled_evidence_entries') invalid();
    } else if (!exactMoney(input.debit_rwf) || !exactMoney(input.credit_rwf) ||
        !isSafeCount(input.entry_count) || typeof input.balanced !== 'boolean' ||
        input.amount !== String(input.debit_rwf) ||
        input.balanced !== (input.entry_count >= 2 && input.debit_rwf > 0 && input.debit_rwf === input.credit_rwf)) invalid();
  }
  return input as DataRow;
}

export function parseCorePage(input: unknown, area: CoreArea, expectedModel: FinancialModel, limit: number, offset: number, status = ''): CorePage {
  if (!isObject(input) || !Array.isArray(input.rows) || !isSafeCount(input.total) ||
      !Number.isSafeInteger(limit) || limit < 1 || limit > 100 ||
      !Number.isSafeInteger(offset) || offset < 0 || offset > 2147483647) invalid();
  const canonical = input.contract_version !== undefined || input.model !== undefined;
  if (canonical ? input.contract_version !== 2 || input.model !== 'canonical_evidence_ledger' : expectedModel !== 'transaction_journals') invalid();
  if ((canonical ? 'canonical_evidence_ledger' : 'transaction_journals') !== expectedModel) invalid();
  const expectedKeys = canonical ? ['contract_version', 'model', 'rows', 'total'] : ['rows', 'total'];
  if (Object.keys(input).length !== expectedKeys.length || !expectedKeys.every(key => key in input) ||
      input.rows.length !== Math.min(limit, Math.max(0, input.total - offset))) invalid();
  const rows = input.rows.map(row => parseCoreRow(area, expectedModel, row));
  if (new Set(rows.map(row => row.id)).size !== rows.length || (status && rows.some(row => row.status !== status))) invalid();
  return { rows, total: input.total, model: expectedModel };
}

export function formatField(key: string, value: unknown): string {
  if (value === null || value === undefined || value === '') return 'Not recorded';
  if (key.endsWith('_rwf')) return formatMoney(value, key === 'signed_amount_rwf');
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'number') return Number.isSafeInteger(value) ? String(value) : 'Unavailable';
  if (typeof value === 'string') {
    if (key.endsWith('_at') && isTimestamp(value)) return new Intl.DateTimeFormat('en-GB', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Africa/Kigali' }).format(new Date(value));
    if (key === 'status' || key.endsWith('_status') || key === 'kind' || key === 'network' || key === 'member_type') return label(value);
    return value;
  }
  return 'Unavailable';
}

/** The SMS token identifies retained evidence, not a customer-facing payment reference. */
export function isInternalSmsReference(value: unknown): boolean {
  return typeof value === 'string' && /^sms:/i.test(value);
}

/** Use only the server's persisted reference; old or incomplete servers may omit it. */
export function paymentReference(row: Record<string, unknown>): string {
  if (isPaymentReference(row.payment_reference)) return row.payment_reference;
  return isInternalSmsReference(row.title) ? 'Not available' : formatField('title', row.title);
}

export function evidenceReference(value: unknown): string {
  return isInternalSmsReference(value) ? 'Source identifier retained' : formatField('reference', value);
}

export function label(value: string): string {
  return value.replaceAll('_', ' ').replace(/\b\w/g, char => char.toUpperCase());
}
