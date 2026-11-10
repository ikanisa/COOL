import {requirePort,requireThat,BuriError} from './errors.js';
import {requireId,requireRequestId} from './values.js';
import {pgInteger} from './postgres-values.js';
const integer=v=>pgInteger(v,{minimum:0,code:'canonical_authority_unavailable'});

/** Current shared managed actor inside the caller's admitted WRITE transaction.
 * Reuses Collect's signed claims/session and actual assurance fields. Does not
 * grant a native capability or replace the per-command shared mutation guard.
 */
export async function canonicalManagedActor(authority,sql){
    requirePort(authority,['assertOwned']);requirePort(sql,['unsafe']);
    await authority.assertOwned();let rows;
    try{
      rows=await sql.unsafe(`WITH canonical AS MATERIALIZED (
        SELECT private.assert_actor() AS principal_user_id,api.current_session_id() AS principal_session_id,
          floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms)
        SELECT c.*,s.user_id AS session_user_id,s.surface,s.expires_at,s.revoked_at,s.mfa_at
        FROM canonical c JOIN app.auth_sessions s ON s.id=c.principal_session_id
        FOR SHARE OF s`);
    }catch{throw new BuriError('canonical_authority_unavailable',403);}
    await authority.assertOwned();requireThat(rows.length===1,'canonical_authority_unavailable',403);const r=rows[0];
    requireId(r.principal_user_id);requireRequestId(r.principal_session_id);
    const nowMs=integer(r.now_ms),now=Math.floor(nowMs/1000),expiry=integer(r.expires_at);
    requireThat(r.session_user_id===r.principal_user_id&&
      r.surface==='admin'&&r.revoked_at===null&&expiry>now,'canonical_authority_unavailable',403);
    const mfa=r.mfa_at===null?null:integer(r.mfa_at);
    requireThat(mfa===null||mfa<=now,'canonical_authority_unavailable',403);
    return Object.freeze({userId:r.principal_user_id,sessionId:r.principal_session_id,now,nowMs,expiry,mfa});

}
