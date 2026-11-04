import {ApiError} from './core.js';

// Only the BFF resolver installs this attestation after a current SQL lookup.
// Neither an AAL value nor a caller-supplied actor timestamp is email evidence.
const attestations=new WeakMap();
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const epoch=()=>Math.floor(Date.now()/1000);
const fields=['id','principal_id','auth_user_id','auth_session_id','token_hash','public_id','origin','auth_version'];
const denied=()=>new ApiError(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');
const unavailable=()=>new ApiError(503,'admin_email_verification_unavailable','Your email verification could not be confirmed.');
function binding(account){
 if(!account||!fields.every(key=>Object.hasOwn(account,key))||
  !['id','principal_id','auth_user_id','auth_session_id','public_id'].every(key=>uuid.test(account[key]??''))||
  !/^[a-f0-9]{64}$/.test(account.token_hash??'')||!Number.isSafeInteger(account.auth_version)||account.auth_version<1||
  typeof account.origin!=='string'||!account.origin)throw unavailable();
 return Object.fromEntries(fields.map(key=>[key,account[key]]));
}
export function attestAdminEmailAccount(account,status){
 const captured=binding(account);
 if(status?.contract_version!==1||status.public_session_id!==account.public_id||
  !(status.email_verified_at===null&&status.proof_id===null||
   Number.isSafeInteger(status.email_verified_at)&&status.email_verified_at>0&&status.email_verified_at<=epoch()&&uuid.test(status.proof_id??'')))throw unavailable();
 attestations.set(account,{account,binding:captured,at:status.email_verified_at,proofId:status.proof_id});return account;
}
function current(subject){
 const proof=subject&&attestations.get(subject);if(!proof)return null;
 if(!fields.every(key=>proof.account[key]===proof.binding[key]))return null;
 if(subject!==proof.account&&(subject.surface!=='admin'||subject.userId!==proof.binding.principal_id||subject.sessionId!==proof.binding.auth_session_id))return null;
 return proof;
}
export function bindAdminEmailActor(actor,account){
 const proof=current(account);
 if(!proof||actor?.surface!=='admin'||actor.userId!==account.principal_id||actor.sessionId!==account.auth_session_id)throw denied();
 attestations.set(actor,proof);return actor;
}
export function adminEmailVerifiedAt(subject){return current(subject)?.at??null;}
export function adminEmailProofId(subject){return current(subject)?.proofId??null;}
export function hasFreshAdminEmail(subject,maxAge=300){
 const proof=current(subject),at=proof?.at,now=epoch();
 return Number.isSafeInteger(maxAge)&&maxAge>0&&maxAge<=300&&Number.isSafeInteger(at)&&at>0&&at<=now&&now-at<=maxAge;
}
export function requireFreshAdminEmail(subject,maxAge=300){if(!hasFreshAdminEmail(subject,maxAge))throw denied();return current(subject);}
export function adminEmailState(account){
 if(!current(account))throw unavailable();const at=adminEmailVerifiedAt(account);
 return {contractVersion:1,sessionId:account.public_id,emailVerifiedAt:at===null?null:new Date(at*1000).toISOString()};
}
export function adminEmailArguments(account){binding(account);return [account.id,account.token_hash,account.origin,account.public_id];}
// The minimum remains the requested sensitive-operation policy. The SQL Admin
// branch checks independent email proof; actual AAL and MFA evidence stay real.
export function requestedAdminEmail(actor,minimumAssurance){
 if(actor?.surface!=='admin'||minimumAssurance!==2)return false;
 requireFreshAdminEmail(actor);return true;
}
