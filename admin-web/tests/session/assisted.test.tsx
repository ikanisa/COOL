import {fireEvent, render, screen, waitFor} from '@testing-library/react';
import {describe, expect, it, vi} from 'vitest';
import {AssistedSmsPage} from '../../src/features/assisted/AssistedSmsPage';
import {parseAssistedPage} from '../../src/features/assisted/assistedContracts';
import {SessionProvider} from '../../src/session/SessionProvider';

const jobId = '53c51330-f311-4519-977b-30f67b47c1f1', paymentId = 'cdd3c1c0-c124-4c8a-9719-bd2435d198d1', attemptId = '6ea1b44a-25b7-4f2a-9d20-5829675211bc';
const createdAt = '2026-10-18T12:34:56.000Z';
const row = {id: jobId, payment_id: paymentId, state: 'queued', created_at: createdAt, fence: 0, attempt_id: null};
const marker = {contract_version: 1, scope: 'assisted_sms_internal_record', delivery_confirmed: false, provider_confirmation: false, settlement_status: 'not_asserted'};
const response = {ok: true, result: {...marker, items: [row], next_cursor: null}};
const reply = (body: unknown) => new Response(JSON.stringify(body), {status: 200, headers: {'Content-Type': 'application/json'}});

describe('assisted SMS pending list contract', () => {
  it('accepts a strictly typed internal record and valid next cursor', () => {
    const page = parseAssistedPage({ok: true, result: {...marker, items: [row], next_cursor: {after_created_at: createdAt, after_job_id: jobId}}}, null, 1);
    expect(page).toMatchObject({items: [{id: jobId, state: 'queued'}], next_cursor: {after_job_id: jobId}});
  });
  it('rejects claims of delivery, bad order or cursor, and inconsistent attempt state', () => {
    expect(() => parseAssistedPage({ok: true, result: {...marker, delivery_confirmed: true, items: [row], next_cursor: null}})).toThrow();
    expect(() => parseAssistedPage({ok: true, result: {...marker, items: [row, row], next_cursor: null}})).toThrow();
    expect(() => parseAssistedPage({ok: true, result: {...marker, items: [row], next_cursor: {after_created_at: createdAt, after_job_id: paymentId}}}, null, 1)).toThrow();
    expect(() => parseAssistedPage({ok: true, result: {...marker, items: [{...row, state: 'send_started', fence: 1, attempt_id: null}], next_cursor: null}})).toThrow();
    expect(() => parseAssistedPage({ok: true, result: {...marker, items: [{...row, state: ['queued']}], next_cursor: null}})).toThrow();
    expect(() => parseAssistedPage({ok: true, result: {...marker, items: [{...row, state: 'uncertain', fence: 1, attempt_id: attemptId, extra: 'unexpected'}], next_cursor: null}})).toThrow();
  });
});

describe('read-only assisted SMS queue', () => {
  const account = {id: 'operator-one', email: 'a@example.com', role: 'staff', sessionId: 'session-one', permissions: ['assisted_sms.read'], assuranceLevel: 2, mfaAt: new Date().toISOString(), principalId: paymentId, financialModel: 'canonical_evidence_ledger'};
  const expiresAt = new Date(Date.now() + 3_600_000).toISOString();
  it('reads only the current verified queue and exposes no claim or sending controls', async () => {
    let visibility: DocumentVisibilityState = 'visible';
    vi.spyOn(document, 'visibilityState', 'get').mockImplementation(() => visibility);
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      if (String(url).endsWith('/auth/session')) return reply({user: account, expiresAt});
      if (String(url).endsWith('/notification-operator')) {
        expect(init?.method).toBe('POST');
        expect(JSON.parse(String(init?.body))).toEqual({action: 'list_pending', limit: 20});
        return reply(response);
      }
      throw new Error('Unexpected endpoint');
    });
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><AssistedSmsPage onVerify={() => undefined} /></SessionProvider>);
    expect(await screen.findByText(jobId)).toBeInTheDocument();
    expect(screen.getByText(/delivery are not confirmed/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', {name: /claim|send|outcome/i})).not.toBeInTheDocument();
    expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/notification-operator'))).toHaveLength(1);
    visibility = 'hidden'; fireEvent(document, new Event('visibilitychange'));
    expect(screen.queryByText(jobId)).not.toBeInTheDocument();
    visibility = 'visible'; fireEvent(document, new Event('visibilitychange'));
    await waitFor(() => expect(fetchImpl.mock.calls.filter(([url]) => String(url).endsWith('/notification-operator'))).toHaveLength(2));
    expect(await screen.findByText(jobId)).toBeInTheDocument();
  });

  it('requires fresh verification before sending even the read-only command', async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).endsWith('/auth/session')) return reply({user: {...account, assuranceLevel: 1, mfaAt: null}, expiresAt});
      throw new Error('Unexpected endpoint');
    });
    const onVerify = vi.fn();
    render(<SessionProvider config={{backend: 'cloudflare', captchaEnabled: false, googleEnabled: false, fetchImpl}}><AssistedSmsPage onVerify={onVerify} /></SessionProvider>);
    expect(await screen.findByRole('button', {name: 'Verify authenticator'})).toBeInTheDocument();
    await waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(1));
  });
});
