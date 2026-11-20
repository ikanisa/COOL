import {useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent} from 'react';
import type {JsonObject} from '../api/client';
import {listPending, type PendingAttempt, type PendingIdentity} from '../features/core/pendingAttempt';
import {Button, Card, Dialog, EmptyState, ErrorState, Field, LoadingState, PageHeader, StatusBadge} from '../ui';
import {useSession, type AdminUser} from './SessionProvider';
import {lookupInvitation, parseInvitationAttempt, parseInvitationReceipt, type InvitationAttempt, type InvitationReceipt} from './invitationRecovery';
import {checkCloudflareTeam, checkTeamInvitation, checkTeamRemoval, readCloudflareTeamTarget, removeTeamAccess, restoreCloudflareTeam,
  retryCloudflareTeam, retryTeamInvitation, submitCloudflareTeam, submitTeamInvitation, type CloudflareTeamAction, type CloudflareTeamContext,
  type CloudflareTeamPending, type CloudflareTeamResult, type InvitationAction, type TeamMutationContext} from './teamMutations';
import './auth.css';

interface TeamMember {
  id: string;
  email: string;
  role: 'owner' | 'admin' | 'staff';
  status: 'active' | 'invited' | 'revoked';
  displayName: string | null;
  publicId: string | null;
  emailStatus: string | null;
  invitationKind: 'auth_invite' | 'access_notice' | null;
  invitation: InvitationReceipt | null;
  invitationRequestId: string | null;
  invitationOperation: 'invite' | 'resend' | null;
}
interface Team {currentEmail: string; canManage: boolean; contractVersion: 1 | 2; members: TeamMember[]; permissionsByRole: Record<string, string[]>}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function object(value: unknown): value is JsonObject {return !!value && typeof value === 'object' && !Array.isArray(value);}

export function parseTeam(body: JsonObject, actor: AdminUser, allowLegacyStatus = false): Team {
  if (body.currentEmail !== actor.email || typeof body.canManage !== 'boolean' || !Array.isArray(body.members) || body.members.length > 1000 || !object(body.permissionsByRole)) throw new Error('The team list could not be verified.');
  if (body.canManage && (actor.role !== 'owner' || actor.email.toLowerCase() !== 'info@ikanisa.com' || !actor.permissions.includes('admin_users.manage'))) throw new Error('The team management authority could not be verified.');
  const v2 = Object.hasOwn(body, 'contractVersion');
  if (v2 && (body.contractVersion !== 2 || body.canManage !== true)) throw new Error('The team invitation version could not be verified.');
  const permissionsByRole: Record<string, string[]> = {};
  for (const [role, values] of Object.entries(body.permissionsByRole)) {
    if (!['owner', 'admin', 'staff'].includes(role) || !Array.isArray(values) || !values.every((value) => typeof value === 'string')) throw new Error('The team access policy could not be verified.');
    permissionsByRole[role] = values as string[];
  }
  const seen = new Set<string>();
  const members = body.members.map((value): TeamMember => {
    if (!object(value) || typeof value.id !== 'string' || !value.id || value.id.length > 200 || seen.has(value.id) || typeof value.email !== 'string' || !value.email || !['owner', 'admin', 'staff'].includes(String(value.role)) || !['active', 'invited', 'revoked'].includes(String(value.status)) || (value.displayName != null && typeof value.displayName !== 'string') || (value.publicId != null && typeof value.publicId !== 'string') || (value.emailStatus != null && !['accepted', 'rejected', 'unknown', 'already_registered', ...(allowLegacyStatus ? ['failed', 'pending'] : [])].includes(String(value.emailStatus)))) throw new Error('The team list could not be verified.');
    let receipt: InvitationReceipt | null = null;
    const requestId = value.invitationRequestId ?? null, operation = value.invitationOperation ?? null;
    if (v2) {
      if (!Object.hasOwn(value, 'invitation') || Object.hasOwn(value, 'emailStatus') || Object.hasOwn(value, 'noticeStatus')) throw new Error('The team invitation could not be verified.');
      if (value.invitation !== null) {receipt = parseInvitationReceipt(value.invitation, 2); if (receipt.id !== value.id || receipt.accessStatus !== value.status) throw new Error('The team invitation target changed.');}
    } else if (!allowLegacyStatus) {
      const hasStatus = value.emailStatus != null;
      if ((requestId === null) !== (operation === null) || hasStatus !== (requestId !== null) || (requestId !== null && (typeof requestId !== 'string' || !UUID.test(requestId) || !['invite', 'resend'].includes(String(operation))))) throw new Error('The team invitation history could not be verified.');
    }
    seen.add(value.id);
    return {id: value.id, email: value.email, role: value.role as TeamMember['role'], status: value.status as TeamMember['status'], displayName: (value.displayName as string | null | undefined) ?? null, publicId: (value.publicId as string | null | undefined) ?? null, emailStatus: receipt?.status ?? (value.emailStatus as string | null | undefined) ?? null, invitationKind: receipt?.messageKind ?? (value.emailStatus != null ? 'auth_invite' : null), invitation: receipt, invitationRequestId: typeof requestId === 'string' ? requestId : null, invitationOperation: operation === 'invite' || operation === 'resend' ? operation : null};
  });
  return {currentEmail: body.currentEmail, canManage: body.canManage, contractVersion: v2 ? 2 : 1, members, permissionsByRole};
}

