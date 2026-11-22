import {webcrypto} from 'node:crypto';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {listPending, retainPending, type PendingIdentity} from '../../src/features/core/pendingAttempt';
import {parseInvitationAttempt, type InvitationReceipt} from '../../src/session/invitationRecovery';
import {checkTeamInvitation, checkTeamRemoval, removeTeamAccess, retryTeamInvitation, submitTeamInvitation, type TeamMutationContext, type TeamTarget} from '../../src/session/managedTeamMutations';

const ownerId = 'cdd3c1c0-c124-4c8a-9719-bd2435d198d1', memberId = '53c51330-f311-4519-977b-30f67b47c1f1', requestId = '0f689afa-5a45-4fb5-a147-9aff36f137dd';
const identity: PendingIdentity = {id: ownerId, sessionId: requestId, email: 'info@ikanisa.com', role: 'owner', permissions: ['admin_users.read', 'admin_users.manage'], expiresAt: new Date(Date.now() + 3_600_000).toISOString()};
const receipt = {contractVersion: 2, id: memberId, requestId, messageKind: 'auth_invite', emailStatus: 'accepted', accessStatus: 'invited', operation: 'invite', replayed: false, duplicate: false, sourceRequestId: null};
const invite = {kind: 'invite', email: ' STAFF@example.com ', role: 'staff', displayName: '  A Staff  '} as const;
let current: boolean;
const context = (request: TeamMutationContext['request'], enabled = true): TeamMutationContext => ({allowMutations: enabled, identity, request, verify: vi.fn(async () => true), current: () => current});
const invitations = () => listPending(identity, 'team-invitation', 'admin_users.manage');
const removals = () => listPending(identity, 'team-revoke', 'admin_users.manage');
const member: TeamTarget = {id: memberId, email: 'staff@example.com', role: 'staff', status: 'invited', invitation: {id: memberId, requestId, operation: 'invite', messageKind: 'auth_invite', status: 'accepted', accessStatus: 'invited', replayed: false, duplicate: false, sourceRequestId: null, contractVersion: 2}};

beforeEach(() => {Object.defineProperty(globalThis, 'crypto', {value: webcrypto, configurable: true}); sessionStorage.clear(); current = true;});
afterEach(() => {vi.restoreAllMocks();});

