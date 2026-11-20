/* eslint-disable no-control-regex -- Reject ASCII control characters in untrusted input. */
import {createContext, useContext, useEffect, useState, useSyncExternalStore, type ReactNode} from 'react';
import {AdminApiClient, AdminRequestError, type AdminBackend, type AdminClientConfig, type AdminRequest, type JsonObject} from '../api/client';
import {bindPendingIdentity} from '../features/core/pendingAttempt';
import {googleAvailable, googleAuthorizationUrl, googleChallenge, openGooglePopup, randomUrlValue, type GooglePopup} from './google';
import {MANAGED_MFA_TRANSITION_QUALIFIED} from './mfaQualification';
import {
  decodeAdminUser, isVerificationUuid, parseAuthenticatorSession, parseEmailProof, parseLogoutSessionId,
  parseSensitiveOtpReceipt, parseSessionUser, parseSignInOtpReceipt, type AdminUser, type OtpReceipt,
} from './sessionResponses';
import {clearLogoutIntent, LOGOUT_INTENT_PREFIX, logoutFingerprint, readLogoutIntents, retainLogoutIntent} from './logoutIntent';
import {clearMfaRecoveryIntent, mfaRecoveryDelay, readMfaRecoveryIntent, writeMfaRecoveryIntent, type MfaRecoveryIntent} from './mfaRecovery';
import {clearMfaTransition, MFA_TRANSITION_PREFIX, mfaTransitionIdentity, readMfaTransitions, retainMfaTransition} from './mfaTransition';
import {clearMfaAuthorityCheckpoint, createMfaAuthorityCheckpoint, mfaActorDigest, mfaIntentDigest, readMfaAuthorityCheckpoint, writeMfaAuthorityCheckpoint, type MfaAuthorityCheckpoint} from './mfaAuthority';
export {isVerifiedCurrentOwner, type AdminOwnerIdentity} from './ownerIdentity';
export type {AdminUser, OtpReceipt} from './sessionResponses';

export interface SensitiveEmailRecovery {kind: 'request' | 'verify'; retryAt: number | null; checked: boolean}

export interface SessionSnapshot {
  status: 'loading' | 'anonymous' | 'authenticated' | 'error';
  user: AdminUser | null;
  error?: string;
  logoutUnconfirmed: boolean;
  mfaRecoveryPending: boolean;
  epoch: number;
}

export interface SessionContextValue extends SessionSnapshot {
  request: AdminRequest;
  refresh: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  googleSignInAvailable: boolean;
  signInWithGoogle: () => Promise<void>;
  cancelGoogleSignIn: () => void;
  requestEmailOtp: (email: string) => Promise<OtpReceipt>;
  verifyEmailOtp: (email: string, challengeId: string, code: string) => Promise<void>;
  requestPasswordReset: (email: string) => Promise<void>;
  completePasswordSetup: (token: string, password: string, invite: boolean) => Promise<void>;
  changePassword: (currentPassword: string, newPassword: string) => Promise<void>;
  clearLocalSession: () => void;
  isCurrentAuthority: (epoch: number, actorId: string, sessionId: string) => boolean;
  isRecentSensitiveVerification: (epoch: number, actorId: string, sessionId: string) => boolean;
  verificationMode: 'email' | 'authenticator';
  requestSensitiveEmailVerification: () => Promise<OtpReceipt>;
  verifySensitiveEmailVerification: (challengeId: string, code: string) => Promise<void>;
  /** Checks only the email step; it does not grant combined sensitive access. */
  recheckEmailVerification: () => Promise<boolean>;
  recheckSensitiveEmailVerification: () => Promise<boolean>;
  sensitiveEmailRecovery: () => SensitiveEmailRecovery | null;
  releaseExpiredSensitiveRequest: () => void;
  cancelSensitiveEmailVerification: () => void;
  verifyAuthenticator: (factorId: string, challengeId: string, code: string) => Promise<void>;
}

const OTP = /^[0-9]{6}$/;

export function normalizeAdminEmail(input: string): string {
  const email = input.trim().toLowerCase();
  if (email.length > 254 || /[\s\x00-\x1f\x7f]/.test(email)) throw new Error('Check the email address.');
  const parts = email.split('@');
  const local = parts[0];
  if (parts.length !== 2 || !local || local.length > 64 || local.startsWith('.') || local.endsWith('.') || local.includes('..') || !/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$/.test(local)) throw new Error('Check the email address.');
  const domain = parts[1].split('.');
  if (domain.length < 2 || domain.some((label) => !label || label.length > 63 || !/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label))) throw new Error('Check the email address.');
  return email;
}

export function parseAdminUser(body: JsonObject, now = Date.now()): AdminUser {
  return decodeAdminUser(body, now);
}

function authorityKey(user: AdminUser): string {
  return JSON.stringify([user.id, user.sessionId, user.email, user.role, [...new Set(user.permissions)].sort(), user.assuranceLevel, user.mfaAt, user.principalId, user.financialModel, user.mfaAvailable ?? false, user.mfaRequired ?? false, user.ownerIdentity ?? null]);
}
// The Google exchange predates policy/owner negotiation: auth/session is the
// authoritative source for these fields, which can be omitted by the exchange.
function loginIdentityKey(user: AdminUser): string {return authorityKey({...user, mfaAvailable: false, mfaRequired: false, ownerIdentity: null});}

/** Earliest expiry of the server-issued proofs required by this account policy. */
export function sensitiveVerificationDeadline(user: AdminUser, backend: AdminBackend, now = Date.now()): number | null {
  const expires = Date.parse(user.expiresAt);
  if (!Number.isFinite(now) || !Number.isFinite(expires) || expires <= now) return null;
  let verified: number;
  if (backend === 'supabase') {
    if (!user.emailVerifiedAt || !/(?:Z|\+00:00)$/.test(user.emailVerifiedAt)) return null;
    const email = Date.parse(user.emailVerifiedAt); if (!Number.isFinite(email) || email > now) return null;
    verified = email;
    if (user.mfaRequired === true) {
      if (user.assuranceLevel !== 2 || !user.mfaAt) return null;
      const mfa = Date.parse(user.mfaAt); if (!Number.isFinite(mfa) || mfa > now + 60_000) return null;
      verified = Math.min(email, mfa);
    }
  } else {
    if (user.assuranceLevel !== 2 || !user.mfaAt) return null;
    verified = Date.parse(user.mfaAt); if (!Number.isFinite(verified) || verified > now + 60_000) return null;
  }
  return Math.min(expires, verified + 300_000);
}

/** Fields that must not change during the same live authenticator operation. */
function sameMfaActor(left: AdminUser, right: AdminUser): boolean {
  return left.id === right.id && left.sessionId === right.sessionId && left.email === right.email && left.role === right.role &&
    left.principalId === right.principalId && left.financialModel === right.financialModel &&
    (left.mfaAvailable ?? false) === (right.mfaAvailable ?? false) && (left.mfaRequired ?? false) === (right.mfaRequired ?? false) &&
    JSON.stringify([...new Set(left.permissions)].sort()) === JSON.stringify([...new Set(right.permissions)].sort()) &&
    JSON.stringify(left.ownerIdentity ?? null) === JSON.stringify(right.ownerIdentity ?? null);
}