function invitationStatus(value: string | null, kind: TeamMember['invitationKind']): string | null {
  const label = kind === 'access_notice' ? 'Access notice' : 'Invitation';
  if (value === 'accepted') return `${label} accepted for sending`;
  if (value === 'rejected') return `${label} request rejected`;
  if (value === 'unknown') return `${label} sending unconfirmed`;
  if (value === 'failed') return 'Invitation email sending could not be confirmed';
  if (value === 'pending') return 'Invitation email sending is unconfirmed';
  if (value === 'already_registered') return 'Account already registered';
  return null;
}

export function TeamPage({onVerify, allowMutations = false, managedInvitationVersion = 2, cloudflareRecoveryVersion, allowRecovery = true, showVerification = true}: {onVerify: () => void; allowMutations?: boolean; managedInvitationVersion?: 1 | 2; cloudflareRecoveryVersion?: 1; allowRecovery?: boolean; showVerification?: boolean}) {
  const session = useSession(), actor = session.user, request = session.request, epoch = session.epoch;
  const [state, setState] = useState<{team: Team; epoch: number; actorId: string} | null>(null);
  const [error, setError] = useState(''), [loading, setLoading] = useState(true), [revision, setRevision] = useState(0);
  const [actionMessage, setActionMessage] = useState<{epoch: number; actorId: string; text: string} | null>(null);
  const allowed = actor?.permissions.includes('admin_users.read') === true;
  useEffect(() => {
    if (!actor || !allowed) return;
    let alive = true;
    const verifiedAt = actor.emailVerifiedAt ? Date.parse(actor.emailVerifiedAt) : NaN;
    const v2 = managedInvitationVersion === 2 && session.verificationMode === 'email' && actor.role === 'owner' && actor.email.toLowerCase() === 'info@ikanisa.com' && actor.permissions.includes('admin_users.manage') && Number.isFinite(verifiedAt) && verifiedAt <= Date.now() && Date.now() - verifiedAt <= 300_000;
    void request(v2 ? 'team/v2' : 'team', {authenticated: true}).then((body) => {
      if (!alive) return;
      setState({team: parseTeam(body, actor, session.verificationMode === 'authenticator'), epoch, actorId: actor.id}); setError('');
    }).catch((failure: unknown) => {if (alive) setError(failure instanceof Error ? failure.message : 'Team access could not be loaded.');})
      .finally(() => {if (alive) setLoading(false);});
    return () => {alive = false;};
  }, [request, actor, allowed, epoch, revision, session.verificationMode, managedInvitationVersion]);
  if (!actor || !allowed) return <ErrorState title="Access unavailable" message="Your account cannot view team access." />;
  const team = state?.epoch === epoch && state.actorId === actor.id ? state.team : null;
  const refresh = () => {setLoading(true); setRevision((value) => value + 1);};
  const resolved = (message: string) => {setActionMessage({epoch, actorId: actor.id, text: message}); refresh();};
  return <><PageHeader title="Team access" subtitle="Admins and staff who can use the Collect workspace." actions={<Button icon="refresh" onClick={refresh} disabled={loading}>Refresh</Button>} />
    {actionMessage?.epoch === epoch && actionMessage.actorId === actor.id && <p role="status">{actionMessage.text}</p>}
    {showVerification && actor.role === 'owner' && actor.permissions.includes('admin_users.manage') && <p><Button onClick={onVerify}>{session.verificationMode === 'email' ? 'Verify email to manage team access' : 'Verify authenticator to manage team access'}</Button></p>}
    {loading && <LoadingState label="Loading team access" />}
    {error && <ErrorState title="Team access unavailable" message={error} onRetry={refresh} />}
    {team && !loading && <><Card className="admin-security-card"><h2>Team members</h2>{team.canManage && (!allowMutations || session.verificationMode === 'authenticator' && cloudflareRecoveryVersion !== 1) && <p>Team access changes are currently unavailable.</p>}{team.members.length === 0 ? <EmptyState title="No team members" /> : <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th scope="col">Account</th><th scope="col">Role</th><th scope="col">Status</th><th scope="col">Invitation</th></tr></thead><tbody>{team.members.map((member) => <tr key={member.id}><td><strong>{member.displayName || member.publicId || member.email}</strong><br /><span>{member.email}</span></td><td>{member.role === 'owner' ? 'Owner' : member.role === 'admin' ? 'Admin' : 'Staff'}</td><td><StatusBadge tone={member.status === 'active' ? 'success' : member.status === 'invited' ? 'warning' : 'neutral'}>{member.status === 'active' ? 'Active' : member.status === 'invited' ? 'Invitation pending' : 'Access removed'}</StatusBadge></td><td>{invitationStatus(member.emailStatus, member.invitationKind) ?? '—'}</td></tr>)}</tbody></table></div>}</Card>{team.canManage && team.contractVersion === managedInvitationVersion && session.verificationMode === 'email' && allowMutations && <TeamManager actor={actor} epoch={epoch} team={team} onChanged={resolved} />}{allowRecovery && team.canManage && session.verificationMode === 'email' && <InvitationRecoveryPanel actor={actor} epoch={epoch} allowMutations={allowMutations && team.contractVersion === managedInvitationVersion} invitationVersion={team.contractVersion} onResolved={resolved} />}{allowRecovery && actor.role === 'owner' && actor.permissions.includes('admin_users.manage') && session.verificationMode === 'authenticator' && cloudflareRecoveryVersion === 1 && <CloudflareTeamPanel actor={actor} epoch={epoch} team={team} allowMutations={allowMutations} onChanged={resolved} onVerify={onVerify} />}<Card className="admin-security-card"><h2>Role permissions</h2>{Object.entries(team.permissionsByRole).map(([role, permissions]) => <div key={role}><h3>{role === 'owner' ? 'Owner' : role === 'admin' ? 'Admin' : 'Staff'}</h3><p>{permissions.length ? permissions.join(', ') : 'No permissions recorded'}</p></div>)}</Card></>}
  </>;
}

