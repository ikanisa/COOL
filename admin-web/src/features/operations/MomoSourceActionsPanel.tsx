import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import {Link} from 'react-router';
import {verifySensitiveAccess} from '../../app/sensitive-access';
import {useSession} from '../../session/SessionProvider';
import {Button, Field, LoadingState} from '../../ui';
import {listPending, type PendingIdentity} from '../core';
import type {MomoSourceJob} from './momoContracts';
import {canReviewMomoSource, loadMomoReceivingAccounts, momoSourceFamily, nonPaymentExtraction, parseMomoSourceIntent, restoreMomoSource, retryMomoSource, submitMomoSource,
  type MomoExtraction, type MomoReceivingAccount, type MomoSourceActionContext, type MomoSourceActionKind, type MomoSourceIntent, type MomoSourcePending} from './momoSourceActions';

const rawFields = [
  ['transaction_id_raw', 'Provider transaction ID'], ['original_transaction_id_raw', 'Original transaction ID'], ['transaction_datetime_raw', 'Provider date and time'],
  ['principal_amount_raw', 'Principal amount'], ['currency_raw', 'Currency'], ['payer_name_raw', 'Payer name'], ['payer_identifier_raw', 'Visible payer identifier'],
  ['payment_reference_raw', 'Payment reference'], ['fee_amount_raw', 'Fee'], ['wallet_balance_after_raw', 'Wallet balance observation'],
] as const;
const evidenceFields = [
  ['incoming_success', 'Success excerpt'], ['principal', 'Principal excerpt'], ['transaction_id', 'Transaction ID excerpt'], ['transaction_datetime', 'Date and time excerpt'],
  ['payer', 'Payer excerpt'], ['fee', 'Fee excerpt'], ['wallet_balance_after', 'Wallet balance excerpt'],
] as const;
const label = (kind: MomoSourceActionKind) => kind === 'correct' ? 'Correct extraction' : kind === 'non-payment' ? 'Classify non-payment' : kind === 'reparse' ? 'Reparse source' : 'Resolve historical source';
const sourceIdValid = (value: string) => /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(value);

/** Source actions remain unavailable until the caller explicitly enables them. */
export function MomoSourceActionsPanel({source, candidate, enabled = false, onUpdated}: {source: MomoSourceJob; candidate?: MomoExtraction | null; enabled?: boolean; onUpdated: () => void}) {
  const session = useSession(), [selected, setSelected] = useState<MomoSourceActionKind | null>(null), permissions = session.user?.permissions ?? [];
  if (!enabled || !['sms.read', 'sms.extract'].every((value) => permissions.includes(value))) return null;
  const choices: MomoSourceActionKind[] = ['correct', 'non-payment', 'resolve', 'reparse'];
  return <section className="momo-assignment"><h3>Source review</h3><p>These actions review source evidence. They do not credit a contribution or confirm provider settlement.</p>
    {choices.filter((kind) => canReviewMomoSource(source, kind) && (kind !== 'resolve' || permissions.includes('receivers.read'))).map((kind) => <Button key={kind} onClick={() => setSelected(kind)} disabled={selected !== null}>{label(kind)}</Button>)}
    {selected && <SourceWorkflow key={`${source.raw_sms_id}:${selected}:${session.epoch}`} sourceId={source.raw_sms_id} source={source} candidate={candidate} kind={selected} enabled={enabled} onClose={() => setSelected(null)} onUpdated={onUpdated} />}
  </section>;
}

