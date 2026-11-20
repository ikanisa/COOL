import {render, screen, within} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {UserEditPage} from '../../src/features/core/UserEditPage';
import {lookupLegacyUserEdit, parseLegacyUserEditIntent, restoreLegacyUserEdit, retryLegacyUserEdit, submitLegacyUserEdit, type LegacyPersonSnapshot, type LegacyUserEditContext} from '../../src/features/core/legacyUserEdit';
import {readPending, retainPending, type PendingIdentity} from '../../src/features/core/pendingAttempt';

const actor = '11111111-1111-4111-8111-111111111111', key = '22222222-2222-4222-8222-222222222222';
const requestId = '33333333-3333-4333-8333-333333333333', userId = '44444444-4444-4444-8444-444444444444';
const identity: PendingIdentity = {id: actor, sessionId: 'session-1', email: 'operator@example.test', role: 'admin', permissions: ['users.read', 'users.manage', 'overview.read'], expiresAt: '2100-01-01T00:00:00.000Z'};
const person: LegacyPersonSnapshot = {id: userId, publicId: '123456', displayName: 'Recorded Person', nameRecorded: true, memberType: 'app', momoProvider: 'mtn_momo', momoNumber: '0788123456', momoCode: '', email: 'person@example.test', phone: '+250788123456', status: 'active', operatorId: null, version: 1};
const detail = {resource_type: 'users', current_actor_id: actor, can_manage: true, resource: {id: userId, collect_user_id: userId, public_id: '123456', display_name: 'Recorded Person', display_name_recorded: true, member_type: 'app', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: null, email: 'person@example.test', phone_e164: '+250788123456', status: 'active', operator_admin_id: null, version: 1}};
const intent = {status: 'suspended', expected_version: 1, reason: 'Reviewed the account status'};
const receipt = {request_id: requestId, resource_type: 'users', resource_id: userId, version: 2, status: 'succeeded'};
const originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
function context(request: LegacyUserEditContext['request']): LegacyUserEditContext {
  return {request, identity, actorId: actor, userId, permissions: identity.permissions, financialModel: 'transaction_journals', enabled: false,
    statusEnabled: true, verifyStatusFresh: async () => true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage,
    lock: async (_name, work) => work(), createKey: () => key};
}
async function revision(ctx: LegacyUserEditContext) {const pending = await restoreLegacyUserEdit(ctx); if (pending.kind !== 'ready') throw new Error('Expected ready'); return pending.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('legacy person status changes', () => {
  it('accepts only a status, exact version and reason, with its own default-off gate', async () => {
    expect(parseLegacyUserEditIntent(intent, 'app')).toEqual(intent);
    for (const bad of [{...intent, status: 'deleted'}, {...intent, status: 'suspended', email: 'change@example.test'}, {...intent, reason: 'short'}, {...intent, expected_version: Number.MAX_SAFE_INTEGER}]) {
      expect(() => parseLegacyUserEditIntent(bad, 'app')).toThrow();
    }
    const request = vi.fn(), ctx = {...context(request), statusEnabled: false};
    await expect(submitLegacyUserEdit(ctx, intent, person, '')).rejects.toThrow('not enabled');
    await expect(submitLegacyUserEdit(context(request), {...intent, status: 'active'}, person, '')).rejects.toThrow('different status');
    expect(request).not.toHaveBeenCalled();
  });

  it('rechecks the person after fresh verification and verifies the original receipt', async () => {
    const verify = vi.fn().mockResolvedValue(true);
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'PATCH') {expect(options.body).toEqual(intent); expect(options.idempotencyKey).toBe(key); return receipt;}
      return path.startsWith('operations/requests/') ? {status: 'succeeded', request_id: requestId, receipt} : detail;
    });
    const ctx = {...context(request), verifyStatusFresh: verify};
    expect(await submitLegacyUserEdit(ctx, intent, person, await revision(ctx))).toEqual({status: 'succeeded', receipt: {requestId, userId, version: 2}});
    expect(verify).toHaveBeenCalledOnce(); expect(request).toHaveBeenCalledTimes(4);
    expect(await readPending(identity, 'operating-updateuser', userId)).toBeNull();
  });

  it('dispatches nothing when verification fails, the gate closes, or the person changes during verification', async () => {
    for (const scenario of ['failed', 'gate', 'changed'] as const) {
      sessionStorage.clear(); localStorage.clear(); let gate = true, reads = 0;
      const request = vi.fn(async () => {reads++; return scenario === 'changed' && reads === 2 ? {...detail, resource: {...detail.resource, version: 2}} : detail;});
      const ctx = {...context(request), isStatusEnabled: () => gate, verifyStatusFresh: async () => {if (scenario === 'gate') gate = false; return scenario !== 'failed';}};
      await expect(submitLegacyUserEdit(ctx, intent, person, await revision(ctx))).rejects.toThrow();
      expect(request.mock.calls.length).toBe(scenario === 'changed' ? 2 : 1);
      expect(await readPending(identity, 'operating-updateuser', userId)).toBeNull();
    }
  });

  it('preserves an uncertain status change and retries only the same key and body after another verification', async () => {
    let writes = 0; const verify = vi.fn().mockResolvedValue(true);
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown; idempotencyKey?: string}) => {
      if (options?.method === 'PATCH') {writes++; expect(options.body).toEqual(intent); expect(options.idempotencyKey).toBe(key); if (writes === 1) throw new Error('lost'); return receipt;}
      if (path.startsWith('operations/requests/')) return writes === 1 ? {status: 'not_found'} : {status: 'succeeded', request_id: requestId, receipt};
      return detail;
    });
    const ctx = {...context(request), verifyStatusFresh: verify};
    expect(await submitLegacyUserEdit(ctx, intent, person, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreLegacyUserEdit(ctx);
    expect(await lookupLegacyUserEdit(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    expect((await retryLegacyUserEdit(ctx, pending)).status).toBe('succeeded');
    expect(verify).toHaveBeenCalledTimes(2); expect(writes).toBe(2);
  });

  it('keeps the original status request check-only if the gate closes before dispatch', async () => {
    let gate = true;
    const storage: Storage = {
      get length() {return sessionStorage.length;}, clear: () => sessionStorage.clear(), key: index => sessionStorage.key(index),
      getItem: name => sessionStorage.getItem(name), removeItem: name => sessionStorage.removeItem(name),
      setItem: (name, value) => {sessionStorage.setItem(name, value); if (name.startsWith('collect.admin.legacy-user-edit.context.v1:')) gate = false;},
    };
    const request = vi.fn(async (path: string, _options?: {method?: string}) => path.startsWith('operations/requests/') ? {status: 'not_found'} : detail);
    const ctx = {...context(request), storage, isStatusEnabled: () => gate};
    expect(await submitLegacyUserEdit(ctx, intent, person, await revision(ctx))).toEqual({status: 'unknown', requestKey: key});
    const saved = await restoreLegacyUserEdit(ctx);
    expect(await lookupLegacyUserEdit(ctx, saved)).toEqual({status: 'not_found', retryAvailable: false});
    expect(request.mock.calls.every(([, options]) => options?.method !== 'PATCH')).toBe(true);
    expect(await readPending(identity, 'operating-updateuser', userId)).not.toBeNull();
  });

  it('keeps older unbound status requests and disabled status recovery check-only', async () => {
    await retainPending(identity, 'operating-updateuser', userId, key, 'users.manage', {...intent, display_name: 'Recorded Person'});
    const request = vi.fn().mockResolvedValue({status: 'not_found'}), ctx = context(request), pending = await restoreLegacyUserEdit(ctx);
    expect(await lookupLegacyUserEdit(ctx, pending)).toEqual({status: 'not_found', retryAvailable: false});
    await expect(retryLegacyUserEdit(ctx, pending)).rejects.toThrow('remains unresolved');
    expect(request).toHaveBeenCalledTimes(2);
  });

  it('does not start a status change while a profile edit for the same person is unresolved', async () => {
    const profile = {display_name: 'Updated Person', momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '', expected_version: 1, reason: 'Reviewed the profile'};
    let writes = 0;
    const request = vi.fn(async (path: string, options?: {method?: string}) => {
      if (options?.method === 'PATCH') {writes++; throw new Error('lost');}
      return path.startsWith('operations/requests/') ? {status: 'not_found'} : detail;
    });
    const profileContext = {...context(request), enabled: true, statusEnabled: false};
    expect((await submitLegacyUserEdit(profileContext, profile, person, await revision(profileContext))).status).toBe('unknown');
    const statusContext = context(request), pending = await restoreLegacyUserEdit(statusContext);
    expect(pending.kind).toBe('owned');
    expect(await lookupLegacyUserEdit(statusContext, pending)).toEqual({status: 'not_found', retryAvailable: false});
    expect((await submitLegacyUserEdit(statusContext, intent, person, '')).status).toBe('existing');
    expect(writes).toBe(1);
  });
});

