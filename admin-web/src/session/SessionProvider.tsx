import {createContext, useContext, useEffect, useState, useSyncExternalStore, type ReactNode} from 'react';
import type {AdminClientConfig} from '../api/client';
import {AdminSessionController} from './AdminSessionController';
import type {SessionContextValue} from './sessionContext';

export {AdminSessionController} from './AdminSessionController';
export {parseAdminUser} from './sessionResponses';
export {sensitiveVerificationDeadline} from './sessionPolicy';
export type {SessionContextValue, SessionSnapshot} from './sessionContext';
export type {SensitiveEmailRecovery} from './sensitiveEmailVerification';
export {captureSetupLocation, safeAdminReturnLocation, safeAdminVerificationReturnLocation} from './returnLocation';
export {isVerifiedCurrentOwner, type AdminOwnerIdentity} from './ownerIdentity';
export type {AdminUser, OtpReceipt} from './sessionResponses';

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({config, children}: {config: AdminClientConfig; children: ReactNode}) {
  const [controller] = useState(() => new AdminSessionController(config));
  const snapshot = useSyncExternalStore(controller.subscribe, controller.getSnapshot, controller.getSnapshot);
  useEffect(() => {
    void controller.refresh().catch(() => undefined);
    return () => controller.stop();
  }, [controller]);
  const value: SessionContextValue = {
    ...snapshot,
    request: controller.request,
    refresh: controller.refresh,
    signIn: controller.signIn,
    signOut: controller.signOut,
    googleSignInAvailable: controller.googleSignInAvailable,
    signInWithGoogle: controller.signInWithGoogle,
    cancelGoogleSignIn: controller.cancelGoogleSignIn,
    requestEmailOtp: controller.requestEmailOtp,
    verifyEmailOtp: controller.verifyEmailOtp,
    requestPasswordReset: controller.requestPasswordReset,
    completePasswordSetup: controller.completePasswordSetup,
    changePassword: controller.changePassword,
    clearLocalSession: controller.clearLocalSession,
    isCurrentAuthority: controller.isCurrentAuthority,
    isRecentSensitiveVerification: controller.isRecentSensitiveVerification,
    verificationMode: config.backend === 'supabase' ? 'email' : 'authenticator',
    requestSensitiveEmailVerification: controller.requestSensitiveEmailVerification,
    verifySensitiveEmailVerification: controller.verifySensitiveEmailVerification,
    recheckEmailVerification: controller.recheckEmailVerification,
    recheckSensitiveEmailVerification: controller.recheckSensitiveEmailVerification,
    sensitiveEmailRecovery: controller.sensitiveEmailRecovery,
    releaseExpiredSensitiveRequest: controller.releaseExpiredSensitiveRequest,
    cancelSensitiveEmailVerification: controller.cancelSensitiveEmailVerification,
    verifyAuthenticator: controller.verifyAuthenticator,
  };
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error('SessionProvider is required.');
  return value;
}
