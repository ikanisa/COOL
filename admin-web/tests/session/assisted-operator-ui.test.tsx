import {createHash, webcrypto} from 'node:crypto';
import {fireEvent, render, screen, waitFor, within} from '@testing-library/react';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {AssistedSmsPage} from '../../src/features/assisted/AssistedSmsPage';
import type {AssistedSmsSender} from '../../src/features/assisted/operatorWorkflow';
import {SessionProvider} from '../../src/session/SessionProvider';

const actorId = 'cdd3c1c0-c124-4c8a-9719-bd2435d198d1', principalId = '53c51330-f311-4519-977b-30f67b47c1f1', sessionId = '0f689afa-5a45-4fb5-a147-9aff36f137dd', jobId = '6ea1b44a-25b7-4f2a-9d20-5829675211bc', paymentId = 'fa1e3f37-1e2b-4e57-9d7d-77f0c13d0d50', claimId = '0d7bfc80-d88c-4b4c-9f7d-9935f6c5aaf1', attemptId = '1cb27c41-c93b-4efe-bd7b-a8a52fd81239';
const marker = {contract_version: 1, scope: 'assisted_sms_internal_record', delivery_confirmed: false, provider_confirmation: false, settlement_status: 'not_asserted'};
const message = 'Synthetic recorded contribution.', destination = '+250788123456', digest = (value: string) => createHash('sha256').update(value).digest('hex');
const reply = (body: unknown) => new Response(JSON.stringify(body), {status: 200, headers: {'Content-Type': 'application/json'}});
beforeEach(() => {vi.stubGlobal('crypto', webcrypto); sessionStorage.clear();});
afterEach(() => {sessionStorage.clear(); vi.unstubAllGlobals();});

function fixture(lostClaim = false) {
  const expiresAt = new Date(Date.now() + 3_600_000).toISOString(), claimExpiry = new Date(Date.now() + 120_000).toISOString(), receipts = new Map<string, Record<string, unknown>>(), actions: string[] = [];
  const account = {id: actorId, email: 'a@example.com', role: 'staff', sessionId, principalId, permissions: ['assisted_sms.read', 'assisted_sms.manage'], assuranceLevel: 2, mfaAt: new Date().toISOString(), financialModel: 'canonical_evidence_ledger'};
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith('/auth/session')) return reply({user: account, expiresAt});
    if (!String(url).endsWith('/notification-operator')) throw new Error('Unexpected endpoint');
    const body = JSON.parse(String(init?.body)) as Record<string, unknown>, action = String(body.action); actions.push(action);
    if (action === 'list_pending') return reply({ok: true, result: {...marker, items: [{id: jobId, payment_id: paymentId, state: 'queued', fence: 0, attempt_id: null, created_at: '2026-10-18T12:34:56.000Z'}], next_cursor: null}});
    if (action === 'claim') {
      const value = {...marker, job_id: jobId, claim_token: claimId, fence_version: 1, worker_id: body.worker_id, claim_expires_at: claimExpiry, originating_session_id: principalId, public_session_id: sessionId}; receipts.set(String(body.request_id), value);
      if (lostClaim) throw new TypeError('connection lost');
      return reply({ok: true, result: value});
    }
    if (action === 'get_claimed') return reply({ok: true, result: {...marker, job_id: jobId, claim_token: claimId, fence_version: 1, destination_e164: destination, destination_sha256: digest(destination), destination_revision: 2, message_body: message, body_sha256: digest(message), payment_id: paymentId, template_key: 'collect.recorded_contribution.v1', claim_expires_at: claimExpiry}});
    if (action === 'confirm') {const value = {...marker, job_id: jobId, confirmation_id: body.confirmation_id, claim_token: claimId, fence_version: 1, body_sha256: digest(message), destination_sha256: digest(destination), destination_revision: 2, expires_at: claimExpiry, originating_session_id: principalId, public_session_id: sessionId}; receipts.set(String(body.request_id), value); return reply({ok: true, result: value});}
    if (action === 'record_send_start') {const value = {...marker, attempt_id: attemptId, job_id: jobId, confirmation_id: body.confirmation_id, claim_token: claimId, fence_version: 1, state: 'send_started', originating_session_id: principalId, public_session_id: sessionId}; receipts.set(String(body.request_id), value); return reply({ok: true, result: {...value, replay: false, may_send: true, acknowledgement: 'first_committed_response_only'}});}
    if (action === 'record_outcome') return reply({ok: true, result: {...marker, attempt_id: attemptId, observation: body.observation, evidence_reference_sha256: body.evidence_reference_sha256, may_send: false}});
    if (action === 'release_claim') return reply({ok: true, result: {...marker, job_id: jobId, state: 'queued', fence_version: 2}});
    if (action === 'get_operation') {const receipt = receipts.get(String(body.request_id)) ?? null; return reply({ok: true, result: {...marker, request_id: body.request_id, observed: receipt !== null, receipt, may_send: false}});}
    throw new Error('Unexpected action');
  });
  return {fetchImpl, actions, receipts};
}
function mount(fetchImpl: typeof fetch, allowWrites = false, sender?: AssistedSmsSender) {
  return render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><AssistedSmsPage onVerify={() => undefined} {...(allowWrites ? {allowWrites: true} : {})} sender={sender} /></SessionProvider>);
}
async function claimAndReview() {
  fireEvent.click(await screen.findByRole('button', {name: 'Claim for review'}));
  const dialog = screen.getByRole('dialog', {name: 'Claim this SMS job?'});
  fireEvent.click(within(dialog).getByRole('button', {name: 'Claim job'}));
  fireEvent.click(await screen.findByRole('button', {name: 'Load exact content'}));
  expect(await screen.findByText(/Synthetic recorded contribution/)).toBeInTheDocument();
  fireEvent.click(screen.getByLabelText('I checked this exact recipient and message.'));
  fireEvent.click(screen.getByRole('button', {name: 'Confirm exact content'}));
  expect(await screen.findByText('The exact recipient and message are confirmed for this sign-in.')).toBeInTheDocument();
}

