import {requirePort,requireThat} from './errors.js';
import {requireId,requireRequestId,canonicalJson} from './values.js';
import {pgInteger} from './postgres-values.js';
import {PostgresStorageWitnesses,immutableStorageJournal} from './postgres-storage-witnesses.js';

const HASH=/^[a-f0-9]{64}$/;
const encoder=new TextEncoder();
const decoder=new TextDecoder('utf-8',{fatal:true});
const fail=()=>requireThat(false,'posting_evidence_unavailable',503);
const check=value=>{if(!value)fail();};
const integer=value=>pgInteger(value,{minimum:0,code:'posting_evidence_unavailable'});
const snapshot=value=>JSON.parse(canonicalJson(value));
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const sha=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),v=>v.toString(16).padStart(2,'0')).join('');
const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&Object.getPrototypeOf(value)===Object.prototype;
function route(v){
  if(typeof v!=='string')return null;
  if(/^07[2389][0-9]{7}$/.test(v))return '250'+v.slice(1);
  if(/^\+?2507[2389][0-9]{7}$/.test(v))return v.replace(/^\+/,'');
  return /^[0-9]{4,9}$/.test(v)?v:null;
}

// Original accepted parse only. Duplicate observations are not replacement sources.
// Use canonical parse_attempt_id, not a caller-selected raw SMS or latest attempt.
export const POSTING_CUSTODY_LINEAGE_SQL=`SELECT
  x.collection_id,x.receiving_account_id,x.source_binding_id,x.source_binding_version,x.policy_version,
  t.id AS transaction_id,t.parse_attempt_id AS canonical_attempt,t.event_kind,t.mode,t.has_conflict,t.allocation_state,
  t.provider_transaction_id,t.amount_minor,t.currency,t.provider,
  p.id AS payment_id,p.evidence_id,p.collection_id AS payment_group,p.amount_minor AS payment_amount,
  f.beneficiary_member_id,
  e.owner_user_id AS evidence_owner,e.collection_id AS evidence_group,e.object_key AS evidence_key,
  e.object_sha256 AS evidence_sha256,e.size_bytes AS evidence_size,e.currency AS evidence_currency,
  e.amount_minor AS evidence_amount,e.external_reference,e.receiver_network,e.receiver_momo_number,
  s.raw_sms_id,s.parse_attempt_id,s.relation,
  r.owner_user_id AS raw_owner,r.object_key AS raw_key,r.object_sha256 AS raw_sha256,r.size_bytes AS raw_size,r.body_sha256,r.receiver_hash,
  a.source_body_sha256,a.outcome AS parse_outcome,a.profile_version AS parse_profile,a.profile_json AS parse_profile_json,
  c.credential_id,c.identity_sha256,c.completeness,c.source_mode,c.subscription_id,
  j.binding_id AS job_binding,j.binding_version AS job_binding_version,j.receiving_account_id AS job_account,j.mode AS job_mode,j.state AS job_state,j.last_error AS job_error,
  b.owner_user_id AS binding_owner,b.receiving_account_id AS binding_account,b.version AS binding_version,b.status AS binding_status,b.subscription_evidence,
  k.binding_id AS credential_binding,k.revoked_at AS credential_revoked,
  w.provider AS wallet_provider,w.public_code,w.receiver_hash AS wallet_hash,w.status AS wallet_status,w.profile_status,w.profile_version,w.profile_json AS wallet_profile_json,
  EXISTS(SELECT 1 FROM app.momo_transaction_sources conflict WHERE conflict.transaction_id=t.id AND conflict.relation='conflict') AS source_conflict
  FROM private.burimunsi_transaction_scopes x
  JOIN private.burimunsi_scopes scope ON scope.collection_id=x.collection_id AND scope.receiving_account_id=x.receiving_account_id AND scope.enabled=true
  JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
  JOIN app.momo_financial_links f ON f.transaction_id=t.id
  JOIN app.payments p ON p.id=f.payment_id
  JOIN app.payment_evidence e ON e.id=p.evidence_id
  JOIN app.momo_transaction_sources s ON s.transaction_id=t.id AND s.parse_attempt_id=t.parse_attempt_id AND s.relation='accepted'
  JOIN app.sms_receipts r ON r.id=s.raw_sms_id
  JOIN app.momo_parse_attempts a ON a.id=s.parse_attempt_id AND a.raw_sms_id=r.id
  JOIN app.momo_gateway_captures c ON c.raw_sms_id=r.id
  JOIN app.momo_processing_jobs j ON j.raw_sms_id=r.id
  JOIN app.momo_gateway_credentials k ON k.id=c.credential_id
  JOIN app.momo_gateway_bindings b ON b.id=k.binding_id
  JOIN app.momo_receiving_accounts w ON w.id=t.receiving_account_id
  WHERE x.collection_id=$1 AND t.id=$2 AND p.id=$3 AND e.id=$4
  FOR UPDATE OF x,scope,t,f,p,e,s,r,a,c,j,k,b,w`;

