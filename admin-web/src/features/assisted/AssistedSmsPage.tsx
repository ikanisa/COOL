import {useEffect, useState} from 'react';
import type {JsonObject} from '../../api/client';
import {sensitiveVerificationDeadline, useSession} from '../../session/SessionProvider';
import {Button, Card, EmptyState, ErrorState, LoadingState, PageHeader, StatusBadge} from '../../ui';
import {OperatorPanel} from './OperatorPanel';
import {ASSISTED_PAGE_SIZE, parseAssistedPage, type AssistedCursor, type AssistedPage, type JobState} from './assistedContracts';
import type {AssistedSmsSender} from './operatorWorkflow';

function stateLabel(state: JobState) {
  return state === 'send_started' ? 'Send started' : state === 'uncertain' ? 'Uncertain' : state === 'claimed' ? 'Claimed' : 'Queued';
}
function dateLabel(value: string) {
  return new Intl.DateTimeFormat('en-GB', {timeZone: 'Africa/Kigali', dateStyle: 'medium', timeStyle: 'short'}).format(new Date(value));
}

export function AssistedSmsPage({onVerify, allowWrites = false, sender}: {onVerify: () => void; allowWrites?: boolean; sender?: AssistedSmsSender}) {
  const session = useSession(), user = session.user;
  if (!user || !user.permissions.includes('assisted_sms.read') || !user.principalId) return <><PageHeader title="Assisted SMS" /><ErrorState title="Access unavailable" message="Your account cannot open the assisted SMS queue." /></>;
  return <Queue key={JSON.stringify([session.epoch, user.id, user.sessionId, allowWrites])} onVerify={onVerify} allowWrites={allowWrites} sender={sender} />;
}

function Queue({onVerify, allowWrites, sender}: {onVerify: () => void; allowWrites: boolean; sender?: AssistedSmsSender}) {
  const session = useSession(), user = session.user!;
  const {epoch, request, recheckSensitiveEmailVerification, isRecentSensitiveVerification, verificationMode} = session;
  const actorId = user.id, sessionId = user.sessionId;
  const deadline = sensitiveVerificationDeadline(user, verificationMode === 'email' ? 'supabase' : 'cloudflare') ?? 0;
  const [clock, setClock] = useState(() => Date.now()), [pageCursor, setPageCursor] = useState<AssistedCursor | null>(null);
  const [foreground, setForeground] = useState(() => document.visibilityState === 'visible');
  const [previous, setPrevious] = useState<(AssistedCursor | null)[]>([]), [revision, setRevision] = useState(0);
  const [operatorBusy, setOperatorBusy] = useState(false);
  const [result, setResult] = useState<{key: string; page: AssistedPage} | {key: string; error: string} | null>(null);
  const cursorKey = pageCursor ? `${pageCursor.after_created_at}:${pageCursor.after_job_id}` : 'first';
  const key = `${epoch}:${cursorKey}:${revision}`;
  const allowed = foreground && clock <= deadline && isRecentSensitiveVerification(epoch, actorId, sessionId);
  useEffect(() => {
    const changed = () => {const visible = document.visibilityState === 'visible'; if (!visible) setRevision((value) => value + 1); setForeground(visible);};
    document.addEventListener('visibilitychange', changed);
    return () => document.removeEventListener('visibilitychange', changed);
  }, []);
  useEffect(() => {
    if (!deadline) return;
    const timer = setTimeout(() => setClock(Date.now()), Math.max(0, deadline - Date.now() + 1));
    return () => clearTimeout(timer);
  }, [deadline]);
  useEffect(() => {
    if (!allowed) return;
    let active = true;
    const current = () => active && isRecentSensitiveVerification(epoch, actorId, sessionId);
    void (async () => {
      try {
        if (verificationMode === 'email' && !(await recheckSensitiveEmailVerification())) throw new Error('Verify your email to open the assisted SMS queue.');
        if (!current()) return;
        const body: JsonObject = {action: 'list_pending', limit: ASSISTED_PAGE_SIZE};
        if (pageCursor) {body.after_created_at = pageCursor.after_created_at; body.after_job_id = pageCursor.after_job_id;}
        const response = await request('notification-operator', {method: 'POST', body, authenticated: true});
        if (!current()) return;
        const page = parseAssistedPage(response, pageCursor);
        if (current()) setResult({key, page});
      } catch {
        if (current()) setResult({key, error: 'The assisted SMS queue could not be loaded. Refresh to try again.'});
      }
    })();
    return () => {active = false;};
  }, [actorId, allowed, epoch, isRecentSensitiveVerification, key, pageCursor, recheckSensitiveEmailVerification, request, sessionId, verificationMode]);
  const current = result?.key === key ? result : null;
  return <><PageHeader title="Assisted SMS" subtitle="Review the current internal SMS queue." actions={<Button icon="refresh" disabled={!allowed || !current || operatorBusy} onClick={() => setRevision((value) => value + 1)}>Refresh</Button>} />
    {!foreground ? <Card><p>The queue is hidden while this tab is inactive.</p></Card> : !allowed ? <Card><h2>Verification required</h2><p>{verificationMode === 'email' ? 'Verify your email to open this queue.' : 'Verify your authenticator to open this queue.'}</p><Button onClick={onVerify}>{verificationMode === 'email' ? 'Verify email' : 'Verify authenticator'}</Button></Card> :
      <><p>These are internal records. Sending and delivery are not confirmed by this list.</p><Card><h2>Pending SMS jobs</h2>
        {!current ? <LoadingState label="Loading assisted SMS jobs" /> : 'error' in current ? <ErrorState message={current.error} onRetry={() => setRevision((value) => value + 1)} /> : current.page.items.length === 0 ? <EmptyState title="No pending SMS jobs" /> : <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th scope="col">Job ID</th><th scope="col">Payment ID</th><th scope="col">Status</th><th scope="col">Created</th><th scope="col">Fence</th><th scope="col">Attempt ID</th></tr></thead><tbody>{current.page.items.map((job) => <tr key={job.id}><td>{job.id}</td><td>{job.payment_id}</td><td><StatusBadge tone={job.state === 'uncertain' ? 'warning' : 'info'}>{stateLabel(job.state)}</StatusBadge></td><td>{dateLabel(job.created_at)}</td><td>{job.fence}</td><td>{job.attempt_id ?? '—'}</td></tr>)}</tbody></table></div>}
        {current && 'page' in current && <div><Button disabled={operatorBusy || previous.length === 0} onClick={() => {setPageCursor(previous[previous.length - 1]); setPrevious((value) => value.slice(0, -1));}}>Previous jobs</Button> <Button disabled={operatorBusy || !current.page.next_cursor} onClick={() => {if (current.page.next_cursor) {setPrevious((value) => [...value, pageCursor]); setPageCursor(current.page.next_cursor);}}}>Next jobs</Button></div>}
      </Card>{current && 'page' in current && user.permissions.includes('assisted_sms.manage') && <OperatorPanel jobs={current.page.items} allowWrites={allowWrites} sender={sender} onBusyChange={setOperatorBusy} onRefresh={() => setRevision((value) => value + 1)} />}</>}
  </>;
}