function mutationContext(actor: AdminUser, epoch: number, session: ReturnType<typeof useSession>, allowMutations: boolean, invitationVersion: 1 | 2 = 2): TeamMutationContext {
  return {allowMutations, invitationVersion, identity: {id: actor.id, sessionId: actor.sessionId, email: actor.email, role: actor.role, permissions: actor.permissions, expiresAt: actor.expiresAt}, request: session.request, verify: session.recheckSensitiveEmailVerification, current: () => session.isRecentSensitiveVerification(epoch, actor.id, actor.sessionId)};
}

function TeamManager({actor, epoch, team, onChanged}: {actor: AdminUser; epoch: number; team: Team; onChanged: (message: string) => void}) {
  const session = useSession(), context = mutationContext(actor, epoch, session, true, team.contractVersion);
  const [email, setEmail] = useState(''), [name, setName] = useState(''), [role, setRole] = useState<'admin' | 'staff'>('staff');
  const [busy, setBusy] = useState(false), [error, setError] = useState('');
  const [confirm, setConfirm] = useState<{kind: 'resend' | 'notice_repair' | 'revoke'; member: TeamMember} | null>(null);
  async function run(action: InvitationAction | {kind: 'revoke'; member: TeamMember}) {
    if (busy) return; setBusy(true); setError('');
    try {
      let message: string;
      if (action.kind === 'revoke') {await removeTeamAccess(context, action.member); message = `Access removed for ${action.member.email}.`;}
      else {const result = await submitTeamInvitation(context, action); message = result.messageKind === 'access_notice' ? 'Access notice accepted for sending. Inbox delivery is not confirmed.' : 'Invitation accepted for sending. Inbox delivery is not confirmed.'; setEmail(''); setName('');}
      setConfirm(null); onChanged(message);
    } catch (failure) {setConfirm(null); setError(failure instanceof Error ? failure.message : 'Team access could not be updated.');}
    finally {setBusy(false);}
  }
  function invite(event: FormEvent) {event.preventDefault(); void run({kind: 'invite', email, displayName: name, role});}
  return <Card className="admin-security-card"><h2>Manage team access</h2>{team.contractVersion === 1 && <p>Access removal is currently unavailable.</p>}<form onSubmit={invite}>
    <Field label="Email address" htmlFor="team-email"><input className="admin-input" id="team-email" type="email" autoComplete="email" required value={email} onChange={(event) => setEmail(event.target.value)} /></Field>
    <Field label="Name" htmlFor="team-name" hint="Optional"><input className="admin-input" id="team-name" maxLength={120} value={name} onChange={(event) => setName(event.target.value)} /></Field>
    <Field label="Role" htmlFor="team-role"><select className="admin-input" id="team-role" value={role} onChange={(event) => setRole(event.target.value as 'admin' | 'staff')}><option value="staff">Staff</option><option value="admin">Admin</option></select></Field>
    <Button type="submit" variant="primary" disabled={busy}>{team.contractVersion === 2 ? 'Add teammate' : 'Invite teammate'}</Button></form>
    {team.members.filter((member) => member.role !== 'owner' && member.id !== actor.id && member.email.toLowerCase() !== 'info@ikanisa.com' && member.status !== 'revoked').map((member) => {
      const prior = member.invitation;
      const resend = member.status === 'invited' && (team.contractVersion === 2 ? prior && ['accepted', 'rejected'].includes(prior.status) : member.invitationRequestId && member.invitationOperation && ['accepted', 'rejected'].includes(member.emailStatus ?? ''));
      const repair = prior?.messageKind === 'auth_invite' && prior.status === 'already_registered' && ['invite', 'resend'].includes(prior.operation);
      return <div key={member.id}><h3>{member.displayName || member.email}</h3>{resend && <Button disabled={busy} onClick={() => setConfirm({kind: 'resend', member})}>Resend email</Button>}{repair && <Button disabled={busy} onClick={() => setConfirm({kind: 'notice_repair', member})}>Send access notice</Button>}{team.contractVersion === 2 && <Button variant="danger" disabled={busy} onClick={() => setConfirm({kind: 'revoke', member})}>Remove access</Button>}</div>;
    })}
    {error && <p role="alert" className="admin-auth-feedback">{error}</p>}
    <Dialog open={confirm !== null} title={confirm?.kind === 'revoke' ? 'Remove team access?' : confirm?.kind === 'notice_repair' ? 'Send an access notice?' : 'Resend email?'} onClose={() => {if (!busy) setConfirm(null);}} footer={<><Button disabled={busy} onClick={() => setConfirm(null)}>Cancel</Button><Button variant={confirm?.kind === 'revoke' ? 'danger' : 'primary'} disabled={busy} onClick={() => {if (confirm) void run(confirm);}}>{confirm?.kind === 'revoke' ? 'Remove access' : 'Send email'}</Button></>}><p>{confirm?.kind === 'revoke' ? `${confirm.member.email} will lose access to Collect admin. Any pending invitation will stop working.` : confirm?.kind === 'notice_repair' ? `${confirm.member.email} already has a registered account. Send Admin sign-in instructions; delivery and sign-in are not confirmed.` : `Send another email to ${confirm?.member.email}. Delivery is not confirmed.`}</p></Dialog>
  </Card>;
}

