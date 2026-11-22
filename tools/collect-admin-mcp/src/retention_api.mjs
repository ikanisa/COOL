import {loadCredential, SafeError, object, unavailable} from './config.mjs';
import {parseSession, requestJson} from './api.mjs';
import {
  READ_RPC, WRITE_RPC, assertBinding, assertRetentionFields, authorityBinding, instant, isRetentionHash, isRetentionUuid,
} from './retention_contract.mjs';

const SESSION_PATH = '/api/admin/auth/session';
const PROOF_PATH = '/api/admin/auth/email-verification';
const MAX_RPC_BODY_BYTES = 16384;
const EMAIL_SCOPE = Object.freeze({fresh: false, privacy: false});

async function readBoundSession(config, credential) {
  const {value} = await requestJson(config, SESSION_PATH, {cookie: credential.cookie});
  const user = parseSession(value);
  if (credential.accountId !== user.id || credential.sessionId !== user.sessionId || credential.principalId !== user.principalId) {
    throw new SafeError('session_unavailable', 'The original local Admin session is unavailable. No operation was retried.');
  }
  return {user, csrfToken: value.csrfToken};
}

export function parseEmailProof(value, user, {fresh = true} = {}) {
  assertRetentionFields(value, ['contractVersion', 'emailVerifiedAt', 'sessionId']);
  if (value.contractVersion !== 1 || value.sessionId !== user.sessionId ||
      (value.emailVerifiedAt !== null && !instant(value.emailVerifiedAt))) unavailable();
  const at = value.emailVerifiedAt === null ? null : Date.parse(value.emailVerifiedAt);
  const now = Date.now();
  if (at !== null && at > now) unavailable();
  if (fresh && (at === null || now - at > 300000)) {
    throw new SafeError('recent_email_sign_in_required',
      'Run npm run verify-email in a terminal to verify this same Admin session. Do not sign in again while an operation is unresolved.');
  }
  return value;
}

function scopedRequests(config, cookie, csrfToken, {privacy, fresh}) {
  async function post(path, body) {
    return (await requestJson(config, path, {cookie, csrfToken, method: 'POST', body})).value;
  }
  function privacyRpc(routes, name, body) {
    if (!privacy || !fresh || typeof name !== 'string' || !Object.hasOwn(routes, name) || !object(body) ||
      Buffer.byteLength(JSON.stringify(body)) > MAX_RPC_BODY_BYTES) unavailable();
    return post('/api/admin/privacy/' + routes[name], body);
  }
  return {
    read: (name, body = {}) => privacyRpc(READ_RPC, name, body),
    write: (name, body) => privacyRpc(WRITE_RPC, name, body),
    async email(name, body) {
      if (privacy || fresh || !['request', 'verify'].includes(name)) unavailable();
      return post('/api/admin/auth/email/' + name, body);
    },
  };
}

function parseVerificationChallenge(value) {
  assertRetentionFields(value, ['challenge_id', 'delivery_status', 'expires_in', 'retry_after']);
  if (!isRetentionUuid(value.challenge_id) || !['accepted', 'unknown'].includes(value.delivery_status) ||
    value.retry_after !== 60 || !Number.isInteger(value.expires_in) || value.expires_in < 1 || value.expires_in > 1800) unavailable();
  return value;
}

export class RetentionApi {
  constructor(config) { this.config = config; }

  async withSession(action, {fresh = true, privacy = true, sessionId} = {}) {
    const credential = await loadCredential(this.config);
    const {user, csrfToken} = await readBoundSession(this.config, credential);
    if (sessionId !== undefined && user.sessionId !== sessionId) {
      throw new SafeError('retention_session_changed', 'The original local Admin session changed. Keep the original operation references.');
    }
    if (privacy && !user.permissions.includes('privacy.review')) {
      throw new SafeError('permission_denied', 'The current Admin account lacks privacy.review.');
    }
    if (!isRetentionHash(csrfToken)) unavailable();

    const readProof = async () => {
      const {value} = await requestJson(this.config, PROOF_PATH, {cookie: credential.cookie});
      return parseEmailProof(value, user, {fresh});
    };
    const initialProof = await readProof();
    const binding = authorityBinding(user, this.config.origin);
    const requests = scopedRequests(this.config, credential.cookie, csrfToken, {privacy, fresh});
    const result = await action({binding, user, initialProof, ...requests});

    const latest = await loadCredential(this.config);
    if (latest.fingerprint !== credential.fingerprint) {
      throw new SafeError('retention_session_changed', 'The local Admin credential changed. Keep the original operation references.');
    }
    const after = await readBoundSession(this.config, credential);
    assertBinding(authorityBinding(after.user, this.config.origin), binding);
    await readProof();
    return result;
  }

  async verificationStatus({sessionId} = {}) {
    return this.withSession(async ({initialProof}) => initialProof, {...EMAIL_SCOPE, sessionId});
  }

  async requestVerification(captchaToken, {sessionId} = {}) {
    if (typeof captchaToken !== 'string' || captchaToken.length < 1 || captchaToken.length > 2048 ||
      /[\u0000-\u0020\u007f]/.test(captchaToken)) unavailable();
    return this.withSession(async ({email}) =>
      parseVerificationChallenge(await email('request', {captcha_token: captchaToken})), {...EMAIL_SCOPE, sessionId});
  }

  async verifyEmail(challengeId, code, {sessionId} = {}) {
    if (!isRetentionUuid(challengeId) || typeof code !== 'string' || !/^\d{6}$/.test(code)) {
      throw new SafeError('invalid_arguments', 'Use the current six-digit email verification code.');
    }
    return this.withSession(async ({email, user}) =>
      parseEmailProof(await email('verify', {challenge_id: challengeId, code}), user), {...EMAIL_SCOPE, sessionId});
  }
}
