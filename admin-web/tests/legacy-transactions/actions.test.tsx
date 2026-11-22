import {render, screen} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import type {AdminRequest, AdminRequestOptions} from '../../src/api/client';
import {readPending, retainPending, sha256Text, type PendingIdentity} from '../../src/features/core/pendingAttempt';
import {checkLegacyTransaction, loadLegacyTransaction, restoreLegacyTransaction, retryLegacyTransaction, submitLegacyTransaction, validateReview, type LegacyTransactionContext, type LegacyTransactionMode} from '../../src/features/legacy-transactions/actions';
import { LegacyTransactionActions } from '../../src/features/legacy-transactions/LegacyTransactionActions';

const actor = '11111111-1111-4111-8111-111111111111', recorder = '22222222-2222-4222-8222-222222222222', transaction = '33333333-3333-4333-8333-333333333333', group = '44444444-4444-4444-8444-444444444444', payee = '55555555-5555-4555-8555-555555555555', evidenceId = '66666666-6666-4666-8666-666666666666', key = '77777777-7777-4777-8777-777777777777', requestId = '88888888-8888-4888-8888-888888888888';
const reason = 'Independent evidence review', digest = 'a'.repeat(64), originalLocks = Object.getOwnPropertyDescriptor(navigator, 'locks');
const sourceEvidence = {id: evidenceId, kind: 'provider_statement' as const, reference: 'Synthetic provider evidence', sha256: digest, recorded_by_admin_id: recorder, recorded_at: 1700000000};
const transactionResource = {id: transaction, group_id: group, payee_id: payee, network: 'mtn_momo', payee_momo_number_or_code: '123456', provider_reference: 'SYNTHETIC-REF', amount_rwf: 2500, observed_at: 1700000000, verification_status: 'pending', version: 2, recorded_by_admin_id: recorder, reference_source_fact_id: null, currency: 'RWF', provider_confirmation: false, settlement_status: 'not_asserted'};
const addBody = {expected_version: 2, evidence: {kind: 'receiver_statement', reference: 'Synthetic receiver statement', sha256: 'b'.repeat(64)}, reason};
const reviewBody = {expected_version: 2, evidence_id: evidenceId, outcome: 'confirmation_recorded', reason};
const receipt = {request_id: requestId, resource_type: 'transactions', resource_id: transaction, version: 3, status: 'succeeded'};
function identity(): PendingIdentity {return {id: actor, sessionId: 'session-1', email: 'admin@example.test', role: 'admin', permissions: ['payments.read', 'payments.manage', 'overview.read'], expiresAt: new Date(Date.now() + 3600000).toISOString()};}
function ctx(request: AdminRequest, mode: LegacyTransactionMode = 'add'): LegacyTransactionContext {const user = identity(); return {id: transaction, mode, request, identity: user, permissions: user.permissions, financialModel: 'transaction_journals', enabled: true, isCurrent: () => true, storage: sessionStorage, sharedStorage: localStorage, lock: async (_name, work) => work(), createKey: () => key};}
function page(relation: 'evidence' | 'journals', options: {version?: number; recordedBy?: string | null; evidence?: unknown[]; journals?: unknown[]; currentActor?: string} = {}) {
  const rows = relation === 'evidence' ? options.evidence ?? [sourceEvidence] : options.journals ?? [];
  return {resource_type: 'transactions', resource: {...transactionResource, version: options.version ?? 2, recorded_by_admin_id: options.recordedBy === undefined ? recorder : options.recordedBy}, current_actor_id: options.currentActor ?? actor,
    can_manage: true, related: {[relation]: rows}, related_pages: {[relation]: {total: rows.length, limit: 100, offset: 0, next_offset: null}}, related_truncated: false};
}
function requestFor(mode: LegacyTransactionMode, onPost: (options?: AdminRequestOptions) => Promise<Record<string, unknown>> = async () => receipt) {
  const operation = mode === 'add' ? 'evidence' : 'verification';
  return vi.fn(async (path: string, options?: AdminRequestOptions): Promise<Record<string, unknown>> => {
    if (path === `operations/transactions/${transaction}?relation=evidence&limit=100&offset=0`) return page('evidence');
    if (path === `operations/transactions/${transaction}?relation=journals&limit=100&offset=0`) return page('journals');
    if (path === `operations/transactions/${transaction}/${operation}`) return onPost(options);
    if (path === `operations/requests/${key}`) return {status: 'succeeded', request_id: requestId, receipt};
    if (path === 'operations/requests?limit=100&offset=0') return {total: 1, rows: [{id: requestId, idempotency_key: key, scope: `transactions.post.${operation}`, status: 'succeeded', receipt, created_at: 1700000000, completed_at: 1700000001}]};
    throw new Error(`Unexpected synthetic request ${path}`);
  });
}
async function revision(context: LegacyTransactionContext) {const saved = await restoreLegacyTransaction(context); if (saved.kind !== 'ready') throw new Error('Expected clear checkpoint'); return saved.revision;}
beforeEach(() => {sessionStorage.clear(); localStorage.clear(); Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: async (name: string, _options: unknown, task: (lock: {name: string}) => Promise<unknown>) => task({name})}});});
afterEach(() => {if (originalLocks) Object.defineProperty(navigator, 'locks', originalLocks); else Reflect.deleteProperty(navigator, 'locks');});

