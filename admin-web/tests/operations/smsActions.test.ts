import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readPending, type PendingIdentity } from '../../src/features/core/pendingAttempt';
import { parseSmsPage, type SmsReceipt } from '../../src/features/operations/contracts';
import { lookupSmsExtraction, restoreSmsExtraction, revealSmsSource, submitSmsExtraction, type SmsActionContext } from '../../src/features/operations/smsActions';

const id = '11111111-1111-1111-1111-111111111111';
const actor = '22222222-2222-2222-2222-222222222222';
const key = '33333333-3333-4333-8333-333333333333';
const requestId = '44444444-4444-4444-8444-444444444444';
const factId = '55555555-5555-4555-8555-555555555555';
const hash = 'a'.repeat(64);
const epoch = Date.parse('2026-11-16T08:00:00.000Z') / 1000;

function source(): SmsReceipt {
  const capture = {source_kind: 'capture', id, user_id: actor, payee_id: null, source_sha256: hash, status: 'received', version: 1, received_at: epoch, created_at: epoch,
    public_id: '123456', display_name: null, transaction_id: null, evidence_level: 'client_received', source_fact_id: null, parser_version: null, extraction_status: 'not_extracted',
    source_body_sha256: null, source_payload_sha256: null, parsed_at: null, payer_name: null, payer_phone: null, payer_masked_phone: null, payer_last3: null,
    payee_momo_number: null, payee_momo_code: null, momo_transaction_reference: null, momo_timestamp_local: null, momo_timezone_offset: null, amount_rwf: null,
    wallet_balance_rwf: null, network: null, direction: null, is_payment: null, transaction_reference: null, duplicate_reference_count: 0, conflicting_reference_count: 0,
    provider_confirmation: false, settlement_status: 'not_asserted', timezone_known: false, payer_last3_known: false, source_content_reveal_required: true,
    received_at_device: '2026-11-16T10:00:00+02:00'};
  return parseSmsPage({rows: [capture], total: 1, limit: 25, offset: 0, next_offset: null}, 0).rows[0];
}
function identity(): PendingIdentity {
  return {id: actor, sessionId: 'session-1', email: 'operator@example.com', role: 'admin', permissions: ['sms.read', 'sms.extract', 'sms.reveal'], expiresAt: new Date(Date.now() + 3600000).toISOString()};
}
const saved = {request_id: requestId, status: 'succeeded', resource_type: 'sms_facts', resource_id: factId, source_kind: 'capture', source_id: id, parser_version: 'collect-admin-source-facts-v1'};
function context(request: SmsActionContext['request'], enabled = true): SmsActionContext {
  return {request, identity: identity(), source: source(), enabled, isCurrent: () => true, storage: sessionStorage,
    lock: async (_name, work) => work(), createKey: () => key};
}
async function revision(ctx: SmsActionContext): Promise<string> {const state = await restoreSmsExtraction(ctx); if (state.kind !== 'ready') throw new Error('expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('SMS source actions', () => {
  it('never dispatches while the release gate is disabled', async () => {
    const request = vi.fn();
    await expect(submitSmsExtraction(context(request, false), 'Review source evidence', '')).rejects.toThrow('not enabled');
    expect(request).not.toHaveBeenCalled();
    expect(sessionStorage.length).toBe(0);
  });

  it('retains the original key before dispatch and clears it only after a verified receipt', async () => {
    const request = vi.fn(async (_path: string, options?: {idempotencyKey?: string}) => {
      expect(options?.idempotencyKey).toBe(key);
      expect(await readPending(identity(), 'sms-extraction', `capture:${id}`)).not.toBeNull();
      return saved;
    });
    const ctx = context(request);
    const result = await submitSmsExtraction(ctx, 'Review source evidence', await revision(ctx));
    expect(result.status).toBe('succeeded');
    expect(await readPending(identity(), 'sms-extraction', `capture:${id}`)).toBeNull();
    expect(request).toHaveBeenCalledTimes(1);
  });

  it('retains an uncertain original request and checks it without replay, even if the source changed', async () => {
    const request = vi.fn().mockRejectedValueOnce(new Error('response lost'));
    const ctx = context(request);
    const result = await submitSmsExtraction(ctx, 'Review source evidence', await revision(ctx));
    expect(result).toEqual({status: 'unknown', requestKey: key});
    const changed = {...ctx, source: {...ctx.source, source_sha256: 'b'.repeat(64)}};
    const attempt = await restoreSmsExtraction(changed);
    expect(attempt).toMatchObject({kind: 'owned', requestKey: key});
    request.mockResolvedValueOnce({status: 'not_found'});
    expect(await lookupSmsExtraction(changed, attempt!)).toEqual({status: 'not_found'});
    expect(await restoreSmsExtraction(changed)).toMatchObject({kind: 'owned'});
    expect(request).toHaveBeenCalledTimes(2);
    expect(request).toHaveBeenLastCalledWith(`sms/requests/${key}`);
    request.mockResolvedValueOnce({status: 'succeeded', request_id: requestId, receipt: saved});
    expect((await lookupSmsExtraction(changed, attempt!)).status).toBe('succeeded');
    expect(await restoreSmsExtraction(changed)).toMatchObject({kind: 'ready'});
  });

  it('keeps the checkpoint if a returned receipt is not trustworthy', async () => {
    const request = vi.fn().mockResolvedValue({...saved, source_id: actor});
    const ctx = context(request);
    expect((await submitSmsExtraction(ctx, 'Review source evidence', await revision(ctx))).status).toBe('unknown');
    expect(await restoreSmsExtraction(ctx)).toMatchObject({kind: 'owned', requestKey: key});
  });

  it('does not dispatch without verified recovery storage or a lock', async () => {
    const request = vi.fn();
    const broken = {getItem: () => null, setItem: () => {throw new Error('quota');}, removeItem: () => {}, clear: () => {}, key: () => null, length: 0} satisfies Storage;
    const ctx = context(request);
    const observed = await revision(ctx);
    await expect(submitSmsExtraction({...ctx, storage: broken}, 'Review source evidence', observed)).rejects.toThrow();
    expect(request).not.toHaveBeenCalled();
    const locked: SmsActionContext['lock'] = async () => {throw new Error('locked');};
    await expect(submitSmsExtraction({...context(request), lock: locked}, 'Review source evidence', observed)).rejects.toThrow('locked');
    expect(request).not.toHaveBeenCalled();
  });

  it('reveals source only after permission and reason checks, validating identity and evidence', async () => {
    const request = vi.fn().mockResolvedValue({source_kind: 'capture', source_id: id, raw_sender: 'MTN', raw_body: 'Recorded message', source_sha256: hash, evidence_level: 'client_received', provider_confirmation: false});
    const result = await revealSmsSource(context(request), 'Investigate source message');
    expect(result).toEqual({sender: 'MTN', body: 'Recorded message'});
    expect(request).toHaveBeenCalledWith(`sms/receipts/capture/${id}/content`, {reviewReason: 'Investigate source message'});
    request.mockResolvedValueOnce({source_kind: 'capture', source_id: id, raw_sender: 'MTN', raw_body: 'Recorded message', source_sha256: hash, evidence_level: 'client_received', provider_confirmation: true});
    await expect(revealSmsSource(context(request), 'Investigate source message')).rejects.toThrow();
  });
});
