import {useCallback} from 'react';
import {useNavigate} from 'react-router';
import type {FeatureAccess} from '../../features/core/types';
import {useSession} from '../../session/SessionProvider';
import {featureAuthorityKey} from '../authority';
import {verifySensitiveAccess} from '../sensitive-access';

export function useAccess(): FeatureAccess {
  const session = useSession(), go = useNavigate();
  if (!session.user) throw new Error('The workspace session is unavailable.');
  const user = session.user;
  const authorityKey = featureAuthorityKey(session.epoch, user);
  return {request: session.request, permissions: user.permissions, actorId: user.id, principalId: user.principalId,
    role: user.role, authorityKey, financialModel: user.financialModel, navigate: go};
}

export function useCurrentAuthority() {
  const session = useSession(), user = session.user!;
  const {epoch, isCurrentAuthority} = session, {id, sessionId} = user;
  return useCallback(() => isCurrentAuthority(epoch, id, sessionId), [epoch, id, sessionId, isCurrentAuthority]);
}

export function useSensitiveAccess() {
  const session = useSession();
  const user = session.user!;
  return {identity: {id: user.id, sessionId: user.sessionId, email: user.email, role: user.role,
    permissions: user.permissions, expiresAt: user.expiresAt}, verifyFresh: () => verifySensitiveAccess(session, user)};
}
