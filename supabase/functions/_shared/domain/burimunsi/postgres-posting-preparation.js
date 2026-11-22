import {requireThat,requirePort} from './errors.js';
import {canonicalJson,sha256} from './values.js';
import {pgInteger} from './postgres-values.js';
import {PostgresNativeAuthority} from './postgres-authority.js';
import {PostgresSharedPosting} from './postgres-shared-posting.js';
import {PostgresPostingAllocation} from './postgres-posting-allocation.js';
import {postingPreparationIdentity,postingEvidenceDescriptor} from './posting-preparation.js';

const check=v=>requireThat(v,'posting_preparation_unavailable',503);
const enc=new TextEncoder(),dec=new TextDecoder('utf-8',{fatal:true});
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const snapshot=v=>JSON.parse(canonicalJson(v));
const freeze=v=>{if(v&&typeof v==='object'){Object.values(v).forEach(freeze);Object.freeze(v);}return v;};
const integer=v=>pgInteger(v,{minimum:0,code:'posting_preparation_unavailable'});
const hash=/^[a-f0-9]{64}$/;
const shaBytes=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),v=>v.toString(16).padStart(2,'0')).join('');
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&Object.getPrototypeOf(v)===Object.prototype;
function route(v){
  if(typeof v!=='string')return null;
  if(/^07[2389][0-9]{7}$/.test(v))return '250'+v.slice(1);
  if(/^\+?2507[2389][0-9]{7}$/.test(v))return v.replace(/^\+/,'');
  return /^[0-9]{4,9}$/.test(v)?v:null;
}

// Original accepted source only; there is no payment/link to join before allocation.
export const POSTING_PREPARATION_SOURCE_SQL=`SELECT
  r.id AS raw_sms_id,r.owner_user_id AS raw_owner,r.object_key AS raw_key,
  r.object_sha256 AS raw_sha256,r.size_bytes AS raw_size,r.body_sha256,r.receiver_hash,
  a.id AS parse_attempt_id,a.source_body_sha256,a.outcome AS parse_outcome,
  a.profile_version AS parse_profile,a.profile_json AS parse_profile_json,
  c.credential_id,c.identity_sha256,c.completeness,c.source_mode,c.subscription_id,
  j.binding_id AS job_binding,j.binding_version AS job_binding_version,j.receiving_account_id AS job_account,
  j.mode AS job_mode,j.state AS job_state,j.last_error AS job_error,
  b.owner_user_id AS binding_owner,b.receiving_account_id AS binding_account,b.version AS binding_version,
  b.status AS binding_status,b.subscription_evidence,
  k.binding_id AS credential_binding,k.revoked_at AS credential_revoked,
  w.public_code,w.receiver_hash AS wallet_hash,w.status AS wallet_status,
  w.profile_status,w.profile_version,w.profile_json AS wallet_profile_json
  FROM app.momo_transactions t
  JOIN app.momo_transaction_sources s ON s.transaction_id=t.id AND s.parse_attempt_id=t.parse_attempt_id AND s.relation='accepted'
  JOIN app.sms_receipts r ON r.id=s.raw_sms_id
  JOIN app.momo_parse_attempts a ON a.id=s.parse_attempt_id AND a.raw_sms_id=r.id
  JOIN app.momo_gateway_captures c ON c.raw_sms_id=r.id
  JOIN app.momo_processing_jobs j ON j.raw_sms_id=r.id
  JOIN app.momo_gateway_credentials k ON k.id=c.credential_id
  JOIN app.momo_gateway_bindings b ON b.id=k.binding_id
  JOIN app.momo_receiving_accounts w ON w.id=t.receiving_account_id
  WHERE t.id=$1 AND r.id=$2 AND a.id=$3
  FOR UPDATE OF t,s,r,a,c,j,k,b,w`;

