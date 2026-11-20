import {requireThat,requirePort} from './errors.js';
import {requireId,requireRequestId} from './values.js';
import {pgInteger} from './postgres-values.js';
import {hasPhonePinContext,PIN_CLOCK_SKEW_MS} from './phone-pin-request.js';

export const CURRENT_PIN_CONTEXT_SQL='SELECT *,floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms FROM private.burimunsi_pin_context()';
/** Native opaque proof, independently revalidated by SQL in each transaction.
 * A native session is never projected as a web/BFF/GoTrue or MFA session.
 */
export class PostgresPhonePinSessions {
  constructor({db,groupId}){requireId(groupId);requirePort(db?.applicationWork,['assert']);Object.assign(this,{db,groupId,work:db.applicationWork});}
  async current(sql,principalUserId){
    requireId(principalUserId);requireThat(hasPhonePinContext(this.db)&&this.db.applicationWork===this.work,'session_unavailable',401);
    await this.work.assert();const rows=await sql.unsafe(CURRENT_PIN_CONTEXT_SQL);
    requireThat(rows.length===1&&this.db.applicationWork===this.work,'session_unavailable',401);const r=rows[0];
    const now=pgInteger(r.now_ms,{minimum:0,code:'session_unavailable'}),expiresAt=pgInteger(r.expires_at,{minimum:now+1,code:'session_unavailable'});
    requireThat(r.collection_id===this.groupId&&r.principal_user_id===principalUserId&&
      pgInteger(r.created_at,{minimum:0,code:'session_unavailable'})-now<=PIN_CLOCK_SKEW_MS,'session_unavailable',401);
    requireRequestId(r.native_session_id);requireRequestId(r.account_id);
    return Object.freeze({authMethod:'phone_pin',principalUserId,principalSessionId:r.native_session_id,nativeAccountId:r.account_id,
      expiresAt,createdAt:pgInteger(r.created_at,{minimum:0,code:'session_unavailable'}),now,sharedRole:r.shared_role});
  }
  async assertInTransaction(sql,actor){
    const c=await this.current(sql,actor.principalUserId);
    requireThat(actor.groupId===this.groupId&&actor.id===c.nativeAccountId&&actor.sessionId===c.principalSessionId&&actor.expiresAt===c.expiresAt,'session_unavailable',401);
    return Object.freeze({principalSessionId:c.principalSessionId,expiresAt:c.expiresAt,authMethod:'phone_pin'});
  }
  // Login registration is the separate, credential-version-CAS SQL bootstrap.
  // The legacy managed login service must not create or bind native PIN proof.
  async prepareInTransaction(){requireThat(false,'invalid_credentials',401);}
  async bindInTransaction(){requireThat(false,'invalid_credentials',401);}
}
