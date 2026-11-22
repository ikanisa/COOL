#!/usr/bin/env node
import { configuration, isUuid, SafeError } from './config.mjs';
import { RetentionApi } from './retention_api.mjs';
import { acquireHumanChallenge } from './human_challenge.mjs';
import { runTerminalCommand, secretPrompt } from './operator_terminal.mjs';

const PROOF_LIFETIME_MS = 300_000;

function originalProof(proof, sessionId) {
  if (sessionId !== undefined && proof.sessionId !== sessionId) {
    throw new SafeError('retention_session_changed', 'The original local Admin session is unavailable. Keep the original operation references.');
  }
  return proof;
}

/** Recover an uncertain verification against the original session once. */
export async function verifyCurrentEmail(api, challengeId, code, {
  requestedAfter = Date.now() - PROOF_LIFETIME_MS,
  sessionId,
} = {}) {
  try {
    return originalProof(await api.verifyEmail(challengeId, code, { sessionId }), sessionId);
  } catch (error) {
    if (error instanceof SafeError && error.code === 'retention_session_changed') throw error;
    try {
      const proof = originalProof(await api.verificationStatus({ sessionId }), sessionId);
      const at = proof.emailVerifiedAt === null ? 0 : Date.parse(proof.emailVerifiedAt);
      const now = Date.now();
      if (at >= requestedAfter && at <= now && now - at <= PROOF_LIFETIME_MS) return proof;
    } catch { /* The original code remains unconfirmed. */ }
    if (error instanceof SafeError) throw error;
    throw new SafeError('email_verification_unknown', 'Email verification is unconfirmed. Check the original session; no code was replayed.');
  }
}

export function verificationArguments(args, interactive) {
  if (!interactive || args.length !== 0 && !(args.length === 2 && args[0] === 'resume' && isUuid(args[1]))) {
    throw new SafeError('interactive_verification_required', 'Run npm run verify-email directly in a terminal, optionally with resume and the original challenge UUID. Email codes, passwords and CAPTCHA tokens in arguments, pipes or environment variables are not accepted.');
  }
  return args[1] ?? null;
}

async function requestOriginalChallenge(config, api, sessionId) {
  let token = await acquireHumanChallenge(config, {
    operation: 'admin.email_otp.send',
    onPairing: ({ descriptor, parentUrl }) => {
      process.stderr.write(`Open ${parentUrl} in your normal browser and connect this public challenge:\n${JSON.stringify(descriptor)}\n`);
    },
  });
  try {
    const challenge = await api.requestVerification(token, { sessionId });
    process.stderr.write(`Original verification reference: ${challenge.challenge_id}\n`);
    process.stderr.write(challenge.delivery_status === 'unknown'
      ? 'Delivery is unconfirmed. Enter the original code if it arrives; no replacement was requested.\n'
      : 'The code request was accepted. Enter the code sent to this Admin account email.\n');
    process.stderr.write(`Expires within ${challenge.expires_in} seconds. Keep the same local session; do not sign in again.\n`);
    return challenge.challenge_id;
  } finally { token = ''; }
}

async function main() {
  const existing = verificationArguments(process.argv.slice(2), process.stdin.isTTY && process.stderr.isTTY);
  const config = configuration(), api = new RetentionApi(config);
  const current = await api.verificationStatus();
  if (!existing && current.emailVerifiedAt !== null && Date.now() - Date.parse(current.emailVerifiedAt) < 240_000) {
    process.stderr.write('This same Admin session already has fresh email verification. No new code was requested.\n');
    return;
  }
  const requestedAfter = Date.now() - 1000;
  const challengeId = existing ?? await requestOriginalChallenge(config, api, current.sessionId);
  let code = await secretPrompt('Email code (hidden): ', 6);
  try {
    const proof = await verifyCurrentEmail(api, challengeId, code, {
      sessionId: current.sessionId,
      requestedAfter: existing ? Date.now() - PROOF_LIFETIME_MS : requestedAfter,
    });
    process.stderr.write(`Email verification is current as of ${proof.emailVerifiedAt}. The original Admin session and operation references are preserved.\n`);
  } finally { code = ''; }
}

runTerminalCommand(import.meta.url, main, 'Email verification could not be confirmed. No code or session credential was printed.');
