import {createHash, webcrypto} from 'node:crypto';
import {fireEvent, render, screen, waitFor, within} from '@testing-library/react';
import {afterEach, describe, expect, it, vi} from 'vitest';
import {parseSmsAccess, parseSmsDecision, parseSmsHistory, parseSmsPolicy, SmsControlsPage} from '../../src/features/assisted/SmsControlsPage';
import {SessionProvider, useSession} from '../../src/session/SessionProvider';

const ownerId = 'cdd3c1c0-c124-4c8a-9719-bd2435d198d1', principalId = '53c51330-f311-4519-977b-30f67b47c1f1', sessionId = '0f689afa-5a45-4fb5-a147-9aff36f137dd', groupId = '6ea1b44a-25b7-4f2a-9d20-5829675211bc', requestId = 'fa1e3f37-1e2b-4e57-9d7d-77f0c13d0d50';
const marker = {contract_version: 1, legal_release_approved: false, provider_approved: false, delivery_confirmed: false};
const access = {ok: true, result: {...marker, scope: 'owner_receipt_sms_access', current_admin_id: ownerId, current_principal_id: principalId, decision_revision: 2, read_granted: true, manage_granted: true, can_operate: true, permissions: ['assisted_sms.read', 'assisted_sms.manage']}};
const policy = {ok: true, result: {...marker, scope: 'owner_receipt_sms_configuration', collection_id: groupId, configured: true, enabled: false, revision: 1, template_key: 'collect.recorded_contribution.v1', recorded_owner_decision_sha256: 'a'.repeat(64), recorded_at: '2026-10-18T12:34:56.000Z', collection_active: true}};
const item = {request_id: requestId, kind: 'access', recorded_at: '2026-10-18T12:34:56.000Z', recorded_outcome: 'decision_recorded', status_path: `/api/admin/notification-operator/access/operations/${requestId}`, recorded_state_only: true, may_send: false};
const history = {ok: true, result: {...marker, scope: 'own_receipt_sms_request_history', items: [item], next_cursor: null, original_session_only: true, recorded_state_only: true, may_send: false, replay_authorized: false}};
const stableHash = (value: Record<string, unknown>) => createHash('sha256').update(JSON.stringify(Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b))))).digest('hex');
const accessDecision = {kind: 'authenticated_owner_receipt_sms_access', request_id: requestId, grant_transaction_id: groupId, current_admin_id: ownerId, current_principal_id: principalId, decision_revision: 2, originating_session_id: groupId, public_session_id: sessionId, enabled: true, permissions: ['assisted_sms.read', 'assisted_sms.manage'], recorded_at: item.recorded_at};
const accessReceipt = {...marker, scope: 'owner_receipt_sms_access', ...accessDecision, read_granted: true, manage_granted: true, can_operate: true, decision_sha256: stableHash(accessDecision), recorded_state_only: true, replay: false};
const accessStatus = {ok: true, result: {...marker, scope: 'owner_receipt_sms_access_operation', request_id: requestId, observed: true, status: 'recorded', may_be_in_flight: false, recorded_decision: accessReceipt, current_access: access.result, recorded_state_only: true, may_send: false, replay_authorized: false}};
const policyDecision = {kind: 'authenticated_owner_receipt_sms_policy', request_id: requestId, collection_id: groupId, revision: 2, enabled: false, template_key: 'collect.recorded_contribution.v1', owner_user_id: principalId, originating_session_id: groupId, public_session_id: sessionId, recorded_at: item.recorded_at, legal_release_approved: false, provider_approved: false};
const policyReceipt = {...marker, scope: 'owner_receipt_sms_configuration', ...policyDecision, recorded_owner_decision_sha256: stableHash(policyDecision)};
const policyStatus = {ok: true, result: {...marker, scope: 'owner_receipt_sms_policy_operation', request_id: requestId, observed: true, status: 'recorded', may_be_in_flight: false, recorded_decision: policyReceipt, recorded_state_only: true, may_send: false, replay_authorized: false}};
const reply = (body: unknown) => new Response(JSON.stringify(body), {status: 200, headers: {'Content-Type': 'application/json'}});
const expiresAt = new Date(Date.now() + 3_600_000).toISOString();
const owner = {id: ownerId, email: 'info@ikanisa.com', role: 'owner', sessionId, principalId, permissions: ['admin_users.manage', 'assisted_sms.manage'], assuranceLevel: 2, mfaAt: new Date().toISOString(), financialModel: 'canonical_evidence_ledger'};
afterEach(() => {vi.unstubAllGlobals(); sessionStorage.clear();});