describe('Legacy transaction evidence actions', () => {
  it('requires the explicit gate, current authority, legacy model and payment permissions', async () => {
    const request = requestFor('add'), context = ctx(request), snapshot = await loadLegacyTransaction(context); request.mockClear();
    await expect(submitLegacyTransaction({...context, enabled: false}, addBody, snapshot, '')).rejects.toThrow(/not enabled/);
    await expect(submitLegacyTransaction({...context, financialModel: 'canonical_evidence_ledger'}, addBody, snapshot, '')).rejects.toThrow(/unavailable/);
    await expect(submitLegacyTransaction({...context, identity: {...context.identity, role: 'staff'}}, addBody, snapshot, '')).rejects.toThrow(/unavailable/);
    await expect(submitLegacyTransaction({...context, permissions: ['payments.manage']}, addBody, snapshot, '')).rejects.toThrow(/unavailable/);
    await expect(submitLegacyTransaction({...context, isCurrent: () => false}, addBody, snapshot, '')).rejects.toThrow(/unavailable/);
    expect(request).not.toHaveBeenCalled();
  });
  it.each(['add', 'review'] as const)('retains exact %s intent and verifies the actor-scoped original receipt and action scope', async mode => {
    const original = mode === 'add' ? addBody : reviewBody, request = requestFor(mode, async options => {
      expect(options).toEqual({method: 'POST', body: original, idempotencyKey: key});
      const saved = await readPending(identity(), mode === 'add' ? 'legacy-guarded-add-evidence' : 'legacy-guarded-review-evidence', transaction);
      expect(saved).toMatchObject({request_key: key, intent: {expected_version: 2, request_sha256: await sha256Text(JSON.stringify(original))}});
      expect(sessionStorage.getItem('collect.admin.pending-attempts.v1')).not.toContain(reason);
      expect(sessionStorage.getItem('collect.admin.pending-attempts.v1')).not.toContain('Synthetic receiver statement'); return receipt;
    });
    const context = ctx(request, mode), snapshot = await loadLegacyTransaction(context);
    expect(await submitLegacyTransaction(context, original, snapshot, await revision(context))).toEqual({status: 'succeeded', receipt});
    expect((await restoreLegacyTransaction(context)).kind).toBe('ready');
  });
  it('checks a lost original request and explicitly retries only the original key and exact version', async () => {
    let sends = 0, recorded = false;
    const request = requestFor('add', async options => {sends++; expect(options).toEqual({method: 'POST', body: addBody, idempotencyKey: key}); if (sends === 1) throw new Error('Lost response'); recorded = true; return receipt;});
    const original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => path === `operations/requests/${key}` && !recorded ? {status: 'not_found'} : original(path, options));
    const context = ctx(request), snapshot = await loadLegacyTransaction(context);
    expect(await submitLegacyTransaction(context, addBody, snapshot, await revision(context))).toEqual({status: 'unknown', requestKey: key});
    const pending = await restoreLegacyTransaction(context); expect(await checkLegacyTransaction(context, pending)).toEqual({status: 'not_found', retryAvailable: true});
    await expect(retryLegacyTransaction(context, pending, snapshot, {...addBody, reason: 'Different review reason'})).rejects.toThrow(/does not match/);
    expect((await retryLegacyTransaction(context, pending, snapshot, addBody)).status).toBe('succeeded'); expect(sends).toBe(2);
  });
  it('rejects changed versions, changed evidence and posted journals before a review or retry', async () => {
    const request = requestFor('review', async () => {throw new Error('Lost response');}), context = ctx(request, 'review'), snapshot = await loadLegacyTransaction(context);
    await submitLegacyTransaction(context, reviewBody, snapshot, await revision(context)); const pending = await restoreLegacyTransaction(context);
    const original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => {
      if (path === `operations/requests/${key}`) return {status: 'not_found'};
      if (path.includes('?relation=')) return page(path.includes('relation=evidence') ? 'evidence' : 'journals', {version: 3});
      return original(path, options);
    });
    await expect(retryLegacyTransaction(context, pending, snapshot, reviewBody)).rejects.toThrow(/transaction changed/i);
    expect(request.mock.calls.filter(([path]) => path.endsWith('/verification'))).toHaveLength(1);
    expect(() => validateReview(context, {...snapshot, posted: true}, reviewBody)).toThrow(/independently/);
    expect(() => validateReview(context, {...snapshot, evidence: [{...sourceEvidence, recorded_by_admin_id: actor}]}, reviewBody)).toThrow(/independently/);
    expect(() => validateReview(context, {...snapshot, recordedBy: actor}, reviewBody)).toThrow(/independently/);
    expect(() => validateReview(context, {...snapshot, evidence: [{...sourceEvidence, kind: 'payer_receipt'}]}, reviewBody)).toThrow(/independently/);
  });
  it('reads the whole journal history and detects a posted journal beyond the first page', async () => {
    const request = requestFor('review'), original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => {
      if (!path.includes('relation=journals')) return original(path, options);
      const offset = Number(new URL(`https://admin.invalid/${path}`).searchParams.get('offset'));
      const count = offset === 0 ? 100 : 1;
      const rows = Array.from({length: count}, (_, index) => ({id: `${String(offset + index + 1).padStart(8, '0')}-0000-4000-8000-000000000000`, status: offset ? 'posted' : 'draft', version: 1}));
      return {...page('journals', {journals: rows}), related_pages: {journals: {total: 101, limit: 100, offset, next_offset: offset ? null : 100}}, related_truncated: true};
    });
    const context = ctx(request, 'review'), snapshot = await loadLegacyTransaction(context);
    expect(snapshot.posted).toBe(true); expect(() => validateReview(context, snapshot, reviewBody)).toThrow(/independently/);
  });
  it('preserves a request if history identifies the wrong action and blocks another transaction action', async () => {
    const request = requestFor('add', async () => {throw new Error('Lost response');}), context = ctx(request), snapshot = await loadLegacyTransaction(context);
    await submitLegacyTransaction(context, addBody, snapshot, await revision(context)); const pending = await restoreLegacyTransaction(context);
    const original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => path === 'operations/requests?limit=100&offset=0' ? {total: 1, rows: [{id: requestId, idempotency_key: key, scope: 'transactions.post.verification', status: 'succeeded', receipt}]} : original(path, options));
    await expect(checkLegacyTransaction(context, pending)).rejects.toThrow();
    expect((await restoreLegacyTransaction(context)).kind).toBe('owned');
    const reviewContext = {...context, mode: 'review' as const}, reviewSnapshot = await loadLegacyTransaction(reviewContext);
    await expect(submitLegacyTransaction(reviewContext, reviewBody, reviewSnapshot, await revision(reviewContext))).rejects.toThrow(/another transaction request/i);
  });
  it('blocks new guarded writes while an earlier Flutter action is retained', async () => {
    await retainPending(identity(), 'operating-verifytransaction', transaction, key, 'payments.manage', reviewBody);
    const request = requestFor('add'), context = ctx(request), snapshot = await loadLegacyTransaction(context);
    await expect(submitLegacyTransaction(context, addBody, snapshot, await revision(context))).rejects.toThrow(/earlier transaction request/i);
    expect(request.mock.calls.some(([path]) => path.endsWith('/evidence'))).toBe(false);
    expect(await readPending(identity(), 'operating-verifytransaction', transaction)).toMatchObject({request_key: key});
  });
  it('does not dispatch when the gate closes while the original intent is retained', async () => {
    let enabled = true; const storage: Storage = {get length() {return sessionStorage.length;}, clear: () => sessionStorage.clear(), key: index => sessionStorage.key(index), getItem: name => sessionStorage.getItem(name), removeItem: name => sessionStorage.removeItem(name), setItem: (name, value) => {sessionStorage.setItem(name, value); enabled = false;}};
    const request = requestFor('add'), context = {...ctx(request), storage, isEnabled: () => enabled}, snapshot = await loadLegacyTransaction(context);
    expect(await submitLegacyTransaction(context, addBody, snapshot, await revision(context))).toEqual({status: 'unknown', requestKey: key});
    expect(await readPending(identity(), 'legacy-guarded-add-evidence', transaction)).toMatchObject({request_key: key});
    expect(request.mock.calls.some(([path]) => path.endsWith('/evidence'))).toBe(false);
  });
  it('fails closed for wrong actor, malformed pagination or a foreign session', async () => {
    const request = requestFor('add'), context = ctx(request);
    await expect(loadLegacyTransaction({...context, request: async () => page('evidence', {currentActor: recorder})})).rejects.toThrow();
    await expect(loadLegacyTransaction({...context, request: async () => ({...page('evidence'), related_truncated: true})})).rejects.toThrow();
    const snapshot = await loadLegacyTransaction(context); request.mockImplementation(async path => path.endsWith('/evidence') ? Promise.reject(new Error('Lost')) : page('evidence'));
    await submitLegacyTransaction(context, addBody, snapshot, await revision(context));
    expect(await restoreLegacyTransaction({...context, identity: {...context.identity, sessionId: 'other-session'}})).toEqual({kind: 'foreign'});
  });
  it('keeps the key if session authority changes while a request is in flight', async () => {
    let active = true; const request = requestFor('add', async () => {active = false; return receipt;}), context = {...ctx(request), isCurrent: () => active}, snapshot = await loadLegacyTransaction(context);
    expect(await submitLegacyTransaction(context, addBody, snapshot, await revision(context))).toEqual({status: 'unknown', requestKey: key});
    expect(await readPending(identity(), 'legacy-guarded-add-evidence', transaction)).toMatchObject({request_key: key});
    expect(request.mock.calls.some(([path]) => path === `operations/requests/${key}`)).toBe(false);
  });
  it('queues independent panels only for the short shared checkpoint lock', async () => {
    let chain: Promise<unknown> = Promise.resolve();
    Object.defineProperty(navigator, 'locks', {configurable: true, value: {request: (name: string, options: LockOptions, task: (lock: {name: string}) => Promise<unknown>) => {
      expect(name).toBe('collect.admin.pending-fence.v2'); expect(options.ifAvailable).toBeUndefined();
      const next = chain.then(() => task({name})); chain = next.catch(() => undefined); return next;
    }}});
    const request = requestFor('add'), base = {...ctx(request), lock: undefined};
    const [add, review] = await Promise.all([restoreLegacyTransaction(base), restoreLegacyTransaction({...base, mode: 'review'})]);
    expect(add.kind).toBe('ready'); expect(review.kind).toBe('ready');
  });
});

