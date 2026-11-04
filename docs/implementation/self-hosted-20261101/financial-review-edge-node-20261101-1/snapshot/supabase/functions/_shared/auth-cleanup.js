import {ApiError} from './domain/core.js';

/** Purge only expired, unconsumed Google payloads. This does not authenticate,
 * admit, replay, revoke managed sessions, or delete flow/context/audit records.
 * nowEpoch is a server-owned clock override for deterministic qualification;
 * never populate these options from an HTTP body or caller-controlled header.
 * @param {any} env
 * @param {{limit?:number,nowEpoch?:number}} options
 */
export async function cleanupExpiredGoogleFlows(env,{limit=100,nowEpoch=Math.floor(Date.now()/1000)}={}) {
 if(!Number.isSafeInteger(limit)||limit<1||limit>500||!Number.isSafeInteger(nowEpoch)||nowEpoch<0)
  throw new ApiError(400,'auth_cleanup_invalid_budget','A bounded cleanup budget is required.');
 if(typeof env?.DB?.prepare!=='function')
  throw new ApiError(503,'auth_cleanup_unavailable','Expired sign-in cleanup is unavailable.');
 try {
  // Selection and purge share one transaction and row lock. An exchange that
  // already owns a row is skipped. A cleanup winner makes its status terminal,
  // so a waiting ready→consumed/exchanging→ready CAS cannot resurrect it.
  const count=await env.DB.prepare(`
   WITH expired AS MATERIALIZED (
    SELECT id FROM app.auth_google_flows
    WHERE expires_at<=? AND status IN('pending','exchanging','ready')
    ORDER BY expires_at,id LIMIT ? FOR UPDATE SKIP LOCKED
   ), purged AS (
    UPDATE app.auth_google_flows AS flow
    SET provider_verifier='{}',status='failed'
    FROM expired WHERE flow.id=expired.id
     AND flow.expires_at<=? AND flow.status IN('pending','exchanging','ready')
    RETURNING flow.id
   ) SELECT count(*)::integer AS purged FROM purged
  `).bind(nowEpoch,limit,nowEpoch).first('purged');
  if(!Number.isSafeInteger(count)||count<0||count>limit)throw new Error('Unconfirmed cleanup count');
  return {status:'complete',examined_limit:limit,purged:count,provider_calls:0};
 }catch {
  // A SQL reply can be lost after commit. A future bounded sweep is safe and
  // idempotent; do not claim rollback, log payloads or retry OAuth operations.
  throw new ApiError(503,'auth_cleanup_unconfirmed','Expired sign-in cleanup could not be confirmed.');
 }
}
