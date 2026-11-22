import {fireEvent, render, screen} from '@testing-library/react';
import {afterEach, describe, expect, it, vi} from 'vitest';
import {SessionProvider} from '../../src/session/SessionProvider';
import {SmsControlsPage} from '../../src/features/assisted/SmsControlsPage';
import {parseSmsMaterializationStatus} from '../../src/features/assisted/smsMaterializationStatus';

const actor = '11111111-1111-4111-8111-111111111111', principal = '22222222-2222-4222-8222-222222222222', session = '33333333-3333-4333-8333-333333333333';
const requestId = '44444444-4444-4444-8444-444444444444', group = '55555555-5555-4555-8555-555555555555', entry1 = '66666666-6666-4666-8666-666666666666';
const entry2 = '77777777-7777-4777-8777-777777777777', payment1 = '88888888-8888-4888-8888-888888888888', payment2 = '99999999-9999-4999-8999-999999999999';
const job = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', origin = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', time = '2026-10-18T12:34:56.000Z';
const marker = {contract_version: 1, legal_release_approved: false, provider_approved: false, delivery_confirmed: false};
const jobReceipt = {contract_version: 1, scope: 'assisted_sms_internal_record', delivery_confirmed: false, provider_confirmation: false, settlement_status: 'not_asserted', job_id: job, payment_id: payment1, state: 'queued', body_sha256: 'a'.repeat(64)};
const status = {ok: true, result: {...marker, scope: 'bounded_receipt_sms_materialization', request_id: requestId, observed: true, collection_id: group, source_identity: 'immutable_contribution_entry_id',
  originating_session_id: origin, public_session_id: session, recorded_at: time, status: 'partial_blocked', planned_count: 2,
  items: [{entry_id: entry1, payment_id: payment1, status: 'committed', receipt: jobReceipt}, {entry_id: entry2, payment_id: payment2, status: 'blocked', code: 'source_already_queued'}],
  materialized_jobs: [jobReceipt], materialized_count: 1, blocked: {source_entry_id: entry2, code: 'source_already_queued'}, has_more_observed: true, may_be_in_flight: false,
  recorded_state_only: true, may_send: false, transport_started: false, all_source_events_complete: false}};
const missing = {ok: true, result: {...marker, scope: 'bounded_receipt_sms_materialization', request_id: requestId, observed: false, status: 'not_recorded', may_be_in_flight: true,
  planned_count: null, items: [], materialized_jobs: [], materialized_count: 0, blocked: null, recorded_state_only: true, may_send: false, transport_started: false, all_source_events_complete: false}};
const access = {ok: true, result: {...marker, scope: 'owner_receipt_sms_access', current_admin_id: actor, current_principal_id: principal, decision_revision: 1, read_granted: true, manage_granted: true, can_operate: true, permissions: ['assisted_sms.read', 'assisted_sms.manage']}};
const history = {ok: true, result: {...marker, scope: 'own_receipt_sms_request_history', original_session_only: true, recorded_state_only: true, may_send: false, replay_authorized: false, next_cursor: null,
  items: [{request_id: requestId, kind: 'materialization', recorded_at: time, recorded_outcome: 'plan_recorded', status_path: `/api/admin/notification-operator/materialize/${requestId}`, recorded_state_only: true, may_send: false}]}};
const owner = {id: actor, email: 'info@ikanisa.com', role: 'owner', sessionId: session, principalId: principal, permissions: ['admin_users.manage', 'assisted_sms.manage'], assuranceLevel: 2, mfaAt: new Date().toISOString(), financialModel: 'canonical_evidence_ledger'};
const expiresAt = new Date(Date.now() + 3_600_000).toISOString();
const reply = (body: unknown) => new Response(JSON.stringify(body), {status: 200, headers: {'Content-Type': 'application/json'}});
afterEach(() => {vi.restoreAllMocks(); sessionStorage.clear();});

