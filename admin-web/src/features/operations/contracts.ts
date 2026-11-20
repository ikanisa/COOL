/* eslint-disable no-control-regex -- Reject control characters in untrusted response text. */
import { z } from 'zod';

const uuid = z.string().regex(/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/);
const hash = z.string().regex(/^[a-f0-9]{64}$/);
const integer = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const positiveInteger = integer.min(1);
const boundedText = (maximum = 1000) => z.string().max(maximum).refine((value) => value.trim().length > 0 && !/[\x00-\x1f\x7f]/.test(value));
const coreTime = z.string().refine((value) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value);
const sourceTime = z.string().refine((value) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 19) === value.slice(0, 19));
const localTime = z.string().refine((value) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(value) && Number.isFinite(Date.parse(`${value}Z`)) && new Date(`${value}Z`).toISOString().slice(0, 19) === value);
const phone = z.string().regex(/^(?:\+?2507[2389][0-9]{7}|07[2389][0-9]{7})$/);
const publicId = z.string().regex(/^[0-9]{6}$/);
const failure = () => { throw new Error('The workspace response could not be verified.'); };

/** Project only an explicitly zoned, strictly valid device time to UTC seconds. */
function captureEpoch(raw: string | null | undefined): number | null {
  if (!raw) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|([+-])(\d{2}):(\d{2}))$/.exec(raw);
  if (!match) return null;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map(Number);
  if (month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59 || second > 59) return null;
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(hour, minute, second, 0);
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  const zoneHour = Number(match[9] ?? 0), zoneMinute = Number(match[10] ?? 0);
  if (zoneHour > 23 || zoneMinute > 59) return null;
  const offset = (zoneHour * 60 + zoneMinute) * (match[8] === '+' ? 1 : -1);
  return date.getTime() / 1000 - offset * 60;
}

