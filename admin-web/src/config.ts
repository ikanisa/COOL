import {isAdminPublishableKey, type AdminClientConfig} from './api/contracts';
import {acquireSameOriginCaptcha, cancelSameOriginCaptcha} from './session/captcha';

type PublicEnvironment = Record<string, string | boolean | undefined>;
export const SUPABASE_PROJECT_ORIGIN = 'https://rrlduytparvsjfmegalh.supabase.co';

function booleanSetting(value: string | boolean | undefined): boolean {
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw new Error('The Admin security policy is not configured.');
}

/** Explicit public settings only; neither a backend nor a security policy is guessed. */
export function readAdminConfig(environment: PublicEnvironment, actualOrigin: string): AdminClientConfig {
  const expectedOrigin = environment.VITE_ADMIN_EXPECTED_ORIGIN;
  if (typeof expectedOrigin !== 'string' || expectedOrigin.length > 2048) throw new Error('The Admin origin is not configured.');
  let origin: URL;
  try {origin = new URL(expectedOrigin);} catch {throw new Error('The Admin origin is not configured.');}
  const local = origin.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(origin.hostname);
  if ((origin.protocol !== 'https:' && !local) || origin.username || origin.password ||
      origin.pathname !== '/' || origin.search || origin.hash || origin.origin !== actualOrigin) {
    throw new Error('This Admin origin is not configured.');
  }
  const backend = environment.VITE_ADMIN_BACKEND;
  if (backend !== 'supabase' && backend !== 'cloudflare') throw new Error('The Admin backend is not configured.');
  const captchaEnabled = booleanSetting(environment.VITE_ADMIN_CAPTCHA_ENABLED);
  const googleEnabled = booleanSetting(environment.VITE_ADMIN_GOOGLE_ENABLED);
  const publishableKey = environment.VITE_SUPABASE_PUBLISHABLE_KEY;
  const supabaseProjectOrigin = environment.VITE_SUPABASE_PROJECT_ORIGIN;
  if (backend === 'supabase' && !isAdminPublishableKey(publishableKey)) {
    throw new Error('The Admin public configuration is incomplete.');
  }
  // The retained same-origin challenge and captcha_token contract are for the
  // Supabase transport; Cloudflare's current Admin endpoints do not accept it.
  if (backend === 'cloudflare' && (publishableKey || googleEnabled || supabaseProjectOrigin || captchaEnabled)) {
    throw new Error('The Admin public configuration is inconsistent.');
  }
  if (backend === 'supabase' && supabaseProjectOrigin !== SUPABASE_PROJECT_ORIGIN) {
    throw new Error('The Admin project origin is not configured for this workspace.');
  }
  return {
    backend, captchaEnabled, googleEnabled,
    ...(backend === 'supabase' ? {publishableKey: publishableKey as string, supabaseProjectOrigin: SUPABASE_PROJECT_ORIGIN} : {}),
    ...(captchaEnabled ? {acquireCaptcha: acquireSameOriginCaptcha, cancelCaptcha: cancelSameOriginCaptcha} : {}),
  };
}
