import { z } from 'zod';
import type { Page } from './contracts';

const uuid = z.string().regex(/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/);
const nonNegative = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const text = z.string().min(1).max(2000).refine((value) => value.trim().length > 0);
const nullableText = text.nullish().transform((value) => value ?? null);
const nullableId = uuid.nullish().transform((value) => value ?? null);
const timestamp = z.iso.datetime({offset: true}).refine((value) => {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/.exec(value);
  if (!match || !Number.isFinite(Date.parse(value))) return false;
  const [, year, month, day, hour, minute, second] = match.map(Number);
  const calendar = new Date(0); calendar.setUTCFullYear(year, month - 1, day); calendar.setUTCHours(hour, minute, second, 0);
  return year >= 1 && calendar.getUTCFullYear() === year && calendar.getUTCMonth() === month - 1 && calendar.getUTCDate() === day && hour <= 23 && minute <= 59 && second <= 59;
});
export const momoStatuses = ['needs_attention', 'needs_allocation', 'awaiting_review', 'credited', 'needs_review', 'reversed'] as const;
export type MomoStatus = '' | typeof momoStatuses[number];
const transaction = z.object({
  id: uuid, receiving_account_id: uuid, provider_transaction_id: text, recipient_name: text, public_code: text,
  payer_name: nullableText, payer_last3: z.string().regex(/^[0-9]{3}$/).nullish().transform((value) => value ?? null),
  member_name: nullableText, group_name: nullableText, payment_id: nullableId, beneficiary_member_id: nullableId, group_id: nullableId,
  amount_minor: nonNegative.min(1), credited_amount_minor: nonNegative, version: nonNegative.min(1),
  created_at: timestamp, transaction_at: timestamp.nullish().transform((value) => value ?? null), currency: z.literal('RWF'),
  status: z.enum(['needs_allocation', 'awaiting_review', 'credited', 'needs_review', 'reversed']), has_conflict: z.union([z.literal(0), z.literal(1)]),
  event_kind: z.enum(['incoming_receipt', 'reversal']).optional(), allocation_state: z.enum(['unallocated', 'linked', 'needs_review']).optional(),
  provider_confirmation: z.literal(false).optional(), settlement_status: z.literal('not_asserted').optional(),
}).superRefine((value, ctx) => {
  if (value.credited_amount_minor > value.amount_minor || value.status === 'credited' && (!value.payment_id || !value.credited_amount_minor) || value.status === 'awaiting_review' && !value.payment_id || (value.provider_confirmation === undefined) !== (value.settlement_status === undefined)) ctx.addIssue({code: 'custom', message: 'Invalid transaction relationships.'});
});
export type MomoTransaction = z.infer<typeof transaction>;
export interface MomoFilters {search: string; status: MomoStatus; account: string; group: string; from: string; to: string;}
export interface MomoPage extends Page<MomoTransaction> {totals: {received_minor: number; credited_minor: number; unallocated_minor: number}; asOf: string;}
const page = z.object({contract_version: z.literal(1), rows: z.array(transaction).max(25), total: nonNegative, offset: nonNegative.max(2147483647), limit: z.literal(25), currency: z.literal('RWF'), date_basis: z.literal('provider_transaction_time'), as_of: timestamp,
  totals: z.object({received_minor: nonNegative, credited_minor: nonNegative, unallocated_minor: nonNegative})});