function completedMfa(user: AdminUser, intent: MfaRecoveryIntent, now = Date.now()): boolean {
  const at = user.mfaAt === null ? NaN : Date.parse(user.mfaAt);
  return user.id === intent.user_id && user.sessionId === intent.session_id && user.principalId !== null && user.mfaAvailable === true && user.assuranceLevel === 2 &&
    Number.isFinite(at) && at >= intent.created_at_ms - 1_000 && at >= now - 300_000 && at <= now + 60_000 &&
    (intent.starting_assurance_level === 1 || intent.starting_mfa_at_ms !== null && at > intent.starting_mfa_at_ms);
}

function sameMfaIntent(left: MfaRecoveryIntent | null, right: MfaRecoveryIntent): boolean {
  return !!left && left.factor_id === right.factor_id && left.challenge_id === right.challenge_id && left.verification_id === right.verification_id &&
    left.session_id === right.session_id && left.user_id === right.user_id && left.starting_assurance_level === right.starting_assurance_level &&
    left.starting_mfa_at_ms === right.starting_mfa_at_ms && left.created_at_ms === right.created_at_ms;
}

function sameMfaCheckpoint(left: MfaAuthorityCheckpoint | null, right: MfaAuthorityCheckpoint | null): boolean {
  return right === null ? left === null : left !== null && left.version === right.version && left.intent === right.intent && left.authority === right.authority;
}

