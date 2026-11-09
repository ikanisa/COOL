import {requirePort,requireThat} from './errors.js';
import {requireId,sha256} from './values.js';
import {pgInteger} from './postgres-values.js';
import {PARSER_VERSION} from './receipt.js';

/** Preserves global pause and scoped approval; profile comes from the canonical
 * receiving account, never scheduler/request JSON. Trusted validation is imported
 * from the pinned Collect momo_pipeline module by the installed entrypoint.
 */
export class PostgresProcessingAdmission {
  constructor({db,groupId,env,validateProviderProfile}) {
    requireId(groupId);requirePort(db?.applicationWork,['assert']);
    requireThat(env&&typeof validateProviderProfile==='function','collect_adapter_required',503);
    Object.assign(this,{db,groupId,env,validateProviderProfile,work:db.applicationWork});
  }
  async owned() {
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);await this.work.assert();
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);
    requireThat(this.env.MOMO_PROCESSING_PAUSED==='false','processing_on_hold',503);
  }
  async assertInTransaction(sql,{groupId,profileVersion=null,policyVersion=null}={}) {
    requireThat(groupId===this.groupId,'access_denied',403);requirePort(sql,['unsafe']);await this.owned();
    const policies=await sql.unsafe(`SELECT p.*,floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms
      FROM private.burimunsi_integration_policies p JOIN private.burimunsi_scopes s USING(collection_id)
      WHERE p.collection_id=$1 AND s.enabled FOR SHARE OF p,s`,[groupId]);
    requireThat(policies.length===1,'processing_on_hold',503);const p=policies[0];
    requireThat(p.processing_enabled===true&&p.revoked_at===null&&typeof p.approved_version==='string'&&p.approved_version.length>0&&
      pgInteger(p.approved_at,{minimum:0})<=pgInteger(p.now_ms,{minimum:0})&&
      pgInteger(p.expires_at,{minimum:0})>pgInteger(p.now_ms,{minimum:0})&&p.native_parser_version===PARSER_VERSION,
      'processing_on_hold',503);
    const accounts=await sql.unsafe(`SELECT w.* FROM private.burimunsi_scopes s JOIN app.momo_receiving_accounts w
      ON w.id=s.receiving_account_id WHERE s.collection_id=$1 AND s.enabled FOR SHARE OF s,w`,[groupId]);
    requireThat(accounts.length===1,'profile_changed',409);const w=accounts[0],profile=this.validateProviderProfile(w);
    requireThat(profile&&w.provider==='mtn_momo'&&profile.date_format==='YMD_HMS'&&w.profile_version===p.provider_profile_version&&
      typeof w.profile_json==='string'&&await sha256(w.profile_json)===p.provider_profile_sha256&&
      (profileVersion===null||profileVersion===w.profile_version)&&(policyVersion===null||policyVersion===p.approved_version),
      'profile_changed',409);
    const projected=Object.freeze({version:w.profile_version,offsetMinutes:profile.utc_offset_minutes,
      senders:Object.freeze([...profile.sender_allowlist])});
    await this.owned();return Object.freeze({processingEnabled:true,policyVersion:p.approved_version,
      schedulerEnabled:p.scheduler_enabled===true,profile:projected});
  }
}
