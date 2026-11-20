import {useLayoutEffect, useRef, useState} from 'react';
import {Button, Card} from '../../ui';
import type {BuriProvisioning} from './contracts';
import {NATIVE_PROTECTED_DELIVERY_QUALIFIED, cancelNativeProvisioning, checkNativeProvisioning, closeNativeDelivery, openNativeDelivery, reviewNativeProvisioning, submitNativeProvisioning,
  type NativeGrantReceipt, type NativeProvisionContext, type NativeProvisionPending, type NativeProvisionResult, type NativeProvisionReview, type ProvisionOperation} from './nativeProvisioning';

type Props = {pinContext: NativeProvisionContext; grantContext: NativeProvisionContext; directory: BuriProvisioning; onResolved: (status: 'recorded' | 'cancelled' | 'closed') => void};
/** PINs and installation tokens exist only in uncontrolled DOM fields and the
 * in-flight request; they never enter React state, a checkpoint or a log. */
export function NativeProvisioningPanel({pinContext, grantContext, directory, onResolved}: Props) {
  const alive = useRef(false), generation = useRef(0), live = useRef({pinContext, grantContext}), inFlight = useRef<AbortController | null>(null), expiryTimer = useRef<number | null>(null);
  const pinField = useRef<HTMLInputElement>(null), confirmation = useRef<HTMLInputElement>(null), tokenField = useRef<HTMLInputElement>(null);
  const [principal, setPrincipal] = useState(''), [installation, setInstallation] = useState(''), [profile, setProfile] = useState<'staff' | 'internal_receiver'>('staff');
  const [review, setReview] = useState<Extract<NativeProvisionReview, {status: 'ready'}> | null>(null), [pending, setPending] = useState<NativeProvisionPending | null>(null);
  const [delivery, setDelivery] = useState<NativeGrantReceipt | null>(null), [tokenVisible, setTokenVisible] = useState(false), [missing, setMissing] = useState(false);
  const [busy, setBusy] = useState(false), [message, setMessage] = useState('');
  useLayoutEffect(() => {live.current = {pinContext, grantContext};}, [pinContext, grantContext]);
  useLayoutEffect(() => {
    alive.current = true;
    const clear = () => {
      if (pinField.current) pinField.current.value = '';
      if (confirmation.current) confirmation.current.value = '';
      if (tokenField.current) {tokenField.current.value = ''; tokenField.current.type = 'password';}
      if (expiryTimer.current !== null) {window.clearTimeout(expiryTimer.current); expiryTimer.current = null;}
    };
    const advance = () => {generation.current++;};
    const pause = () => {advance(); inFlight.current?.abort(); clear(); if (alive.current) {setReview(null); setTokenVisible(false);}};
    const visibility = () => {if (document.visibilityState !== 'visible') pause();};
    document.addEventListener('visibilitychange', visibility); window.addEventListener('blur', pause); window.addEventListener('pagehide', pause);
    return () => {alive.current = false; advance(); inFlight.current?.abort(); clear(); document.removeEventListener('visibilitychange', visibility); window.removeEventListener('blur', pause); window.removeEventListener('pagehide', pause);};
  }, []);
  const clearToken = () => {if (tokenField.current) {tokenField.current.value = ''; tokenField.current.type = 'password';} if (expiryTimer.current !== null) {window.clearTimeout(expiryTimer.current); expiryTimer.current = null;} setTokenVisible(false);};
  const context = (op: ProvisionOperation, controller: AbortController, turn: number): NativeProvisionContext => {
    const initial = op === 'set_pin' ? live.current.pinContext : live.current.grantContext;
    const latest = () => op === 'set_pin' ? live.current.pinContext : live.current.grantContext;
    return {...initial, signal: controller.signal,
      isCurrent: () => alive.current && generation.current === turn && !controller.signal.aborted && latest().isCurrent(),
      isVisible: () => alive.current && generation.current === turn && !controller.signal.aborted && document.visibilityState === 'visible' && latest().isVisible(),
      isEnabled: () => latest().enabled && (!latest().isEnabled || latest().isEnabled!()),
      verifyFresh: () => latest().verifyFresh(),
    };
  };
  const run = async (work: (controller: AbortController, turn: number) => Promise<void>) => {
    if (busy || !alive.current) return; const turn = generation.current, controller = new AbortController(); inFlight.current = controller; setBusy(true); setMessage('');
    try {await work(controller, turn);} catch {if (alive.current && generation.current === turn) setMessage('The native request could not be verified. Check the original request before continuing.');}
    finally {if (inFlight.current === controller) inFlight.current = null; if (alive.current) setBusy(false);}
  };
  const results = (result: NativeProvisionResult) => {
    if (!alive.current) return;
    if (result.status === 'recorded' || result.status === 'cancelled') {onResolved(result.status); return;}
    if (result.status === 'delivery') {setPending({kind: 'owned', requestKey: result.receipt.requestId, operation: 'grant_installation'}); setDelivery(result.receipt); setMissing(false); setMessage(NATIVE_PROTECTED_DELIVERY_QUALIFIED ? 'The grant is recorded. Open protected delivery for this installation.' : 'The grant is recorded. Protected delivery is unavailable here.');}
    else if (result.status === 'unknown' || result.status === 'not_found') {setPending({kind: 'owned', requestKey: result.requestKey, operation: result.operation}); setDelivery(null); setMissing(result.status === 'not_found'); setMessage(result.status === 'not_found' ? 'No receipt was found. The original request remains unresolved.' : 'The result is unknown. Check the original request before continuing.');}
    else {setPending(result.pending.kind === 'ready' ? null : result.pending); setDelivery(null); setMissing(false); setMessage(result.pending.kind === 'ready' ? 'No retained native setup request was found here.' : 'Check the original request before continuing.');}
  };
  const startReview = (op: ProvisionOperation) => void run(async (controller, turn) => {
    setReview(null); clearToken(); setDelivery(null); setMissing(false);
    const result = await reviewNativeProvisioning(context(op, controller, turn), {operation: op, principalId: principal, installationId: op === 'set_pin' ? null : installation.trim(), profile: op === 'set_pin' ? null : profile});
    if (!alive.current || generation.current !== turn) return;
    if (result.status === 'ready') {setPending(null); setReview(result);} else {setPending(result.pending); setMessage('Check the original request before continuing.');}
  });
  const submit = () => void run(async (controller, turn) => {
    if (!review) return; const selected = review;
    const takePin = selected.snapshot.operation === 'set_pin' ? () => {
      const first = pinField.current?.value ?? '', second = confirmation.current?.value ?? '';
      if (pinField.current) pinField.current.value = ''; if (confirmation.current) confirmation.current.value = '';
      if (first !== second) throw new Error('PIN confirmation failed.'); return first;
    } : undefined;
    try {const result = await submitNativeProvisioning(context(selected.snapshot.operation, controller, turn), selected, takePin); if (alive.current && generation.current === turn) results(result);}
    finally {if (pinField.current) pinField.current.value = ''; if (confirmation.current) confirmation.current.value = ''; if (alive.current && generation.current === turn) setReview(null);}
  });
  const check = () => void run(async (controller, turn) => {setReview(null); clearToken(); const result = await checkNativeProvisioning(context('set_pin', controller, turn)); if (alive.current && generation.current === turn) results(result);});
  const cancel = () => void run(async (controller, turn) => {
    if (pending?.kind !== 'owned') return;
    setReview(null); clearToken();
    const result = await cancelNativeProvisioning(context(pending.operation, controller, turn), pending.requestKey, pending.operation);
    if (alive.current && generation.current === turn) results(result);
  });
  const open = () => void run(async (controller, turn) => {
    if (!delivery) return;
    clearToken(); await openNativeDelivery(context('grant_installation', controller, turn), delivery.requestId, (secret, expiresAt) => {
      if (!alive.current || generation.current !== turn || !tokenField.current) throw new Error('Delivery view closed.');
      tokenField.current.value = secret; tokenField.current.type = 'password'; setTokenVisible(true);
      expiryTimer.current = window.setTimeout(() => {if (tokenField.current) {tokenField.current.value = ''; tokenField.current.type = 'password';} if (alive.current) setTokenVisible(false);}, Math.max(0, expiresAt - Date.now()));
    });
  });
  const close = () => void run(async (controller, turn) => {
    if (!delivery) return;
    clearToken(); await closeNativeDelivery(context('grant_installation', controller, turn), delivery.requestId);
    if (alive.current && generation.current === turn) onResolved('closed');
  });
  const enabledReview = review && (review.snapshot.operation === 'set_pin' ? pinContext.enabled : grantContext.enabled);
  return <Card><div className="core-detail"><h2>Native access setup</h2><p>Check an original request before starting another native access change.</p>
    {message && <p role="status">{message}</p>}
    {(pending?.kind === 'owned' || pending?.kind === 'unbound') && <p>Original request reference: <code>{pending.requestKey}</code>{pending.kind === 'unbound' && ' — its original review details are unavailable; keep the reference.'}</p>}
    {pending?.kind === 'external' && <p>Use the original request shown for this group.</p>}{pending?.kind === 'foreign' && <p>The original owner session must check this request.</p>}
    <Button type="button" disabled={busy} onClick={check}>Check native setup request</Button>
    {missing && pending?.kind === 'owned' && (pending.operation === 'set_pin' ? pinContext.enabled : grantContext.enabled) && <><p>Cancellation prevents a late original request from applying.</p><Button type="button" disabled={busy} onClick={cancel}>Cancel original native setup</Button></>}
    {(pinContext.enabled || grantContext.enabled) && !pending && <div className="core-edit-form"><label>Approved native account<select className="admin-input" disabled={busy} value={principal} onChange={event => {setPrincipal(event.target.value); setReview(null); setMessage('');}}><option value="">Select an account</option>{directory.accounts.map(account => <option key={account.principalId} value={account.principalId}>{account.name} · {account.phone}</option>)}</select></label>
      {pinContext.enabled && <Button type="button" disabled={busy || !principal} onClick={() => startReview('set_pin')}>Review PIN setup</Button>}
      {grantContext.enabled && !NATIVE_PROTECTED_DELIVERY_QUALIFIED && <p>Protected installation delivery is unavailable. New grants cannot be issued here.</p>}
      {grantContext.enabled && NATIVE_PROTECTED_DELIVERY_QUALIFIED && <><label>Installation ID<input className="admin-input" value={installation} autoComplete="off" onChange={event => {setInstallation(event.target.value); setReview(null);}} /></label>
        <label>Installation profile<select className="admin-input" value={profile} onChange={event => {setProfile(event.target.value === 'internal_receiver' ? 'internal_receiver' : 'staff'); setReview(null);}}><option value="staff">Staff</option><option value="internal_receiver">Receiving phone</option></select></label>
        <Button type="button" disabled={busy || !principal || !installation.trim()} onClick={() => startReview('grant_installation')}>Review installation grant</Button></>}
    </div>}
    {enabledReview && <section aria-label="Native access review"><h3>{review.snapshot.operation === 'set_pin' ? 'Review PIN setup' : 'Review installation grant'}</h3>
      <p>{review.snapshot.operation === 'set_pin' ? 'Existing native sign-ins for this account will end. Deliver the PIN privately to this approved teammate.' : 'Deliver the new token through approved device management. Existing native sign-ins for this grant will end.'}</p>
      <dl><div><dt>Group</dt><dd>{review.snapshot.collectionId}</dd></div><div><dt>Person reference</dt><dd>{review.snapshot.principalId}</dd></div>
        {review.snapshot.installationId && <div><dt>Installation</dt><dd>{review.snapshot.installationId} · {review.snapshot.profile}</dd></div>}</dl>
      {review.snapshot.operation === 'set_pin' && <div className="core-edit-form"><label>Four-digit PIN<input ref={pinField} type="password" className="admin-input" inputMode="numeric" maxLength={4} autoComplete="off" disabled={busy} /></label>
        <label>Confirm PIN<input ref={confirmation} type="password" className="admin-input" inputMode="numeric" maxLength={4} autoComplete="off" disabled={busy} /></label></div>}
      <Button type="button" disabled={busy} onClick={submit}>{review.snapshot.operation === 'set_pin' ? 'Confirm PIN setup' : 'Confirm installation grant'}</Button></section>}
    {delivery && <section aria-label="Protected delivery"><h3>Protected installation delivery</h3><p>Use approved device management for this exact installation. This is not a login PIN or wallet pairing credential.</p>
      <p>{delivery.installationId} · {delivery.profile}</p>
      {grantContext.enabled && NATIVE_PROTECTED_DELIVERY_QUALIFIED && <Button type="button" disabled={busy} onClick={open}>Open protected delivery</Button>}
      <Button type="button" disabled={busy} onClick={close}>Close local delivery record</Button>
      <div hidden={!tokenVisible}><label>Installation token<input ref={tokenField} type="password" className="admin-input" readOnly autoComplete="off" /></label>{' '}
        <Button type="button" onClick={() => {if (tokenField.current) tokenField.current.type = tokenField.current.type === 'password' ? 'text' : 'password';}}>Reveal or hide token</Button>{' '}<Button type="button" onClick={clearToken}>Hide delivery</Button></div>
    </section>}
    {!delivery && <input ref={tokenField} type="password" hidden readOnly autoComplete="off" aria-label="Protected delivery buffer" />}
  </div></Card>;
}
