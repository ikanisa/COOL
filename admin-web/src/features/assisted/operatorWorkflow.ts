import type {AdminRequest, JsonObject} from '../../api/client';
import {clearPending, listPending, readPending, retainPending, sha256Text, type PendingAttempt, type PendingIdentity} from '../core/pendingAttempt';
import {validateGatewayObservation, type AssistedGateway, type AssistedGatewayObservation, type AssistedGatewayPayload} from './assistedGateway';

import {
  ACTIONS, HASH, UUID, checkedClaim, checkedConfirmation, checkedOutcome, checkedRelease, checkedStart,
  invalid, parseClaimedContent, parseOperatorReceipt, result,
  type Action, type AssistedJob, type AssistedObservation, type Claim, type Confirmation, type Content,
} from './assistedContracts';

const FAMILY = 'notification-operator', PERMISSION = 'assisted_sms.manage';
const running = new Set<string>();
export interface AssistedNativePayload {attemptId: string; destinationE164: string; messageBody: string}
/** An injected native adapter must take at most once immediately before dispatch and must never retry. */
export interface AssistedSmsSender {sendOnce: (takeForImmediateDispatch: () => AssistedNativePayload | null) => Promise<{observation: AssistedObservation; evidenceReferenceSha256: string} | null>}
export interface OperatorContext {
  allowWrites: boolean; epoch: number; identity: PendingIdentity & {principalId: string}; request: AdminRequest;
  verifyFresh: () => Promise<boolean>; isCurrent: () => boolean; sender?: AssistedSmsSender; storage?: Storage;
  /** Gateway operations remain off until the email-proof backend is qualified. */
  allowGateway?: boolean; isGatewayEnabled?: () => boolean; gatewayVerificationMode?: 'email' | 'authenticator'; gateway?: AssistedGateway;
}
export interface OperatorView {jobId: string | null; expiresAt: string | null; destination: string | null; destinationHash: string | null; destinationRevision: number | null; message: string | null; bodyHash: string | null; confirmed: boolean; attemptId: string | null; observation: AssistedObservation | null; evidenceReferenceSha256: string | null}
export interface OperatorLookup {observed: boolean; action: Action; resourceId: string; attemptId: string | null; observation: AssistedObservation | null; evidenceReferenceSha256: string | null}
export interface OperatorManualLookup {requestId: string; observed: boolean; action: Action | 'enqueue' | null; resourceId: string | null; attemptId: string | null; observation: AssistedObservation | null; evidenceReferenceSha256: string | null}
export class OperatorOutcomeUnknown extends Error {constructor(readonly checkpoint: PendingAttempt) {super('The result is unknown. Check the original operation before continuing.');}}

function freshId(): string {if (typeof globalThis.crypto?.randomUUID !== 'function') throw new Error('A secure request reference is unavailable.'); return globalThis.crypto.randomUUID();}

export function parseOperatorPending(saved: PendingAttempt): PendingAttempt {
  const intent = saved.intent;
  if (saved.family !== FAMILY || saved.permission !== PERMISSION || !UUID.test(saved.request_key) || Object.keys(intent).sort().join(',') !== 'action,resource_id' || !ACTIONS.includes(intent.action as Action) || typeof intent.resource_id !== 'string' || !UUID.test(intent.resource_id) || saved.resource_id !== intent.resource_id) throw new Error('The original assisted SMS reference could not be verified.');
  return saved;
}

/** Metadata-only guarded adapter for the existing per-tab recovery store. */
class CurrentStorage implements Storage {
  constructor(private readonly base: Storage, private readonly current: () => boolean) {}
  private guard() {if (!this.current()) throw new Error('The original session changed.');}
  get length() {return 0;} clear(): void {throw new Error('Unsupported recovery operation.');} key(): string | null {return null;}
  getItem(key: string): string | null {this.guard(); return this.base.getItem(key);}
  setItem(key: string, value: string): void {this.guard(); this.base.setItem(key, value);}
  removeItem(key: string): void {this.guard(); this.base.removeItem(key);}
}

