import {beforeEach, describe, expect, it, vi} from 'vitest';
import type {PendingIdentity} from '../../src/features/core/pendingAttempt';
import type {MemberReceipt} from '../../src/features/operations/contracts';
import {memberReceiptRevealReason, revealMemberReceipt, type MemberReceiptRevealContext} from '../../src/features/operations/memberReceiptReveal';

const actor = '22222222-2222-4222-8222-222222222222', id = '11111111-1111-4111-8111-111111111111', other = '33333333-3333-4333-8333-333333333333', hash = 'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9';
const receipt: MemberReceipt = {id, user_id: actor, body_sha256: hash, status: 'needs_review', version: 1, received_at: '2026-10-18T08:00:00.000Z', created_at: '2026-10-18T08:00:00.000Z', public_id: '123456', display_name: 'Synthetic member', transaction_id: null, reviewed_at: null};
const response = {submission_id: id, raw_sender: 'MTN MoMo', raw_body: 'hello world', body_sha256: hash, evidence_level: 'member_submitted'};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.test', role: 'admin', permissions: ['payments.read', 'payments.manage'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: MemberReceiptRevealContext['request']): MemberReceiptRevealContext {return {request, identity: identity(), financialModel: 'transaction_journals', receipt, canManage: true, enabled: true, isCurrent: () => true};}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('Legacy member-submitted receipt access', () => {
  it('requires the explicit gate, legacy model, current admin authority and both payment permissions', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(revealMemberReceipt({...ctx, enabled: false}, 'Review the submitted receipt')).rejects.toThrow(/not enabled/);
    await expect(revealMemberReceipt({...ctx, financialModel: 'canonical_evidence_ledger'}, 'Review the submitted receipt')).rejects.toThrow(/unavailable/);
    await expect(revealMemberReceipt({...ctx, canManage: false}, 'Review the submitted receipt')).rejects.toThrow(/unavailable/);
    await expect(revealMemberReceipt({...ctx, identity: {...ctx.identity, role: 'staff'}}, 'Review the submitted receipt')).rejects.toThrow(/unavailable/);
    await expect(revealMemberReceipt({...ctx, identity: {...ctx.identity, permissions: ['payments.read']}}, 'Review the submitted receipt')).rejects.toThrow(/unavailable/);
    await expect(revealMemberReceipt({...ctx, isCurrent: () => false}, 'Review the submitted receipt')).rejects.toThrow(/unavailable/);
    expect(request).not.toHaveBeenCalled();
  });
  it('sends one audited request and checks the exact returned source bytes', async () => {
    const request = vi.fn().mockResolvedValue(response), controller = new AbortController();
    expect(await revealMemberReceipt({...context(request), signal: controller.signal}, ' Review the submitted receipt ')).toEqual({sender: 'MTN MoMo', body: 'hello world', bodySha256: hash});
    expect(request).toHaveBeenCalledOnce(); expect(request).toHaveBeenCalledWith(`gateway/receipts/${id}/content`, {reviewReason: 'Review the submitted receipt', signal: controller.signal});
    expect(localStorage.length).toBe(0); expect(sessionStorage.length).toBe(0);
  });
  it('withholds mismatched IDs, evidence levels, digest, bytes, sender or response shape', async () => {
    for (const invalid of [{...response, submission_id: other}, {...response, evidence_level: 'client_received'}, {...response, body_sha256: 'a'.repeat(64)},
      {...response, raw_body: 'changed'}, {...response, raw_body: 'a'.repeat(16001)}, {...response, raw_sender: ''}, {...response, raw_sender: 'x\u0000y'}, {...response, unexpected: true}])
      await expect(revealMemberReceipt(context(vi.fn().mockResolvedValue(invalid)), 'Review the submitted receipt')).rejects.toThrow();
  });
  it('does not expose content after authority or gate changes and never automatically repeats an unconfirmed audit', async () => {
    let active = true;
    const request = vi.fn().mockImplementation(async () => {active = false; return response;});
    await expect(revealMemberReceipt({...context(request), isCurrent: () => active}, 'Review the submitted receipt')).rejects.toThrow(/unavailable/);
    active = true; await expect(revealMemberReceipt({...context(request), isEnabled: () => active}, 'Review the submitted receipt')).rejects.toThrow(/not enabled/);
    const lost = vi.fn().mockRejectedValue(new Error('lost reply')); await expect(revealMemberReceipt(context(lost), 'Review the submitted receipt')).rejects.toThrow('lost reply');
    expect(lost).toHaveBeenCalledOnce(); expect(localStorage.length).toBe(0); expect(sessionStorage.length).toBe(0);
  });
  it('rejects invalid reasons', () => {
    for (const value of ['short', 'invalid\nreason', 'invalid\u0000reason', 'a'.repeat(1001)]) expect(() => memberReceiptRevealReason(value)).toThrow();
  });
});