const smsSchema = z.object({
  source_kind: z.enum(['member', 'receiver', 'capture']), id: uuid,
  user_id: uuid.nullable(), payee_id: uuid.nullable(), source_sha256: hash,
  status: z.enum(['pending', 'parsed', 'parse_failed', 'needs_review', 'rejected', 'reviewed', 'received', 'under_review', 'linked']),
  version: positiveInteger, received_at: z.number().int().min(-8640000000000).max(8640000000000).nullable(), created_at: positiveInteger,
  public_id: publicId.nullable(), display_name: boundedText().nullable(), transaction_id: uuid.nullable(),
  evidence_level: z.enum(['member_submitted', 'receiver_ingress_unverified', 'client_received']),
  source_fact_id: uuid.nullable(), parser_version: z.literal('collect-admin-source-facts-v1').nullable(),
  extraction_status: z.enum(['not_extracted', 'parsed', 'needs_review']),
  source_body_sha256: hash.nullable(), source_payload_sha256: hash.nullable(), parsed_at: positiveInteger.nullable(),
  payer_name: boundedText().nullable(), payer_phone: phone.nullable(), payer_masked_phone: z.string().regex(/^\*{3,}[0-9]{3}$/).nullable(), payer_last3: z.string().regex(/^[0-9]{3}$/).nullable(),
  payee_momo_number: phone.nullable(), payee_momo_code: z.string().regex(/^[0-9]{4,9}$/).nullable(),
  momo_transaction_reference: boundedText().nullable(), momo_timestamp_local: localTime.nullable(), momo_timezone_offset: z.string().regex(/^[+-](?:0[0-9]|1[0-3]):[0-5][0-9]$|^[+-]14:00$/).nullable(),
  amount_rwf: positiveInteger.nullable(), wallet_balance_rwf: integer.nullable(), network: z.enum(['mtn_momo', 'airtel_money']).nullable(),
  direction: z.enum(['incoming', 'outgoing']).nullable(), is_payment: z.union([z.literal(0), z.literal(1)]).nullable(), transaction_reference: z.string().regex(/^[0-9]{18}$/).nullable(),
  duplicate_reference_count: integer, conflicting_reference_count: integer,
  provider_confirmation: z.literal(false), settlement_status: z.literal('not_asserted'), timezone_known: z.boolean(), payer_last3_known: z.boolean(), source_content_reveal_required: z.literal(true),
  received_at_device: z.string().min(1).max(64).nullable().optional(),
}).strict().superRefine((value, ctx) => {
  const invalid = () => ctx.addIssue({code: 'custom', message: 'Invalid SMS receipt relationship.'});
  const capture = value.source_kind === 'capture', member = value.source_kind === 'member';
  if (capture !== Object.hasOwn(value, 'received_at_device')) invalid();
  if (value.evidence_level !== (capture ? 'client_received' : member ? 'member_submitted' : 'receiver_ingress_unverified')) invalid();
  if (value.conflicting_reference_count > value.duplicate_reference_count || value.timezone_known !== (value.momo_timezone_offset !== null) || value.payer_last3_known !== (value.payer_last3 !== null)) invalid();
  if (capture) {
    if (!value.user_id || value.payee_id !== null || value.transaction_id !== null || value.version !== 1 || !['received', 'under_review', 'rejected', 'linked'].includes(value.status) || value.extraction_status !== 'not_extracted' || value.received_at !== captureEpoch(value.received_at_device)) invalid();
  } else if (member) {
    if (!value.user_id || value.payee_id !== null || !['needs_review', 'rejected', 'reviewed'].includes(value.status) || value.received_at === null || value.received_at < 1) invalid();
  } else if (!value.payee_id || value.user_id !== null || value.public_id !== null || value.version !== 1 || !['pending', 'parsed', 'parse_failed', 'needs_review'].includes(value.status) || value.received_at === null || value.received_at < 1) invalid();
  const actualPhone = value.payer_phone ?? value.payer_masked_phone;
  if (value.payer_phone !== null && value.payer_masked_phone !== null || value.payer_last3 !== (actualPhone?.slice(-3) ?? null) || value.momo_timezone_offset !== null && value.momo_timestamp_local === null) invalid();
  const factFields = [value.source_fact_id, value.parser_version, value.source_body_sha256, value.source_payload_sha256, value.parsed_at, value.payer_name, value.payer_phone, value.payer_masked_phone, value.payer_last3, value.payee_momo_number, value.payee_momo_code, value.momo_transaction_reference, value.momo_timestamp_local, value.momo_timezone_offset, value.amount_rwf, value.wallet_balance_rwf, value.network, value.direction, value.is_payment];
  if (value.extraction_status === 'not_extracted') {
    if (factFields.some((field) => field !== null) || value.duplicate_reference_count !== 0 || value.conflicting_reference_count !== 0) invalid();
  } else {
    const isPayment = value.direction !== null && value.amount_rwf !== null && value.network !== null ? 1 : 0;
    if (!value.source_fact_id || !value.parser_version || !value.source_body_sha256 || !value.source_payload_sha256 || !value.parsed_at || (member ? value.source_body_sha256 : value.source_payload_sha256) !== value.source_sha256 || value.is_payment !== isPayment || value.extraction_status !== (isPayment === 1 && value.momo_transaction_reference !== null ? 'parsed' : 'needs_review')) invalid();
  }
  if (value.transaction_reference !== null && value.transaction_id === null) invalid();
});
export type SmsReceipt = z.infer<typeof smsSchema>;

const grantSchema = z.object({
  id: uuid, device_id: uuid, device_label: boundedText(120), installation_id: uuid, key_sha256: hash,
  payee_id: uuid, payee_label: boundedText(120), payee_network: z.enum(['mtn_momo', 'airtel_money']),
  payee_momo_number_or_code: z.string().regex(/^[0-9]{4,12}$/), status: z.enum(['active', 'revoked']),
  version: positiveInteger, created_by_admin_id: uuid, created_at: coreTime,
  revoked_by_admin_id: uuid.nullable(), revoked_at: coreTime.nullable(), capture_authority: z.boolean(),
  send_authority: z.literal(false), financial_authority: z.literal(false),
}).strict().superRefine((value, ctx) => {
  const active = value.status === 'active';
  if (value.capture_authority !== active || (active ? value.revoked_by_admin_id !== null || value.revoked_at !== null || value.version !== 1 : !value.revoked_by_admin_id || !value.revoked_at || value.version !== 2)) ctx.addIssue({code: 'custom', message: 'Invalid capture grant state.'});
});
export type ReceiverGrant = z.infer<typeof grantSchema>;

