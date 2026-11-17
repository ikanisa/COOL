import {requireThat} from './errors.js';
import {requireId,requireRequestId} from './values.js';

export const OPERATION_RECOVERY_PROTOCOL='burimunsi.operation-recovery.v1';
export const STAFF_OPERATIONS=Object.freeze(['create','edit','reset','disable','enable','remove'].map(action=>'burimunsi.staff.'+action));
export const cancelledStaffOperation=operation=>{
  requireThat(STAFF_OPERATIONS.includes(operation),'invalid_staff_operation',400);
  return operation.replace('burimunsi.staff.','burimunsi.staff.cancelled.');
};
export const originalStaffOperation=operation=>STAFF_OPERATIONS.find(value=>cancelledStaffOperation(value)===operation)??null;
const allowedOperations=new Set([
  'burimunsi.allocate','burimunsi.enroll','burimunsi.membership','burimunsi.members_import',
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
    const cancelled=originalStaffOperation(receipt?.operation);
    requireThat(receipt&&receipt.groupId===groupId&&receipt.actorId===current.actorId&&
      receipt.requestId===requestId&&receipt.sessionId===origin.sessionId&&
      (allowedOperations.has(receipt.operation)||(cancelled!==null&&receipt.cancellationMarkerValid===true))&&
      Number.isSafeInteger(receipt.createdAt)&&receipt.createdAt>=origin.createdAt&&receipt.createdAt<=now,
      'invalid_recovery_receipt',503);
    state=cancelled?'cancelled':'committed';
    if(cancelled)return {protocol:OPERATION_RECOVERY_PROTOCOL,requestId,state,originDigest,
      groupId,actorId:current.actorId,installationId:current.installationId,operation:cancelled};
  }
  // Absence is not proof of no effect. No invented rejection or command payload.
  return {protocol:OPERATION_RECOVERY_PROTOCOL,requestId,state,originDigest,
    groupId,actorId:current.actorId,installationId:current.installationId};
}