/** Restore saved requests even when a completed operation moved the source out of the current list. */
export function MomoSourceRecoveryPanel({enabled = false, onUpdated}: {enabled?: boolean; onUpdated: () => void}) {
  const session = useSession(), user = session.user, [items, setItems] = useState<{kind: MomoSourceActionKind; sourceId: string; requestKey: string}[] | null>(null),
    [selected, setSelected] = useState<{kind: MomoSourceActionKind; sourceId: string} | null>(null), [message, setMessage] = useState(''), [busy, setBusy] = useState(false);
  if (!enabled || session.status !== 'authenticated' || !user || !['sms.read', 'sms.extract'].every((permission) => user.permissions.includes(permission))) return null;
  const actor = user, epoch = session.epoch;
  async function read() {
    if (busy) return; setBusy(true); setMessage('');
    try {
      const identity: PendingIdentity = {id: actor.id, sessionId: actor.sessionId, email: actor.email, role: actor.role, permissions: actor.permissions, expiresAt: actor.expiresAt};
      const result: {kind: MomoSourceActionKind; sourceId: string; requestKey: string}[] = [];
      for (const kind of ['correct', 'non-payment', 'resolve', 'reparse'] as const) {
        for (const attempt of await listPending(identity, momoSourceFamily(kind), 'sms.extract')) {
          if (!sourceIdValid(attempt.resource_id)) throw new Error('Invalid source reference.');
          parseMomoSourceIntent(kind, attempt.intent); result.push({kind, sourceId: attempt.resource_id, requestKey: attempt.request_key});
        }
      }
      if (session.isCurrentAuthority(epoch, actor.id, actor.sessionId)) setItems(result);
    } catch {if (session.isCurrentAuthority(epoch, actor.id, actor.sessionId)) setMessage('Original source requests could not be verified.');}
    finally {setBusy(false);}
  }
  return <section className="momo-assignment"><h3>Original source requests</h3><p>Check requests retained in this tab before making another change.</p><Button disabled={busy || selected !== null} onClick={() => void read()}>Review original source requests</Button>
    {message && <p role="alert">{message}</p>}{items?.length === 0 && <p>No original source requests were found in this tab.</p>}
    {items?.map((item) => <div key={`${item.kind}:${item.sourceId}`}><p>{label(item.kind)} · source <code>{item.sourceId}</code> · request <code>{item.requestKey}</code></p><Button disabled={busy || selected !== null || item.kind === 'resolve' && !actor.permissions.includes('receivers.read')} onClick={() => setSelected(item)}>Review original request</Button></div>)}
    {selected && <SourceWorkflow key={`${selected.kind}:${selected.sourceId}:${epoch}`} {...selected} enabled={enabled} onClose={() => setSelected(null)} onUpdated={() => {setSelected(null); setItems(null); onUpdated();}} />}
  </section>;
}

