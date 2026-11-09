import {requireThat,requirePort} from './errors.js';
import {requireId,canonicalJson,sha256} from './values.js';
import {pgInteger} from './postgres-values.js';
import {PostgresPostingCustody} from './postgres-posting-custody.js';
import {postingPreparationIdentity,postingEvidenceDescriptor} from './posting-preparation.js';

const fail=()=>requireThat(false,'posting_allocation_unavailable',503);
const check=v=>{if(!v)fail();};
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const integer=v=>pgInteger(v,{minimum:0,code:'posting_allocation_unavailable'});
const snapshot=v=>JSON.parse(canonicalJson(v));
const encoder=new TextEncoder(),decoder=new TextDecoder('utf-8',{fatal:true});
function route(v){
  if(typeof v!=='string')return null;
  if(/^07[2389][0-9]{7}$/.test(v))return '250'+v.slice(1);
  if(/^\+?2507[2389][0-9]{7}$/.test(v))return v.replace(/^\+/,'');
  return /^[0-9]{4,9}$/.test(v)?v:null;
}
function timestamp(value){
  if(value instanceof Date)value=value.toISOString();
  check(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/.test(value)&&Number.isFinite(Date.parse(value)));
  return value;
}
export const POSTING_ALLOCATION_SOURCE_SQL=`SELECT
  x.collection_id,x.receiving_account_id,x.source_binding_id,x.source_binding_version,x.policy_version,
  b.enabled,b.version AS scope_version,t.id AS transaction_id,t.version AS transaction_version,
  t.amount_minor,t.currency,t.provider,t.provider_transaction_id,t.event_kind,t.has_conflict,t.allocation_state,t.mode,
  t.payer_name,t.transaction_at,t.created_at,
  a.status AS account_status,a.profile_status,a.profile_version,a.provider AS account_provider,a.public_code,
  g.status AS group_status,g.revision AS group_revision,g.receiver_network,g.receiver_momo_number,g.receiver_display_label,
  m.user_id AS member_id,m.active AS membership_active,m.revision AS membership_revision,u.access_status,u.member_type,u.revision AS user_revision,
  s.raw_sms_id,s.relation,s.parse_attempt_id,r.body_sha256,pa.source_body_sha256,pa.outcome AS parse_outcome,
  EXISTS(SELECT 1 FROM app.momo_financial_links f WHERE f.transaction_id=t.id) AS has_link,
  EXISTS(SELECT 1 FROM app.momo_transaction_sources conflict WHERE conflict.transaction_id=t.id AND conflict.relation='conflict') AS source_conflict
  FROM private.burimunsi_transaction_scopes x
  JOIN private.burimunsi_scopes b ON b.collection_id=x.collection_id AND b.receiving_account_id=x.receiving_account_id
  JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
  JOIN app.momo_receiving_accounts a ON a.id=t.receiving_account_id
  JOIN app.collections g ON g.id=x.collection_id
  JOIN app.memberships m ON m.collection_id=g.id AND m.user_id=$3
  JOIN app.users u ON u.id=m.user_id
  JOIN app.momo_transaction_sources s ON s.transaction_id=t.id AND s.parse_attempt_id=t.parse_attempt_id AND s.relation='accepted'
  JOIN app.sms_receipts r ON r.id=s.raw_sms_id
  JOIN app.momo_parse_attempts pa ON pa.id=s.parse_attempt_id AND pa.raw_sms_id=r.id
  WHERE x.collection_id=$1 AND t.id=$2
  FOR UPDATE OF x,b,t,a,g,m,u,s,r,pa`;

/** Concrete allocation stage for PostgresSharedPosting, not a public command.
 * Requires the caller's admitted transaction, canonical global mutation lock,
 * runtime-authorized principal, and protected evidence prepared before BEGIN.
 * It creates the existing payment/evidence/link rows and advances the source
 * exactly once. It NEVER posts a ledger entry, opens/commits a transaction,
 * uploads an object, supplies authority, or accepts an existing financial link.
 * The executor MUST run full custody, shared posting and canonical readback in
 * this same transaction. Every thrown error MUST cause the caller to roll back.
 */