/** Protect against redirecting outside the Admin after authentication. */
export function safeAdminReturnLocation(location: string | null | undefined): string | null {
  if (!location || location.length > 2000 || /[\x00-\x20\\#]/.test(location) || !location.startsWith('/') || location.startsWith('//')) return null;
  const rawPath = location.split('?')[0];
  if (!(rawPath === '/admin' || rawPath.startsWith('/admin/')) || ['/admin/login', '/admin/forgot-password', '/admin/setup', '/admin/session'].includes(rawPath)) return null;
  try {
    const parsed = new URL(location, 'https://admin.invalid');
    if (parsed.origin !== 'https://admin.invalid' || parsed.pathname !== rawPath || parsed.hash) return null;
    return location;
  } catch { return null; }
}

/** Verification never forwards arbitrary drafts, nested return targets or secrets. */
export function safeAdminVerificationReturnLocation(location: string | null | undefined): string | null {
  const candidate = safeAdminReturnLocation(location);
  if (!candidate) return null;
  const parsed = new URL(candidate, 'https://admin.invalid');
  if (parsed.pathname.startsWith('/admin/security/')) return null;
  try {
    for (const segment of parsed.pathname.split('/')) {
      const decoded = decodeURIComponent(segment);
      if (decoded === '.' || decoded === '..' || /[\x00-\x20/\\]/.test(decoded)) return null;
    }
  } catch {return null;}
  const keys = parsed.pathname === '/admin/requests' ? parsed.searchParams.getAll('key') : [];
  const key = keys.length === 1 && /^[A-Za-z0-9._:-]{8,200}$/.test(keys[0]) ? keys[0] : null;
  return parsed.pathname + (key ? `?key=${encodeURIComponent(key)}` : '');
}

/** Capture one-use setup data in memory and remove it from browser history immediately. */
export function captureSetupLocation(location: Location = window.location, history: History = window.history): {token: string; invite: boolean} | null {
  const hashRoute = location.hash.startsWith('#/admin/setup');
  const source = hashRoute ? location.hash.slice(1) : location.pathname + location.search;
  let parsed: URL;
  try { parsed = new URL(source, location.origin); } catch { return null; }
  if (parsed.pathname !== '/admin/setup') return null;
  const values = parsed.searchParams.getAll('token');
  const invites = parsed.searchParams.getAll('invite');
  history.replaceState(null, '', hashRoute ? '/#/admin/setup' : '/admin/setup');
  if (values.length !== 1 || invites.length > 1 || (invites.length === 1 && !['true', 'false'].includes(invites[0]))) return null;
  const token = values[0];
  if (!/^\S{32,512}$/.test(token)) return null;
  return {token, invite: invites[0] === 'true'};
}

export class AdminSessionController {
  private user: AdminUser | null = null;
  private lastAuthority: string | null = null;
  private csrfToken: string | null = null;
  private epoch = 0;
  private sequence = 0;
  private listeners = new Set<() => void>();
  private snapshot: SessionSnapshot = {status: 'loading', user: null, logoutUnconfirmed: false, mfaRecoveryPending: false, epoch: 0};
  private api: AdminApiClient;
  private expiryTimer: ReturnType<typeof setTimeout> | undefined;
  private refreshTimer: ReturnType<typeof setTimeout> | undefined;
  private otp: {email: string; receipt: OtpReceipt; epoch: number} | null = null;
  private sensitive: {receipt: OtpReceipt; key: string; epoch: number; attempt: number; expires: number} | null = null;
  private sensitiveAttempt = 0;
  private sensitiveUnknown = false;
  private sensitiveUnknownKind: 'request' | 'verify' | null = null;
  private sensitiveUnknownUntil = 0;
  private sensitiveUnknownChecked = false;
  private sensitiveOperation: 'request' | 'verify' | 'check' | null = null;
  private sensitiveBaseline: number | null = null;
  private sensitiveBusy = false;
  private googleAttempt = 0;
  private googlePopup: GooglePopup | null = null;
  private logoutBusy = false;
  private mfaActive: {intent: MfaRecoveryIntent; marker: {key: string; session: string}} | null = null;
  private mfaInFlight: object | null = null;
  private listeningForLogout = false;
  private readonly onLogoutStorage = (event: StorageEvent) => {
    if (event.storageArea !== localStorage) return;
    if (event.key === null || event.key.startsWith(LOGOUT_INTENT_PREFIX)) this.fencePendingLogout();
    if (event.key === null || event.key.startsWith(MFA_TRANSITION_PREFIX)) {
      if (!this.fencePendingMfa() && this.snapshot.mfaRecoveryPending && !this.snapshot.logoutUnconfirmed) void this.refresh().catch(() => undefined);
    }
  };

  constructor(private readonly config: AdminClientConfig) {
    this.api = new AdminApiClient(config, () => {
      this.fencePendingLogout();
      if (!this.logoutBusy) this.fencePendingMfa();
      return {epoch: this.epoch, key: this.user ? authorityKey(this.user) : null, csrfToken: this.csrfToken};
    }, (token) => {this.csrfToken = token;}, () => this.unauthorized());
  }

  private hasPendingLogout(): boolean {
    if (this.config.backend !== 'supabase') return this.snapshot.logoutUnconfirmed;
    try {return this.snapshot.logoutUnconfirmed || readLogoutIntents().size !== 0;} catch {return true;}
  }
  private hasPendingMfa(): boolean {
    if (this.config.backend !== 'supabase') return false;
    try {return readMfaRecoveryIntent() !== null || readMfaTransitions().size !== 0;} catch {return true;}
  }
  private fencePendingMfa(): boolean {
    if (this.config.backend !== 'supabase') return false;
    if (this.mfaInFlight && !this.mfaActive) return false; // Preparation already advanced the epoch.
    let blocked = true;
    try {
      const intent = readMfaRecoveryIntent(), markers = readMfaTransitions(), active = this.mfaActive;
      blocked = !!intent || markers.size !== 0;
      if (active && sameMfaIntent(intent, active.intent) && markers.size === 1 && markers.get(active.marker.key) === active.marker.session) blocked = false;
    } catch { /* Invalid or inaccessible storage fails closed. */ }
    if (blocked && (!this.snapshot.mfaRecoveryPending || this.mfaActive !== null) && !this.snapshot.logoutUnconfirmed) {
      this.epoch++; this.sequence++; this.stopTimers(); this.resetSensitive();
      this.mfaActive = null;
      this.emit('error', 'Authenticator verification is unconfirmed. Recheck the session or sign out.', false, true);
    }
    return blocked;
  }
  private fencePendingLogout(): boolean {
    if (!this.hasPendingLogout()) return false;
    if (!this.snapshot.logoutUnconfirmed) {
      this.epoch++; this.sequence++; this.stopTimers(); this.resetSensitive();
      this.emit('error', 'Sign-out was not confirmed. Try again.', true);
    }
    return true;
  }
  private listenForLogout() {
    if (this.config.backend === 'supabase' && typeof window !== 'undefined' && !this.listeningForLogout) {
      window.addEventListener('storage', this.onLogoutStorage); this.listeningForLogout = true;
    }
  }

  readonly subscribe = (listener: () => void) => {this.listeners.add(listener); return () => this.listeners.delete(listener);};
  readonly getSnapshot = () => this.snapshot;
  private emit(status: SessionSnapshot['status'], error?: string, logoutUnconfirmed = this.snapshot.logoutUnconfirmed, mfaRecoveryPending = false) {
    this.snapshot = {status, user: status === 'authenticated' ? this.user : null, error, logoutUnconfirmed, mfaRecoveryPending, epoch: this.epoch};
    this.listeners.forEach((listener) => listener());
  }
  private stopTimers() {clearTimeout(this.expiryTimer); clearTimeout(this.refreshTimer); this.expiryTimer = undefined; this.refreshTimer = undefined;}
  private resetSensitive() {this.sensitiveAttempt++; this.sensitive = null; this.sensitiveUnknown = false; this.sensitiveUnknownKind = null; this.sensitiveUnknownUntil = 0; this.sensitiveUnknownChecked = false; this.sensitiveOperation = null; this.sensitiveBaseline = null; this.sensitiveBusy = false;}
  private clear() {
    this.config.cancelCaptcha?.();
    this.cancelGoogleSignIn();
    this.epoch++; this.sequence++; this.user = null; this.lastAuthority = null; this.csrfToken = null; this.otp = null;
    this.resetSensitive(); this.stopTimers();
    let logoutPending = false, mfaPending = false;
    if (this.config.backend === 'supabase') {try {logoutPending = readLogoutIntents().size !== 0; mfaPending = readMfaRecoveryIntent() !== null || readMfaTransitions().size !== 0;} catch {logoutPending = true;}}
    this.emit(logoutPending || mfaPending ? 'error' : 'anonymous', logoutPending ? 'Sign-out was not confirmed. Try again.' : mfaPending ? 'Authenticator verification is unconfirmed. Recheck the session or sign out.' : undefined, logoutPending, mfaPending);
  }
  private async bindPending(user: AdminUser | null, current: () => boolean): Promise<boolean> {
    try {return await bindPendingIdentity(user, undefined, undefined, current) !== 'stale';}
    catch {return current();} // Recovery storage remains fail-closed; ordinary sign-in can continue.
  }
  private unauthorized() {
    if (this.fencePendingLogout() || this.hasPendingMfa()) return;
    this.clear();
    const epoch = this.epoch, sequence = this.sequence;
    void this.bindPending(null, () => epoch === this.epoch && sequence === this.sequence && this.snapshot.status === 'anonymous');
  }
  private async confirmedAnonymous() {
    const epoch = this.epoch, sequence = this.sequence, current = () => epoch === this.epoch && sequence === this.sequence;
    if (await this.bindPending(null, current) && current()) this.clear();
  }
  stop() {this.config.cancelCaptcha?.(); this.cancelGoogleSignIn(); this.epoch++; this.sequence++; this.stopTimers(); this.user = null; this.lastAuthority = null; this.csrfToken = null; this.otp = null; this.mfaActive = null; this.mfaInFlight = null; this.resetSensitive(); if (this.listeningForLogout) {window.removeEventListener('storage', this.onLogoutStorage); this.listeningForLogout = false;} this.emit('loading', undefined, false);}

  get googleSignInAvailable(): boolean {
    return typeof window !== 'undefined' && googleAvailable(this.config.backend, this.config.googleEnabled, this.config.supabaseProjectOrigin, window.location.origin);
  }

  readonly cancelGoogleSignIn = () => {
    this.googleAttempt++; this.googlePopup?.cancel(); this.googlePopup = null;
  };

  readonly signInWithGoogle = async () => {
    if (!this.googleSignInAvailable || this.fencePendingLogout() || this.mfaInFlight || this.fencePendingMfa()) throw new AdminRequestError('Google sign-in is unavailable.');
    this.clear();
    const epoch = this.epoch, attempt = ++this.googleAttempt;
    const verifier = randomUrlValue(), state = randomUrlValue(), origin = window.location.origin;
    const popup = openGooglePopup(state, origin); this.googlePopup = popup;
    const current = () => epoch === this.epoch && attempt === this.googleAttempt;
    try {
      const reply = await popup.authorize(async () => {
        const challenge = await googleChallenge(verifier);
        if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.');
        const body = await this.api.request('auth/google/start', {body: {code_challenge: challenge, client_state: state, return_origin: origin}, authenticated: false});
        if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.');
        return googleAuthorizationUrl(body.authorization_url, origin, this.config.supabaseProjectOrigin);
      });
      if (!current() || reply.state !== state) throw new AdminRequestError('Google sign-in could not be verified.');
      if (reply.error) throw new AdminRequestError(reply.error === 'google_sign_in_unconfirmed' ? 'Google sign-in could not be confirmed. Check your session before trying again.' : 'Google sign-in could not finish.', {outcomeUnknown: reply.error === 'google_sign_in_unconfirmed'});
      if (!reply.code || !/^[A-Za-z0-9_-]{43}$/.test(reply.code)) throw new AdminRequestError('Google sign-in could not be verified.');
      const response = await this.api.request('auth/google/exchange', {body: {code: reply.code, code_verifier: verifier, client_state: state}, authenticated: false});
      if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.', {outcomeUnknown: true});
      let expected: AdminUser;
      try {expected = parseAdminUser(response);} catch {throw new AdminRequestError('Google sign-in could not be confirmed. Check your session before trying again.', {outcomeUnknown: true});}
      await this.refresh();
      if (!current() || !this.user || loginIdentityKey(this.user) !== loginIdentityKey(expected)) {this.clear(); throw new AdminRequestError('Google sign-in could not be confirmed.', {outcomeUnknown: true});}
    } finally {if (this.googlePopup === popup) this.googlePopup = null;}
  };

  readonly request: AdminRequest = async (path, options = {}) => {
    if (this.config.backend === 'supabase' && !MANAGED_MFA_TRANSITION_QUALIFIED && path.startsWith('auth/mfa/')) throw new AdminRequestError('Authenticator access is unavailable.');
    if (this.config.backend === 'supabase' && (path === 'auth/mfa/verify' || path === 'auth/mfa/recover')) throw new AdminRequestError('Use the authenticator verification flow for this request.');
    if (this.fencePendingLogout() || this.mfaInFlight || this.fencePendingMfa()) throw new AdminRequestError('Complete the pending session verification before continuing.', {outcomeUnknown: true});
    if ((options.authenticated ?? true) && (this.snapshot.status !== 'authenticated' || !this.user || Date.parse(this.user.expiresAt) <= Date.now())) throw new AdminRequestError('Sign in again to continue.');
    return this.api.request(path, options);
  };

  private install(user: AdminUser) {
    if (this.user && authorityKey(this.user) !== authorityKey(user)) {this.epoch++; this.resetSensitive();}
    this.user = user;
    this.lastAuthority = authorityKey(user);
    this.stopTimers();
    const epoch = this.epoch, key = authorityKey(user);
    const checkExpiry = () => {
      if (this.epoch !== epoch || !this.user || authorityKey(this.user) !== key) return;
      const remaining = Date.parse(this.user.expiresAt) - Date.now();
      if (remaining <= 0) {this.unauthorized(); return;}
      // Browsers clamp/overflow longer delays; re-evaluate until actual expiry.
      this.expiryTimer = setTimeout(checkExpiry, Math.min(remaining, 2_147_483_647));
    };
    checkExpiry();
    if (this.epoch !== epoch || !this.user) return;
    this.refreshTimer = setTimeout(() => {void this.refresh().catch(() => undefined);}, 60_000);
    this.emit('authenticated', undefined, false);
  }

  readonly refresh = async (): Promise<void> => {
    this.listenForLogout();
    if (this.fencePendingLogout()) throw new AdminRequestError('Sign-out is not confirmed. Complete sign-out before signing in again.', {outcomeUnknown: true});
    if (this.config.backend === 'supabase') {
      if (this.mfaInFlight) throw new AdminRequestError('Authenticator verification is already in progress.', {outcomeUnknown: true});
      let intent: MfaRecoveryIntent | null;
      try {intent = readMfaRecoveryIntent();} catch {this.fencePendingMfa(); throw new AdminRequestError('Authenticator recovery could not be verified.', {outcomeUnknown: true});}
      if (intent && !MANAGED_MFA_TRANSITION_QUALIFIED) {
        this.fencePendingMfa();
        throw new AdminRequestError('Authenticator recovery is unavailable. Sign out of the original session.', {outcomeUnknown: true});
      }
      if (intent) return this.recoverManagedMfa(intent, this.user, null);
      if (this.fencePendingMfa()) throw new AdminRequestError('Authenticator verification is still in progress in another tab.', {outcomeUnknown: true});
    }
    let epoch = this.epoch; const sequence = ++this.sequence;
    try {
      const body = await this.api.request('auth/session', {authenticated: false});
      if (epoch !== this.epoch || sequence !== this.sequence) return;
      if (body.user === null) {await this.confirmedAnonymous(); return;}
      let user = this.config.backend === 'supabase' ? parseSessionUser(body, Date.now()) : parseAdminUser(body);
      if (this.lastAuthority && this.lastAuthority !== authorityKey(user)) {
        this.epoch++; epoch = this.epoch; this.user = null; this.resetSensitive(); this.stopTimers(); this.emit('loading');
      }
      if (this.config.backend === 'supabase') {
        try {
          const proof = await this.api.request('auth/email-verification', {authenticated: false, expectedStatus: 200});
          if (epoch !== this.epoch || sequence !== this.sequence) return;
          if (typeof proof.sessionId === 'string' && proof.sessionId !== user.sessionId) throw new Error('Session mismatch.');
          const verifiedAt = parseEmailProof(proof, user, Date.now());
          user = {...user, emailVerifiedAt: this.sensitiveUnknown && (verifiedAt === null || this.sensitiveBaseline !== null && Date.parse(verifiedAt) <= this.sensitiveBaseline) ? null : verifiedAt};
        } catch (failure) {
          if (epoch !== this.epoch || sequence !== this.sequence) return;
          // A retired client must not install the earlier session response
          // after its follow-up proof request was explicitly rejected.
          if (failure instanceof AdminRequestError && failure.statusCode === 426 ||
              failure instanceof Error && failure.message === 'Session mismatch.') throw failure;
          user = {...user, emailVerifiedAt: null};
        }
      }
      if (epoch !== this.epoch || sequence !== this.sequence) return;
      const current = () => epoch === this.epoch && sequence === this.sequence;
      if (!(await this.bindPending(user, current)) || !current() || this.fencePendingLogout() || this.fencePendingMfa()) return;
      this.install(user);
    } catch (failure) {
      if (epoch !== this.epoch || sequence !== this.sequence) return;
      this.epoch++; this.user = null; this.csrfToken = null; this.stopTimers();
      this.emit('error', failure instanceof Error ? failure.message : 'Account access could not be checked.');
      throw failure;
    }
  };

  readonly signIn = async (email: string, password: string) => {
    if (this.fencePendingLogout()) throw new AdminRequestError('Complete sign-out before signing in again.', {outcomeUnknown: true});
    if (this.mfaInFlight || this.fencePendingMfa()) throw new AdminRequestError('Complete the pending session verification before signing in again.', {outcomeUnknown: true});
    const normalized = normalizeAdminEmail(email);
    if (!password || password.length > 512) throw new Error('Check the password.');
    this.clear();
    const body = await this.api.request('auth/login', {body: {email: normalized, password}, authenticated: false});
    let expected: AdminUser;
    try {expected = parseAdminUser(body);} catch {throw new AdminRequestError('Sign-in could not be confirmed. Check your session before trying again.', {outcomeUnknown: true});}
    if (expected.email.toLowerCase() !== normalized) throw new AdminRequestError('Sign-in could not be confirmed.', {outcomeUnknown: true});
    await this.refresh();
    if (!this.user || this.user.id !== expected.id || this.user.sessionId !== expected.sessionId) {this.clear(); throw new AdminRequestError('Sign-in could not be confirmed.', {outcomeUnknown: true});}
  };

  readonly signOut = async () => {
    if (this.config.backend === 'supabase') return this.signOutSupabase();
    this.epoch++; this.sequence++; const epoch = this.epoch, sequence = this.sequence; this.stopTimers(); this.user = null; this.otp = null; this.resetSensitive();
    this.emit('loading', undefined, true);
    try {
      const result = await this.api.request('auth/logout', {body: {}, authenticated: false});
      if (result.ok !== true) throw new AdminRequestError('Sign-out was not confirmed.', {outcomeUnknown: true});
      if (epoch === this.epoch && sequence === this.sequence) await this.confirmedAnonymous();
    } catch (failure) {
      if (epoch === this.epoch && sequence === this.sequence) this.emit('error', 'Sign-out was not confirmed. Try again.', true);
      throw failure;
    }
  };

  /** Match the newer Admin's durable, exact-session sign-out intent. */
  private async signOutSupabase(): Promise<void> {
    if (this.logoutBusy) throw new AdminRequestError('Sign-out is already in progress.');
    this.logoutBusy = true;
    const original = this.user;
    this.epoch++; this.sequence++; const epoch = this.epoch, sequence = this.sequence;
    const current = () => epoch === this.epoch && sequence === this.sequence;
    this.stopTimers(); this.user = null; this.otp = null; this.resetSensitive(); this.emit('loading', undefined, true);
    try {
      let pending = readLogoutIntents();
      const reserve = async (sessionId: string) => {
        const fingerprint = await logoutFingerprint(sessionId);
        if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.', {outcomeUnknown: true});
        pending = readLogoutIntents();
        if (pending.size && !pending.has(fingerprint)) throw new AdminRequestError('Another sign-out is unresolved. Check the original session.', {outcomeUnknown: true});
        retainLogoutIntent(fingerprint);
        if (!readLogoutIntents().has(fingerprint)) throw new Error('Sign-out could not be retained.');
        return fingerprint;
      };
      // A pending upgrade may have replaced or lost the browser cookie while
      // logout starts. Use the exact original recovery capability even when
      // an old CSRF value remains; an ordinary empty-cookie logout can return
      // ok without proving that the pending upgrade was revoked.
      const recovery = readMfaRecoveryIntent();
      if (original && recovery && (original.sessionId !== recovery.session_id || original.id !== recovery.user_id)) throw new AdminRequestError('The pending authenticator check belongs to another session.', {outcomeUnknown: true});
      let fingerprint: string, sessionId: string;
      if (original) {sessionId = original.sessionId; fingerprint = await reserve(sessionId);}
      else if (recovery) {sessionId = recovery.session_id; fingerprint = await reserve(sessionId);}
      else {
        // Read the cookie without installing authority; bind it to the original marker.
        const body = await this.api.request('auth/session', {authenticated: false, expectedStatus: 200});
        if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.', {outcomeUnknown: true});
        const cookieSessionId = parseLogoutSessionId(body, Date.now());
        if (cookieSessionId === null) {
          for (const value of pending) clearLogoutIntent(value);
          if (readLogoutIntents().size) throw new Error('Another sign-out is unresolved.');
          if (current()) await this.confirmedAnonymous();
          return;
        }
        sessionId = cookieSessionId; fingerprint = await reserve(sessionId);
      }
      const result = recovery
        ? await this.api.request('auth/logout', {body: {factor_id: recovery.factor_id, challenge_id: recovery.challenge_id, verification_id: recovery.verification_id}, authenticated: false, mfaRecovery: true})
        : await this.api.request('auth/logout', {body: {}, authenticated: false});
      if (!current() || result.ok !== true) throw new AdminRequestError('Sign-out was not confirmed.', {outcomeUnknown: true});
      clearLogoutIntent(fingerprint);
      // A successful exact-session logout revokes this recovery capability too.
      try {
        const retained = readMfaRecoveryIntent();
        if (retained?.session_id === sessionId) {
          const transition = await mfaTransitionIdentity(retained);
          if (!current()) throw new Error('Your session changed.');
          const checkpoint = readMfaAuthorityCheckpoint();
          if (checkpoint && checkpoint.intent !== await mfaIntentDigest(retained)) throw new Error('Authenticator authority could not be verified.');
          if (!current()) throw new Error('Your session changed.');
          const transitions = readMfaTransitions();
          if (transitions.has(transition.key)) clearMfaTransition(transition);
          if (checkpoint) clearMfaAuthorityCheckpoint(checkpoint);
          clearMfaRecoveryIntent(retained);
        }
      } catch { /* Preserve malformed or inaccessible recovery data. */ }
      if (readLogoutIntents().size) throw new AdminRequestError('Another sign-out is unresolved.', {outcomeUnknown: true});
      if (current()) await this.confirmedAnonymous();
    } catch (failure) {
      if (current()) this.emit('error', 'Sign-out was not confirmed. Try again.', true);
      throw failure;
    } finally {this.logoutBusy = false;}
  }

  readonly requestEmailOtp = async (email: string): Promise<OtpReceipt> => {
    if (this.fencePendingLogout()) throw new AdminRequestError('Complete sign-out before signing in again.', {outcomeUnknown: true});
    if (this.mfaInFlight || this.fencePendingMfa()) throw new AdminRequestError('Complete the pending session verification before signing in again.', {outcomeUnknown: true});
    const normalized = normalizeAdminEmail(email);
    this.clear(); const epoch = this.epoch;
    let body: JsonObject, deliveryUnknown = false;
    try {body = await this.api.request('auth/otp', {body: {email: normalized}, authenticated: false});}
    catch (failure) {
      if (!(failure instanceof AdminRequestError) || failure.code !== 'email_delivery_unknown' || !failure.otpReceiptBody) throw failure;
      body = failure.otpReceiptBody; deliveryUnknown = true;
    }
    if (this.epoch !== epoch) throw new AdminRequestError('Your sign-in changed. Try again.');
    const parsed = parseSignInOtpReceipt(body);
    const receipt = {...parsed, deliveryUnknown: deliveryUnknown || parsed.deliveryUnknown};
    this.otp = {email: normalized, receipt, epoch};
    return receipt;
  };

  readonly verifyEmailOtp = async (email: string, challengeId: string, code: string) => {
    if (this.fencePendingLogout()) throw new AdminRequestError('Complete sign-out before signing in again.', {outcomeUnknown: true});
    if (this.mfaInFlight || this.fencePendingMfa()) throw new AdminRequestError('Complete the pending session verification before signing in again.', {outcomeUnknown: true});
    const normalized = normalizeAdminEmail(email), pending = this.otp;
    if (!pending || pending.email !== normalized || pending.receipt.challengeId !== challengeId || pending.epoch !== this.epoch || !OTP.test(code.trim())) throw new Error('Request a fresh sign-in code.');
    let expected: AdminUser | null = null, response: JsonObject | null = null;
    try {
      response = await this.api.request('auth/verify', {body: {email: normalized, challenge_id: challengeId, code: code.trim()}, authenticated: false});
    } catch (failure) {
      if (!(failure instanceof AdminRequestError && failure.outcomeUnknown)) throw failure;
    }
    if (response) {
      try {expected = parseAdminUser(response);} catch {expected = null;}
      if (expected && expected.email.toLowerCase() !== normalized) {this.clear(); throw new AdminRequestError('Sign-in could not be confirmed.', {outcomeUnknown: true});}
    }
    if (pending !== this.otp || pending.epoch !== this.epoch) throw new AdminRequestError('Your sign-in changed. Try again.');
    await this.refresh();
    if (!this.user || this.user.email.toLowerCase() !== normalized || (expected && (this.user.id !== expected.id || this.user.sessionId !== expected.sessionId))) throw new AdminRequestError('Sign-in could not be confirmed. Check your session before requesting a new code.', {outcomeUnknown: true});
    this.otp = null;
  };

  readonly requestPasswordReset = async (email: string) => {
    if (this.fencePendingLogout()) throw new AdminRequestError('Complete sign-out before continuing.', {outcomeUnknown: true});
    if (this.mfaInFlight || this.fencePendingMfa()) throw new AdminRequestError('Complete the pending session verification before continuing.', {outcomeUnknown: true});
    const result = await this.api.request('auth/forgot-password', {body: {email: normalizeAdminEmail(email)}, authenticated: false});
    if (result.ok !== true) throw new AdminRequestError('The request was not confirmed.', {outcomeUnknown: true});
  };
  readonly completePasswordSetup = async (token: string, password: string, invite: boolean) => {
    if (this.fencePendingLogout()) throw new AdminRequestError('Complete sign-out before continuing.', {outcomeUnknown: true});
    if (this.mfaInFlight || this.fencePendingMfa()) throw new AdminRequestError('Complete the pending session verification before continuing.', {outcomeUnknown: true});
    if (!/^\S{32,512}$/.test(token) || password.length < 12 || password.length > 128) throw new Error('Check the password and link.');
    const result = await this.api.request('auth/complete-password', {body: {token, password, invite}, authenticated: false});
    if (result.ok !== true) throw new AdminRequestError('The password result is not confirmed. Sign in using your email code or request a new reset link.', {outcomeUnknown: true});
    await this.confirmedAnonymous();
  };

  readonly clearLocalSession = () => this.clear();
  readonly isCurrentAuthority = (epoch: number, actorId: string, sessionId: string) => !this.hasPendingLogout() && !this.hasPendingMfa() && this.snapshot.status === 'authenticated' && this.epoch === epoch && this.user?.id === actorId && this.user.sessionId === sessionId && Date.parse(this.user.expiresAt) > Date.now();
  readonly isRecentSensitiveVerification = (epoch: number, actorId: string, sessionId: string) => {
    if (!this.isCurrentAuthority(epoch, actorId, sessionId) || !this.user) return false;
    const now = Date.now(), deadline = sensitiveVerificationDeadline(this.user, this.config.backend, now);
    return deadline !== null && deadline >= now;
  };
  readonly changePassword = async (currentPassword: string, newPassword: string) => {
    const actor = this.user;
    if (!actor || this.snapshot.status !== 'authenticated' || !actor.permissions.includes('account.manage')) throw new AdminRequestError('Your account cannot change this password.');
    if (!currentPassword || currentPassword.length > 512 || newPassword.length < 12 || newPassword.length > 128 || currentPassword === newPassword) throw new Error('Enter your current password and a different new password of 12 to 128 characters.');
    const epoch = this.epoch, key = authorityKey(actor);
    if (this.config.backend === 'supabase' && !(await this.recheckSensitiveEmailVerification())) throw new AdminRequestError('Verify your email before making this change.', {code: 'recent_email_sign_in_required'});
    if (epoch !== this.epoch || !this.user || authorityKey(this.user) !== key) throw new AdminRequestError('Your sign-in changed. Reopen account security.');
    const result = await this.request('auth/change-password', {body: {currentPassword, newPassword}, authenticated: true, expectedStatus: 200});
    if (result.ok !== true) throw new AdminRequestError('The password result is not confirmed. Sign in using your email code or request a reset.', {outcomeUnknown: true});
    await this.confirmedAnonymous();
  };

  readonly requestSensitiveEmailVerification = async (): Promise<OtpReceipt> => {
    const actor = this.user;
    if (this.config.backend !== 'supabase' || !actor || this.snapshot.status !== 'authenticated') throw new Error('Email verification is unavailable.');
    if (this.sensitiveBusy || this.sensitiveUnknown) throw new Error('Check the current verification before requesting another code.');
    const epoch = this.epoch, key = authorityKey(actor), attempt = ++this.sensitiveAttempt; this.sensitiveBusy = true; this.sensitiveOperation = 'request'; this.sensitiveUnknownUntil = Date.now() + 300_000;
    try {
      const body = await this.request('auth/email/request', {body: {}, authenticated: true, expectedStatus: 202});
      const receipt = parseSensitiveOtpReceipt(body);
      if (attempt !== this.sensitiveAttempt || epoch !== this.epoch || !this.user || authorityKey(this.user) !== key) throw new AdminRequestError('Your sign-in changed. Try again.');
      this.sensitive = {receipt, key, epoch, attempt, expires: Date.now() + receipt.expiresInSeconds * 1000};
      return receipt;
    } catch (failure) {if (attempt === this.sensitiveAttempt && epoch === this.epoch && failure instanceof AdminRequestError && failure.outcomeUnknown) {this.sensitiveUnknown = true; this.sensitiveUnknownKind = 'request'; this.sensitiveUnknownChecked = false;} throw failure;}
    finally {if (attempt === this.sensitiveAttempt) {this.sensitiveBusy = false; this.sensitiveOperation = null;}}
  };

  readonly verifySensitiveEmailVerification = async (challengeId: string, code: string) => {
    const actor = this.user, pending = this.sensitive;
    if (!actor || !pending || this.sensitiveBusy || this.sensitiveUnknown || pending.attempt !== this.sensitiveAttempt || pending.epoch !== this.epoch || pending.key !== authorityKey(actor) || pending.receipt.challengeId !== challengeId || pending.expires <= Date.now() || !OTP.test(code.trim())) throw new Error('Use the current six-digit email code.');
    this.sensitiveBusy = true; this.sensitiveOperation = 'verify'; this.sensitiveBaseline = actor.emailVerifiedAt ? Date.parse(actor.emailVerifiedAt) : null;
    this.user = {...actor, emailVerifiedAt: null}; this.emit('authenticated');
    try {
      const body = await this.request('auth/email/verify', {body: {challenge_id: challengeId, code: code.trim()}, authenticated: true, expectedStatus: 200});
      let proof: string | null;
      try {proof = parseEmailProof(body, actor, Date.now());} catch {throw new AdminRequestError('Email verification could not be confirmed. Check verification.', {outcomeUnknown: true});}
      if (!proof || (this.sensitiveBaseline !== null && Date.parse(proof) <= this.sensitiveBaseline) || Date.now() - Date.parse(proof) > 300_000) throw new AdminRequestError('Email verification could not be confirmed. Check verification.', {outcomeUnknown: true});
      if (pending.attempt !== this.sensitiveAttempt || pending.epoch !== this.epoch || !this.user || pending.key !== authorityKey(this.user)) throw new AdminRequestError('Your sign-in changed. Try again.', {outcomeUnknown: true});
      this.user = {...this.user, emailVerifiedAt: proof}; this.sensitive = null; this.sensitiveUnknown = false; this.sensitiveUnknownKind = null; this.sensitiveBaseline = null; this.emit('authenticated');
    } catch (failure) {
      if (pending.attempt === this.sensitiveAttempt && pending.epoch === this.epoch) {
        if (failure instanceof AdminRequestError && failure.outcomeUnknown) {this.sensitiveUnknown = true; this.sensitiveUnknownKind = 'verify'; this.sensitiveUnknownChecked = false;}
        else this.sensitiveBaseline = null;
      }
      throw failure;
    } finally {if (pending.attempt === this.sensitiveAttempt) {this.sensitiveBusy = false; this.sensitiveOperation = null;}}
  };

  readonly recheckEmailVerification = async (): Promise<boolean> => {
    const actor = this.user;
    if (!actor || this.config.backend !== 'supabase' || this.sensitiveBusy) throw new Error('Verification is unavailable.');
    const epoch = this.epoch, key = authorityKey(actor), attempt = this.sensitiveAttempt; this.sensitiveBusy = true; this.sensitiveOperation = 'check';
    try {
      const proof = parseEmailProof(await this.request('auth/email-verification', {authenticated: true, expectedStatus: 200}), actor, Date.now());
      if (attempt !== this.sensitiveAttempt || epoch !== this.epoch || !this.user || authorityKey(this.user) !== key) throw new Error('Your sign-in changed.');
      const admitted = proof !== null && (!this.sensitiveUnknown || this.sensitiveBaseline === null || Date.parse(proof) > this.sensitiveBaseline) ? proof : null;
      this.user = {...this.user, emailVerifiedAt: admitted}; this.emit('authenticated');
      if (admitted && Date.now() - Date.parse(admitted) <= 300_000) {this.sensitiveUnknown = false; this.sensitiveUnknownKind = null; this.sensitiveBaseline = null; this.sensitive = null; return this.isCurrentAuthority(epoch, actor.id, actor.sessionId);}
      if (this.sensitiveUnknownKind === 'request') this.sensitiveUnknownChecked = true;
      return false;
    } catch (failure) {
      if (attempt === this.sensitiveAttempt && epoch === this.epoch && this.user && authorityKey(this.user) === key) {this.user = {...this.user, emailVerifiedAt: null}; this.emit('authenticated');}
      throw failure;
    } finally {if (attempt === this.sensitiveAttempt) {this.sensitiveBusy = false; this.sensitiveOperation = null;}}
  };

  readonly recheckSensitiveEmailVerification = async (): Promise<boolean> => {
    const actor = this.user, epoch = this.epoch;
    if (!actor) throw new Error('Verification is unavailable.');
    return await this.recheckEmailVerification() && this.isRecentSensitiveVerification(epoch, actor.id, actor.sessionId);
  };

  readonly sensitiveEmailRecovery = (): SensitiveEmailRecovery | null => this.sensitiveUnknown && this.sensitiveUnknownKind ? {kind: this.sensitiveUnknownKind, retryAt: this.sensitiveUnknownKind === 'request' ? this.sensitiveUnknownUntil : null, checked: this.sensitiveUnknownChecked} : null;
  readonly releaseExpiredSensitiveRequest = () => {
    if (this.sensitiveBusy || !this.sensitiveUnknown || this.sensitiveUnknownKind !== 'request' || !this.sensitiveUnknownChecked || Date.now() < this.sensitiveUnknownUntil) throw new Error('Check verification and wait before requesting a new code.');
    this.sensitiveUnknown = false; this.sensitiveUnknownKind = null; this.sensitiveUnknownUntil = 0; this.sensitiveUnknownChecked = false; this.sensitive = null;
  };
  readonly cancelSensitiveEmailVerification = () => {
    if (this.sensitiveBusy && (this.sensitiveOperation === 'request' || this.sensitiveOperation === 'verify')) {
      this.sensitiveUnknown = true; this.sensitiveUnknownKind = this.sensitiveOperation; this.sensitiveUnknownChecked = false;
    }
    this.sensitiveAttempt++; this.sensitive = null; this.sensitiveBusy = false; this.sensitiveOperation = null;
  };

  /** Recover the original managed check only; never resubmit an authenticator code. */
  private async recoverManagedMfa(intent: MfaRecoveryIntent, before: AdminUser | null, code: string | null): Promise<void> {
    if (!MANAGED_MFA_TRANSITION_QUALIFIED) throw new AdminRequestError('Authenticator recovery is unavailable. Sign out of the original session.', {outcomeUnknown: true});
    if (this.mfaInFlight || this.fencePendingLogout()) throw new AdminRequestError('Authenticator verification is already in progress.', {outcomeUnknown: true});
    const operation = {}; this.mfaInFlight = operation;
    this.epoch++; this.sequence++; const epoch = this.epoch, sequence = this.sequence;
    this.stopTimers(); this.resetSensitive(); this.emit('loading', undefined, false, true);
    let marker: {key: string; session: string} | null = null;
    let checkpoint: MfaAuthorityCheckpoint | null = null;
    const basic = () => this.mfaInFlight === operation && this.epoch === epoch && this.sequence === sequence && !this.hasPendingLogout();
    const current = () => {
      if (!basic() || !marker || this.mfaActive?.intent !== intent) return false;
      try {const markers = readMfaTransitions(); return sameMfaIntent(readMfaRecoveryIntent(), intent) && sameMfaCheckpoint(readMfaAuthorityCheckpoint(), checkpoint) && markers.size === 1 && markers.get(marker.key) === marker.session;}
      catch {return false;}
    };
    const requireCurrent = () => {if (!current()) throw new AdminRequestError('Your session changed. Reopen this page.', {outcomeUnknown: true});};
    const waitUntilRecoverable = async (atLeast = 0) => {
      const remaining = mfaRecoveryDelay(intent);
      if (remaining === null) throw new AdminRequestError('The authenticator result cannot be recovered automatically. Sign out and sign in again.', {outcomeUnknown: true});
      const delay = Math.max(remaining, atLeast);
      if (delay) await new Promise<void>((resolve) => setTimeout(resolve, delay));
      requireCurrent();
      if (mfaRecoveryDelay(intent) === null) throw new AdminRequestError('The authenticator result cannot be recovered automatically. Sign out and sign in again.', {outcomeUnknown: true});
    };
    const readCandidate = async (): Promise<AdminUser | null> => {
      const body = await this.api.request('auth/session', {authenticated: false, expectedStatus: 200}); requireCurrent();
      const candidate = parseAuthenticatorSession(body, Date.now());
      if (candidate.id !== intent.user_id || candidate.sessionId !== intent.session_id || before && !sameMfaActor(before, candidate)) throw new AdminRequestError('Your sign-in changed. Reopen this page.', {outcomeUnknown: true});
      if (!before && candidate.mfaRequired === true && !checkpoint) throw new AdminRequestError('The original authenticator authority is unavailable.', {outcomeUnknown: true});
      if (checkpoint && checkpoint.authority !== await mfaActorDigest(candidate)) throw new AdminRequestError('Your sign-in changed. Reopen this page.', {outcomeUnknown: true});
      requireCurrent();
      return completedMfa(candidate, intent) ? candidate : null;
    };
    try {
      checkpoint = readMfaAuthorityCheckpoint();
      if (checkpoint && (checkpoint.intent !== await mfaIntentDigest(intent) || before && checkpoint.authority !== await mfaActorDigest(before))) throw new AdminRequestError('The original authenticator authority could not be verified.', {outcomeUnknown: true});
      if (!basic() || !sameMfaCheckpoint(readMfaAuthorityCheckpoint(), checkpoint)) throw new AdminRequestError('Your session changed. Reopen this page.', {outcomeUnknown: true});
      marker = await mfaTransitionIdentity(intent);
      if (!basic() || !sameMfaIntent(readMfaRecoveryIntent(), intent)) throw new AdminRequestError('Your session changed. Reopen this page.', {outcomeUnknown: true});
      const existing = readMfaTransitions();
      if (existing.size && (existing.size !== 1 || existing.get(marker.key) !== marker.session)) {
        // A new intent has not been dispatched yet; no recovery is needed for it.
        if (code !== null) {if (checkpoint) clearMfaAuthorityCheckpoint(checkpoint); clearMfaRecoveryIntent(intent);}
        throw new AdminRequestError('Another authenticator check is still in progress.', {outcomeUnknown: true});
      }
      retainMfaTransition(marker);
      const retained = readMfaTransitions();
      if (retained.size !== 1 || retained.get(marker.key) !== marker.session) {
        if (code !== null && retained.get(marker.key) === marker.session) {clearMfaTransition(marker); if (checkpoint) clearMfaAuthorityCheckpoint(checkpoint); clearMfaRecoveryIntent(intent);}
        throw new AdminRequestError('Another authenticator check is still in progress.', {outcomeUnknown: true});
      }
      this.mfaActive = {intent, marker}; requireCurrent();
      // A cold Flutter-origin intent has no original principal/grants baseline.
      // Even an auth/session GET can finalize a candidate cookie, so neither
      // that read nor recovery may run until the original authority is known.
      if (code === null && before === null && !checkpoint) throw new AdminRequestError('The original authenticator authority is unavailable. Reopen the original Admin session or sign out.', {outcomeUnknown: true});
      // Leave enough of the five-minute server window for a lost reply and
      // its mandatory 26-second lease delay; no request was dispatched yet.
      if (code !== null && (mfaRecoveryDelay(intent) === null || Date.now() - intent.created_at_ms > 60_000)) {
        clearMfaTransition(marker); if (checkpoint) clearMfaAuthorityCheckpoint(checkpoint); clearMfaRecoveryIntent(intent);
        this.mfaActive = null; this.mfaInFlight = null; await this.refresh();
        throw new AdminRequestError('The authenticator challenge expired. Request a new code.');
      }
      let waitAfterUnknown = false;
      if (code !== null) {
        try {
          const result = await this.api.request('auth/mfa/verify', {body: {factor_id: intent.factor_id, challenge_id: intent.challenge_id, code, verification_id: intent.verification_id}, authenticated: true});
          requireCurrent(); if (result.ok !== true) waitAfterUnknown = true;
        } catch (failure) {
          requireCurrent();
          if (failure instanceof AdminRequestError && !failure.outcomeUnknown && failure.statusCode !== 401) {
            // The BFF releases its lease only on a definite provider rejection.
            clearMfaTransition(marker); if (checkpoint) clearMfaAuthorityCheckpoint(checkpoint); clearMfaRecoveryIntent(intent); this.mfaActive = null; this.mfaInFlight = null;
            await this.refresh(); throw failure;
          }
          waitAfterUnknown = true;
        }
      }
      if (code === null || waitAfterUnknown) await waitUntilRecoverable(waitAfterUnknown ? 26_000 : 0);
      let candidate: AdminUser | null = null;
      try {candidate = await readCandidate();}
      catch (failure) {
        if (!(failure instanceof AdminRequestError && failure.statusCode === 409 && failure.code === 'mfa_recovery_pending')) throw failure;
      }
      if (!candidate) {
        await waitUntilRecoverable();
        const recovered = await this.api.request('auth/mfa/recover', {body: {factor_id: intent.factor_id, challenge_id: intent.challenge_id, verification_id: intent.verification_id}, authenticated: false, mfaRecovery: true});
        requireCurrent(); if (recovered.ok !== true) throw new AdminRequestError('Authenticator recovery could not be confirmed.', {outcomeUnknown: true});
        candidate = await readCandidate();
      }
      requireCurrent();
      if (!candidate) throw new AdminRequestError('Authenticator verification could not be confirmed.', {outcomeUnknown: true});
      try {
        const proof = await this.api.request('auth/email-verification', {authenticated: false, expectedStatus: 200}); requireCurrent();
        if (typeof proof.sessionId === 'string' && proof.sessionId !== candidate.sessionId) throw new Error('Session mismatch.');
        candidate = {...candidate, emailVerifiedAt: parseEmailProof(proof, candidate, Date.now())};
      } catch (failure) {
        requireCurrent();
        if (failure instanceof Error && failure.message === 'Session mismatch.' || failure instanceof AdminRequestError && failure.statusCode === 401) throw failure;
        candidate = {...candidate, emailVerifiedAt: null};
      }
      if (!(await this.bindPending(candidate, current))) throw new AdminRequestError('Your session changed. Reopen this page.', {outcomeUnknown: true});
      requireCurrent();
      clearMfaTransition(marker); if (checkpoint) clearMfaAuthorityCheckpoint(checkpoint); clearMfaRecoveryIntent(intent);
      this.mfaActive = null; this.mfaInFlight = null; this.install(candidate);
    } catch (failure) {
      if (basic()) this.emit('error', failure instanceof Error ? failure.message : 'Authenticator verification could not be confirmed.', false, true);
      throw failure;
    } finally {
      if (this.mfaInFlight === operation) {this.mfaInFlight = null; this.mfaActive = null;}
    }
  }

  readonly verifyAuthenticator = async (factorId: string, challengeId: string, code: string): Promise<void> => {
    if (this.config.backend === 'supabase' && !MANAGED_MFA_TRANSITION_QUALIFIED) throw new AdminRequestError('Authenticator access is unavailable.');
    const before = this.user;
    if (!before || !before.principalId || !isVerificationUuid(factorId) || !isVerificationUuid(challengeId) || !OTP.test(code)) throw new Error('Enter the current six-digit authenticator code.');
    if (this.config.backend === 'supabase') {
      if (!before.mfaAvailable || !this.isCurrentAuthority(this.epoch, before.id, before.sessionId) || this.mfaInFlight || this.sensitiveBusy || this.sensitiveUnknown) throw new AdminRequestError('Complete the current email verification before using the authenticator.');
      const random = new Uint8Array(32); globalThis.crypto.getRandomValues(random);
      const intent: MfaRecoveryIntent = {factor_id: factorId, challenge_id: challengeId, verification_id: [...random].map(value => value.toString(16).padStart(2, '0')).join(''), session_id: before.sessionId, user_id: before.id, starting_assurance_level: before.assuranceLevel, starting_mfa_at_ms: before.mfaAt === null ? null : Date.parse(before.mfaAt), created_at_ms: Date.now()};
      const epoch = this.epoch, authority = authorityKey(before), checkpoint = await createMfaAuthorityCheckpoint(intent, before);
      if (!this.isCurrentAuthority(epoch, before.id, before.sessionId) || !this.user || authorityKey(this.user) !== authority || this.mfaInFlight || this.sensitiveBusy || this.sensitiveUnknown) throw new AdminRequestError('Your sign-in changed. Reopen this page.');
      writeMfaAuthorityCheckpoint(checkpoint);
      writeMfaRecoveryIntent(intent);
      return this.recoverManagedMfa(intent, before, code);
    }
    const result = await this.request('auth/mfa/verify', {body: {factor_id: factorId, challenge_id: challengeId, code}, authenticated: true});
    if (result.ok !== true) throw new AdminRequestError('Verification could not be confirmed. Recheck your session.', {outcomeUnknown: true});
    // Verification rotates the server cookie; fence work issued under the old cookie.
    this.epoch++; this.sequence++; this.stopTimers();
    try {await this.refresh();} catch {throw new AdminRequestError('Verification could not be confirmed. Recheck your session.', {outcomeUnknown: true});}
    const current = this.user, now = Date.now();
    if (!current || current.id !== before.id || current.email !== before.email || current.sessionId !== before.sessionId || current.principalId !== before.principalId || current.role !== before.role || JSON.stringify([...new Set(current.permissions)].sort()) !== JSON.stringify([...new Set(before.permissions)].sort()) || current.assuranceLevel !== 2 || !current.mfaAt || Date.parse(current.mfaAt) < now - 300_000 || Date.parse(current.mfaAt) > now + 60_000) {
      this.clear();
      throw new AdminRequestError('Verification could not be confirmed. Recheck your session.', {outcomeUnknown: true});
    }
  };
}

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({config, children}: {config: AdminClientConfig; children: ReactNode}) {
  const [controller] = useState(() => new AdminSessionController(config));
  const snapshot = useSyncExternalStore(controller.subscribe, controller.getSnapshot, controller.getSnapshot);
  useEffect(() => {void controller.refresh().catch(() => undefined); return () => controller.stop();}, [controller]);
  const value: SessionContextValue = {...snapshot, request: controller.request, refresh: controller.refresh, signIn: controller.signIn, signOut: controller.signOut, googleSignInAvailable: controller.googleSignInAvailable, signInWithGoogle: controller.signInWithGoogle, cancelGoogleSignIn: controller.cancelGoogleSignIn, requestEmailOtp: controller.requestEmailOtp, verifyEmailOtp: controller.verifyEmailOtp, requestPasswordReset: controller.requestPasswordReset, completePasswordSetup: controller.completePasswordSetup, changePassword: controller.changePassword, clearLocalSession: controller.clearLocalSession, isCurrentAuthority: controller.isCurrentAuthority, isRecentSensitiveVerification: controller.isRecentSensitiveVerification, verificationMode: config.backend === 'supabase' ? 'email' : 'authenticator', requestSensitiveEmailVerification: controller.requestSensitiveEmailVerification, verifySensitiveEmailVerification: controller.verifySensitiveEmailVerification, recheckEmailVerification: controller.recheckEmailVerification, recheckSensitiveEmailVerification: controller.recheckSensitiveEmailVerification, sensitiveEmailRecovery: controller.sensitiveEmailRecovery, releaseExpiredSensitiveRequest: controller.releaseExpiredSensitiveRequest, cancelSensitiveEmailVerification: controller.cancelSensitiveEmailVerification, verifyAuthenticator: controller.verifyAuthenticator};
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error('SessionProvider is required.');
  return value;
}
