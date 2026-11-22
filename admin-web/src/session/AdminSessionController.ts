import {AdminApiClient, AdminRequestError, type AdminClientConfig, type AdminRequest} from '../api/client';
import {isVerificationUuid} from '../api/contracts';
import {bindPendingIdentity} from '../features/core/pendingAttempt';
import {AdminSignIn} from './adminSignIn';
import {ManagedAuthenticator, hasStoredAuthenticatorTransition} from './managedAuthenticator';
import {confirmManagedLogout} from './managedLogout';
import {authorityKey, matchesPredecessorAuthenticator} from './sessionAuthority';
import {changeAccountPassword, completePasswordSetup} from './passwordActions';
import {OTP, sensitiveVerificationDeadline} from './sessionPolicy';
import {MANAGED_MFA_TRANSITION_QUALIFIED} from './mfaQualification';
import type {SessionSnapshot} from './sessionContext';
import {readAdminSession, readSessionEmailProof, type SessionReadback} from './sessionReadback';
import type {AdminUser} from './sessionResponses';
import {LOGOUT_INTENT_PREFIX, readLogoutIntents} from './logoutIntent';
import {readMfaRecoveryIntent, type MfaRecoveryIntent} from './mfaRecovery';
import {MFA_TRANSITION_PREFIX} from './mfaTransition';
import {SensitiveEmailVerification} from './sensitiveEmailVerification';

const LOGOUT_UNCONFIRMED = 'Sign-out was not confirmed. Try again.';
const AUTHENTICATOR_UNCONFIRMED = 'Authenticator verification is unconfirmed. Recheck the session or sign out.';
const VERIFY_AUTHENTICATOR_RESULT = 'Verification could not be confirmed. Recheck your session.';

export class AdminSessionController {
  private user: AdminUser | null = null;
  private lastAuthority: string | null = null;
  private csrfToken: string | null = null;
  private epoch = 0;
  private readRevision = 0;
  private listeners = new Set<() => void>();
  private snapshot: SessionSnapshot = {status: 'loading', user: null, logoutUnconfirmed: false, mfaRecoveryPending: false, epoch: 0};
  private readonly api: AdminApiClient;
  private expiryTimer: ReturnType<typeof setTimeout> | undefined;
  private refreshTimer: ReturnType<typeof setTimeout> | undefined;
  private readonly signInFlow = new AdminSignIn({
    config: () => this.config,
    request: (...args) => this.api.request(...args),
    epoch: () => this.epoch,
    clear: () => this.clear(),
    fenceLogout: () => this.fencePendingLogout(),
    fenceVerification: () => this.authenticator.inProgress || this.fencePendingMfa(),
    restore: (readback) => this.restoreSession(readback),
  });
  private readonly emailVerification = new SensitiveEmailVerification({
    current: () => ({actor: this.user, epoch: this.epoch, authenticated: this.snapshot.status === 'authenticated'}),
    backend: () => this.config.backend,
    authorityKey,
    request: (...args) => this.request(...args),
    updateProof: (proof) => {
      if (!this.user) return;
      // Discard a refresh that read the proof before this transition.
      this.readRevision++;
      this.user = {...this.user, emailVerifiedAt: proof};
      this.emit('authenticated');
    },
    isCurrentAuthority: (...args) => this.isCurrentAuthority(...args),
  });
  private logoutBusy = false;
  private readonly authenticator = new ManagedAuthenticator({
    request: (...args) => this.api.request(...args),
    begin: () => this.beginTransition('authenticator'),
    hasPendingLogout: () => this.hasPendingLogout(),
    fenceLogout: () => this.fencePendingLogout(),
    refresh: () => this.refresh(),
    bindPending: (user, current) => this.bindPending(user, current),
    install: (user) => this.install(user),
    fail: (message) => this.emit('error', message, false, true),
  });
  private listeningForRetainedSessions = false;
  private readonly onRetainedSessionChange = (event: StorageEvent) => {
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
    try {return hasStoredAuthenticatorTransition();} catch {return true;}
  }
  private fencePendingMfa(): boolean {
    if (this.config.backend !== 'supabase') return false;
    const blocked = this.authenticator.isBlocked();
    if (blocked && (!this.snapshot.mfaRecoveryPending || this.authenticator.hasActiveTransition) && !this.snapshot.logoutUnconfirmed) {
      this.invalidateAuthority();
      this.emailVerification.reset();
      this.authenticator.invalidateTransition();
      this.emit('error', AUTHENTICATOR_UNCONFIRMED, false, true);
    }
    return blocked;
  }
  private fencePendingLogout(): boolean {
    if (!this.hasPendingLogout()) return false;
    if (!this.snapshot.logoutUnconfirmed) {
      this.invalidateAuthority();
      this.emailVerification.reset();
      this.emit('error', LOGOUT_UNCONFIRMED, true);
    }
    return true;
  }
  private observeRetainedSessions() {
    if (this.config.backend === 'supabase' && typeof window !== 'undefined' && !this.listeningForRetainedSessions) {
      window.addEventListener('storage', this.onRetainedSessionChange);
      this.listeningForRetainedSessions = true;
    }
  }