describe('owner receipt SMS contracts', () => {
  it('validates actor identity, exact capability definitions, and actual current grants', () => {
    expect(parseSmsAccess(access, ownerId, principalId)).toMatchObject({revision: 2, canOperate: true});
    expect(() => parseSmsAccess(access, groupId, principalId)).toThrow();
    expect(() => parseSmsAccess({ok: true, result: {...access.result, can_operate: false}}, ownerId, principalId)).toThrow();
    expect(() => parseSmsAccess({ok: true, result: {...access.result, provider_approved: true}}, ownerId, principalId)).toThrow();
  });
  it('rejects another group, inconsistent policy metadata, and malformed history claims', () => {
    expect(parseSmsPolicy(policy, groupId)).toMatchObject({enabled: false, configured: true});
    expect(() => parseSmsPolicy(policy, ownerId)).toThrow();
    expect(() => parseSmsPolicy({ok: true, result: {...policy.result, revision: 0}}, groupId)).toThrow();
    expect(() => parseSmsHistory({ok: true, result: {...history.result, may_send: true}})).toThrow();
    expect(() => parseSmsHistory({ok: true, result: {...history.result, items: [{...item, status_path: 'https://example.invalid'}]}})).toThrow();
    expect(() => parseSmsHistory({ok: true, result: {...history.result, items: [item, item]}})).toThrow();
    expect(() => parseSmsHistory({ok: true, result: {...history.result, next_cursor: {after_created_at: item.recorded_at, after_request_id: groupId}}}, null, 1)).toThrow();
    expect(parseSmsHistory({ok: true, result: {...history.result, next_cursor: {after_created_at: item.recorded_at, after_request_id: requestId}}}, null, 1)).toMatchObject({next: {after_request_id: requestId}});
  });
  it('verifies recorded decision hashes and binds each receipt to the actor and original session', async () => {
    vi.stubGlobal('crypto', webcrypto);
    await expect(parseSmsDecision(accessStatus, 'access', requestId, ownerId, principalId, sessionId)).resolves.toMatchObject({observed: true, decision: {enabled: true, revision: 2}, currentAccess: {revision: 2}});
    await expect(parseSmsDecision(policyStatus, 'policy', requestId, ownerId, principalId, sessionId)).resolves.toMatchObject({decision: {collectionId: groupId, revision: 2}});
    await expect(parseSmsDecision({ok: true, result: {...policyStatus.result, recorded_decision: {...policyReceipt, enabled: true}}}, 'policy', requestId, ownerId, principalId, sessionId)).rejects.toThrow();
    await expect(parseSmsDecision(accessStatus, 'access', requestId, ownerId, principalId, groupId)).rejects.toThrow();
  });
});