const deviceFields = {
  id: uuid, label: z.string().min(2).max(120).refine((value) => value.trim().length >= 2),
  app_id: z.string().max(160).regex(/^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$/),
  installation_id: uuid, key_sha256: hash, signing_certificate_sha256: hash,
  state: z.enum(['pending', 'active', 'revoked']), version: positiveInteger,
  created_at: coreTime, activated_at: coreTime.nullable(), revoked_at: coreTime.nullable(), last_heartbeat_at: coreTime.nullable(),
  carrier_proof: z.literal(false), send_authority: z.literal(false),
};
const deviceSchema = z.object(deviceFields).strict().superRefine((value, ctx) => {
  const invalidTime = [value.activated_at, value.revoked_at, value.last_heartbeat_at].some((time) => time !== null && time < value.created_at);
  if (invalidTime || value.state === 'pending' && (value.activated_at !== null || value.revoked_at !== null) || value.state === 'active' && (value.activated_at === null || value.revoked_at !== null) || value.state === 'revoked' && value.revoked_at === null) ctx.addIssue({code: 'custom', message: 'Invalid gateway state.'});
});
const deviceDetailSchema = z.object({...deviceFields, public_key_spki_base64: z.string()}).strict().superRefine((value, ctx) => {
  if (!deviceSchema.safeParse(Object.fromEntries(Object.entries(value).filter(([key]) => key !== 'public_key_spki_base64'))).success) ctx.addIssue({code: 'custom', message: 'Invalid gateway state.'});
});
export type GatewayDevice = z.infer<typeof deviceSchema>;

const emailStatus = z.enum(['queued', 'leased', 'send_started', 'accepted', 'delivered', 'failed_no_send', 'uncertain', 'suppressed']);
const epoch = integer.max(253402300799);
const emailSchema = z.object({
  id: uuid, recipient_masked: z.string().refine((v) => v === 'Unavailable' || /^.•••@[^\s@]+$/.test(v)),
  notification_type: z.string().min(1), status: emailStatus, attempt_count: integer,
  created_at: epoch.min(1), updated_at: epoch, accepted_at: epoch.nullable(), delivered_at: epoch.nullable(),
}).strict().superRefine((value, ctx) => {
  if (value.updated_at < value.created_at || value.accepted_at !== null && value.accepted_at < value.created_at || value.delivered_at !== null && value.delivered_at < value.created_at || value.status === 'accepted' && value.accepted_at === null || value.status === 'delivered' && value.delivered_at === null) ctx.addIssue({code: 'custom', message: 'Invalid email delivery state.'});
});
export type EmailEvent = z.infer<typeof emailSchema>;

const memberSchema = z.object({
  id: uuid, user_id: uuid, body_sha256: hash,
  status: z.enum(['needs_review', 'reviewed', 'rejected', 'received', 'under_review', 'linked']),
  version: positiveInteger, received_at: z.string().nullable(), created_at: coreTime,
  public_id: publicId.nullable(), display_name: z.string().nullable(), transaction_id: uuid.nullable(), reviewed_at: coreTime.nullable(),
  source_kind: z.literal('capture').optional(), received_at_device: z.string().min(1).max(64).nullable().optional(),
  evidence_level: z.literal('client_received').optional(), provider_confirmation: z.literal(false).optional(), settlement_status: z.literal('not_asserted').optional(), source_content_reveal_required: z.literal(true).optional(),
}).strict().superRefine((value, ctx) => {
  const capture = value.source_kind === 'capture';
  const fields = ['received_at_device', 'evidence_level', 'provider_confirmation', 'settlement_status', 'source_content_reveal_required'] as const;
  const invalid = () => ctx.addIssue({code: 'custom', message: 'Invalid receipt state.'});
  if (fields.some((field) => Object.hasOwn(value, field) !== capture)) invalid();
  if (capture) {
    const seconds = captureEpoch(value.received_at_device);
    const normalized = seconds === null ? null : new Date(seconds * 1000).toISOString();
    if (!['received', 'under_review', 'rejected', 'linked'].includes(value.status) || value.version !== 1 || !value.public_id || value.transaction_id !== null || value.reviewed_at !== null || value.received_at !== normalized) invalid();
  } else if (!['needs_review', 'reviewed', 'rejected'].includes(value.status) || !coreTime.safeParse(value.received_at).success || value.status === 'needs_review' && value.reviewed_at !== null || value.status !== 'needs_review' && value.reviewed_at === null) invalid();
});
export type MemberReceipt = z.infer<typeof memberSchema>;

export interface Page<T> { rows: T[]; total: number; limit: number; offset: number; }
function verifyPage<T>(rows: T[], total: number, offset: number, limit: number, identity: (row: T) => string): Page<T> {
  if (rows.length !== Math.max(0, Math.min(limit, total - offset)) || new Set(rows.map(identity)).size !== rows.length) failure();
  return {rows, total, offset, limit};
}

