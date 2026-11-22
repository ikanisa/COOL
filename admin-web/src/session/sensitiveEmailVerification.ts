import {AdminRequestError, type AdminBackend, type AdminRequest} from '../api/client';
import {OTP} from './sessionPolicy';
import {parseEmailProof, parseSensitiveOtpReceipt, type AdminUser, type OtpReceipt} from './sessionResponses';

export type SensitiveEmailRecovery =
  | {kind: 'request'; retryAt: number; checked: boolean}
  | {kind: 'verify'; retryAt: null; checked: false};

interface VerificationPort {
  current(): {actor: AdminUser | null; epoch: number; authenticated: boolean};
  backend(): AdminBackend;
  authorityKey(actor: AdminUser): string;
  request: AdminRequest;
  updateProof(proof: string | null): void;
  isCurrentAuthority(epoch: number, actorId: string, sessionId: string): boolean;
}

interface EmailChallenge {
  receipt: OtpReceipt;
  key: string;
  epoch: number;
  attempt: number;
  expires: number;
}

const VERIFICATION_WINDOW_MS = 300_000;

export class SensitiveEmailVerification {
  private challenge: EmailChallenge | null = null;
  private attempt = 0;
  private pendingRecovery: SensitiveEmailRecovery | null = null;
  private requestDeadline = 0;
  private operation: 'request' | 'verify' | 'check' | null = null;
  private proofBaseline: number | null = null;

  constructor(private readonly port: VerificationPort) {}

  private isCurrent(attempt: number, epoch: number, key: string): boolean {
    const current = this.port.current();
    return attempt === this.attempt && epoch === current.epoch &&
      current.actor !== null && this.port.authorityKey(current.actor) === key;
  }

  private retainUnconfirmed(kind: SensitiveEmailRecovery['kind']) {
    this.pendingRecovery = kind === 'request'
      ? {kind, retryAt: this.requestDeadline, checked: false}
      : {kind, retryAt: null, checked: false};
  }

  private finish(attempt: number) {
    if (attempt === this.attempt) this.operation = null;
  }

  get blocksAuthenticator(): boolean {
    return this.operation !== null || this.pendingRecovery !== null;
  }

  sessionProof(proof: string | null): string | null {
    // A background session read cannot complete an in-flight email check.
    if (this.operation === 'verify') return null;
    if (this.pendingRecovery && this.proofBaseline !== null && proof !== null && Date.parse(proof) <= this.proofBaseline) return null;
    return proof;
  }

  reset() {
    this.attempt++;
    this.challenge = null;
    this.pendingRecovery = null;
    this.requestDeadline = 0;
    this.operation = null;
    this.proofBaseline = null;
  }

  readonly requestCode = async (): Promise<OtpReceipt> => {
    const {actor, epoch, authenticated} = this.port.current();
    if (this.port.backend() !== 'supabase' || !actor || !authenticated) throw new Error('Email verification is unavailable.');
    if (this.blocksAuthenticator) throw new Error('Check the current verification before requesting another code.');
    const key = this.port.authorityKey(actor);
    const attempt = ++this.attempt;
    this.operation = 'request';
    this.requestDeadline = Date.now() + VERIFICATION_WINDOW_MS;
    try {
      const body = await this.port.request('auth/email/request', {body: {}, authenticated: true, expectedStatus: 202});
      const receipt = parseSensitiveOtpReceipt(body);
      if (!this.isCurrent(attempt, epoch, key)) throw new AdminRequestError('Your sign-in changed. Try again.');
      this.challenge = {receipt, key, epoch, attempt, expires: Date.now() + receipt.expiresInSeconds * 1000};
      return receipt;
    } catch (failure) {
      if (attempt === this.attempt && epoch === this.port.current().epoch && failure instanceof AdminRequestError && failure.outcomeUnknown) {
        this.retainUnconfirmed('request');
      }
      throw failure;
    } finally {
      this.finish(attempt);
    }
  };

