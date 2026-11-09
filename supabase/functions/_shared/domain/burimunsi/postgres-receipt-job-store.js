import {requirePort,requireThat,BuriError} from './errors.js';
import {requireId,requireRequestId,sha256} from './values.js';
import {pgInteger} from './postgres-values.js';
import {parseReceipt,receiptFingerprint,transactionKey} from './receipt.js';

// Operational metadata only. No raw SMS, credentials, balances or ledger writes.
const TABLE='private.burimunsi_receipt_jobs';
const HASH=/^[a-f0-9]{64}$/;
const ERRORS=new Set(['processing_unavailable','processing_on_hold','lease_unavailable','source_scope_changed',
  'source_hash_changed','unsupported_receipt','unsupported_sender','incomplete_receipt','secret_bearing_message',
  'invalid_phone','invalid_amount','invalid_timestamp','transaction_conflict','transaction_unavailable',
  'canonical_ack_missing','canonical_posting_outcome_missing','canonical_writer_contract_violation',
  'provider_profile_required','profile_changed','source_changed','job_exhausted']);
export const safeProcessingCode=code=>ERRORS.has(code)?code:'processing_unavailable';
const integer=(value,minimum=0)=>pgInteger(value,{minimum,code:'invalid_job_record'});
const project=r=>r?Object.freeze({id:r.id,groupId:r.collection_id,sourceId:r.source_id,sourceSha256:r.source_sha256,
  bindingId:r.binding_id,bindingVersion:integer(r.binding_version,1),receivingAccountId:r.receiving_account_id,
  profileVersion:r.profile_version,owner:r.lease_owner,leaseVersion:integer(r.lease_version),
  leaseExpiresAt:r.lease_expires_at==null?null:integer(r.lease_expires_at),attempt:integer(r.attempt),
  maxAttempts:integer(r.max_attempts,4),transactionId:r.transaction_id??null,state:r.state}):null;

/** Uses an admitted Collect authority.write transaction, never an unrestricted
 * connection. admission must lock the current work fence/hold through the SAME
 * transaction. sources reuses Collect's retained-source authorization/decryption.
 * canonical ingests/reads Collect's EXISTING canonical transactions; not a ledger.
 * The SQL and ports are not deployed until actual schema/guard qualification. */
