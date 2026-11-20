import {requireThat,requirePort} from './errors.js';
const integer=v=>{const n=Number(v);requireThat(Number.isSafeInteger(n)&&n>=0,'invalid_health_snapshot',503);return n;};
/** No receipt bodies, phone numbers, FT references, PINs or tokens are projected. */
export class PostgresOperationsHealth {
  constructor({authority}){requirePort(authority,['read']);requireThat(typeof authority.groupId==='string','group_required',503);this.authority=authority;}
  async snapshot(){
    return this.authority.read(async tx=>{
      const row=(await tx.unsafe(`WITH clock AS (SELECT floor(extract(epoch FROM clock_timestamp())*1000)::bigint AS now_ms)
        SELECT clock.now_ms::text AS now_ms,
          count(*) FILTER(WHERE j.state IN('queued','retry','running'))::text AS pending,
          coalesce(clock.now_ms-min(j.created_at) FILTER(WHERE j.state IN('queued','retry','running')),0)::text AS oldest_pending_ms,
          count(*) FILTER(WHERE j.state='running' AND j.lease_expires_at<=clock.now_ms)::text AS expired_leases,
          count(*) FILTER(WHERE j.state='dead_letter')::text AS dead_letters,
          count(*) FILTER(WHERE j.state='rejected')::text AS rejected,
          count(*) FILTER(WHERE j.state='completed')::text AS completed
        FROM clock LEFT JOIN private.burimunsi_receipt_jobs j ON j.collection_id=$1
        GROUP BY clock.now_ms`,[this.authority.groupId]))[0];
      requireThat(row,'invalid_health_snapshot',503);
      return Object.freeze({groupId:this.authority.groupId,asOfMs:integer(row.now_ms),pending:integer(row.pending),
        oldestPendingMs:integer(row.oldest_pending_ms),expiredLeases:integer(row.expired_leases),
        deadLetters:integer(row.dead_letters),rejected:integer(row.rejected),completedJobs:integer(row.completed),
        basis:'durable_processing_jobs_not_capture_heartbeat_or_ledger_total'});
    });
  }
}
/** Thresholds are mandatory deployment inputs. These tests do not authorize or
 * deliver alerts; the admitted scheduler must dispatch to the approved on-call. */
export function evaluateOperationalAlerts(snapshot,thresholds){
  requireThat(snapshot&&thresholds,'alert_thresholds_required',503);
  const rules=[['pending','maxPending','processing_backlog'],['oldestPendingMs','maxOldestPendingMs','processing_age'],
    ['expiredLeases','maxExpiredLeases','worker_leases_expired'],['deadLetters','maxDeadLetters','processing_dead_letters']];
  return rules.flatMap(([metric,threshold,code])=>{
    requireThat(Number.isSafeInteger(snapshot[metric])&&snapshot[metric]>=0&&Number.isSafeInteger(thresholds[threshold])&&thresholds[threshold]>=0,'invalid_alert_threshold',503);
    return snapshot[metric]>thresholds[threshold]?[{code,observed:snapshot[metric],threshold:thresholds[threshold]}]:[];
  });
}
