import { consumeEmailProof, consumePasswordProof } from './human_login.mjs';
import { ADMIN_ROUTES, adminCookie, createAdminTransport, hasUnexpectedCookie } from './admin_http_transport.mjs';
import { AdminSessionState, admitLogin } from './admin_session_state.mjs';
import {
  OperatorError, authorityKey, emailVerification, hasFreshEmailVerification, keys, need, plain, uuid,
} from './contract.mjs';

function challengeReceipt(value, initial) {
  keys(value, ['challenge_id', 'retry_after', 'expires_in', 'delivery_status'], initial ? ['channel'] : []);
  uuid(value.challenge_id);
  need(value.retry_after === 60 && Number.isSafeInteger(value.expires_in) &&
    value.expires_in >= 0 && value.expires_in <= 300 &&
    ['accepted', 'unknown'].includes(value.delivery_status), 'invalid_email_challenge');
  if (initial) need(value.channel === 'email', 'invalid_email_challenge');
  return structuredClone(value);
}

function validateCode(challengeId, code) {
  uuid(challengeId);
  need(typeof code === 'string' && /^[0-9]{6}$/.test(code), 'invalid_email_code');
}

function unknownOutcome(error, fallback = 'transport_outcome_unknown') {
  return new OperatorError(error?.code ?? fallback, { unknown: true });
}

export class AdminHttp {
  #origin;
  #clock;
  #session;
  #send;
  #challenges = new Map();
  #sendAttempt = 0;

