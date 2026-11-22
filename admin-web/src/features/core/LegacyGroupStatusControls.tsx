import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Button, Card, LoadingState } from '../../ui';
import { currentLegacyGroup, type LegacyGroupSnapshot } from './legacyGroupRecords';
import { buildLegacyGroupStatusIntent, currentLegacyGroupStatusSource, lookupLegacyGroupStatus, parseLegacyGroupStatusIntent, restoreLegacyGroupStatus, retryLegacyGroupStatus, sameLegacyGroupStatusIntent, submitLegacyGroupStatus, type LegacyGroupStatus, type LegacyGroupStatusContext, type LegacyGroupStatusIntent, type LegacyGroupStatusPending, type LegacyGroupStatusSource, } from './legacyGroupStatus';
export function LegacyGroupStatusControls({ context, enabled, onBlocked, onRecorded }: {
  context: LegacyGroupStatusContext;
  enabled: boolean;
  onBlocked: (value: boolean) => void;
  onRecorded: () => void;
}) {
  const [pending, setPending] = useState<LegacyGroupStatusPending | null>(null), [group, setGroup] = useState<LegacyGroupSnapshot | null>(null), [loaded, setLoaded] = useState(false);
  const [state, setState] = useState<'loading' | 'ready' | 'checking' | 'sending' | 'error'>('loading'), [message, setMessage] = useState(''), [retry, setRetry] = useState(false);
  const [status, setStatus] = useState<LegacyGroupStatus>('active'), [reason, setReason] = useState(''), [review, setReview] = useState<{
    intent: LegacyGroupStatusIntent;
    source: LegacyGroupStatusSource;
    revision: string;
    retry: boolean;
  } | null>(null), [confirmed, setConfirmed] = useState(false), busy = useRef(false);
  useEffect(() => {
    let live = true;
    restoreLegacyGroupStatus(context).then(async (saved) => {
      const current = saved.kind === 'ready' && enabled ? await currentLegacyGroup(context, true) : null;
      if (live && context.isCurrent()) {
        setPending(saved);
        setGroup(current);
        if (current)
          setStatus(current.status === 'active' ? 'suspended' : 'active');
        setLoaded(true);
        setState('ready');
        onBlocked(saved.kind !== 'ready');
      }
    }).catch(() => { if (live && context.isCurrent()) {
      setLoaded(true);
      setState('error');
      setMessage('Group status recovery could not be verified.');
      onBlocked(true);
    } });
    return () => { live = false; };
  }, [context, enabled, onBlocked]);
  if (!loaded)
    return <LoadingState label="Checking group status recovery"/>;
  const unresolved = pending && pending.kind !== 'ready' ? pending : null, ready = pending?.kind === 'ready' ? pending : null;
  if (!enabled && !unresolved && state !== 'error')
    return null;
  const prepare = async (event: FormEvent) => {
    event.preventDefault();
    if (!enabled || !ready || !group || group.status === 'archived' || busy.current || !context.isCurrent())
      return;
    busy.current = true;
    setState('checking');
    setMessage('');
    try {
      const source = await currentLegacyGroupStatusSource(context, status);
      if (JSON.stringify(source.group) !== JSON.stringify(group))
        throw new Error('Group changed');
      const intent = buildLegacyGroupStatusIntent(source, status, reason);
      if (context.isCurrent() && context.isEnabled?.()) {
        setReview({ intent, source, revision: ready.revision, retry: false });
        setConfirmed(false);
      }
    }
    catch {
      if (context.isCurrent())
        setMessage('The group, active owner or receiver could not be verified. Review the current records and reason.');
    }
    finally {
      busy.current = false;
      if (context.isCurrent())
        setState(previous => previous === 'checking' ? 'ready' : previous);
    }
  };
  const check = async () => {
    if (unresolved?.kind !== 'owned' || busy.current || !context.isCurrent())
      return;
    busy.current = true;
    setState('checking');
    setMessage('');
    setRetry(false);
    try {
      const result = await lookupLegacyGroupStatus(context, unresolved);
      if (!context.isCurrent())
        return;
      if (result.status === 'succeeded' && result.verifiedIntent) {
        setPending(null);
        onBlocked(false);
        onRecorded();
      }
      else if (result.status === 'succeeded')
        setMessage(`The server recorded group request ${result.receipt.requestId}, but its original intent is unavailable. Keep the reference for investigation.`);
      else if (result.status === 'not_found') {
        setRetry(result.retryAvailable && enabled);
        setMessage(result.retryAvailable ? (enabled ? 'No server receipt was found. Review the same request before an explicit retry.' : 'No server receipt was found. Keep the original reference; status changes are not enabled.') : 'No server receipt was found. Keep the original reference; its intent cannot be retried here.');
      }
      else
        setMessage('The original group status request remains unresolved. Keep its reference and check again.');
    }
    catch {
      if (context.isCurrent())
        setMessage('The original group status could not be verified. Keep the reference and check again.');
    }
    finally {
      busy.current = false;
      if (context.isCurrent())
        setState(previous => previous === 'checking' ? 'ready' : previous);
    }
  };
  const reviewSame = async () => {
    if (unresolved?.kind !== 'owned' || !unresolved.attempt || !retry || !enabled || busy.current || !context.isCurrent())
      return;
    busy.current = true;
    setState('checking');
    setMessage('');
    try {
      const intent = parseLegacyGroupStatusIntent(unresolved.attempt.intent), source = await currentLegacyGroupStatusSource(context, intent.status), current = buildLegacyGroupStatusIntent(source, intent.status, intent.reason);
      if (!sameLegacyGroupStatusIntent(current, intent))
        throw new Error('Source changed');
      if (context.isCurrent() && context.isEnabled?.()) {
        setReview({ intent, source, revision: '', retry: true });
        setConfirmed(false);
      }
    }
    catch {
      if (context.isCurrent()) {
        setRetry(false);
        setMessage('The original group, owner or receiver changed. Check the request before continuing.');
      }
    }
    finally {
      busy.current = false;
      if (context.isCurrent())
        setState(previous => previous === 'checking' ? 'ready' : previous);
    }
  };
  const send = async () => {
    if (!review || !confirmed || !enabled || busy.current || !context.isCurrent())
      return;
    busy.current = true;
    setState('sending');
    setMessage('');
    setRetry(false);
    try {
      const result = review.retry ? await retryLegacyGroupStatus(context, unresolved!) : await submitLegacyGroupStatus(context, review.intent, review.source, review.revision);
      if (!context.isCurrent())
        return;
      if (result.status === 'succeeded') {
        setPending(null);
        onBlocked(false);
        onRecorded();
      }
      else if (result.status === 'existing') {
        setPending(result.pending);
        onBlocked(result.pending.kind !== 'ready');
        setMessage('A group request needs recovery.');
      }
      else {
        setPending({ kind: 'owned', requestKey: result.requestKey, attempt: null });
        onBlocked(true);
        setMessage(`The result is unconfirmed. Keep request reference ${result.requestKey} and check the original request.`);
        try {
          const saved = await restoreLegacyGroupStatus(context);
          if (context.isCurrent())
            setPending(saved);
        }
        catch { /* Keep the reference visible. */ }
      }
    }
    catch {
      if (context.isCurrent()) {
        setMessage('The group status or recovery data could not be verified. Check the original request.');
        try {
          const saved = await restoreLegacyGroupStatus(context);
          if (context.isCurrent()) {
            setPending(saved);
            onBlocked(saved.kind !== 'ready');
          }
        }
        catch {
          if (context.isCurrent()) {
            setState('error');
            onBlocked(true);
          }
        }
      }
    }
    finally {
      busy.current = false;
      if (context.isCurrent()) {
        setState(previous => previous === 'sending' ? 'ready' : previous);
        setReview(null);
        setConfirmed(false);
      }
    }
  };
  return <Card><div className="core-detail"><h2>Group status</h2>{message && <p role="status">{message}</p>}
  {state === 'error' && <p>The original group request must be verified before changing status.</p>}
  {unresolved?.kind === 'foreign' && <p>Another account or session has an unresolved group request. The original account must check it.</p>}
  {unresolved?.kind === 'older' && <p>Resolve the existing group edit request above before changing status.</p>}
  {unresolved?.kind === 'owned' && <section><h3>Original status request</h3><p>Reference: <code>{unresolved.requestKey}</code></p>{!unresolved.attempt && <p>The original form is unavailable. Keep this reference and check the request.</p>}
    <Button type="button" disabled={state !== 'ready'} onClick={() => void check()}>Check status request</Button>{enabled && retry && <Button type="button" disabled={state !== 'ready'} onClick={() => void reviewSame()}>Review same status request</Button>}</section>}
  {enabled && ready && group?.status === 'archived' && <p>This archived group cannot be changed or reopened.</p>}
  {enabled && ready && group && group.status !== 'archived' && !review && <form className="core-edit-form" onSubmit={event => void prepare(event)}><p>Current status: {group.status} · version {group.version}. Activation requires the current active owner and receiver. Archiving is permanent.</p>
    <label>New group status<select className="admin-input" value={status} onChange={event => setStatus(event.target.value as LegacyGroupStatus)}>{(['draft', 'active', 'suspended', 'archived'] as const).map(value => <option key={value} value={value} disabled={value === group.status}>{value}</option>)}</select></label>
    <label>Reason for status change<textarea className="admin-input" value={reason} minLength={8} maxLength={1000} required onChange={event => setReason(event.target.value)}/></label><Button type="submit" variant="primary" disabled={state !== 'ready'}>Review status change</Button></form>}
  {enabled && review && <section><h3>{review.retry ? 'Review same status request' : 'Review group status'}</h3><p>Group: {review.source.group.title} · {review.source.group.status} → {review.intent.status} · version {review.source.group.version}.</p>
    {review.source.activation && <p>Active owner: {review.source.activation.owner.displayName ?? 'Name not recorded'} · {review.source.activation.owner.id} · user version {review.source.activation.owner.version} · membership version {review.source.activation.membershipVersion}.<br />Active receiver: {review.source.activation.receiver.label} · {review.source.activation.receiver.id} · {review.source.activation.receiver.network} · {review.source.activation.receiver.route} · version {review.source.activation.receiver.version}.</p>}
    <p>Reason: {review.intent.reason}</p>{review.intent.status === 'archived' && <p>Archiving is permanent; the group cannot be reopened.</p>}{review.retry && <p>The same original request may change the group if the earlier request did not commit.</p>}
    <label><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)}/> I reviewed the status and current group records.</label><Button type="button" disabled={state !== 'ready'} onClick={() => { setReview(null); setConfirmed(false); }}>Cancel</Button><Button type="button" variant="primary" disabled={state !== 'ready' || !confirmed} onClick={() => void send()}>{review.retry ? 'Confirm same status request' : 'Confirm status change'}</Button></section>}
  </div></Card>;
}