describe('gated team management', () => {
  it('fails closed without explicit activation or owner authority', async () => {
    const request = vi.fn(async () => ({}));
    expect(() => submitTeamInvitation(context(request, false), invite)).toThrow();
    expect(() => submitTeamInvitation({...context(request), identity: {...identity, role: 'admin'}}, invite)).toThrow();
    await expect(submitTeamInvitation(context(request), {...invite, email: 'info@ikanisa.com'})).rejects.toThrow();
    expect(request).not.toHaveBeenCalled();
    expect(await invitations()).toHaveLength(0);
  });

  it('writes the exact original invitation and key before sending, then clears only the accepted result', async () => {
    const request = vi.fn(async (_path, options) => {
      const saved = await invitations();
      expect(saved).toHaveLength(1);
      expect(options.idempotencyKey).toBe(saved[0].request_key);
      expect(saved[0].intent.body).toEqual({email: 'staff@example.com', role: 'staff', displayName: 'A Staff'});
      return {ok: true, outcome: 'accepted', ...receipt};
    });
    const ctx = context(request);
    await expect(submitTeamInvitation(ctx, invite)).resolves.toMatchObject({id: memberId, status: 'accepted'});
    expect(ctx.verify).toHaveBeenCalledOnce();
    expect(request).toHaveBeenCalledWith('team/v2/invite', expect.objectContaining({method: 'POST', body: {email: 'staff@example.com', role: 'staff', displayName: 'A Staff'}}));
    expect(await invitations()).toHaveLength(0);
  });

  it('uses the explicitly selected managed v1 invitation contract with the original key', async () => {
    const request = vi.fn(async (_path, options) => {
      const [saved] = await invitations();
      expect(saved.resource_id).toBe('invite');
      expect(saved.intent).toEqual({operation: 'invite', path: 'team/invite', staff_id: null, prior_request_id: null, prior_operation: null, body: {email: 'staff@example.com', role: 'staff', displayName: 'A Staff'}});
      expect(options.idempotencyKey).toBe(saved.request_key);
      return {ok: true, outcome: 'accepted', id: memberId, requestId, emailStatus: 'accepted', accessStatus: 'invited', operation: 'invite', replayed: false, duplicate: false};
    });
    await expect(submitTeamInvitation({...context(request), invitationVersion: 1}, invite)).resolves.toMatchObject({contractVersion: 1, status: 'accepted'});
    expect(request).toHaveBeenCalledWith('team/invite', expect.objectContaining({method: 'POST'}));
    expect(await invitations()).toHaveLength(0);
  });

  it('requires eligible v1 history for resend and never invents a v1 notice-repair route', async () => {
    const request = vi.fn(async (_path, options) => {
      const [saved] = await invitations();
      expect(options.idempotencyKey).toBe(saved.request_key);
      expect(saved.intent).toEqual({operation: 'resend', path: `team/${memberId}/resend`, staff_id: memberId, prior_request_id: requestId, prior_operation: 'invite', body: {}});
      return {ok: true, outcome: 'accepted', id: memberId, requestId: crypto.randomUUID(), emailStatus: 'accepted', accessStatus: 'invited', operation: 'resend', replayed: false, duplicate: false};
    });
    const legacy = {...member, invitation: null, emailStatus: 'accepted', invitationRequestId: requestId, invitationOperation: 'invite' as const};
    const ctx = {...context(request), invitationVersion: 1 as const};
    await expect(submitTeamInvitation(ctx, {kind: 'resend', member: legacy})).resolves.toMatchObject({operation: 'resend'});
    await expect(submitTeamInvitation(ctx, {kind: 'resend', member: {...legacy, emailStatus: 'unknown'}})).rejects.toThrow(/known original/i);
    await expect(submitTeamInvitation(ctx, {kind: 'notice_repair', member: legacy})).rejects.toThrow();
    expect(request).toHaveBeenCalledOnce();
  });

  it('recovers and explicitly retries a lost v1 request with the same key and intent', async () => {
    const send = vi.fn(async () => {throw new Error('connection lost');});
    await expect(submitTeamInvitation({...context(send), invitationVersion: 1}, invite)).rejects.toThrow(/not confirmed/);
    const [saved] = await invitations(), attempt = parseInvitationAttempt(saved);
    expect(attempt.version).toBe(1);
    const lookup = vi.fn(async () => ({ok: true, found: false}));
    await checkTeamInvitation(context(lookup), attempt);
    expect(lookup).toHaveBeenCalledWith('team/invitation-status', {authenticated: true, method: 'GET', idempotencyKey: saved.request_key});
    const retry = vi.fn(async () => ({ok: true, outcome: 'accepted', id: memberId, requestId, emailStatus: 'accepted', accessStatus: 'invited', operation: 'invite', replayed: false, duplicate: false}));
    await expect(retryTeamInvitation(context(retry), attempt)).resolves.toMatchObject({contractVersion: 1});
    expect(retry).toHaveBeenCalledWith('team/invite', {authenticated: true, method: 'POST', body: saved.intent.body, idempotencyKey: saved.request_key});
    expect(await invitations()).toHaveLength(0);
  });

  it('does not touch recovery storage or dispatch if authority changes during its digest', async () => {
    const request = vi.fn(async () => ({}));
    const digest = crypto.subtle.digest.bind(crypto.subtle);
    vi.spyOn(crypto.subtle, 'digest').mockImplementationOnce(async (...args) => {const value = await digest(...args); current = false; return value;});
    await expect(submitTeamInvitation({...context(request), invitationVersion: 1}, invite)).rejects.toThrow();
    expect(request).not.toHaveBeenCalled();
    expect(sessionStorage.length).toBe(0);
  });

  it('does not dispatch when durable per-tab checkpoint storage fails', async () => {
    const request = vi.fn(async () => ({}));
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {throw new Error('storage unavailable');});
    await expect(submitTeamInvitation(context(request), invite)).rejects.toThrow();
    expect(request).not.toHaveBeenCalled();
  });

  it('retains an uncertain invitation, blocks a new one, and checks only the original key', async () => {
    const request = vi.fn(async () => {throw new Error('connection lost');});
    const ctx = context(request);
    await expect(submitTeamInvitation(ctx, invite)).rejects.toThrow(/not confirmed/);
    const [saved] = await invitations();
    expect(saved).toBeDefined();
    await expect(submitTeamInvitation(ctx, invite)).rejects.toThrow(/original/);
    expect(request).toHaveBeenCalledOnce();
    const lookup = vi.fn(async () => ({ok: true, found: true, ...receipt}));
    await expect(checkTeamInvitation(context(lookup), parseInvitationAttempt(saved))).resolves.toMatchObject({found: true});
    expect(lookup).toHaveBeenCalledWith('team/v2/invitation-status', {authenticated: true, method: 'GET', idempotencyKey: saved.request_key});
    expect(await invitations()).toHaveLength(0);
  });

  it('keeps the original checkpoint when lookup is missing, unconfirmed, or for a different operation', async () => {
    const request = vi.fn(async () => {throw new Error('connection lost');});
    await expect(submitTeamInvitation(context(request), invite)).rejects.toThrow();
    const attempt = parseInvitationAttempt((await invitations())[0]);
    await checkTeamInvitation(context(vi.fn(async () => ({ok: true, found: false, contractVersion: 2}))), attempt);
    await checkTeamInvitation(context(vi.fn(async () => ({ok: true, found: true, ...receipt, emailStatus: 'unknown'}))), attempt);
    await expect(checkTeamInvitation(context(vi.fn(async () => ({ok: true, found: true, ...receipt, operation: 'resend'}))), attempt)).rejects.toThrow();
    expect(await invitations()).toHaveLength(1);
  });

  it('retries only after an explicit not-found lookup and uses the identical original key and body once', async () => {
    const failure = vi.fn(async () => {throw new Error('connection lost');});
    await expect(submitTeamInvitation(context(failure), invite)).rejects.toThrow();
    const saved = (await invitations())[0], attempt = parseInvitationAttempt(saved);
    const send = vi.fn(async () => ({ok: true, outcome: 'accepted', ...receipt}));
    await expect(retryTeamInvitation(context(send), attempt)).rejects.toThrow(/Check the original/);
    expect(send).not.toHaveBeenCalled();
    const lookup = vi.fn(async () => ({ok: true, found: false, contractVersion: 2}));
    await checkTeamInvitation(context(lookup), attempt);
    await expect(retryTeamInvitation(context(send), attempt)).resolves.toMatchObject({status: 'accepted'});
    expect(send).toHaveBeenCalledWith('team/v2/invite', {authenticated: true, method: 'POST', body: saved.intent.body, idempotencyKey: saved.request_key});
    await expect(retryTeamInvitation(context(send), attempt)).rejects.toThrow(/Check the original/);
    expect(send).toHaveBeenCalledOnce();
    expect(await invitations()).toHaveLength(0);
  });

  it('retains a response when authority changes while a request is in flight', async () => {
    const request = vi.fn(async () => {current = false; return {ok: true, outcome: 'accepted', ...receipt};});
    await expect(submitTeamInvitation(context(request), invite)).rejects.toThrow(/not confirmed/);
    expect(await invitations()).toHaveLength(1);
  });

  it('only resends or repairs from a known eligible original invitation', async () => {
    const request = vi.fn(async (path) => path.endsWith('/resend') ? {ok: true, outcome: 'accepted', ...receipt, operation: 'resend'} : {ok: true, outcome: 'accepted', ...receipt, operation: 'notice_repair', messageKind: 'access_notice', emailStatus: undefined, noticeStatus: 'accepted', sourceRequestId: requestId});
    await expect(submitTeamInvitation(context(request), {kind: 'resend', member})).resolves.toMatchObject({operation: 'resend'});
    await expect(submitTeamInvitation(context(request), {kind: 'resend', member: {...member, status: 'active'}})).rejects.toThrow();
    const original: InvitationReceipt = {...member.invitation!, status: 'already_registered', accessStatus: 'active'};
    const repairRequest = vi.fn(async () => ({ok: true, outcome: 'accepted', contractVersion: 2, id: memberId, requestId: '6ea1b44a-25b7-4f2a-9d20-5829675211bc', messageKind: 'access_notice', noticeStatus: 'accepted', accessStatus: 'active', operation: 'notice_repair', replayed: false, duplicate: false, sourceRequestId: requestId}));
    await expect(submitTeamInvitation(context(repairRequest), {kind: 'notice_repair', member: {...member, status: 'active', invitation: original}})).resolves.toMatchObject({operation: 'notice_repair'});
    expect(repairRequest).toHaveBeenCalledWith(`team/v2/${memberId}/access-notice`, expect.objectContaining({body: {sourceRequestId: requestId}}));
  });

  it('retains an unconfirmed removal without inventing a server key, and only a current revoked state clears it', async () => {
    const request = vi.fn(async (_path, options) => {expect(options.idempotencyKey).toBeUndefined(); throw new Error('connection lost');});
    await expect(removeTeamAccess(context(request), member)).rejects.toThrow(/not confirmed/);
    const [saved] = await removals();
    expect(saved.intent).toEqual({email: member.email, path: `team/${member.id}/revoke`, staff_id: member.id});
    const read = (status: string) => vi.fn(async () => ({contractVersion: 2, canManage: true, currentEmail: identity.email, members: [{id: memberId, email: member.email, role: member.role, status}]}));
    await expect(checkTeamRemoval(context(read('active')), saved)).resolves.toBe(false);
    expect(await removals()).toHaveLength(1);
    await expect(checkTeamRemoval(context(read('revoked')), saved)).resolves.toBe(true);
    expect(await removals()).toHaveLength(0);
    expect(request).toHaveBeenCalledOnce();
  });

  it('blocks new v1 removals while permitting a current-state check for an existing checkpoint', async () => {
    const failed = vi.fn(async () => ({}));
    await expect(removeTeamAccess({...context(failed), invitationVersion: 1}, member)).rejects.toThrow(/recovery is unavailable/);
    expect(failed).not.toHaveBeenCalled();
    const saved = await retainPending(identity, 'team-revoke', memberId, crypto.randomUUID(), 'admin_users.manage', {staff_id: memberId, email: member.email, path: `team/${memberId}/revoke`});
    const read = vi.fn(async () => ({canManage: true, currentEmail: identity.email, members: [{id: memberId, email: member.email, role: member.role, status: 'revoked'}]}));
    await expect(checkTeamRemoval({...context(read), invitationVersion: 1}, saved)).resolves.toBe(true);
    expect(read).toHaveBeenCalledWith('team', {authenticated: true, method: 'GET'});
    expect(failed).not.toHaveBeenCalled();
    expect(await removals()).toHaveLength(0);
  });
});