/** Visible only when the caller selects the deployed Cloudflare recovery protocol. */
function CloudflareTeamPanel({actor, epoch, team, allowMutations, onChanged, onVerify}: {actor: AdminUser; epoch: number; team: Team;
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
        {team.members.filter(member => member.role !== 'owner' && member.id !== actor.id && member.email !== 'info@ikanisa.com' && member.status !== 'revoked').map(member =>
          <div key={member.id}><h3>{member.displayName || member.email}</h3>{member.status === 'invited' && <Button disabled={busy} onClick={() => void reviewTarget('resend', member)}>Review resend</Button>}{' '}
            <Button variant="danger" disabled={busy} onClick={() => void reviewTarget('revoke', member)}>Review access removal</Button></div>)}
      </>}
    </>}
    {review && <Dialog open title={review.kind === 'retry' ? 'Retry original team request?' : action?.kind === 'invite' ? 'Invite teammate?' : action?.kind === 'resend' ? 'Resend invitation?' : 'Remove team access?'}
      onClose={() => {if (!busy) setReview(null);}} footer={<><Button disabled={busy} onClick={() => setReview(null)}>Cancel</Button><Button variant={action?.kind === 'revoke' ? 'danger' : 'primary'} disabled={busy} onClick={() => void submit()}>{review.kind === 'retry' ? 'Retry same request' : 'Confirm team request'}</Button></>}>
      {review.kind === 'retry' ? <><p>This retry may perform the original action if it never committed. It uses the same reference and details.</p><p>Original reference: <code>{review.pending.kind === 'owned' ? review.pending.requestKey : ''}</code></p>
        {review.pending.kind === 'owned' && review.pending.attempt && <><p>Action: {String(review.pending.attempt.intent.operation)}</p><p>Email: {String(review.pending.attempt.intent.email)}</p><p>Role: {String(review.pending.attempt.intent.role)}</p>
          {object(review.pending.attempt.intent.body) && Object.entries(review.pending.attempt.intent.body).filter(([key]) => !['email','role'].includes(key)).map(([key,value]) => <p key={key}>{key}: {String(value)}</p>)}</>}</> :
        <><p>Account: {action?.kind === 'invite' ? action.email : action?.member.email}</p><p>Role: {action?.kind === 'invite' ? action.role : action?.member.role}</p>{action?.kind === 'invite' && <p>Name: {action.displayName || 'Not provided'}</p>}
          <p>{action?.kind === 'revoke' ? 'This removes access. Refresh the team list after the request is recorded.' : 'Email acceptance does not confirm inbox delivery.'}</p></>}
    </Dialog>}
  </Card>;
}

