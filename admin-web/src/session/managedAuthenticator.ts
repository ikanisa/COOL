import {AdminRequestError, type AdminRequest} from '../api/client';
import {clearMfaAuthorityCheckpoint, createMfaAuthorityCheckpoint, mfaActorDigest, mfaIntentDigest, readMfaAuthorityCheckpoint, writeMfaAuthorityCheckpoint, type MfaAuthorityCheckpoint} from './mfaAuthority';
import {MANAGED_MFA_TRANSITION_QUALIFIED} from './mfaQualification';
import {clearMfaRecoveryIntent, mfaRecoveryDelay, readMfaRecoveryIntent, writeMfaRecoveryIntent, type MfaRecoveryIntent} from './mfaRecovery';
import {clearMfaTransition, mfaTransitionIdentity, readMfaTransitions, retainMfaTransition} from './mfaTransition';
import {orderedPermissions} from './sessionAuthority';
import {parseAuthenticatorSession, parseEmailProof, type AdminUser} from './sessionResponses';

type TransitionMarker = Awaited<ReturnType<typeof mfaTransitionIdentity>>;

interface AuthenticatorSession {
  request: AdminRequest;
  begin: () => () => boolean;
  hasPendingLogout: () => boolean;
  fenceLogout: () => boolean;
  refresh: () => Promise<void>;
  bindPending: (user: AdminUser, current: () => boolean) => Promise<boolean>;
  install: (user: AdminUser) => void;
  fail: (message: string) => void;
}

export function hasStoredAuthenticatorTransition(): boolean {
  return readMfaRecoveryIntent() !== null || readMfaTransitions().size !== 0;
}

function clearRetainedTransition(marker: TransitionMarker, checkpoint: MfaAuthorityCheckpoint | null, intent: MfaRecoveryIntent) {
  clearMfaTransition(marker);
  if (checkpoint) clearMfaAuthorityCheckpoint(checkpoint);
  clearMfaRecoveryIntent(intent);
}

