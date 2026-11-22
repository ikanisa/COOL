import { performance } from 'node:perf_hooks';
import { acquireHumanChallenge } from '../../collect-admin-mcp/src/human_challenge.mjs';
import { ORIGINS, need } from './contract.mjs';

const MAX_PROOF_AGE_MS = 120_000;
const EMAIL_PURPOSES = new Set(['sign_in', 'sensitive']);

// Opaque, one-use memory custody, bound to the exact origin and intended send.
const candidates = new WeakMap();

async function acquire(origin, purpose, operation, { onPairing, signal } = {}) {
  need(ORIGINS.includes(origin), 'independently_approved_frontend_origin_required');
  const startedAt = performance.now();
  let expiresAt;
  const token = await acquireHumanChallenge({ origin }, {
    operation,
    signal,
    onPairing(pairing) {
      expiresAt = pairing.descriptor.expires_at_ms;
      return onPairing(pairing);
    },
  });

  const proof = Object.freeze({});
  candidates.set(proof, { origin, purpose, token, expiresAt, startedAt, signal });
  return proof;
}

function consume(proof, origin, purpose) {
  const candidate = proof && typeof proof === 'object' ? candidates.get(proof) : undefined;
  if (candidate) candidates.delete(proof);
  need(candidate && candidate.origin === origin && candidate.purpose === purpose &&
    !candidate.signal?.aborted && Date.now() < candidate.expiresAt &&
    performance.now() - candidate.startedAt < MAX_PROOF_AGE_MS, 'fresh_bound_human_captcha_required');
  return candidate.token;
}

export function acquireEmailProof({ origin, purpose = 'sign_in' }, options = {}) {
  need(EMAIL_PURPOSES.has(purpose), 'invalid_email_proof_purpose');
  return acquire(origin, purpose, 'admin.email_otp.send', options);
}

export function consumeEmailProof(proof, origin, purpose) {
  need(EMAIL_PURPOSES.has(purpose), 'invalid_email_proof_purpose');
  return consume(proof, origin, purpose);
}

// The legacy password path has its own proof purpose and challenge operation.
export function acquirePasswordProof({ origin }, options = {}) {
  return acquire(origin, 'password', 'admin.password.sign_in', options);
}

export function consumePasswordProof(proof, origin) {
  return consume(proof, origin, 'password');
}
