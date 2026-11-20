import {useLayoutEffect, useRef, useState} from 'react';
import {Button, Card} from '../../ui';
import type {BuriProvisioning} from './contracts';
import {cancelNativeRevocation, checkNativeRevocation, reviewNativeRevocation, submitNativeRevocation, type NativeRevokeContext, type NativeRevokePending, type NativeRevokeReview, type NativeRevokeResult} from './nativeRevocation';

export function NativeRevocationPanel({context, directory, onResolved}: {context: NativeRevokeContext; directory: BuriProvisioning; onResolved: (status: 'recorded' | 'cancelled') => void}) {
  const mounted = useRef(false), live = useRef(context);
  useLayoutEffect(() => {mounted.current = true; return () => {mounted.current = false;};}, []);
  useLayoutEffect(() => {live.current = context;}, [context]);
  const [grantId, setGrantId] = useState(''), [review, setReview] = useState<Extract<NativeRevokeReview, {status: 'ready'}> | null>(null);
  const [pending, setPending] = useState<NativeRevokePending | null>(null), [message, setMessage] = useState(''), [busy, setBusy] = useState(false), [missing, setMissing] = useState(false);
  const actionContext = (): NativeRevokeContext => ({...context,
    isCurrent: () => mounted.current && live.current.isCurrent(),
    isEnabled: () => live.current.enabled && (!live.current.isEnabled || live.current.isEnabled()),
    verifyFresh: () => live.current.verifyFresh(),
  });
  const results = (result: NativeRevokeResult) => {
    if (!mounted.current) return;
    if (result.status === 'recorded' || result.status === 'cancelled') {onResolved(result.status); return;}
    if (result.status === 'unknown') {setPending({kind: 'owned', requestKey: result.requestKey}); setMissing(false); setMessage('The result is unknown. Check the original request before continuing.');}
    else if (result.status === 'not_found') {setPending({kind: 'owned', requestKey: result.requestKey}); setMissing(true); setMessage('No receipt was found. The original request remains unresolved.');}
    else {setPending(result.pending.kind === 'ready' ? null : result.pending); setMissing(false); setMessage(result.pending.kind === 'ready' ? 'No retained native revocation request was found here.' : 'Check the original request before continuing.');}
  };
  const run = async (work: () => Promise<void>) => {
    if (busy || !mounted.current) return; setBusy(true); setMessage('');
    try {await work();} catch (error) {if (mounted.current) setMessage(error instanceof Error ? error.message : 'The original native request could not be verified.');}
    finally {if (mounted.current) setBusy(false);}
  };
  const startReview = () => void run(async () => {
    setReview(null); setMissing(false); const value = await reviewNativeRevocation(actionContext(), grantId);
    if (!mounted.current) return;
    if (value.status === 'ready') {setPending(null); setReview(value);} else {setPending(value.pending); setMessage('Check the original request before continuing.');}
  });
  const submit = () => void run(async () => {if (review) {setReview(null); results(await submitNativeRevocation(actionContext(), review));}});
  const check = () => void run(async () => {setReview(null); results(await checkNativeRevocation(actionContext()));});
  const cancel = () => void run(async () => {
    if (pending?.kind !== 'owned') return;
    setReview(null); results(await cancelNativeRevocation(actionContext(), pending.requestKey));
  });
  const choices = directory.grants.filter(grant => grant.active && grant.accountId !== null && directory.accounts.some(account => account.accountId === grant.accountId));
  return <Card><div className="core-detail"><h2>Native installation requests</h2>
    <p>Check an original request before making another change.</p>
    {message && <p role="status">{message}</p>}
    {pending?.kind === 'owned' || pending?.kind === 'unbound' ? <p>Original request reference: <code>{pending.requestKey}</code>{pending.kind === 'unbound' && ' — its original review details are unavailable; keep the reference.'}</p> : null}
    {pending?.kind === 'foreign' && <p>The original owner session must check this request.</p>}
    {pending?.kind === 'external' && <p>Use the original request shown for this group.</p>}
    <Button type="button" disabled={busy} onClick={check}>Check native revocation request</Button>
    {missing && context.enabled && pending?.kind === 'owned' && <><p>Cancel the original request only if it should no longer be applied. A late original request will then be blocked.</p><Button type="button" disabled={busy} onClick={cancel}>Cancel original request</Button></>}
    {context.enabled && !pending && <div className="core-edit-form"><label>Active installation<select className="admin-input" value={grantId} disabled={busy} onChange={event => {setGrantId(event.target.value); setReview(null); setMessage('');}}><option value="">Select an installation</option>{choices.map(grant => <option key={grant.id} value={grant.id}>{grant.installationId} · {grant.profile}</option>)}</select></label>
      <Button type="button" disabled={busy || !grantId} onClick={startReview}>Review installation revocation</Button></div>}
    {context.enabled && review && <section aria-label="Revocation review"><h3>Review installation revocation</h3><p>This ends BuriMunsi sign-ins using this installation.</p><dl>
      <div><dt>Group</dt><dd>{review.snapshot.collectionId}</dd></div><div><dt>Person reference</dt><dd>{review.snapshot.principalId}</dd></div>
      <div><dt>Installation</dt><dd>{review.snapshot.installationId}</dd></div><div><dt>Profile</dt><dd>{review.snapshot.profile}</dd></div>
      <div><dt>Grant version</dt><dd>{review.snapshot.expectedGrantVersion}</dd></div></dl>
      <Button type="button" disabled={busy} onClick={submit}>Confirm installation revocation</Button></section>}
  </div></Card>;
}
