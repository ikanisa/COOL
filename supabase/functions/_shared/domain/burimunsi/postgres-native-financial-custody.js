// Native custody is a source-evidence port, not a ledger writer. This module is
// deliberately not composed into a live worker. The independent confirmation
// port must be implemented by a reviewed server-side provider-evidence adapter;
// a client assertion, sender label or model result cannot implement it.
import {applicationWorkTuple} from '../../application-fence.js';
import {digest} from '../core.js';
import {BuriError,requirePort,requireThat} from './errors.js';
import {canonicalJson,requireId,requireRequestId,sha256} from './values.js';
import {parseWire} from './wire/runtime.mjs';
import {PostgresNativeAuthority} from './postgres-authority.js';
import {PostgresPostingCustody} from './postgres-posting-custody.js';
import {PostgresStorageWitnesses} from './postgres-storage-witnesses.js';
import {observationContentFingerprint} from './postgres-observations.js';
import {prepareNativeAutoExtraction,validateNativeAutoExtraction} from './native-auto-parser.js';
import {matchesPartialInboxFinancialQuotes,parseNativeRecipientQuote,parsePartialInboxEvidence,parseUnresolvedEvidence} from './unresolved-evidence.js';

const hash=/^[a-f0-9]{64}$/;
const enc=new TextEncoder(),dec=new TextDecoder('utf-8',{fatal:true});
const check=(v,code='native_financial_custody_unavailable')=>requireThat(v,code,503);
const copy=v=>JSON.parse(canonicalJson(v));
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const field=(v,k)=>{const d=Object.getOwnPropertyDescriptor(v??{},k);check(d&&Object.hasOwn(d,'value'));return d.value;};
const target=r=>({ownerId:r.principalUserId,purpose:'sms_receipt',entityId:r.id,
 plaintextSha256:r.object_sha256,aad:`sms:${r.id}:${r.object_sha256}`});
function route(value){
 if(typeof value!=='string')return null;
 if(/^07[2389][0-9]{7}$/.test(value))return '+250'+value.slice(1);
 if(/^2507[2389][0-9]{7}$/.test(value))return '+'+value;
 if(/^\+2507[2389][0-9]{7}$/.test(value))return value;
 return /^[0-9]{4,9}$/.test(value)?value:null;
}
function routeKind(value){
 if(typeof value!=='string')return null;
 return /^07[2389][0-9]{7}$|^2507[2389][0-9]{7}$|^\+2507[2389][0-9]{7}$/.test(value)?'phone_number':
  /^[0-9]{4,9}$/.test(value)?'public_code':null;
}
function command(work){
 const jobId=requireRequestId(field(work,'jobId')),leaseToken=requireRequestId(field(work,'leaseToken'));
 const leaseVersion=field(work,'leaseVersion');check(Number.isSafeInteger(leaseVersion)&&leaseVersion>0);
 return Object.freeze({jobId,leaseToken,leaseVersion});
}
function accountTuple(account){return {provider:account.provider,status:account.status,profile_status:account.profile_status,
 profile_version:account.profile_version,profile_json:account.profile_json,currency:account.currency,timezone:account.timezone};}
