import {requirePort,requireThat,BuriError} from './errors.js';
import {requireId,canonicalJson,sha256} from './values.js';
import {pgInteger} from './postgres-values.js';
import {PostgresPostingCustody} from './postgres-posting-custody.js';
const HASH=/^[a-f0-9]{64}$/;
const integer=value=>pgInteger(value,{minimum:0,code:'source_unavailable'});
const decoder=new TextDecoder('utf-8',{fatal:true}),encoder=new TextEncoder();
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const copy=v=>JSON.parse(canonicalJson(v));
const route=v=>typeof v==='string'&&/^07[2389][0-9]{7}$/.test(v)?'250'+v.slice(1):
 typeof v==='string'&&/^\+?2507[2389][0-9]{7}$/.test(v)?v.replace(/^\+/,''):
 typeof v==='string'&&/^[0-9]{4,9}$/.test(v)?v:null;
export const RETAINED_SOURCE_SQL=`SELECT r.id,r.owner_user_id,r.object_key,r.object_sha256,r.size_bytes,r.body_sha256,r.receiver_hash,
 c.credential_id,c.identity_sha256,c.completeness,c.source_mode,c.subscription_id,
 j.binding_id,j.binding_version AS job_binding_version,j.receiving_account_id,j.mode AS job_mode,j.state AS job_state,j.last_error,
 b.owner_user_id AS binding_owner,b.version AS binding_version,b.status AS binding_status,b.subscription_evidence,
 k.revoked_at AS credential_revoked,k.binding_id AS credential_binding,
 w.public_code,w.receiver_hash AS wallet_hash,w.status AS wallet_status,w.profile_status,w.profile_version,
 s.collection_id,s.active_binding_id,s.binding_version AS scope_binding_version
 FROM private.burimunsi_scopes s
 JOIN app.sms_receipts r ON r.id=$2
 JOIN app.momo_gateway_captures c ON c.raw_sms_id=r.id
 JOIN app.momo_gateway_credentials k ON k.id=c.credential_id
 JOIN app.momo_gateway_bindings b ON b.id=k.binding_id
 JOIN app.momo_processing_jobs j ON j.raw_sms_id=r.id AND j.binding_id=b.id
 JOIN app.momo_receiving_accounts w ON w.id=j.receiving_account_id AND w.id=b.receiving_account_id
 WHERE s.collection_id=$1 AND s.receiving_account_id=w.id AND s.enabled
 FOR UPDATE OF s,r,c,k,b,j,w`;

/** Loads the original committed encrypted journal, never replacement text from
 * HTTP, the newest SMS or a bucket fallback. Only completed canonical processing
 * is eligible. Caller owns the existing financial transaction/global lock.
 */
