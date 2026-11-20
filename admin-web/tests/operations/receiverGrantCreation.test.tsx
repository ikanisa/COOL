import {render, screen} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach, beforeAll, beforeEach, describe, expect, it, vi} from 'vitest';
import type {AdminRequest, AdminRequestOptions} from '../../src/api/client';
import {readPending, retainPending, type PendingIdentity} from '../../src/features/core/pendingAttempt';
import {withPendingFence, type FenceLock} from '../../src/features/operations/pendingFence';
import {loadGrantDevices, loadGrantPayees, loadGrantTargets, loadOriginalGrantTargets, lookupGrantCreation, restoreGrantCreation, retryGrantCreation, submitGrantCreation, verifyGrantSelection, type GrantCreateContext} from '../../src/features/operations/receiverGrantCreation';

const mock = vi.hoisted(() => ({request: vi.fn(), user: {id: '22222222-2222-4222-8222-222222222222', sessionId: 'session-1', email: 'admin@example.test', role: 'admin' as const, permissions: ['gateway.read', 'gateway.manage', 'receivers.read'], expiresAt: new Date(Date.now() + 3600000).toISOString(), financialModel: 'transaction_journals' as const}}));
vi.mock('../../src/session/SessionProvider', () => ({useSession: () => ({user: mock.user, epoch: 1, status: 'authenticated', request: mock.request, isCurrentAuthority: () => true})}));
import {ReceiverGrantCreatePanel} from '../../src/features/operations/ReceiverGrantCreatePanel';

