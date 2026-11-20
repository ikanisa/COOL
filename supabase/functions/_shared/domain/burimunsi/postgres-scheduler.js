import {requirePort,requireThat,BuriError} from './errors.js';
import {requireId,requireRequestId,canonicalJson} from './values.js';
import {pgInteger} from './postgres-values.js';
const safeCode=e=>e instanceof BuriError&&['processing_on_hold','profile_changed','lease_unavailable','worker_financial_authority_required'].includes(e.code)?e.code:'scheduler_failed';
const leaseOf=r=>Object.freeze({runId:r.run_id,owner:r.lease_owner,version:pgInteger(r.lease_version,{minimum:1}),
 profileVersion:r.profile_version,policyVersion:r.policy_version});

/** Coordination metadata, never financial authority. All operations stay inside
 * existing admitted transactions. Receipt/rematch leases remain authoritative.
 */
export class PostgresSchedulerStore {
  constructor({authority,admission,applicationWorkTuple}) {
    requirePort(authority,['write','assertOwned']);requirePort(admission,['assertInTransaction']);
    requireThat(typeof applicationWorkTuple==='function','collect_adapter_required',503);
    Object.assign(this,{authority,admission,applicationWorkTuple,groupId:authority.groupId});
    const work=authority.db.applicationWork;this.work=work;this.tuple=Object.freeze([...applicationWorkTuple(work)]);
    requireThat(work.kind==='jobs'&&this.tuple.length===3&&/^[a-f0-9]{64}$/.test(this.tuple[2]),'worker_admission_required',503);
    requireRequestId(this.tuple[0]);requireThat(Number.isSafeInteger(this.tuple[1])&&this.tuple[1]>0,'worker_admission_required',503);
  }
  async owned() {await this.authority.assertOwned();requireThat(this.authority.db.applicationWork===this.work&&this.work.kind==='jobs'&&
    canonicalJson(this.applicationWorkTuple(this.work))===canonicalJson(this.tuple),'worker_admission_required',503);}
  async now(sql) {return pgInteger((await sql.unsafe('SELECT floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms'))[0]?.now_ms,{minimum:0});}
  async policy(sql) {await this.owned();const p=await this.admission.assertInTransaction(sql,{groupId:this.groupId});
    requireThat(p.schedulerEnabled===true,'processing_on_hold',503);return p;}
  async claim({owner,leaseMs}) {
    requireId(owner);requireThat(Number.isInteger(leaseMs)&&leaseMs>=30000&&leaseMs<=600000,'invalid_worker_config',503);
    return this.authority.write(async sql=>{
      const p=await this.policy(sql);
      await sql.unsafe('INSERT INTO private.burimunsi_schedulers(collection_id) VALUES($1) ON CONFLICT(collection_id) DO NOTHING',[this.groupId]);
      const rows=await sql.unsafe('SELECT * FROM private.burimunsi_schedulers WHERE collection_id=$1 FOR UPDATE',[this.groupId]);
      requireThat(rows.length===1,'scheduler_unavailable',503);const r=rows[0],now=await this.now(sql);
      if(r.state==='running'&&pgInteger(r.lease_expires_at,{minimum:0})>now)return null;
      const updated=await sql.unsafe(`UPDATE private.burimunsi_schedulers SET state='running',run_id=$2::uuid,
        lease_owner=$3,lease_version=lease_version+1,lease_expires_at=$4,profile_version=$5,policy_version=$6,
        admission_id=$7::uuid,source_sha256=$8,started_at=$9,completed_at=NULL,last_outcome=NULL,summary=NULL
        WHERE collection_id=$1 RETURNING *`,[this.groupId,crypto.randomUUID(),owner,now+leaseMs,p.profile.version,
          p.policyVersion,this.tuple[0],this.tuple[2],now]);
      requireThat(updated.length===1,'scheduler_unavailable',503);await this.owned();
      return Object.freeze({lease:leaseOf(updated[0]),profile:p.profile});
    });
  }
  async locked(sql,lease) {
    requireRequestId(lease.runId);requireId(lease.owner);
    const rows=await sql.unsafe('SELECT * FROM private.burimunsi_schedulers WHERE collection_id=$1 FOR UPDATE',[this.groupId]);
    requireThat(rows.length===1,'lease_unavailable',409);const r=rows[0],now=await this.now(sql);
    requireThat(r.run_id===lease.runId&&r.lease_owner===lease.owner&&pgInteger(r.lease_version,{minimum:1})===lease.version&&
      r.admission_id===this.tuple[0]&&r.source_sha256===this.tuple[2]&&r.state==='running'&&
      r.policy_version===lease.policyVersion&&r.profile_version===lease.profileVersion&&
      pgInteger(r.lease_expires_at,{minimum:0})>now,'lease_unavailable',409);
    return {r,now};
  }
  async renew(lease,leaseMs) {
    const witness=JSON.parse(canonicalJson(lease));
    requireThat(Number.isInteger(leaseMs)&&leaseMs>=30000&&leaseMs<=600000,'invalid_worker_config',503);
    return this.authority.write(async sql=>{const p=await this.policy(sql),{r,now}=await this.locked(sql,witness);
      requireThat(r.policy_version===p.policyVersion&&r.profile_version===p.profile.version,'profile_changed',409);
      const rows=await sql.unsafe('UPDATE private.burimunsi_schedulers SET lease_expires_at=$2 WHERE collection_id=$1 RETURNING run_id',[this.groupId,now+leaseMs]);
      requireThat(rows.length===1,'lease_unavailable',409);await this.owned();return true;});
  }
  async finish(lease,summary) {
    const witness=JSON.parse(canonicalJson(lease)),report=JSON.parse(canonicalJson(summary));
    requireThat(report.runId===witness.runId&&['completed','yielded','stopped','failed'].includes(report.status)&&
      Object.keys(report).every(k=>['status','runId','receipts','rematches','code'].includes(k))&&
      (report.code===undefined||['processing_on_hold','profile_changed','lease_unavailable','worker_financial_authority_required','scheduler_failed'].includes(report.code)),
      'invalid_scheduler_result',503);
    for(const [kind,fields] of [['receipts',receiptFields],['rematches',rematchFields]]) {
      requireThat(report[kind]&&typeof report[kind]==='object'&&!Array.isArray(report[kind])&&
        Object.entries(report[kind]).every(([k,v])=>fields.includes(k)&&Number.isSafeInteger(v)&&v>=0),'invalid_scheduler_result',503);
    }
    requireThat(canonicalJson(report).length<=4096,'invalid_scheduler_result',503);
    // A new pause stops starts but does not prevent durable final checkpointing.
    return this.authority.write(async sql=>{await this.owned();const {now}=await this.locked(sql,witness);
      const rows=await sql.unsafe(`UPDATE private.burimunsi_schedulers SET state='idle',lease_expires_at=NULL,
        completed_at=$2,last_outcome=$3,summary=$4::jsonb WHERE collection_id=$1 RETURNING run_id`,[this.groupId,now,report.status,report]);
      requireThat(rows.length===1,'lease_unavailable',409);await this.owned();return {applied:true};});
  }
}
export const receiptFields=Object.freeze(['claimed','retained','posted','unallocated','rejected','retry','deadLetter','leaseLost','checkpointFailed']);
export const rematchFields=Object.freeze(['claimed','completed','yielded','postedObservations','unallocated','skipped','resumedOutcomes','replayedCheckpoints','retry','deadLetter','leaseLost','checkpointFailed']);
function add(target,result,fields) {
  requireThat(result&&typeof result.stopped==='boolean','invalid_scheduler_result',503);
  for(const field of fields){requireThat(Number.isSafeInteger(result[field])&&result[field]>=0,'invalid_scheduler_result',503);
    const total=(target[field]??0)+result[field];requireThat(Number.isSafeInteger(total),'invalid_scheduler_result',503);target[field]=total;}
  requireThat(result.claimed<=1,'invalid_scheduler_result',503);
}
/** One bounded invocation. Time budget limits NEW starts, never races/cancels
 * an in-flight financial command. No background timers or detached work.
 */