export class PostgresRetainedSources {
  constructor({db,groupId,namespace,decrypt}) {
    this.custody=new PostgresPostingCustody({db,groupId,namespace,decrypt});this.groupId=groupId;
  }
  async lineage(sql,sourceId) {
    requireId(sourceId);const r=await this.custody.one(sql,RETAINED_SOURCE_SQL,[this.groupId,sourceId]);
    requireThat(r.id===sourceId&&r.collection_id===this.groupId&&r.object_key==='sms/'+sourceId&&
      r.owner_user_id===r.binding_owner&&r.credential_binding===r.binding_id&&r.active_binding_id===r.binding_id&&
      integer(r.binding_version)>0&&integer(r.job_binding_version)===integer(r.binding_version)&&
      integer(r.scope_binding_version)===integer(r.binding_version)&&r.binding_status==='active'&&r.credential_revoked===null&&
      r.wallet_status==='active'&&r.profile_status==='approved'&&typeof r.profile_version==='string'&&r.profile_version.length>0&&
      r.completeness==='complete'&&r.source_mode==='live'&&r.job_mode==='live'&&r.job_state==='completed'&&r.last_error===null&&
      HASH.test(r.object_sha256)&&HASH.test(r.body_sha256)&&HASH.test(r.identity_sha256)&&
      HASH.test(r.receiver_hash)&&r.receiver_hash===r.wallet_hash&&integer(r.size_bytes)>0&&integer(r.size_bytes)<=262144,
      'source_unavailable',503);
    requireId(r.owner_user_id);requireId(r.binding_id);requireId(r.receiving_account_id);return r;
  }
  descriptor(r) {
    return Object.freeze({groupId:this.groupId,sourceId:r.id,sourceSha256:r.body_sha256,bindingId:r.binding_id,
      bindingVersion:integer(r.binding_version),receivingAccountId:r.receiving_account_id,profileVersion:r.profile_version});
  }
  async sourceForEnqueue(sql,sourceId) {return this.descriptor(await this.lineage(sql,sourceId));}
  async assertLineage(sql,source) {
    const expected=copy(source);requireThat(expected.groupId===this.groupId,'source_scope_changed',409);
    const actual=this.descriptor(await this.lineage(sql,expected.sourceId));
    requireThat(Object.keys(actual).every(k=>actual[k]===expected[k]),'source_scope_changed',409);return true;
  }
  async load(sql,job) {
    const expected=copy(job);requireThat(expected.groupId===this.groupId,'source_scope_changed',409);
    try {
      const r=await this.lineage(sql,expected.sourceId),actual=this.descriptor(r);
      requireThat(Object.keys(actual).every(k=>actual[k]===expected[k]),'source_scope_changed',409);
      const ns=await this.custody.one(sql,'SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE');
      requireThat(same(ns,this.custody.namespace),'source_unavailable',503);
      const target={ownerId:r.owner_user_id,purpose:'sms_receipt',entityId:r.id,
        plaintextSha256:r.object_sha256,aad:`sms:${r.id}:${r.object_sha256}`};
      const journal=await this.custody.journal(sql,r.object_key,target);
      const plaintext=await this.custody.decrypt(journal.reservation.sealed_body,target.aad);
      requireThat(plaintext instanceof Uint8Array&&plaintext.length===integer(r.size_bytes),'source_unavailable',503);
      const bytes=new Uint8Array(plaintext);await this.custody.owned();
      const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),v=>v.toString(16).padStart(2,'0')).join('');
      requireThat(digest===r.object_sha256,'source_unavailable',503);
      const payload=JSON.parse(decoder.decode(bytes));
      requireThat(payload&&typeof payload==='object'&&!Array.isArray(payload)&&typeof payload.raw_body==='string'&&
        encoder.encode(payload.raw_body).length>0&&encoder.encode(payload.raw_body).length<=8192&&
        typeof payload.raw_sender==='string'&&payload.raw_sender.length>0&&payload.raw_sender.length<=160&&
        payload.gateway_binding_id===r.binding_id&&payload.gateway_binding_version===integer(r.binding_version)&&
        payload.completeness==='complete'&&payload.source_mode==='live'&&route(r.public_code)!==null&&
        route(payload.receiver_momo_number)===route(r.public_code)&&
        Number.isSafeInteger(payload.subscription_id)&&payload.subscription_id>=0&&payload.subscription_id===r.subscription_id&&
        await sha256(payload.raw_body)===r.body_sha256&&await sha256(canonicalJson(payload))===r.identity_sha256,
        'source_unavailable',503);
      const sim=typeof r.subscription_evidence==='string'?JSON.parse(r.subscription_evidence):null;
      requireThat(sim&&sim.subscription_id===payload.subscription_id,'source_unavailable',503);
      requireThat(same(await this.lineage(sql,r.id),r)&&same(await this.custody.journal(sql,r.object_key,target),journal)&&
        same(await this.custody.one(sql,'SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE'),ns),
        'source_scope_changed',409);
      await this.custody.owned();return Object.freeze({id:r.id,groupId:this.groupId,receivingAccountId:r.receiving_account_id,
        bindingId:r.binding_id,bindingVersion:integer(r.binding_version),body:payload.raw_body,sender:payload.raw_sender,
        complete:true,subscriptionId:payload.subscription_id});
    } catch(error) {
      if(error instanceof BuriError&&['source_scope_changed','request_not_admitted'].includes(error.code))throw error;
      throw new BuriError('source_unavailable',503);
    }
  }
}