describe('assisted operator controls', () => {
  it('keeps all writes hidden by default even for an account with manage access', async () => {
    const {fetchImpl, actions} = fixture(); mount(fetchImpl);
    expect(await screen.findByText('Changes to assisted SMS operations are currently unavailable.')).toBeInTheDocument();
    expect(screen.queryByRole('button', {name: /Claim for review|Record observation|send once/i})).not.toBeInTheDocument();
    expect(actions).toEqual(['list_pending']);
  });

  it('checks an entered original UUID and shows its recorded start without granting sending authority', async () => {
    const {fetchImpl, actions, receipts} = fixture(), reference = 'b9a88ee2-1b57-4860-b6b2-56249cb37855';
    receipts.set(reference, {...marker, attempt_id: attemptId, job_id: jobId, confirmation_id: 'ee972a01-8de9-4527-82d4-032f0f23df54', claim_token: claimId, fence_version: 1, state: 'send_started', originating_session_id: principalId, public_session_id: sessionId});
    mount(fetchImpl);
    fireEvent.change(await screen.findByLabelText('Original operation UUID'), {target: {value: reference}});
    fireEvent.click(screen.getByRole('button', {name: 'Check original UUID'}));
    expect(await screen.findByText(/No sending authority was recovered/)).toBeInTheDocument();
    expect(screen.getByRole('heading', {name: 'Recorded operation'})).toBeInTheDocument();
    expect(screen.getByText(new RegExp(`Attempt ID: ${attemptId}`))).toBeInTheDocument();
    expect(actions).toEqual(['list_pending', 'get_operation']);
    expect(screen.queryByRole('button', {name: /Claim for review|Record observation|send once/i})).not.toBeInTheDocument();
    expect(sessionStorage.length).toBe(0);
  });

  it('reports an invalid or unobserved lookup without creating a pending operation', async () => {
    const {fetchImpl, actions} = fixture(); mount(fetchImpl);
    const input = await screen.findByLabelText('Original operation UUID');
    fireEvent.change(input, {target: {value: 'invalid'}});
    fireEvent.click(screen.getByRole('button', {name: 'Check original UUID'}));
    expect(await screen.findByText(/valid original operation UUID/i)).toBeInTheDocument();
    expect(actions).toEqual(['list_pending']);
    fireEvent.change(input, {target: {value: 'b9a88ee2-1b57-4860-b6b2-56249cb37855'}});
    fireEvent.click(screen.getByRole('button', {name: 'Check original UUID'}));
    expect(await screen.findByText(/No recorded result was observed/)).toBeInTheDocument();
    expect(actions).toEqual(['list_pending', 'get_operation']);
    expect(sessionStorage.length).toBe(0);
  });

  it('confirms exact content but cannot start a send without an injected sender', async () => {
    const {fetchImpl, actions} = fixture(); mount(fetchImpl, true);
    await claimAndReview();
    expect(screen.getByText('A native SMS sender is unavailable. Sending is disabled.')).toBeInTheDocument();
    expect(screen.queryByRole('button', {name: 'Record start and send once'})).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', {name: 'Release claim'}));
    const dialog = screen.getByRole('dialog', {name: 'Release this claim?'});
    fireEvent.click(within(dialog).getByRole('button', {name: 'Release claim'}));
    await waitFor(() => expect(actions).toContain('release_claim'));
    expect(actions).not.toContain('record_send_start');
  });

  it('uses a synthetic sender once and requires separate confirmation to record an observation', async () => {
    const {fetchImpl, actions} = fixture(), handoffs: unknown[] = [];
    const sender: AssistedSmsSender = {sendOnce: vi.fn(async (take) => {handoffs.push(take(), take()); return {observation: 'observed_sent' as const, evidenceReferenceSha256: digest('synthetic evidence')};})};
    mount(fetchImpl, true, sender); await claimAndReview();
    fireEvent.click(screen.getByRole('button', {name: 'Record start and send once'}));
    const start = screen.getByRole('dialog', {name: 'Send this SMS once?'});
    expect(handoffs).toHaveLength(0);
    fireEvent.click(within(start).getByRole('button', {name: 'Send once'}));
    expect(await screen.findByText(/sender accepted the one-time handoff/i)).toBeInTheDocument();
    expect(handoffs).toEqual([{attemptId, destinationE164: destination, messageBody: message}, null]);
    expect(screen.getByLabelText('Observed outcome')).toHaveValue('observed_sent');
    expect(screen.getByLabelText('Evidence reference SHA-256')).toHaveValue(digest('synthetic evidence'));
    fireEvent.click(screen.getByRole('button', {name: 'Record observation'}));
    const outcome = screen.getByRole('dialog', {name: 'Record this observation?'});
    expect(actions).not.toContain('record_outcome');
    fireEvent.click(within(outcome).getByRole('button', {name: 'Record observation'}));
    await waitFor(() => expect(actions).toContain('record_outcome'));
  });

  it('checks a lost claim by its original reference without adopting recovered authority', async () => {
    const {fetchImpl, actions} = fixture(true); mount(fetchImpl, true);
    fireEvent.click(await screen.findByRole('button', {name: 'Claim for review'}));
    fireEvent.click(within(screen.getByRole('dialog', {name: 'Claim this SMS job?'})).getByRole('button', {name: 'Claim job'}));
    expect(await screen.findByText(/result is unknown/i)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', {name: 'Check original operation'}));
    expect(await screen.findByText(/No sending authority was recovered/)).toBeInTheDocument();
    expect(screen.queryByText('Current claim')).not.toBeInTheDocument();
    expect(actions.filter((action) => action === 'claim')).toHaveLength(1);
  });

  it('invalidates a delayed sender handoff when the tab is hidden', async () => {
    let visibility: DocumentVisibilityState = 'visible'; vi.spyOn(document, 'visibilityState', 'get').mockImplementation(() => visibility);
    const {fetchImpl, actions} = fixture();
    let take!: Parameters<AssistedSmsSender['sendOnce']>[0], finish!: (value: null) => void;
    const sender: AssistedSmsSender = {sendOnce: (value) => {take = value; return new Promise((resolve) => {finish = resolve;});}};
    mount(fetchImpl, true, sender); await claimAndReview();
    fireEvent.click(screen.getByRole('button', {name: 'Record start and send once'}));
    fireEvent.click(within(screen.getByRole('dialog', {name: 'Send this SMS once?'})).getByRole('button', {name: 'Send once'}));
    await waitFor(() => expect(take).toBeDefined());
    visibility = 'hidden'; fireEvent(document, new Event('visibilitychange'));
    expect(take()).toBeNull(); finish(null);
    expect(screen.queryByText(/Synthetic recorded contribution/)).not.toBeInTheDocument();
    expect(actions.filter((action) => action === 'record_send_start')).toHaveLength(1);
    expect(actions).not.toContain('record_outcome');
  });
});
