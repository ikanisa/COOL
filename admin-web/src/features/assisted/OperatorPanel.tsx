import {useEffect, useRef, useState} from 'react';
import {useSession} from '../../session/SessionProvider';
import type {PendingAttempt} from '../core/pendingAttempt';
import {Button, Card, Dialog, Field} from '../../ui';
import type {AssistedJob, AssistedObservation} from './assistedContracts';
import {AssistedOperator, OperatorOutcomeUnknown, type AssistedSmsSender, type OperatorManualLookup} from './operatorWorkflow';

type Confirmation = {kind: 'claim'; job: AssistedJob} | {kind: 'release' | 'start' | 'outcome'};
const HASH = /^[a-f0-9]{64}$/;
const observationLabel = (value: AssistedObservation) => value === 'observed_sent' ? 'Observed sent' : value === 'failed_no_send' ? 'Failed without sending' : 'Uncertain';

export function OperatorPanel({jobs, allowWrites, sender, onBusyChange, onRefresh}: {jobs: readonly AssistedJob[]; allowWrites: boolean; sender?: AssistedSmsSender; onBusyChange: (busy: boolean) => void; onRefresh: () => void}) {
  const session = useSession(), actor = session.user!, epoch = session.epoch;
  const [operator] = useState(() => new AssistedOperator({allowWrites, epoch, identity: {id: actor.id, sessionId: actor.sessionId, email: actor.email, role: actor.role, permissions: actor.permissions, expiresAt: actor.expiresAt, principalId: actor.principalId!}, request: session.request, verifyFresh: session.verificationMode === 'email' ? session.recheckSensitiveEmailVerification : async () => session.isRecentSensitiveVerification(epoch, actor.id, actor.sessionId), isCurrent: () => document.visibilityState === 'visible' && session.isRecentSensitiveVerification(epoch, actor.id, actor.sessionId), sender}));
  const [view, setView] = useState(() => operator.view()), [pending, setPending] = useState<PendingAttempt[] | null>(null);
  const [lookupId, setLookupId] = useState(''), [lookup, setLookup] = useState<OperatorManualLookup | null>(null);
  const [busy, setBusy] = useState(false), [message, setMessage] = useState(''), [error, setError] = useState('');
  const [checked, setChecked] = useState(false), [confirm, setConfirm] = useState<Confirmation | null>(null);
  const [observation, setObservation] = useState<AssistedObservation>('uncertain'), [evidence, setEvidence] = useState('');
  const lifecycle = useRef(0), unresolved = !!pending?.length;
  useEffect(() => {onBusyChange(busy); return () => onBusyChange(false);}, [busy, onBusyChange]);
  useEffect(() => () => {lifecycle.current++; operator.dispose();}, [operator]);
  useEffect(() => {
    if (!view.expiresAt) return;
    const timer = setTimeout(() => {lifecycle.current++; operator.invalidate(); setView(operator.view()); setChecked(false); setConfirm(null); setPending(null); setBusy(false); setMessage('The claim or confirmation expired. Refresh pending jobs.');}, Math.max(0, Date.parse(view.expiresAt) - Date.now()));
    return () => clearTimeout(timer);
  }, [operator, view.expiresAt]);
  function capture() {
    const next = operator.view(); setView(next);
    if (next.observation && next.evidenceReferenceSha256) {setObservation(next.observation); setEvidence(next.evidenceReferenceSha256);}
  }
  async function perform(work: () => Promise<unknown>, success: string, refresh = false) {
    if (busy) return; const task = lifecycle.current; setBusy(true); setError(''); setMessage(''); setConfirm(null);
    try {
      await work();
      if (task === lifecycle.current) {capture(); setMessage(success); if (refresh) onRefresh();}
    } catch (failure) {
      if (task === lifecycle.current) {
        capture(); setChecked(false);
        if (failure instanceof OperatorOutcomeUnknown) setPending([failure.checkpoint]);
        setError(failure instanceof Error ? failure.message : 'The assisted SMS operation could not be confirmed.');
      }
    } finally {if (task === lifecycle.current) setBusy(false);}
  }
  async function checkOriginal(saved: PendingAttempt) {
    if (busy) return; const task = lifecycle.current; setBusy(true); setError(''); setMessage('');
    try {
      const found = await operator.checkOriginal(saved);
      if (task === lifecycle.current) {capture(); if (found.observed) {setPending((items) => items?.filter((item) => item.request_key !== saved.request_key) ?? null); setMessage('The original operation was recorded. No sending authority was recovered.');} else setMessage('No recorded result was observed. Keep the original request reference.');}
    } catch (failure) {if (task === lifecycle.current) setError(failure instanceof Error ? failure.message : 'The original operation could not be checked.');}
    finally {if (task === lifecycle.current) setBusy(false);}
  }
  async function review() {
    if (busy) return; const task = lifecycle.current; setBusy(true); setError(''); setMessage('');
    try {const saved = await operator.listOriginals(); if (task === lifecycle.current) setPending(saved);}
    catch (failure) {if (task === lifecycle.current) setError(failure instanceof Error ? failure.message : 'The original operations could not be loaded.');}
    finally {if (task === lifecycle.current) setBusy(false);}
  }
  async function lookupById() {
    if (busy) return; const task = lifecycle.current; setBusy(true); setError(''); setMessage(''); setLookup(null);
    try {
      const found = await operator.lookupOriginal(lookupId);
      if (task === lifecycle.current) {
        setLookup(found); capture();
        if (found.observed) setPending((items) => items?.filter((item) => item.request_key.toLowerCase() !== found.requestId) ?? null);
        if (found.action === 'record_send_start') {setObservation('uncertain'); setEvidence('');}
        setMessage(found.observed ? 'The original operation was recorded. No sending authority was recovered.' : 'No recorded result was observed. Keep the original request reference.');
      }
    } catch (failure) {if (task === lifecycle.current) setError(failure instanceof Error ? failure.message : 'The original operation could not be checked.');}
    finally {if (task === lifecycle.current) setBusy(false);}
  }
  function selectAttempt(job: AssistedJob) {
    if (busy || unresolved) return;
    try {operator.selectAttempt(job); capture(); setObservation('uncertain'); setEvidence(''); setError('');}
    catch (failure) {setError(failure instanceof Error ? failure.message : 'The SMS attempt could not be selected.');}
  }
  async function start() {
    if (busy) return; const task = lifecycle.current; setBusy(true); setConfirm(null); setError(''); setMessage('');
    try {
      const result = await operator.startAndSend();
      if (task === lifecycle.current) {capture(); setChecked(false); setMessage(result.adapterResultUnknown ? 'The sender result is unknown. Record an observation using retained evidence.' : result.sentToAdapter ? 'The sender accepted the one-time handoff. Delivery is not confirmed.' : result.permitIssued ? 'No SMS handoff was made. The recorded start cannot be reused.' : 'No sending authority was issued. Review the recorded attempt.');}
    } catch (failure) {if (task === lifecycle.current) {capture(); setChecked(false); if (failure instanceof OperatorOutcomeUnknown) setPending([failure.checkpoint]); setError(failure instanceof Error ? failure.message : 'The send start could not be confirmed.');}}
    finally {if (task === lifecycle.current) setBusy(false);}
  }
  const disabled = busy || unresolved || !allowWrites;
  return <Card><h2>Assisted SMS operations</h2><p>Original operations stay tied to this sign-in. An observation does not confirm delivery or settlement.</p>
    {!allowWrites && <p>Changes to assisted SMS operations are currently unavailable.</p>}
    <Button disabled={busy} onClick={() => void review()}>Review original operations</Button>
    {pending?.length === 0 && <p>No original operations were found in this tab.</p>}
    {pending?.map((saved) => <div key={saved.request_key}><p>{String(saved.intent.action).replaceAll('_', ' ')} · {saved.request_key}</p><Button disabled={busy} onClick={() => void checkOriginal(saved)}>Check original operation</Button></div>)}
    <form onSubmit={(event) => {event.preventDefault(); void lookupById();}}><Field label="Original operation UUID" htmlFor="assisted-lookup"><input className="admin-input" id="assisted-lookup" value={lookupId} onChange={(event) => setLookupId(event.target.value)} autoComplete="off" spellCheck={false} disabled={busy} /></Field><Button type="submit" disabled={busy}>Check original UUID</Button></form>
    {lookup?.observed && <div><h3>Recorded operation</h3><p>Original UUID: {lookup.requestId}<br />Action: {lookup.action?.replaceAll('_', ' ')}<br />Resource ID: {lookup.resourceId}{lookup.attemptId && <><br />Attempt ID: {lookup.attemptId}</>}{lookup.observation && <><br />Observation: {observationLabel(lookup.observation)}<br />Evidence reference SHA-256: <code>{lookup.evidenceReferenceSha256}</code></>}<br />Delivery confirmed: No<br />Provider confirmation: No<br />Settlement: Not asserted</p></div>}
    {allowWrites && !view.jobId && <div><h3>Available jobs</h3>{jobs.filter((job) => job.state === 'queued' || job.state === 'claimed' || job.attempt_id).map((job) => <div key={job.id}><p>Job {job.id}</p>{job.attempt_id ? <Button disabled={disabled} onClick={() => selectAttempt(job)}>Record observation</Button> : <Button disabled={disabled || view.attemptId !== null} onClick={() => setConfirm({kind: 'claim', job})}>Claim for review</Button>}</div>)}</div>}
    {view.jobId && <div><h3>Current claim</h3><p>Job: {view.jobId}<br />Expires: {view.expiresAt}</p>{view.destination && view.message ? <><p>Recipient: {view.destination}<br />Recipient digest: <code>{view.destinationHash}</code><br />Destination revision: {view.destinationRevision}</p><p>Message: {view.message}<br />Message digest: <code>{view.bodyHash}</code></p>{!view.confirmed && <label><input type="checkbox" checked={checked} disabled={disabled} onChange={(event) => setChecked(event.target.checked)} /> I checked this exact recipient and message.</label>}</> : <Button disabled={disabled} onClick={() => void perform(() => operator.loadContent(), 'Exact content loaded.')}>Load exact content</Button>}
      {view.confirmed && <p>The exact recipient and message are confirmed for this sign-in.</p>}{!sender && <p>A native SMS sender is unavailable. Sending is disabled.</p>}
      {view.destination && !view.confirmed && <Button variant="primary" disabled={disabled || !checked} onClick={() => void perform(() => operator.confirm(checked), 'Exact content confirmed.')}>Confirm exact content</Button>}
      {view.confirmed && sender && <Button variant="primary" disabled={disabled} onClick={() => setConfirm({kind: 'start'})}>Record start and send once</Button>}
      <Button disabled={disabled} onClick={() => setConfirm({kind: 'release'})}>Release claim</Button>
    </div>}
    {view.attemptId && allowWrites && <div><h3>Record observed outcome</h3><p>Attempt: {view.attemptId}</p><Field label="Observed outcome" htmlFor="assisted-observation"><select className="admin-input" id="assisted-observation" value={observation} disabled={disabled} onChange={(event) => setObservation(event.target.value as AssistedObservation)}><option value="uncertain">Uncertain</option><option value="observed_sent">Observed sent</option><option value="failed_no_send">Failed without sending</option></select></Field><Field label="Evidence reference SHA-256" htmlFor="assisted-evidence" hint="64 lowercase hexadecimal characters"><input className="admin-input" id="assisted-evidence" value={evidence} disabled={disabled} onChange={(event) => setEvidence(event.target.value.trim())} /></Field><Button variant="primary" disabled={disabled || !HASH.test(evidence)} onClick={() => setConfirm({kind: 'outcome'})}>Record observation</Button></div>}
    {error && <p role="alert">{error}</p>}{message && <p role="status">{message}</p>}
    <Dialog open={confirm !== null} title={confirm?.kind === 'claim' ? 'Claim this SMS job?' : confirm?.kind === 'release' ? 'Release this claim?' : confirm?.kind === 'start' ? 'Send this SMS once?' : 'Record this observation?'} onClose={() => {if (!busy) setConfirm(null);}} footer={<><Button disabled={busy} onClick={() => setConfirm(null)}>Cancel</Button><Button variant="primary" disabled={disabled} onClick={() => {if (confirm?.kind === 'claim') void perform(() => operator.claim(confirm.job), 'Claim recorded. Load and review the exact content.'); else if (confirm?.kind === 'release') void perform(() => operator.release(), 'Claim released. Refresh the queue.', true); else if (confirm?.kind === 'start') void start(); else if (confirm?.kind === 'outcome') void perform(() => operator.recordOutcome(observation, evidence, true), 'Observation recorded. Delivery is not confirmed.', true);}}>{confirm?.kind === 'claim' ? 'Claim job' : confirm?.kind === 'release' ? 'Release claim' : confirm?.kind === 'start' ? 'Send once' : 'Record observation'}</Button></>}><p>{confirm?.kind === 'claim' ? `Claim job ${confirm.job.id} using its current fence.` : confirm?.kind === 'release' ? 'Release the current claim without sending.' : confirm?.kind === 'start' ? 'Record the start and hand the verified content to the approved sender once.' : `Record ${observationLabel(observation)} for attempt ${view.attemptId}. This does not confirm delivery.`}</p></Dialog>
  </Card>;
}