function snapshotValid(value,cmd,groupId,tuple){
 const w=value?.work,c=value?.capture,r=value?.receipt,t=r?.transaction,a=r?.account,p=c?.proof;
 check(w?.contractVersion===1&&w.kind==='native_receipt'&&w.groupId===groupId&&w.jobId===cmd.jobId&&
  w.leaseToken===cmd.leaseToken&&w.leaseVersion===cmd.leaseVersion&&w.admissionId===tuple[0]&&
  w.admissionEpoch===tuple[1]&&w.sourceCodeSha256===tuple[2]);
 requireRequestId(w.sourceId);requireId(w.transactionId);requireId(w.ownerUserId);requireId(w.workerGrantId);requireId(w.owner);
 check(Number.isSafeInteger(w.workerGrantVersion)&&w.workerGrantVersion>0&&Number.isSafeInteger(w.leaseExpiresAt)&&w.leaseExpiresAt>0);
 check(hash.test(w.sourceKey??'')&&hash.test(w.sourceKeyContentSha256??'')&&hash.test(w.sourceKeyBodySha256??'')&&
  hash.test(w.bodySha256??'')&&hash.test(w.objectSha256??'')&&hash.test(w.sourceFingerprint??'')&&
  w.sourceKeyBodySha256===w.bodySha256&&Number.isSafeInteger(w.objectSizeBytes)&&w.objectSizeBytes>0&&w.objectSizeBytes<=131072&&
  c?.kind==='jobs'&&c.actor?.collectionId===groupId&&p?.id===w.sourceId&&p.sourceId===w.sourceId&&
  p.object_key==='sms/'+w.sourceId&&p.principalUserId===w.ownerUserId&&p.object_sha256===w.objectSha256&&
  p.bodySha256===w.bodySha256&&p.fingerprint===w.sourceFingerprint&&Number(p.size_bytes)===w.objectSizeBytes&&
  r?.sourceId===w.sourceId&&r.groupId===groupId&&r.ownerUserId===w.ownerUserId&&r.evidenceLevel==='client_received'&&
  r.bodySha256===w.bodySha256&&r.objectSha256===w.objectSha256&&r.sourceFingerprint===w.sourceFingerprint&&
  Number(r.objectSizeBytes)===w.objectSizeBytes&&t?.id===w.transactionId&&t.sourceId===w.sourceId&&t.groupId===groupId&&
  t.mode===w.transactionMode&&['live','historical'].includes(t.mode)&&t.eventKind==='incoming_receipt'&&
  t.paymentOutcome==='successful'&&t.currency==='RWF'&&Number.isSafeInteger(t.amountMinor)&&t.amountMinor>0&&
  typeof t.providerTransactionId==='string'&&/^[^\s]{1,160}$/u.test(t.providerTransactionId)&&
  t.allocationState==='unallocated'&&(t.hasConflict===0||t.hasConflict===false)&&a?.id===t.receivingAccountId&&
  a.provider===t.provider&&a.status==='active'&&a.profile_status==='approved'&&a.profile_version!=='unverified'&&
  a.currency===t.currency&&hash.test(a.receiver_hash??'')&&t.parseOutput&&typeof t.parseOutput==='object');
 return value;
}
function confirmationValid(v,w,t,a){
 check(v&&v.kind==='independent_provider_receipt_v1'&&v.state==='settled'&&typeof v.id==='string'&&v.id.length>0&&v.id.length<=128&&
  Number.isSafeInteger(v.version)&&v.version>0&&hash.test(v.evidenceSha256??'')&&v.groupId===w.groupId&&
  v.sourceId===w.sourceId&&v.sourceKey===w.sourceKey&&v.bodySha256===w.bodySha256&&v.transactionId===w.transactionId&&
  v.receivingAccountId===a.id&&v.receiverHash===a.receiver_hash&&v.provider===a.provider&&
  v.providerTransactionId===t.providerTransactionId&&v.eventKind===t.eventKind&&v.amountMinor===t.amountMinor&&v.currency===t.currency);
}
function counterpartyTokenMatches(body,identifier,evidence){
 if(identifier===null)return true;
 if(typeof identifier!=='string'||!identifier.length||identifier.length>160||identifier.trim()!==identifier||
  /[*•…#\u0000-\u001f\u007f]/u.test(identifier)||typeof evidence!=='string'||!evidence.includes(identifier))return false;
 const start=body.indexOf(identifier),end=start+identifier.length;
 if(start<0||body.indexOf(identifier,start+1)!==-1)return false;
 const before=Array.from(body.slice(0,start)).at(-1)??'',after=String.fromCodePoint(body.codePointAt(end)??0);
 const token=c=>Boolean(c)&&/[\p{L}\p{N}\p{M}_+\-/*•…#]/u.test(c);
 if(token(before)||token(after))return false;
 // A numeric identifier may itself contain spaces. Do not accept one end of
 // a longer space-separated or masked number as the whole counterparty token.
 if(/^\+?[0-9][0-9 -]*$/u.test(identifier)&&
  (/[0-9*•…#][ \t]+$/u.test(body.slice(0,start))||/^[ \t]+[0-9*•…#]/u.test(body.slice(end))))return false;
 // Dots inside a longer identifier or decimal are not sentence punctuation.
 if(after==='.'&&token(String.fromCodePoint(body.codePointAt(end+1)??0)))return false;
 if(before==='.'&&token(Array.from(body.slice(0,start-1)).at(-1)??''))return false;
 return true;
}
async function verifyPayload(source,receipt,work){
 const t=receipt.transaction,a=receipt.account,account=accountTuple(a);
 check(source&&source.provenance==='native_observation_unverified'&&
  ((source.source_mode==='live'&&source.complete===true&&t.mode==='live')||
   (source.source_mode==='catch_up'&&source.complete===false&&t.mode==='historical'))&&
  typeof source.raw_sender==='string'&&typeof source.raw_body==='string'&&enc.encode(source.raw_body).length<=3000&&
  await sha256(source.raw_body)===work.bodySha256);
 const content=await observationContentFingerprint({rawSender:source.raw_sender,serviceCentreAt:source.service_centre_at,
  inboxReceivedAt:source.inbox_received_at,subscriptionId:source.subscription_id},work.bodySha256);
 check(content===work.sourceKeyContentSha256);
 const parsed=validateNativeAutoExtraction(source,account,t.parseOutput);
 check(parsed.kind==='parsed'&&parsed.facts.source_mode===source.source_mode&&parsed.facts.event_kind===t.eventKind&&
  parsed.facts.payment_outcome===t.paymentOutcome&&parsed.facts.provider_transaction_id===t.providerTransactionId&&
  parsed.facts.amount_minor===t.amountMinor&&parsed.facts.currency===t.currency&&
  parsed.facts.counterparty_identifier===t.payerIdentifier&&
  counterpartyTokenMatches(source.raw_body,t.payerIdentifier,t.parseOutput.evidence?.payer));
 if(source.source_mode==='catch_up'){
  // Partial evidence is used only to rule out ambiguous visible labels. An
  // independent provider receipt establishes settlement/recipient; it does
  // not rewrite or claim the capture itself was complete or carrier-signed.
  let partialSource=source,partial=parsePartialInboxEvidence({source:partialSource,providerProfile:account});
  if(partial.state==='unavailable'&&partial.recipient?.reason==='unsupported_message'){
   const planned=prepareNativeAutoExtraction(source,account);check(planned.kind==='provider');
   partialSource={...source,raw_body:planned.body};
   partial=parsePartialInboxEvidence({source:partialSource,providerProfile:account});
  }
  check(partial.state==='partial'&&matchesPartialInboxFinancialQuotes({source:partialSource,providerProfile:account,
   reference:t.providerTransactionId,amountMinor:t.amountMinor,currency:t.currency}));
 }else{
  const full=parseUnresolvedEvidence({source:{raw_sender:source.raw_sender,raw_body:source.raw_body,completeness:'complete'},
   providerProfile:account,modelOutput:t.parseOutput});
  check(full.facts_state==='supported'&&full.facts.principal.amount_minor===t.amountMinor&&
   full.facts.transaction_id.raw===t.providerTransactionId);
 }
 const canonical=route(a.public_code);check(canonical&&await sha256(canonical)===a.receiver_hash);
 const quote=parseNativeRecipientQuote({source,providerProfile:account});
 if(quote.state==='quoted')check(quote.recipient.kind===routeKind(a.public_code)&&route(quote.recipient.raw)===canonical&&
  source.raw_body.slice(quote.recipient.identifier.start,quote.recipient.identifier.end)===quote.recipient.raw);
 else check(['recipient_grammar_missing','recipient_evidence_missing'].includes(quote.reason));
 return {sourceMode:source.source_mode,sourceComplete:source.complete,recipientEvidence:quote.state==='quoted'?'provider_and_quote':'provider',
  providerProfileSha256:await sha256(a.profile_json),receiverHash:a.receiver_hash};
}

/** A proof is privately held by this instance and tied to the active jobs fence,
 * the original native lease, current approved account, object journal and an
 * independently verified provider record. It is never sufficient on its own
 * to pick a beneficiary, bypass final policy, or create a ledger entry. */
export class PostgresNativeFinancialCustody {
 #proofs=new WeakMap();
 constructor({authority,custody,witnesses,confirmation}){
  check(authority instanceof PostgresNativeAuthority&&custody instanceof PostgresPostingCustody&&
   witnesses instanceof PostgresStorageWitnesses&&custody.qualificationOnly===false&&custody.storageWitnesses===witnesses&&
   authority.db===custody.db&&authority.db===witnesses.db&&authority.groupId===custody.groupId&&
   authority.groupId===witnesses.groupId&&authority.work?.kind==='jobs');
  requirePort(confirmation,['locked']);
  this.authority=authority;this.custody=custody;this.witnesses=witnesses;this.confirmation=confirmation;
  this.groupId=authority.groupId;this.work=authority.work;
 }
 async owned(){
  check(this.authority.work===this.work&&this.authority.db.applicationWork===this.work&&this.custody.db===this.authority.db&&
   this.custody.storageWitnesses===this.witnesses&&this.witnesses.db===this.authority.db);
  await this.authority.assertOwned();
  check(this.authority.work===this.work&&this.authority.db.applicationWork===this.work);
 }
 async snapshot(sql,cmd){
  requirePort(sql,['unsafe']);await this.owned();const tuple=applicationWorkTuple(this.work);
  const rows=await sql.unsafe('SELECT private.burimunsi_native_custody_snapshot($1::uuid,$2::uuid,$3::bigint) AS result',
   [cmd.jobId,cmd.leaseToken,cmd.leaseVersion]);
  check(Array.isArray(rows)&&rows.length===1);const value=copy(snapshotValid(rows[0].result,cmd,this.groupId,tuple));
  // The provider-evidence adapter receives only its scoped lookup identity;
  // the parsed receipt and any SMS contents remain inside the custody boundary.
  const {groupId,sourceId,sourceKey,bodySha256,transactionId,jobId,leaseVersion,admissionId}=value.work;
  const provider=await this.confirmation.locked(sql,Object.freeze({groupId,sourceId,sourceKey,bodySha256,
   transactionId,jobId,leaseVersion,admissionId}));
  if(provider===null)return null;
  const verified=copy(provider);confirmationValid(verified,value.work,value.receipt.transaction,value.receipt.account);
  const r=value.capture.proof,expect=target(r),ns=await sql.unsafe('SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE');
  check(Array.isArray(ns)&&ns.length===1&&same(ns[0],this.custody.namespace));
  const journal=await this.custody.journal(sql,r.object_key,expect),keyId=journal?.reservation?.key_id;
  const descriptor={scope:{ownerId:expect.ownerId,purpose:expect.purpose,entityId:expect.entityId},aad:expect.aad,keyId,
   plaintextSha256:r.object_sha256,requestDigest:r.fingerprint,httpMetadata:{contentType:'application/octet-stream'},
   customMetadata:{sha256:r.object_sha256,key_id:keyId}};
  check(typeof keyId==='string'&&keyId.length>0&&await sha256(canonicalJson(descriptor))===journal.reservation.source_fingerprint);
  await this.owned();return {value,provider:verified,journal};
 }
 async prepare(work){
  const cmd=command(work);let binding,plaintext,retained=false;
  try{
   const initial=await this.authority.write(async sql=>{
    const value=await this.snapshot(sql,cmd);if(value===null)return null;
    binding={kind:'native_financial_custody',groupId:this.groupId,work:value.value.work,source:value.value.capture.proof,
     providerEvidenceId:value.provider.id,providerEvidenceVersion:value.provider.version};
    const plan=await this.witnesses.stage(binding,[{key:value.value.capture.proof.object_key,journal:value.journal}]);
    return {...value,plan};
   });
   if(initial===null)return {state:'unavailable'};
   await this.witnesses.prefetch(initial.plan);const r=initial.value.capture.proof;
   plaintext=await this.custody.decrypt(await this.witnesses.sealed(binding,r.object_key,initial.journal),target(r).aad);
   check(plaintext instanceof Uint8Array&&plaintext.length===Number(r.size_bytes)&&await digest(plaintext)===r.object_sha256);
   const source=parseWire(dec.decode(plaintext),131072),evidence=await verifyPayload(source,initial.value.receipt,initial.value.work);
   await this.authority.write(async sql=>{
    const current=await this.snapshot(sql,cmd);check(current&&same(current.value,initial.value)&&same(current.provider,initial.provider)&&
     this.custody.sameJournal(current.journal,initial.journal));
    await this.witnesses.sealed(binding,r.object_key,current.journal);await this.owned();
   });
   const proof=Object.freeze(Object.create(null));this.#proofs.set(proof,{cmd,binding,initial,evidence});retained=true;
   return {state:'ready',proof};
  }catch(error){
   if(error instanceof BuriError)throw error;
   if(['40001','23505'].includes(error?.code))throw new BuriError('native_financial_custody_changed',409);
   if(error?.code==='42501')throw new BuriError('access_denied',403);
   throw new BuriError('native_financial_custody_unavailable',503);
  }finally{plaintext?.fill(0);if(binding&&!retained)this.witnesses.forget(binding);}
 }
 async assertInTransaction(sql,proof){
  const saved=this.#proofs.get(proof);check(saved);await this.owned();
  const current=await this.snapshot(sql,saved.cmd);check(current&&same(current.value,saved.initial.value)&&
   same(current.provider,saved.initial.provider)&&this.custody.sameJournal(current.journal,saved.initial.journal));
  await this.witnesses.sealed(saved.binding,current.value.capture.proof.object_key,current.journal);await this.owned();
  return Object.freeze({...saved.evidence});
 }
 release(proof){const saved=this.#proofs.get(proof);if(!saved)return;this.#proofs.delete(proof);this.witnesses.forget(saved.binding);}
}
