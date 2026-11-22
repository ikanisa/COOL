import {encrypt,decrypt} from './encryption.js';
import {authRequest} from '../auth-http.js';
import {digest} from './core.js';

// The browser duration follows the 400-day persistent cookie cap. The
// underlying managed account and session still govern authority independently.
export const ADMIN_COOKIE_SECONDS = 400 * 24 * 60 * 60;

export function adminTokenCustody(env) {
  return {
    ...env,
    DATA_KEY_ID: env.SESSION_KEY_ID ?? 'bff-v1',
    DATA_ENCRYPTION_KEY: env.SESSION_ENCRYPTION_KEY,
    DATA_DECRYPTION_KEYS_JSON: env.SESSION_DECRYPTION_KEYS_JSON,
  };
}

const tokenContext = ({auth_session_id,auth_user_id}) => `bff:${auth_session_id}:${auth_user_id}`;
export const adminMfaOldCookieContext = ({auth_session_id,auth_user_id}) => `bff-mfa-old:${auth_session_id}:${auth_user_id}`;
export const adminMfaCandidateContext = ({auth_session_id,auth_user_id}) => `bff-mfa-candidate:${auth_session_id}:${auth_user_id}`;
export const adminMfaIntentHash = value => digest('collect-admin-mfa-intent-v1:' + value);

export function newAdminCookieToken() {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), value => value.toString(16).padStart(2,'0')).join('');
}

export async function encryptAdminTokens(env, session, tokens) {
  const {access_token,refresh_token} = tokens;
  const bytes = new TextEncoder().encode(JSON.stringify({access_token,refresh_token}));
  return encrypt(adminTokenCustody(env), bytes, tokenContext(session));
}

export async function decryptAdminTokens(env, session, ciphertext = session.token_ciphertext) {
  const bytes = await decrypt(adminTokenCustody(env), ciphertext, tokenContext(session));
  return JSON.parse(new TextDecoder().decode(bytes));
}

// Callers have already confirmed the exact local revocation. A missing or
// uncertain provider reply must never restore local access or trigger a retry.
export async function finishAdminProviderLogout(env, retained) {
  if (!retained) return 'unconfirmed';
  try {
    const tokens = await decryptAdminTokens(env, retained);
    await authRequest(env, '/logout?scope=local', {token:tokens.access_token});
    return 'confirmed';
  } catch {
    return 'unconfirmed';
  }
}