export class PostgresPostingAllocation {
  constructor({db,groupId,custody}){
    requireId(groupId);requirePort(db?.applicationWork,['assert']);
    check(custody instanceof PostgresPostingCustody&&custody.db===db&&custody.groupId===groupId&&custody.work===db.applicationWork);
    Object.assign(this,{db,groupId,custody,work:db.applicationWork});
  }
  async owned(){check(this.db.applicationWork===this.work);await this.work.assert();check(this.db.applicationWork===this.work);}
  async query(sql,text,values=[]){await this.owned();const result=await sql.unsafe(text,values);await this.owned();check(Array.isArray(result));return result;}
  async source(sql,c){
    const rows=await this.query(sql,POSTING_ALLOCATION_SOURCE_SQL,[this.groupId,c.receiptId,c.memberId]);
    check(rows.length===1);const r=rows[0],destination=route(r.public_code);
    check(r.collection_id===this.groupId&&r.transaction_id===c.receiptId&&r.member_id===c.memberId&&
      r.enabled===true&&integer(r.scope_version)>=1&&integer(r.transaction_version)===c.expectedVersion&&
      r.receiving_account_id===c.receipt.receivingAccountId&&r.source_binding_id===c.receipt.sourceBindingId&&
      integer(r.source_binding_version)===c.receipt.sourceBindingVersion&&r.has_link===false&&r.source_conflict===false&&
      r.event_kind==='incoming_receipt'&&r.mode==='live'&&r.allocation_state==='unallocated'&&integer(r.has_conflict)===0&&
      r.currency==='RWF'&&integer(r.amount_minor)===c.receipt.amountRwf&&r.provider_transaction_id===c.receipt.providerTransactionId&&
      r.account_status==='active'&&r.profile_status==='approved'&&typeof r.profile_version==='string'&&r.profile_version.length>0&&
      ['mtn_momo','airtel_money'].includes(r.provider)&&r.account_provider===r.provider&&r.receiver_network===r.provider&&
      destination!==null&&route(r.receiver_momo_number)===destination&&r.group_status==='active'&&integer(r.group_revision)>=1&&
      integer(r.membership_active)===1&&integer(r.membership_revision)===c.member.version&&r.access_status==='active'&&
      typeof r.member_type==='string'&&r.member_type.length>0&&r.member_type!=='operator'&&integer(r.user_revision)>=1&&
      r.relation==='accepted'&&r.parse_outcome==='accepted'&&/^[a-f0-9]{64}$/.test(r.body_sha256)&&r.source_body_sha256===r.body_sha256&&
      (r.payer_name===null||typeof r.payer_name==='string'&&encoder.encode(r.payer_name).length<=8192)&&
      (r.receiver_display_label===null||typeof r.receiver_display_label==='string'&&encoder.encode(r.receiver_display_label).length<=1024));
    requireId(r.raw_sms_id);requireId(r.parse_attempt_id);
    if(c.mode==='automatic')check(r.policy_version===c.policyVersion);
    timestamp(r.transaction_at??r.created_at);return r;
  }
  async noOverlap(sql,r,identity){
    // Any earlier evidence for this wallet/reference is a reconciliation case,
    // including orphan evidence, a reversed payment or a different currency.
    // The enclosing global mutation lock is required: row locks cannot lock an
    // absent record or stop a non-cooperating writer from inserting a phantom.
    const previous=await this.query(sql,`SELECT e.id FROM app.payment_evidence e
      WHERE e.id=$1 OR e.object_key=$2 OR (e.receiver_network=$3 AND e.external_reference IN($4,$5)
      AND (CASE WHEN substr(e.receiver_momo_number,1,2)='07' AND length(e.receiver_momo_number)=10
        THEN '250'||substr(e.receiver_momo_number,2) ELSE replace(e.receiver_momo_number,'+','') END)=$6)
      LIMIT 2 FOR UPDATE`,[identity.evidenceId,identity.objectKey,r.provider,r.provider_transaction_id,
        r.receiving_account_id+':'+r.provider_transaction_id,route(r.public_code)]);
    check(previous.length===0);
    check((await this.query(sql,'SELECT id FROM app.payments WHERE id=$1 LIMIT 1 FOR UPDATE',[identity.paymentId])).length===0);
  }
  async prepared(sql,r,identity){
    const ns=await this.query(sql,'SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE');
    check(ns.length===1&&same(ns[0],this.custody.namespace));
    const scope={ownerId:identity.ownerId,purpose:'payment_evidence',entityId:identity.evidenceId};
    const aad=`evidence:${identity.evidenceId}:${r.body_sha256}`;
    // Reuse the concrete custody journal validator; no metadata-only fallback.
    const journal=await this.custody.journal(sql,identity.objectKey,{...scope,plaintextSha256:r.body_sha256,aad});
    await this.owned();
    const descriptor=postingEvidenceDescriptor(identity,r.body_sha256,journal.reservation.key_id);
    check(await sha256(canonicalJson(descriptor))===journal.reservation.source_fingerprint);await this.owned();
    const expectedMetadata={...descriptor.customMetadata,source_fingerprint:journal.reservation.source_fingerprint};
    check(same(journal.put.custom_metadata,expectedMetadata)&&same(journal.put.http_metadata,descriptor.httpMetadata));
    const returned=await this.custody.decrypt(journal.reservation.sealed_body,aad);
    check(returned instanceof Uint8Array&&returned.length>0&&returned.length<=16384);
    const bytes=new Uint8Array(returned);await this.owned();const body=decoder.decode(bytes);
    check(!body.includes('\0')&&sameBytes(encoder.encode(body),bytes)&&await sha256(body)===r.body_sha256);await this.owned();
    // A changed journal or source cannot inherit an earlier asynchronous proof.
    check(same(await this.custody.journal(sql,identity.objectKey,{...scope,plaintextSha256:r.body_sha256,aad}),journal));
    await this.owned();return {sizeBytes:bytes.length,journal};
  }
  async prepareInTransaction(sql,input,principalInput){
    try{
      requirePort(sql,['unsafe']);const c=snapshot(input),p=snapshot(principalInput);
      check(c.groupId===this.groupId&&c.receipt?.state==='unallocated'&&c.receipt.hasConflict===false&&
        c.member?.id===c.memberId&&c.member.groupId===this.groupId&&c.member.active===true&&c.member.eligible===true&&
        Number.isSafeInteger(c.member.version)&&c.member.version>=1&&c.intentId==null);
      const identity=await postingPreparationIdentity(c,p);await this.owned();
      const r=await this.source(sql,c);await this.noOverlap(sql,r,identity);
      const protectedEvidence=await this.prepared(sql,r,identity);
      check(same(await this.source(sql,c),r));await this.noOverlap(sql,r,identity);
      const clock=await this.query(sql,'SELECT clock_timestamp() AS allocation_at');
      check(clock.length===1);const at=timestamp(clock[0].allocation_at);
      const evidence=await this.query(sql,`INSERT INTO app.payment_evidence
        (id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,
         receiver_momo_number,amount_minor,currency,observed_at,created_at,receiver_network,receiver_display_label)
        VALUES($1,$2,$3,$4,$5,$6,'text/plain','operator_recorded',$7,$8,$9,'RWF',$10,$11,$12,$13) RETURNING id`,
        [identity.evidenceId,this.groupId,p.principalUserId,identity.objectKey,r.body_sha256,protectedEvidence.sizeBytes,
          r.receiving_account_id+':'+r.provider_transaction_id,r.receiver_momo_number,integer(r.amount_minor),
          timestamp(r.transaction_at??r.created_at),at,r.provider,r.receiver_display_label]);
      check(evidence.length===1&&evidence[0].id===identity.evidenceId);
      const payment=await this.query(sql,`INSERT INTO app.payments
        (id,collection_id,evidence_id,intent_id,member_id,amount_minor,currency,rail,revision,status,payer_display_name,created_at)
        VALUES($1,$2,$3,NULL,NULL,$4,'RWF','rwanda_momo',1,'recorded',$5,$6) RETURNING id`,
        [identity.paymentId,this.groupId,identity.evidenceId,integer(r.amount_minor),r.payer_name??'',at]);
      check(payment.length===1&&payment[0].id===identity.paymentId);
      const reason=c.mode==='exception'?c.reason:'Automatic verified identity policy: '+c.policyVersion;
      const link=await this.query(sql,`INSERT INTO app.momo_financial_links
        (transaction_id,payment_id,beneficiary_member_id,linked_by,reason,historical_existing,created_at)
        VALUES($1,$2,$3,$4,$5,0,$6) RETURNING transaction_id,payment_id`,
        [c.receiptId,identity.paymentId,c.memberId,p.principalUserId,reason,at]);
      check(link.length===1&&link[0].transaction_id===c.receiptId&&link[0].payment_id===identity.paymentId);
      const changed=await this.query(sql,`UPDATE app.momo_transactions SET allocation_state='linked',version=version+1,updated_at=$1
        WHERE id=$2 AND version=$3 AND allocation_state='unallocated' AND has_conflict=0 AND event_kind='incoming_receipt' AND mode='live'
        RETURNING id,version`,[at,c.receiptId,c.expectedVersion]);
      check(changed.length===1&&changed[0].id===c.receiptId&&integer(changed[0].version)===c.expectedVersion+1);
      await this.owned();return {paymentId:identity.paymentId};
    }catch{fail();} // No raw source, SQL, encrypted body, key or provider error in public errors.
  }
}
function sameBytes(a,b){return a.length===b.length&&a.every((v,i)=>v===b[i]);}
