import {sha256} from './values.js';
/** Exact Collect gateway v2 contract, inspected at source 497de00b.
 * TLS success, count or an arbitrary `durable` flag cannot retire capture work.
 * Binding and owner context stay immutable on the local queued envelope.
 */
export async function matchesCollectAcknowledgement(envelope, response) {
  if (!envelope || !response || response.ok!==true) return false;
  const r=response.receipt;
  if (!r || r.contract_version!==2 || r.stored!==true || typeof r.raw_sms_id!=='string' || !r.raw_sms_id.length) return false;
  if (typeof envelope.id!=='string'||!envelope.id.length||typeof envelope.owner_user_id!=='string'||!envelope.owner_user_id.length||typeof envelope.raw_body!=='string')return false;
  if(r.owner_user_id!==envelope.owner_user_id || r.client_envelope_id!==envelope.id) return false;
  return r.body_sha256===await sha256(envelope.raw_body);
}
/** A batch is only a sequence of independent v2 outcomes, never a new wire protocol. */
export async function acknowledgedIds(pending, responses) {
  if(!Array.isArray(pending)||!Array.isArray(responses))return [];
  const byId=new Map(pending.map(p=>[p.id,p]));
  if(byId.size!==pending.length)return [];
  const seen=new Set(), accepted=[];
  for(const response of responses){
    const id=response?.receipt?.client_envelope_id;
    if(typeof id!=='string'||seen.has(id))return [];
    seen.add(id);const envelope=byId.get(id);
    if(envelope&&await matchesCollectAcknowledgement(envelope,response))accepted.push(id);
  }
  return accepted;
}