const actor = mock.user.id, deviceId = '33333333-3333-4333-8333-333333333333', payeeId = '44444444-4444-4444-8444-444444444444', groupId = '55555555-5555-4555-8555-555555555555', key = '66666666-6666-4666-8666-666666666666', operationId = '77777777-7777-4777-8777-777777777777', grantId = '88888888-8888-4888-8888-888888888888', installation = '99999999-9999-4999-8999-999999999999', otherKey = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const time = '2026-11-16T08:00:00.000Z', reason = 'Reviewed capture scope', originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
const receipt = {request_id: operationId, resource_type: 'receiver_capture_grants', resource_id: grantId, version: 1, status: 'succeeded'};
const intent = {device_id: deviceId, expected_device_version: 2, payee_id: payeeId, expected_payee_version: 3, reason};
let device: Record<string, unknown>, deviceDetail: Record<string, unknown>, payeeDetail: Record<string, unknown>, payeeRow: Record<string, unknown>, grantDetail: Record<string, unknown>;
function identity(): PendingIdentity {return {...mock.user, permissions: [...mock.user.permissions]};}
function context(request: AdminRequest): GrantCreateContext {return {request, identity: identity(), financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
async function ready(ctx: GrantCreateContext) {const state = await restoreGrantCreation(ctx); if (state.kind !== 'ready') throw new Error('Expected a clear checkpoint'); return state.revision;}
function mockRequest(onPost: (options?: AdminRequestOptions) => Promise<Record<string, unknown>> = async () => receipt) {
  return vi.fn(async (path: string, options?: AdminRequestOptions): Promise<Record<string, unknown>> => {
    if (path.startsWith('gateway/devices?')) return {rows: [device], total: 1};
    if (path.startsWith('core/payees?')) return {rows: [payeeRow], total: 1};
    if (path === `gateway/devices/${deviceId}`) return deviceDetail;
    if (path === `operations/payees/${payeeId}`) return payeeDetail;
    if (path === 'gateway/receiver-grants') return onPost(options);
    if (path === `gateway/receiver-requests/${key}`) return {found: false};
    if (path === `gateway/receiver-grants/${grantId}?limit=25&offset=0`) return grantDetail;
    throw new Error(`Unexpected synthetic request ${path}`);
  });
}
beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({name: 'ECDSA', namedCurve: 'P-256'}, true, ['sign', 'verify']);
  const bytes = new Uint8Array(await crypto.subtle.exportKey('spki', pair.publicKey)), encoded = btoa(String.fromCharCode(...bytes));
  const fingerprint = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(value => value.toString(16).padStart(2, '0')).join('');
  device = {id: deviceId, label: 'Synthetic handset', app_id: 'app.collect.gateway', installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64), state: 'active', version: 2, created_at: time, activated_at: time, revoked_at: null, last_heartbeat_at: null, carrier_proof: false, send_authority: false};
  deviceDetail = {resource_type: 'gateway_devices', resource: {...device, public_key_spki_base64: encoded}, current_actor_id: actor, can_manage: true, related_truncated: false, related: {heartbeats: []}, enrollment: {contract_version: 1, device_id: deviceId, installation_id: installation, key_sha256: fingerprint, signing_certificate_sha256: 'b'.repeat(64)}};
  const payee = {id: payeeId, group_id: groupId, label: 'Synthetic receiver', network: 'mtn_momo', momo_number_or_code: '123456', status: 'active', version: 3};
  payeeDetail = {resource_type: 'payees', resource: payee, current_actor_id: actor, can_manage: true, related: {}, related_pages: {}, related_truncated: false};
  payeeRow = {id: payeeId, title: 'Synthetic receiver', subtitle: 'Synthetic group', amount: '123456', status: 'active', country_code: 'RW', currency_code: 'RWF', created_at: time, group_id: groupId, group_name: 'Synthetic group', network: 'mtn_momo', momo_masked: '***456', momo_number_or_code: '123456', momo_number: null, momo_pay_code: '123456'};
  const grant = {id: grantId, device_id: deviceId, device_label: 'Synthetic handset', installation_id: installation, key_sha256: fingerprint, payee_id: payeeId, payee_label: 'Synthetic receiver', payee_network: 'mtn_momo', payee_momo_number_or_code: '123456', status: 'active', version: 1, created_by_admin_id: actor, created_at: time, revoked_by_admin_id: null, revoked_at: null, capture_authority: true, send_authority: false, financial_authority: false};
  grantDetail = {resource_type: 'receiver_capture_grants', resource: grant, current_actor_id: actor, can_manage: true, related: {captures: []}, related_total: 0, related_limit: 25, related_offset: 0};
});
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, work: (lock: {name: string}) => Promise<unknown>) => work({name})}});});
afterEach(() => {mock.request.mockReset(); if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('Legacy receiver capture grant creation', () => {
  it('requires the explicit gate, legacy model and current non-staff permissions', async () => {
    const request = mockRequest(), ctx = context(request), targets = await loadGrantTargets(ctx, deviceId, payeeId); request.mockClear();
    await expect(submitGrantCreation({...ctx, enabled: false}, targets, reason, '')).rejects.toThrow(/not enabled/);
    await expect(submitGrantCreation({...ctx, financialModel: 'canonical_evidence_ledger'}, targets, reason, '')).rejects.toThrow(/unavailable/);
    await expect(submitGrantCreation({...ctx, identity: {...ctx.identity, role: 'staff'}}, targets, reason, '')).rejects.toThrow(/unavailable/);
    await expect(submitGrantCreation({...ctx, identity: {...ctx.identity, permissions: ['gateway.manage']}}, targets, reason, '')).rejects.toThrow(/unavailable/);
    await expect(submitGrantCreation({...ctx, isCurrent: () => false}, targets, reason, '')).rejects.toThrow(/unavailable/);
    expect(request).not.toHaveBeenCalled();
  });
  it('retains the exact request before posting, validates the resulting grant and preserves an independent enrollment checkpoint', async () => {
    await retainPending(identity(), 'gateway-device-enrollment', 'new', otherKey, 'gateway.manage', {reason: 'Review enrollment'});
    const request = mockRequest(async options => {expect(await readPending(identity(), 'receiver-capture-grant', 'new')).toMatchObject({request_key: key, intent}); expect(options).toEqual({method: 'POST', body: intent, idempotencyKey: key}); return receipt;});
    const ctx = context(request), targets = await loadGrantTargets(ctx, deviceId, payeeId);
    const devices = await loadGrantDevices(ctx, 0), payees = await loadGrantPayees(ctx, 0, 'Synthetic'); verifyGrantSelection(targets, devices.rows[0], payees.rows[0]);
    expect(await submitGrantCreation(ctx, targets, reason, await ready(ctx))).toEqual({status: 'succeeded', receipt: {requestId: operationId, grantId, version: 1}});
    expect(await readPending(identity(), 'receiver-capture-grant', 'new')).toBeNull();
    expect(await readPending(identity(), 'gateway-device-enrollment', 'new')).toMatchObject({request_key: otherKey});
  });
  it('checks a lost response and retries the original key and exact intent after a fresh review', async () => {
    let attempts = 0; const request = mockRequest(async options => {attempts++; expect(options).toEqual({method: 'POST', body: intent, idempotencyKey: key}); if (attempts === 1) throw new Error('Lost response'); return receipt;});
    const ctx = context(request), targets = await loadGrantTargets(ctx, deviceId, payeeId);
    expect(await submitGrantCreation(ctx, targets, reason, await ready(ctx))).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreGrantCreation(ctx);
    expect(await lookupGrantCreation(ctx, pending)).toEqual({status: 'not_found', retryAvailable: true});
    const reviewed = await loadOriginalGrantTargets(ctx, pending);
    expect(await retryGrantCreation(ctx, pending, reviewed)).toEqual({status: 'succeeded', receipt: {requestId: operationId, grantId, version: 1}});
    expect(attempts).toBe(2); expect(await readPending(identity(), 'receiver-capture-grant', 'new')).toBeNull();
  });
  it('does not hold the shared checkpoint lock while a grant request is in flight', async () => {
    const held = new Set<string>();
    const lock: FenceLock = async (name, work) => {if (held.has(name)) throw new Error('Lock busy'); held.add(name); try {return await work();} finally {held.delete(name);}};
    let entered!: () => void, release!: (value: Record<string, unknown>) => void;
    const inFlight = new Promise<void>(resolve => {entered = resolve;});
    const request = mockRequest(() => {entered(); return new Promise(resolve => {release = resolve;});});
    const ctx = {...context(request), lock}, targets = await loadGrantTargets(ctx, deviceId, payeeId), observed = await ready(ctx);
    const operation = submitGrantCreation(ctx, targets, reason, observed); await inFlight;
    const enrollment = {identity: ctx.identity, family: 'gateway-device-enrollment', resourceId: 'new', isCurrent: () => true, storage: localStorage, lock};
    await withPendingFence(enrollment, async access => {access.reserve(otherKey, access.read().revision);});
    release(receipt); expect((await operation).status).toBe('succeeded');
    expect(await withPendingFence(enrollment, async access => access.read())).toMatchObject({kind: 'owned', requestKey: otherKey});
  });
  it('clears an original request only after its lookup and grant details agree', async () => {
    const request = mockRequest(async () => {throw new Error('Lost response');}), ctx = context(request), targets = await loadGrantTargets(ctx, deviceId, payeeId);
    await submitGrantCreation(ctx, targets, reason, await ready(ctx)); const pending = await restoreGrantCreation(ctx);
    const recovering: AdminRequest = async path => path === `gateway/receiver-requests/${key}` ? {found: true, receipt} : grantDetail;
    expect(await lookupGrantCreation({...ctx, request: recovering}, pending)).toEqual({status: 'succeeded', receipt: {requestId: operationId, grantId, version: 1}});
    expect(await readPending(identity(), 'receiver-capture-grant', 'new')).toBeNull();
  });
  it('never submits a changed device or receiver and retains a mismatching original receipt', async () => {
    const request = mockRequest(async () => {throw new Error('Lost response');}), ctx = context(request), targets = await loadGrantTargets(ctx, deviceId, payeeId);
    await submitGrantCreation(ctx, targets, reason, await ready(ctx)); const pending = await restoreGrantCreation(ctx);
    const oldDevice = deviceDetail; deviceDetail = {...deviceDetail, resource: {...deviceDetail.resource as object, version: 3}};
    await expect(retryGrantCreation(ctx, pending, targets)).rejects.toThrow(/device or receiver changed/); deviceDetail = oldDevice;
    const oldPayee = payeeDetail; payeeDetail = {...payeeDetail, resource: {...payeeDetail.resource as object, version: 4}};
    await expect(retryGrantCreation(ctx, pending, targets)).rejects.toThrow(/device or receiver changed/); payeeDetail = oldPayee;
    const mismatched = {...grantDetail, resource: {...grantDetail.resource as object, payee_id: groupId}};
    const lookupRequest: AdminRequest = async path => path === `gateway/receiver-requests/${key}` ? {found: true, receipt} : mismatched;
    await expect(lookupGrantCreation({...ctx, request: lookupRequest}, pending)).rejects.toThrow(/receipt could not be verified/);
    expect((await restoreGrantCreation(ctx)).kind).toBe('owned');
    expect(request.mock.calls.filter(([path]) => path === 'gateway/receiver-grants')).toHaveLength(1);
  });
  it('keeps the key without sending if the gate closes during retention', async () => {
    let enabled = true; const storage: Storage = {get length() {return sessionStorage.length;}, clear: () => sessionStorage.clear(), key: index => sessionStorage.key(index), getItem: name => sessionStorage.getItem(name), removeItem: name => sessionStorage.removeItem(name), setItem: (name, value) => {sessionStorage.setItem(name, value); enabled = false;}};
    const request = mockRequest(), ctx = {...context(request), storage, isEnabled: () => enabled}, targets = await loadGrantTargets(ctx, deviceId, payeeId);
    expect(await submitGrantCreation(ctx, targets, reason, await ready(ctx))).toEqual({status: 'unknown', requestKey: key});
    expect(await readPending(identity(), 'receiver-capture-grant', 'new')).toMatchObject({request_key: key});
    expect(request.mock.calls.some(([path]) => path === 'gateway/receiver-grants')).toBe(false);
  });
  it('does not retry when the local original intent is unavailable or authority changed', async () => {
    const request = mockRequest(async () => {throw new Error('Lost');}), ctx = context(request), targets = await loadGrantTargets(ctx, deviceId, payeeId);
    await submitGrantCreation(ctx, targets, reason, await ready(ctx));
    const other = {...ctx, identity: {...ctx.identity, sessionId: 'other-session'}}; expect(await restoreGrantCreation(other)).toEqual({kind: 'foreign'});
    const empty: Storage = {length: 0, clear() {}, getItem() {return null;}, key() {return null;}, removeItem() {}, setItem() {}};
    const crash = {...ctx, storage: empty}, pending = await restoreGrantCreation(crash);
    expect(pending).toEqual({kind: 'owned', requestKey: key, attempt: null});
    expect(await lookupGrantCreation(crash, pending)).toEqual({status: 'not_found', retryAvailable: false});
    await expect(retryGrantCreation(crash, pending, targets)).rejects.toThrow(/intent is unavailable/);
  });
});

describe('Receiver capture grant panel', () => {
  it('does not offer creation by default', async () => {
    render(<ReceiverGrantCreatePanel onUpdated={() => undefined} />);
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(screen.queryByRole('button', {name: 'Find active devices'})).not.toBeInTheDocument(); expect(mock.request).not.toHaveBeenCalled();
  });
  it('can check an original request with creation disabled without dispatching a retry', async () => {
    await retainPending(identity(), 'receiver-capture-grant', 'new', key, 'gateway.manage', intent);
    const user = userEvent.setup(), request = mockRequest(); mock.request.mockImplementation(request);
    render(<ReceiverGrantCreatePanel onUpdated={() => undefined} />);
    await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    expect(await screen.findByText('No receipt was found. Keep the original reference and check again before continuing.')).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Review identical retry'})).not.toBeInTheDocument();
    expect(request.mock.calls.some(([path]) => path === 'gateway/receiver-grants')).toBe(false);
  });
  it('shows the reviewed receiving scope and requires explicit confirmation before dispatch', async () => {
    const user = userEvent.setup(), updated = vi.fn(), request = mockRequest(); mock.request.mockImplementation(request);
    render(<ReceiverGrantCreatePanel enabled onUpdated={updated} />);
    await user.click(await screen.findByRole('button', {name: 'Find active devices'})); await user.selectOptions(await screen.findByLabelText('Active device'), deviceId);
    await user.click(screen.getByRole('button', {name: 'Find active receivers'})); await user.selectOptions(await screen.findByLabelText('Active receiver'), payeeId);
    await user.type(screen.getByLabelText('Capture access review reason'), reason); await user.click(screen.getByRole('button', {name: 'Review capture grant'}));
    expect(await screen.findByText(groupId)).toBeVisible(); expect(screen.getByText('123456')).toBeVisible();
    expect(screen.getByRole('button', {name: 'Confirm capture grant'})).toBeDisabled();
    expect(request.mock.calls.some(([path]) => path === 'gateway/receiver-grants')).toBe(false);
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the device, receiver and capture access.'})); await user.click(screen.getByRole('button', {name: 'Confirm capture grant'}));
    expect(await screen.findByText(`Capture grant recorded. Request ${operationId}.`)).toBeVisible(); expect(updated).toHaveBeenCalledOnce();
  });
});
