import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import {useSession} from '../../session/SessionProvider';
import {Button, Card, Dialog, Field, LoadingState} from '../../ui';
import type {PendingIdentity} from '../core/pendingAttempt';
import type {DataRow} from '../core/types';
import type {GatewayDevice, Page} from './contracts';
import {loadGrantDevices, loadGrantPayees, loadGrantTargets, loadOriginalGrantTargets, lookupGrantCreation, restoreGrantCreation, retryGrantCreation, submitGrantCreation, verifyGrantSelection,
  type GrantCreateContext, type GrantCreatePending, type GrantTargets} from './receiverGrantCreation';

/** Legacy capture grants are unavailable until explicitly qualified and enabled. */
export function ReceiverGrantCreatePanel({enabled = false, onUpdated}: {enabled?: boolean; onUpdated: () => void}) {
  const session = useSession(), user = session.user;
  const id = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role, expiresAt = user?.expiresAt, model = user?.financialModel;
  const permissions = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => id && sessionId && email && role && expiresAt ? {id, sessionId, email, role, expiresAt, permissions: JSON.parse(permissions) as string[]} : null, [id, sessionId, email, role, expiresAt, permissions]);
  const scope = `${session.epoch}:${id ?? ''}:${sessionId ?? ''}:receiver-grant-create`, currentScope = useRef(scope), gate = useRef(enabled), live = useRef(session), busyRef = useRef(false);
  useLayoutEffect(() => {currentScope.current = scope; return () => {currentScope.current = '';};}, [scope]);
  useLayoutEffect(() => {gate.current = enabled; return () => {gate.current = false;};}, [enabled]);
  useLayoutEffect(() => {live.current = session;}, [session]);
  const context = useMemo<GrantCreateContext | null>(() => identity && model ? {request: session.request, identity, financialModel: model, enabled,
    isCurrent: () => currentScope.current === scope && Date.parse(identity.expiresAt) > Date.now() && live.current.isCurrentAuthority(session.epoch, identity.id, identity.sessionId),
    isEnabled: () => gate.current} : null, [identity, model, enabled, scope, session.request, session.epoch]);
  const allowed = !!identity && identity.role !== 'staff' && model === 'transaction_journals' && ['gateway.read', 'gateway.manage', 'receivers.read'].every(value => identity.permissions.includes(value));
  const [pending, setPending] = useState<GrantCreatePending | null>(null), [loadedScope, setLoadedScope] = useState(''), [message, setMessage] = useState('');
  const [devicePage, setDevicePage] = useState<Page<GatewayDevice> | null>(null), [payeePage, setPayeePage] = useState<{rows: DataRow[]; total: number; offset: number} | null>(null);
  const [device, setDevice] = useState<GatewayDevice | null>(null), [payee, setPayee] = useState<DataRow | null>(null), [search, setSearch] = useState(''), [reason, setReason] = useState('');
  const [targets, setTargets] = useState<GrantTargets | null>(null), [review, setReview] = useState<'new' | 'retry' | null>(null), [confirmed, setConfirmed] = useState(false), [retryAvailable, setRetryAvailable] = useState(false);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!context || !allowed) return;
    let active = true;
    restoreGrantCreation(context).then(state => {if (active && context.isCurrent()) {setPending(state); setLoadedScope(scope); if (state.kind !== 'ready') setMessage('Check the original capture request before continuing.');}},
      () => {if (active && context.isCurrent()) {setLoadedScope(scope); setMessage('Recovery data could not be verified. Check the original request before continuing.');}});
    return () => {active = false;};
  }, [allowed, context, scope]);
  if (!identity || !model || !allowed) return null;
  if (loadedScope !== scope) return <LoadingState label="Checking capture request recovery" />;
  const ready = pending?.kind === 'ready' ? pending : null, original = pending && pending.kind !== 'ready' ? pending : null;
  if (!enabled && !original && !message) return null;
  const devices = async (offset: number) => {
    if (!context || busyRef.current || !enabled) return; busyRef.current = true; setBusy(true); setMessage('');
    try {const result = await loadGrantDevices(context, offset); if (context.isCurrent() && gate.current) {setDevicePage(result); setDevice(null);}}
    catch {if (context.isCurrent()) setMessage('Active devices could not be verified.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const payees = async (offset: number) => {
    if (!context || busyRef.current || !enabled) return; busyRef.current = true; setBusy(true); setMessage('');
    try {const result = await loadGrantPayees(context, offset, search); if (context.isCurrent() && gate.current) {setPayeePage({rows: result.rows, total: result.total, offset}); setPayee(null);}}
    catch {if (context.isCurrent()) setMessage('Active receivers could not be verified.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const begin = async (event: FormEvent) => {
    event.preventDefault(); if (!context || !enabled || !ready || !device || !payee || busyRef.current || reason.trim().length < 8 || reason.trim().length > 1000) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {const result = await loadGrantTargets(context, device.id, payee.id); verifyGrantSelection(result, device, payee); if (context.isCurrent() && gate.current) {setTargets(result); setConfirmed(false); setReview('new');}}
    catch {if (context.isCurrent()) setMessage('The selected device or receiver could not be verified. Refresh and review again.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const check = async () => {
    if (!context || original?.kind !== 'owned' || busyRef.current) return; busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = await lookupGrantCreation(context, original); if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setMessage(`Capture grant recorded. Request ${result.receipt.requestId}.`); onUpdated(); try {const next = await restoreGrantCreation(context); if (context.isCurrent()) setPending(next);} catch { /* Leave further creation unavailable if recovery cannot be verified. */ }}
      else if (result.retryAvailable && gate.current) {
        const matched = await loadOriginalGrantTargets(context, original); if (!context.isCurrent() || !gate.current) return;
        setTargets(matched); setRetryAvailable(true); setMessage('No receipt was found. Review the unchanged original request before retrying its key.');
      } else setMessage(result.retryAvailable ? 'No receipt was found. Keep the original reference and check again before continuing.' : 'No receipt was found. The original intent is unavailable; keep this reference and check again.');
    } catch {if (context.isCurrent()) setMessage('The original request or its current device and receiver could not be verified. Keep the original reference.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const submit = async () => {
    if (!context || !enabled || !confirmed || !review || !targets || busyRef.current || review === 'new' && !ready || review === 'retry' && (!retryAvailable || original?.kind !== 'owned' || !original.attempt)) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = review === 'new' ? await submitGrantCreation(context, targets, reason, ready!.revision) : await retryGrantCreation(context, original!, targets);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setPending(null); setMessage(`Capture grant recorded. Request ${result.receipt.requestId}.`); onUpdated(); try {const next = await restoreGrantCreation(context); if (context.isCurrent()) setPending(next);} catch { /* Leave further creation unavailable if recovery cannot be verified. */ }}
      else if (result.status === 'existing') {setPending(result.pending); setMessage('Check the original capture request before continuing.');}
      else {setPending({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The outcome is unknown. Keep request reference ${result.requestKey} and check the original request.`); try {setPending(await restoreGrantCreation(context));} catch { /* Keep the reference visible. */ }}
    } catch {if (context.isCurrent()) {setMessage('The request could not be started safely. Check the original request and review the current device and receiver.'); try {setPending(await restoreGrantCreation(context));} catch {setPending(null);}}}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false);}}
  };
  const reasonForReview = review === 'retry' && original?.kind === 'owned' && typeof original.attempt?.intent.reason === 'string' ? original.attempt.intent.reason : reason.trim();
  return <Card className="operations-detail"><h2>Receiver capture access</h2><p>A capture grant permits receipt evidence for the selected device and receiver. It does not permit sending SMS or confirm payments.</p>
    {message && <p role="status">{message}</p>}
    {original?.kind === 'owned' && <section><h3>Original request</h3><p>Reference: <code>{original.requestKey}</code></p><Button onClick={() => void check()} disabled={busy}>Check original request</Button>{enabled && retryAvailable && original.attempt && <Button disabled={busy} onClick={() => {setConfirmed(false); setReview('retry');}}>Review identical retry</Button>}</section>}
    {original?.kind === 'foreign' && <p>Another account or session has an unresolved capture request. The original account must check it.</p>}
    {enabled && ready && <form className="operations-action-form" onSubmit={event => void begin(event)}>
      <Button disabled={busy} onClick={() => void devices(0)}>Find active devices</Button>
      {devicePage && <><Field label="Active device" htmlFor="grant-device"><select id="grant-device" className="admin-input" value={device?.id ?? ''} onChange={event => setDevice(devicePage.rows.find(row => row.id === event.target.value) ?? null)} required disabled={busy}><option value="">Select a device</option>{devicePage.rows.map(row => <option key={row.id} value={row.id}>{row.label} · {row.installation_id}</option>)}</select></Field><div><Button disabled={busy || devicePage.offset === 0} onClick={() => void devices(Math.max(0, devicePage.offset - 25))}>Previous devices</Button><Button disabled={busy || devicePage.offset + devicePage.rows.length >= devicePage.total} onClick={() => void devices(devicePage.offset + 25)}>Next devices</Button></div></>}
      <Field label="Find receiver" htmlFor="grant-search"><input id="grant-search" className="admin-input" value={search} onChange={event => setSearch(event.target.value)} maxLength={200} disabled={busy} /></Field><Button disabled={busy} onClick={() => void payees(0)}>Find active receivers</Button>
      {payeePage && <><Field label="Active receiver" htmlFor="grant-payee"><select id="grant-payee" className="admin-input" value={payee?.id ?? ''} onChange={event => setPayee(payeePage.rows.find(row => row.id === event.target.value) ?? null)} required disabled={busy}><option value="">Select a receiver</option>{payeePage.rows.map(row => <option key={row.id} value={row.id}>{row.title} · {String(row.momo_number_or_code)} · {String(row.group_name)}</option>)}</select></Field><div><Button disabled={busy || payeePage.offset === 0} onClick={() => void payees(Math.max(0, payeePage.offset - 25))}>Previous receivers</Button><Button disabled={busy || payeePage.offset + payeePage.rows.length >= payeePage.total} onClick={() => void payees(payeePage.offset + 25)}>Next receivers</Button></div></>}
      <Field label="Capture access review reason" htmlFor="grant-create-reason"><textarea id="grant-create-reason" className="admin-input" value={reason} onChange={event => setReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy} /></Field><Button type="submit" variant="primary" disabled={busy || !device || !payee}>Review capture grant</Button>
    </form>}
    <Dialog open={review !== null} title={review === 'retry' ? 'Review identical capture retry' : 'Review receiver capture access'} onClose={() => {if (!busy) setReview(null);}} footer={<><Button onClick={() => setReview(null)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>{review === 'retry' ? 'Confirm identical retry' : 'Confirm capture grant'}</Button></>}>
      {targets && <><p>The grant records capture access only; it does not permit SMS sending or payment confirmation.</p><dl className="operations-facts"><div><dt>Device</dt><dd>{targets.device.label}</dd></div><div><dt>Device ID</dt><dd>{targets.device.id}</dd></div><div><dt>Application</dt><dd>{targets.device.app_id}</dd></div><div><dt>Installation</dt><dd>{targets.device.installation_id}</dd></div><div><dt>Device version</dt><dd>{targets.device.version}</dd></div><div><dt>Public key SHA-256</dt><dd>{targets.device.key_sha256}</dd></div><div><dt>Signing certificate SHA-256</dt><dd>{targets.device.signing_certificate_sha256}</dd></div><div><dt>Receiver</dt><dd>{targets.payee.label}</dd></div><div><dt>Receiver ID</dt><dd>{targets.payee.id}</dd></div><div><dt>Receiving group ID</dt><dd>{targets.payee.group_id}</dd></div><div><dt>Network</dt><dd>{targets.payee.network}</dd></div><div><dt>MoMo number or code</dt><dd>{targets.payee.momo_number_or_code}</dd></div><div><dt>Receiver version</dt><dd>{targets.payee.version}</dd></div><div><dt>Reason</dt><dd>{reasonForReview}</dd></div></dl><label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} disabled={busy} /> I reviewed the device, receiver and capture access.</label></>}
    </Dialog>
  </Card>;
}