/** Concrete SQL + local-decryption implementation of posting.evidence.
 * It uses the EXISTING committed Collect storage journal, with no bucket read,
 * upload, nested transaction, ledger write, new table or bypass role.
 * The executor/canonical adapter owns the admitted transaction and global lock.
 * Production requires an admission-bound storage preflight. Scrubbed reservation
 * bytes are supported only through its privately retained verified ciphertext.
 * The explicit qualification mode exercises the older local-journal fixtures.
 */
export class PostgresPostingCustody {
  #proofs=new WeakMap();
  constructor({db,groupId,namespace,decrypt,storageWitnesses=null,qualificationOnly=false}){
    requireId(groupId);requirePort(db.applicationWork,['assert']);
    requireThat(typeof decrypt==='function','collect_adapter_required',503);
    let origin;try{origin=new URL(namespace?.origin);}catch{fail();}
    check(origin.protocol==='https:'&&!origin.username&&!origin.password&&origin.origin===namespace.origin&&
      typeof namespace.bucket==='string'&&/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$/.test(namespace.bucket));
    this.db=db;this.groupId=groupId;this.namespace=Object.freeze({origin:origin.origin,bucket:namespace.bucket});
    this.decrypt=decrypt;this.work=db.applicationWork;
    check(typeof qualificationOnly==='boolean'&&(qualificationOnly?storageWitnesses===null:
      storageWitnesses instanceof PostgresStorageWitnesses&&storageWitnesses.db===db&&
      storageWitnesses.groupId===groupId&&same(storageWitnesses.namespace,this.namespace)));
    Object.defineProperties(this,{storageWitnesses:{value:storageWitnesses},qualificationOnly:{value:qualificationOnly}});
  }
  async owned(){
    check(this.db.applicationWork===this.work);await this.work.assert();check(this.db.applicationWork===this.work);
  }
  async query(sql,text,values=[]){
    await this.owned();const rows=await sql.unsafe(text,values);await this.owned();check(Array.isArray(rows));return rows;
  }
  async one(sql,text,values=[]){const rows=await this.query(sql,text,values);check(rows.length===1);return snapshot(rows[0]);}
  async sourceScope(sql,{sourceId,ownerId,bodySha256,objectSha256,bindingId,bindingVersion,receivingAccountId,credentialId}){
    if(this.qualificationOnly)return null;
    // The capture-time association is immutable. Today's receiving-wallet join
    // cannot move an old SMS into a newly assigned group. The original approved
    // custodian/installation is checked independently of operator PIN/session.
    const x=await this.one(sql,`SELECT x.source_id,x.collection_id,x.receiving_account_id,x.owner_user_id,
      x.source_body_sha256,x.object_sha256,x.binding_id,x.binding_version,x.credential_id,x.installation_id,
      x.custodian_account_id,x.grant_id,x.grant_version,x.provenance,x.proof_id,x.proof_sha256,
      x.associated_at::text AS associated_at FROM private.burimunsi_sms_source_scopes x
      JOIN app.momo_gateway_credentials k ON k.id=x.credential_id AND k.binding_id=x.binding_id
        AND k.installation_id::text=x.installation_id::text
      JOIN private.burimunsi_accounts a ON a.id=x.custodian_account_id AND a.collection_id=x.collection_id
        AND a.principal_user_id=x.owner_user_id
      WHERE x.source_id=$1 AND x.collection_id=$2 FOR UPDATE OF k,a`,[sourceId,this.groupId]);
    check(x.source_id===sourceId&&x.collection_id===this.groupId&&x.owner_user_id===ownerId&&
      x.source_body_sha256===bodySha256&&x.object_sha256===objectSha256&&x.binding_id===bindingId&&
      integer(x.binding_version)===bindingVersion&&x.receiving_account_id===receivingAccountId&&
      x.credential_id===credentialId&&typeof x.installation_id==='string'&&x.installation_id.length>0&&
      typeof x.custodian_account_id==='string'&&x.custodian_account_id.length>0&&
      typeof x.grant_id==='string'&&x.grant_id.length>0&&integer(x.grant_version)>0&&
      typeof x.provenance==='string'&&x.provenance.length>0&&typeof x.proof_id==='string'&&x.proof_id.length>0&&HASH.test(x.proof_sha256));
    return x;
  }
  async lineage(sql,d){
    const r=await this.one(sql,POSTING_CUSTODY_LINEAGE_SQL,[this.groupId,d.transactionId,d.paymentId,d.evidenceId]);
    const cmd=d.command,receipt=cmd.receipt;
    check(r.collection_id===this.groupId&&r.payment_group===this.groupId&&r.evidence_group===this.groupId&&
      r.transaction_id===d.transactionId&&r.payment_id===d.paymentId&&r.evidence_id===d.evidenceId&&
      r.beneficiary_member_id===cmd.memberId&&r.receiving_account_id===d.receivingAccountId&&
      r.source_binding_id===d.sourceBindingId&&integer(r.source_binding_version)===d.sourceBindingVersion&&
      r.event_kind==='incoming_receipt'&&r.mode==='live'&&integer(r.has_conflict)===0&&
      r.allocation_state==='linked'&&r.source_conflict===false&&r.relation==='accepted'&&r.parse_outcome==='accepted'&&
      r.parse_attempt_id===r.canonical_attempt&&r.completeness==='complete'&&r.source_mode==='live'&&r.job_mode==='live'&&r.job_state==='completed'&&r.job_error===null);
    requireId(r.raw_sms_id);requireId(r.parse_attempt_id);requireId(r.raw_owner);requireId(r.evidence_owner);
    check(r.raw_owner===r.binding_owner&&r.job_binding===d.sourceBindingId&&r.credential_binding===d.sourceBindingId&&
      r.job_account===d.receivingAccountId&&r.binding_account===d.receivingAccountId&&
      integer(r.job_binding_version)===d.sourceBindingVersion&&integer(r.binding_version)===d.sourceBindingVersion&&
      r.binding_status==='active'&&r.credential_revoked===null&&r.wallet_status==='active'&&r.profile_status==='approved'&&
      typeof r.profile_version==='string'&&r.profile_version.length>0&&r.parse_profile===r.profile_version&&typeof r.parse_profile_json==='string'&&r.parse_profile_json.length>0&&
      r.parse_profile_json.length<=65536&&r.parse_profile_json===r.wallet_profile_json);
    check(r.raw_key==='sms/'+r.raw_sms_id&&r.evidence_key==='evidence/'+d.evidenceId&&r.evidence_key===d.objectKey&&
      r.evidence_sha256===d.objectSha256&&integer(r.evidence_size)===d.sizeBytes&&
      HASH.test(r.raw_sha256)&&HASH.test(r.body_sha256)&&r.body_sha256===r.source_body_sha256&&
      r.evidence_sha256===r.body_sha256&&HASH.test(r.identity_sha256)&&
      HASH.test(r.receiver_hash)&&r.receiver_hash===r.wallet_hash);
    check(r.currency==='RWF'&&r.evidence_currency==='RWF'&&integer(r.amount_minor)===receipt.amountRwf&&
      integer(r.payment_amount)===receipt.amountRwf&&integer(r.evidence_amount)===receipt.amountRwf&&
      r.provider_transaction_id===receipt.providerTransactionId&&
      [r.provider_transaction_id,d.receivingAccountId+':'+r.provider_transaction_id].includes(r.external_reference)&&
      ['mtn_momo','airtel_money'].includes(r.provider)&&r.wallet_provider===r.provider&&r.receiver_network===r.provider&&
      route(r.public_code)!==null&&route(r.public_code)===route(r.receiver_momo_number));
    check(integer(r.raw_size)>0&&integer(r.raw_size)<=262144&&d.sizeBytes>0&&d.sizeBytes<=16384);
    if(cmd.mode==='automatic')check(r.policy_version===cmd.policyVersion);
    r.source_scope=await this.sourceScope(sql,{sourceId:r.raw_sms_id,ownerId:r.raw_owner,bodySha256:r.body_sha256,
      objectSha256:r.raw_sha256,bindingId:r.job_binding,bindingVersion:integer(r.job_binding_version),
      receivingAccountId:r.job_account,credentialId:r.credential_id});
    return r;
  }
  async journal(sql,key,{ownerId,purpose,entityId,plaintextSha256,aad}){
    // The enclosing Collect global mutation lock must also cover retention.
    // These are the original storage-journal key and owner advisory-lock salts.
    await this.query(sql,'SELECT pg_advisory_xact_lock(hashtextextended($1,7346369))',[key]);
    await this.query(sql,'SELECT pg_advisory_xact_lock(hashtextextended($1,7346370))',[ownerId]);
    check((await this.query(sql,'SELECT subject_id FROM app.privacy_retention_barriers WHERE subject_id=$1',[ownerId])).length===0);
    check((await this.query(sql,'SELECT operation_id FROM private.storage_delete_intents WHERE object_key=$1',[key])).length===0);
    const p=await this.one(sql,'SELECT object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state,active_attempt,upload_unresolved,delete_tombstone FROM private.storage_put_intents WHERE object_key=$1 FOR UPDATE',[key]);
    const m=await this.one(sql,'SELECT object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata FROM private.storage_objects WHERE object_key=$1 FOR UPDATE',[key]);
    const r=await this.one(sql,'SELECT object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body FROM private.storage_payload_reservations WHERE object_key=$1 FOR UPDATE',[key]);
    const scope={ownerId,purpose,entityId};
    check(p.object_key===key&&m.object_key===key&&r.object_key===key&&p.state==='committed'&&
      p.active_attempt===null&&p.upload_unresolved===false&&p.delete_tombstone===false&&
      typeof p.operation_id==='string'&&p.operation_id.length>0&&m.operation_id===p.operation_id&&
      HASH.test(p.fingerprint)&&m.fingerprint===p.fingerprint&&HASH.test(p.sha256)&&m.sha256===p.sha256&&
      integer(p.size)>0&&integer(p.size)<=524288&&integer(m.size)===integer(p.size)&&
      object(p.scope)&&same(p.scope,scope)&&same(m.scope,scope)&&same(r.scope,scope)&&
      r.aad===aad&&r.plaintext_sha256===plaintextSha256&&HASH.test(r.source_fingerprint)&&
      typeof r.key_id==='string'&&r.key_id.length>0&&r.key_id.length<=128&&
      object(p.custom_metadata)&&object(m.custom_metadata)&&same(p.custom_metadata,m.custom_metadata)&&
      p.custom_metadata.sha256===plaintextSha256&&p.custom_metadata.key_id===r.key_id&&
      p.custom_metadata.source_fingerprint===r.source_fingerprint&&
      object(p.http_metadata)&&same(p.http_metadata,m.http_metadata)&&p.http_metadata.contentType==='application/octet-stream'&&
      (r.sealed_body===null||typeof r.sealed_body==='string'));
    if(r.sealed_body!==null){
      check(encoder.encode(r.sealed_body).length===integer(p.size)&&await sha(encoder.encode(r.sealed_body))===p.sha256);
      const sealed=JSON.parse(r.sealed_body);check(sealed?.v===1&&sealed.kid===r.key_id);
    }else check(!this.qualificationOnly);
    await this.owned();
    return {put:p,metadata:m,reservation:r};
  }
  postingBinding(command,principal){return {kind:'posting',groupId:this.groupId,command:snapshot(command),principal:snapshot(principal)};}
  async sealed(binding,key,journal){
    return this.qualificationOnly?journal.reservation.sealed_body:this.storageWitnesses.sealed(binding,key,journal);
  }
  sameJournal(a,b){return same(immutableStorageJournal(a),immutableStorageJournal(b));}
  async assertInTransaction(sql,input){
    try{
      requirePort(sql,['unsafe']);const d=snapshot(input),cmd=d.command;
      check(cmd&&cmd.groupId===this.groupId&&['automatic','exception'].includes(cmd.mode));
      requireId(d.transactionId);requireId(d.paymentId);requireId(d.evidenceId);requireId(d.receivingAccountId);requireId(d.sourceBindingId);
      requireId(cmd.memberId);requireRequestId(cmd.requestId);
      check(d.transactionId===cmd.receiptId&&cmd.receipt?.id===d.transactionId&&cmd.receipt.groupId===this.groupId&&
        cmd.receipt.receivingAccountId===d.receivingAccountId&&cmd.receipt.sourceBindingId===d.sourceBindingId&&
        Number.isSafeInteger(d.sourceBindingVersion)&&d.sourceBindingVersion>0&&cmd.receipt.sourceBindingVersion===d.sourceBindingVersion&&
        Number.isSafeInteger(d.sizeBytes)&&d.sizeBytes>0&&HASH.test(d.objectSha256));
      const ns=await this.one(sql,'SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE');
      check(same(ns,this.namespace));
      const r=await this.lineage(sql,d);
      // Fixed order, used again for final readback. No arbitrary client key selection.
      const targets=[{key:r.raw_key,expect:{ownerId:r.raw_owner,purpose:'sms_receipt',entityId:r.raw_sms_id,plaintextSha256:r.raw_sha256,aad:`sms:${r.raw_sms_id}:${r.raw_sha256}`}},
        {key:r.evidence_key,expect:{ownerId:r.evidence_owner,purpose:'payment_evidence',entityId:d.evidenceId,plaintextSha256:r.evidence_sha256,aad:`evidence:${d.evidenceId}:${r.evidence_sha256}`}}].sort((a,b)=>a.key.localeCompare(b.key));
      const saved=new Map();
      for(const target of targets)saved.set(target.key,await this.journal(sql,target.key,target.expect));
      const principal=d.principal;
      if(!this.qualificationOnly)check(principal&&principal.groupId===this.groupId);
      const binding=this.qualificationOnly?null:this.postingBinding(cmd,principal);
      const decrypt=async target=>{
        const returned=await this.decrypt(await this.sealed(binding,target.key,saved.get(target.key)),target.expect.aad);
        check(returned instanceof Uint8Array&&returned.length>0&&returned.length<=262144);
        const bytes=new Uint8Array(returned); // Own bytes before the next awaited admission check.
        await this.owned();
        check(await sha(bytes)===target.expect.plaintextSha256);await this.owned();return bytes;
      };
      const rawTarget=targets.find(t=>t.key===r.raw_key),evidenceTarget=targets.find(t=>t.key===r.evidence_key);
      const rawBytes=await decrypt(rawTarget),evidenceBytes=await decrypt(evidenceTarget);
      check(rawBytes.length===integer(r.raw_size)&&evidenceBytes.length===d.sizeBytes);
      const payload=JSON.parse(decoder.decode(rawBytes));
      check(object(payload)&&typeof payload.raw_body==='string'&&payload.raw_body.length>0&&typeof payload.raw_sender==='string'&&payload.raw_sender.length>0&&
        payload.gateway_binding_id===d.sourceBindingId&&payload.gateway_binding_version===d.sourceBindingVersion&&
        payload.source_mode==='live'&&payload.completeness==='complete'&&route(payload.receiver_momo_number)===route(r.public_code)&&
        payload.subscription_id===r.subscription_id);
      let sub=null;
      if(r.subscription_evidence!==null){const binding=JSON.parse(r.subscription_evidence);check(object(binding));sub=binding.subscription_id;check(Number.isSafeInteger(sub)&&sub>=0);}
      check((sub===null||payload.subscription_id===sub)&&
        (payload.subscription_id===null||Number.isSafeInteger(payload.subscription_id)&&payload.subscription_id>=0));
      const bodyBytes=encoder.encode(payload.raw_body);
      check(bodyBytes.length===d.sizeBytes&&bodyBytes.length<=16384&&!payload.raw_body.includes('\0')&&
        await sha(bodyBytes)===r.body_sha256&&decoder.decode(evidenceBytes)===payload.raw_body&&
        await sha(encoder.encode(canonicalJson(payload)))===r.identity_sha256);
      // Awaited local decryption must not allow a changed journal, source or admission
      // to inherit the old result. Locks persist until the caller commits/rolls back.
      check(same(await this.lineage(sql,d),r));
      for(const target of targets){
        const current=await this.journal(sql,target.key,target.expect);
        check(this.sameJournal(current,saved.get(target.key)));
        if(!this.qualificationOnly)await this.sealed(binding,target.key,current);
      }
      check(same(await this.one(sql,'SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE'),ns));
      await this.owned();
      const proof=Object.freeze({verified:true});
      this.#proofs.set(proof,{descriptor:d,binding,lineage:r,namespace:ns,targets,saved});
      return proof;
    }catch{fail();}
  }
  async revalidateInTransaction(sql,proof){
    try{
      const saved=this.#proofs.get(proof);check(saved);await this.owned();
      check(same(await this.lineage(sql,saved.descriptor),saved.lineage));
      for(const target of saved.targets){
        const journal=await this.journal(sql,target.key,target.expect);
        check(this.sameJournal(journal,saved.saved.get(target.key)));
        if(!this.qualificationOnly)await this.sealed(saved.binding,target.key,journal);
      }
      check(same(await this.one(sql,'SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE'),saved.namespace));
      await this.owned();return {verified:true};
    }catch{fail();}
  }
}
