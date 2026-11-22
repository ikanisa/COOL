import {useEffect, useState} from 'react';
import {Button, Card, EmptyState, ErrorState, LoadingState, PageHeader, StatusBadge} from '../ui';
import {CloudflareTeamPanel} from './CloudflareTeamPanel';
import {InvitationRecoveryPanel, TeamManager} from './ManagedTeamPanel';
import {useSession, type AdminUser, type SessionContextValue} from './SessionProvider';
import {invitationStatus, parseTeam, teamDirectoryPath, type Team} from './teamDirectory';
import {TEAM_MANAGE} from './teamPolicy';
import './auth.css';

interface TeamPageProps {
  onVerify: () => void;
  allowMutations?: boolean;
  managedInvitationVersion?: 1 | 2;
  cloudflareRecoveryVersion?: 1;
  allowRecovery?: boolean;
  showVerification?: boolean;
}

export function TeamPage(props: TeamPageProps) {
  const session = useSession(), actor = session.user;
  if (!actor?.permissions.includes('admin_users.read')) {
    return <ErrorState title="Access unavailable" message="Your account cannot view team access." />;
  }
  const scope = JSON.stringify([session.epoch, actor.id, actor.sessionId]);
  return <TeamWorkspace key={scope} actor={actor} session={session} {...props} />;
}

const roleNames = {owner: 'Owner', admin: 'Admin', staff: 'Staff'} as const;
const accessStatus = {
  active: {label: 'Active', tone: 'success'},
  invited: {label: 'Invitation pending', tone: 'warning'},
  revoked: {label: 'Access removed', tone: 'neutral'},
} as const;

function TeamDirectoryCard({team, changesUnavailable}: {team: Team; changesUnavailable: boolean}) {
  return <Card className="admin-security-card">
    <h2>Team members</h2>
    {changesUnavailable && <p>Team access changes are currently unavailable.</p>}
    {team.members.length === 0 ? <EmptyState title="No team members" /> :
      <div className="admin-table-wrap"><table className="admin-table">
        <thead><tr><th scope="col">Account</th><th scope="col">Role</th><th scope="col">Status</th><th scope="col">Invitation</th></tr></thead>
        <tbody>{team.members.map(member => {
          const status = accessStatus[member.status];
          return <tr key={member.id}>
            <td><strong>{member.displayName || member.publicId || member.email}</strong><br /><span>{member.email}</span></td>
            <td>{roleNames[member.role]}</td>
            <td><StatusBadge tone={status.tone}>{status.label}</StatusBadge></td>
            <td>{invitationStatus(member.emailStatus, member.invitationKind) ?? '—'}</td>
          </tr>;
        })}</tbody>
      </table></div>}
  </Card>;
}

function TeamWorkspace({
  actor, session, onVerify, allowMutations = false, managedInvitationVersion = 2, cloudflareRecoveryVersion,
  allowRecovery = true, showVerification = true,
}: TeamPageProps & {actor: AdminUser; session: SessionContextValue}) {
  const {request, epoch, verificationMode} = session;
  const [team, setTeam] = useState<Team | null>(null);
  const [error, setError] = useState(''), [loading, setLoading] = useState(true), [revision, setRevision] = useState(0);
  const [actionMessage, setActionMessage] = useState('');
  useEffect(() => {
    let alive = true;
    const path = teamDirectoryPath(actor, verificationMode, managedInvitationVersion);
    void request(path, {authenticated: true}).then(body => {
      if (!alive) return;
      setTeam(parseTeam(body, actor, verificationMode === 'authenticator'));
      setError('');
    }).catch((failure: unknown) => {
      if (alive) setError(failure instanceof Error ? failure.message : 'Team access could not be loaded.');
    }).finally(() => {
      if (alive) setLoading(false);
    });
    return () => {alive = false;};
  }, [request, actor, revision, verificationMode, managedInvitationVersion]);

  const refresh = () => {setLoading(true); setRevision(value => value + 1);};
  const resolved = (message: string) => {setActionMessage(message); refresh();};
  const usesEmail = verificationMode === 'email';
  const isOwnerManager = actor.role === 'owner' && actor.permissions.includes(TEAM_MANAGE);
  const managedWrites = allowMutations && team?.contractVersion === managedInvitationVersion;
  return <>
    <PageHeader title="Team access" subtitle="Admins and staff who can use the Collect workspace."
      actions={<Button icon="refresh" onClick={refresh} disabled={loading}>Refresh</Button>} />
    {actionMessage && <p role="status">{actionMessage}</p>}
    {showVerification && isOwnerManager && <p><Button onClick={onVerify}>
      {usesEmail ? 'Verify email to manage team access' : 'Verify authenticator to manage team access'}
    </Button></p>}
    {loading && <LoadingState label="Loading team access" />}
    {error && <ErrorState title="Team access unavailable" message={error} onRetry={refresh} />}
    {team && !loading && <>
      <TeamDirectoryCard team={team} changesUnavailable={team.canManage && (!allowMutations || !usesEmail && cloudflareRecoveryVersion !== 1)} />
      {team.canManage && usesEmail && managedWrites && <TeamManager actor={actor} epoch={epoch} team={team} onChanged={resolved} />}
      {allowRecovery && team.canManage && usesEmail && <InvitationRecoveryPanel actor={actor} epoch={epoch}
        allowMutations={managedWrites} invitationVersion={team.contractVersion} onResolved={resolved} />}
      {allowRecovery && isOwnerManager && !usesEmail && cloudflareRecoveryVersion === 1 &&
        <CloudflareTeamPanel actor={actor} epoch={epoch} team={team} allowMutations={allowMutations} onChanged={resolved} onVerify={onVerify} />}
      <Card className="admin-security-card"><h2>Role permissions</h2>
        {Object.entries(team.permissionsByRole).map(([role, permissions]) => <div key={role}>
          <h3>{role === 'owner' ? 'Owner' : role === 'admin' ? 'Admin' : 'Staff'}</h3>
          <p>{permissions.length ? permissions.join(', ') : 'No permissions recorded'}</p>
        </div>)}
      </Card>
    </>}
  </>;
}
