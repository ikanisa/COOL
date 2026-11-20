import {beforeEach, describe, expect, it, vi} from 'vitest';
import {lookupLegacyPersonAccess, parseLegacyPersonAccessIntent, restoreLegacyPersonAccess, retryLegacyPersonAccess, submitLegacyPersonAccess, type LegacyPersonAccessContext} from '../../src/features/core/legacyPersonAccess';
import {readPending, retainPending, type PendingIdentity} from '../../src/features/core/pendingAttempt';
import type {LegacyPersonSnapshot} from '../../src/features/core/legacyUserEdit';

const actor = '11111111-1111-4111-8111-111111111111', key = '22222222-2222-4222-8222-222222222222';
const requestId = '33333333-3333-4333-8333-333333333333', userId = '44444444-4444-4444-8444-444444444444', operatorId = '55555555-5555-4555-8555-555555555555';
const person: LegacyPersonSnapshot = {id: userId, publicId: '123456', displayName: 'Recorded Person', nameRecorded: true, memberType: 'app', momoProvider: 'mtn_momo', momoNumber: '0788123456', momoCode: '0009', email: 'person@example.test', phone: '+250788123456', status: 'active', operatorId: null, version: 1};
const detail = {resource_type: 'users', current_actor_id: actor, can_manage: true, resource: {id: userId, collect_user_id: userId, public_id: '123456', display_name: 'Recorded Person', display_name_recorded: true, member_type: 'app', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '0009', email: 'person@example.test', phone_e164: '+250788123456', status: 'active', operator_admin_id: null, version: 1}};
const contact = {phone_e164: '+250788123457', expected_version: 1, reason: 'Review contact changes'};
const receipt = {request_id: requestId, resource_type: 'users', resource_id: userId, version: 2, status: 'succeeded'}, found = {status: 'succeeded', request_id: requestId, receipt};
function identity(role: PendingIdentity['role'] = 'admin'): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'operator@example.test', role, permissions: ['users.read', 'users.manage', 'overview.read', ...(role === 'owner' ? ['admin_users.manage'] : [])], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function context(request: LegacyPersonAccessContext['request'], role: PendingIdentity['role'] = 'admin'): LegacyPersonAccessContext {const user = identity(role); return {request, identity: user, actorId: actor, userId, permissions: user.permissions, financialModel: 'transaction_journals', enabled: false, contactsEnabled: true, loginTypeEnabled: true, operatorLinkEnabled: true, verifyFresh: async () => true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function revision(ctx: LegacyPersonAccessContext) {const state = await restoreLegacyPersonAccess(ctx); if (state.kind !== 'ready') throw new Error('Expected ready'); return state.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear();});

describe('legacy person access candidate', () => {
  it('accepts only exact contact/type changes and preserves email-based App sign-in', () => {
    expect(parseLegacyPersonAccessIntent(contact, person)).toEqual(contact);
    expect(parseLegacyPersonAccessIntent({member_type: 'direct', expected_version: 1, reason: 'Review membership type'}, person)).toMatchObject({member_type: 'direct'});
    for (const bad of [{...contact, email: null}, {...contact, email: 'UPPER@example.test'}, {...contact, phone_e164: '0788123457'}, {...contact, expected_version: 2}, {...contact, status: 'active'}, {...contact, reason: 'short'}, {...contact, phone_e164: person.phone}]) expect(() => parseLegacyPersonAccessIntent(bad, person)).toThrow();
    expect(() => parseLegacyPersonAccessIntent(contact, {...person, operatorId})).toThrow();
    expect(() => parseLegacyPersonAccessIntent(contact, {...person, status: 'closed'})).toThrow();
    expect(() => parseLegacyPersonAccessIntent({member_type: 'direct', expected_version: 1, reason: 'Review membership type'}, {...person, momoNumber: ''})).toThrow();
  });
  it('keeps both changes default-off, excludes the canonical model and never dispatches operator links', async () => {
    const request = vi.fn(), ctx = context(request);
    await expect(submitLegacyPersonAccess({...ctx, contactsEnabled: false}, contact, person, '')).rejects.toThrow('not enabled');
    await expect(submitLegacyPersonAccess({...ctx, loginTypeEnabled: false}, {member_type: 'direct', expected_version: 1, reason: 'Review membership type'}, person, '')).rejects.toThrow('not enabled');
    await expect(submitLegacyPersonAccess(ctx, {member_type: 'direct', expected_version: 1, reason: 'Review membership type'}, person, '')).rejects.toThrow('not enabled');
    await expect(submitLegacyPersonAccess(ctx, {email: 'new@example.test', expected_version: 1, reason: 'Review login email'}, person, '')).rejects.toThrow('not enabled');
    await expect(restoreLegacyPersonAccess({...ctx, financialModel: 'canonical_evidence_ledger'})).rejects.toThrow('unavailable');
    await expect(restoreLegacyPersonAccess(context(request, 'staff'))).rejects.toThrow('unavailable');
    await expect(submitLegacyPersonAccess(context(request, 'owner'), {operator_admin_id: operatorId, expected_version: 1, reason: 'Review operator link'}, person, '')).rejects.toThrow('not enabled');
    expect(request).not.toHaveBeenCalled();
  });
  it('rechecks authority and person after fresh verification and verifies actor-scoped receipt', async () => {
    const verify = vi.fn().mockResolvedValue(true);
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'PATCH') {expect(options.body).toEqual(contact); expect(options.idempotencyKey).toBe(key); expect(await readPending(identity(), 'operating-updateuser', userId)).toMatchObject({request_key: key, intent: contact}); return receipt;}
      return path.startsWith('operations/requests/') ? found : detail;
    });
    const ctx = {...context(request), verifyFresh: verify};
    expect(await submitLegacyPersonAccess(ctx, contact, person, await revision(ctx))).toEqual({status: 'succeeded', receipt: {requestId, userId, version: 2}});
    expect(verify).toHaveBeenCalledOnce(); expect(await readPending(identity(), 'operating-updateuser', userId)).toBeNull();
  });
  it('dispatches nothing if verification fails, the gate closes, or a person changes during verification', async () => {
    for (const scenario of ['failed', 'gate', 'changed'] as const) {
      sessionStorage.clear(); localStorage.clear(); let gate = true, reads = 0;
      const request = vi.fn(async () => {reads++; return scenario === 'changed' && reads === 2 ? {...detail, resource: {...detail.resource, version: 2}} : detail;});
      const ctx = {...context(request), isContactsEnabled: () => gate, verifyFresh: async () => {if (scenario === 'gate') gate = false; return scenario !== 'failed';}};
      await expect(submitLegacyPersonAccess(ctx, contact, person, await revision(ctx))).rejects.toThrow();
      expect(request.mock.calls.length).toBe(scenario === 'changed' ? 2 : 1); expect(await readPending(identity(), 'operating-updateuser', userId)).toBeNull();
    }
  });
  it('recovers a lost result by original key and retries only the unchanged request after re-verification', async () => {
    let writes = 0; const verify = vi.fn().mockResolvedValue(true);
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'PATCH') {writes++; expect(options.body).toEqual(contact); expect(options.idempotencyKey).toBe(key); if (writes === 1) throw new Error('lost'); return receipt;}
      return path.startsWith('operations/requests/') ? writes === 1 ? {status: 'not_found'} : found : detail;
    });
    const ctx = {...context(request), verifyFresh: verify};
    expect(await submitLegacyPersonAccess(ctx, contact, person, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreLegacyPersonAccess(ctx);
    expect(await lookupLegacyPersonAccess(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect((await retryLegacyPersonAccess(ctx, pending)).status).toBe('succeeded'); expect(verify).toHaveBeenCalledTimes(2); expect(writes).toBe(2);
  });
  it('keeps foreign, changed, unbound and disabled attempts check-only', async () => {
    await retainPending(identity(), 'operating-updateuser', userId, key, 'users.manage', {...contact});
    const request = vi.fn().mockResolvedValue({status: 'not_found'}), ctx = context(request), pending = await restoreLegacyPersonAccess(ctx);
    expect(await lookupLegacyPersonAccess(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false});
    await expect(retryLegacyPersonAccess(ctx, pending)).rejects.toThrow('remains unresolved');
    expect(await restoreLegacyPersonAccess({...ctx, identity: {...ctx.identity, sessionId: 'another-session'}})).toEqual({kind: 'foreign'});
    expect(request.mock.calls.every(([, options]) => options?.method !== 'PATCH')).toBe(true);
  });
  it('preserves the original request if the contact gate closes while the write is in flight', async () => {
    let gate = true;
    const request = vi.fn(async (path: string, options?: {method?: string}) => {
      if (options?.method === 'PATCH') {gate = false; return receipt;}
      return path.startsWith('operations/requests/') ? {status: 'not_found'} : detail;
    });
    const ctx = {...context(request), isContactsEnabled: () => gate};
    expect(await submitLegacyPersonAccess(ctx, contact, person, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreLegacyPersonAccess(ctx);
    expect(await lookupLegacyPersonAccess(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false});
    expect((await readPending(identity(), 'operating-updateuser', userId))?.request_key).toBe(key);
  });
  it('does not begin a contact change while a profile edit for the same person is unresolved', async () => {
    const profile = {display_name: 'Updated Person', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '', expected_version: 1, reason: 'Reviewed the profile'};
    await retainPending(identity(), 'operating-updateuser', userId, key, 'users.manage', profile);
    const request = vi.fn(), ctx = context(request);
    const result = await submitLegacyPersonAccess(ctx, contact, person, 'unused');
    expect(result.status).toBe('existing'); expect(request).not.toHaveBeenCalled();
  });
});