export interface SmsPageFilters { sourceKind?: string; extractionStatus?: string; duplicates?: string; canonical?: boolean }

export function parseSmsPage(input: unknown, offset: number, limit = 25, status = '', filters: SmsPageFilters = {}): Page<SmsReceipt> {
  const body = z.object({rows: z.array(smsSchema), total: integer, limit: positiveInteger.max(100), offset: integer.max(2147483647), next_offset: integer.nullable()}).strict().parse(input);
  if (filters.sourceKind && !['member', 'receiver', 'capture'].includes(filters.sourceKind) ||
      filters.extractionStatus && !['not_extracted', 'parsed', 'needs_review'].includes(filters.extractionStatus) ||
      filters.duplicates && !['all', 'conflicting'].includes(filters.duplicates)) failure();
  if (body.offset !== offset || body.limit !== limit || body.next_offset !== (offset + body.rows.length < body.total ? offset + body.rows.length : null) ||
      body.rows.some((row) => status && row.status !== status || filters.sourceKind && row.source_kind !== filters.sourceKind ||
        filters.extractionStatus && row.extraction_status !== filters.extractionStatus ||
        filters.duplicates === 'all' && row.duplicate_reference_count === 0 ||
        filters.duplicates === 'conflicting' && row.conflicting_reference_count === 0 ||
        filters.canonical !== undefined && (row.source_kind === 'capture') !== filters.canonical)) failure();
  return verifyPage(body.rows, body.total, offset, limit, (row) => `${row.source_kind}/${row.id}`);
}

export function parseGatewayPage(input: unknown, offset: number, state = ''): Page<GatewayDevice> {
  const body = z.object({rows: z.array(deviceSchema), total: integer}).strict().parse(input);
  if (state && body.rows.some((row) => row.state !== state)) failure();
  return verifyPage(body.rows, body.total, offset, 25, (row) => row.id);
}

export function parseGrantPage(input: unknown, offset: number, status = '', limit = 25): Page<ReceiverGrant> {
  const body = z.object({rows: z.array(grantSchema), total: integer, limit: positiveInteger.max(100), offset: integer.max(2147483647)}).strict().parse(input);
  if (body.offset !== offset || body.limit !== limit || status && body.rows.some((row) => row.status !== status)) failure();
  return verifyPage(body.rows, body.total, offset, limit, (row) => row.id);
}

export function parseMemberPage(input: unknown, offset: number, canonical: boolean, status = ''): Page<MemberReceipt> {
  const body = z.object({rows: z.array(memberSchema), total: integer}).strict().parse(input);
  if (body.rows.some((row) => (row.source_kind === 'capture') !== canonical || status && row.status !== status)) failure();
  return verifyPage(body.rows, body.total, offset, 25, (row) => row.id);
}

export function parseEmailPage(input: unknown, offset: number, status = ''): Page<EmailEvent> {
  const body = z.object({rows: z.array(emailSchema), total: integer, limit: z.literal(25), offset: integer.max(2147483647)}).strict().parse(input);
  if (body.offset !== offset || status && body.rows.some((row) => row.status !== status)) failure();
  return verifyPage(body.rows, body.total, offset, 25, (row) => row.id);
}

export function parseSmsDetail(input: unknown, kind: string, id: string, actor: string, canExtract: boolean, offset = 0) {
  const body = z.object({resource_type: z.literal('sms_receipts'), resource: smsSchema, current_actor_id: z.string(), can_extract: z.boolean(), related: z.object({duplicate_references: z.unknown()}).strict()}).strict().parse(input);
  if (body.current_actor_id !== actor || body.can_extract && !canExtract || body.resource.id !== id || body.resource.source_kind !== kind) failure();
  const duplicates = parseSmsPage(body.related.duplicate_references, offset);
  if (duplicates.total !== body.resource.duplicate_reference_count || duplicates.rows.some((row) => row.source_kind === kind && row.id === id || row.network === null || row.network !== body.resource.network || row.momo_transaction_reference === null || row.momo_transaction_reference !== body.resource.momo_transaction_reference)) failure();
  return {resource: body.resource, duplicates, canExtract: body.can_extract};
}

