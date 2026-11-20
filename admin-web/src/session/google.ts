import {AdminRequestError} from '../api/client';
import {SUPABASE_PROJECT_ORIGIN} from '../config';

const ALLOWED_ORIGINS = new Set(['https://platform-admin.collect.ikanisa.com', 'https://admin-supabase-qa.collect.ikanisa.com']);

export function googleAvailable(backend: string, enabled: boolean, projectOrigin: string | undefined, origin: string): boolean {
  return enabled && backend === 'supabase' && projectOrigin === SUPABASE_PROJECT_ORIGIN && ALLOWED_ORIGINS.has(origin);
}

export function googleAuthorizationUrl(value: unknown, callbackOrigin: string, projectOrigin: string | undefined): string {
  if (typeof value !== 'string' || !ALLOWED_ORIGINS.has(callbackOrigin) || projectOrigin !== SUPABASE_PROJECT_ORIGIN) throw new Error('Google sign-in is unavailable.');
  let candidate: URL;
  try {candidate = new URL(value);} catch {throw new Error('Google sign-in is unavailable.');}
  if (candidate.protocol !== 'https:' || candidate.origin !== projectOrigin || candidate.pathname !== '/auth/v1/authorize' || candidate.username || candidate.password || candidate.hash) throw new Error('Google sign-in is unavailable.');
  const allowed = new Set(['provider', 'redirect_to', 'code_challenge', 'code_challenge_method', 'scopes', 'prompt']);
  for (const key of candidate.searchParams.keys()) if (!allowed.has(key) || candidate.searchParams.getAll(key).length !== 1) throw new Error('Google sign-in is unavailable.');
  if (candidate.searchParams.get('provider') !== 'google' || candidate.searchParams.get('code_challenge_method') !== 's256' || !/^[A-Za-z0-9_-]{43}$/.test(candidate.searchParams.get('code_challenge') ?? '') || (candidate.searchParams.has('scopes') && candidate.searchParams.get('scopes') !== 'openid email profile') || (candidate.searchParams.has('prompt') && candidate.searchParams.get('prompt') !== 'select_account')) throw new Error('Google sign-in is unavailable.');
  let redirect: URL;
  try {redirect = new URL(candidate.searchParams.get('redirect_to') ?? '');} catch {throw new Error('Google sign-in is unavailable.');}
  if (redirect.origin !== callbackOrigin || redirect.pathname !== '/functions/v1/collect-api/v1/auth/google/callback' || redirect.username || redirect.password || redirect.hash || [...redirect.searchParams.keys()].some((key) => key !== 'state') || redirect.searchParams.getAll('state').length !== 1 || !/^[A-Za-z0-9_-]{43}$/.test(redirect.searchParams.get('state') ?? '')) throw new Error('Google sign-in is unavailable.');
  return candidate.href;
}

export function randomUrlValue(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

export async function googleChallenge(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  return btoa(String.fromCharCode(...new Uint8Array(digest))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

export interface GooglePopup {
  authorize: (createUrl: () => Promise<string>) => Promise<{state: string; code?: string; error?: string}>;
  cancel: () => void;
}

/** Call in the click handler before awaiting network or cryptography. */
export function openGooglePopup(state: string, origin: string): GooglePopup {
  const popup = window.open('about:blank', `collect-google-${state}`, 'popup,width=500,height=700');
  if (!popup) throw new AdminRequestError('Allow the Google sign-in window in your browser.');
  let cancel: (() => void) | null = null;
  return {
    cancel: () => cancel?.(),
    authorize: async (createUrl) => {
      let resolve!: (value: {state: string; code?: string; error?: string}) => void;
      let reject!: (error: Error) => void;
      const result = new Promise<{state: string; code?: string; error?: string}>((ok, fail) => {resolve = ok; reject = fail;});
      // Cancellation can occur while the initial network request is in flight.
      void result.catch(() => undefined);
      cancel = () => reject(new AdminRequestError('Google sign-in was cancelled.'));
      const listener = (event: MessageEvent) => {
        if (event.origin !== origin || event.source !== popup || !event.data || typeof event.data !== 'object' || event.data.type !== 'collect-google-auth' || event.data.state !== state) return;
        resolve({state, code: typeof event.data.code === 'string' ? event.data.code : undefined, error: typeof event.data.error === 'string' ? event.data.error : undefined});
      };
      window.addEventListener('message', listener);
      const closed = setInterval(() => {if (popup.closed) cancel?.();}, 500);
      const timeout = setTimeout(() => reject(new AdminRequestError('Google sign-in expired.')), 300_000);
      try {
        // The user can cancel while the start request or PKCE calculation is
        // still pending. Do not leave the popup open until that work returns.
        const first = await Promise.race([
          createUrl().then((url) => ({kind: 'url' as const, url})),
          result.then((reply) => ({kind: 'reply' as const, reply})),
        ]);
        if (first.kind === 'reply') return first.reply;
        if (!popup.closed) popup.location.href = first.url;
        return await result;
      } finally {
        clearInterval(closed); clearTimeout(timeout); window.removeEventListener('message', listener); popup.close(); cancel = null;
      }
    },
  };
}
