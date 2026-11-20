import {webcrypto} from 'node:crypto';
import {beforeEach, describe, expect, it, vi} from 'vitest';
import {lookupInvitation, parseInvitationAttempt, parseInvitationReceipt} from '../../src/session/invitationRecovery';
import {listPending, retainPending, type PendingAttempt, type PendingIdentity} from '../../src/features/core/pendingAttempt';

const id = 'cdd3c1c0-c124-4c8a-9719-bd2435d198d1';
const requestId = '0f689afa-5a45-4fb5-a147-9aff36f137dd';
const checkpoint: PendingAttempt = {family: 'team-invitation', resource_id: 'v2:invite', request_key: 'original-key-12345', permission: 'admin_users.manage', created_at: Date.now(), expires_at: Date.now() + 60_000, intent: {contract_version: 2, operation: 'invite', path: 'team/v2/invite', staff_id: null, prior_request_id: null, prior_operation: null, body: {email: 'staff@example.com', role: 'staff', displayName: 'A Staff'}}};
const receipt = {contractVersion: 2, id, requestId, messageKind: 'auth_invite', emailStatus: 'accepted', accessStatus: 'invited', operation: 'invite', replayed: false, duplicate: false, sourceRequestId: null};
beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true}); sessionStorage.clear();});

describe('original invitation recovery', () => {
  it('checks the retained request using only its original key and never posts', async () => {
    const attempt = parseInvitationAttempt(checkpoint);
    const request = vi.fn(async () => ({ok: true, found: true, ...receipt}));
    const result = await lookupInvitation(request, attempt);
    expect(result).toMatchObject({found: true, receipt: {status: 'accepted', requestId}});
    expect(request).toHaveBeenCalledOnce();
    expect(request).toHaveBeenCalledWith('team/v2/invitation-status', {authenticated: true, method: 'GET', idempotencyKey: 'original-key-12345'});
  });

  it('recovers a per-tab retained invitation without clearing or replaying it', async () => {
    const identity: PendingIdentity = {id, sessionId: requestId, email: 'info@ikanisa.com', role: 'owner', permissions: ['admin_users.manage'], expiresAt: new Date(Date.now() + 3_600_000).toISOString()};
    await retainPending(identity, checkpoint.family, checkpoint.resource_id, checkpoint.request_key, checkpoint.permission, checkpoint.intent);
    const saved = await listPending(identity, 'team-invitation', 'admin_users.manage');
    const request = vi.fn(async () => ({ok: true, found: true, ...receipt}));
    await lookupInvitation(request, parseInvitationAttempt(saved[0]));
    expect(await listPending(identity, 'team-invitation', 'admin_users.manage')).toHaveLength(1);
    expect(request).toHaveBeenCalledOnce();
  });

  it('keeps missing or unconfirmed requests distinct from completion', async () => {
    const attempt = parseInvitationAttempt(checkpoint);
    const request = vi.fn(async () => ({ok: true, found: false, contractVersion: 2}));
    await expect(lookupInvitation(request, attempt)).resolves.toEqual({found: false});
    expect(request).toHaveBeenCalledOnce();
  });

  it('rejects tampered retained bodies, wrong identities and malformed receipts', async () => {
    expect(() => parseInvitationAttempt({...checkpoint, intent: {...checkpoint.intent, body: {email: 'staff@example.com', role: 'owner', displayName: 'A'}}})).toThrow();
    expect(() => parseInvitationAttempt({...checkpoint, resource_id: 'different'})).toThrow();
    expect(() => parseInvitationReceipt({...receipt, messageKind: 'access_notice', noticeStatus: 'accepted'}, 2)).toThrow();
    const attempt = parseInvitationAttempt(checkpoint);
    const request = vi.fn(async () => ({ok: true, found: true, ...receipt, operation: 'resend'}));
    await expect(lookupInvitation(request, attempt)).rejects.toThrow();
  });
});
