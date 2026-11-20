import {requireThat} from './errors.js';
import {MAX_RWF,requireId} from './values.js';

export const HISTORY_LIMIT = 1000;
/** Only recorded canonical facts. A transaction observation is NOT a credit,
 * and a negative ledger entry is NOT automatically described as a refund.
 * Unknown lifecycle stages are not inferred from the payment's current status.
 */
export function projectPaymentHistory(rows,groupId,transactionId) {
  requireThat(Array.isArray(rows)&&rows.length<=HISTORY_LIMIT,'history_limit',413);
  const ids=new Set();let observations=0;
  const events=rows.map(row=>{
    requireThat(row&&row.groupId===groupId&&row.transactionId===transactionId,'history_scope_violation',503);
    requireThat(!['rawBody','raw_body','pinHash','tokenHash','gateway_token'].some(k=>Object.hasOwn(row,k)),'sensitive_projection_violation',503);
    requireId(row.canonicalRecordId);
    requireThat(['transaction_recorded','ledger_entry'].includes(row.kind),'invalid_history_event',503);
    const isObservation=row.kind==='transaction_recorded';
    requireThat(typeof row.recordedAt==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(row.recordedAt),'invalid_history_timestamp',503);
    const time=Date.parse(row.recordedAt);
    requireThat(Number.isFinite(time)&&new Date(time).toISOString().replace('.000Z','Z')===row.recordedAt.replace('.000Z','Z'),'invalid_history_timestamp',503);
    if(isObservation){
      observations++;
      requireThat(row.canonicalRecordId===transactionId&&row.amountRwf===null&&row.memberId===null,'invalid_history_event',503);
    }else{
      requireThat(Number.isSafeInteger(row.amountRwf)&&row.amountRwf!==0&&Math.abs(row.amountRwf)<=MAX_RWF,'invalid_history_amount',503);
      requireId(row.memberId);
    }
    const id=(isObservation?'transaction:':'ledger:')+row.canonicalRecordId;
    requireThat(!ids.has(id),'duplicate_history_event',503);ids.add(id);
    return {id,groupId,transactionId,kind:row.kind,recordedAt:new Date(time).toISOString(),amountRwf:row.amountRwf,memberId:row.memberId};
  });
  requireThat(observations===1,'history_observation_required',503);
  // Stable chronological order, including deterministic ties. No inferred stages.
  return events.sort((a,b)=>a.recordedAt<b.recordedAt?-1:a.recordedAt>b.recordedAt?1:a.id<b.id?-1:a.id>b.id?1:0);
}
