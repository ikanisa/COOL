import {requirePort,requireThat} from './errors.js';
import {requireId,canonicalJson,normalizePhone} from './values.js';
import {pgInteger} from './postgres-values.js';
import {parseReceipt,receiptFingerprint,transactionKey} from './receipt.js';

/** Adopts an ALREADY accepted canonical transaction. Never creates a second
 * momo_transactions/payment/ledger row. Missing/conflicting/unresolved results
 * stay unavailable; caller-provided parsed fields are not authoritative.
 */
export class PostgresCanonicalAdoption {
  constructor({db,groupId,sources,admission}) {
    requireId(groupId);requirePort(db?.applicationWork,['assert']);requirePort(sources,['load']);requirePort(admission,['assertInTransaction']);
    Object.assign(this,{db,groupId,sources,admission,work:db.applicationWork});
  }
  async owned() {requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);await this.work.assert();
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);}
  async ingest(sql,input) {
    const {job,key,fingerprint}=JSON.parse(canonicalJson(input));requireThat(job.groupId===this.groupId,'access_denied',403);
    requireId(job.sourceId);await this.owned();
    const admission=await this.admission.assertInTransaction(sql,{groupId:this.groupId,profileVersion:job.profileVersion});
    const source=await this.sources.load(sql,job),receipt=parseReceipt(source,admission.profile);
    requireThat(key===transactionKey(job.receivingAccountId,receipt)&&fingerprint===await receiptFingerprint(receipt),'source_changed',409);
    const rows=await sql.unsafe(`SELECT t.*,s.raw_sms_id,s.relation,a.outcome AS parse_outcome,a.profile_version,
      a.source_body_sha256,EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict') AS source_conflict
      FROM app.momo_transaction_sources s JOIN app.momo_transactions t ON t.id=s.transaction_id AND t.parse_attempt_id=s.parse_attempt_id
      JOIN app.momo_parse_attempts a ON a.id=s.parse_attempt_id AND a.raw_sms_id=s.raw_sms_id
      WHERE s.raw_sms_id=$1 AND t.receiving_account_id=$2 AND s.relation='accepted' FOR UPDATE OF s,t,a`,[job.sourceId,job.receivingAccountId]);
    requireThat(rows.length===1,'canonical_source_not_accepted',503);const t=rows[0];requireId(t.id);
    const phone=receipt.fullPayerPhone===null?t.payer_identifier===receipt.payerPhoneRaw:
      (()=>{try{return normalizePhone(t.payer_identifier)===receipt.fullPayerPhone;}catch{return false;}})();
    const at=t.transaction_at instanceof Date?t.transaction_at.getTime():Date.parse(t.transaction_at);
    requireThat(Number.isFinite(at)&&t.raw_sms_id===job.sourceId&&t.parse_outcome==='accepted'&&t.profile_version===job.profileVersion&&
      t.source_body_sha256===job.sourceSha256&&t.source_conflict===false&&pgInteger(t.has_conflict,{minimum:0})===0&&
      t.mode==='live'&&t.event_kind==='incoming_receipt'&&t.provider===receipt.provider&&t.currency==='RWF'&&
      t.provider_transaction_id===receipt.ftId&&pgInteger(t.amount_minor,{minimum:1})===receipt.amountRwf&&
      t.payer_name===receipt.payerNameRaw&&phone&&new Date(at).toISOString()===receipt.at,'canonical_source_mismatch',409);
    await sql.unsafe(`INSERT INTO private.burimunsi_transaction_scopes
      (transaction_id,collection_id,receiving_account_id,source_binding_id,source_binding_version,policy_version,created_at)
      VALUES($1,$2,$3,$4,$5,$6,floor(extract(epoch FROM clock_timestamp())*1000)) ON CONFLICT(transaction_id) DO NOTHING`,
      [t.id,this.groupId,job.receivingAccountId,job.bindingId,job.bindingVersion,admission.policyVersion]);
    const scoped=await sql.unsafe('SELECT * FROM private.burimunsi_transaction_scopes WHERE transaction_id=$1 FOR UPDATE',[t.id]);
    requireThat(scoped.length===1&&scoped[0].collection_id===this.groupId&&scoped[0].receiving_account_id===job.receivingAccountId&&
      scoped[0].source_binding_id===job.bindingId&&pgInteger(scoped[0].source_binding_version,{minimum:1})===job.bindingVersion&&
      scoped[0].policy_version===admission.policyVersion,'source_scope_changed',409);
    await this.admission.assertInTransaction(sql,{groupId:this.groupId,profileVersion:job.profileVersion,policyVersion:admission.policyVersion});
    await this.owned();return Object.freeze({durable:true,transactionId:t.id,groupId:this.groupId,
      receivingAccountId:job.receivingAccountId,hasConflict:false});
  }
  async outcome(sql,{groupId,transactionId}) {
    requireThat(groupId===this.groupId,'access_denied',403);requireId(transactionId);await this.owned();
    const rows=await sql.unsafe(`SELECT t.id,t.has_conflict,t.allocation_state,t.amount_minor AS transaction_amount,t.currency AS transaction_currency,
      p.status,p.collection_id AS payment_group,p.amount_minor AS payment_amount,p.currency AS payment_currency,
      p.member_id,f.beneficiary_member_id,l.id AS ledger_entry_id,l.amount_minor AS ledger_amount,l.currency AS ledger_currency,
      EXISTS(SELECT 1 FROM app.ledger_entries c WHERE c.reverses_entry_id=l.id) AS compensated
      FROM private.burimunsi_transaction_scopes x JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
      LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id LEFT JOIN app.payments p ON p.id=f.payment_id
      LEFT JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=x.collection_id AND l.member_id=p.member_id AND l.kind='contribution'
      WHERE x.collection_id=$1 AND t.id=$2`,[groupId,transactionId]);
    await this.owned();requireThat(rows.length===1,'canonical_posting_outcome_missing',503);const r=rows[0];
    requireThat(pgInteger(r.has_conflict,{minimum:0})===0&&r.compensated===false,'transaction_conflict',409);
    if(r.allocation_state==='unallocated'&&r.ledger_entry_id===null&&r.status===null)
      return Object.freeze({groupId,transactionId,state:'unallocated',hasConflict:false});
    requireThat(r.allocation_state==='linked'&&r.payment_group===groupId&&['confirmed','reconciled'].includes(r.status)&&
      typeof r.ledger_entry_id==='string'&&r.member_id===r.beneficiary_member_id&&
      [r.transaction_currency,r.payment_currency,r.ledger_currency].every(v=>v==='RWF')&&
      pgInteger(r.transaction_amount,{minimum:1})===pgInteger(r.payment_amount,{minimum:1})&&
      pgInteger(r.payment_amount,{minimum:1})===pgInteger(r.ledger_amount,{minimum:1}),'canonical_posting_outcome_missing',503);
    requireId(r.ledger_entry_id);requireId(r.member_id);
    return Object.freeze({groupId,transactionId,state:'posted',ledgerEntryId:r.ledger_entry_id,hasConflict:false});
  }
}
