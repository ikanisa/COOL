/* eslint-disable no-control-regex -- Reject ASCII control characters in untrusted input. */
const INTERNAL_BASE = 'https://admin.invalid';

export const publicSessionPaths = {
  login: '/admin/login',
  forgotPassword: '/admin/forgot-password',
  setup: '/admin/setup',
  redirect: '/admin/session',
} as const;

const publicEntries = new Set<string>(Object.values(publicSessionPaths));

/** Protect against redirecting outside the Admin after authentication. */
export function safeAdminReturnLocation(location: string | null | undefined): string | null {
  if (!location || location.length > 2000 || /[\x00-\x20\\#]/.test(location) || !location.startsWith('/') || location.startsWith('//')) return null;
  const rawPath = location.split('?')[0];
  if (!(rawPath === '/admin' || rawPath.startsWith('/admin/'))) return null;
  try {
    const parsed = new URL(location, INTERNAL_BASE);
    if (parsed.origin !== INTERNAL_BASE || parsed.pathname !== rawPath || parsed.hash) return null;
    const route = decodeURIComponent(parsed.pathname).replace(/\/+$/, '').toLowerCase();
    if (publicEntries.has(route)) return null;
    return location;
  } catch { return null; }
}

/** Verification never forwards arbitrary drafts, nested return targets or secrets. */
export function safeAdminVerificationReturnLocation(location: string | null | undefined): string | null {
  const candidate = safeAdminReturnLocation(location);
  if (!candidate) return null;
  const parsed = new URL(candidate, INTERNAL_BASE);
  if (parsed.pathname.startsWith('/admin/security/')) return null;
  try {
    for (const segment of parsed.pathname.split('/')) {
      const decoded = decodeURIComponent(segment);
      if (decoded === '.' || decoded === '..' || /[\x00-\x20/\\]/.test(decoded)) return null;
    }
  } catch {return null;}
  const keys = parsed.pathname === '/admin/requests' ? parsed.searchParams.getAll('key') : [];
  const key = keys.length === 1 && /^[A-Za-z0-9._:-]{8,200}$/.test(keys[0]) ? keys[0] : null;
  return parsed.pathname + (key ? `?key=${encodeURIComponent(key)}` : '');
}

/** Capture one-use setup data in memory and remove it from browser history immediately. */
export function captureSetupLocation(location: Location = window.location, history: History = window.history): {token: string; invite: boolean} | null {
  const hashRoute = location.hash.startsWith('#/admin/setup');
  const source = hashRoute ? location.hash.slice(1) : location.pathname + location.search;
  let parsed: URL;
  try { parsed = new URL(source, location.origin); } catch { return null; }
  if (parsed.pathname !== publicSessionPaths.setup) return null;
  const values = parsed.searchParams.getAll('token');
  const invites = parsed.searchParams.getAll('invite');
  history.replaceState(null, '', hashRoute ? '/#' + publicSessionPaths.setup : publicSessionPaths.setup);
  if (values.length !== 1 || invites.length > 1 || (invites.length === 1 && !['true', 'false'].includes(invites[0]))) return null;
  const token = values[0];
  if (!/^\S{32,512}$/.test(token)) return null;
  return {token, invite: invites[0] === 'true'};
}

export type VerificationMode = 'email' | 'authenticator';

export function verificationPath(mode: VerificationMode, requested?: string | null): string {
  const path = mode === 'email' ? '/admin/security/verify-email' : '/admin/security/authenticator';
  const destination = safeAdminVerificationReturnLocation(requested);
  return destination ? `${path}?${new URLSearchParams({returnTo: destination})}` : path;
}
