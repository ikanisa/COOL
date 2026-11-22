import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import {isJsonObject} from '../api/contracts';
import type {PendingIdentity} from '../features/core/pendingAttempt';
import {Button, Card, Dialog, Field} from '../ui';
import {useSession, type AdminUser} from './SessionProvider';
import {checkCloudflareTeam, readCloudflareTeamTarget, restoreCloudflareTeam, retryCloudflareTeam, submitCloudflareTeam,
  type CloudflareTeamAction, type CloudflareTeamContext, type CloudflareTeamPending, type CloudflareTeamResult} from './cloudflareTeamMutations';
import type {Team, TeamMember} from './teamDirectory';
import {TEAM_OWNER_EMAIL} from './teamPolicy';

/** Visible only when the caller selects the deployed Cloudflare recovery protocol. */
export function CloudflareTeamPanel({actor, epoch, team, allowMutations, onChanged, onVerify}: {actor: AdminUser; epoch: number; team: Team;
  allowMutations: boolean; onChanged: (message: string) => void; onVerify: () => void}) {
  const session = useSession(), permissionKey = JSON.stringify([...new Set(actor.permissions)].sort());
  const identity = useMemo<PendingIdentity>(() => ({id: actor.id, sessionId: actor.sessionId, email: actor.email, role: actor.role,
    permissions: JSON.parse(permissionKey) as string[], expiresAt: actor.expiresAt}),
  [actor.id, actor.sessionId, actor.email, actor.role, actor.expiresAt, permissionKey]);
  const scope = JSON.stringify([epoch, actor.id, actor.sessionId, actor.principalId, actor.mfaAt, permissionKey, actor.expiresAt]);
  const scopeRef = useRef(scope), gateRef = useRef(allowMutations), liveSession = useRef(session), busyRef = useRef(false);
  useLayoutEffect(() => {scopeRef.current = scope; return () => {scopeRef.current = '';};}, [scope]);
  useLayoutEffect(() => {gateRef.current = allowMutations; return () => {gateRef.current = false;};}, [allowMutations]);
  useLayoutEffect(() => {liveSession.current = session;}, [session]);
  const context = useMemo<CloudflareTeamContext | null>(() => actor.principalId ? {identity, principalId: actor.principalId, request: session.request,
    allowMutations, isEnabled: () => gateRef.current, current: () => scopeRef.current === scope &&
      liveSession.current.isRecentSensitiveVerification(epoch, identity.id, identity.sessionId)} : null,
  [actor.principalId, identity, session.request, allowMutations, scope, epoch]);
  const [pending, setPending] = useState<CloudflareTeamPending | null>(null), [busy, setBusy] = useState(false), [message, setMessage] = useState(''),
    [checked, setChecked] = useState(false), [review, setReview] = useState<{kind: 'new'; action: CloudflareTeamAction} | {kind: 'retry'; pending: CloudflareTeamPending} | null>(null),
    [email, setEmail] = useState(''), [name, setName] = useState(''), [role, setRole] = useState<'admin' | 'staff'>('staff');
  useEffect(() => {
    if (!context || !context.current()) return;
    let live = true;
    void restoreCloudflareTeam(context).then(value => {if (live && context.current()) setPending(value);})
      .catch(() => {if (live && context.current()) setMessage('Team recovery could not be verified in this browser.');});
    return () => {live = false;};
  }, [context]);
  const fresh = session.isRecentSensitiveVerification(epoch, actor.id, actor.sessionId);
  if (!actor.principalId) return <Card className="admin-security-card"><h2>Team request recovery</h2><p>The account principal could not be verified.</p></Card>;
  async function restore() {
    if (busyRef.current) return; busyRef.current = true; setBusy(true); setMessage(''); setChecked(false);
    try {const value = await restoreCloudflareTeam(context!); if (context!.current()) setPending(value);}
    catch {if (context!.current()) setMessage('Team recovery could not be verified in this browser.');}
    finally {busyRef.current = false; if (context!.current()) setBusy(false);}
  }
  async function check() {
    if (!pending || busyRef.current) return; busyRef.current = true; setBusy(true); setMessage(''); setChecked(false);
    try {
      const result = await checkCloudflareTeam(context!, pending); if (!context!.current()) return;
      if (!result) {setChecked(true); setMessage('No original team request was found. A retry can still perform the reviewed action.');}
      else if (result.emailStatus === 'unknown') setMessage('Invitation sending is unconfirmed. Keep the original reference; a new email is not sent automatically.');
      else {setPending(null); setMessage(result.operation === 'revoke' ? 'The original removal was recorded. Refresh current team access.' : 'The invitation was accepted for sending. Inbox delivery is not confirmed.'); onChanged('The original team request was recorded.');}
    } catch {if (context!.current()) setMessage('The original team request could not be verified. Keep its reference.');}
    finally {busyRef.current = false; if (context!.current()) setBusy(false);}
  }
  async function reviewTarget(kind: 'resend' | 'revoke', member: TeamMember) {
    if (!allowMutations || pending?.kind !== 'ready' || busyRef.current || !fresh) return;
    busyRef.current = true; setBusy(true); setMessage('');
    try {
      const target = await readCloudflareTeamTarget(context!, member.id);
      if (!context!.current() || !gateRef.current) return;
      if (target.email !== member.email || target.role !== member.role || target.accessStatus !== member.status) throw new Error('The team account changed.');
      if (kind === 'resend' && !target.canResend) throw new Error('The invitation history is unresolved.');
      setReview({kind:'new', action:{kind, member:target}});
    } catch {if (context!.current()) setMessage('The account or its invitation history changed. Refresh before continuing.');}
    finally {busyRef.current = false; if (context!.current()) setBusy(false);}
  }
  function invite(event: FormEvent) {
    event.preventDefault(); if (!allowMutations || !fresh || pending?.kind !== 'ready' || busyRef.current) return;
    setMessage(''); setReview({kind:'new', action:{kind:'invite', email, role, displayName:name}});
  }
  async function submit() {
    if (!review || !pending || busyRef.current || !allowMutations || !fresh) return;
    busyRef.current = true; setBusy(true); setMessage(''); setChecked(false);
    try {
      const result: CloudflareTeamResult = review.kind === 'new' && pending.kind === 'ready' ?
        await submitCloudflareTeam(context!, review.action, pending.revision) : review.kind === 'retry' ?
          await retryCloudflareTeam(context!, review.pending) : (() => {throw new Error('Review the original request.');})();
      if (!context!.current()) return;
      if (result.status === 'existing') {setPending(result.pending); setMessage('An original team request already needs review.');}
      else if (result.status === 'unknown') {setPending(await restoreCloudflareTeam(context!)); setMessage('Invitation sending is unconfirmed. Keep the original reference; a new email is not sent automatically.');}
      else {setPending(null); setEmail(''); setName(''); onChanged(result.receipt.operation === 'revoke' ? 'Access removal recorded. Refresh current team access.' : 'Invitation accepted for sending. Inbox delivery is not confirmed.');}
    } catch (error) {
      if (context!.current()) {
        setMessage(error instanceof Error ? error.message : 'The team request could not be confirmed.');
        try {setPending(await restoreCloudflareTeam(context!));} catch {/* Keep any visible original reference. */}
      }
    } finally {busyRef.current = false; if (context!.current()) {setBusy(false); setReview(null);}}
  }
  const action = review?.kind === 'new' ? review.action : null;
  return <Card className="admin-security-card"><h2>Team request recovery</h2>
    {!fresh && <><p>Complete a current authenticator check before reviewing team requests.</p><Button onClick={onVerify}>Verify authenticator</Button></>}
    {fresh && <><p>Original requests stay in this tab. Provider acceptance does not confirm inbox delivery.</p>
      <Button disabled={busy} onClick={() => void restore()}>Review pending team request</Button>
      {message && <p role="status">{message}</p>}
      {pending?.kind === 'foreign' && <p>Another account or session has an unresolved team request. Its original owner must review it.</p>}
      {pending?.kind === 'owned' && <><p>Original request: <code>{pending.requestKey}</code></p><Button disabled={busy} onClick={() => void check()}>Check original team request</Button>{' '}
        {allowMutations && checked && pending.attempt && <Button disabled={busy} onClick={() => setReview({kind:'retry', pending})}>Review same team request</Button>}
        {!pending.attempt && <p>The original intent or principal is unavailable. Keep the reference; retry is unavailable.</p>}</>}
      {allowMutations && pending?.kind === 'ready' && <><form onSubmit={invite}>
        <Field label="Team email" htmlFor="cf-team-email"><input id="cf-team-email" className="admin-input" type="email" required value={email} onChange={event => setEmail(event.target.value)} /></Field>
        <Field label="Team name" htmlFor="cf-team-name" hint="Optional"><input id="cf-team-name" className="admin-input" maxLength={120} value={name} onChange={event => setName(event.target.value)} /></Field>
        <Field label="Team role" htmlFor="cf-team-role"><select id="cf-team-role" className="admin-input" value={role} onChange={event => setRole(event.target.value as 'admin' | 'staff')}><option value="staff">Staff</option><option value="admin">Admin</option></select></Field>
        <Button type="submit" disabled={busy}>Review invitation</Button></form>
        {team.members.filter(member => member.role !== 'owner' && member.id !== actor.id && member.email !== TEAM_OWNER_EMAIL && member.status !== 'revoked').map(member =>
          <div key={member.id}><h3>{member.displayName || member.email}</h3>{member.status === 'invited' && <Button disabled={busy} onClick={() => void reviewTarget('resend', member)}>Review resend</Button>}{' '}
            <Button variant="danger" disabled={busy} onClick={() => void reviewTarget('revoke', member)}>Review access removal</Button></div>)}
      </>}
    </>}
    {review && <Dialog open title={review.kind === 'retry' ? 'Retry original team request?' : action?.kind === 'invite' ? 'Invite teammate?' : action?.kind === 'resend' ? 'Resend invitation?' : 'Remove team access?'}
      onClose={() => {if (!busy) setReview(null);}} footer={<><Button disabled={busy} onClick={() => setReview(null)}>Cancel</Button><Button variant={action?.kind === 'revoke' ? 'danger' : 'primary'} disabled={busy} onClick={() => void submit()}>{review.kind === 'retry' ? 'Retry same request' : 'Confirm team request'}</Button></>}>
      {review.kind === 'retry' ? <><p>This retry may perform the original action if it never committed. It uses the same reference and details.</p><p>Original reference: <code>{review.pending.kind === 'owned' ? review.pending.requestKey : ''}</code></p>
        {review.pending.kind === 'owned' && review.pending.attempt && <><p>Action: {String(review.pending.attempt.intent.operation)}</p><p>Email: {String(review.pending.attempt.intent.email)}</p><p>Role: {String(review.pending.attempt.intent.role)}</p>
          {isJsonObject(review.pending.attempt.intent.body) && Object.entries(review.pending.attempt.intent.body).filter(([key]) => !['email','role'].includes(key)).map(([key,value]) => <p key={key}>{key}: {String(value)}</p>)}</>}</> :
        <><p>Account: {action?.kind === 'invite' ? action.email : action?.member.email}</p><p>Role: {action?.kind === 'invite' ? action.role : action?.member.role}</p>{action?.kind === 'invite' && <p>Name: {action.displayName || 'Not provided'}</p>}
          <p>{action?.kind === 'revoke' ? 'This removes access. Refresh the team list after the request is recorded.' : 'Email acceptance does not confirm inbox delivery.'}</p></>}
    </Dialog>}
  </Card>;
}
