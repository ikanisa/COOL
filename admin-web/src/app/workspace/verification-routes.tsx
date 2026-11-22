import {lazy} from 'react';
import {Navigate, useLocation, useNavigate} from 'react-router';
import {SensitiveEmailVerificationPage} from '../../session/SensitiveEmailVerificationPage';
import {useSession} from '../../session/SessionProvider';
import {safeAdminVerificationReturnLocation, verificationPath} from '../../session/returnLocation';
import {workspaceRoute} from './routePolicy';

const AuthenticatorPage = lazy(() => import('../../session/AuthenticatorPage').then(module => ({default: module.AuthenticatorPage})));

function VerifyEmailRoute() {
  const go = useNavigate(), location = useLocation(), session = useSession();
  const requested = new URLSearchParams(location.search).get('returnTo');
  if (session.verificationMode !== 'email') return <Navigate to={verificationPath('authenticator', requested)} replace />;
  const destination = safeAdminVerificationReturnLocation(requested) ?? '/admin';
  return <SensitiveEmailVerificationPage onDone={(completed) => go(completed && session.user?.mfaRequired ?
    verificationPath('authenticator', destination) : destination, {replace: true})} />;
}

function AuthenticatorRoute() {
  const session = useSession(), go = useNavigate(), location = useLocation();
  const requested = new URLSearchParams(location.search).get('returnTo');
  if (session.verificationMode === 'email' && !session.user?.mfaAvailable) return <Navigate to={verificationPath('email', requested)} replace />;
  const destination = safeAdminVerificationReturnLocation(requested) ?? '/admin/security';
  return <AuthenticatorPage onBack={() => go(destination)} onSignIn={() => go('/admin/login', {replace: true})} />;
}

export const verificationRoutes = [
  workspaceRoute('security/verify-email', <VerifyEmailRoute />, () => true),
  workspaceRoute('security/authenticator', <AuthenticatorRoute />, () => true),
];
