import {ApiError,first,id} from './core.js';
import {authRequest,verifyToken} from '../auth-http.js';
import {lockAdminSessionMutation} from '../postgres-mutation-lock.js';
import {decryptAdminTokens,encryptAdminTokens} from './admin_bff_tokens.js';
import {failAdminAccount as fail} from './admin_account_support/errors.js';

const unix = () => Math.floor(Date.now() / 1000);
const terminalErrors = new Set([
  'refresh_token_not_found', 'refresh_token_already_used', 'session_not_found',
  'session_expired', 'user_not_found', 'user_banned',
]);

function sameSession(original, current, hash) {
  return current?.token_hash === hash && current.auth_user_id === original.auth_user_id &&
    current.auth_session_id === original.auth_session_id;
}

function committedWinner(original, current, hash) {
  return sameSession(original, current, hash) && current.version === original.version + 1 &&
    current.refresh_lease === null && current.refresh_lease_until === null &&
    typeof current.token_ciphertext === 'string' && current.token_ciphertext &&
    current.token_ciphertext !== original.token_ciphertext;
}

function expiredClaim(original, current, hash) {
  return sameSession(original, current, hash) && current.version === original.version &&
    current.token_ciphertext === original.token_ciphertext && typeof current.refresh_lease === 'string' &&
    Number.isSafeInteger(current.refresh_lease_until) && current.refresh_lease_until <= unix();
}

async function verifyOriginalSession(env, original, tokens) {
  const proof = await verifyToken(env, tokens.access_token);
  if (proof.user.id !== original.auth_user_id || proof.claims.session_id !== original.auth_session_id)
    fail('session_changed', 401);
  return proof;
}

async function recoverWinner(env, original, winner) {
  const tokens = await decryptAdminTokens(env, winner);
  await verifyOriginalSession(env, original, tokens);
  return tokens;
}

function readCurrent(env, hash) {
  return first(env, 'SELECT * FROM private.bff_sessions WHERE token_hash=?', hash);
}

async function revokeFailedRefresh(env, hash, version, lease) {
  // A reclaimed lease or a concurrent logout may have superseded this response.
  return env.DB.transaction(async sql => {
    await env.DB.context(sql);
    await lockAdminSessionMutation(sql,hash);
    const rows = await sql.unsafe(`SELECT s.token_hash FROM app.admin_sessions s
    JOIN private.bff_sessions b ON b.token_hash=s.token_hash
    WHERE s.token_hash=$1 AND b.version=$2 AND b.refresh_lease=$3 FOR UPDATE OF s,b`, [hash,version,lease]);
    if (rows.length !== 1) return false;
    await sql.unsafe('DELETE FROM app.admin_sessions WHERE token_hash=$1', [hash]);
    return true;
  });
}

const refreshUnavailable = () => new ApiError(503, 'session_refresh_pending', 'The session is temporarily unavailable.');

export async function refreshAdminSession(env, row, tokens, hash) {
  const lease = id();
  const claimed = await env.DB.prepare('UPDATE private.bff_sessions SET refresh_lease=?,refresh_lease_until=? WHERE token_hash=? AND version=? AND refresh_lease IS NULL RETURNING token_hash')
    .bind(lease, unix()+30, hash, row.version).first();
  if (!claimed) {
    const current = await readCurrent(env, hash);
    if (committedWinner(row, current, hash)) return recoverWinner(env, row, current);
    if (!expiredClaim(row, current, hash)) fail('session_refresh_pending', 409);

    // GoTrue accepts the current refresh token or its immediate parent after a
    // lost reply. Reclaim only the exact expired lease and original ciphertext.
    const reclaimed = await env.DB.prepare(`UPDATE private.bff_sessions SET refresh_lease=?,refresh_lease_until=?
      WHERE token_hash=? AND version=? AND refresh_lease=? AND refresh_lease_until=? AND token_ciphertext=? RETURNING token_hash`)
      .bind(lease,unix()+30,hash,row.version,current.refresh_lease,current.refresh_lease_until,row.token_ciphertext).first();
    if (!reclaimed) fail('session_refresh_pending', 409);
  }

  let refreshed, cipher;
  try {
    refreshed = await authRequest(env, '/token?grant_type=refresh_token', {body:{refresh_token:tokens.refresh_token}});
    const proof = await verifyOriginalSession(env, row, refreshed);
    if (proof.claims.aal === 'aal2' && row.issued_assurance_level !== 2)
      throw new ApiError(409, 'mfa_recovery_required', 'Recheck the authenticator result before continuing.');
    cipher = await encryptAdminTokens(env, row, refreshed);
    const updated = await env.DB.prepare('UPDATE private.bff_sessions SET token_ciphertext=?,version=version+1,refresh_lease=NULL,refresh_lease_until=NULL WHERE token_hash=? AND refresh_lease=? AND version=? RETURNING version')
      .bind(cipher,hash,lease,row.version).first();
    if (!updated) fail('session_changed', 401);
    return refreshed;
  } catch (error) {
    // Recover a lost COMMIT reply from the exact retained ciphertext, or a
    // separately verified winner under the same SID.
    let retained;
    try { retained = await readCurrent(env, hash); }
    catch { throw refreshUnavailable(); }
    if (!retained) fail('unauthenticated', 401);
    if (refreshed && cipher && retained.version === row.version + 1 &&
        retained.token_ciphertext === cipher && retained.refresh_lease === null) return refreshed;
    if (committedWinner(row, retained, hash)) return recoverWinner(env, row, retained);
    if (!refreshed && [400,401,403,422].includes(error?.status) && terminalErrors.has(error?.code) &&
        retained.version === row.version && retained.refresh_lease === lease) {
      if (!await revokeFailedRefresh(env, hash, row.version, lease)) fail('session_refresh_pending', 409);
      fail('session_refresh_recovery_required', 401);
    }
    if (error?.code === 'mfa_recovery_required') {
      await env.DB.prepare('UPDATE private.bff_sessions SET refresh_lease=NULL,refresh_lease_until=NULL WHERE token_hash=? AND version=? AND refresh_lease=?')
        .bind(hash,row.version,lease).first();
      throw error;
    }
    throw refreshUnavailable();
  }
}