export async function runSchedulerCycle({store,workers,owner,receiptLimit=20,rematchLimit=5,targetsPerJob=20,
 leaseMs=180000,budgetMs=30000,monotonic=()=>performance.now()}) {
  requirePort(store,['claim','renew','finish']);requirePort(workers,['processReceipts']);requireId(owner);
  requireThat(Number.isInteger(receiptLimit)&&receiptLimit>=0&&receiptLimit<=100&&Number.isInteger(rematchLimit)&&rematchLimit>=0&&rematchLimit<=20&&
    receiptLimit+rematchLimit>0&&Number.isInteger(targetsPerJob)&&targetsPerJob>=1&&targetsPerJob<=100&&
    Number.isInteger(leaseMs)&&leaseMs>=30000&&leaseMs<=600000&&Number.isInteger(budgetMs)&&budgetMs>=1000&&budgetMs<=300000&&
    typeof monotonic==='function','invalid_worker_config',503);
  if(rematchLimit>0)requirePort(workers,['processRematches']);
  const started=monotonic();requireThat(Number.isFinite(started),'invalid_scheduler_clock',503);
  const claimed=await store.claim({owner,leaseMs});if(!claimed)return Object.freeze({status:'busy'});
  const lease=Object.freeze(JSON.parse(canonicalJson(claimed.lease))),profile=Object.freeze(JSON.parse(canonicalJson(claimed.profile)));
  requireThat(lease.owner===owner&&profile.version===lease.profileVersion,'invalid_scheduler_result',503);
  const result={status:'completed',runId:lease.runId,receipts:{},rematches:{}};let finalizing=false,previous=started;
  try {
    outer:for(const [kind,limit] of [['receipts',receiptLimit],['rematches',rematchLimit]])for(let i=0;i<limit;i++) {
      const now=monotonic();requireThat(Number.isFinite(now)&&now>=previous,'invalid_scheduler_clock',503);previous=now;
      if(now-started>=budgetMs){result.status='yielded';break outer;}
      requireThat(await store.renew(lease,leaseMs)===true,'lease_unavailable',409);
      const batch=kind==='receipts'?await workers.processReceipts({owner,profile,limit:1,leaseMs}):
        await workers.processRematches({owner,limit:1,targetsPerJob,leaseMs});
      add(result[kind],batch,kind==='receipts'?receiptFields:rematchFields);
      if(batch.stopped){result.status='stopped';break outer;}if(batch.claimed===0)break;
    }
    finalizing=true;requireThat((await store.finish(lease,result))?.applied===true,'scheduler_outcome_unknown',503);
    return Object.freeze(result);
  } catch(error) {
    // A lost finalization ACK is NOT permission to finalize/execute again.
    if(finalizing)throw new BuriError('scheduler_outcome_unknown',503);
    try{const saved=await store.finish(lease,{...result,status:'failed',code:safeCode(error)});
      if(saved?.applied!==true)throw new Error();}catch{throw new BuriError('scheduler_outcome_unknown',503);}
    throw new BuriError(safeCode(error),503);
  }
}
