import {createHash, webcrypto} from 'node:crypto';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {PENDING_KEY} from '../../src/features/core/pendingAttempt';
import {AssistedOperator, OperatorOutcomeUnknown, type AssistedSmsSender, type OperatorContext} from '../../src/features/assisted/operatorWorkflow';
import type {AssistedJob} from '../../src/features/assisted/AssistedSmsPage';

const ownerId = 'cdd3c1c0-c124-4c8a-9719-bd2435d198d1', principalId = '53c51330-f311-4519-977b-30f67b47c1f1', sessionId = '0f689afa-5a45-4fb5-a147-9aff36f137dd', jobId = '6ea1b44a-25b7-4f2a-9d20-5829675211bc', paymentId = 'fa1e3f37-1e2b-4e57-9d7d-77f0c13d0d50', claimId = '0d7bfc80-d88c-4b4c-9f7d-9935f6c5aaf1', attemptId = '1cb27c41-c93b-4efe-bd7b-a8a52fd81239';
const marker = {contract_version: 1, scope: 'assisted_sms_internal_record', delivery_confirmed: false, provider_confirmation: false, settlement_status: 'not_asserted'};
const message = 'Synthetic contribution record; provider confirmation not asserted.', destination = '+250788123456';
const hash = (value: string) => createHash('sha256').update(value).digest('hex');
const job: AssistedJob = {id: jobId, payment_id: paymentId, state: 'queued', fence: 0, attempt_id: null, created_at: '2026-10-18T12:34:56.000Z'};
let current = true;

function fixture({loseClaim = false, noPermit = false}: {loseClaim?: boolean; noPermit?: boolean} = {}) {
  const expires = new Date(Date.now() + 120_000).toISOString(), receipts = new Map<string, Record<string, unknown>>();
  const request = vi.fn(async (_path: string, options?: {body?: Record<string, unknown>}) => {
    const body = options?.body ?? {}, action = body.action;
    if (action === 'claim') {
      const receipt = {...marker, job_id: jobId, claim_token: claimId, fence_version: 1, worker_id: body.worker_id, claim_expires_at: expires, originating_session_id: principalId, public_session_id: sessionId};
      receipts.set(String(body.request_id), receipt);
      if (loseClaim) throw new Error('connection lost');
      return {ok: true, result: receipt};
    }
    if (action === 'get_claimed') return {ok: true, result: {...marker, job_id: jobId, claim_token: claimId, fence_version: 1, destination_e164: destination, destination_sha256: hash(destination), destination_revision: 2, message_body: message, body_sha256: hash(message), payment_id: paymentId, template_key: 'collect.recorded_contribution.v1', claim_expires_at: expires}};
    if (action === 'confirm') {
      const receipt = {...marker, job_id: jobId, confirmation_id: body.confirmation_id, claim_token: claimId, fence_version: 1, body_sha256: hash(message), destination_sha256: hash(destination), destination_revision: 2, expires_at: expires, originating_session_id: principalId, public_session_id: sessionId};
      receipts.set(String(body.request_id), receipt); return {ok: true, result: receipt};
    }
    if (action === 'record_send_start') {
      const stored = {...marker, attempt_id: attemptId, job_id: jobId, confirmation_id: body.confirmation_id, claim_token: claimId, fence_version: 1, state: 'send_started', originating_session_id: principalId, public_session_id: sessionId};
      receipts.set(String(body.request_id), stored);
      return {ok: true, result: {...stored, replay: noPermit, may_send: !noPermit, acknowledgement: noPermit ? 'recorded_start_permit_not_reissued' : 'first_committed_response_only'}};
    }
    if (action === 'release_claim') {const receipt = {...marker, job_id: jobId, state: 'queued', fence_version: 2}; receipts.set(String(body.request_id), receipt); return {ok: true, result: receipt};}
    if (action === 'record_outcome') {const receipt = {...marker, attempt_id: attemptId, observation: body.observation, evidence_reference_sha256: body.evidence_reference_sha256, may_send: false}; receipts.set(String(body.request_id), receipt); return {ok: true, result: receipt};}
    if (action === 'get_operation') {const receipt = receipts.get(String(body.request_id)) ?? null; return {ok: true, result: {...marker, request_id: body.request_id, observed: receipt !== null, receipt, may_send: false}};}
    throw new Error('Unexpected request');
  });
  return {request, receipts};
}
function context(request: OperatorContext['request'], allowWrites = true, sender?: AssistedSmsSender): OperatorContext {
  return {allowWrites, epoch: 1, identity: {id: ownerId, sessionId, principalId, email: 'a@example.com', role: 'staff', permissions: ['assisted_sms.read', 'assisted_sms.manage'], expiresAt: new Date(Date.now() + 3_600_000).toISOString()}, request, verifyFresh: vi.fn(async () => true), isCurrent: () => current, sender};
}
beforeEach(() => {vi.stubGlobal('crypto', webcrypto); sessionStorage.clear(); current = true;});
afterEach(() => {sessionStorage.clear(); vi.restoreAllMocks(); vi.unstubAllGlobals();});

