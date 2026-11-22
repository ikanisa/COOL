import {AdminRequestError, type AdminApiClient, type AdminClientConfig, type JsonObject} from '../api/client';
import {googleAvailable, googleAuthorizationUrl, googleChallenge, openGooglePopup, randomUrlValue, type GooglePopup} from './google';
import {normalizeAdminEmail} from './adminEmail';
import {authorityKey} from './sessionAuthority';
import {OTP} from './sessionPolicy';
import type {SessionReadback} from './sessionReadback';
import {parseAdminUser, parseSignInOtpReceipt, type AdminUser, type OtpReceipt} from './sessionResponses';

// The Google exchange predates policy/owner negotiation: auth/session is the
// authoritative source for these fields, which can be omitted by the exchange.
function loginIdentityKey(user: AdminUser): string {return authorityKey({...user, mfaAvailable: false, mfaRequired: false, ownerIdentity: null});}

interface SignInSession {
  config: () => AdminClientConfig;
  request: AdminApiClient['request'];
  epoch: () => number;
  clear: () => void;
  fenceLogout: () => boolean;
  fenceVerification: () => boolean;
  restore: (readback: SessionReadback) => Promise<boolean>;
}

export class AdminSignIn {
  private otp: {email: string; receipt: OtpReceipt; epoch: number} | null = null;
  private googleAttempt = 0;
  private googlePopup: GooglePopup | null = null;

  constructor(private readonly session: SignInSession) {}

  clearOtp() {
    this.otp = null;
  }

  private requireAvailable(action: 'signing in again' | 'continuing') {
    if (this.session.fenceLogout()) {
      throw new AdminRequestError('Complete sign-out before ' + action + '.', {outcomeUnknown: true});
    }
    if (this.session.fenceVerification()) {
      throw new AdminRequestError('Complete the pending session verification before ' + action + '.', {outcomeUnknown: true});
    }
  }

  private async confirmSignIn(readback: SessionReadback): Promise<void> {
    if (!(await this.session.restore(readback))) {
      throw new AdminRequestError(readback.message, {outcomeUnknown: true});
    }
  }

  get googleSignInAvailable(): boolean {
    return typeof window !== 'undefined' && googleAvailable(this.session.config().backend, this.session.config().googleEnabled, this.session.config().supabaseProjectOrigin, window.location.origin);
  }

  readonly cancelGoogleSignIn = () => {
    this.googleAttempt++; this.googlePopup?.cancel(); this.googlePopup = null;
  };

  readonly signInWithGoogle = async () => {
    if (!this.googleSignInAvailable || this.session.fenceLogout() || this.session.fenceVerification()) throw new AdminRequestError('Google sign-in is unavailable.');
    this.session.clear();
    const epoch = this.session.epoch(), attempt = ++this.googleAttempt;
    const verifier = randomUrlValue(), state = randomUrlValue(), origin = window.location.origin;
    const popup = openGooglePopup(state, origin); this.googlePopup = popup;
    const current = () => epoch === this.session.epoch() && attempt === this.googleAttempt;
    try {
      const reply = await popup.authorize(async () => {
        const challenge = await googleChallenge(verifier);
        if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.');
        const body = await this.session.request('auth/google/start', {body: {code_challenge: challenge, client_state: state, return_origin: origin}, authenticated: false}, {isCurrent: current});
        if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.');
        return googleAuthorizationUrl(body.authorization_url, origin, this.session.config().supabaseProjectOrigin);
      });
      if (!current() || reply.state !== state) throw new AdminRequestError('Google sign-in could not be verified.');
      if (reply.error) throw new AdminRequestError(reply.error === 'google_sign_in_unconfirmed' ? 'Google sign-in could not be confirmed. Check your session before trying again.' : 'Google sign-in could not finish.', {outcomeUnknown: reply.error === 'google_sign_in_unconfirmed'});
      if (!reply.code || !/^[A-Za-z0-9_-]{43}$/.test(reply.code)) throw new AdminRequestError('Google sign-in could not be verified.');
      const response = await this.session.request('auth/google/exchange', {body: {code: reply.code, code_verifier: verifier, client_state: state}, authenticated: false}, {isCurrent: current});
      if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.', {outcomeUnknown: true});
      let expected: AdminUser;
      try {expected = parseAdminUser(response);} catch {throw new AdminRequestError('Google sign-in could not be confirmed. Check your session before trying again.', {outcomeUnknown: true});}
      await this.confirmSignIn({
        isCurrent: current,
        matches: (user) => loginIdentityKey(user) === loginIdentityKey(expected),
        message: 'Google sign-in could not be confirmed.',
      });
    } finally {if (this.googlePopup === popup) this.googlePopup = null;}
  };

