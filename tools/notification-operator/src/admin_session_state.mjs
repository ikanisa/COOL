import { OperatorError, authorityKey, keys, need, publicSession, sensitiveAuthorityKey } from './contract.mjs';
import { adminCookie, csrfFor } from './admin_http_transport.mjs';

export function admitLogin(value, headers, now) {
  const cookie = adminCookie(headers);
  keys(value, ['user', 'expiresAt', 'csrfToken']);
  const user = publicSession(value.user, now);
  need(value.expiresAt === user.expiresAt, 'session_expiry_mismatch');
  need(value.csrfToken === csrfFor(cookie), 'csrf_cookie_binding_invalid');
  return { user, cookie, csrf: value.csrfToken };
}

export class AdminSessionState {
  // Authority changes within a login advance the epoch. Clearing custody also
  // advances the generation so an older operation cannot affect a later login.
  #epoch = 0;
  #generation = 0;
  #user = null;
  #cookie = null;
  #csrf = null;
  #emailVerifiedAt = null;
  #proofState = 'unavailable';
  #unknownVerification = null;
  #onFence;

  constructor(onFence) {
    this.#onFence = onFence;
  }

  get epoch() { return this.#epoch; }
  get generation() { return this.#generation; }
  get verificationPending() { return this.#unknownVerification !== null; }

  credentials() {
    return { cookie: this.#cookie, csrf: this.#csrf };
  }

  snapshot() {
    if (!this.#user) return null;
    return {
      epoch: this.#epoch,
      user: structuredClone(this.#user),
      authority: sensitiveAuthorityKey(this.#user, this.#emailVerifiedAt),
      emailVerifiedAt: this.#emailVerifiedAt,
      proofState: this.#proofState,
    };
  }

  assertEpoch(epoch) {
    need(epoch === this.#epoch, 'session_changed_during_request');
  }

  assertAuthority(before, errorCode = 'session_changed_during_request') {
    need(before && this.#user && this.#epoch === before.epoch &&
      sensitiveAuthorityKey(this.#user, this.#emailVerifiedAt) === before.authority, errorCode);
  }

  fence() {
    this.#epoch++;
    this.#onFence();
  }

  clear() {
    this.#generation++;
    this.#user = null;
    this.#cookie = null;
    this.#csrf = null;
    this.#emailVerifiedAt = null;
    this.#unknownVerification = null;
    this.#proofState = 'unavailable';
    this.fence();
  }

  unavailable() {
    if (!this.#user) return;
    this.#proofState = 'unavailable';
    this.fence();
  }

  acceptLogin(login) {
    this.#user = login.user;
    this.#cookie = login.cookie;
    this.#csrf = login.csrf;
    this.fence();
  }

  acceptSession(value, now) {
    keys(value, ['user', 'expiresAt', 'ownerEmail', 'csrfToken']);
    if (value.user === null) {
      this.clear();
      throw new OperatorError('authentication_required');
    }

    const user = publicSession(value.user, now);
    need(value.expiresAt === user.expiresAt && typeof value.ownerEmail === 'string' &&
      value.ownerEmail.length <= 254, 'invalid_session_metadata');
    need(this.#cookie && value.csrfToken === csrfFor(this.#cookie), 'csrf_cookie_binding_invalid');

    const changed = this.#user && authorityKey(this.#user) !== authorityKey(user);
    this.#user = user;
    this.#csrf = value.csrfToken;
    if (changed) this.unavailable();
    return this.snapshot();
  }

  acceptProof({ sessionId, emailVerifiedAt }, { forceFence = false } = {}) {
    const held = this.#unknownVerification;
    if (held) {
      const newer = held.sessionId === sessionId && held.user === authorityKey(this.#user) &&
        emailVerifiedAt !== null && Date.parse(emailVerifiedAt) >
          (held.emailVerifiedAt === null ? -Infinity : Date.parse(held.emailVerifiedAt));
      if (!newer) {
        this.#proofState = 'unavailable';
        return this.snapshot();
      }
      this.#unknownVerification = null;
    }

    // A read failure already fenced the old custody. The same timestamp does
    // not establish a new proof event on the next successful read.
    const changed = emailVerifiedAt !== this.#emailVerifiedAt;
    this.#emailVerifiedAt = emailVerifiedAt;
    this.#proofState = 'available';
    if (changed || forceFence) this.fence();
    return this.snapshot();
  }

  verificationFailed(generation, before, unknown) {
    const original = authorityKey(before.user);
    if (generation !== this.#generation || !this.#user || authorityKey(this.#user) !== original) return;

    if (unknown) {
      this.#unknownVerification = {
        sessionId: before.user.sessionId,
        user: original,
        emailVerifiedAt: before.emailVerifiedAt,
      };
    }
    this.unavailable();
  }
}