function fail(): never {throw new Error('The MoMo records could not be verified.');}
export function parseMomoPage(value: unknown, offset: number, filters: MomoFilters): MomoPage {
  const data = page.parse(value);
  if (data.offset !== offset || data.rows.length !== Math.max(0, Math.min(25, data.total - offset)) || new Set(data.rows.map((row) => row.id)).size !== data.rows.length ||
      data.totals.credited_minor > data.totals.received_minor || data.totals.unallocated_minor > data.totals.received_minor || data.totals.credited_minor + data.totals.unallocated_minor > data.totals.received_minor) fail();
  for (const row of data.rows) {
    const matchesStatus = !filters.status || filters.status === 'needs_attention' && (row.has_conflict === 1 || ['needs_allocation', 'awaiting_review', 'needs_review'].includes(row.status)) || filters.status === 'needs_review' && (row.has_conflict === 1 || row.status === 'needs_review') || row.status === filters.status;
    const instant = row.transaction_at ? Date.parse(row.transaction_at) : null;
    if (row.provider_confirmation !== false || row.settlement_status !== 'not_asserted' || !matchesStatus || filters.account && row.receiving_account_id !== filters.account || filters.group && row.group_id !== filters.group || filters.from && (instant === null || instant < Date.parse(filters.from)) || filters.to && (instant === null || instant > Date.parse(filters.to))) fail();
  }
  return {rows: data.rows, total: data.total, limit: data.limit, offset, totals: data.totals, asOf: data.as_of};
}
const source = z.object({raw_sms_id: uuid, attempt_id: uuid.optional(), relation: z.enum(['accepted', 'duplicate', 'conflict']), outcome: text, parser_version: text, created_at: timestamp});
const detail = z.object({transaction, sources: z.array(source).max(100), conflicting_attempt_ids: z.array(uuid).max(101).optional()});
export type MomoDetail = z.infer<typeof detail>;
export function parseMomoDetail(value: unknown, id: string): MomoDetail {
  const data = detail.parse(value);
  if (data.transaction.id !== id || data.conflicting_attempt_ids && new Set(data.conflicting_attempt_ids).size !== data.conflicting_attempt_ids.length) fail();
  return data;
}
export const sourceStatuses = ['needs_review', 'source_unresolved', 'retry', 'completed'] as const;
export type SourceStatus = typeof sourceStatuses[number];
const job = z.object({raw_sms_id: uuid, state: z.enum(sourceStatuses), binding_id: uuid.nullable(), receiving_account_id: uuid.nullable(), received_at: timestamp, last_error: nullableText,
  body_sha256: z.string().regex(/^[a-f0-9]{64}$/).optional(), attempt_count: nonNegative.optional(),
  latest_attempt_id: uuid.nullable().optional(), latest_attempt_outcome: z.enum(['accepted', 'duplicate', 'conflict', 'non_payment', 'needs_review', 'retry', 'superseded']).nullable().optional()});
export type MomoSourceJob = z.infer<typeof job>;
export function parseMomoSources(value: unknown, offset: number, status: SourceStatus): Page<MomoSourceJob> {
  const data = z.object({rows: z.array(job).max(25), total: nonNegative, limit: z.literal(25), offset: nonNegative.max(2147483647)}).parse(value);
  if (data.offset !== offset || data.rows.length !== Math.max(0, Math.min(25, data.total - offset)) || data.rows.some((row) => row.state !== status) || new Set(data.rows.map((row) => row.raw_sms_id)).size !== data.rows.length) fail();
  return data;
}

const memberCheck = z.object({id: uuid, member_id: uuid, group_id: uuid, intent_id: uuid,
  member_public_id: text, member_name: text, group_name: text, expected_amount_minor: nonNegative.min(1),
  currency: z.literal('RWF'), requested_at: timestamp, request_status: z.literal('received'),
  provider_reference: z.string().max(160).nullable(), evidence_note: z.string().max(2000).nullable(),
  source: z.literal('member_request'), provider_reference_verified: z.literal(false), financial_effects: z.literal(0)});
export type MomoMemberCheck = z.infer<typeof memberCheck>;
export function parseMomoMemberChecks(value: unknown, offset: number): Page<MomoMemberCheck> {
  const data = z.object({contract_version: z.literal(1), rows: z.array(memberCheck).max(25), total: nonNegative, offset: nonNegative.max(2147483647), limit: z.literal(25), next_offset: nonNegative.nullable()}).parse(value);
  if (data.offset !== offset || data.rows.length !== Math.max(0, Math.min(25, data.total - offset)) || data.next_offset !== (offset + data.rows.length < data.total ? offset + data.rows.length : null) || new Set(data.rows.map((row) => row.id)).size !== data.rows.length) fail();
  return data;
}
