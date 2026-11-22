import {requireThat} from './errors.js';
import {normalizePhone} from './values.js';
import {roleAllowsCapability} from './operator-access.mjs';
export {CAPABILITIES} from './operator-access.mjs';
/** actor must be loaded from the trusted native-session store, never req.body. */
export function authorize(actor, groupId, capability, {now=Date.now(), binding=null}={}) {
  requireThat(actor && actor.active === true && actor.revoked !== true && actor.expiresAt > now, 'session_unavailable',401);
  requireThat(actor.groupId === groupId && roleAllowsCapability(actor.role, capability), 'access_denied',403);
  requireThat(Array.isArray(actor.capabilities) && actor.capabilities.includes(capability),'access_denied',403);
  if (['sms.read','gateway.manage'].includes(capability)) {
    requireThat(actor.installationProfile === 'internal_receiver' && binding && binding.active === true && binding.groupId === groupId && binding.installationId === actor.installationId,'gateway_unavailable',403);
  }
  return actor;
}
export function authorizeEntity(actor, entity, capability, options) {
  requireThat(entity && typeof entity.groupId === 'string','record_unavailable',404);
  authorize(actor,entity.groupId,capability,options); return entity;
}
/** Gateway capture authority is deliberately independent from an operator session. */
export function admitGateway(binding, request, now=Date.now()) {
  requireThat(binding && binding.active && binding.expiresAt > now,'gateway_unavailable',401);
  requireThat(request && binding.id === request.bindingId && binding.version === request.bindingVersion &&
    binding.installationId === request.installationId && binding.receivingAccountId === request.receivingAccountId,
    'gateway_unavailable',403);
  requireThat(Number.isInteger(binding.subscriptionId) && binding.subscriptionId >= 0 && request.subscriptionId === binding.subscriptionId,'receiving_route_unresolved',409);
  return Object.freeze({groupId:binding.groupId,receivingAccountId:binding.receivingAccountId,bindingId:binding.id,bindingVersion:binding.version});
}
/** Only server-loaded, approved identity records enter this function. */
export function matchExistingMember(receipt, members, identities, policy) {
  if (typeof policy?.approvedVersion !== 'string' || !policy.approvedVersion || !policy.groupId || policy.fullIdentityEnabled !== true)
    return {kind:'unallocated',reason:'policy_unavailable'};
  if (!receipt || receipt.groupId !== policy.groupId) return {kind:'unallocated',reason:'scope_mismatch'};
  if (!Array.isArray(members) || !Array.isArray(identities)) return {kind:'unallocated',reason:'identity_data_unavailable'};
  if (!receipt.fullPayerPhone) return {kind:'unallocated',reason:'masked_identity'};
  const at=Date.parse(receipt.at); if (!Number.isFinite(at)) return {kind:'unallocated',reason:'invalid_time'};
  let phone;try{phone=normalizePhone(receipt.fullPayerPhone);}catch{return {kind:'unallocated',reason:'invalid_identity'};}
  // Establish ownership at the receipt's time BEFORE testing present membership.
  // Deactivating one of two overlapping owners must not resolve their ambiguity.
  const matching=identities.filter(i=>i && i.groupId===policy.groupId && i.status==='verified' &&
    i.authority==='collect_verified' && i.purpose==='own_contributions' && i.phone===phone &&
    typeof i.id==='string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(i.id) &&
    typeof i.memberId==='string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(i.memberId) &&
    Number.isFinite(Date.parse(i.validFrom)) && Date.parse(i.validFrom)<=at &&
    (i.validUntil===null || (Number.isFinite(Date.parse(i.validUntil)) && at<Date.parse(i.validUntil))));
  const owners=[...new Set(matching.map(i=>i.memberId))];
  if(owners.length!==1)return {kind:'unallocated',reason:owners.length?'ambiguous_identity':'no_verified_identity'};
  const membership=members.filter(m=>m && m.id===owners[0] && m.groupId===policy.groupId);
  if(membership.length!==1 || membership[0].active!==true || membership[0].eligible!==true)
    return {kind:'unallocated',reason:'member_ineligible'};
  return Object.freeze({kind:'matched',memberId:owners[0],identityIds:[...new Set(matching.map(i=>i.id))].sort(),policyVersion:policy.approvedVersion});
}
