import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import {Button, Dialog, Field, LoadingState} from '../../ui';
import type {FeatureAccess, PendingIdentity} from '../core';
import {cancellationReason, checkCancellation, restoreCancellation, retryCancellation, submitCancellation,
  type CancellationContext, type CancellationPending, type CancellationResult} from './cancellation';
import type {RequestLookup} from './contracts';

export interface CancellationPanelProps extends FeatureAccess {
  identity: PendingIdentity;
  verifyFresh: () => Promise<boolean>;
  targetKey: string;
  target: RequestLookup;
  allowCancellation?: boolean;
  onOutcome: (targetKey: string, outcome: RequestLookup) => void;
}

/** Each panel is tied to one verified target and one session authority. */
export function CancellationPanel({request, identity, verifyFresh, targetKey, target, allowCancellation = false,
  permissions, actorId, principalId, role, financialModel, authorityKey, navigate, onOutcome}: CancellationPanelProps) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    expiresAt: identity.expiresAt, permissions: JSON.parse(permissionKey) as string[]}),
  [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const scope = JSON.stringify([authorityKey, actorId, principalId, financialModel, role, targetKey, permissionKey, stableIdentity.sessionId, stableIdentity.expiresAt,
    [...new Set(permissions)].sort()]);
  const scopeRef = useRef(scope), gateRef = useRef(allowCancellation), verifyRef = useRef(verifyFresh), busyRef = useRef(false);
  useLayoutEffect(() => {scopeRef.current = scope; return () => {scopeRef.current = '';};}, [scope]);
  useLayoutEffect(() => {gateRef.current = allowCancellation; return () => {gateRef.current = false;};}, [allowCancellation]);
  useLayoutEffect(() => {verifyRef.current = verifyFresh;}, [verifyFresh]);
  const allowed = financialModel === 'canonical_evidence_ledger' && !!principalId && stableIdentity.id === actorId && stableIdentity.role === role &&
    ['overview.read', 'account.manage'].every((permission) => permissions.includes(permission) && stableIdentity.permissions.includes(permission));
  const context = useMemo<CancellationContext | null>(() => allowed && principalId ? {
    request, identity: stableIdentity, principalId, targetKey, financialModel, enabled: allowCancellation,
    isCurrent: () => scopeRef.current === scope && Date.parse(stableIdentity.expiresAt) > Date.now(),
    isEnabled: () => gateRef.current, verifyFresh: () => verifyRef.current(),
  } : null, [allowed, principalId, request, stableIdentity, targetKey, financialModel, allowCancellation, scope]);
  const [pending, setPending] = useState<CancellationPending | null>(null), [loading, setLoading] = useState(true),
    [checked, setChecked] = useState<RequestLookup | null>(null), [message, setMessage] = useState(''), [busy, setBusy] = useState(false),
    [mode, setMode] = useState<'new' | 'retry' | null>(null), [reason, setReason] = useState(''), [needsVerification, setNeedsVerification] = useState(false);
  useEffect(() => {
    if (!context) return;
    let live = true;
    void restoreCancellation(context).then((value) => {if (live && context.isCurrent()) setPending(value);})
      .catch(() => {if (live && context.isCurrent()) setMessage('Cancellation recovery could not be verified in this browser.');})
      .finally(() => {if (live && context.isCurrent()) setLoading(false);});
    return () => {live = false;};
  }, [context]);
  if (!allowed || !principalId) return null;
  const outcomeText = (value: RequestLookup) => value.status === 'cancelled' ? 'The original reference is blocked.' : value.status === 'succeeded' ?
    'The original change was already recorded; it was not cancelled.' : value.status === 'unconfirmed' ?
      'The original request is still unconfirmed. A cancellation cannot be submitted yet.' :
      'No target request was found. This does not prove that an attempted change failed.';
  async function check() {
    if (!pending || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setChecked(null);
    try {
      const result = await checkCancellation(context!, pending);
      if (context!.isCurrent()) {setChecked(result); setMessage(outcomeText(result)); onOutcome(targetKey, result);}
    } catch {if (context!.isCurrent()) setMessage('The original target could not be verified. Keep both references and check again.');}
    finally {busyRef.current = false; if (context!.isCurrent()) setBusy(false);}
  }
  function review(event: FormEvent) {
    event.preventDefault();
    if (!allowCancellation || busyRef.current || pending?.kind !== 'ready' || target.status !== 'not_found') return;
    setReason(''); setNeedsVerification(false); setMessage(''); setMode('new');
  }
  function reviewRetry() {
    if (!allowCancellation || busyRef.current || pending?.kind !== 'owned' || !pending.attempt || !checked || checked.status === 'unconfirmed') return;
    setReason(String(pending.attempt.intent.reason)); setNeedsVerification(false); setMessage(''); setMode('retry');
  }
  async function submit() {
    if (!mode || !pending || busyRef.current) return;
    try {cancellationReason(reason);} catch {setMessage('Provide a cancellation reason of 8 to 500 characters.'); return;}
    busyRef.current = true; setBusy(true); setMessage(''); setNeedsVerification(false);
    try {
      const result: CancellationResult = mode === 'new' && pending.kind === 'ready' ?
        await submitCancellation(context!, reason, pending.revision) : await retryCancellation(context!, pending);
      if (!context!.isCurrent()) return;
      if (result.status === 'confirmed') {
        setPending(null); setChecked(result.outcome); setMessage(outcomeText(result.outcome)); onOutcome(targetKey, result.outcome);
      } else if (result.status === 'target_changed') {
        setChecked(result.outcome); setMessage(outcomeText(result.outcome)); onOutcome(targetKey, result.outcome);
      } else if (result.status === 'existing') {
        setPending(result.pending); setChecked(null); setMessage('An original cancellation already needs review.');
      } else {
        setChecked(null); setMessage(`The cancellation result is unknown. Keep cancellation reference ${result.requestKey} and check the original target.`);
        try {setPending(await restoreCancellation(context!));} catch {setPending({kind: 'owned', requestKey: result.requestKey, attempt: null});}
      }
    } catch (error) {
      if (context!.isCurrent()) {
        setNeedsVerification(error instanceof Error && error.message.includes('current verification'));
        setMessage(error instanceof Error && error.message.includes('unconfirmed') ? 'The original request is still unconfirmed. Check it again before cancellation.' :
          'The cancellation could not be submitted. Check the request and your current verification.');
        try {setPending(await restoreCancellation(context!));} catch { /* Keep any displayed original reference. */ }
      }
    } finally {busyRef.current = false; if (context!.isCurrent()) {setBusy(false); setMode(null);}}
  }
  return <section className="request-cancellation" aria-label="Original request cancellation">
    {loading && <LoadingState label="Checking cancellation recovery" />}
    {message && !mode && <p role="status">{message}</p>}
    {needsVerification && <Button onClick={() => navigate('/admin/security')}>Open account security</Button>}
    {pending?.kind === 'foreign' && <p>Another account or session has an unresolved cancellation for this reference. Its original owner must review it.</p>}
    {pending?.kind === 'owned' && <><p>Cancellation reference: <code>{pending.requestKey}</code></p>
      <p>A target check cannot establish which cancellation request produced the result.</p>
      <Button disabled={busy || mode !== null} onClick={() => void check()}>Check original target</Button>{' '}
      {allowCancellation && checked && checked.status !== 'unconfirmed' && pending.attempt && <Button disabled={busy || mode !== null} onClick={reviewRetry}>Review same cancellation</Button>}
      {!pending.attempt && <p>The original cancellation intent or principal is unavailable. Keep the references; retry is unavailable.</p>}
    </>}
    {pending?.kind === 'ready' && allowCancellation && target.status === 'not_found' && <form onSubmit={review}>
      <Button type="submit" disabled={busy}>Review cancellation of original reference</Button>
    </form>}
    {mode && <Dialog open title={mode === 'new' ? 'Cancel original request reference' : 'Retry the same cancellation'} onClose={() => {if (!busy) setMode(null);}}
      footer={<><Button disabled={busy} onClick={() => setMode(null)}>Keep reference</Button><Button variant="danger" loading={busy} onClick={() => void submit()}>{mode === 'new' ? 'Cancel uncommitted request' : 'Retry same cancellation'}</Button></>}>
      <p>A committed change is returned. Otherwise, cancellation blocks this original reference so a delayed retry cannot apply it.</p>
      <p>Original reference: <code>{targetKey}</code></p>
      {mode === 'retry' && <><p>Cancellation reference: <code>{pending?.kind === 'owned' ? pending.requestKey : ''}</code></p><p>This retry is a write and can still cancel the original if it was not already recorded.</p></>}
      <Field label="Cancellation reason" htmlFor="cancellation-reason"><textarea className="admin-input" id="cancellation-reason" value={reason} maxLength={500}
        readOnly={mode === 'retry'} onChange={(event) => setReason(event.target.value)} /></Field>
      {message && <p role="alert">{message}</p>}
    </Dialog>}
  </section>;
}
