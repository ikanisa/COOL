// Synthetic, in-memory descriptor calculation only. This does not connect to
// PostgreSQL or Storage, verify an identity decision, or authorize a write.
import {createHash} from 'node:crypto';
import {canonical, validKey} from '../../../../supabase/functions/_shared/storage/protocol.js';

export const SCOPE_REBIND_FORMAT='collect.synthetic-storage-owner-rebind.v1';
const HASH=/^[a-f0-9]{64}$/;
const fail=code=>{const error=Error(code);error.code=code;throw error;};
const digest=value=>createHash('sha256').update(value).digest('hex');
const exact=(value,keys)=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&
 Object.getPrototypeOf(value)===Object.prototype&&Object.keys(value).sort().join('\0')===[...keys].sort().join('\0');
const same=(a,b)=>canonical(a)===canonical(b);
const text=(value,max=200)=>typeof value==='string'&&value.length>0&&Buffer.byteLength(value)<=max&&
 Buffer.from(value,'utf8').toString('utf8')===value&&!/[\u0000-\u001f\u007f]/.test(value);
const freeze=value=>{if(value&&typeof value==='object'){for(const child of Object.values(value))freeze(child);Object.freeze(value);}return value;};

// The caller supplies canonical JSON and its independently pinned SHA-256.
// Canonical round-trip rejects duplicate keys and avoids caller-owned getters,
// proxies and later mutation of an approved object. All inputs and the return
// value contain private descriptor data and must stay in trusted memory.
export function calculateSyntheticScopeRebind(serialized,expectedPlanSha256){
 if(typeof serialized!=='string'||Buffer.byteLength(serialized)>32768||!HASH.test(expectedPlanSha256??'')||
  digest(serialized)!==expectedPlanSha256)fail('scope_rebind_plan_refused');
 let plan;try{plan=JSON.parse(serialized);}catch{fail('scope_rebind_plan_refused');}
 if(canonical(plan)!==serialized||!exact(plan,['format','mode','mapping','reservation','intent','object'])||
  plan.format!==SCOPE_REBIND_FORMAT)fail('scope_rebind_plan_refused');
 if(plan.mode!=='synthetic')fail('scope_rebind_managed_unqualified');
 const {mapping,reservation:r,intent:i,object:o}=plan;
 if(!exact(mapping,['sourceOwner','targetOwner','decisionSha256'])||
  !text(mapping.sourceOwner,128)||!text(mapping.targetOwner,128)||mapping.sourceOwner===mapping.targetOwner||
  !HASH.test(mapping.decisionSha256??'')||
  !exact(r,['scope','aad','keyId','plaintextSha256','requestDigest','httpMetadata','customMetadata','sourceFingerprint'])||
  !exact(i,['key','operationId','size','sha256','scope','httpMetadata','customMetadata','fingerprint','state'])||
  !exact(o,['key','operationId','size','sha256','scope','httpMetadata','customMetadata','fingerprint'])||
  !exact(r.scope,['ownerId','entityId','purpose'])||r.scope.ownerId!==mapping.sourceOwner||
  !text(r.scope.entityId)||!['sms_receipt','payment_evidence'].includes(r.scope.purpose)||
  !text(r.keyId,128)||!HASH.test(r.plaintextSha256??'')||!HASH.test(r.requestDigest??'')||
  !HASH.test(r.sourceFingerprint??'')||!HASH.test(i.sha256??'')||!HASH.test(i.fingerprint??'')||
  !Number.isSafeInteger(i.size)||i.size<1||i.size>8_000_000||
  !/^[A-Za-z0-9:._-]{8,200}$/.test(i.operationId??'')||i.state!=='committed')
  fail('scope_rebind_preimage_refused');
 const prefix=r.scope.purpose==='sms_receipt'?'sms':'evidence';
 try{validKey(i.key);}catch{fail('scope_rebind_preimage_refused');}
 if(i.key!==prefix+'/'+r.scope.entityId||r.aad!==prefix+':'+r.scope.entityId+':'+r.plaintextSha256||
  !exact(r.httpMetadata,['contentType'])||r.httpMetadata.contentType!=='application/octet-stream'||
  !exact(r.customMetadata,['sha256','key_id'])||r.customMetadata.sha256!==r.plaintextSha256||
  r.customMetadata.key_id!==r.keyId||!same(i.scope,r.scope)||!same(i.httpMetadata,r.httpMetadata)||
  !same(i.customMetadata,{...r.customMetadata,source_fingerprint:r.sourceFingerprint}))
  fail('scope_rebind_preimage_refused');
 const sourceDescriptor={scope:r.scope,aad:r.aad,keyId:r.keyId,plaintextSha256:r.plaintextSha256,
  requestDigest:r.requestDigest,httpMetadata:r.httpMetadata,customMetadata:r.customMetadata};
 const intentDescriptor={key:i.key,size:i.size,sha256:i.sha256,scope:i.scope,
  httpMetadata:i.httpMetadata,customMetadata:i.customMetadata};
 if(digest(canonical(sourceDescriptor))!==r.sourceFingerprint||digest(canonical(intentDescriptor))!==i.fingerprint||
  !same(o,{key:i.key,operationId:i.operationId,size:i.size,sha256:i.sha256,scope:i.scope,
   httpMetadata:i.httpMetadata,customMetadata:i.customMetadata,fingerprint:i.fingerprint}))
  fail('scope_rebind_preimage_refused');
 const scope={...r.scope,ownerId:mapping.targetOwner};
 const sourceFingerprint=digest(canonical({...sourceDescriptor,scope}));
 const customMetadata={...r.customMetadata,source_fingerprint:sourceFingerprint};
 const fingerprint=digest(canonical({...intentDescriptor,scope,customMetadata}));
 return freeze({format:SCOPE_REBIND_FORMAT,status:'synthetic_candidate',writeAuthorized:false,
  original:{sourceFingerprint:r.sourceFingerprint,intentFingerprint:i.fingerprint,decisionSha256:mapping.decisionSha256},
  reservation:{...r,scope,sourceFingerprint},
  intent:{...i,scope,customMetadata,fingerprint},
  object:{...o,scope,customMetadata,fingerprint}});
}