export class PostgresReceiptJobStore {
  constructor({authority,admission,sources,canonical,maxAttempts=4}){
    requirePort(authority,['write']);requireId(authority.groupId);
    requirePort(admission,['assertInTransaction']);
    requirePort(sources,['assertLineage','load']);
    requirePort(canonical,['ingest','outcome']);
    requireThat(Number.isInteger(maxAttempts)&&maxAttempts>=4&&maxAttempts<=10,'invalid_worker_config',503);
    Object.assign(this,{authority,admission,sources,canonical,maxAttempts});this.groupId=authority.groupId;
  }
  group(g){requireThat(g===this.groupId,'access_denied',403);}
  async time(tx){return integer((await tx.unsafe("SELECT floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms"))[0]?.now_ms);}
  async admitted(tx,profileVersion,job=null){
    requireThat(typeof profileVersion==='string'&&profileVersion.length>0&&profileVersion.length<=128,'provider_profile_required',503);
    const result=await this.admission.assertInTransaction(tx,{groupId:this.groupId,profileVersion,job});
    requireThat(result?.processingEnabled===true,'processing_on_hold',503);
    requireThat(result.profile?.version===profileVersion,'profile_changed',409);
    return result;
  }
  async assertProcessingAdmission({groupId,profileVersion}){
    this.group(groupId);return this.authority.write(tx=>this.admitted(tx,profileVersion));
  }
  /** Called by admitted ingress INSIDE its retained-source transaction. It may
   * retain work while processing is paused; it never lifts that pause. */
  async enqueueInTransaction(tx,source){
    requirePort(tx,['unsafe']);this.group(source?.groupId);
    for(const k of ['sourceId','bindingId','receivingAccountId'])requireId(source[k]);
    requireThat(Number.isSafeInteger(source.bindingVersion)&&source.bindingVersion>0&&HASH.test(source.sourceSha256)&&
      typeof source.profileVersion==='string'&&source.profileVersion.length>0&&source.profileVersion.length<=128,'invalid_job_source',503);
    // This port verifies original authenticated ingress lineage, not caller claims.
    const verified=await this.sources.assertLineage(tx,source);
    requireThat(verified===true,'source_scope_changed',409);
    const now=await this.time(tx),id=crypto.randomUUID();
    await tx.unsafe(`INSERT INTO ${TABLE}(id,collection_id,source_id,source_sha256,binding_id,binding_version,receiving_account_id,profile_version,max_attempts,created_at,next_attempt_at,updated_at)
      VALUES($1::uuid,$2,$3,$4,$5,$6,$7,$8,$9,$10,$10,$10)
      ON CONFLICT(collection_id,source_id) DO NOTHING`,
      [id,this.groupId,source.sourceId,source.sourceSha256,source.bindingId,source.bindingVersion,source.receivingAccountId,source.profileVersion,this.maxAttempts,now]);
    const saved=project((await tx.unsafe(`SELECT * FROM ${TABLE} WHERE collection_id=$1 AND source_id=$2 FOR UPDATE`,[this.groupId,source.sourceId]))[0]);
    requireThat(saved&&['groupId','sourceId','sourceSha256','bindingId','bindingVersion','receivingAccountId','profileVersion'].every(k=>saved[k]===source[k]),'source_changed',409);
    return {durable:true,jobId:saved.id,state:saved.state};
  }
  async claimNext({groupId,owner,profileVersion,leaseMs}){
    this.group(groupId);requireId(owner);
    requireThat(Number.isInteger(leaseMs)&&leaseMs>=30000&&leaseMs<=600000,'invalid_worker_config',503);
    return this.authority.write(async tx=>{
      await this.admitted(tx,profileVersion);const now=await this.time(tx);
      // A process that died on its final attempt must not strand RUNNING forever.
      await tx.unsafe(`UPDATE ${TABLE} SET state='dead_letter',lease_owner=NULL,lease_expires_at=NULL,last_error='job_exhausted',updated_at=$2
        WHERE collection_id=$1 AND profile_version=$3 AND attempt>=max_attempts
          AND ((state='running' AND lease_expires_at<=$2) OR state IN('queued','retry'))`,[this.groupId,now,profileVersion]);
      const rows=await tx.unsafe(`WITH candidate AS (
        SELECT id FROM ${TABLE} WHERE collection_id=$1 AND profile_version=$4 AND attempt<max_attempts
          AND ((state IN('queued','retry') AND next_attempt_at<=$2) OR (state='running' AND lease_expires_at<=$2))
        ORDER BY next_attempt_at,created_at,id LIMIT 1 FOR UPDATE SKIP LOCKED)
        UPDATE ${TABLE} j SET state='running',lease_owner=$3,lease_version=j.lease_version+1,
          lease_expires_at=$2+$5,attempt=j.attempt+1,updated_at=$2
        FROM candidate c WHERE j.id=c.id AND j.collection_id=$1 RETURNING j.*`,[this.groupId,now,owner,profileVersion,leaseMs]);
      return project(rows[0]);
    });
  }
  async locked(tx,{jobId,owner,leaseVersion}){
    requireRequestId(jobId);requireId(owner);
    requireThat(Number.isSafeInteger(leaseVersion)&&leaseVersion>0,'lease_unavailable',409);
    const job=project((await tx.unsafe(`SELECT * FROM ${TABLE} WHERE collection_id=$1 AND id=$2::uuid FOR UPDATE`,[this.groupId,jobId]))[0]);
    const now=await this.time(tx);
    requireThat(job&&job.state==='running'&&job.owner===owner&&job.leaseVersion===leaseVersion&&job.leaseExpiresAt>now,'lease_unavailable',409);
    return {job,now};
  }
  async lease(tx,command){
    const result=await this.locked(tx,command);
    const admission=await this.admitted(tx,result.job.profileVersion,result.job);
    requireThat(result.job.leaseExpiresAt>await this.time(tx),'lease_unavailable',409);
    return {...result,admission};
  }
  witness(job,owner,leaseVersion){
    this.group(job?.groupId);
    return {jobId:job.id,owner,leaseVersion};
  }
  async readSource(tx,job){
    const source=await this.sources.load(tx,job);
    requireThat(source?.groupId===this.groupId&&source.receivingAccountId===job.receivingAccountId&&
      source.bindingId===job.bindingId&&source.bindingVersion===job.bindingVersion&&source.id===job.sourceId,'source_scope_changed',409);
    requireThat(typeof source.body==='string'&&new TextEncoder().encode(source.body).length<=8192&&await sha256(source.body)===job.sourceSha256,'source_hash_changed',409);
    return source;
  }
  async loadSource({job,owner,leaseVersion}){
    return this.authority.write(async tx=>{const current=await this.lease(tx,this.witness(job,owner,leaseVersion));return this.readSource(tx,current.job);});
  }
  async commitCanonicalReceipt({job,owner,leaseVersion,key,fingerprint}){
    return this.authority.write(async tx=>{
      const current=await this.lease(tx,this.witness(job,owner,leaseVersion));
      const source=await this.readSource(tx,current.job);
      // Reparse the retained source under the server-selected profile. An in-memory
      // caller receipt or fingerprint is never authority to create a transaction.
      const receipt=parseReceipt(source,current.admission.profile);
      requireThat(key===transactionKey(current.job.receivingAccountId,receipt)&&fingerprint===await receiptFingerprint(receipt),'source_changed',409);
      const canonical=await this.canonical.ingest(tx,{job:current.job,source,receipt,key,fingerprint});
      requireThat(canonical?.durable===true&&typeof canonical.transactionId==='string'&&canonical.groupId===this.groupId&&
        canonical.receivingAccountId===current.job.receivingAccountId,'canonical_ack_missing',503);
      requireId(canonical.transactionId);
      requireThat(current.job.transactionId===null||current.job.transactionId===canonical.transactionId,'transaction_conflict',409);
      // A slow decrypt/ingest cannot publish a new result after its lease expired.
      const at=await this.time(tx);
      const updated=await tx.unsafe(`UPDATE ${TABLE} SET transaction_id=$5,updated_at=$4
        WHERE collection_id=$1 AND id=$2::uuid AND state='running' AND lease_owner=$3 AND lease_version=$6 AND lease_expires_at>$4 RETURNING id`,
        [this.groupId,current.job.id,owner,at,canonical.transactionId,leaseVersion]);
      requireThat(updated.length===1,'lease_unavailable',409);
      return {durable:true,transactionId:canonical.transactionId,hasConflict:canonical.hasConflict===true};
    });
  }
  /** Bind this method to tx.assertAutomaticAdmission on the canonical adapter.
   * It MUST receive the writer's existing SQL transaction, not start a new one. */
  async assertPostingLease(tx,{groupId,transactionId,work}){
    this.group(groupId);requireThat(work?.kind==='receipt','automatic_work_required',503);
    const current=await this.lease(tx,work);
    requireThat(current.job.transactionId===transactionId,'transaction_conflict',409);
    return {jobId:current.job.id,leaseVersion:current.job.leaseVersion,profileVersion:current.job.profileVersion};
  }
  async finishJob({jobId,owner,leaseVersion,transactionId}){
    return this.authority.write(async tx=>{
      const current=await this.lease(tx,{jobId,owner,leaseVersion});
      requireThat(current.job.transactionId===transactionId,'transaction_conflict',409);
      const outcome=await this.canonical.outcome(tx,{groupId:this.groupId,transactionId});
      requireThat(outcome?.transactionId===transactionId&&outcome.groupId===this.groupId&&outcome.hasConflict===false&&
        (outcome.state==='unallocated'||(outcome.state==='posted'&&typeof outcome.ledgerEntryId==='string'&&outcome.ledgerEntryId.length>0)),
        'canonical_posting_outcome_missing',503);
      const now=await this.time(tx);
      const updated=await tx.unsafe(`UPDATE ${TABLE} SET state='completed',lease_owner=NULL,lease_expires_at=NULL,last_error=NULL,updated_at=$4
        WHERE collection_id=$1 AND id=$2::uuid AND lease_owner=$3 AND lease_version=$5 AND state='running' AND lease_expires_at>$4 RETURNING id`,
        [this.groupId,jobId,owner,now,leaseVersion]);
      requireThat(updated.length===1,'lease_unavailable',409);return {applied:true};
    });
  }
  async failJob({jobId,owner,leaseVersion,permanent=false,code}){
    requireRequestId(jobId);requireId(owner);requireThat(Number.isSafeInteger(leaseVersion)&&leaseVersion>0,'lease_unavailable',409);
    // This cleanup deliberately does not require processing to remain enabled.
    // It may schedule a retry under a hold, but never dispatches held work.
    return this.authority.write(async tx=>{
      let current;
      try{current=await this.locked(tx,{jobId,owner,leaseVersion});}
      catch(error){if(error instanceof BuriError&&error.code==='lease_unavailable')return {applied:false,state:'lease_lost'};throw error;}
      // Read time after the row lock, not before an arbitrary lock wait.
      const now=current.now;
      const rows=await tx.unsafe(`UPDATE ${TABLE} SET
        state=CASE WHEN attempt>=max_attempts THEN 'dead_letter' WHEN $6 THEN 'rejected' ELSE 'retry' END,
        next_attempt_at=$4+least(3600000::bigint,1000::bigint*(1::bigint<<least(attempt,12))),
        lease_owner=NULL,lease_expires_at=NULL,last_error=$7,updated_at=$4
        WHERE collection_id=$1 AND id=$2::uuid AND state='running' AND lease_owner=$3 AND lease_version=$5 AND lease_expires_at>$4 RETURNING state`,
        [this.groupId,jobId,owner,now,leaseVersion,permanent===true,safeProcessingCode(code)]);
      return rows.length===1?{applied:true,state:rows[0].state}:{applied:false,state:'lease_lost'};
    });
  }
  async extendLease({jobId,owner,leaseVersion,leaseMs=180000}){
    requireThat(Number.isInteger(leaseMs)&&leaseMs>=30000&&leaseMs<=600000,'invalid_worker_config',503);
    return this.authority.write(async tx=>{
      const current=await this.lease(tx,{jobId,owner,leaseVersion});const now=await this.time(tx);
      const rows=await tx.unsafe(`UPDATE ${TABLE} SET lease_expires_at=greatest(lease_expires_at,$4+$6),updated_at=$4
        WHERE collection_id=$1 AND id=$2::uuid AND state='running' AND lease_owner=$3 AND lease_version=$5 AND lease_expires_at>$4 RETURNING lease_expires_at`,
        [this.groupId,current.job.id,owner,now,leaseVersion,leaseMs]);
      requireThat(rows.length===1,'lease_unavailable',409);return {expiresAt:integer(rows[0].lease_expires_at)};
    });
  }
}