/** A task instance never reconstructs claims, content, confirmations or send permits. */
export class AssistedOperator {
  private generation = 0;
  private disposed = false;
  private claimValue: Claim | null = null;
  private expectedPaymentId: string | null = null;
  private contentValue: Content | null = null;
  private confirmation: Confirmation | null = null;
  private attemptId: string | null = null;
  private observation: AssistedObservation | null = null;
  private evidence: string | null = null;
  private permit: {active: boolean; payload: AssistedNativePayload | null} | null = null;
  private gatewayPermit: {active: boolean; payload: AssistedGatewayPayload | null} | null = null;
  private readonly attemptedConfirmations = new Set<string>();
  private workerId: string | null = null;
  constructor(private readonly context: OperatorContext) {}

  private current(generation: number): boolean {return !this.disposed && generation === this.generation && this.context.isCurrent();}
  private authority(generation: number, mutate = false) {
    const actor = this.context.identity;
    if (!this.current(generation) || (mutate && !this.context.allowWrites) || !actor.permissions.includes('assisted_sms.read') || !actor.permissions.includes(PERMISSION) || !UUID.test(actor.id) || !UUID.test(actor.sessionId) || !UUID.test(actor.principalId) || !Number.isFinite(Date.parse(actor.expiresAt)) || Date.parse(actor.expiresAt) <= Date.now()) throw new Error('Reopen assisted SMS with your current verified sign-in.');
  }
  private storage(generation: number): Storage {return new CurrentStorage(this.context.storage ?? sessionStorage, () => this.current(generation));}
  private async run<T>(mutate: boolean, work: (generation: number) => Promise<T>): Promise<T> {
    const generation = this.generation; this.authority(generation, mutate);
    const actor = this.context.identity, lock = JSON.stringify([actor.id, actor.sessionId]);
    if (running.has(lock)) throw new Error('Wait for the current assisted SMS request.');
    running.add(lock);
    try {
      if (!(await this.context.verifyFresh())) throw new Error('Verify your current sign-in before continuing.');
      this.authority(generation, mutate); return await work(generation);
    } finally {running.delete(lock);}
  }
  private live(value: string) {if (Date.parse(value) <= Date.now()) throw new Error('This claim or confirmation expired. Refresh the queue.');}
  private clearSensitive() {this.claimValue = null; this.expectedPaymentId = null; this.contentValue = null; this.confirmation = null; if (this.permit) {this.permit.active = false; this.permit.payload = null;} this.permit = null; if(this.gatewayPermit){this.gatewayPermit.active=false;this.gatewayPermit.payload=null;}this.gatewayPermit=null;}
  invalidate() {this.generation++; this.clearSensitive(); this.attemptId = null; this.observation = null; this.evidence = null;}
  dispose() {this.invalidate(); this.disposed = true;}
  view(): OperatorView {return {jobId: this.claimValue?.jobId ?? null, expiresAt: this.confirmation?.expires ?? this.claimValue?.expires ?? null, destination: this.contentValue?.destination ?? null, destinationHash: this.contentValue?.destinationHash ?? null, destinationRevision: this.contentValue?.destinationRevision ?? null, message: this.contentValue?.message ?? null, bodyHash: this.contentValue?.bodyHash ?? null, confirmed: this.confirmation !== null, attemptId: this.attemptId, observation: this.observation, evidenceReferenceSha256: this.evidence};}
  private async request(generation: number, body: JsonObject): Promise<JsonObject> {
    this.authority(generation); const response = await this.context.request('notification-operator', {authenticated: true, method: 'POST', body}); this.authority(generation); return result(response);
  }
  private async pending(generation: number): Promise<PendingAttempt[]> {
    const values = (await listPending(this.context.identity, FAMILY, PERMISSION, this.storage(generation))).map(parseOperatorPending); this.authority(generation); return values;
  }
  private async exact(generation: number, saved: PendingAttempt): Promise<PendingAttempt> {
    const found = await readPending(this.context.identity, FAMILY, saved.resource_id, this.storage(generation)); this.authority(generation);
    if (!found || found.request_key !== saved.request_key || JSON.stringify(found.intent) !== JSON.stringify(saved.intent)) throw new Error('The original operation reference could not be verified.');
    return parseOperatorPending(found);
  }
  private async mutate<T>(generation: number, action: Action, resourceId: string, body: JsonObject, parse: (value: JsonObject) => Promise<T> | T, beforeDispatch?: () => void): Promise<T> {
    this.authority(generation, true);
    if ((await this.pending(generation)).length) throw new Error('Check the original assisted SMS operation before making another change.');
    const requestId = freshId(), saved = await retainPending(this.context.identity, FAMILY, resourceId, requestId, PERMISSION, {action, resource_id: resourceId}, this.storage(generation));
    this.authority(generation, true);
    try {
      beforeDispatch?.();
      const value = await this.request(generation, {action, ...body, request_id: requestId});
      this.authority(generation, true);
      const parsed = await parse(value); this.authority(generation, true);
      await this.exact(generation, saved);
      await clearPending(this.context.identity, FAMILY, resourceId, requestId, this.storage(generation));
      this.authority(generation, true);
      return parsed;
    } catch {this.clearSensitive(); throw new OperatorOutcomeUnknown(saved);}
  }