function InvitationRecoveryPanel({actor, epoch, allowMutations, invitationVersion, onResolved}: {actor: AdminUser; epoch: number; allowMutations: boolean; invitationVersion: 1 | 2; onResolved: (message: string) => void}) {
  const session = useSession();
  const [attempts, setAttempts] = useState<{epoch: number; actorId: string; values: InvitationAttempt[]} | null>(null);
  const [removals, setRemovals] = useState<PendingAttempt[]>([]);
  const [retryKey, setRetryKey] = useState(''), [retryAttempt, setRetryAttempt] = useState<InvitationAttempt | null>(null);
  const [messages, setMessages] = useState<Record<string, string>>({}), [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const identity: PendingIdentity = {id: actor.id, sessionId: actor.sessionId, email: actor.email, role: actor.role, permissions: actor.permissions, expiresAt: actor.expiresAt};
  function requireCurrent() {if (!session.isCurrentAuthority(epoch, actor.id, actor.sessionId)) throw new Error('Reopen team access with your current verified sign-in.');}
  async function read() {
    if (busy) return; setBusy(true); setError('');
    try {
      if (!(await session.recheckSensitiveEmailVerification())) throw new Error('Verify your email before reviewing original invitations.');
      requireCurrent();
      const saved = await listPending(identity, 'team-invitation', 'admin_users.manage');
      const pendingRemovals = allowMutations ? await listPending(identity, 'team-revoke', 'admin_users.manage') : [];
      requireCurrent();
      setAttempts({epoch, actorId: actor.id, values: saved.map(parseInvitationAttempt)}); setRemovals(pendingRemovals); setMessages({}); setRetryKey('');
    } catch (failure) {setError(failure instanceof Error ? failure.message : 'The original invitations could not be checked.');}
    finally {setBusy(false);}
  }
  async function check(attempt: InvitationAttempt) {
    if (busy) return; setBusy(true); setError(''); setRetryKey('');
    try {
      if (!(await session.recheckSensitiveEmailVerification())) throw new Error('Verify your email before reviewing original invitations.');
      requireCurrent();
      const result = allowMutations ? await checkTeamInvitation(mutationContext(actor, epoch, session, true, invitationVersion), attempt) : await lookupInvitation(session.request, attempt);
      requireCurrent();
      const resultText = result.found ? invitationStatus(result.receipt.status, result.receipt.messageKind) ?? 'Original request recorded' : 'No matching original request was found. Check before taking any further action.';
      setMessages((previous) => ({...previous, [attempt.checkpoint.request_key]: resultText}));
      if (allowMutations && !result.found) setRetryKey(attempt.checkpoint.request_key);
      if (allowMutations && result.found && result.receipt.status !== 'unknown') onResolved(resultText);
    } catch (failure) {setError(failure instanceof Error ? failure.message : 'The original invitation could not be checked.');}
    finally {setBusy(false);}
  }
  async function checkRemoval(saved: PendingAttempt) {
    if (busy) return; setBusy(true); setError('');
    try {
      const removed = await checkTeamRemoval(mutationContext(actor, epoch, session, allowMutations, invitationVersion), saved);
      requireCurrent();
      setMessages((previous) => ({...previous, [saved.request_key]: removed ? 'The account is currently revoked.' : 'Access is still shown as active or invited. The original removal result is not confirmed.'}));
      if (removed) onResolved('The account is currently revoked.');
    } catch (failure) {setError(failure instanceof Error ? failure.message : 'The current access status could not be checked.');}
    finally {setBusy(false);}
  }
  async function retry(attempt: InvitationAttempt) {
    if (busy) return; setBusy(true); setError(''); setRetryKey(''); setRetryAttempt(null);
    try {
      const result = await retryTeamInvitation(mutationContext(actor, epoch, session, allowMutations, invitationVersion), attempt);
      requireCurrent();
      onResolved(result.messageKind === 'access_notice' ? 'Access notice accepted for sending. Inbox delivery is not confirmed.' : 'Invitation accepted for sending. Inbox delivery is not confirmed.');
    } catch (failure) {setError(failure instanceof Error ? failure.message : 'The original invitation could not be retried.');}
    finally {setBusy(false);}
  }
  const visible = attempts?.epoch === epoch && attempts.actorId === actor.id ? attempts.values : null;
  return <Card className="admin-security-card"><h2>Original team access requests</h2><p>Review retained requests in this tab before making another change.</p><Button disabled={busy} onClick={() => void read()}>Review pending requests</Button>{error && <p role="alert" className="admin-auth-feedback">{error}</p>}{visible && visible.length === 0 && removals.length === 0 && <p>No pending team access references were found in this tab.</p>}{visible?.map((attempt) => <div key={attempt.checkpoint.request_key}><p>Original invitation request: <strong>{attempt.checkpoint.request_key}</strong></p><Button disabled={busy} onClick={() => void check(attempt)}>Check original request</Button>{retryKey === attempt.checkpoint.request_key && <Button disabled={busy} onClick={() => setRetryAttempt(attempt)}>Retry the same request</Button>}{messages[attempt.checkpoint.request_key] && <p role="status">{messages[attempt.checkpoint.request_key]}</p>}</div>)}{removals.map((saved) => <div key={saved.request_key}><p>Access removal for <strong>{typeof saved.intent.email === 'string' ? saved.intent.email : 'an account'}</strong></p><Button disabled={busy} onClick={() => void checkRemoval(saved)}>Check current access</Button>{messages[saved.request_key] && <p role="status">{messages[saved.request_key]}</p>}</div>)}{Object.entries(messages).filter(([key]) => !visible?.some((attempt) => attempt.checkpoint.request_key === key) && !removals.some((saved) => saved.request_key === key)).map(([key, value]) => <p key={key} role="status">{value}</p>)}
    <Dialog open={retryAttempt !== null} title="Retry the original invitation?" onClose={() => setRetryAttempt(null)} footer={<><Button disabled={busy} onClick={() => setRetryAttempt(null)}>Cancel</Button><Button variant="primary" disabled={busy} onClick={() => {if (retryAttempt) void retry(retryAttempt);}}>Retry same request</Button></>}><p>The original request was not found. This sends exactly the same details and reference; delivery is not guaranteed.</p>{retryAttempt?.operation === 'invite' && <p>Email: {String((retryAttempt.checkpoint.intent.body as JsonObject).email)}<br />Role: {String((retryAttempt.checkpoint.intent.body as JsonObject).role)}<br />Name: {String((retryAttempt.checkpoint.intent.body as JsonObject).displayName) || 'Not provided'}</p>}<p>Original reference: {retryAttempt?.checkpoint.request_key}</p></Dialog>
  </Card>;
}
