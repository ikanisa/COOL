import {BuriError, requireThat} from './errors.js';
import {pgInteger} from './postgres-values.js';
import {normalizePhone} from './values.js';

// Collect stores canonical MoMo routes in local 07... form; native DTOs require
// E.164. Normalize only the authoritative member reference, never payer evidence
// or the original SMS. Missing/masked member identity has no login-phone fallback.
function memberPhone(value, nullable = false) {
  if (nullable && (value == null || value === '')) return null;
  try {
    return normalizePhone(value);
  } catch {
    throw new BuriError('invalid_member_projection', 503);
  }
}

const POSTED_STATUSES = new Set(['reconciled', 'confirmed']);
const TERMINAL_STATUSES = new Set(['reversed', 'corrected']);

function paymentState(row,native) {
  if (!native && (pgInteger(row.has_conflict) === 1 || row.source_conflict)) return 'conflict';
  if (TERMINAL_STATUSES.has(row.payment_status)) return row.payment_status;
  if (POSTED_STATUSES.has(row.payment_status) && row.ledger_posted === true) return 'posted';
  if (native) return 'recorded';
  return row.allocation_state === 'unallocated' ? 'unallocated' : 'processing';
}

function ledgerState(row) {
  if (row.has_conflict != null && pgInteger(row.has_conflict) === 1) return 'conflict';
  if (TERMINAL_STATUSES.has(row.payment_status)) return row.payment_status;
  if (POSTED_STATUSES.has(row.payment_status)) return 'posted';
  if (row.allocation_state === 'unallocated') return 'unallocated';
  return row.payment_status ? 'processing' : null;
}

export function projectPayment(row) {
  const native = row.native_source_id != null;
  requireThat(typeof row.source_conflict === 'boolean', 'invalid_transaction_projection', 503);
  if (native) {
    requireThat(
      row.native_meta?.sourceId === row.native_source_id &&
      typeof row.native_meta.canReveal === 'boolean' &&
      ['successful', 'failed', 'pending', 'unknown'].includes(row.native_meta.outcome),
      'invalid_transaction_projection',
      503,
    );
  }
  const payment = {
    id: row.id,
    groupId: row.collection_id,
    payerNameRaw: row.payer_name ?? '',
    payerPhoneRaw: row.payer_identifier ?? '',
    amountRwf: row.amount_minor === null ? null : pgInteger(row.amount_minor),
    atRaw: row.transaction_datetime_raw ?? '',
    ftId: row.provider_transaction_id,
    state: paymentState(row, native),
    version: pgInteger(row.version),
    memberId: row.member_id ?? null,
    memberPhone: memberPhone(row.momo_number, true),
    sourceId: native ? (row.native_meta.canReveal ? row.native_source_id : null) : row.source_id ?? null,
  };
  if (!native) return payment;
  return {
    ...payment,
    direction: row.event_kind === 'incoming_receipt' ? 'incoming' :
      ['outgoing', 'reversal'].includes(row.event_kind) ? row.event_kind : 'other',
    outcome: row.native_meta.outcome,
    sourceKind: 'observation',
    feeRwf: row.fee_minor === null ? null : pgInteger(row.fee_minor),
    walletBalanceAfterRwf: row.wallet_balance_after_minor === null ? null : pgInteger(row.wallet_balance_after_minor),
  };
}

export function projectMember(row) {
  return {
    id: row.id,
    groupId: row.collection_id,
    name: row.full_name,
    phone: memberPhone(row.momo_number),
    balanceRwf: pgInteger(row.balance),
    active: pgInteger(row.active) === 1,
    version: pgInteger(row.revision),
  };
}

export function projectLedger(row) {
  return {
    id: row.id,
    groupId: row.collection_id,
    transactionId: row.transaction_id ?? null,
    amountRwf: pgInteger(row.amount_minor),
    atRaw: row.source_at ?? '',
    ftId: row.ft_id ?? '',
    payerNameRaw: row.payer_name ?? '',
    memberPhone: memberPhone(row.momo_number),
    state: ledgerState(row),
  };
}
