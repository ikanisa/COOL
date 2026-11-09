import {requirePort,requireThat} from './errors.js';
import {requireId,normalizePhone} from './values.js';
import {pgInteger} from './postgres-values.js';
const integer=v=>pgInteger(v,{minimum:0,code:'identity_data_unavailable'});

/** Authoritative, effective-dated ownership proofs; never infer ownership from
 * app.users.momo_number, display name or a login lookup HMAC. The owner-managed
 * registry is empty by default. Runtime has SELECT, not approval/write grants.
 */
export class PostgresIdentityDirectory {
  constructor({db,groupId,maxRows=100000}) {
    requireId(groupId);requirePort(db?.applicationWork,['assert']);
    requireThat(Number.isInteger(maxRows)&&maxRows>=1&&maxRows<=100000,'invalid_identity_limit',503);
    Object.assign(this,{db,groupId,maxRows,work:db.applicationWork});
  }
  async owned() {
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);await this.work.assert();
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);
  }
  async query(sql,group,text,values=[]) {
    requireThat(group===this.groupId,'access_denied',403);requirePort(sql,['unsafe']);await this.owned();
    const rows=await sql.unsafe(text,[group,...values]);await this.owned();
    requireThat(Array.isArray(rows),'identity_data_unavailable',503);return rows;
  }
  async policy(sql,group) {
    const rows=await this.query(sql,group,`SELECT p.*,floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms
      FROM private.burimunsi_integration_policies p JOIN private.burimunsi_scopes s USING(collection_id)
      WHERE p.collection_id=$1 AND s.enabled FOR SHARE OF p,s`);
    requireThat(rows.length<=1,'identity_data_unavailable',503);const p=rows[0];
    if(!p||p.identity_enabled!==true||p.revoked_at!==null||!p.approved_version||
      integer(p.approved_at)>integer(p.now_ms)||integer(p.expires_at)<=integer(p.now_ms))
      return Object.freeze({groupId:group,approvedVersion:null,fullIdentityEnabled:false});
    return Object.freeze({groupId:group,approvedVersion:p.approved_version,fullIdentityEnabled:true});
  }
  async members(sql,group) {
    const rows=await this.query(sql,group,`SELECT u.id,m.collection_id,m.active,u.access_status FROM app.memberships m
      JOIN app.users u ON u.id=m.user_id WHERE m.collection_id=$1 ORDER BY u.id LIMIT $2 FOR SHARE OF m,u`,[this.maxRows+1]);
    requireThat(rows.length<=this.maxRows,'identity_snapshot_limit',413);const seen=new Set();
    return rows.map(r=>{requireId(r.id);const active=integer(r.active);
      requireThat(!seen.has(r.id)&&r.collection_id===group&&(active===0||active===1),'identity_data_unavailable',503);seen.add(r.id);
      return Object.freeze({id:r.id,groupId:group,active:active===1,eligible:r.access_status==='active'});});
  }
  async verified(sql,group) {
    const policy=await this.policy(sql,group);if(!policy.fullIdentityEnabled)return [];
    // Do not filter by active membership: it must not erase a competing owner.
    const rows=await this.query(sql,group,`SELECT p.*,floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms
      FROM private.burimunsi_identity_proofs p WHERE collection_id=$1 AND policy_version=$2 AND state='verified' AND revoked_at IS NULL
      ORDER BY id LIMIT $3 FOR SHARE`,[policy.approvedVersion,this.maxRows+1]);
    requireThat(rows.length<=this.maxRows,'identity_snapshot_limit',413);const seen=new Set();
    return rows.map(r=>{requireId(r.id);requireId(r.member_id);requireId(r.approved_by);
      requireThat(!seen.has(r.id)&&r.collection_id===group&&r.policy_version===policy.approvedVersion&&r.state==='verified'&&r.revoked_at===null&&
        r.verification_method==='collect_owner_review'&&r.purpose==='own_contributions'&&
        typeof r.source_reference==='string'&&r.source_reference.length>0&&r.source_reference.length<=512&&
        /^[a-f0-9]{64}$/.test(r.evidence_sha256??'')&&integer(r.approved_at)<=integer(r.now_ms),'identity_data_unavailable',503);seen.add(r.id);
      const from=integer(r.valid_from),until=r.valid_until===null?null:integer(r.valid_until);
      requireThat(from<=8640000000000000&&(until===null||until>from&&until<=8640000000000000),'identity_data_unavailable',503);
      const phone=normalizePhone(r.phone);requireThat(phone===r.phone,'identity_data_unavailable',503);
      return Object.freeze({id:r.id,groupId:group,memberId:r.member_id,phone,status:'verified',authority:'collect_verified',
        purpose:'own_contributions',validFrom:new Date(from).toISOString(),validUntil:until===null?null:new Date(until).toISOString()});});
  }
}
