import {useState, type FormEvent} from 'react';
import type {JsonObject} from '../api/client';
import {listPending, type PendingAttempt, type PendingIdentity} from '../features/core/pendingAttempt';
import {Button, Card, Dialog, Field} from '../ui';
import {useSession, type AdminUser} from './SessionProvider';
import {lookupInvitation, parseInvitationAttempt, type InvitationAttempt} from './invitationRecovery';
import {checkTeamInvitation, checkTeamRemoval, removeTeamAccess, retryTeamInvitation, submitTeamInvitation, type InvitationAction, type TeamMutationContext} from './managedTeamMutations';
import {invitationStatus, type Team, type TeamMember} from './teamDirectory';
import {TEAM_MANAGE, TEAM_OWNER_EMAIL} from './teamPolicy';

function mutationContext(actor: AdminUser, epoch: number, session: ReturnType<typeof useSession>, allowMutations: boolean, invitationVersion: 1 | 2 = 2): TeamMutationContext {
  return {allowMutations, invitationVersion, identity: {id: actor.id, sessionId: actor.sessionId, email: actor.email, role: actor.role, permissions: actor.permissions, expiresAt: actor.expiresAt}, request: session.request, verify: session.recheckSensitiveEmailVerification, current: () => session.isRecentSensitiveVerification(epoch, actor.id, actor.sessionId)};
}

export function TeamManager({actor, epoch, team, onChanged}: {actor: AdminUser; epoch: number; team: Team; onChanged: (message: string) => void}) {
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
    {team.members.filter((member) => member.role !== 'owner' && member.id !== actor.id && member.email.toLowerCase() !== TEAM_OWNER_EMAIL && member.status !== 'revoked').map((member) => {
      const prior = member.invitation;
      const resend = member.status === 'invited' && (team.contractVersion === 2 ? prior && ['accepted', 'rejected'].includes(prior.status) : member.invitationRequestId && member.invitationOperation && ['accepted', 'rejected'].includes(member.emailStatus ?? ''));
      const repair = prior?.messageKind === 'auth_invite' && prior.status === 'already_registered' && ['invite', 'resend'].includes(prior.operation);
      return <div key={member.id}><h3>{member.displayName || member.email}</h3>{resend && <Button disabled={busy} onClick={() => setConfirm({kind: 'resend', member})}>Resend email</Button>}{repair && <Button disabled={busy} onClick={() => setConfirm({kind: 'notice_repair', member})}>Send access notice</Button>}{team.contractVersion === 2 && <Button variant="danger" disabled={busy} onClick={() => setConfirm({kind: 'revoke', member})}>Remove access</Button>}</div>;
    })}
    {error && <p role="alert" className="admin-auth-feedback">{error}</p>}
    <Dialog open={confirm !== null} title={confirm?.kind === 'revoke' ? 'Remove team access?' : confirm?.kind === 'notice_repair' ? 'Send an access notice?' : 'Resend email?'} onClose={() => {if (!busy) setConfirm(null);}} footer={<><Button disabled={busy} onClick={() => setConfirm(null)}>Cancel</Button><Button variant={confirm?.kind === 'revoke' ? 'danger' : 'primary'} disabled={busy} onClick={() => {if (confirm) void run(confirm);}}>{confirm?.kind === 'revoke' ? 'Remove access' : 'Send email'}</Button></>}><p>{confirm?.kind === 'revoke' ? `${confirm.member.email} will lose access to Collect admin. Any pending invitation will stop working.` : confirm?.kind === 'notice_repair' ? `${confirm.member.email} already has a registered account. Send Admin sign-in instructions; delivery and sign-in are not confirmed.` : `Send another email to ${confirm?.member.email}. Delivery is not confirmed.`}</p></Dialog>
  </Card>;
}

export function InvitationRecoveryPanel({actor, epoch, allowMutations, invitationVersion, onResolved}: {actor: AdminUser; epoch: number; allowMutations: boolean; invitationVersion: 1 | 2; onResolved: (message: string) => void}) {
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
      const saved = await listPending(identity, 'team-invitation', TEAM_MANAGE);
      const pendingRemovals = allowMutations ? await listPending(identity, 'team-revoke', TEAM_MANAGE) : [];
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