  readonly signIn = async (email: string, password: string) => {
    this.requireAvailable('signing in again');
    const normalized = normalizeAdminEmail(email);
    if (!password || password.length > 512) throw new Error('Check the password.');
    this.session.clear();
    const epoch = this.session.epoch();
    const body = await this.session.request('auth/login', {body: {email: normalized, password}, authenticated: false});
    let expected: AdminUser;
    try {expected = parseAdminUser(body);} catch {throw new AdminRequestError('Sign-in could not be confirmed. Check your session before trying again.', {outcomeUnknown: true});}
    if (expected.email.toLowerCase() !== normalized) throw new AdminRequestError('Sign-in could not be confirmed.', {outcomeUnknown: true});
    await this.confirmSignIn({
      isCurrent: () => epoch === this.session.epoch(),
      matches: (user) => user.id === expected.id && user.sessionId === expected.sessionId,
      message: 'Sign-in could not be confirmed.',
    });
  };

  readonly requestEmailOtp = async (email: string): Promise<OtpReceipt> => {
    this.requireAvailable('signing in again');
    const normalized = normalizeAdminEmail(email);
    this.session.clear(); const epoch = this.session.epoch();
    let body: JsonObject, deliveryUnknown = false;
    try {body = await this.session.request('auth/otp', {body: {email: normalized}, authenticated: false});}
    catch (failure) {
      if (!(failure instanceof AdminRequestError) || failure.code !== 'email_delivery_unknown' || !failure.otpReceiptBody) throw failure;
      body = failure.otpReceiptBody; deliveryUnknown = true;
    }
    if (this.session.epoch() !== epoch) throw new AdminRequestError('Your sign-in changed. Try again.');
    const parsed = parseSignInOtpReceipt(body);
    const receipt = {...parsed, deliveryUnknown: deliveryUnknown || parsed.deliveryUnknown};
    this.otp = {email: normalized, receipt, epoch};
    return receipt;
  };

  readonly verifyEmailOtp = async (email: string, challengeId: string, code: string) => {
    this.requireAvailable('signing in again');
    const normalized = normalizeAdminEmail(email), pending = this.otp;
    if (!pending || pending.email !== normalized || pending.receipt.challengeId !== challengeId || pending.epoch !== this.session.epoch() || !OTP.test(code.trim())) throw new Error('Request a fresh sign-in code.');
    let expected: AdminUser | null = null, response: JsonObject | null = null;
    try {
      response = await this.session.request('auth/verify', {body: {email: normalized, challenge_id: challengeId, code: code.trim()}, authenticated: false});
    } catch (failure) {
      if (!(failure instanceof AdminRequestError && failure.outcomeUnknown)) throw failure;
    }
    const current = () => pending === this.otp && pending.epoch === this.session.epoch();
    if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.', {outcomeUnknown: true});
    if (response) {
      try {expected = parseAdminUser(response);} catch {expected = null;}
      if (expected && expected.email.toLowerCase() !== normalized) {this.session.clear(); throw new AdminRequestError('Sign-in could not be confirmed.', {outcomeUnknown: true});}
    }
    await this.confirmSignIn({
      isCurrent: current,
      matches: (user) => user.email.toLowerCase() === normalized && (!expected || user.id === expected.id && user.sessionId === expected.sessionId),
      message: 'Sign-in could not be confirmed. Check your session before requesting a new code.',
    });
    if (this.otp === pending) this.otp = null;
  };

  readonly requestPasswordReset = async (email: string) => {
    this.requireAvailable('continuing');
    const result = await this.session.request('auth/forgot-password', {body: {email: normalizeAdminEmail(email)}, authenticated: false});
    if (result.ok !== true) throw new AdminRequestError('The request was not confirmed.', {outcomeUnknown: true});
  };
}
