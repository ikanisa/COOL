import {requirePort,requireThat,BuriError} from './errors.js';
import {requireId,requireRequestId} from './values.js';
import {pgInteger} from './postgres-values.js';

// The current shared assert_actor/Admin email helpers take row locks. Use the
// reconciled lock-free snapshot helper for READ ONLY native authentication.
// A write restores the genuine parent BFF context before existing guards run.
export const MANAGED_SESSION_SQL='SELECT * FROM private.burimunsi_managed_admin_snapshot()';
export const MANAGED_CONTEXT_SQL='SELECT private.set_admin_email_context($1,$2,$3,$4) AS result';
const integer=value=>pgInteger(value,{minimum:0,code:'managed_session_required'});

/** Bind successful PIN authentication to an EXISTING verified Collect session.
 * The request gate verifies the provider token first. No JWT, refresh token or
 * PIN is retained here. Canonical financial guards remain independently required.
 */
export class PostgresManagedSessions {
  constructor({db,groupId}) {
    requireId(groupId);requirePort(db?.applicationWork,['assert']);
    Object.assign(this,{db,groupId,work:db.applicationWork});
  }
  async owned() {
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);
    await this.work.assert();
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);
  }
  async current(sql,principalUserId) {
    requirePort(sql,['unsafe']);requireId(principalUserId);await this.owned();
    let rows;try{rows=await sql.unsafe(MANAGED_SESSION_SQL);}catch{throw new BuriError('managed_session_required',401);}
    await this.owned();requireThat(rows.length===1,'managed_session_required',401);
    const r=rows[0],now=integer(r.now_ms),expiresAt=integer(r.expires_at)*1000;
    requireRequestId(r.principal_session_id);
    requireThat(Number.isSafeInteger(expiresAt)&&r.principal_user_id===principalUserId&&r.session_user_id===principalUserId&&
      r.surface==='admin'&&r.revoked_at===null&&expiresAt>now,'managed_session_required',401);
    requireThat(['on','off'].includes(r.transaction_read_only)&&['owner','admin','staff'].includes(r.shared_role),
      'managed_session_required',401);
    requireId(r.admin_id);requireRequestId(r.public_session_id);
    requireThat(typeof r.cookie_hash==='string'&&/^[a-f0-9]{64}$/.test(r.cookie_hash)&&
      typeof r.origin==='string'&&r.origin.length<=2048&&new URL(r.origin).protocol==='https:'&&new URL(r.origin).origin===r.origin,
      'managed_session_required',401);
    if(r.transaction_read_only==='off'){
      // This is the actual current BFF tuple selected for the signed GoTrue
      // session, not a client-supplied cookie or a manufactured AAL/email proof.
      // The shared setter locks/revalidates that tuple. Sensitive financial
      // guards still require its independently recorded, fresh email proof.
      let bound;
      try{bound=await sql.unsafe(MANAGED_CONTEXT_SQL,[r.admin_id,r.cookie_hash,r.origin,r.public_session_id]);}
      catch{throw new BuriError('managed_session_required',401);}
      requireThat(bound.length===1&&bound[0].result?.contract_version===1&&
        bound[0].result.public_session_id===r.public_session_id,'managed_session_required',401);
      await this.owned();
    }
    return Object.freeze({principalUserId,principalSessionId:r.principal_session_id,expiresAt,now,sharedRole:r.shared_role});
  }
  async prepareInTransaction(sql,input) {
    const s={...input};requireThat(s.groupId===this.groupId,'access_denied',403);
    requireRequestId(s.id);requireRequestId(s.accountId);
    const c=await this.current(sql,s.principalUserId),expiresAt=Math.min(s.expiresAt,c.expiresAt);
    requireThat(Number.isSafeInteger(s.createdAt)&&s.createdAt<=c.now&&Number.isSafeInteger(expiresAt)&&expiresAt>c.now,
      'managed_session_required',401);
    return Object.freeze({nativeSessionId:s.id,accountId:s.accountId,groupId:this.groupId,
      principalUserId:c.principalUserId,principalSessionId:c.principalSessionId,expiresAt,createdAt:s.createdAt});
  }
  async bindInTransaction(sql,proof) {
    const p={...proof};requireThat(p.groupId===this.groupId,'access_denied',403);
    requireRequestId(p.nativeSessionId);requireRequestId(p.accountId);requireRequestId(p.principalSessionId);
    const c=await this.current(sql,p.principalUserId);
    requireThat(c.principalSessionId===p.principalSessionId&&p.expiresAt<=c.expiresAt&&p.expiresAt>c.now,
      'managed_session_changed',409);
    const result=await sql.unsafe(`INSERT INTO private.burimunsi_session_links
      (native_session_id,collection_id,account_id,principal_user_id,principal_session_id,created_at,expires_at)
      SELECT s.id,s.collection_id,s.account_id,s.principal_user_id,$5,$6,$7
      FROM private.burimunsi_sessions s WHERE s.id=$1::uuid AND s.collection_id=$2 AND s.account_id=$3::uuid
       AND s.principal_user_id=$4 AND s.created_at=$6 AND s.expires_at=$7 AND NOT s.revoked
      RETURNING native_session_id`,[p.nativeSessionId,this.groupId,p.accountId,p.principalUserId,p.principalSessionId,p.createdAt,p.expiresAt]);
    requireThat(result.length===1,'managed_session_changed',409);await this.owned();
  }
  async assertInTransaction(sql,actor) {
    const a={...actor};requireThat(a.groupId===this.groupId,'access_denied',403);
    requireRequestId(a.sessionId);requireRequestId(a.id);
    const c=await this.current(sql,a.principalUserId);
    const rows=await sql.unsafe(`SELECT * FROM private.burimunsi_session_links
      WHERE collection_id=$1 AND native_session_id=$2::uuid`,[this.groupId,a.sessionId]);
    await this.owned();requireThat(rows.length===1,'managed_session_required',401);const p=rows[0];
    requireThat(p.account_id===a.id&&p.principal_user_id===c.principalUserId&&p.principal_session_id===c.principalSessionId&&
      integer(p.created_at)<=c.now&&integer(p.expires_at)>c.now&&integer(p.expires_at)===a.expiresAt,
      'managed_session_required',401);
    return Object.freeze({principalSessionId:c.principalSessionId,expiresAt:Math.min(a.expiresAt,c.expiresAt)});
  }
}