  readonly subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };
  readonly getSnapshot = () => this.snapshot;
  private emit(status: SessionSnapshot['status'], error?: string, logoutUnconfirmed = this.snapshot.logoutUnconfirmed, mfaRecoveryPending = false) {
    this.snapshot = {status, user: status === 'authenticated' ? this.user : null, error, logoutUnconfirmed, mfaRecoveryPending, epoch: this.epoch};
    this.listeners.forEach((listener) => listener());
  }
  private stopTimers() {
    clearTimeout(this.expiryTimer);
    clearTimeout(this.refreshTimer);
    this.expiryTimer = undefined;
    this.refreshTimer = undefined;
  }

  /** Retire all current transport responses and readbacks. */
  private invalidateAuthority() {
    this.epoch++;
    this.readRevision++;
    this.stopTimers();
  }

  private ownsCurrentRevision(stillOwns?: () => boolean): () => boolean {
    const epoch = this.epoch;
    const revision = this.readRevision;
    return () => epoch === this.epoch && revision === this.readRevision && (stillOwns?.() ?? true);
  }

  private resetLocalAuthority() {
    this.config.cancelCaptcha?.();
    this.cancelGoogleSignIn();
    this.invalidateAuthority();
    this.user = null;
    this.lastAuthority = null;
    this.csrfToken = null;
    this.signInFlow.clearOtp();
    this.emailVerification.reset();
  }

  private clear() {
    this.resetLocalAuthority();
    let logoutPending = false;
    let mfaPending = false;
    if (this.config.backend === 'supabase') {
      try {
        logoutPending = readLogoutIntents().size !== 0;
        mfaPending = hasStoredAuthenticatorTransition();
      } catch {
        logoutPending = true;
      }
    }
    const message = logoutPending ? LOGOUT_UNCONFIRMED : mfaPending ? AUTHENTICATOR_UNCONFIRMED : undefined;
    this.emit(message ? 'error' : 'anonymous', message, logoutPending, mfaPending);
  }

  private async bindPending(user: AdminUser | null, current: () => boolean): Promise<boolean> {
    try {return await bindPendingIdentity(user, undefined, undefined, current) !== 'stale';}
    catch {return current();} // Recovery storage remains fail-closed; ordinary sign-in can continue.
  }

  private unauthorized() {
    if (this.fencePendingLogout() || this.hasPendingMfa()) return;
    this.clear();
    const ownsRevision = this.ownsCurrentRevision();
    void this.bindPending(null, () => ownsRevision() && this.snapshot.status === 'anonymous');
  }

  private async confirmedAnonymous(stillOwns?: () => boolean): Promise<boolean> {
    const current = this.ownsCurrentRevision(stillOwns);
    if (!(await this.bindPending(null, current)) || !current()) return false;
    this.clear();
    return true;
  }

  stop() {
    this.resetLocalAuthority();
    this.authenticator.reset();
    if (this.listeningForRetainedSessions) {
      window.removeEventListener('storage', this.onRetainedSessionChange);
      this.listeningForRetainedSessions = false;
    }
    this.emit('loading', undefined, false);
  }

  get googleSignInAvailable(): boolean {
    return this.signInFlow.googleSignInAvailable;
  }

  readonly cancelGoogleSignIn = this.signInFlow.cancelGoogleSignIn;
  readonly signInWithGoogle = this.signInFlow.signInWithGoogle;
  readonly signIn = this.signInFlow.signIn;
  readonly requestEmailOtp = this.signInFlow.requestEmailOtp;
  readonly verifyEmailOtp = this.signInFlow.verifyEmailOtp;
  readonly requestPasswordReset = this.signInFlow.requestPasswordReset;

  readonly request: AdminRequest = async (path, options = {}) => {
    if (this.config.backend === 'supabase' && !MANAGED_MFA_TRANSITION_QUALIFIED && path.startsWith('auth/mfa/')) throw new AdminRequestError('Authenticator access is unavailable.');
    if (this.config.backend === 'supabase' && (path === 'auth/mfa/verify' || path === 'auth/mfa/recover')) throw new AdminRequestError('Use the authenticator verification flow for this request.');
    if (this.fencePendingLogout() || this.authenticator.inProgress || this.fencePendingMfa()) throw new AdminRequestError('Complete the pending session verification before continuing.', {outcomeUnknown: true});
    if (options.authenticated ?? true) {
      const expired = this.user !== null && Date.parse(this.user.expiresAt) <= Date.now();
      if (expired) this.unauthorized();
      if (expired || this.snapshot.status !== 'authenticated' || !this.user) throw new AdminRequestError('Sign in again to continue.');
    }
    return this.api.request(path, options);
  };

  private install(user: AdminUser) {
    const key = authorityKey(user);
    if (this.user && authorityKey(this.user) !== key) {
      this.epoch++;
      this.emailVerification.reset();
    }
    this.user = user;
    this.lastAuthority = key;
    this.stopTimers();
    const epoch = this.epoch;
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

  readonly refresh = async (): Promise<void> => {await this.restoreSession();};

  private async restoreSession(readback?: SessionReadback): Promise<boolean> {
    if (readback?.isCurrent && !readback.isCurrent()) return false;
    this.observeRetainedSessions();
    if (this.fencePendingLogout()) throw new AdminRequestError('Sign-out is not confirmed. Complete sign-out before signing in again.', {outcomeUnknown: true});
    if (this.config.backend === 'supabase') {
      if (this.authenticator.inProgress) throw new AdminRequestError('Authenticator verification is already in progress.', {outcomeUnknown: true});
      let intent: MfaRecoveryIntent | null;
      try {intent = readMfaRecoveryIntent();} catch {this.fencePendingMfa(); throw new AdminRequestError('Authenticator recovery could not be verified.', {outcomeUnknown: true});}
      if (intent && !MANAGED_MFA_TRANSITION_QUALIFIED) {
        this.fencePendingMfa();
        throw new AdminRequestError('Authenticator recovery is unavailable. Sign out of the original session.', {outcomeUnknown: true});
      }
      if (intent) {
        if (readback) {
          this.fencePendingMfa();
          throw new AdminRequestError('Complete the pending session verification before continuing.', {outcomeUnknown: true});
        }
        await this.authenticator.recover(intent, this.user, null);
        return false;
      }
      if (this.fencePendingMfa()) throw new AdminRequestError('Authenticator verification is still in progress in another tab.', {outcomeUnknown: true});
    }
    let epoch = this.epoch;
    const revision = ++this.readRevision;
    const current = () => epoch === this.epoch && revision === this.readRevision && (readback?.isCurrent?.() ?? true);
    try {
      const session = await readAdminSession(this.api.request, this.config.backend, current);
      if (!session || !current()) return false;
      let user = session.user;
      if (user === null) {
        if (readback) throw new AdminRequestError(readback.message, {outcomeUnknown: true});
        await this.confirmedAnonymous();
        return false;
      }
      // Apply the exchange identity before exposing the session or rebinding
      // the saved requests associated with the previous browser authority.
      if (readback && !readback.matches(user)) throw new AdminRequestError(readback.message, {outcomeUnknown: true});
      if (this.lastAuthority && this.lastAuthority !== authorityKey(user)) {
        // This readback owns the new epoch until it binds the confirmed account.
        epoch = ++this.epoch;
        this.user = null;
        this.csrfToken = null;
        this.emailVerification.reset();
        this.stopTimers();
        this.emit('loading');
      }
      if (this.config.backend === 'supabase') {
        const verifiedAt = await readSessionEmailProof(this.api.request, user, current);
        if (!current()) return false;
        user = {...user, emailVerifiedAt: this.emailVerification.sessionProof(verifiedAt)};
      }
      if (!current() || !(await this.bindPending(user, current)) || !current() || this.fencePendingLogout() || this.fencePendingMfa()) return false;
      if (session.csrfToken !== undefined) this.csrfToken = session.csrfToken;
      this.install(user);
      return this.user === user && this.snapshot.status === 'authenticated';
    } catch (failure) {
      if (!current()) return false;
      this.epoch++;
      this.user = null;
      this.csrfToken = null;
      this.stopTimers();
      this.emit('error', failure instanceof Error ? failure.message : 'Account access could not be checked.');
      throw failure;
    }
  };

  private beginTransition(kind: 'logout' | 'authenticator'): () => boolean {
    this.invalidateAuthority();
    if (kind === 'logout') {
      this.user = null;
      this.signInFlow.clearOtp();
    }
    this.emailVerification.reset();
    const current = this.ownsCurrentRevision();
    this.emit('loading', undefined, kind === 'logout', kind === 'authenticator');
    return current;
  }

  readonly signOut = async () => {
    if (this.config.backend === 'supabase') return this.signOutSupabase();
    const current = this.beginTransition('logout');
    try {
      const result = await this.api.request('auth/logout', {body: {}, authenticated: false});
      if (result.ok !== true) throw new AdminRequestError('Sign-out was not confirmed.', {outcomeUnknown: true});
      if (current()) await this.confirmedAnonymous(current);
    } catch (failure) {
      if (current()) this.emit('error', LOGOUT_UNCONFIRMED, true);
      throw failure;
    }
  };

  /** Match the newer Admin's durable, exact-session sign-out intent. */
  private async signOutSupabase(): Promise<void> {
    if (this.logoutBusy) throw new AdminRequestError('Sign-out is already in progress.');
    this.logoutBusy = true;
    const original = this.user;
    const current = this.beginTransition('logout');
    try {
      await confirmManagedLogout({
        request: this.api.request,
        original,
        current,
        confirmAnonymous: () => this.confirmedAnonymous(current),
      });
    } catch (failure) {
      if (current()) this.emit('error', LOGOUT_UNCONFIRMED, true);
      throw failure;
    } finally {this.logoutBusy = false;}
  }

  readonly completePasswordSetup = async (token: string, password: string, invite: boolean) => {
    if (this.fencePendingLogout()) throw new AdminRequestError('Complete sign-out before continuing.', {outcomeUnknown: true});
    if (this.authenticator.inProgress || this.fencePendingMfa()) throw new AdminRequestError('Complete the pending session verification before continuing.', {outcomeUnknown: true});
    const current = this.ownsCurrentRevision();
    await completePasswordSetup({token, password, invite}, {
      request: this.api.request,
      current,
      confirmAnonymous: () => this.confirmedAnonymous(current),
    });
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
    const epoch = this.epoch;
    const key = authorityKey(actor);
    const current = () => this.epoch === epoch && !!this.user && authorityKey(this.user) === key;
    await changeAccountPassword({currentPassword, newPassword}, {
      request: this.request,
      current,
      confirmAnonymous: () => this.confirmedAnonymous(current),
      verifyEmail: this.config.backend === 'supabase' ? this.recheckSensitiveEmailVerification : undefined,
    });
  };

  readonly requestSensitiveEmailVerification = this.emailVerification.requestCode;
  readonly verifySensitiveEmailVerification = this.emailVerification.verifyCode;
  readonly recheckEmailVerification = this.emailVerification.recheck;
  readonly recheckSensitiveEmailVerification = async (): Promise<boolean> => {
    const actor = this.user, epoch = this.epoch;
    if (!actor) throw new Error('Verification is unavailable.');
    return await this.recheckEmailVerification() && this.isRecentSensitiveVerification(epoch, actor.id, actor.sessionId);
  };

  readonly sensitiveEmailRecovery = this.emailVerification.recovery;
  readonly releaseExpiredSensitiveRequest = this.emailVerification.releaseExpiredRequest;
  readonly cancelSensitiveEmailVerification = this.emailVerification.cancel;

  readonly verifyAuthenticator = async (factorId: string, challengeId: string, code: string): Promise<void> => {
    if (this.config.backend === 'supabase' && !MANAGED_MFA_TRANSITION_QUALIFIED) throw new AdminRequestError('Authenticator access is unavailable.');
    const before = this.user;
    if (!before || !before.principalId || !isVerificationUuid(factorId) || !isVerificationUuid(challengeId) || !OTP.test(code)) throw new Error('Enter the current six-digit authenticator code.');
    if (this.config.backend === 'supabase') {
      if (!before.mfaAvailable || !this.isCurrentAuthority(this.epoch, before.id, before.sessionId) || this.authenticator.inProgress || this.emailVerification.blocksAuthenticator) throw new AdminRequestError('Complete the current email verification before using the authenticator.');
      const epoch = this.epoch;
      const authority = authorityKey(before);
      return this.authenticator.verify(before, factorId, challengeId, code, () =>
        this.isCurrentAuthority(epoch, before.id, before.sessionId) &&
        this.user !== null &&
        authorityKey(this.user) === authority &&
        !this.authenticator.inProgress &&
        !this.emailVerification.blocksAuthenticator
      );
    }
    const epoch = this.epoch;
    const result = await this.request('auth/mfa/verify', {body: {factor_id: factorId, challenge_id: challengeId, code}, authenticated: true});
    if (result.ok === true && epoch === this.epoch) {
      // Fence work issued under the old cookie. Admit the rotated session only
      // after checking it still belongs to the exact previous account.
      this.invalidateAuthority();
      const current = this.ownsCurrentRevision();
      this.emit('loading', undefined, false);
      if (!current()) throw new AdminRequestError(VERIFY_AUTHENTICATOR_RESULT, {outcomeUnknown: true});
      try {
        if (await this.restoreSession({
          matches: candidate => matchesPredecessorAuthenticator(before, candidate),
          message: VERIFY_AUTHENTICATOR_RESULT,
        })) return;
      } catch {
        // The readback keeps the workspace closed until the session is checked.
      }
    }
    throw new AdminRequestError(VERIFY_AUTHENTICATOR_RESULT, {outcomeUnknown: true});
  };
}
