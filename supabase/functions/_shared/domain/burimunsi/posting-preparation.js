import {requireThat} from './errors.js';
import {requireId,requireRequestId,requireAmount,canonicalJson,sha256} from './values.js';

const HASH=/^[a-f0-9]{64}$/;
const KEY=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const check=value=>requireThat(value,'posting_preparation_invalid',503);
const frozen=value=>{if(value&&typeof value==='object'){Object.values(value).forEach(frozen);Object.freeze(value);}return value;};
const snapshot=value=>JSON.parse(canonicalJson(value));
async function namedId(kind,serialized){
  const h=await sha256('burimunsi.posting.'+kind+'.v1\n'+serialized);
  // SHA-256-derived UUIDv8. This is a stable object identity, not authentication.
  return `${h.slice(0,8)}-${h.slice(8,12)}-8${h.slice(13,16)}-${((parseInt(h[16],16)&3)|8).toString(16)}${h.slice(17,20)}-${h.slice(20,32)}`;
}
/** Pure identity calculation for the separately admitted evidence preparation.
 * Never accepts a client-selected object key. It performs no I/O and does not
 * prove source custody, worker admission, member identity, or posting authority.
 * Lease owner/version are deliberately excluded: a retry of the SAME command
 * may reuse protected bytes, but must reacquire all live authority checks.
 */
export async function postingPreparationIdentity(input,principalInput){
  // Take owned copies before the first await.
  const c=snapshot(input),p=snapshot(principalInput),r=c.receipt;
  check(['automatic','exception'].includes(c.mode)&&r&&c.groupId===r.groupId&&c.receiptId===r.id&&
    c.expectedVersion===r.version&&Number.isSafeInteger(c.expectedVersion)&&c.expectedVersion>=1&&c.expectedVersion<Number.MAX_SAFE_INTEGER&&
    r.currency==='RWF');
  const native=r.nativeOrigin??null;
  if(native===null){
    check(Number.isSafeInteger(r.sourceBindingVersion)&&r.sourceBindingVersion>=1);
    requireId(r.sourceBindingId);
  }else{
    // This calculates an identity only; it does not prove native source
    // integrity, recipient, worker authority, payer, or a payment. In
    // particular, historical/catch-up mode is recorded without relabelling.
    check(c.mode==='automatic'&&r.sourceBindingId===null&&r.sourceBindingVersion===null&&
      native&&typeof native==='object'&&!Array.isArray(native)&&
      Object.keys(native).sort().join(',')==='kind,sourceId,sourceTag,transactionMode'&&
      native.kind==='native_observation'&&native.sourceTag==='native.auto.v1'&&
      ['live','historical'].includes(native.transactionMode));
    requireId(native.sourceId);
  }
  for(const id of [c.groupId,c.receiptId,c.memberId,r.receivingAccountId,p.principalUserId])requireId(id);
  requireRequestId(c.requestId);requireRequestId(p.principalSessionId);requireRequestId(p.sessionId);requireId(p.actorId);
  check(p.groupId===c.groupId&&p.receiptId===c.receiptId&&p.requestId===c.requestId&&p.mode===c.mode);
  requireAmount(r.amountRwf);
  check(typeof r.providerTransactionId==='string'&&r.providerTransactionId.length>0&&r.providerTransactionId.length<=160&&!/[\u0000-\u001f\u007f]/.test(r.providerTransactionId));
  const target={contractVersion:1,groupId:c.groupId,transactionId:c.receiptId,memberId:c.memberId,requestId:c.requestId,
    expectedVersion:c.expectedVersion,mode:c.mode,principalUserId:p.principalUserId,principalSessionId:p.principalSessionId,
    actorId:p.actorId,sessionId:p.sessionId,receivingAccountId:r.receivingAccountId,
    ...(native===null?{sourceBindingId:r.sourceBindingId,sourceBindingVersion:r.sourceBindingVersion}:{nativeOrigin:native}),
    providerTransactionId:r.providerTransactionId,amountRwf:r.amountRwf,currency:r.currency};
  if(c.mode==='automatic'){
    check(p.kind==='admitted_worker'&&typeof c.policyVersion==='string'&&c.policyVersion.length>0&&c.policyVersion.length<=128&&
      !/[\u0000-\u001f\u007f]/.test(c.policyVersion)&&p.policyVersion===c.policyVersion&&
      Array.isArray(c.identityIds)&&c.identityIds.length>0&&c.identityIds.length<=100&&new Set(c.identityIds).size===c.identityIds.length);
    c.identityIds.forEach(requireId);Object.assign(target,{policyVersion:c.policyVersion,identityIds:c.identityIds});
  }else{
    check(p.kind==='native_operator'&&c.actorId===p.actorId&&c.sessionId===p.sessionId&&c.actor?.principalUserId===p.principalUserId&&
      typeof c.reason==='string'&&c.reason===c.reason.trim()&&c.reason.length>=8&&c.reason.length<=500&&!/[\u0000-\u001f\u007f]/.test(c.reason));
    target.reason=c.reason;
  }
  const serialized=canonicalJson(target),requestDigest=await sha256(serialized);
  const paymentId=await namedId('payment',serialized),evidenceId=await namedId('evidence',serialized);
  return frozen({contractVersion:1,requestDigest,paymentId,evidenceId,objectKey:'evidence/'+evidenceId,
    ownerId:p.principalUserId,target});
}
/** Exact descriptor passed to Collect's existing protected-object protocol.
 * The original raw SMS body must be independently obtained and protected BEFORE
 * the financial transaction. This helper neither reads nor writes that body.
 */
export function postingEvidenceDescriptor(identity,plaintextSha256,keyId){
  check(identity?.contractVersion===1&&HASH.test(identity.requestDigest)&&HASH.test(plaintextSha256)&&KEY.test(keyId));
  requireId(identity.evidenceId);requireId(identity.ownerId);
  check(identity.objectKey==='evidence/'+identity.evidenceId);
  return frozen({scope:{ownerId:identity.ownerId,purpose:'payment_evidence',entityId:identity.evidenceId},
    aad:`evidence:${identity.evidenceId}:${plaintextSha256}`,keyId,plaintextSha256,requestDigest:identity.requestDigest,
    httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:plaintextSha256,key_id:keyId}});
}
