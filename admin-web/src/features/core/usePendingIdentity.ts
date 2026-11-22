import {useMemo} from 'react';
import type {PendingIdentity} from './pendingAttempt';

export function usePendingIdentity({id, sessionId, email, role, expiresAt, permissions}: PendingIdentity): PendingIdentity {
  const permissionKey = JSON.stringify([...new Set(permissions)].sort());
  return useMemo(() => ({
    id, sessionId, email, role, permissions: JSON.parse(permissionKey) as string[], expiresAt,
  }), [id, sessionId, email, role, permissionKey, expiresAt]);
}