const captureSchema = z.object({
  id: uuid, request_id: uuid, client_sms_id: uuid, ingress_id: uuid, payload_sha256: hash,
  issued_at: sourceTime, source_received_at: coreTime, accepted_at: coreTime,
  metadata_accepted: z.literal(true), provider_confirmation: z.literal(false), send_authority: z.literal(false), financial_authority: z.literal(false),
}).strict();
export function parseGrantDetail(input: unknown, id: string, actor: string, canManage: boolean, offset = 0) {
  const body = z.object({resource_type: z.literal('receiver_capture_grants'), resource: grantSchema, current_actor_id: z.string(), can_manage: z.boolean(), related: z.object({captures: z.array(captureSchema)}).strict(), related_total: integer, related_limit: z.literal(25), related_offset: integer}).strict().parse(input);
  if (body.current_actor_id !== actor || body.resource.id !== id || body.related_offset !== offset || body.can_manage && !canManage) failure();
  const captures = verifyPage(body.related.captures, body.related_total, offset, 25, (row) => row.id);
  return {resource: body.resource, captures, canManage: body.can_manage};
}

const reviewSchema = z.object({id: uuid, outcome: z.enum(['reviewed', 'rejected']), transaction_id: uuid.nullable(), evidence_id: uuid.nullable(), actor_admin_id: uuid, reason: z.string(), reviewed_at: coreTime}).strict();
export function parseMemberDetail(input: unknown, id: string, actor: string, staff: boolean, canonical: boolean) {
  const body = z.object({resource_type: z.literal('member_receipts'), resource: memberSchema, current_actor_id: z.string(), can_manage: z.boolean(), related_truncated: z.literal(false), related: z.object({reviews: z.array(reviewSchema).max(100)}).strict()}).strict().parse(input);
  if (body.current_actor_id !== actor || body.resource.id !== id || (body.resource.source_kind === 'capture') !== canonical || body.can_manage && (staff || canonical) || canonical && body.related.reviews.length !== 0) failure();
  return {resource: body.resource, reviews: body.related.reviews, canManage: body.can_manage};
}

const heartbeatSchema = z.object({
  observation_id: uuid, request_id: uuid, issued_at: sourceTime, reported_at: sourceTime, ingested_at: sourceTime,
  sms_permission: z.boolean(), network: z.enum(['validated', 'unvalidated', 'offline', 'unknown']),
  telephony: z.enum(['ready', 'unavailable', 'unknown']), sim_selected: z.boolean(), sim_revision_sha256: hash.nullable(),
  local_pause: z.boolean(), carrier_proof: z.literal(false), send_authority: z.literal(false),
}).strict().superRefine((value, ctx) => {
  if (value.sim_selected !== (value.sim_revision_sha256 !== null)) ctx.addIssue({code: 'custom', message: 'Invalid device observation.'});
});

async function validGatewayKey(encoded: string, fingerprint: string): Promise<boolean> {
  if (encoded.length !== 124 || !globalThis.crypto?.subtle) return false;
  try {
    const binary = atob(encoded);
    if (binary.length !== 91 || btoa(binary) !== encoded) return false;
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    const prefix = [0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00, 0x04];
    if (!prefix.every((byte, index) => bytes[index] === byte)) return false;
    const digest = await globalThis.crypto.subtle.digest('SHA-256', bytes);
    return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('') === fingerprint;
  } catch { return false; }
}

export async function parseGatewayDetail(input: unknown, id: string, actor: string, staff: boolean) {
  const body = z.object({
    resource_type: z.literal('gateway_devices'), resource: deviceDetailSchema, current_actor_id: z.string(),
    can_manage: z.boolean(), related_truncated: z.boolean(), related: z.object({heartbeats: z.array(heartbeatSchema).max(100)}).strict(),
    enrollment: z.object({contract_version: z.literal(1), device_id: uuid, installation_id: uuid, key_sha256: hash, signing_certificate_sha256: hash}).strict(),
  }).strict().parse(input);
  if (body.current_actor_id !== actor || body.resource.id !== id || staff && body.can_manage || body.enrollment.device_id !== id || body.enrollment.installation_id !== body.resource.installation_id || body.enrollment.key_sha256 !== body.resource.key_sha256 || body.enrollment.signing_certificate_sha256 !== body.resource.signing_certificate_sha256 || !(await validGatewayKey(body.resource.public_key_spki_base64, body.resource.key_sha256))) failure();
  return {resource: body.resource, heartbeats: body.related.heartbeats, truncated: body.related_truncated, enrollment: body.enrollment, canManage: body.can_manage};
}

export function isValidId(value: string | undefined): value is string {
  return uuid.safeParse(value).success;
}
