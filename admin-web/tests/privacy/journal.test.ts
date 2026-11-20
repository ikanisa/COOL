import {describe, expect, it} from 'vitest';
import {parsePrivacyJournal, privacyJournalKey, type PrivacyPending} from '../../src/features/privacy/contracts';
import {completePrivacyIntent, reservePrivacyIntent, type PrivacyJournalContext} from '../../src/features/privacy/journal';

const actor = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', session = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const requestId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', operationId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const intent: PrivacyPending = {kind: 'claim', actorId: actor, sessionId: session, requestId, operationId,
  parameters: {p_request_id: requestId, p_claim_request_id: operationId, p_expected_revision: 0, p_lease_seconds: 60}};
const receipt = {contract_version: 1, scope: 'account_privacy_review_only', request_id: requestId, claim_request_id: operationId,
  claim_id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', revision: 1, fence: 1, claimed_at: '2026-11-16T12:00:00.000Z',
  expires_at: '2026-11-16T12:01:00.000Z', policy_acceptance_granted: false, destructive_execution_available: false, erasure_completed: false};

describe('privacy review journal', () => {
  it('retains the Flutter-compatible original and clears it only after the matching receipt', async () => {
    const key = privacyJournalKey(actor, session); localStorage.removeItem(key);
    const context: PrivacyJournalContext = {actorId: actor, sessionId: session, current: () => true, storage: localStorage,
      lock: async (name, work) => {expect(name).toBe(`${key}.exclusive`); return work();}};
    const generation = await reservePrivacyIntent(context, intent, 0);
    expect(generation).toBe(1);
    expect(parsePrivacyJournal(localStorage.getItem(key), actor, session).pending?.operationId).toBe(operationId);
    await expect(reservePrivacyIntent(context, intent, 0)).rejects.toThrow();
    await expect(completePrivacyIntent(context, intent, 1, {...receipt, claim_request_id: requestId})).rejects.toThrow();
    expect(parsePrivacyJournal(localStorage.getItem(key), actor, session).pending?.operationId).toBe(operationId);
    expect(await completePrivacyIntent(context, intent, 1, receipt)).toBe(2);
    expect(parsePrivacyJournal(localStorage.getItem(key), actor, session)).toEqual({generation: 2, pending: null});
    await expect(reservePrivacyIntent(context, intent, 0)).rejects.toThrow();
    localStorage.removeItem(key);
  });

  it('refuses writes when the authority changes inside the lock', async () => {
    const key = privacyJournalKey(actor, session); localStorage.removeItem(key);
    let current = true;
    const context: PrivacyJournalContext = {actorId: actor, sessionId: session, current: () => current, storage: localStorage,
      lock: async (_name, work) => {current = false; return work();}};
    await expect(reservePrivacyIntent(context, intent, 0)).rejects.toThrow();
    expect(localStorage.getItem(key)).toBeNull();
  });
});