  listOriginals(): Promise<PendingAttempt[]> {return this.run(false, (generation) => this.pending(generation));}
  private async resolveOriginal(generation: number, requestId: string) {
    const response = await this.request(generation, {action: 'get_operation', request_id: requestId});
    return parseOperatorReceipt(response, requestId, this.context.identity.sessionId);
  }
  private async resolveRetained(generation: number, saved: PendingAttempt): Promise<OperatorLookup> {
    const pending = await this.exact(generation, parseOperatorPending(saved)), action = pending.intent.action as Action, resourceId = pending.resource_id;
    const details = await this.resolveOriginal(generation, pending.request_key.toLowerCase());
    if (!details) return {observed: false, action, resourceId, attemptId: null, observation: null, evidenceReferenceSha256: null};
    if (details.action !== action || details.resourceId !== resourceId.toLowerCase()) return invalid();
    await this.exact(generation, pending);
    await clearPending(this.context.identity, FAMILY, resourceId, pending.request_key, this.storage(generation)); this.authority(generation);
    if (details.action === 'record_send_start' && details.attemptId) {this.attemptId = details.attemptId; this.observation = null; this.evidence = null;}
    return {observed: true, ...details, action};
  }
  checkOriginal(saved: PendingAttempt): Promise<OperatorLookup> {return this.run(false, (generation) => this.resolveRetained(generation, saved));}
  lookupOriginal(requestId: string): Promise<OperatorManualLookup> {
    return this.run(false, async (generation) => {
      if (!UUID.test(requestId.trim())) throw new Error('Enter a valid original operation UUID.');
      const id = requestId.trim().toLowerCase(), saved = (await this.pending(generation)).find((item) => item.request_key.toLowerCase() === id);
      if (saved) return {requestId: id, ...await this.resolveRetained(generation, saved)};
      const details = await this.resolveOriginal(generation, id);
      if (details?.action === 'record_send_start' && details.attemptId) {this.attemptId = details.attemptId; this.observation = null; this.evidence = null;}
      return {requestId: id, observed: details !== null, action: details?.action ?? null, resourceId: details?.resourceId ?? null, attemptId: details?.attemptId ?? null, observation: details?.observation ?? null, evidenceReferenceSha256: details?.evidenceReferenceSha256 ?? null};
    });
  }

