import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PendingIdentity } from '../../src/features/core';
import type { MomoSourceJob } from '../../src/features/operations/momoContracts';
import { momoRevealReason, revealMomoSource, type MomoSourceRevealContext } from '../../src/features/operations/momoSourceReveal';
import {nonPaymentExtraction} from '../../src/features/operations/momoSourceActions';

const rawId = '11111111-1111-4111-8111-111111111111', actor = '22222222-2222-4222-8222-222222222222', other = '33333333-3333-4333-8333-333333333333';
const hash = 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9', reason = 'Investigate source evidence';
const source: MomoSourceJob = {raw_sms_id: rawId, state: 'needs_review', binding_id: null, receiving_account_id: null, received_at: '2026-10-18T08:00:00.000Z', last_error: 'schema_mismatch', body_sha256: hash};
const response = {raw_sms_id: rawId, body_sha256: hash, raw_sender: 'MTN MoMo', raw_body: 'hello world', latest_attempt: null};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'operator@example.com', role: 'admin', permissions: ['sms.read', 'sms.reveal'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: MomoSourceRevealContext['request']): MomoSourceRevealContext {return {request, identity: identity(), financialModel: 'canonical_evidence_ledger', source, enabled: true, isCurrent: () => true, verifyFresh: async () => true};}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('MoMo audited source access', () => {
  it('requires the gate, current read and reveal permissions, canonical model and fresh verification', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(revealMomoSource({...ctx, enabled: false}, reason)).rejects.toThrow('not enabled');
    await expect(revealMomoSource({...ctx, identity: {...ctx.identity, permissions: ['sms.reveal']}}, reason)).rejects.toThrow('unavailable');
    await expect(revealMomoSource({...ctx, identity: {...ctx.identity, permissions: ['sms.read']}}, reason)).rejects.toThrow('unavailable');
    await expect(revealMomoSource({...ctx, financialModel: 'transaction_journals'}, reason)).rejects.toThrow('unavailable');
    await expect(revealMomoSource({...ctx, source: {...source, body_sha256: undefined}}, reason)).rejects.toThrow('unavailable');
    await expect(revealMomoSource({...ctx, verifyFresh: async () => false}, reason)).rejects.toThrow('current verification');
    expect(request).not.toHaveBeenCalled();
  });
  it('sends a single audited GET with the exact trimmed reason and validates source bytes', async () => {
    const request = vi.fn().mockResolvedValue(response), ctx = context(request), controller = new AbortController();
    expect(await revealMomoSource({...ctx, signal: controller.signal}, ` ${reason} `)).toEqual({sender: 'MTN MoMo', body: 'hello world', bodySha256: hash});
    expect(request).toHaveBeenCalledOnce();
    expect(request).toHaveBeenCalledWith(`momo/sources/${rawId}/content`, {reviewReason: reason, signal: controller.signal});
    expect(localStorage.length).toBe(0); expect(sessionStorage.length).toBe(0);
  });
  it('returns a well-formed latest extraction as an unverified suggestion after source verification', async () => {
    const candidate = {...nonPaymentExtraction('failed', 'hello'), event_kind: 'incoming_receipt', payment_outcome: 'successful', transaction_id_raw: 'hello'};
    const request = vi.fn().mockResolvedValue({...response, latest_attempt: {output_json: JSON.stringify(candidate)}});
    expect(await revealMomoSource(context(request), reason)).toMatchObject({candidate: {transaction_id_raw: 'hello'}});
    expect(request).toHaveBeenCalledOnce();
    const invalid = vi.fn().mockResolvedValue({...response, latest_attempt: {output_json: '{invalid'}});
    expect(await revealMomoSource(context(invalid), reason)).not.toHaveProperty('candidate');
  });
  it('rejects invalid reasons and a gate or session change before the audited request', async () => {
    for (const value of ['short', 'some\nreason with newline', 'some\u0000reason', 'a'.repeat(501)]) expect(() => momoRevealReason(value)).toThrow();
    let admitted = true;
    const request = vi.fn(), ctx = {...context(request), isEnabled: () => admitted, verifyFresh: async () => {admitted = false; return true;}};
    await expect(revealMomoSource(ctx, reason)).rejects.toThrow('not enabled');
    await expect(revealMomoSource({...context(request), isCurrent: () => false}, reason)).rejects.toThrow('unavailable');
    expect(request).not.toHaveBeenCalled();
  });
  it('withholds data for identity, hash, bytes, sender or response-shape mismatches', async () => {
    for (const invalid of [
      {...response, raw_sms_id: other}, {...response, body_sha256: 'a'.repeat(64)}, {...response, raw_body: 'changed body'},
      {...response, raw_body: 'a'.repeat(16385)}, {...response, raw_sender: ''}, {...response, raw_sender: 'x\u0000y'},
      {...response, latest_attempt: undefined}, {...response, unexpected: 'value'},
    ]) {
      const candidate = {...invalid}; if (candidate.latest_attempt === undefined) Reflect.deleteProperty(candidate, 'latest_attempt');
      await expect(revealMomoSource(context(vi.fn().mockResolvedValue(candidate)), reason)).rejects.toThrow();
    }
  });
  it('does not disclose a response after authority or action gate changes in flight', async () => {
    let active = true;
    const request = vi.fn().mockImplementation(async () => {active = false; return response;});
    await expect(revealMomoSource({...context(request), isCurrent: () => active}, reason)).rejects.toThrow('unavailable');
    active = true;
    await expect(revealMomoSource({...context(request), isEnabled: () => active}, reason)).rejects.toThrow('not enabled');
  });
  it('does not retry or create a fabricated recovery key after a lost response', async () => {
    const request = vi.fn().mockRejectedValue(new Error('connection lost'));
    await expect(revealMomoSource(context(request), reason)).rejects.toThrow('connection lost');
    expect(request).toHaveBeenCalledOnce();
    expect(request).toHaveBeenCalledWith(`momo/sources/${rawId}/content`, {reviewReason: reason});
    expect(localStorage.length).toBe(0); expect(sessionStorage.length).toBe(0);
  });
});