/** Admitted, pre-financial-transaction protected-evidence preparation.
 * Call only with a server-derived posting command, OUTSIDE an existing DB
 * transaction. Uses the same real runtime authority as the shared executor.
 * Each local SQL stage is admitted and locked; encryption and media.put run
 * between transactions. media MUST be Collect's bound SupabaseObjectBucket,
 * never a raw provider client or a replacement protocol. No routes, financial
 * writes, credential provisioning, activation, or alternate ledger are added.
 * A successful result is NOT posting authority: posting revalidates everything.
 */
export class PostgresPostingPreparation {
  constructor({authority,posting,allocation,media,encrypt,keyId}){
    check(authority instanceof PostgresNativeAuthority&&posting instanceof PostgresSharedPosting&&
      allocation instanceof PostgresPostingAllocation&&posting.allocation===allocation&&
      posting.evidence===allocation.custody&&authority.db===posting.db&&allocation.db===posting.db&&
      authority.groupId===posting.groupId&&allocation.groupId===posting.groupId);
    requirePort(media,['put']);check(typeof encrypt==='function'&&typeof keyId==='string'&&/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(keyId));
    check(same(media.namespace,allocation.custody.namespace));
    Object.assign(this,{authority,posting,allocation,media,encrypt,keyId,custody:allocation.custody});
  }
  async owned(){
    check(this.authority.db===this.posting.db&&this.posting.allocation===this.allocation&&
      this.posting.evidence===this.custody&&this.allocation.custody===this.custody&&
      same(this.media.namespace,this.custody.namespace));
    await this.authority.assertOwned();
    check(this.authority.db===this.posting.db&&this.posting.allocation===this.allocation&&
      this.posting.evidence===this.custody&&this.allocation.custody===this.custody&&
      same(this.media.namespace,this.custody.namespace));
  }
  async raw(sql,c,source){
    const r=await this.custody.one(sql,POSTING_PREPARATION_SOURCE_SQL,[c.receiptId,source.raw_sms_id,source.parse_attempt_id]);
    const receipt=c.receipt;
    check(r.raw_sms_id===source.raw_sms_id&&r.parse_attempt_id===source.parse_attempt_id&&
      r.raw_owner===r.binding_owner&&r.raw_key==='sms/'+r.raw_sms_id&&hash.test(r.raw_sha256)&&
      r.body_sha256===source.body_sha256&&r.source_body_sha256===r.body_sha256&&
      integer(r.raw_size)>0&&integer(r.raw_size)<=262144&&hash.test(r.identity_sha256)&&
      hash.test(r.receiver_hash)&&r.receiver_hash===r.wallet_hash&&r.parse_outcome==='accepted'&&
      r.completeness==='complete'&&r.source_mode==='live'&&r.job_mode==='live'&&r.job_state==='completed'&&r.job_error===null&&
      r.job_binding===receipt.sourceBindingId&&r.credential_binding===receipt.sourceBindingId&&
      r.job_account===receipt.receivingAccountId&&r.binding_account===receipt.receivingAccountId&&
      integer(r.job_binding_version)===receipt.sourceBindingVersion&&integer(r.binding_version)===receipt.sourceBindingVersion&&
      r.binding_status==='active'&&r.credential_revoked===null&&r.wallet_status==='active'&&r.profile_status==='approved'&&
      typeof r.profile_version==='string'&&r.profile_version.length>0&&r.parse_profile===r.profile_version&&
      typeof r.parse_profile_json==='string'&&r.parse_profile_json.length>0&&r.parse_profile_json.length<=65536&&
      r.parse_profile_json===r.wallet_profile_json&&route(r.public_code)!==null);
    r.source_scope=await this.custody.sourceScope(sql,{sourceId:r.raw_sms_id,ownerId:r.raw_owner,bodySha256:r.body_sha256,
      objectSha256:r.raw_sha256,bindingId:r.job_binding,bindingVersion:integer(r.job_binding_version),
      receivingAccountId:r.job_account,credentialId:r.credential_id});
    return r;
  }
  async source(sql,c,prior=null){
    await this.owned();
    const principal=await this.posting.authority(sql,c,'before_preparation',prior?.principal??null);
    const identity=await postingPreparationIdentity(c,principal);await this.owned();
    const source=snapshot(await this.allocation.source(sql,c));
    await this.allocation.noOverlap(sql,source,identity);
    const ns=await this.custody.one(sql,'SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE');
    check(same(ns,this.custody.namespace));
    const raw=await this.raw(sql,c,source);
    const expect={ownerId:raw.raw_owner,purpose:'sms_receipt',entityId:raw.raw_sms_id,
      plaintextSha256:raw.raw_sha256,aad:`sms:${raw.raw_sms_id}:${raw.raw_sha256}`};
    const journal=await this.custody.journal(sql,raw.raw_key,expect);
    const proof={principal,identity,source,raw,journal,namespace:ns};
    if(prior)check(same(proof,prior));
    return proof;
  }
  async body(sql,c,proof){
    const r=proof.raw,aad=proof.journal.reservation.aad;
    const binding=this.custody.postingBinding(c,proof.principal);
    const value=await this.custody.decrypt(await this.custody.sealed(binding,r.raw_key,proof.journal),aad);
    check(value instanceof Uint8Array&&value.length===integer(r.raw_size));
    const bytes=new Uint8Array(value);let body;
    try{
      await this.owned();check(await shaBytes(bytes)===r.raw_sha256);
      const payload=JSON.parse(dec.decode(bytes));
      check(object(payload)&&typeof payload.raw_body==='string'&&payload.raw_body.length>0&&
        !payload.raw_body.includes('\0')&&typeof payload.raw_sender==='string'&&payload.raw_sender.length>0&&
        payload.gateway_binding_id===c.receipt.sourceBindingId&&payload.gateway_binding_version===c.receipt.sourceBindingVersion&&
        payload.source_mode==='live'&&payload.completeness==='complete'&&
        route(payload.receiver_momo_number)===route(r.public_code)&&payload.subscription_id===r.subscription_id&&
        (payload.subscription_id===null||Number.isSafeInteger(payload.subscription_id)&&payload.subscription_id>=0));
      if(r.subscription_evidence!==null){const sub=JSON.parse(r.subscription_evidence);
        check(object(sub)&&Number.isSafeInteger(sub.subscription_id)&&sub.subscription_id>=0&&sub.subscription_id===payload.subscription_id);}
      body=enc.encode(payload.raw_body);
      check(body.length>0&&body.length<=16384&&dec.decode(body)===payload.raw_body&&
        await shaBytes(body)===r.body_sha256&&await sha256(canonicalJson(payload))===r.identity_sha256);
      await this.source(sql,c,proof);await this.posting.authority(sql,c,'after_preparation_source',proof.principal);
      return body;
    }catch(e){body?.fill(0);throw e;}finally{bytes.fill(0);}
  }
  async prepare(input){
    let body,c,completed=false;
    try{
      // Copy before the first await. Never trust a client principal/key/body.
      c=freeze(snapshot(input));
      check(c.groupId===this.authority.groupId&&c.intentId==null&&c.receipt?.state==='unallocated'&&
        c.receipt.hasConflict===false&&c.member?.id===c.memberId&&c.member.groupId===c.groupId&&
        c.member.active===true&&c.member.eligible===true&&Number.isSafeInteger(c.member.version)&&c.member.version>=1);
      const proof=await this.authority.write(sql=>this.source(sql,c));
      const binding=this.custody.postingBinding(c,proof.principal);
      if(!this.custody.qualificationOnly){
        const plan=await this.authority.write(async sql=>{
          await this.source(sql,c,proof);
          return this.custody.storageWitnesses.stage(binding,[{key:proof.raw.raw_key,journal:proof.journal}]);
        });
        // Real committed Storage read, outside every SQL transaction. A sealed
        // reservation in SQL is never substituted for this production proof.
        await this.custody.storageWitnesses.prefetch(plan);
      }
      body=await this.authority.write(async sql=>{
        await this.source(sql,c,proof);return this.body(sql,c,proof);
      });
      // Provider I/O is never performed while these SQL locks are held.
      await this.owned();
      const descriptor=postingEvidenceDescriptor(proof.identity,proof.raw.body_sha256,this.keyId);
      const sealed=await this.encrypt(new Uint8Array(body),descriptor.aad);await this.owned();
      check(typeof sealed==='string'&&enc.encode(sealed).length>0&&enc.encode(sealed).length<=524288);
      const envelope=JSON.parse(sealed);check(envelope?.v===1&&envelope.kid===this.keyId);
      // Verify the configured encryption binding before persisting any ciphertext.
      const decoded=await this.custody.decrypt(sealed,descriptor.aad);
      check(decoded instanceof Uint8Array&&decoded.length===body.length&&decoded.every((v,i)=>v===body[i]));
      await this.owned();
      await this.authority.write(async sql=>{await this.source(sql,c,proof);
        await this.posting.authority(sql,c,'before_preparation_storage',proof.principal);});
      await this.owned();
      const ack=await this.media.put(proof.identity.objectKey,sealed,{
        scope:descriptor.scope,aad:descriptor.aad,sourceDigest:descriptor.requestDigest,
        httpMetadata:descriptor.httpMetadata,customMetadata:descriptor.customMetadata});
      await this.owned();
      check(ack?.stored===true&&ack.metadataCommitted===true&&ack.key===proof.identity.objectKey&&
        typeof ack.operationId==='string'&&ack.operationId.length>0&&hash.test(ack.sha256)&&Number.isSafeInteger(ack.size)&&ack.size>0);
      if(!this.custody.qualificationOnly){
        const plan=await this.authority.write(async sql=>{
          await this.source(sql,c,proof);
          const journal=await this.custody.journal(sql,proof.identity.objectKey,{
            ownerId:proof.identity.ownerId,purpose:'payment_evidence',entityId:proof.identity.evidenceId,
            plaintextSha256:proof.raw.body_sha256,aad:descriptor.aad});
          check(journal.put.operation_id===ack.operationId&&journal.put.sha256===ack.sha256&&integer(journal.put.size)===ack.size);
          await this.posting.authority(sql,c,'after_preparation_storage',proof.principal);
          return this.custody.storageWitnesses.stage(binding,[
            {key:proof.raw.raw_key,journal:proof.journal},{key:proof.identity.objectKey,journal}]);
        });
        // Pin both original and prepared encrypted objects before BEGIN of the
        // financial command. payment_evidence INSERT may now scrub its own
        // reservation without discarding this privately verified ciphertext.
        await this.custody.storageWitnesses.prefetch(plan);
      }
      // Do not promote a provider response to proof. Read the real journal again.
      const prepared=await this.authority.write(async sql=>{
        await this.source(sql,c,proof);
        const prepared=await this.allocation.prepared(sql,proof.source,proof.identity,binding);
        check(prepared.sizeBytes===body.length&&prepared.journal.put.operation_id===ack.operationId&&
          prepared.journal.put.sha256===ack.sha256&&integer(prepared.journal.put.size)===ack.size);
        await this.source(sql,c,proof);
        await this.posting.authority(sql,c,'after_preparation_storage',proof.principal);
        return {prepared:true,contractVersion:1,requestDigest:proof.identity.requestDigest,
          paymentId:proof.identity.paymentId,evidenceId:proof.identity.evidenceId,
          objectKey:proof.identity.objectKey,bodySha256:proof.raw.body_sha256,sizeBytes:prepared.sizeBytes};
      });
      await this.owned();completed=true;return freeze(prepared);
    }catch{check(false);} // Redact raw messages, keys, SQL and provider details.
    finally{body?.fill(0);if(!completed&&c)this.release(c);} // Owned bytes only; JS copies cannot be guaranteed erased.
  }
  release(command){this.custody.storageWitnesses?.releaseCommand(command);}
}
