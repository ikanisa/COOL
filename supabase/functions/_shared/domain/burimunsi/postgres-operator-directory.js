import {requirePort,requireThat} from './errors.js';
import {requireId,normalizePhone} from './values.js';
import {hasPhonePinContext} from './phone-pin-request.js';

const CURRENT='SELECT private.burimunsi_operator_is_current($1,$2,$3,$4,$5::text[]) AS allowed';

/** Resolve only identities explicitly approved by the existing Collect owner.
 * This adapter creates no app.users/Auth identity, session, approval or grant.
 * The native staff command owns the same transaction and checks its actor first.
 */
export class PostgresOperatorDirectory {
  constructor({db,groupId,managedSessions}){
    requireId(groupId);requirePort(db?.applicationWork,['assert']);requirePort(managedSessions,['current']);
    Object.assign(this,{db,groupId,managedSessions,work:db.applicationWork});
  }
  async owned(){
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);await this.work.assert();
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);
  }
  async permits(sql,account){
    requirePort(sql,['unsafe']);requireThat(account?.groupId===this.groupId,'access_denied',403);
    requireId(account.principalUserId);
    requireThat(normalizePhone(account.phone)===account.phone&&['admin','staff'].includes(account.role)&&
      Array.isArray(account.capabilities),'access_denied',403);
    await this.owned();
    const rows=await sql.unsafe(CURRENT,[this.groupId,account.principalUserId,account.phone,account.role,account.capabilities]);
    await this.owned();return rows.length===1&&rows[0].allowed===true;
  }
  async assertInTransaction(sql,account){
    requireThat(await this.permits(sql,account),'access_denied',403);
  }
  async resolveStaff(sql,input){
    requirePort(sql,['unsafe']);requireThat(input?.groupId===this.groupId,'access_denied',403);
    requireId(input.actorId);requireThat(normalizePhone(input.phone)===input.phone,'invalid_phone');
    await this.owned();const parent=await this.managedSessions.current(sql,input.actorId);
    if(hasPhonePinContext(this.db)){
      requireThat(parent.authMethod==='phone_pin'&&parent.principalSessionId===input.actorNativeSessionId,'access_denied',403);
      const rows=await sql.unsafe('SELECT private.burimunsi_pin_resolve_staff($1,$2::uuid,$3,$4,$5,$6::text[],$7::uuid) AS result',
        [this.groupId,input.actorNativeSessionId,input.actorId,input.name,input.phone,input.capabilities,input.requestId]);
      await this.owned();requireThat(rows.length===1,'access_denied',403);requireId(rows[0].result?.id);
      return Object.freeze({id:rows[0].result.id});
    }
    requireThat(['owner','admin'].includes(parent.sharedRole),'access_denied',403);
    const rows=await sql.unsafe(`SELECT o.principal_user_id FROM private.burimunsi_operator_approvals o
      WHERE o.collection_id=$1 AND o.phone=$2 AND o.active AND o.role='staff'
      AND private.burimunsi_operator_is_current(o.collection_id,o.principal_user_id,o.phone,o.role,o.capabilities)
      FOR SHARE OF o`,[this.groupId,input.phone]);
    await this.owned();requireThat(rows.length===1,'access_denied',403);
    requireId(rows[0].principal_user_id);return Object.freeze({id:rows[0].principal_user_id});
  }
}