describe('read-only bounded job preparation status', () => {
  it('distinguishes missing, committed and blocked source evidence', () => {
    expect(parseSmsMaterializationStatus(missing, requestId, session)).toMatchObject({observed: false, status: 'not_recorded', mayBeInFlight: true, items: []});
    expect(parseSmsMaterializationStatus(status, requestId, session)).toMatchObject({observed: true, status: 'partial_blocked', plannedCount: 2, materializedCount: 1, hasMore: true,
      items: [{entryId: entry1, paymentId: payment1, status: 'committed', jobId: job}, {entryId: entry2, paymentId: payment2, status: 'blocked', code: 'source_already_queued'}]});
  });
  it('preserves an unknown source as unknown rather than implying failure or retry authority', () => {
    const unknown = {ok: true, result: {...status.result, status: 'unknown', planned_count: 1, items: [{entry_id: entry1, payment_id: payment1, status: 'unknown', code: 'enqueue_not_observed', resume_safe: true}],
      materialized_jobs: [], materialized_count: 0, blocked: null, may_be_in_flight: true}};
    expect(parseSmsMaterializationStatus(unknown, requestId, session)).toMatchObject({status: 'unknown', mayBeInFlight: true, materializedCount: 0});
  });
  it('rejects another session, sending or provider claims, mismatched receipts and false completion', () => {
    expect(() => parseSmsMaterializationStatus(status, requestId, origin)).toThrow();
    expect(() => parseSmsMaterializationStatus({ok: true, result: {...status.result, transport_started: true}}, requestId, session)).toThrow();
    expect(() => parseSmsMaterializationStatus({ok: true, result: {...status.result, provider_approved: true}}, requestId, session)).toThrow();
    expect(() => parseSmsMaterializationStatus({ok: true, result: {...status.result, all_source_events_complete: true}}, requestId, session)).toThrow();
    expect(() => parseSmsMaterializationStatus({ok: true, result: {...status.result, materialized_jobs: [{...jobReceipt, job_id: group}]}}, requestId, session)).toThrow();
    expect(() => parseSmsMaterializationStatus({ok: true, result: {...status.result, status: 'bounded_pass'}}, requestId, session)).toThrow();
    expect(() => parseSmsMaterializationStatus({ok: true, result: {...missing.result, observed: false, may_be_in_flight: false}}, requestId, session)).toThrow();
  });
  it('opens only an authenticated, original-session history status via GET', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url); if (path.endsWith('/auth/session')) return reply({user: owner, expiresAt});
      expect(init?.method).toBe('GET');
      if (path.endsWith('/notification-operator/access')) return reply(access);
      if (path.includes('/notification-operator/operations?')) return reply(history);
      if (path.endsWith(`/notification-operator/materialize/${requestId}`)) return reply(status);
      throw new Error('Unexpected request');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} /></SessionProvider>);
    fireEvent.click(await screen.findByRole('button', {name: 'View recorded status'}));
    expect(await screen.findByRole('heading', {name: 'Recorded job preparation status'})).toBeInTheDocument();
    expect(screen.getByText(/Recorded jobs: 1/)).toBeInTheDocument(); expect(screen.getByText('source_already_queued')).toBeInTheDocument();
    expect(screen.getByText(/does not authorize a retry or sending/i)).toBeInTheDocument();
    expect(fetchImpl.mock.calls.every(([, init]) => init?.method === 'GET')).toBe(true);
  });
  it('does not fetch materialization status when the management grant is absent', async () => {
    const disabledAccess = {ok: true, result: {...access.result, read_granted: false, manage_granted: false, can_operate: false}};
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const path = String(url); if (path.endsWith('/auth/session')) return reply({user: {...owner, permissions: ['admin_users.manage']}, expiresAt});
      expect(init?.method).toBe('GET'); if (path.endsWith('/notification-operator/access')) return reply(disabledAccess); if (path.includes('/notification-operator/operations?')) return reply(history);
      throw new Error('Unexpected request');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><SmsControlsPage onVerify={() => undefined} /></SessionProvider>);
    expect(await screen.findByText(requestId)).toBeInTheDocument(); expect(screen.queryByRole('button', {name: 'View recorded status'})).not.toBeInTheDocument();
    expect(fetchImpl.mock.calls.some(([url]) => String(url).includes(`/notification-operator/materialize/${requestId}`))).toBe(false);
  });
});