describe('assisted SMS original-session operator workflow', () => {
  it('blocks writes without explicit activation and current manage permission', async () => {
    const {request} = fixture(), disabled = new AssistedOperator(context(request, false));
    await expect(disabled.claim(job)).rejects.toThrow();
    const noManage = new AssistedOperator({...context(request), identity: {...context(request).identity, permissions: ['assisted_sms.read']}});
    await expect(noManage.claim(job)).rejects.toThrow();
    expect(request).not.toHaveBeenCalled(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });

  it('requires exact content confirmation and hands a first-start permit to an injected sender only once', async () => {
    const {request} = fixture(), seen: unknown[] = [];
    const sender: AssistedSmsSender = {sendOnce: vi.fn(async (take) => {seen.push(take(), take()); return {observation: 'observed_sent' as const, evidenceReferenceSha256: hash('synthetic evidence')};})};
    const operator = new AssistedOperator(context(request, true, sender));
    await operator.claim(job); await operator.loadContent();
    expect(operator.view()).toMatchObject({jobId, destination, message, confirmed: false});
    await expect(operator.confirm(false)).rejects.toThrow();
    await operator.confirm(true);
    expect(operator.view().confirmed).toBe(true);
    await expect(operator.startAndSend()).resolves.toEqual({permitIssued: true, sentToAdapter: true, adapterResultUnknown: false});
    expect(seen).toEqual([{attemptId, destinationE164: destination, messageBody: message}, null]);
    expect(operator.view()).toMatchObject({jobId: null, destination: null, message: null, attemptId, observation: 'observed_sent'});
    await expect(operator.recordOutcome('observed_sent', hash('synthetic evidence'), false)).rejects.toThrow();
    await operator.recordOutcome('observed_sent', hash('synthetic evidence'), true);
    expect(operator.view().attemptId).toBeNull();
    expect(request.mock.calls.map(([, options]) => options?.body?.action)).toEqual(['claim', 'get_claimed', 'confirm', 'record_send_start', 'record_outcome']);
  });

  it('never starts sending without an injected adapter and can release the claim', async () => {
    const {request} = fixture(), operator = new AssistedOperator(context(request));
    await operator.claim(job); await operator.loadContent(); await operator.confirm(true);
    await expect(operator.startAndSend()).rejects.toThrow(/native sender/i);
    expect(request.mock.calls.some(([, options]) => options?.body?.action === 'record_send_start')).toBe(false);
    await operator.release();
    expect(operator.view()).toMatchObject({jobId: null, destination: null});
    expect(request.mock.calls.some(([, options]) => options?.body?.action === 'release_claim')).toBe(true);
  });

  it('rejects tampered claimed content before any confirmation can be recorded', async () => {
    const base = fixture();
    const request = vi.fn(async (path: string, options?: {body?: Record<string, unknown>}) => {
      const response = await base.request(path, options);
      return options?.body?.action === 'get_claimed' ? {...response, result: {...response.result, message_body: 'Different message'}} : response;
    });
    const operator = new AssistedOperator(context(request));
    await operator.claim(job);
    await expect(operator.loadContent()).rejects.toThrow(/could not be verified/i);
    expect(operator.view()).toMatchObject({destination: null, message: null});
    await expect(operator.confirm(true)).rejects.toThrow();
    expect(base.request.mock.calls.some(([, options]) => options?.body?.action === 'confirm')).toBe(false);
  });

  it('retains metadata only after a lost claim and never adopts recovered claim authority', async () => {
    const {request} = fixture({loseClaim: true}), operator = new AssistedOperator(context(request));
    let failure: OperatorOutcomeUnknown | null = null;
    try {await operator.claim(job);} catch (error) {if (error instanceof OperatorOutcomeUnknown) failure = error; else throw error;}
    expect(failure).not.toBeNull();
    const raw = sessionStorage.getItem(PENDING_KEY)!;
    expect(raw).not.toContain(claimId); expect(raw).not.toContain(destination); expect(raw).not.toContain(message);
    expect(JSON.parse(raw).entries[0].intent).toEqual({action: 'claim', resource_id: jobId});
    await expect(operator.claim(job)).rejects.toThrow(/original/);
    await expect(operator.checkOriginal(failure!.checkpoint)).resolves.toMatchObject({observed: true, action: 'claim', resourceId: jobId});
    expect(operator.view().jobId).toBeNull();
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
    expect(request.mock.calls.filter(([, options]) => options?.body?.action === 'claim')).toHaveLength(1);
  });

  it('looks up each supported stored receipt by UUID without creating or replaying an operation', async () => {
    const {request, receipts} = fixture(), sendOnce = vi.fn(async () => null), operator = new AssistedOperator(context(request, false, {sendOnce}));
    const expires = new Date(Date.now() + 120_000).toISOString(), confirmationId = 'ee972a01-8de9-4527-82d4-032f0f23df54';
    const examples = [
      {action: 'claim', resourceId: jobId, receipt: {...marker, job_id: jobId, claim_token: claimId, fence_version: 1, worker_id: 'collect-admin-worker', claim_expires_at: expires, originating_session_id: principalId, public_session_id: sessionId}},
      {action: 'confirm', resourceId: jobId, receipt: {...marker, job_id: jobId, confirmation_id: confirmationId, claim_token: claimId, fence_version: 1, body_sha256: hash(message), destination_sha256: hash(destination), destination_revision: 2, expires_at: expires, originating_session_id: principalId, public_session_id: sessionId}},
      {action: 'record_send_start', resourceId: jobId, receipt: {...marker, attempt_id: attemptId, job_id: jobId, confirmation_id: confirmationId, claim_token: claimId, fence_version: 1, state: 'send_started', originating_session_id: principalId, public_session_id: sessionId}},
      {action: 'release_claim', resourceId: jobId, receipt: {...marker, job_id: jobId, state: 'queued', fence_version: 2}},
      {action: 'record_outcome', resourceId: attemptId, receipt: {...marker, attempt_id: attemptId, observation: 'uncertain', evidence_reference_sha256: hash('evidence'), may_send: false}},
      {action: 'enqueue', resourceId: jobId, receipt: {...marker, job_id: jobId, payment_id: paymentId, state: 'queued', body_sha256: hash(message)}},
    ];
    for (const example of examples) {
      const id = crypto.randomUUID(); receipts.set(id, example.receipt);
      const found = await operator.lookupOriginal(` ${id.toUpperCase()} `);
      expect(found).toMatchObject({requestId: id, observed: true, action: example.action, resourceId: example.resourceId});
    }
    expect(operator.view()).toMatchObject({jobId: null, destination: null, message: null, confirmed: false, attemptId});
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
    expect(request.mock.calls.map(([, options]) => options?.body?.action)).toEqual(examples.map(() => 'get_operation'));
    expect(sendOnce).not.toHaveBeenCalled();
  });

  it('does not create a pending reference for an unknown UUID and checks a retained match before clearing it', async () => {
    const {request} = fixture({loseClaim: true}), operator = new AssistedOperator(context(request));
    await expect(operator.lookupOriginal(crypto.randomUUID())).resolves.toMatchObject({observed: false, action: null});
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
    let failed: OperatorOutcomeUnknown | null = null;
    try {await operator.claim(job);} catch (error) {if (error instanceof OperatorOutcomeUnknown) failed = error; else throw error;}
    expect(failed).not.toBeNull();
    await expect(operator.lookupOriginal(failed!.checkpoint.request_key)).resolves.toMatchObject({observed: true, action: 'claim', resourceId: jobId});
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
    expect(operator.view().jobId).toBeNull();
    expect(request.mock.calls.filter(([, options]) => options?.body?.action === 'claim')).toHaveLength(1);
  });

  it('requires fresh current authority and rejects invalid UUIDs and forged lookup receipts', async () => {
    const base = fixture(), operator = new AssistedOperator(context(base.request));
    await expect(operator.lookupOriginal('not-a-uuid')).rejects.toThrow(/valid original operation UUID/i);
    expect(base.request).not.toHaveBeenCalled();
    const id = crypto.randomUUID();
    base.receipts.set(id, {...marker, attempt_id: attemptId, job_id: jobId, confirmation_id: crypto.randomUUID(), claim_token: claimId, fence_version: 1, state: 'send_started', originating_session_id: principalId, public_session_id: sessionId, may_send: true});
    await expect(operator.lookupOriginal(id)).rejects.toThrow(/could not be verified/i);
    expect(operator.view()).toMatchObject({attemptId: null, jobId: null});
    const withoutProof = new AssistedOperator({...context(base.request), verifyFresh: async () => false});
    const calls = base.request.mock.calls.length;
    await expect(withoutProof.lookupOriginal(id)).rejects.toThrow(/verify/i);
    expect(base.request).toHaveBeenCalledTimes(calls);
    current = false;
    await expect(operator.lookupOriginal(id)).rejects.toThrow(/current verified sign-in/i);
    expect(base.request).toHaveBeenCalledTimes(calls);
  });

  it('does not hand a permit to the sender when the server reports an already-recorded start', async () => {
    const {request} = fixture({noPermit: true}), sendOnce = vi.fn(async () => null), operator = new AssistedOperator(context(request, true, {sendOnce}));
    await operator.claim(job); await operator.loadContent(); await operator.confirm(true);
    expect(await operator.startAndSend()).toEqual({permitIssued: false, sentToAdapter: false, adapterResultUnknown: false});
    expect(sendOnce).not.toHaveBeenCalled(); expect(operator.view().attemptId).toBe(attemptId);
  });

  it('does not hand off a recorded start if confirmation expires while the request is in flight', async () => {
    const base = fixture(), sendOnce = vi.fn(async () => null);
    let expireAfterResponse = false;
    const request = vi.fn(async (path: string, options?: {body?: Record<string, unknown>}) => {
      const response = await base.request(path, options);
      if (expireAfterResponse && options?.body?.action === 'record_send_start') vi.spyOn(Date, 'now').mockReturnValue(Date.now() + 120_001);
      return response;
    });
    const operator = new AssistedOperator(context(request, true, {sendOnce}));
    await operator.claim(job); await operator.loadContent(); await operator.confirm(true);
    expireAfterResponse = true;
    await expect(operator.startAndSend()).rejects.toThrow(/start was recorded.*expired/i);
    expect(sendOnce).not.toHaveBeenCalled();
    expect(operator.view()).toMatchObject({jobId: null, destination: null, message: null, attemptId});
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });

  it('retains the original reference without adopting a claim when authority changes in flight', async () => {
    const base = fixture();
    let release!: () => void;
    const request = vi.fn(async (path: string, options?: {body?: Record<string, unknown>}) => {
      const response = await base.request(path, options);
      if (options?.body?.action === 'claim') await new Promise<void>((resolve) => {release = resolve;});
      return response;
    });
    const operator = new AssistedOperator(context(request));
    const claiming = operator.claim(job);
    await vi.waitFor(() => expect(release).toBeDefined());
    current = false; release();
    await expect(claiming).rejects.toBeInstanceOf(OperatorOutcomeUnknown);
    expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
    expect(operator.view()).toMatchObject({jobId: null, destination: null, message: null});
  });

  it('recovers a lost send-start as history only, rejecting any forged recovered permit', async () => {
    const base = fixture(), sendOnce = vi.fn(async () => null);
    let forged = true;
    const request = vi.fn(async (path: string, options?: {body?: Record<string, unknown>}) => {
      const response = await base.request(path, options);
      if (options?.body?.action === 'record_send_start') throw new Error('connection lost');
      if (options?.body?.action === 'get_operation' && forged) {
        const result = response.result as Record<string, unknown>, receipt = result.receipt as Record<string, unknown>;
        return {...response, result: {...result, receipt: {...receipt, may_send: true}}};
      }
      return response;
    });
    const operator = new AssistedOperator(context(request, true, {sendOnce}));
    await operator.claim(job); await operator.loadContent(); await operator.confirm(true);
    let failure: OperatorOutcomeUnknown | null = null;
    try {await operator.startAndSend();} catch (error) {if (error instanceof OperatorOutcomeUnknown) failure = error; else throw error;}
    expect(failure).not.toBeNull(); expect(sendOnce).not.toHaveBeenCalled();
    await expect(operator.checkOriginal(failure!.checkpoint)).rejects.toThrow();
    expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
    forged = false;
    await expect(operator.checkOriginal(failure!.checkpoint)).resolves.toMatchObject({observed: true, action: 'record_send_start', attemptId});
    expect(operator.view()).toMatchObject({jobId: null, destination: null, message: null, attemptId});
    expect(sendOnce).not.toHaveBeenCalled(); expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  });

  it('burns a delayed permit and erases its payload when the page leaves the foreground', async () => {
    const {request} = fixture();
    let take!: Parameters<AssistedSmsSender['sendOnce']>[0], finish!: (value: null) => void;
    const sender: AssistedSmsSender = {sendOnce: (value) => {take = value; return new Promise((resolve) => {finish = resolve;});}};
    const operator = new AssistedOperator(context(request, true, sender));
    await operator.claim(job); await operator.loadContent(); await operator.confirm(true);
    const running = operator.startAndSend();
    await vi.waitFor(() => expect(take).toBeDefined());
    operator.invalidate(); expect(take()).toBeNull(); finish(null);
    expect(await running).toMatchObject({sentToAdapter: false});
    expect(operator.view()).toMatchObject({jobId: null, message: null, destination: null, attemptId: null});
  });
});
