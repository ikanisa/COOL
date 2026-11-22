import { invalid, object, strictKeys, unavailable } from '../config.mjs';
import { pageQuery, readTool, schema } from './contracts.mjs';

const SMS_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const CAPTURE_STATUSES = ['received', 'under_review', 'rejected', 'linked'];
const SMS_STATUSES = [...CAPTURE_STATUSES, 'pending', 'parsed', 'parse_failed', 'needs_review', 'reviewed'];
const SMS_KINDS = ['capture', 'member', 'receiver'];
const SMS_EXTRACTIONS = ['not_extracted', 'parsed', 'needs_review'];
const SMS_DUPLICATES = ['', 'all', 'conflicting'];
const smsPage = { limit: { type: 'integer', minimum: 1, maximum: 100, default: 25 }, offset: { type: 'integer', minimum: 0, maximum: 2_147_483_647, default: 0 } };

function smsPaging(args) {
  const limit = args.limit === undefined ? 25 : args.limit, offset = args.offset === undefined ? 0 : args.offset;
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100 || !Number.isSafeInteger(offset) || offset < 0 || offset > 2_147_483_647) invalid();
  return { limit, offset };
}
function smsFilters(args) {
  const requested = smsPaging(args), search = args.search === undefined ? '' : args.search, status = args.status === undefined ? '' : args.status,
    source_kind = args.source_kind === undefined ? 'capture' : args.source_kind, extraction_status = args.extraction_status === undefined ? '' : args.extraction_status, duplicates = args.duplicates === undefined ? '' : args.duplicates;
  if (typeof search !== 'string' || search.length > 200 || /[\u0000-\u001f\u007f]/.test(search) ||
      typeof status !== 'string' || status && !SMS_STATUSES.includes(status) ||
      !SMS_KINDS.includes(source_kind) || typeof extraction_status !== 'string' ||
      extraction_status && !SMS_EXTRACTIONS.includes(extraction_status) || !SMS_DUPLICATES.includes(duplicates)) invalid();
  const filters = { search: search.trim(), status, source_kind, extraction_status, duplicates };
  return { requested, filters, query: pageQuery(requested, filters) };
}
const SMS_NULL_FACTS = ['payee_id', 'transaction_id', 'source_fact_id', 'parser_version', 'source_body_sha256',
  'source_payload_sha256', 'parsed_at', 'payer_name', 'payer_phone', 'payer_masked_phone', 'payer_last3',
  'payee_momo_number', 'payee_momo_code', 'momo_transaction_reference', 'momo_timestamp_local',
  'momo_timezone_offset', 'amount_rwf', 'wallet_balance_rwf', 'network', 'direction', 'is_payment', 'transaction_reference'];
