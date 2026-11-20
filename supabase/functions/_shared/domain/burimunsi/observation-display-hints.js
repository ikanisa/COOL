// Optional, display-only quotations from an authorized incomplete inbox SMS.
// The caller must independently revalidate the server-side profile proof and
// source authority at the disclosure/audit boundary. No wallet is selected.
import {parsePartialInboxEvidence} from './unresolved-evidence.js';
import {digest} from '../core.js';
const HASH=/^[a-f0-9]{64}$/;
const KEYS=['provider','status','profile_status','profile_version','profile_json','currency','timezone'];
const kinds=new Set(['quoted_incoming_amount','quoted_reference']);
const plain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
export async function observationDisplayHints(payload,proof,bodySha256){
 if(!plain(payload)||!plain(proof)||!plain(proof.profile)||!HASH.test(bodySha256??'')||
  !HASH.test(proof.profileSha256??'')||Object.keys(proof.profile).length!==KEYS.length||
  KEYS.some(k=>!Object.hasOwn(proof.profile,k))||typeof proof.profile.profile_version!=='string'||
  !proof.profile.profile_version.trim()||proof.profile.profile_version.length>128||
  /[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/u.test(proof.profile.profile_version)||
  typeof proof.profile.profile_json!=='string'||await digest(proof.profile.profile_json)!==proof.profileSha256||
  typeof payload.raw_body!=='string'||await digest(payload.raw_body)!==bodySha256)return null;
 const parsed=parsePartialInboxEvidence({source:payload,providerProfile:proof.profile});
 if(parsed.kind!=='partial_inbox_display_only'||parsed.state!=='partial'||parsed.source_complete!==false||
  !Array.isArray(parsed.hints)||parsed.hints.length<1||parsed.hints.length>2)return null;
 const seen=new Set(),hints=[];
 for(const hint of parsed.hints){
  const {kind,text,evidence}=hint??{};
  if(!kinds.has(kind)||seen.has(kind)||typeof text!=='string'||!text||text.length>3000||!plain(evidence)||
   !Number.isInteger(evidence.start)||!Number.isInteger(evidence.end)||evidence.start<0||
   evidence.start>=evidence.end||evidence.end>payload.raw_body.length||
   payload.raw_body.slice(evidence.start,evidence.end)!==text)return null;
  seen.add(kind);hints.push({kind,text,start:evidence.start,end:evidence.end});
 }
 return {schemaVersion:1,kind:'partial_inbox_display_only',profileVersion:proof.profile.profile_version,
  profileSha256:proof.profileSha256,bodySha256,hints};
}
