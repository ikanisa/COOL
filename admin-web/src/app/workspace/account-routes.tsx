import {lazy} from 'react';
import {useNavigate} from 'react-router';
import {AccountSecurityPage} from '../../session/AccountSecurityPage';
import {useSession} from '../../session/SessionProvider';
import {verificationPath} from '../../session/returnLocation';
import {UnavailablePage} from '../UnavailablePage';
import {useAccess, useSensitiveAccess} from './access';
import {requiresPermissions, workspaceRoute} from './routePolicy';

const LicensesPage = lazy(() => import('../../features/licenses/LicensesPage').then(m => ({default: m.LicensesPage})));
const TeamPage = lazy(() => import('../../session/TeamPage').then(m => ({default: m.TeamPage})));
const PrivacyPage = lazy(() => import('../../features/privacy/PrivacyPage').then(m => ({default: m.PrivacyPage})));

function AccountSecurityRoute() {
  const session = useSession(), go = useNavigate();
  if (!session.user?.permissions.includes('account.manage')) return <UnavailablePage title="Account security" />;
  return <AccountSecurityPage onVerify={() => go(verificationPath(session.verificationMode, session.verificationMode === 'email' ? '/admin/security' : undefined))}
    onAuthenticator={() => go(verificationPath('authenticator', '/admin/security'))}
    onLicenses={() => go('/admin/licenses')} onPasswordRecovery={() => go('/admin/forgot-password')}
    onSignIn={() => go('/admin/login', {replace: true})} />;
}

function TeamRoute() {
  const session = useSession(), go = useNavigate();
  return <TeamPage onVerify={() => go(verificationPath(session.verificationMode, '/admin/admin-users'))} />;
}

function PrivacyRoute() {
  const session = useSession(), sensitive = useSensitiveAccess(), go = useNavigate(), access = useAccess();
  return <PrivacyPage key={access.authorityKey} user={session.user!} epoch={session.epoch} verificationMode={session.verificationMode}
    request={session.request} verifyFresh={sensitive.verifyFresh} isCurrentAuthority={session.isCurrentAuthority}
    onVerify={() => go(verificationPath(session.verificationMode, '/admin/privacy-requests'))} />;
}

export const accountRoutes = [
  workspaceRoute('security', <AccountSecurityRoute />, requiresPermissions('account.manage')),
  workspaceRoute('licenses', <LicensesPage />, () => true),
  workspaceRoute('admin-users', <TeamRoute />, requiresPermissions('admin_users.read')),
  workspaceRoute('privacy-requests', <PrivacyRoute />, requiresPermissions('privacy.review')),
];