// Preserve opaque source text. Only a valid explicitly zoned ISO timestamp
// projects whole epoch seconds; never infer a timezone or use server creation.
function smsSourceSeconds(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/.exec(value);
  if (!match) return null;
  const [, year, month, day, hour, minute, second, zone] = match;
  const n = [year, month, day, hour, minute, second].map(Number);
  const leap = n[0] % 4 === 0 && (n[0] % 100 !== 0 || n[0] % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (n[1] < 1 || n[1] > 12 || n[2] < 1 || n[2] > days[n[1] - 1] || n[3] > 23 || n[4] > 59 || n[5] > 59) return null;
  if (zone !== 'Z' && (Number(zone.slice(1, 3)) > 23 || Number(zone.slice(4, 6)) > 59)) return null;
  // setUTCFullYear avoids Date.UTC's year00..99 special case. Discarding the
  // positive fractional part floors signed epoch seconds, including pre1970.
  const local = new Date(0);
  local.setUTCFullYear(n[0], n[1] - 1, n[2]); local.setUTCHours(n[3], n[4], n[5], 0);
  const offset = zone === 'Z' ? 0 : (zone[0] === '-' ? -1 : 1) * (Number(zone.slice(1, 3)) * 60 + Number(zone.slice(4, 6))) * 60;
  const seconds = local.getTime() / 1000 - offset;
  return Number.isSafeInteger(seconds) && Math.abs(seconds) <= 8_640_000_000_000 ? seconds : null;
}
function smsCapture(value) {
  if (!object(value) || value.source_kind !== 'capture' || typeof value.id !== 'string' || !SMS_UUID.test(value.id) ||
      typeof value.user_id !== 'string' || !SMS_UUID.test(value.user_id) ||
      typeof value.source_sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(value.source_sha256) ||
      !CAPTURE_STATUSES.includes(value.status) || value.version !== 1 ||
      value.received_at !== null && (!Number.isSafeInteger(value.received_at) || Math.abs(value.received_at) > 8_640_000_000_000) ||
      value.received_at_device !== null && (typeof value.received_at_device !== 'string' || value.received_at_device.length === 0 || value.received_at_device.length > 64) ||
      value.received_at !== smsSourceSeconds(value.received_at_device) ||
      !Number.isSafeInteger(value.created_at) || value.created_at <= 0 || typeof value.public_id !== 'string' || !/^\d{6}$/.test(value.public_id) ||
      value.display_name !== null && typeof value.display_name !== 'string' || value.evidence_level !== 'client_received' ||
      SMS_NULL_FACTS.some(key => value[key] !== null) || value.extraction_status !== 'not_extracted' ||
      value.duplicate_reference_count !== 0 || value.conflicting_reference_count !== 0 || value.provider_confirmation !== false ||
      value.settlement_status !== 'not_asserted' || value.timezone_known !== false || value.payer_last3_known !== false ||
      value.source_content_reveal_required !== true) unavailable();
  // Explicit metadata projection also withholds any future accidental body,
  // content, storage-key or credential additions, regardless of field name.
  const keys = ['source_kind', 'id', 'user_id', 'source_sha256', 'status', 'version', 'received_at',
    'received_at_device', 'created_at', 'public_id', 'display_name', 'evidence_level', ...SMS_NULL_FACTS,
    'extraction_status', 'duplicate_reference_count', 'conflicting_reference_count', 'provider_confirmation',
    'settlement_status', 'timezone_known', 'payer_last3_known', 'source_content_reveal_required'];
  return Object.fromEntries(keys.map(key => [key, value[key]]));
}
function smsMetadataPage(value, requested) {
  if (!object(value) || !Array.isArray(value.rows) || !Number.isSafeInteger(value.total) || value.total < 0 ||
      value.limit !== requested.limit || value.offset !== requested.offset ||
      value.rows.length !== Math.max(0, Math.min(requested.limit, value.total - requested.offset)) ||
      value.next_offset !== (requested.offset + value.rows.length < value.total ? requested.offset + value.rows.length : null)) unavailable();
  const rows = value.rows.map(smsCapture);
  if (new Set(rows.map(row => row.id)).size !== rows.length) unavailable();
  return { rows, total: value.total, ...requested, next_offset: value.next_offset };
}

function listCaptures(args) {
  strictKeys(args, ['search', 'status', 'source_kind', 'extraction_status', 'duplicates', 'limit', 'offset']);
  const { requested, filters, query } = smsFilters(args);
  return {
    permission: 'sms.read',
    read: async ({ get }) => {
      const value = smsMetadataPage(await get(`/api/admin/sms/receipts?${query}`), requested);
      const requiresEmpty = filters.source_kind !== 'capture' ||
        filters.extraction_status && filters.extraction_status !== 'not_extracted' ||
        filters.duplicates || filters.status && !CAPTURE_STATUSES.includes(filters.status);
      if (requiresEmpty && value.total !== 0 ||
          filters.status && value.rows.some(row => row.status !== filters.status)) unavailable();
      return value;
    },
  };
}

function getCapture(args) {
  strictKeys(args, ['source_kind', 'id', 'limit', 'offset']);
  const requested = smsPaging(args), id = args.id;
  if (args.source_kind !== 'capture' || typeof id !== 'string' || !SMS_UUID.test(id)) invalid();
  return {
    permission: 'sms.read',
    read: async ({ get, user }) => {
      const value = await get(`/api/admin/sms/receipts/capture/${id}?${pageQuery(requested)}`);
      if (!object(value) || value.resource_type !== 'sms_receipts' || value.current_actor_id !== user.id ||
          value.can_extract !== false || !object(value.related)) unavailable();
      const resource = smsCapture(value.resource), duplicates = value.related.duplicate_references;
      if (resource.id !== id || !object(duplicates) || !Array.isArray(duplicates.rows) || duplicates.rows.length !== 0 ||
          duplicates.total !== 0 || duplicates.limit !== requested.limit || duplicates.offset !== requested.offset ||
          duplicates.next_offset !== null) unavailable();
      return { resource_type: 'sms_receipts', resource, current_actor_id: value.current_actor_id, can_extract: false,
        related: { duplicate_references: { rows: [], total: 0, ...requested, next_offset: null } } };
    },
  };
}

export const smsTools = [
  readTool('collect_admin_list_sms_receipts', 'SMS capture receipt metadata',
    'Read one page of canonical capture metadata, ordered by server creation descending then UUID ascending. Search is a literal receipt UUID, Collect public ID or owner-name substring. Legacy member/receiver, extracted or duplicate filters may validly return no captures. No source body, extraction or provider confirmation is exposed.',
    schema({ search: { type: 'string', maxLength: 200 }, status: { type: 'string', enum: ['', ...SMS_STATUSES] },
      source_kind: { type: 'string', enum: SMS_KINDS, default: 'capture' }, extraction_status: { type: 'string', enum: ['', ...SMS_EXTRACTIONS] },
      duplicates: { type: 'string', enum: SMS_DUPLICATES }, ...smsPage }), listCaptures),
  readTool('collect_admin_get_sms_receipt', 'Exact SMS capture metadata',
    'Read one exact capture UUID and its bounded duplicate-reference metadata. source_kind must explicitly be capture. Captures currently have no extracted reference facts; this does not reveal content, extract, retry, link or send.',
    schema({ source_kind: { type: 'string', enum: ['capture'] }, id: { type: 'string', pattern: SMS_UUID.source }, ...smsPage },
      ['source_kind', 'id']), getCapture),
];