describe('owner SMS controls', () => {
  it('shows only current access, selected group policy and original-session history through GET reads', async () => {
    vi.stubGlobal('crypto', webcrypto);
    let visibility: DocumentVisibilityState = 'visible';
    vi.spyOn(document, 'visibilityState', 'get').mockImplementation(() => visibility);
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: owner, expiresAt});
      expect(init?.method).toBe('GET');
      if (path.endsWith('/notification-operator/access')) return reply(access);
      if (path.endsWith(`/notification-operator/access/operations/${requestId}`)) return reply(accessStatus);
      if (path.includes('/notification-operator/operations?')) return reply(history);
      if (path.endsWith(`/notification-operator/policies/${groupId}`)) return reply(policy);
      throw new Error('Unexpected endpoint');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} /></SessionProvider>);
    expect(await screen.findByText('Operator access available')).toBeInTheDocument();
    expect(await screen.findByText(requestId)).toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Remove my SMS access'})).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', {name: 'View recorded status'}));
    expect(await screen.findByText('Recorded request status')).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('Group UUID'), {target: {value: groupId}});
    fireEvent.click(screen.getByRole('button', {name: 'View policy'}));
    expect(await screen.findByText(/Policy: Disabled/)).toBeInTheDocument();
    expect(screen.queryByRole('button', {name: /enable|disable|prepare|send|replay/i})).not.toBeInTheDocument();
    expect(fetchImpl.mock.calls.every(([, init]) => init?.method === 'GET')).toBe(true);
    const calls = fetchImpl.mock.calls.length;
    visibility = 'hidden'; fireEvent(document, new Event('visibilitychange'));
    expect(screen.queryByText('Operator access available')).not.toBeInTheDocument();
    visibility = 'visible'; fireEvent(document, new Event('visibilitychange'));
    await waitFor(() => expect(fetchImpl.mock.calls.length).toBeGreaterThan(calls));
    expect(await screen.findByText('Operator access available')).toBeInTheDocument();
  });

  it('allows current-access and history reads after owner self-disable without exposing policy reads', async () => {
    const disabledAccess = {ok: true, result: {...access.result, read_granted: false, manage_granted: false, can_operate: false}};
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: {...owner, permissions: ['admin_users.manage']}, expiresAt});
      if (path.endsWith('/notification-operator/access')) return reply(disabledAccess);
      if (path.includes('/notification-operator/operations?')) return reply(history);
      throw new Error('Unexpected endpoint');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} /></SessionProvider>);
    expect(await screen.findByText('Operator access unavailable')).toBeInTheDocument();
    expect(screen.getByText('Current access does not include permission to view group policy.')).toBeInTheDocument();
    expect(screen.queryByLabelText('Group UUID')).not.toBeInTheDocument();
    expect(fetchImpl.mock.calls.some(([url]) => String(url).includes('/notification-operator/policies/'))).toBe(false);
  });

  it('keeps policy changes unavailable by default even when the current policy is enabled', async () => {
    const enabled = {ok: true, result: {...policy.result, enabled: true}};
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: owner, expiresAt});
      if (path.endsWith('/notification-operator/access')) return reply(access);
      if (path.includes('/notification-operator/operations?')) return reply(history);
      if (path.endsWith(`/notification-operator/policies/${groupId}`)) return reply(enabled);
      throw new Error('Unexpected endpoint');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} /></SessionProvider>);
    fireEvent.change(await screen.findByLabelText('Group UUID'), {target: {value: groupId}});
    fireEvent.click(screen.getByRole('button', {name: 'View policy'}));
    expect(await screen.findByText(/Policy: Enabled/)).toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Disable current group policy'})).not.toBeInTheDocument();
  });

  it('keeps policy enablement separately disabled until explicitly activated', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url); if (path.endsWith('/auth/session')) return reply({user: owner, expiresAt});
      expect(init?.method).toBe('GET'); if (path.endsWith('/notification-operator/access')) return reply(access);
      if (path.includes('/notification-operator/operations?')) return reply(history); if (path.endsWith(`/notification-operator/policies/${groupId}`)) return reply(policy);
      throw new Error('Unexpected endpoint');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} allowPolicyChanges /></SessionProvider>);
    fireEvent.change(await screen.findByLabelText('Group UUID'), {target: {value: groupId}}); fireEvent.click(screen.getByRole('button', {name: 'View policy'}));
    expect(await screen.findByText(/Policy: Disabled/)).toBeInTheDocument(); expect(screen.queryByRole('button', {name: 'Enable receipt SMS policy'})).not.toBeInTheDocument();
    expect(fetchImpl.mock.calls.every(([, init]) => init?.method === 'GET')).toBe(true);
  });
  it('requires a group-specific owner confirmation before the qualified enable request', async () => {
    vi.stubGlobal('crypto', webcrypto); let enabled = false; const posts: Record<string, unknown>[] = [];
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url); if (path.endsWith('/auth/session')) return reply({user: owner, expiresAt});
      if (path.endsWith('/notification-operator/access')) return reply(access); if (path.includes('/notification-operator/operations?')) return reply(history);
      if (path.endsWith(`/notification-operator/policies/${groupId}`) && init?.method === 'GET') return reply({ok: true, result: {...policy.result, enabled, revision: enabled ? 2 : 1}});
      if (path.endsWith(`/notification-operator/policies/${groupId}`) && init?.method === 'POST') {
        const body = JSON.parse(String(init.body)) as Record<string, unknown>; posts.push(body); expect(body).toMatchObject({expected_revision: 1, enabled: true, owner_confirmation: true});
        const saved = JSON.parse(sessionStorage.getItem(`collect.admin.notification-management.${ownerId}.${sessionId}.${principalId}.collect.admin.pending-attempts.v1`)!).entries[0];
        expect(saved.request_key).toBe(body.request_id); enabled = true; const decision = {...policyDecision, request_id: body.request_id, revision: 2, enabled: true};
        return reply({ok: true, result: {...marker, scope: 'owner_receipt_sms_configuration', ...decision, recorded_owner_decision_sha256: stableHash(decision)}});
      }
      throw new Error('Unexpected endpoint');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} allowPolicyChanges allowPolicyEnabling /></SessionProvider>);
    fireEvent.change(await screen.findByLabelText('Group UUID'), {target: {value: groupId}}); fireEvent.click(screen.getByRole('button', {name: 'View policy'}));
    fireEvent.click(await screen.findByRole('button', {name: 'Enable receipt SMS policy'}));
    const dialog = screen.getByRole('dialog', {name: 'Enable group policy?'}), submit = within(dialog).getByRole('button', {name: 'Enable policy'});
    expect(submit).toBeDisabled(); expect(posts).toHaveLength(0); fireEvent.click(within(dialog).getByLabelText('I confirm enabling policy for this group and revision.')); fireEvent.click(submit);
    expect(await screen.findByText('The policy decision was recorded. Review the current policy after refresh.')).toBeInTheDocument(); expect(posts).toHaveLength(1);
  });
  it('requires confirmation and an original lookup before a same-key policy retry', async () => {
    vi.stubGlobal('crypto', webcrypto);
    sessionStorage.clear();
    const submitted: Record<string, unknown>[] = [];
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: owner, expiresAt});
      if (path.endsWith('/notification-operator/access')) return reply(access);
      if (path.includes('/notification-operator/operations?')) return reply(history);
      if (path.endsWith(`/notification-operator/policies/${groupId}`) && init?.method === 'GET') return reply({ok: true, result: {...policy.result, enabled: submitted.length < 2, revision: submitted.length < 2 ? 3 : 4}});
      if (path.includes('/notification-operator/policies/operations/')) return reply({ok: true, result: {...marker, scope: 'owner_receipt_sms_policy_operation', request_id: path.split('/').at(-1), observed: false, status: 'not_recorded', may_be_in_flight: true, recorded_decision: null, recorded_state_only: true, may_send: false, replay_authorized: false}});
      if (path.endsWith(`/notification-operator/policies/${groupId}`) && init?.method === 'POST') {
        const body = JSON.parse(String(init.body)) as Record<string, unknown>; submitted.push(body);
        if (submitted.length === 1) throw new TypeError('connection lost');
        const decision = {...policyDecision, request_id: body.request_id, revision: 4};
        return reply({ok: true, result: {...marker, scope: 'owner_receipt_sms_configuration', ...decision, recorded_owner_decision_sha256: stableHash(decision)}});
      }
      throw new Error('Unexpected endpoint');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} allowPolicyChanges /></SessionProvider>);
    fireEvent.change(await screen.findByLabelText('Group UUID'), {target: {value: groupId}});
    fireEvent.click(screen.getByRole('button', {name: 'View policy'}));
    fireEvent.click(await screen.findByRole('button', {name: 'Disable current group policy'}));
    const confirm = screen.getByRole('dialog', {name: 'Disable group policy?'});
    expect(submitted).toHaveLength(0);
    fireEvent.click(within(confirm).getByRole('button', {name: 'Disable policy'}));
    expect(await screen.findByText(/policy change is not confirmed/i)).toBeInTheDocument();
    expect(submitted).toHaveLength(1);
    fireEvent.click(screen.getByRole('button', {name: 'Check original request'}));
    fireEvent.click(await screen.findByRole('button', {name: 'Retry same request'}));
    const retry = screen.getByRole('dialog', {name: 'Retry original policy request?'});
    expect(submitted).toHaveLength(1);
    fireEvent.click(within(retry).getByRole('button', {name: 'Retry same request'}));
    await waitFor(() => expect(submitted).toHaveLength(2));
    expect(submitted[1]).toEqual(submitted[0]);
    expect(await screen.findByText('The original policy decision was recorded. Review the current policy after refresh.')).toBeInTheDocument();
  });

  it('requires explicit owner confirmation, then refreshes the session after granting access', async () => {
    vi.stubGlobal('crypto', webcrypto);
    let granted = false, head = 3;
    const posts: Record<string, unknown>[] = [];
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: {...owner, permissions: granted ? ['admin_users.manage', 'assisted_sms.read', 'assisted_sms.manage'] : ['admin_users.manage']}, expiresAt});
      if (path.endsWith('/notification-operator/access') && init?.method === 'GET') return reply({ok: true, result: {...access.result, decision_revision: head, read_granted: granted, manage_granted: granted, can_operate: granted}});
      if (path.endsWith('/notification-operator/access') && init?.method === 'POST') {
        const body = JSON.parse(String(init.body)) as Record<string, unknown>; posts.push(body);
        const saved = JSON.parse(sessionStorage.getItem(`collect.admin.notification-management.${ownerId}.${sessionId}.${principalId}.collect.admin.pending-attempts.v1`)!).entries[0];
        expect(saved.request_key).toBe(body.request_id);
        expect(body).toMatchObject({expected_read: false, expected_manage: false, expected_decision_revision: 3, enabled: true, owner_confirmation: true});
        granted = true; head = 4;
        const decision = {...accessDecision, request_id: body.request_id, decision_revision: 4, enabled: true};
        return reply({ok: true, result: {...marker, scope: 'owner_receipt_sms_access', ...decision, read_granted: true, manage_granted: true, can_operate: true, decision_sha256: stableHash(decision), recorded_state_only: true, replay: false}});
      }
      if (path.includes('/notification-operator/operations?')) return reply(history);
      throw new Error('Unexpected endpoint');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} allowAccessChanges /></SessionProvider>);
    fireEvent.click(await screen.findByRole('button', {name: 'Enable my SMS access'}));
    const dialog = screen.getByRole('dialog', {name: 'Enable my SMS access?'}), submit = within(dialog).getByRole('button', {name: 'Enable access'});
    expect(submit).toBeDisabled(); expect(posts).toHaveLength(0);
    fireEvent.click(within(dialog).getByLabelText('I confirm access for my current account.'));
    fireEvent.click(submit);
    expect(await screen.findByText('Operator access available')).toBeInTheDocument();
    expect(posts).toHaveLength(1);
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/auth/session')).length).toBeGreaterThan(1);
  });

  it('recovers an uncertain self-removal after grants change and refreshes the actual session', async () => {
    vi.stubGlobal('crypto', webcrypto);
    let granted = true, head = 3, writes = 0;
    const makeReceipt = (id: string) => {
      const decision = {...accessDecision, request_id: id, decision_revision: 4, enabled: false};
      return {...marker, scope: 'owner_receipt_sms_access', ...decision, read_granted: false, manage_granted: false, can_operate: false, decision_sha256: stableHash(decision), recorded_state_only: true, replay: false};
    };
    const makeCurrent = () => ({...access.result, decision_revision: head, read_granted: granted, manage_granted: granted, can_operate: granted});
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: {...owner, permissions: granted ? ['admin_users.manage', 'assisted_sms.read', 'assisted_sms.manage'] : ['admin_users.manage']}, expiresAt});
      if (path.endsWith('/notification-operator/access') && init?.method === 'GET') return reply({ok: true, result: makeCurrent()});
      if (path.endsWith('/notification-operator/access') && init?.method === 'POST') {writes++; granted = false; head = 4; throw new TypeError('connection lost');}
      if (path.includes('/notification-operator/access/operations/')) {
        const id = path.split('/').at(-1)!;
        return reply({ok: true, result: {...marker, scope: 'owner_receipt_sms_access_operation', request_id: id, observed: true, status: 'recorded', may_be_in_flight: false, recorded_decision: makeReceipt(id), current_access: makeCurrent(), recorded_state_only: true, may_send: false, replay_authorized: false}});
      }
      if (path.includes('/notification-operator/operations?')) return reply(history);
      throw new Error('Unexpected endpoint');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} allowAccessChanges /></SessionProvider>);
    fireEvent.click(await screen.findByRole('button', {name: 'Remove my SMS access'}));
    const dialog = screen.getByRole('dialog', {name: 'Remove my SMS access?'});
    fireEvent.click(within(dialog).getByRole('button', {name: 'Remove access'}));
    expect(await screen.findByText(/access change is not confirmed/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', {name: 'Check original request'}));
    expect(await screen.findByText('Operator access unavailable')).toBeInTheDocument();
    expect(screen.getByText('Current access does not include permission to view group policy.')).toBeInTheDocument();
    expect(writes).toBe(1);
    expect(sessionStorage.getItem(`collect.admin.notification-management.${ownerId}.${sessionId}.${principalId}.collect.admin.pending-attempts.v1`)).toBeNull();
  });

  it('requires the actual owner and fresh verification before reading', async () => {
    let account: Omit<typeof owner, 'mfaAt'> & {mfaAt: string | null} = {...owner, role: 'staff'};
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply({user: account, expiresAt});
      throw new Error('Unexpected endpoint');
    });
    const first = render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} /></SessionProvider>);
    expect(await screen.findByText('This page requires current owner access.')).toBeInTheDocument();
    await waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(1)); first.unmount();
    account = {...owner, assuranceLevel: 1, mfaAt: null};
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} /></SessionProvider>);
    expect(await screen.findByRole('button', {name: 'Verify authenticator'})).toBeInTheDocument();
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('fences a delayed result when the account changes', async () => {
    let changed = false, finish!: (value: Response) => void;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const path = String(url);
      if (path.endsWith('/auth/session')) return reply({user: changed ? {...owner, role: 'staff', permissions: []} : owner, expiresAt});
      if (path.endsWith('/notification-operator/access')) return new Promise<Response>((resolve) => {finish = resolve;});
      throw new Error('Unexpected endpoint');
    });
    function Harness() {const session = useSession(); return <><button onClick={() => {void session.refresh();}}>Refresh account</button><SmsControlsPage onVerify={() => undefined} /></>;}
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><Harness /></SessionProvider>);
    await waitFor(() => expect(fetchImpl.mock.calls.some(([url]) => String(url).endsWith('/notification-operator/access'))).toBe(true));
    changed = true; fireEvent.click(screen.getByRole('button', {name: 'Refresh account'}));
    await screen.findByText('This page requires current owner access.');
    finish(reply(access));
    await waitFor(() => expect(screen.queryByText('Operator access available')).not.toBeInTheDocument());
    expect(fetchImpl.mock.calls.some(([url]) => String(url).includes('/notification-operator/operations?'))).toBe(false);
  });
});