describe('Legacy transaction evidence panel', () => {
  it('keeps controls off by default and can check a retained request without retrying', async () => {
    await retainPending(identity(), 'operating-addevidence', transaction, key, 'payments.manage', addBody);
    const user = userEvent.setup(), request = requestFor('add'); request.mockImplementation(async path => path === `operations/requests/${key}` ? {status: 'not_found'} : page('evidence'));
    const authority = identity(); render(<LegacyTransactionActions id={transaction} mode="add" request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="epoch-1" isCurrent={() => true} onUpdated={() => undefined} />);
    await user.click(await screen.findByRole('button', {name: 'Check earlier request'}));
    expect(await screen.findByText('No receipt was found. Keep the earlier reference; this panel cannot retry it.')).toBeVisible();
    expect(screen.queryByRole('button', {name: 'Confirm same request'})).not.toBeInTheDocument();
    expect(request.mock.calls.some(([path]) => path.endsWith('/evidence'))).toBe(false);
  });
  it('shows the transaction and requires explicit confirmation before adding evidence', async () => {
    const user = userEvent.setup(), authority = identity(), request = requestFor('add'), updated = vi.fn();
    // Capture the generated original key as the real client would use it.
    let generatedKey = '';
    const original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => {
      if (path.endsWith('/evidence') && options?.method === 'POST') {generatedKey = options.idempotencyKey ?? ''; return receipt;}
      if (path === `operations/requests/${generatedKey}`) return {status: 'succeeded', request_id: requestId, receipt};
      if (path === 'operations/requests?limit=100&offset=0') return {total: 1, rows: [{id: requestId, idempotency_key: generatedKey, scope: 'transactions.post.evidence', status: 'succeeded', receipt}]};
      return original(path, options);
    });
    render(<LegacyTransactionActions id={transaction} mode="add" request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="epoch-1" isCurrent={() => true} allowMutations onUpdated={updated} />);
    await user.selectOptions(await screen.findByLabelText('Evidence type'), 'receiver_statement'); await user.type(screen.getByLabelText('Evidence reference'), 'Synthetic receiver statement');
    await user.type(screen.getByLabelText('Evidence SHA-256'), 'b'.repeat(64)); await user.type(screen.getByLabelText('Reason'), reason); await user.click(screen.getByRole('button', {name: 'Review request'}));
    expect(screen.getByText('SYNTHETIC-REF')).toBeVisible(); expect(screen.getByRole('button', {name: 'Confirm request'})).toBeDisabled();
    expect(request.mock.calls.some(([path, options]) => path.endsWith('/evidence') && options?.method === 'POST')).toBe(false);
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the transaction, evidence and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm request'}));
    expect(await screen.findByText(`Request recorded. Reference ${requestId}.`)).toBeVisible(); expect(updated).toHaveBeenCalledOnce();
  });
  it('shows the independent statement and requires confirmation before recording a review', async () => {
    const user = userEvent.setup(), authority = identity(), request = requestFor('review'), updated = vi.fn(); let generatedKey = '';
    const original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => {
      if (path.endsWith('/verification') && options?.method === 'POST') {generatedKey = options.idempotencyKey ?? ''; expect(options.body).toEqual(reviewBody); return receipt;}
      if (path === `operations/requests/${generatedKey}`) return {status: 'succeeded', request_id: requestId, receipt};
      if (path === 'operations/requests?limit=100&offset=0') return {total: 1, rows: [{id: requestId, idempotency_key: generatedKey, scope: 'transactions.post.verification', status: 'succeeded', receipt}]};
      return original(path, options);
    });
    render(<LegacyTransactionActions id={transaction} mode="review" request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="epoch-1" isCurrent={() => true} allowMutations onUpdated={updated} />);
    await user.selectOptions(await screen.findByLabelText('Independent evidence'), evidenceId); await user.type(screen.getByLabelText('Reason'), reason); await user.click(screen.getByRole('button', {name: 'Review request'}));
    expect(screen.getByText(new RegExp(`provider_statement.*${digest}`))).toBeVisible(); expect(screen.getByRole('button', {name: 'Confirm request'})).toBeDisabled();
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the transaction, evidence and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm request'}));
    expect(await screen.findByText(`Request recorded. Reference ${requestId}.`)).toBeVisible(); expect(updated).toHaveBeenCalledOnce();
  });
  it('requires the evidence reference and reason to be re-entered exactly for a retry', async () => {
    await retainPending(identity(), 'legacy-guarded-add-evidence', transaction, key, 'payments.manage', {expected_version: 2, evidence_kind: addBody.evidence.kind, evidence_sha256: addBody.evidence.sha256, request_sha256: await sha256Text(JSON.stringify(addBody))});
    const user = userEvent.setup(), authority = identity(), request = requestFor('add'), updated = vi.fn(); let posted = false; const original = request.getMockImplementation()!;
    request.mockImplementation(async (path, options) => {
      if (path === `operations/requests/${key}` && !posted) return {status: 'not_found'};
      if (path.endsWith('/evidence') && options?.method === 'POST') {expect(options).toEqual({method: 'POST', body: addBody, idempotencyKey: key}); posted = true; return receipt;}
      return original(path, options);
    });
    render(<LegacyTransactionActions id={transaction} mode="add" request={request} identity={authority} permissions={authority.permissions} financialModel="transaction_journals" authorityKey="epoch-1" isCurrent={() => true} allowMutations onUpdated={updated} />);
    await user.click(await screen.findByRole('button', {name: 'Check original request'}));
    expect(await screen.findByText('No receipt was found. Re-enter the original evidence and reason to review the same request.')).toBeVisible();
    expect(screen.getByLabelText('Evidence reference')).toHaveValue(''); expect(screen.getByLabelText('Reason')).toHaveValue('');
    await user.type(screen.getByLabelText('Evidence reference'), addBody.evidence.reference); await user.type(screen.getByLabelText('Reason'), 'Different private reason'); await user.click(screen.getByRole('button', {name: 'Review request'}));
    expect(await screen.findByText(/A retry must exactly match the original request/)).toBeVisible(); expect(posted).toBe(false);
    await user.clear(screen.getByLabelText('Reason')); await user.type(screen.getByLabelText('Reason'), reason); await user.click(screen.getByRole('button', {name: 'Review request'}));
    await user.click(screen.getByRole('checkbox', {name: 'I reviewed the transaction, evidence and reason.'})); await user.click(screen.getByRole('button', {name: 'Confirm same request'}));
    expect(await screen.findByText(`Request recorded. Reference ${requestId}.`)).toBeVisible(); expect(updated).toHaveBeenCalledOnce();
  });
});