  claim(job: AssistedJob): Promise<void> {
    return this.run(true, async (generation) => {
      if (!UUID.test(job.id) || !UUID.test(job.payment_id) || !['queued', 'claimed'].includes(job.state) || !Number.isSafeInteger(job.fence) || job.fence < 0 || job.fence > 999_999_997) throw new Error('Refresh the selected SMS job.');
      const workerId = this.workerId ?? `collect-admin-${freshId()}`; this.workerId = workerId;
      const claim = await this.mutate(generation, 'claim', job.id, {job_id: job.id, worker_id: workerId, expected_fence: job.fence}, (value) => {
        const item = checkedClaim(value, true);
        if (item.jobId !== job.id.toLowerCase() || item.workerId !== workerId || item.fence !== job.fence + 1 || item.publicSessionId !== this.context.identity.sessionId.toLowerCase()) return invalid();
        this.live(item.expires); return item;
      });
      this.authority(generation, true); this.clearSensitive(); this.claimValue = claim; this.expectedPaymentId = job.payment_id.toLowerCase(); this.attemptId = null;
    });
  }
  loadContent(): Promise<void> {
    return this.run(false, async (generation) => {
      const claim = this.claimValue; if (!claim || (await this.pending(generation)).length) throw new Error('Refresh the current claim first.'); this.live(claim.expires);
      this.contentValue = null; this.confirmation = null;
      const content = parseClaimedContent(await this.request(generation, {
        action: 'get_claimed', job_id: claim.jobId, claim_token: claim.claimToken, fence_version: claim.fence,
      }));
      const {message, destination} = content;
      if (content.jobId !== claim.jobId || content.paymentId !== this.expectedPaymentId || content.claimToken !== claim.claimToken || content.fence !== claim.fence || content.expires !== claim.expires || await sha256Text(message) !== content.bodyHash || await sha256Text(destination) !== content.destinationHash) return invalid();
      this.authority(generation); this.live(content.expires); this.contentValue = content; this.confirmation = null;
    });
  }
  confirm(userConfirmation: boolean): Promise<void> {
    return this.run(true, async (generation) => {
      const claim = this.claimValue, content = this.contentValue;
      if (!userConfirmation || !claim || !content || this.confirmation) throw new Error('Confirm the exact current recipient and message.');
      this.live(claim.expires); const confirmationId = freshId();
      const confirmation = await this.mutate(generation, 'confirm', claim.jobId, {job_id: claim.jobId, claim_token: claim.claimToken, fence_version: claim.fence, confirmation_id: confirmationId, body_sha256: content.bodyHash, destination_sha256: content.destinationHash, destination_revision: content.destinationRevision, user_confirmation: true}, (value) => {
        const item = checkedConfirmation(value, true);
        if (item.jobId !== claim.jobId || item.confirmationId !== confirmationId || item.claimToken !== claim.claimToken || item.fence !== claim.fence || item.bodyHash !== content.bodyHash || item.destinationHash !== content.destinationHash || item.destinationRevision !== content.destinationRevision || item.originatingSessionId !== claim.originatingSessionId || item.publicSessionId !== claim.publicSessionId || Date.parse(item.expires) > Date.parse(claim.expires)) return invalid();
        this.live(item.expires); return item;
      });
      this.authority(generation, true); this.confirmation = confirmation;
    });
  }
  release(): Promise<void> {
    return this.run(true, async (generation) => {
      const claim = this.claimValue; if (!claim) throw new Error('Refresh the current claim first.'); this.live(claim.expires);
      await this.mutate(generation, 'release_claim', claim.jobId, {job_id: claim.jobId, claim_token: claim.claimToken, fence_version: claim.fence}, (value) => {const item = checkedRelease(value); if (item.jobId !== claim.jobId || item.fence !== claim.fence + 1) return invalid();});
      this.authority(generation, true); this.clearSensitive();
    });
  }
  startAndSend(): Promise<{permitIssued: boolean; sentToAdapter: boolean; adapterResultUnknown: boolean}> {
    return this.run(true, async (generation) => {
      const confirmation = this.confirmation, content = this.contentValue, sender = this.context.sender;
      if (!confirmation || !content || !sender) throw new Error('An approved native sender and exact-content confirmation are required.');
      this.live(confirmation.expires);
      if (this.attemptedConfirmations.has(confirmation.confirmationId)) throw new Error('Check the original send-start operation.');
      const start = await this.mutate(generation, 'record_send_start', confirmation.jobId, {job_id: confirmation.jobId, claim_token: confirmation.claimToken, fence_version: confirmation.fence, confirmation_id: confirmation.confirmationId}, (value) => {
        const item = checkedStart(value);
        if (item.jobId !== confirmation.jobId || item.confirmationId !== confirmation.confirmationId || item.claimToken !== confirmation.claimToken || item.fence !== confirmation.fence || item.originatingSessionId !== confirmation.originatingSessionId || item.publicSessionId !== confirmation.publicSessionId) return invalid();
        return item;
      }, () => this.attemptedConfirmations.add(confirmation.confirmationId));
      // A native sender never receives a server gateway grant.
      start.dispatchToken = null;
      this.authority(generation, true); this.attemptId = start.attemptId; this.observation = null; this.evidence = null;
      if (!start.maySend) {this.clearSensitive(); return {permitIssued: false, sentToAdapter: false, adapterResultUnknown: false};}
      if (Date.parse(confirmation.expires) <= Date.now()) {this.clearSensitive(); throw new Error('The start was recorded, but the confirmation expired before handoff. Review the recorded attempt.');}
      const permit = {active: true, payload: {attemptId: start.attemptId, destinationE164: content.destination, messageBody: content.message} as AssistedNativePayload | null}; this.permit = permit;
      let taken = false, handed = false, adapterResultUnknown = false;
      const take = (): AssistedNativePayload | null => {
        if (taken) return null; taken = true;
        const payload = permit.payload; permit.payload = null;
        const usable = permit.active && this.current(generation) && this.context.allowWrites && Date.parse(confirmation.expires) > Date.now();
        permit.active = false; handed = usable && payload !== null; return handed ? payload : null;
      };
      this.claimValue = null; this.expectedPaymentId = null; this.contentValue = null; this.confirmation = null;
      try {
        const observed = await sender.sendOnce(take);
        if (this.current(generation) && handed && observed && ['observed_sent', 'failed_no_send', 'uncertain'].includes(observed.observation) && HASH.test(observed.evidenceReferenceSha256)) {this.observation = observed.observation; this.evidence = observed.evidenceReferenceSha256;}
      } catch {adapterResultUnknown = true;}
      finally {permit.active = false; permit.payload = null; if (this.permit === permit) this.permit = null;}
      return {permitIssued: true, sentToAdapter: handed, adapterResultUnknown};
    });
  }
  private qualifiedGateway(generation:number):AssistedGateway {
    this.authority(generation,true);const gateway=this.context.gateway;
    if(this.context.allowGateway!==true||this.context.isGatewayEnabled&&!this.context.isGatewayEnabled()||this.context.gatewayVerificationMode!=='email'||!gateway||!gateway.matches(this.context.identity))
      throw new Error('The qualified email-verified gateway is unavailable.');
    return gateway;
  }
  /** The first start response is the only possible source of a gateway token. */
  startAndDispatchGateway():Promise<{permitIssued:boolean;tokenIssued:boolean;handedToGateway:boolean;gatewayResultUnknown:boolean;observation:AssistedGatewayObservation|null}>{
    return this.run(true,async generation=>{
      const gateway=this.qualifiedGateway(generation),confirmation=this.confirmation,content=this.contentValue;
      if(!confirmation||!content)throw new Error('Confirm the exact current recipient and message.');
      this.live(confirmation.expires);if(this.attemptedConfirmations.has(confirmation.confirmationId))throw new Error('Check the original send-start operation.');
      const start=await this.mutate(generation,'record_send_start',confirmation.jobId,{job_id:confirmation.jobId,claim_token:confirmation.claimToken,fence_version:confirmation.fence,confirmation_id:confirmation.confirmationId},value=>{
        const item=checkedStart(value);
        if(item.jobId!==confirmation.jobId||item.confirmationId!==confirmation.confirmationId||item.claimToken!==confirmation.claimToken||item.fence!==confirmation.fence||item.originatingSessionId!==confirmation.originatingSessionId||item.publicSessionId!==confirmation.publicSessionId)return invalid();
        return item;
      },()=>{this.qualifiedGateway(generation);this.attemptedConfirmations.add(confirmation.confirmationId);});
      this.authority(generation,true);this.attemptId=start.attemptId;this.observation=null;this.evidence=null;
      try{this.qualifiedGateway(generation);}catch{const issued=start.dispatchToken!==null;start.dispatchToken=null;this.clearSensitive();return {permitIssued:start.maySend,tokenIssued:issued,handedToGateway:false,gatewayResultUnknown:false,observation:null};}
      if(!start.maySend){this.clearSensitive();return {permitIssued:false,tokenIssued:false,handedToGateway:false,gatewayResultUnknown:false,observation:null};}
      if(!start.dispatchToken){this.clearSensitive();return {permitIssued:true,tokenIssued:false,handedToGateway:false,gatewayResultUnknown:false,observation:null};}
      if(Date.parse(confirmation.expires)<=Date.now()){start.dispatchToken=null;this.clearSensitive();throw new Error('The start was recorded, but confirmation expired before handoff. Review the original attempt.');}
      const permit={active:true,payload:{attemptId:start.attemptId,dispatchToken:start.dispatchToken} as AssistedGatewayPayload|null};this.gatewayPermit=permit;start.dispatchToken=null;
      let taken=false,handed=false,gatewayResultUnknown=false,observation:AssistedGatewayObservation|null=null;
      const take=():AssistedGatewayPayload|null=>{
        if(taken)return null;taken=true;const payload=permit.payload;permit.payload=null;
        const usable=permit.active&&this.current(generation)&&this.context.allowWrites&&this.context.allowGateway===true&&(!this.context.isGatewayEnabled||this.context.isGatewayEnabled())&&Date.parse(confirmation.expires)>Date.now();
        permit.active=false;handed=usable&&payload!==null;return handed?payload:null;
      };
      this.claimValue=null;this.expectedPaymentId=null;this.contentValue=null;this.confirmation=null;
      try{
        const result=await gateway.sendOnce(take);
        if(this.current(generation)&&handed){this.qualifiedGateway(generation);observation=validateGatewayObservation(result,start.attemptId);this.observation=observation.observation;this.evidence=observation.observation?observation.evidenceReferenceSha256:null;}
      }catch{gatewayResultUnknown=handed;}
      finally{permit.active=false;permit.payload=null;if(this.gatewayPermit===permit)this.gatewayPermit=null;}
      return {permitIssued:true,tokenIssued:true,handedToGateway:handed,gatewayResultUnknown,observation};
    });
  }
  /** Server inspection may update gateway state; it never authorizes a resend. */
  inspectGateway():Promise<AssistedGatewayObservation>{
    return this.run(true,async generation=>{
      const gateway=this.qualifiedGateway(generation),attempt=this.attemptId;
      if(!attempt||(await this.pending(generation)).length)throw new Error('Select the original attempt and check unresolved operations first.');
      this.qualifiedGateway(generation);const result=validateGatewayObservation(await gateway.inspect(attempt),attempt);this.qualifiedGateway(generation);
      this.observation=result.observation;this.evidence=result.observation?result.evidenceReferenceSha256:null;return result;
    });
  }
  selectAttempt(job: AssistedJob): void {
    this.authority(this.generation);
    if (!job.attempt_id || !UUID.test(job.attempt_id) || !['send_started', 'uncertain'].includes(job.state)) throw new Error('Refresh the selected SMS attempt.');
    this.attemptId = job.attempt_id.toLowerCase(); this.observation = null; this.evidence = null;
  }
  recordOutcome(observation: AssistedObservation, evidenceReferenceSha256: string, confirmed: boolean): Promise<void> {
    return this.run(true, async (generation) => {
      const attempt = this.attemptId;
      if (!confirmed || !attempt || !['observed_sent', 'failed_no_send', 'uncertain'].includes(observation) || !HASH.test(evidenceReferenceSha256)) throw new Error('Confirm the observation and its 64-character evidence reference.');
      await this.mutate(generation, 'record_outcome', attempt, {attempt_id: attempt, observation, evidence_reference_sha256: evidenceReferenceSha256}, (value) => {const item = checkedOutcome(value); if (item.attemptId !== attempt || item.observation !== observation || item.evidence !== evidenceReferenceSha256) return invalid();});
      this.authority(generation, true); this.attemptId = null; this.observation = null; this.evidence = null;
    });
  }
}
