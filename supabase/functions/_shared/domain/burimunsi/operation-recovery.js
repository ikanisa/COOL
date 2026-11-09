import {requireThat} from './errors.js';
import {requireId,requireRequestId} from './values.js';

export const OPERATION_RECOVERY_PROTOCOL='burimunsi.operation-recovery.v1';
const allowedOperations=new Set([
  'burimunsi.allocate','burimunsi.enroll','burimunsi.membership',
  'burimunsi.staff.create','burimunsi.staff.edit','burimunsi.staff.reset',
  'burimunsi.staff.disable','burimunsi.staff.enable','burimunsi.staff.remove'
]);
export function requireOriginDigest(value){
  requireThat(typeof value==='string'&&/^[a-f0-9]{64}$/.test(value),'invalid_recovery_origin',400);
  return value;
}
/** An expired/revoked original session is immutable evidence, NEVER authority.
 * The adapter loads both session snapshots in the current authorized read
 * transaction. No mutable account remapping supplies original identity. */
export function projectRecoveredOutcome({proof,actor,groupId,requestId,originDigest,now}){
  requireRequestId(requestId);requireOriginDigest(originDigest);
  requireThat(proof&&proof.origin&&proof.current,'operation_recovery_unavailable',409);
  const {origin,current,receipt}=proof;
  for(const session of [origin,current]){
    requireId(session.groupId);requireId(session.principalUserId);
    for(const key of ['sessionId','actorId','installationId','grantId'])requireRequestId(session[key]);
    requireThat(Number.isSafeInteger(session.grantVersion)&&session.grantVersion>0,'invalid_recovery_proof',503);
  }
  requireThat(current.sessionId===actor.sessionId&&current.groupId===groupId&&current.actorId===actor.id&&
    current.principalUserId===actor.principalUserId&&current.installationId===actor.installationId,
    'operation_recovery_denied',403);
  requireThat(origin.tokenHash===originDigest&&origin.groupId===current.groupId&&origin.actorId===current.actorId&&
    origin.principalUserId===current.principalUserId&&origin.installationId===current.installationId&&
    origin.grantId===current.grantId&&origin.grantVersion===current.grantVersion,
    'operation_recovery_denied',403);
  requireThat(Number.isSafeInteger(now)&&Number.isSafeInteger(origin.createdAt)&&origin.createdAt>=0&&origin.createdAt<=now,
    'invalid_recovery_proof',503);
  let state='pending';
  if(receipt!==null){
    requireThat(receipt&&receipt.groupId===groupId&&receipt.actorId===current.actorId&&
      receipt.requestId===requestId&&receipt.sessionId===origin.sessionId&&allowedOperations.has(receipt.operation)&&
      Number.isSafeInteger(receipt.createdAt)&&receipt.createdAt>=origin.createdAt&&receipt.createdAt<=now,
      'invalid_recovery_receipt',503);
    state='committed';
  }
  // Absence is not proof of no effect. No invented rejection or command payload.
  return {protocol:OPERATION_RECOVERY_PROTOCOL,requestId,state,originDigest,
    groupId,actorId:current.actorId,installationId:current.installationId};
}