function SourceWorkflow({sourceId, source, candidate, kind, enabled, onClose, onUpdated}: {sourceId: string; source?: MomoSourceJob; candidate?: MomoExtraction | null; kind: MomoSourceActionKind; enabled: boolean; onClose: () => void; onUpdated: () => void}) {
  const session = useSession(), user = session.user, id = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role,
    expiresAt = user?.expiresAt, principalId = user?.principalId, model = user?.financialModel, permissionKey = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => id && sessionId && email && role && expiresAt ? {id, sessionId, email, role, expiresAt, permissions: JSON.parse(permissionKey) as string[]} : null, [id, sessionId, email, role, expiresAt, permissionKey]);
  const scope = JSON.stringify([session.epoch, id, principalId, sourceId, kind]), currentScope = useRef(scope), gate = useRef(enabled), liveSession = useRef(session), busyRef = useRef(false);
  useLayoutEffect(() => {currentScope.current = scope; return () => {currentScope.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = enabled; return () => {gate.current = false;};}, [enabled]);
  useLayoutEffect(() => {liveSession.current = session;}, [session]);
  const context = useMemo<MomoSourceActionContext | null>(() => identity && principalId && model ? {request: session.request, identity, principalId, financialModel: model, sourceId, source, kind, enabled,
    isCurrent: () => currentScope.current === scope && liveSession.current.isCurrentAuthority(session.epoch, identity.id, identity.sessionId) && Date.parse(identity.expiresAt) > Date.now(), isEnabled: () => gate.current,
    verifyFresh: async () => {const live = liveSession.current, actor = live.user; return !!actor && actor.id === identity.id && actor.sessionId === identity.sessionId && await verifySensitiveAccess(live, actor);},
  } : null, [identity, principalId, model, sourceId, source, kind, enabled, scope, session.request, session.epoch]);
  const [pending, setPending] = useState<MomoSourcePending | null>(null), [loading, setLoading] = useState(true), [accounts, setAccounts] = useState<MomoReceivingAccount[]>([]),
    [account, setAccount] = useState(''), [eventKind, setEventKind] = useState<'outgoing' | 'failed' | 'pending'>('outgoing'), [excerpt, setExcerpt] = useState(''),
    [raw, setRaw] = useState<Record<string, string>>(() => kind === 'correct' && candidate ? Object.fromEntries(rawFields.map(([key]) => [key, candidate[key] ?? ''])) : {}),
    [evidence, setEvidence] = useState<Record<string, string>>(() => kind === 'correct' && candidate ? Object.fromEntries(evidenceFields.map(([key]) => [key, candidate.evidence[key] ?? ''])) : {}), [reference, setReference] = useState(''), [reason, setReason] = useState(''),
    [review, setReview] = useState<{mode: 'new' | 'retry'; intent: MomoSourceIntent; revision?: string} | null>(null), [confirmed, setConfirmed] = useState(false),
    [busy, setBusy] = useState(false), [message, setMessage] = useState(''), [needsVerification, setNeedsVerification] = useState(false), [saved, setSaved] = useState(false);
  useEffect(() => {
    if (!context) return;
    let live = true;
    void (async () => {
      try {
        const state = await restoreMomoSource(context);
        if (!live || !context.isCurrent()) return;
        setPending(state);
        if (state.kind === 'ready' && source && kind === 'resolve') {
          const found = await loadMomoReceivingAccounts(context);
          if (live && context.isCurrent()) setAccounts(found);
        }
      } catch {if (live && context.isCurrent()) setMessage('Original source requests could not be verified.');}
      finally {if (live && context.isCurrent()) setLoading(false);}
    })();
    return () => {live = false;};
  }, [context, kind, source]);
  if (!identity || !principalId || !model) return <p>Source review is unavailable for this account.</p>;
  const begin = (event: FormEvent) => {
    event.preventDefault(); if (!source || pending?.kind !== 'ready' || busyRef.current) return;
    try {
      const base = {evidence_reference: reference.trim(), reason: reason.trim()};
      const initial = kind === 'resolve' ? {...base, receiving_account_id: account} : kind === 'reparse' ? {
        reason: reason.trim(), expected_state: source.state, expected_attempt_count: source.attempt_count, expected_body_sha256: source.body_sha256,
        expected_receiving_account_id: source.receiving_account_id,
      } : {
        ...base, expected_state: source.state, expected_attempt_count: source.attempt_count, expected_body_sha256: source.body_sha256,
        extraction: kind === 'non-payment' ? nonPaymentExtraction(eventKind, excerpt) : {schema_version: 'momo-extraction.v1', event_kind: 'incoming_receipt', payment_outcome: 'successful',
          ...Object.fromEntries(rawFields.map(([key]) => [key, raw[key] || null])), evidence: Object.fromEntries(evidenceFields.map(([key]) => [key, evidence[key] || null])), issues: []},
        ...(kind === 'non-payment' ? {classification_evidence: excerpt} : {}),
      };
      if (kind === 'resolve' && !accounts.some((value) => value.id === account)) throw new Error('Select an active receiving account.');
      setReview({mode: 'new', intent: parseMomoSourceIntent(kind, initial), revision: pending.revision}); setConfirmed(false); setMessage('');
    } catch {setMessage('Check the source fields, exact evidence, and reason before continuing.');}
  };
  const beginRetry = () => {
    if (pending?.kind !== 'owned' || !pending.attempt || busyRef.current) return;
    try {setReview({mode: 'retry', intent: parseMomoSourceIntent(kind, pending.attempt.intent)}); setConfirmed(false); setMessage('');}
    catch {setMessage('The original source request could not be verified.');}
  };
  const submit = async () => {
    if (!review || !confirmed || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setNeedsVerification(false);
    try {
      const result = review.mode === 'new' ? await submitMomoSource(context!, review.intent, review.revision!) : await retryMomoSource(context!, pending!);
      if (!context!.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setSaved(true); setMessage(kind === 'resolve' ? 'Historical source queued. No contribution was credited.' : kind === 'reparse' ? 'Source queued for extraction. Review the processing result when it is available.' : 'Source review recorded. No contribution was credited.');}
      else if (result.status === 'existing') {setPending(result.pending); setMessage('An original source request is unresolved.');}
      else {setPending({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The result is unknown. Keep request reference ${result.requestKey}.`); try {setPending(await restoreMomoSource(context!));} catch { /* Preserve visible reference. */ }}
    } catch (error) {
      if (context!.isCurrent()) {setNeedsVerification(error instanceof Error && error.message.includes('current verification')); setMessage('The source request could not be confirmed. Check its current evidence and verification.'); try {setPending(await restoreMomoSource(context!));} catch {setPending(null);}}
    } finally {busyRef.current = false; if (context!.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false);}}
  };
  return <section className="momo-assignment-review" aria-label={label(kind)}><h4>{label(kind)}</h4><p>Source: <code>{sourceId}</code></p>
    {loading && <LoadingState label="Checking source request recovery" />}{message && <p role="status">{message}</p>}
    {needsVerification && <p><Link className="operations-link" to={`/admin/security/${session.verificationMode === 'email' ? 'verify-email' : 'authenticator'}?returnTo=%2Fadmin%2Fmomo-receipts`}>Verify identity</Link></p>}
    {pending?.kind === 'foreign' && <p>Another account or session has an unresolved request. Its original owner must review it.</p>}
    {pending?.kind === 'owned' && <><p>Original request: <code>{pending.requestKey}</code></p><p>There is no read-only result lookup. Retrying the same request may perform the action if it was not already recorded.</p>{pending.attempt ? <Button onClick={beginRetry} disabled={busy || review !== null}>Review original request</Button> : <p>The original intent or principal is unavailable. Keep the reference and contact an authorized operator.</p>}</>}
    {saved && <Button onClick={onUpdated}>Refresh source records</Button>}
    {pending?.kind === 'ready' && !saved && source && !review && <form className="operations-action-form" onSubmit={begin}>
      {kind === 'resolve' ? <><p>Choose the receiving account established by retained historical evidence. The backend validates the source match.</p><Field label="Receiving account" htmlFor="momo-source-account"><select id="momo-source-account" className="admin-input" value={account} onChange={(event) => setAccount(event.target.value)} required disabled={busy}><option value="">Select an account</option>{accounts.map((entry) => <option key={entry.id} value={entry.id}>{entry.recipient_name} · {entry.public_code} · {entry.provider}</option>)}</select></Field>{accounts.length === 0 && <p>No active receiving accounts were found.</p>}</> : kind === 'reparse' ? <p>Queue the reviewed source for another extraction. Processing may record payment evidence or flag a conflict. The source state and attempt must still match when the request is applied.</p> : kind === 'non-payment' ? <><Field label="Classification" htmlFor="momo-source-kind"><select id="momo-source-kind" className="admin-input" value={eventKind} onChange={(event) => setEventKind(event.target.value as typeof eventKind)} disabled={busy}><option value="outgoing">Outgoing</option><option value="failed">Failed</option><option value="pending">Pending</option></select></Field><Field label="Exact classification excerpt" htmlFor="momo-source-excerpt"><textarea id="momo-source-excerpt" className="admin-input" value={excerpt} onChange={(event) => setExcerpt(event.target.value)} maxLength={500} required disabled={busy} /></Field></> : <><p>Enter source facts and supporting excerpts exactly as recorded. The backend validates the complete source and provider profile.</p>{candidate && <p>Suggested fields are unverified. Review them against the original source before continuing.</p>}{rawFields.map(([key, title]) => <Field key={key} label={title} htmlFor={`momo-${key}`}><input id={`momo-${key}`} className="admin-input" value={raw[key] ?? ''} onChange={(event) => setRaw((previous) => ({...previous, [key]: event.target.value}))} maxLength={500} disabled={busy} /></Field>)}<details><summary>Exact supporting excerpts</summary>{evidenceFields.map(([key, title]) => <Field key={key} label={title} htmlFor={`momo-evidence-${key}`}><textarea id={`momo-evidence-${key}`} className="admin-input" value={evidence[key] ?? ''} onChange={(event) => setEvidence((previous) => ({...previous, [key]: event.target.value}))} maxLength={500} disabled={busy} /></Field>)}</details></>}
      {kind !== 'reparse' && <Field label="Supporting evidence reference" htmlFor="momo-source-reference"><textarea id="momo-source-reference" className="admin-input" value={reference} onChange={(event) => setReference(event.target.value)} minLength={8} maxLength={500} required disabled={busy} /></Field>}<Field label="Reason" htmlFor="momo-source-action-reason"><textarea id="momo-source-action-reason" className="admin-input" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={500} required disabled={busy} /></Field><Button type="submit" variant="primary" disabled={busy}>Review source request</Button>
    </form>}
    {review && <section aria-label="Confirm source request"><h4>Confirm source request</h4><p>{review.mode === 'retry' ? 'This reuses the original key and exact fields. It may record the action if it has not already committed.' : 'The exact reviewed fields will be sent once.'} No contribution is credited.</p><pre className="operations-source-content">{JSON.stringify(review.intent, null, 2)}</pre><label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} disabled={busy} /> {kind === 'reparse' ? 'I reviewed this source and its current version.' : 'I reviewed this source, its exact fields and supporting evidence.'}</label><div className="momo-assignment-actions"><Button onClick={() => setReview(null)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>{review.mode === 'retry' ? 'Retry original request' : 'Confirm source request'}</Button></div></section>}
    <Button onClick={onClose} disabled={busy}>Close source action</Button>
  </section>;
}