describe('separately gated status review', () => {
  it('requires a review, explicit confirmation and fresh verification without enabling profile editing', async () => {
    const user = userEvent.setup(), verify = vi.fn().mockResolvedValue(true);
    const request = vi.fn(async (path: string, options?: {method?: string; body?: unknown}) => {
      if (options?.method === 'PATCH') {expect(options.body).toEqual({...intent, status: 'closed'}); return receipt;}
      return path.startsWith('operations/requests/') ? {status: 'succeeded', request_id: requestId, receipt} : detail;
    });
    render(<UserEditPage id={userId} identity={identity} request={request} actorId={actor} principalId={null} role="admin" authorityKey="session-1" permissions={identity.permissions} financialModel="transaction_journals" navigate={() => undefined} allowStatusChanges verifyFresh={verify} />);
    const reason = await screen.findByLabelText('Reason for status change');
    expect(screen.queryByLabelText('Recorded full name')).not.toBeInTheDocument();
    await user.selectOptions(screen.getByLabelText('New account status'), 'closed'); await user.type(reason, intent.reason);
    await user.click(screen.getByRole('button', {name: 'Review account status'}));
    expect(screen.getByText(/Closing cannot be reversed from this editor/)).toBeVisible();
    expect(screen.getByRole('button', {name: 'Confirm account status'})).toBeDisabled(); expect(verify).not.toHaveBeenCalled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the person details and reason.'}));
    await user.click(screen.getByRole('button', {name: 'Confirm account status'}));
    expect(within(await screen.findByRole('status')).getByText('The person was updated.')).toBeVisible(); expect(verify).toHaveBeenCalledOnce();
  });

  it('keeps status controls hidden without their separate gate', async () => {
    const request = vi.fn(); render(<UserEditPage id={userId} identity={identity} request={request} actorId={actor} principalId={null} role="admin" authorityKey="session-1" permissions={identity.permissions} financialModel="transaction_journals" navigate={() => undefined} verifyFresh={async () => true} />);
    expect(await screen.findByText('Person editing is not enabled for this workspace.')).toBeVisible();
    expect(screen.queryByLabelText('New account status')).not.toBeInTheDocument(); expect(request).not.toHaveBeenCalled();
  });
});