  readonly verifyCode = async (challengeId: string, code: string) => {
    const {actor, epoch} = this.port.current();
    const pending = this.challenge;
    if (!actor || !pending || this.blocksAuthenticator || pending.attempt !== this.attempt ||
        pending.epoch !== epoch || pending.key !== this.port.authorityKey(actor) ||
        pending.receipt.challengeId !== challengeId || pending.expires <= Date.now() || !OTP.test(code.trim())) {
      throw new Error('Use the current six-digit email code.');
    }
    this.operation = 'verify';
    this.proofBaseline = actor.emailVerifiedAt ? Date.parse(actor.emailVerifiedAt) : null;
    this.port.updateProof(null);
    try {
      const body = await this.port.request('auth/email/verify', {body: {challenge_id: challengeId, code: code.trim()}, authenticated: true, expectedStatus: 200});
      let proof: string | null;
      try {proof = parseEmailProof(body, actor, Date.now());}
      catch {throw new AdminRequestError('Email verification could not be confirmed. Check verification.', {outcomeUnknown: true});}
      if (!proof || (this.proofBaseline !== null && Date.parse(proof) <= this.proofBaseline) || Date.now() - Date.parse(proof) > VERIFICATION_WINDOW_MS) {
        throw new AdminRequestError('Email verification could not be confirmed. Check verification.', {outcomeUnknown: true});
      }
      if (!this.isCurrent(pending.attempt, pending.epoch, pending.key)) {
        throw new AdminRequestError('Your sign-in changed. Try again.', {outcomeUnknown: true});
      }
      this.challenge = null;
      this.pendingRecovery = null;
      this.proofBaseline = null;
      this.port.updateProof(proof);
    } catch (failure) {
      if (pending.attempt === this.attempt && pending.epoch === this.port.current().epoch) {
        if (failure instanceof AdminRequestError && failure.outcomeUnknown) this.retainUnconfirmed('verify');
        else this.proofBaseline = null;
      }
      throw failure;
    } finally {
      this.finish(pending.attempt);
    }
  };

  readonly recheck = async (): Promise<boolean> => {
    const {actor, epoch} = this.port.current();
    if (!actor || this.port.backend() !== 'supabase' || this.operation) throw new Error('Verification is unavailable.');
    const key = this.port.authorityKey(actor);
    const attempt = this.attempt;
    this.operation = 'check';
    try {
      const body = await this.port.request('auth/email-verification', {authenticated: true, expectedStatus: 200});
      const proof = parseEmailProof(body, actor, Date.now());
      if (!this.isCurrent(attempt, epoch, key)) throw new Error('Your sign-in changed.');
      const admitted = this.sessionProof(proof);
      this.port.updateProof(admitted);
      if (admitted && Date.now() - Date.parse(admitted) <= VERIFICATION_WINDOW_MS) {
        this.pendingRecovery = null;
        this.proofBaseline = null;
        this.challenge = null;
        return this.port.isCurrentAuthority(epoch, actor.id, actor.sessionId);
      }
      if (this.pendingRecovery?.kind === 'request') this.pendingRecovery = {...this.pendingRecovery, checked: true};
      return false;
    } catch (failure) {
      if (this.isCurrent(attempt, epoch, key)) this.port.updateProof(null);
      throw failure;
    } finally {
      this.finish(attempt);
    }
  };

  readonly recovery = (): SensitiveEmailRecovery | null => this.pendingRecovery ? {...this.pendingRecovery} : null;

  readonly releaseExpiredRequest = () => {
    const pending = this.pendingRecovery;
    if (this.operation || pending?.kind !== 'request' || !pending.checked || Date.now() < pending.retryAt) {
      throw new Error('Check verification and wait before requesting a new code.');
    }
    this.pendingRecovery = null;
    this.requestDeadline = 0;
    this.challenge = null;
  };

  readonly cancel = () => {
    if (this.operation === 'request' || this.operation === 'verify') this.retainUnconfirmed(this.operation);
    this.attempt++;
    this.challenge = null;
    this.operation = null;
  };
}
