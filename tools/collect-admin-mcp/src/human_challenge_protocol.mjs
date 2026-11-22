import { sign, timingSafeEqual } from 'node:crypto';
import { isUuid, SafeError } from './config.mjs';

export const OPERATIONS = new Set(['admin.email_otp.send', 'admin.email_otp.verify', 'admin.password.sign_in']);
const ERRORS = new Set(['cancelled', 'expired', 'unavailable', 'timeout', 'invalid_token']);
const B64 = /^[A-Za-z0-9_-]{43}$/;

export const challengeError = code => new SafeError(code, code === 'challenge_cancelled'
  ? 'Security verification was cancelled. No request was retried.'
  : code === 'challenge_expired'
    ? 'Security verification expired. No request was retried.'
    : 'Security verification could not be confirmed. No request was retried.');

export const isHumanChallengeToken = value => typeof value === 'string' && value.length > 0 &&
  value.length <= 2048 && !/[\x00-\x20\x7f]/.test(value);

// Completion envelopes are flat string maps. Parsing that grammar explicitly
// rejects duplicate decoded keys without imposing canonical order on browsers.
function completionJson(bytes) {
  const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  let at = 0;
  const ws = () => { while (/[\x20\t\r\n]/.test(text[at] ?? '\0')) at++; };
  function string() {
    if (text[at] !== '"') throw challengeError('invalid_challenge');
    const start = at++;
    while (at < text.length) {
      if (text[at] === '\\') { at += 2; continue; }
      if (text[at++] === '"') return JSON.parse(text.slice(start, at));
    }
    throw challengeError('invalid_challenge');
  }
  ws(); if (text[at++] !== '{') throw challengeError('invalid_challenge');
  ws(); const value = Object.create(null), seen = new Set();
  if (text[at] !== '}') for (;;) {
    const key = string(); ws();
    if (seen.has(key) || text[at++] !== ':') throw challengeError('invalid_challenge');
    seen.add(key); ws(); value[key] = string(); ws();
    if (text[at] !== ',') break;
    at++; ws();
  }
  if (text[at++] !== '}') throw challengeError('invalid_challenge');
  ws(); if (at !== text.length) throw challengeError('invalid_challenge');
  return value;
}

export function pairingDescriptor({ attempt, operation, origin, port, expiresAt, publicKey }) {
  return Object.freeze({ type: 'collect.admin.human_challenge.pairing.v1', attempt_id: attempt,
    operation, admin_origin: origin, loopback_port: port, expires_at_ms: expiresAt,
    listener_public_key_ed25519: publicKey.export({ format: 'jwk' }).x });
}

export function signedOffer({ attempt, operation, origin, port, nonce, issuedAt, expiresAt, privateKey }) {
  const value = { type: 'collect.admin.human_challenge.offer_payload.v1', attempt_id: attempt,
    operation, admin_origin: origin, loopback_port: port, nonce: nonce.toString('base64url'),
    issued_at_ms: issuedAt, expires_at_ms: expiresAt };
  const payload = Buffer.from(JSON.stringify(Object.fromEntries(Object.keys(value).sort().map(key => [key, value[key]]))));
  const envelope = { type: 'collect.admin.human_challenge.signed_offer.v1', payload_base64url: payload.toString('base64url'),
    signature_ed25519_base64url: sign(null, payload, privateKey).toString('base64url') };
  if (Buffer.byteLength(JSON.stringify(envelope)) > 8192) throw challengeError('invalid_challenge');
  return envelope;
}

export function validateCompletion(bytes, { attempt, operation, nonce }) {
  const value = completionJson(bytes);
  const field = Object.hasOwn(value, 'token') ? 'token' : 'error';
  const expected = ['type', 'attempt_id', 'operation', 'nonce', 'widget_attempt_id', field].sort();
  if (Object.keys(value).sort().join(',') !== expected.join(',') || value.type !== 'collect.admin.human_challenge.complete.v1' ||
      !isUuid(value.attempt_id) || !isUuid(value.widget_attempt_id) || !OPERATIONS.has(value.operation) || !B64.test(value.nonce)) {
    return { refusal: 400 };
  }
  if (value.attempt_id !== attempt || value.widget_attempt_id !== attempt || value.operation !== operation) {
    return { refusal: 409 };
  }
  const candidate = Buffer.from(value.nonce, 'base64url');
  if (candidate.length !== 32 || candidate.toString('base64url') !== value.nonce || !timingSafeEqual(nonce, candidate)) {
    return { refusal: 403 };
  }
  if (field === 'token') {
    return isHumanChallengeToken(value.token)
      ? { token: value.token, status: 'accepted_for_one_cli_operation' }
      : { refusal: 400 };
  }
  if (!ERRORS.has(value.error)) return { refusal: 400 };
  if (value.error === 'cancelled') return { error: challengeError('challenge_cancelled'), status: 'cancelled_without_auth' };
  if (['expired', 'timeout'].includes(value.error)) return { error: challengeError('challenge_expired'), status: 'expired_without_auth' };
  return { error: challengeError('challenge_unconfirmed'), status: 'failed_without_auth' };
}