  constructor({ origin, fetchImpl = fetch, onFence = () => {}, clock = Date.now, timeoutMs = 15000 }) {
    this.#send = createAdminTransport({ origin, fetchImpl, timeoutMs });
    this.#origin = origin;
    this.#clock = clock;
    this.#session = new AdminSessionState(() => {
      this.#sendAttempt++;
      this.#challenges.clear();
      onFence();
    });
  }

  get origin() { return this.#origin; }
  snapshot() { return this.#session.snapshot(); }
  clear() { this.#session.clear(); }

  metadata() {
    const snapshot = this.snapshot();
    let authenticationState = 'unconfigured_or_unavailable';
    if (snapshot) {
      if (snapshot.proofState !== 'available') authenticationState = 'email_verification_unavailable';
      else authenticationState = hasFreshEmailVerification(snapshot, this.#clock())
        ? 'verified_email_session' : 'email_verification_required';
    }
    return {
      authentication_state: authenticationState,
      authority_evidence: 'last_successful_readback; every action rechecks',
      origin: this.#origin,
      operator_session: snapshot?.user.sessionId ?? null,
      role: snapshot?.user.role ?? null,
      assurance_level: snapshot?.user.assuranceLevel ?? null,
      expires_at: snapshot?.user.expiresAt ?? null,
      credentials_persisted: false,
      browser_cookie_extraction: false,
    };
  }

  async #request(route, body, signal) {
    const epoch = this.#session.epoch;
    const { value, headers, status, ok } = await this.#send(route, body, {
      ...this.#session.credentials(),
      signal,
      assertCurrent: () => this.#session.assertEpoch(epoch),
    });

    try {
      this.#session.assertEpoch(epoch);
    } catch (error) {
      if (route.method === 'POST') throw unknownOutcome(error);
      throw error;
    }

    if (!ok) {
      const code = plain(value?.error) && typeof value.error.code === 'string' &&
        /^[a-z_]{1,80}$/.test(value.error.code) ? value.error.code : 'request_rejected';
      if (status === 401) this.clear();
      else if (status === 403) this.#session.unavailable();
      throw new OperatorError(code, { unknown: status >= 500 });
    }

    try {
      need(route.successStatus === undefined || status === route.successStatus, 'unexpected_response_status');
      need(plain(value), 'invalid_response_envelope');
      if (route.cookie === 'login') return admitLogin(value, headers, this.#clock());
      if (route.cookie === 'remove') {
        keys(value, ['ok']);
        need(value.ok === true, 'invalid_logout_envelope');
        adminCookie(headers, { deletion: true });
      } else {
        need(!hasUnexpectedCookie(headers, route.cookie), 'unexpected_auth_rotation');
      }
      return value;
    } catch (error) {
      if (route.method === 'POST') throw unknownOutcome(error);
      throw error;
    }
  }

  async #readSession(epoch, signal) {
    try {
      return await this.#request(ADMIN_ROUTES.session, undefined, signal);
    } catch (error) {
      if (error.code !== 'session_refresh_pending') throw error;
      this.#session.assertEpoch(epoch);
      // A refresh-lease refusal allows exactly one further GET.
      return this.#request(ADMIN_ROUTES.session, undefined, signal);
    }
  }

  async refresh({ signal } = {}) {
    let epoch = this.#session.epoch;
    let phase = 'session_read';
    try {
      const body = await this.#readSession(epoch, signal);
      this.#session.assertEpoch(epoch);
      phase = 'session_admission';
      const before = this.#session.acceptSession(body, this.#clock());
      epoch = before.epoch;
      phase = 'proof';
      const sidecar = await this.#request(ADMIN_ROUTES.emailStatus, undefined, signal);
      this.#session.assertAuthority(before);
      const proof = emailVerification(sidecar, before.user.sessionId, this.#clock());
      return this.#session.acceptProof(proof);
    } catch (error) {
      if (epoch === this.#session.epoch) {
        if (phase === 'session_admission' ||
            (phase === 'session_read' && error.code === 'unexpected_auth_rotation')) this.clear();
        else this.#session.unavailable();
      }
      throw error;
    }
  }

  async #loginResult(login, epoch, signal) {
    this.#session.assertEpoch(epoch);
    this.#session.acceptLogin(login);
    const current = await this.refresh({ signal });
    this.#session.assertAuthority(current);
    need(authorityKey(login.user) === authorityKey(current.user), 'login_session_readback_mismatch');
    return current;
  }

  async signIn(email, password, proof, { signal } = {}) {
    need(typeof email === 'string' && email.length <= 254 && !/[\r\n\x00]/.test(email) &&
      typeof password === 'string' && password.length > 0 && password.length <= 512, 'invalid_credentials_input');
    this.clear();
    const { generation, epoch } = this.#session;
    let accepted = false;
    try {
      const captcha_token = consumePasswordProof(proof, this.#origin);
      const login = await this.#request(ADMIN_ROUTES.passwordLogin, { email, password, captcha_token }, signal);
      accepted = true;
      return await this.#loginResult(login, epoch, signal);
    } catch (error) {
      if (generation === this.#session.generation) {
        if (accepted) this.#session.unavailable();
        else this.clear();
      }
      if (accepted) throw unknownOutcome(error, 'login_readback_unknown');
      throw error;
    }
  }

  async requestEmailSignIn(email, proof, { signal } = {}) {
    need(typeof email === 'string' && email.length <= 254 &&
      /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email), 'invalid_email_input');
    this.clear();
    const captcha_token = consumeEmailProof(proof, this.#origin, 'sign_in');
    const epoch = this.#session.epoch;
    const attempt = ++this.#sendAttempt;
    let replied = false;
    try {
      const body = await this.#request(ADMIN_ROUTES.signInChallenge, { email, captcha_token }, signal);
      replied = true;
      const challenge = challengeReceipt(body, true);
      need(epoch === this.#session.epoch && attempt === this.#sendAttempt, 'email_attempt_changed');
      this.#rememberChallenge(challenge, { purpose: 'sign_in', epoch, attempt });
      return challenge;
    } catch (error) {
      if (replied && !error.outcomeUnknown) throw unknownOutcome(error);
      throw error;
    }
  }

  #rememberChallenge(value, binding) {
    this.#challenges.set(value.challenge_id, {
      ...binding,
      expiresAt: this.#clock() + value.expires_in * 1000,
      busy: false,
    });
  }

  #forgetChallenge(challengeId, challenge) {
    if (this.#challenges.get(challengeId) === challenge) this.#challenges.delete(challengeId);
  }

  async verifyEmailSignIn(challengeId, code, { signal } = {}) {
    validateCode(challengeId, code);
    const { epoch, generation } = this.#session;
    const challenge = this.#challenges.get(challengeId);
    need(challenge?.purpose === 'sign_in' && challenge.epoch === epoch &&
      challenge.expiresAt > this.#clock() && !challenge.busy, 'current_bound_email_challenge_required');

    challenge.busy = true;
    let accepted = false;
    try {
      const login = await this.#request(ADMIN_ROUTES.signInVerification, { challenge_id: challengeId, code }, signal);
      accepted = true;
      this.#forgetChallenge(challengeId, challenge);
      const current = await this.#loginResult(login, epoch, signal);
      need(hasFreshEmailVerification(current, this.#clock()), 'recent_email_sign_in_required');
      return current;
    } catch (error) {
      if (!error.outcomeUnknown && !accepted && this.#challenges.get(challengeId) === challenge) challenge.busy = false;
      else this.#forgetChallenge(challengeId, challenge);

      if (accepted) {
        if (generation === this.#session.generation) this.#session.unavailable();
        throw unknownOutcome(error, 'login_readback_unknown');
      }
      throw error;
    }
  }

  async requestEmailVerification(proof, { signal } = {}) {
    const before = await this.refresh({ signal });
    this.#session.assertAuthority(before);
    if (this.#session.verificationPending) throw new OperatorError('admin_email_operation_unknown', { unknown: true });
    const captcha_token = consumeEmailProof(proof, this.#origin, 'sensitive');
    const attempt = ++this.#sendAttempt;
    this.#challenges.clear();
    let replied = false;
    try {
      const body = await this.#request(ADMIN_ROUTES.emailChallenge, { captcha_token }, signal);
      replied = true;
      const challenge = challengeReceipt(body, false);
      this.#session.assertAuthority(before);
      need(attempt === this.#sendAttempt, 'email_attempt_changed');
      this.#rememberChallenge(challenge, {
        purpose: 'sensitive', epoch: before.epoch, attempt, authority: before.authority,
      });
      return challenge;
    } catch (error) {
      if (replied && !error.outcomeUnknown) throw unknownOutcome(error);
      throw error;
    }
  }

  async verifyEmail(challengeId, code, { signal } = {}) {
    validateCode(challengeId, code);
    const challenge = this.#challenges.get(challengeId);
    need(challenge?.purpose === 'sensitive' && !challenge.busy, 'current_bound_email_challenge_required');

    const before = await this.refresh({ signal });
    this.#session.assertAuthority(before);
    const generation = this.#session.generation;
    need(challenge === this.#challenges.get(challengeId) && !challenge.busy &&
      challenge.epoch === before.epoch && challenge.authority === before.authority &&
      challenge.expiresAt > this.#clock(), 'current_bound_email_challenge_required');

    challenge.busy = true;
    let accepted = false;
    try {
      const value = await this.#request(ADMIN_ROUTES.emailVerification, { challenge_id: challengeId, code }, signal);
      accepted = true;
      this.#session.assertAuthority(before);
      need(challenge === this.#challenges.get(challengeId) && challenge.attempt === this.#sendAttempt, 'email_attempt_changed');
      const parsed = emailVerification(value, before.user.sessionId, this.#clock());
      need(hasFreshEmailVerification({ ...before, emailVerifiedAt: parsed.emailVerifiedAt, proofState: 'available' },
        this.#clock()), 'recent_email_sign_in_required');
      return this.#session.acceptProof(parsed, { forceFence: true });
    } catch (error) {
      if (!error.outcomeUnknown && !accepted && error.code === 'invalid_credentials' &&
          this.#challenges.get(challengeId) === challenge) {
        challenge.busy = false;
      } else {
        this.#forgetChallenge(challengeId, challenge);
        this.#session.verificationFailed(generation, before, accepted || error.outcomeUnknown);
      }
      if (accepted && !error.outcomeUnknown) throw unknownOutcome(error);
      throw error;
    }
  }

  async ensure(operatorSession, permission, { signal } = {}) {
    uuid(operatorSession);
    const before = await this.refresh({ signal });
    this.#session.assertAuthority(before);
    need(before.user.sessionId === operatorSession, 'original_public_session_required');
    need(hasFreshEmailVerification(before, this.#clock()), 'recent_email_sign_in_required');
    need(before.user.permissions.includes(permission), 'permission_required');
    return before;
  }

  async operator(action, args, before, { signal } = {}) {
    this.#session.assertAuthority(before, 'session_changed_before_dispatch');
    const result = await this.#request(ADMIN_ROUTES.notificationOperator, { action, ...args }, signal);
    need(result.ok === true && Object.keys(result).sort().join(',') === 'ok,result', 'invalid_operator_envelope');
    this.#session.assertAuthority(before);
    await this.refresh({ signal });
    this.#session.assertAuthority(before);
    return result.result;
  }

  async logout() {
    this.#session.fence();
    const generation = this.#session.generation;
    try {
      await this.#request(ADMIN_ROUTES.logout, {}, undefined);
    } finally {
      if (generation === this.#session.generation) this.clear();
    }
  }
}

// Historical source compatibility; active callers use the provider-neutral class.
export { AdminHttp as CloudflareAdminHttp };
