// Source-only qualification of a possible native receipt. This is NOT a
// posting capability: the observation, scope and account must be loaded by a
// server authority, and sender authenticity / complete-source proof remain
// unresolved. A caller must never expose it as financial confirmation.
import {parseUnresolvedEvidence} from './unresolved-evidence.js';
import {sha256} from './values.js';

const HASH=/^[a-f0-9]{64}$/;
const UUID=/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const ID=/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const plain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&
 (Object.getPrototypeOf(v)===Object.prototype||Object.getPrototypeOf(v)===null)&&
 Object.getOwnPropertySymbols(v).length===0&&Object.values(Object.getOwnPropertyDescriptors(v)).every(d=>Object.hasOwn(d,'value'));
const safeInt=v=>Number.isSafeInteger(v)&&v>0;
const blocked=reason=>({status:'source_unresolved',reason,promotionAllowed:false,financialEffects:0});

// This matches the canonical receiving-account normalization used when the
// account's receiver_hash is created; it does not consult the device or SIM.
function route(value){
 if(typeof value!=='string')return null;
 if(/^07[2389][0-9]{7}$/.test(value))return '+250'+value.slice(1);
 if(/^2507[2389][0-9]{7}$/.test(value))return '+'+value;
 if(/^\+2507[2389][0-9]{7}$/.test(value))return value;
 return /^[0-9]{4,9}$/.test(value)?value:null;
}

/** Derives a tentative identity for future canonical deduplication.
 * None of the returned data proves the carrier, a complete PDU, a payment,
 * a valid current authorization, or uniqueness in the database. */
export async function nativePromotionEvidence({observation,source,scope,account}={}){
 try{
  if(![observation,source,scope,account].every(plain)||!UUID.test(observation.sourceId??'')||
   !ID.test(observation.collectionId??'')||!UUID.test(observation.nativeAccountId??'')||
   !UUID.test(observation.nativeSessionId??'')||!UUID.test(observation.installationId??'')||
   !UUID.test(observation.grantId??'')||!safeInt(observation.grantVersion)||
   !HASH.test(observation.bodySha256??'')||!HASH.test(observation.objectSha256??'')||
   !HASH.test(observation.profileTupleSha256??''))return blocked('invalid_source_identity');
  if(scope.collectionId!==observation.collectionId||scope.collectionStatus!=='active'||scope.enabled!==true||
   !safeInt(scope.version)||!ID.test(scope.receivingAccountId??'')||account.id!==scope.receivingAccountId||
   account.status!=='active'||account.profile_status!=='approved'||
   !['mtn_momo','airtel_money'].includes(account.provider)||account.currency!=='RWF')return blocked('account_scope_unavailable');
  if(source.provenance!=='native_observation_unverified'||source.source_mode!=='live'||source.complete!==true||
   typeof source.raw_sender!=='string'||typeof source.raw_body!=='string'||
   await sha256(source.raw_body)!==observation.bodySha256)return blocked('source_incomplete_or_changed');
  const tuple={provider:account.provider,status:account.status,profile_status:account.profile_status,
   profile_version:account.profile_version,profile_json:account.profile_json,currency:account.currency,timezone:account.timezone};
  const parsed=parseUnresolvedEvidence({source:{raw_sender:source.raw_sender,raw_body:source.raw_body,completeness:'complete'},providerProfile:tuple});
  if(parsed.facts_state!=='supported'||!parsed.facts||parsed.recipient?.state!=='candidate')return blocked('recipient_or_parse_unresolved');
  const recipient=parsed.recipient,accountRoute=route(account.public_code),recipientRoute=route(recipient.raw);
  if(!['public_code','phone_number'].includes(recipient.kind)||!accountRoute||!recipientRoute||
   recipientRoute!==accountRoute||!HASH.test(account.receiver_hash??'')||
   await sha256(accountRoute)!==account.receiver_hash||
   source.raw_body.slice(recipient.identifier.start,recipient.identifier.end)!==recipient.raw)
   return blocked('recipient_scope_mismatch');
  if(!safeInt(parsed.facts.principal?.amount_minor)||parsed.facts.principal.currency!=='RWF'||
   typeof parsed.facts.transaction_id?.raw!=='string'||!parsed.facts.transaction_id.raw.length)
   return blocked('receipt_facts_unavailable');
  return {status:'recipient_match_candidate',promotionAllowed:false,financialEffects:0,
   source:{kind:'native_observation',sourceId:observation.sourceId,collectionId:observation.collectionId,
    nativeAccountId:observation.nativeAccountId,nativeSessionId:observation.nativeSessionId,
    installationId:observation.installationId,grantId:observation.grantId,grantVersion:observation.grantVersion,
    bodySha256:observation.bodySha256,objectSha256:observation.objectSha256,profileTupleSha256:observation.profileTupleSha256},
   scopeVersion:scope.version,providerProfileVersion:account.profile_version,
   providerProfileSha256:await sha256(account.profile_json),recipientEvidence:{kind:recipient.kind,
    identifier:recipient.identifier,role:recipient.role},amountMinor:parsed.facts.principal.amount_minor,currency:'RWF',
   canonicalUnique:{provider:account.provider,receivingAccountId:account.id,eventKind:'incoming_receipt',
    providerTransactionId:parsed.facts.transaction_id.raw},
   sourceAssurance:'unverified',completeness:'client_claim',requires:['verified_complete_source','verified_sender_authenticity','canonical_native_lineage']};
 }catch{return blocked('source_unavailable');}
}
