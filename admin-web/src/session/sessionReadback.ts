import {AdminRequestError, type AdminApiClient, type AdminBackend} from '../api/client';
import {parseAdminUser, parseEmailProof, parseSessionUser, type AdminUser} from './sessionResponses';

export interface SessionReadback {
  isCurrent?: () => boolean;
  matches: (user: AdminUser) => boolean;
  message: string;
}

/** A refresh can install only the user and CSRF proof that it read under its own authority. */
export async function readAdminSession(request: AdminApiClient['request'], backend: AdminBackend, isCurrent: () => boolean) {
  let csrfToken: string | null | undefined;
  const body = await request('auth/session', {authenticated: false}, {
    isCurrent,
    receiveCsrf: token => { csrfToken = token; },
  });
  if (!isCurrent()) return null;
  if (body.user === null) return {user: null, csrfToken};
  const user = backend === 'supabase' ? parseSessionUser(body, Date.now()) : parseAdminUser(body);
  return {user, csrfToken};
}

export async function readSessionEmailProof(request: AdminApiClient['request'], user: AdminUser, isCurrent: () => boolean): Promise<string | null> {
  try {
    const proof = await request('auth/email-verification', {authenticated: false, expectedStatus: 200}, {isCurrent});
    if (!isCurrent()) return null;
    if (typeof proof.sessionId === 'string' && proof.sessionId !== user.sessionId) throw new Error('Session mismatch.');
    return parseEmailProof(proof, user, Date.now());
  } catch (failure) {
    if (!isCurrent()) return null;
    // A retired client or mismatched proof cannot establish the earlier session response.
    if (failure instanceof AdminRequestError && failure.statusCode === 426 ||
        failure instanceof Error && failure.message === 'Session mismatch.') throw failure;
    return null;
  }
}