/** Fields that must not change during the same live authenticator operation. */
function sameMfaActor(left: AdminUser, right: AdminUser): boolean {
  return left.id === right.id && left.sessionId === right.sessionId && left.email === right.email && left.role === right.role &&
    left.principalId === right.principalId && left.financialModel === right.financialModel &&
    (left.mfaAvailable ?? false) === (right.mfaAvailable ?? false) && (left.mfaRequired ?? false) === (right.mfaRequired ?? false) &&
    JSON.stringify(orderedPermissions(left.permissions)) === JSON.stringify(orderedPermissions(right.permissions)) &&
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

export class ManagedAuthenticator {
  private active: {intent: MfaRecoveryIntent; marker: TransitionMarker} | null = null;
  private operation: object | null = null;

  constructor(private readonly session: AuthenticatorSession) {}

  get inProgress() {
    return this.operation !== null;
  }

  get hasActiveTransition() {
    return this.active !== null;
  }

  invalidateTransition() {
    this.active = null;
  }

  reset() {
    this.active = null;
    this.operation = null;
  }

  isBlocked(): boolean {
    // Preparation already advanced the session epoch.
    if (this.operation && !this.active) return false;
    try {
      const intent = readMfaRecoveryIntent();
      const markers = readMfaTransitions();
      if (this.active && sameMfaIntent(intent, this.active.intent) &&
          markers.size === 1 && markers.get(this.active.marker.key) === this.active.marker.session) return false;
      return intent !== null || markers.size !== 0;
    } catch {
      return true;
    }
  }

  async verify(before: AdminUser, factorId: string, challengeId: string, code: string, isCurrent: () => boolean): Promise<void> {
    const random = new Uint8Array(32);
    globalThis.crypto.getRandomValues(random);
    const intent: MfaRecoveryIntent = {
      factor_id: factorId,
      challenge_id: challengeId,
      verification_id: [...random].map(value => value.toString(16).padStart(2, '0')).join(''),
      session_id: before.sessionId,
      user_id: before.id,
      starting_assurance_level: before.assuranceLevel,
      starting_mfa_at_ms: before.mfaAt === null ? null : Date.parse(before.mfaAt),
      created_at_ms: Date.now(),
    };
    const checkpoint = await createMfaAuthorityCheckpoint(intent, before);
    if (!isCurrent()) throw new AdminRequestError('Your sign-in changed. Reopen this page.');
    writeMfaAuthorityCheckpoint(checkpoint);
    writeMfaRecoveryIntent(intent);
    return this.recover(intent, before, code);
  }

  /** Recover the original managed check only; never resubmit an authenticator code. */
  async recover(intent: MfaRecoveryIntent, before: AdminUser | null, code: string | null): Promise<void> {
    if (!MANAGED_MFA_TRANSITION_QUALIFIED) throw new AdminRequestError('Authenticator recovery is unavailable. Sign out of the original session.', {outcomeUnknown: true});
    if (this.operation || this.session.fenceLogout()) throw new AdminRequestError('Authenticator verification is already in progress.', {outcomeUnknown: true});
    const operation = {};
    this.operation = operation;
    const ownsSession = this.session.begin();
    let marker: {key: string; session: string} | null = null;
    let checkpoint: MfaAuthorityCheckpoint | null = null;
    const basic = () => this.operation === operation && ownsSession() && !this.session.hasPendingLogout();
    const current = () => {
      if (!basic() || !marker || this.active?.intent !== intent) return false;
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
      const body = await this.session.request('auth/session', {authenticated: false, expectedStatus: 200}); requireCurrent();
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
        if (code !== null && retained.get(marker.key) === marker.session) {clearRetainedTransition(marker, checkpoint, intent);}
        throw new AdminRequestError('Another authenticator check is still in progress.', {outcomeUnknown: true});
      }
      this.active = {intent, marker};
      requireCurrent();
      // A cold Flutter-origin intent has no original principal/grants baseline.
      // Even an auth/session GET can finalize a candidate cookie, so neither
      // that read nor recovery may run until the original authority is known.
      if (code === null && before === null && !checkpoint) throw new AdminRequestError('The original authenticator authority is unavailable. Reopen the original Admin session or sign out.', {outcomeUnknown: true});
      // Leave enough of the five-minute server window for a lost reply and
      // its mandatory 26-second lease delay; no request was dispatched yet.
      if (code !== null && (mfaRecoveryDelay(intent) === null || Date.now() - intent.created_at_ms > 60_000)) {
        clearRetainedTransition(marker, checkpoint, intent);
        this.reset();
        await this.session.refresh();
        throw new AdminRequestError('The authenticator challenge expired. Request a new code.');
      }
      let waitAfterUnknown = false;
      if (code !== null) {
        try {
          const result = await this.session.request('auth/mfa/verify', {body: {factor_id: intent.factor_id, challenge_id: intent.challenge_id, code, verification_id: intent.verification_id}, authenticated: true});
          requireCurrent(); if (result.ok !== true) waitAfterUnknown = true;
        } catch (failure) {
          requireCurrent();
          if (failure instanceof AdminRequestError && !failure.outcomeUnknown && failure.statusCode !== 401) {
            // The BFF releases its lease only on a definite provider rejection.
            clearRetainedTransition(marker, checkpoint, intent);
            this.reset();
            await this.session.refresh();
            throw failure;
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
        const recovered = await this.session.request('auth/mfa/recover', {body: {factor_id: intent.factor_id, challenge_id: intent.challenge_id, verification_id: intent.verification_id}, authenticated: false, mfaRecovery: true});
        requireCurrent(); if (recovered.ok !== true) throw new AdminRequestError('Authenticator recovery could not be confirmed.', {outcomeUnknown: true});
        candidate = await readCandidate();
      }
      requireCurrent();
      if (!candidate) throw new AdminRequestError('Authenticator verification could not be confirmed.', {outcomeUnknown: true});
      try {
        const proof = await this.session.request('auth/email-verification', {authenticated: false, expectedStatus: 200}); requireCurrent();
        if (typeof proof.sessionId === 'string' && proof.sessionId !== candidate.sessionId) throw new Error('Session mismatch.');
        candidate = {...candidate, emailVerifiedAt: parseEmailProof(proof, candidate, Date.now())};
      } catch (failure) {
        requireCurrent();
        if (failure instanceof Error && failure.message === 'Session mismatch.' || failure instanceof AdminRequestError && failure.statusCode === 401) throw failure;
        candidate = {...candidate, emailVerifiedAt: null};
      }
      if (!(await this.session.bindPending(candidate, current))) throw new AdminRequestError('Your session changed. Reopen this page.', {outcomeUnknown: true});
      requireCurrent();
      clearRetainedTransition(marker, checkpoint, intent);
      this.reset();
      this.session.install(candidate);
    } catch (failure) {
      if (basic()) this.session.fail(failure instanceof Error ? failure.message : 'Authenticator verification could not be confirmed.');
      throw failure;
    } finally {
      if (this.operation === operation) this.reset();
    }
  }
}
