import {requirePort,requireThat} from './errors.js';
import {requireId,requireRequestId} from './values.js';
import {pgInteger} from './postgres-values.js';

const HASH=/^[a-f0-9]{64}$/;
const REASONS=new Set(['evidence_unavailable','identity_unavailable','source_unavailable','processing_unavailable']);
const field=(value,key)=>{
  const d=value&&typeof value==='object'&&!Array.isArray(value)?Object.getOwnPropertyDescriptor(value,key):null;
  requireThat(d?.enumerable===true&&Object.hasOwn(d,'value'),'native_work_invalid',503);
  return d.value;
};
const lease=value=>{
  const jobId=field(value,'jobId'),leaseToken=field(value,'leaseToken'),leaseVersion=field(value,'leaseVersion');
  requireRequestId(jobId);requireRequestId(leaseToken);
  requireThat(Number.isSafeInteger(leaseVersion)&&leaseVersion>0,'native_work_invalid',503);
  return Object.freeze({jobId,leaseToken,leaseVersion});
};
const result=rows=>{
  requireThat(Array.isArray(rows)&&rows.length===1&&rows[0]?.result&&typeof rows[0].result==='object'&&!Array.isArray(rows[0].result),'native_work_unavailable',503);
  return rows[0].result;
};
const canonical=(value,groupId,expected)=>{
  const keys=['contractVersion','kind','groupId','sourceId','transactionId','jobId','workerGrantId','workerGrantVersion',
    'owner','leaseToken','leaseVersion','leaseExpiresAt','admissionId','admissionEpoch','sourceCodeSha256',
    'sourceKey','sourceKeyContentSha256','sourceKeyBodySha256','bodySha256','objectSha256','sourceFingerprint',
    'ownerUserId','objectSizeBytes','transactionMode'];
  const out=Object.fromEntries(keys.map(k=>[k,field(value,k)]));
  requireThat(out.contractVersion===1&&out.kind==='native_receipt'&&out.groupId===groupId&&
    out.jobId===expected.jobId&&out.leaseToken===expected.leaseToken&&out.leaseVersion===expected.leaseVersion,
    'native_work_unavailable',503);
  for(const k of ['groupId','sourceId','transactionId','owner','ownerUserId'])requireId(out[k]);
  for(const k of ['jobId','workerGrantId','leaseToken','admissionId'])requireRequestId(out[k]);
  for(const k of ['sourceCodeSha256','sourceKey','sourceKeyContentSha256','sourceKeyBodySha256','bodySha256','objectSha256','sourceFingerprint'])
    requireThat(typeof out[k]==='string'&&HASH.test(out[k]),'native_work_unavailable',503);
  for(const k of ['workerGrantVersion','leaseVersion','leaseExpiresAt','admissionEpoch','objectSizeBytes'])
    out[k]=pgInteger(out[k],{minimum:1,code:'native_work_unavailable'});
  requireThat(out.sourceKeyBodySha256===out.bodySha256&&out.objectSizeBytes<=131072&&
    ['live','historical'].includes(out.transactionMode),'native_work_unavailable',503);
  return Object.freeze(out);
};

/** Staging-only operational queue; the SQL functions enforce the live jobs
 * admission and original native provenance. A lease does not authorize a credit.
 * The custody/writer must call assertNativeLease on its existing transaction. */
export class PostgresNativeFinancialJobs {
  constructor({authority}) {
    requirePort(authority,['write']);requireId(authority.groupId);
    this.authority=authority;this.groupId=authority.groupId;Object.freeze(this);
  }
  async enqueue(grantId,sourceId){
    requireRequestId(grantId);requireId(sourceId);
    return this.authority.write(async sql=>Object.freeze(result(await sql.unsafe(
      'SELECT private.burimunsi_native_work_enqueue($1::uuid,$2) AS result',[grantId,sourceId]))));
  }
  async candidates(grantId,limit=25){
    requireRequestId(grantId);requireThat(Number.isInteger(limit)&&limit>=1&&limit<=50,'native_work_invalid',503);
    return this.authority.write(async sql=>{
      const rows=await sql.unsafe('SELECT private.burimunsi_native_work_candidates($1::uuid,$2::integer) AS result',[grantId,limit]);
      const ids=rows?.[0]?.result;requireThat(rows.length===1&&Array.isArray(ids)&&ids.length<=limit,'native_work_unavailable',503);
      for(const id of ids)requireRequestId(id);return Object.freeze([...ids]);
    });
  }
  async sources(grantId,limit=5){
    requireRequestId(grantId);requireThat(Number.isInteger(limit)&&limit>=1&&limit<=10,'native_work_invalid',503);
    return this.authority.write(async sql=>{
      const rows=await sql.unsafe('SELECT private.burimunsi_native_work_sources($1::uuid,$2::integer) AS result',[grantId,limit]);
      const ids=rows?.[0]?.result;requireThat(rows.length===1&&Array.isArray(ids)&&ids.length<=limit,'native_work_unavailable',503);
      for(const id of ids)requireRequestId(id);return Object.freeze([...ids]);
    });
  }
  async claim(grantId,jobId,leaseMs=180000){
    requireRequestId(grantId);requireRequestId(jobId);
    requireThat(Number.isInteger(leaseMs)&&leaseMs>=30000&&leaseMs<=600000,'native_work_invalid',503);
    return this.authority.write(async sql=>{
      const r=result(await sql.unsafe('SELECT private.burimunsi_native_work_claim($1::uuid,$2::uuid,$3::bigint) AS result',[grantId,jobId,leaseMs]));
      const out=lease(r);requireThat(out.jobId===jobId,'native_work_unavailable',503);
      return Object.freeze({...out,leaseExpiresAt:pgInteger(field(r,'leaseExpiresAt'),{minimum:1,code:'native_work_unavailable'})});
    });
  }
  async assertNativeLease(sql,work){
    requirePort(sql,['unsafe']);const w=lease(work);
    const r=result(await sql.unsafe('SELECT private.burimunsi_native_work_assert($1::uuid,$2::uuid,$3::bigint) AS result',[w.jobId,w.leaseToken,w.leaseVersion]));
    return canonical(r,this.groupId,w);
  }
  async defer(work,reason,delayMs){
    const w=lease(work);requireThat(REASONS.has(reason)&&Number.isInteger(delayMs)&&delayMs>=30000&&delayMs<=86400000,'native_work_invalid',503);
    return this.authority.write(async sql=>Object.freeze(result(await sql.unsafe(
      'SELECT private.burimunsi_native_work_defer($1::uuid,$2::uuid,$3::bigint,$4,$5::bigint) AS result',
      [w.jobId,w.leaseToken,w.leaseVersion,reason,delayMs]))));
  }
  async completeInTransaction(sql,work){
    requirePort(sql,['unsafe']);const w=lease(work);
    const r=result(await sql.unsafe('SELECT private.burimunsi_native_work_complete($1::uuid,$2::uuid,$3::bigint) AS result',
      [w.jobId,w.leaseToken,w.leaseVersion]));
    const jobId=field(r,'jobId'),state=field(r,'state'),transactionId=field(r,'transactionId');
    requireThat(jobId===w.jobId&&state==='completed','native_work_unavailable',503);requireId(transactionId);
    return Object.freeze({jobId,state,transactionId});
  }
}
