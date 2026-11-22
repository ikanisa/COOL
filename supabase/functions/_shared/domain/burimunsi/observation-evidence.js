import { BuriError, requireThat } from './errors.js';
import { pgInteger } from './postgres-values.js';
import { canonicalJson, exactKeys, requireRequestId, sha256 } from './values.js';

const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });
const senderControl = /[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/;
// SMS bodies may contain ordinary line breaks and tabs.
const bodyControl = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u202a-\u202e\u2066-\u2069]/;
const requiredInputKeys = [
  'requestId',
  'rawSender',
  'rawBody',
  'sourceMode',
  'complete',
  'capturedAt',
  'serviceCentreAt',
  'inboxReceivedAt',
  'subscriptionId',
];
const inputKeys = [...requiredInputKeys, 'sourceKey'];
const reconcileKeys = [
  'sourceKey',
  'bodySha256',
  'rawSender',
  'serviceCentreAt',
  'inboxReceivedAt',
  'subscriptionId',
];

export const OBSERVATION_HASH = /^[a-f0-9]{64}$/;
export const copyObservationValue = (value) => JSON.parse(canonicalJson(value));
export const sameObservationValue = (left, right) => canonicalJson(left) === canonicalJson(right);
export const requireObservation = (value, code = 'observation_unavailable', status = 503) =>
  requireThat(value, code, status);
export const observationInteger = (value, minimum = 0, maximum = Number.MAX_SAFE_INTEGER) =>
  pgInteger(value, { minimum, maximum, code: 'observation_unavailable' });

const text = (value, min, max) => typeof value === 'string' && value.length >= min && value.length <= max;
const sender = (value) => text(value, 1, 96) && !senderControl.test(value);
const submittedSender = (value) => sender(value) && value.trim().length > 0;
const body = (value) =>
  text(value, 1, 3000) && encoder.encode(value).length <= 3000 && !bodyControl.test(value);
const subscription = (value) =>
  value === null || Number.isInteger(value) && value >= 0 && value <= 2147483647;
const iso = (value) =>
  typeof value === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?Z$/.test(value) &&
  Number.isFinite(Date.parse(value)) &&
  new Date(Date.parse(value)).toISOString().slice(0, 19) === value.slice(0, 19);

// Keep sub-millisecond precision while comparing equivalent ISO spellings.
function instant(value) {
  const [seconds, fraction = ''] = value.slice(0, -1).split('.');
  return `${seconds}.${fraction.replace(/0+$/, '')}Z`;
}

export function mapObservationError(error) {
  if (error instanceof BuriError) return error;
  if (error?.code === '23505' || error?.code === '40001') return new BuriError('observation_changed', 409);
  if (error?.code === '42501') return new BuriError('access_denied', 403);
  if (error?.code === '22023') return new BuriError('invalid_request', 400);
  if (error?.code === '54000') return new BuriError('observation_limit', 429);
  return new BuriError('observation_unavailable', 503);
}

export function validateObservationInput(value) {
  exactKeys(value, inputKeys, requiredInputKeys);
  const input = copyObservationValue(value);
  input.requestId = requireRequestId(input.requestId);
  requireObservation(submittedSender(input.rawSender), 'invalid_request', 400);
  requireObservation(body(input.rawBody), 'invalid_request', 400);
  requireObservation(
    iso(input.capturedAt) && (input.serviceCentreAt === null || iso(input.serviceCentreAt)) &&
      (input.inboxReceivedAt === null || iso(input.inboxReceivedAt)),
    'invalid_request',
    400,
  );
  requireObservation(subscription(input.subscriptionId), 'invalid_request', 400);
  requireObservation(
    (input.sourceMode === 'live' && input.complete === true) ||
      (input.sourceMode === 'catch_up' && input.complete === false && input.inboxReceivedAt !== null),
    'invalid_request',
    400,
  );
  requireObservation(
    input.sourceKey === undefined ||
      (input.sourceMode === 'catch_up' && OBSERVATION_HASH.test(input.sourceKey)),
    'invalid_request',
    400,
  );
  return input;
}

/** Intake admits the configured senders without assuming an incoming-payment format. */
export function isObservationCandidate(value, profile) {
  if (!value || !submittedSender(value.rawSender) || !body(value.rawBody)) return false;
  return profileAdmitsSender(value.rawSender, profile);
}

/** Reconciliation receives sender metadata and a digest without the SMS body. */
export function isObservationSenderAllowed(rawSender, profile) {
  return submittedSender(rawSender) && profileAdmitsSender(rawSender, profile);
}

function profileAdmitsSender(rawSender, profile) {
  if (!profile || !text(profile.version, 1, 80) || profile.version === 'unverified') return false;
  if (
    !Array.isArray(profile.senders) || profile.senders.length === 0 || profile.senders.length > 30 ||
    !profile.senders.every((value) =>
      text(value, 1, 160) && value.trim().length > 0 && !/[\r\n\0]/.test(value)
    )
  ) return false;
  return profile.senders.some((allowedSender) => allowedSender.toLowerCase() === rawSender.toLowerCase());
}

