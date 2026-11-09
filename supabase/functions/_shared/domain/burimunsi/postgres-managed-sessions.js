import {requirePort,requireThat,BuriError} from './errors.js';
import {requireId,requireRequestId} from './values.js';
import {pgInteger} from './postgres-values.js';

// No row locks: native authentication also runs in a READ ONLY snapshot.
export const MANAGED_SESSION_SQL=`WITH canonical AS MATERIALIZED (
 SELECT private.assert_actor() AS principal_user_id,api.current_session_id() AS principal_session_id,
 floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms)
 SELECT c.*,s.user_id AS session_user_id,s.surface,s.expires_at,s.revoked_at
 FROM canonical c JOIN app.auth_sessions s ON s.id=c.principal_session_id`;
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
    return Object.freeze({principalUserId,principalSessionId:r.principal_session_id,expiresAt,now});
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