export function approvedObservationProfile(context, validate) {
  const version = context?.profile_version;
  requireObservation(text(version, 1, 80) && version.trim() === version && !senderControl.test(version));
  const profile = validate(context);
  requireObservation(
    profile && Number.isInteger(profile.utc_offset_minutes) && Math.abs(profile.utc_offset_minutes) <= 840,
  );
  return {
    version,
    offsetMinutes: profile.utc_offset_minutes,
    senders: [...profile.sender_allowlist],
    incomingPrefixes: [...profile.incoming_prefixes],
    currencyAliases: [...profile.currency_aliases],
    transactionIdPrefixes: [...profile.transaction_id_prefixes],
  };
}

export function validateReconcileInput(input) {
  exactKeys(input, reconcileKeys);
  const witness = copyObservationValue(input);
  requireObservation(
    OBSERVATION_HASH.test(witness.sourceKey ?? '') && OBSERVATION_HASH.test(witness.bodySha256 ?? '') &&
      submittedSender(witness.rawSender) && iso(witness.inboxReceivedAt) &&
      (witness.serviceCentreAt === null || iso(witness.serviceCentreAt)) &&
      subscription(witness.subscriptionId),
    'invalid_request',
    400,
  );
  return witness;
}

export function decodeObservationRecord(value) {
  requireObservation(
    value && text(value.id, 36, 36) && value.sourceId === value.id && text(value.requestId, 36, 36) &&
      OBSERVATION_HASH.test(value.bodySha256 ?? '') && value.object_key === 'sms/' + value.id &&
      OBSERVATION_HASH.test(value.object_sha256 ?? '') && OBSERVATION_HASH.test(value.fingerprint ?? '') &&
      text(value.principalUserId, 1, 128) && text(value.sessionId, 36, 36),
  );
  return {
    ...value,
    size_bytes: observationInteger(value.size_bytes, 1, 131072),
    createdAt: observationInteger(value.createdAt),
    consentGeneration: observationInteger(value.consentGeneration, 1),
  };
}

export function observationStorageTarget(record) {
  return {
    ownerId: record.principalUserId,
    purpose: 'sms_receipt',
    entityId: record.id,
    plaintextSha256: record.object_sha256,
    aad: `sms:${record.id}:${record.object_sha256}`,
  };
}

export function observationActorIdentity(actor) {
  return {
    id: actor.id,
    sessionId: actor.sessionId,
    principalUserId: actor.principalUserId,
    installationId: actor.installationId,
    groupId: actor.groupId,
  };
}

export function observationPayload(value) {
  return {
    raw_sender: value.rawSender,
    raw_body: value.rawBody,
    source_mode: value.sourceMode,
    complete: value.complete,
    captured_at: value.capturedAt,
    service_centre_at: value.serviceCentreAt,
    inbox_received_at: value.inboxReceivedAt,
    subscription_id: value.subscriptionId,
    provenance: 'native_observation_unverified',
  };
}

export const encodeObservationPayload = (payload) => encoder.encode(JSON.stringify(payload));
export const decodeObservationPayload = (bytes) => JSON.parse(decoder.decode(bytes));

export function hasObservationContent(payload) {
  return payload && sender(payload.raw_sender) && body(payload.raw_body);
}

export async function observationContentFingerprint(value, bodySha) {
  return sha256(canonicalJson({
    rawSender: value.rawSender,
    bodySha256: bodySha,
    serviceCentreAt: value.serviceCentreAt,
    inboxReceivedAt: value.inboxReceivedAt,
    subscriptionId: value.subscriptionId,
  }));
}

export async function verifyObservationJournal(record, journal) {
  const keyId = journal?.reservation?.key_id;
  requireObservation(text(keyId, 1, 128));
  const target = observationStorageTarget(record);
  const descriptor = {
    scope: { ownerId: target.ownerId, purpose: target.purpose, entityId: target.entityId },
    aad: target.aad,
    keyId,
    plaintextSha256: record.object_sha256,
    requestDigest: record.fingerprint,
    httpMetadata: { contentType: 'application/octet-stream' },
    customMetadata: { sha256: record.object_sha256, key_id: keyId },
  };
  requireObservation(await sha256(canonicalJson(descriptor)) === journal.reservation.source_fingerprint);
}

/** An unavailable or ambiguous legacy witness cannot establish absence. */
export async function matchesLegacyObservationPayload(payload, witness) {
  requireObservation(
    payload && payload.provenance === 'native_observation_unverified' &&
      ((payload.source_mode === 'live' && payload.complete === true) ||
        (payload.source_mode === 'catch_up' && payload.complete === false)) &&
      hasObservationContent(payload) &&
      await sha256(payload.raw_body) === witness.bodySha256 && iso(payload.inbox_received_at) &&
      Object.hasOwn(payload, 'service_centre_at') &&
      (payload.service_centre_at === null || iso(payload.service_centre_at)) &&
      Object.hasOwn(payload, 'subscription_id') && subscription(payload.subscription_id),
    'observation_item_unavailable',
    503,
  );
  requireObservation(
    (payload.service_centre_at === null) === (witness.serviceCentreAt === null) &&
      (payload.subscription_id === null) === (witness.subscriptionId === null),
    'observation_item_unavailable',
    503,
  );
  return payload.raw_sender === witness.rawSender &&
    instant(payload.inbox_received_at) === instant(witness.inboxReceivedAt) &&
    (payload.service_centre_at === null ||
      instant(payload.service_centre_at) === instant(witness.serviceCentreAt)) &&
    payload.subscription_id === witness.subscriptionId;
}
