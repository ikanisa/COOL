/** Invented fixture data; SQL-recorder tests. Actual pinned Collect AES-GCM code
 * is executed with only its ApiError import replaced by a test error class.
 * No storage provider, real principal, PostgreSQL or production key is involved.
 */
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {PostgresPostingCustody} from '../../domain/burimunsi/postgres-posting-custody.js';
import {canonicalJson,sha256} from '../../domain/burimunsi/values.js';
const url=new URL('../../../../../upstream/collect/supabase/functions/_shared/domain/encryption.js',import.meta.url);
const original=readFileSync(url,'utf8');
export const encryptionBlob=createHash('sha1').update('blob '+Buffer.byteLength(original)+'\0').update(original).digest('hex');
const code=original.replace("import {ApiError} from './core.js';","class ApiError extends Error { constructor(status,code,message){super(message);this.status=status;this.code=code;} }");
export const encryption=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
const enc=new TextEncoder();
export const namespace={origin:'https://example.test',bucket:'collect-evidence'};
export async function custodyFixture({body='You have received 12,500 RWF from EXAMPLE PAYER. FT Id: FT100',payloadChange=null}={}){
 const env={DATA_KEY_ID:'test-only-key',DATA_ENCRYPTION_KEY:Buffer.alloc(32,19).toString('base64')};
 const bodySha=await sha256(body),size=enc.encode(body).length;
 const payload={raw_sender:'M-Money',normalized_sender:'M-Money',raw_body:body,received_at_device:'2026-11-07T08:00:00.000Z',
   receiver_momo_number:'0780000001',service_centre_at:'2026-11-07T08:00:00.000Z',captured_at:'2026-11-07T08:00:01.000Z',
   inbox_received_at:null,source_mode:'live',gateway_binding_id:'binding-1',gateway_binding_version:2,subscription_id:7,completeness:'complete'};
 payloadChange?.(payload);
 const raw=JSON.stringify(payload),rawSha=await sha256(raw),identity=await sha256(canonicalJson(payload));
 const command={groupId:'group-1',receiptId:'transaction-1',memberId:'member-1',requestId:'11111111-1111-4111-8111-111111111111',mode:'automatic',policyVersion:'policy-v1',
   receipt:{id:'transaction-1',groupId:'group-1',receivingAccountId:'wallet-1',sourceBindingId:'binding-1',sourceBindingVersion:2,amountRwf:12500,providerTransactionId:'FT100'}};
 const descriptor={command,paymentId:'payment-1',evidenceId:'evidence-1',transactionId:'transaction-1',receivingAccountId:'wallet-1',sourceBindingId:'binding-1',sourceBindingVersion:2,
   objectKey:'evidence/evidence-1',objectSha256:bodySha,sizeBytes:size};
 const row={collection_id:'group-1',receiving_account_id:'wallet-1',source_binding_id:'binding-1',source_binding_version:2,policy_version:'policy-v1',
   transaction_id:'transaction-1',canonical_attempt:'parse-1',event_kind:'incoming_receipt',mode:'live',has_conflict:0,allocation_state:'linked',provider_transaction_id:'FT100',amount_minor:12500,currency:'RWF',provider:'mtn_momo',
   payment_id:'payment-1',evidence_id:'evidence-1',payment_group:'group-1',payment_amount:12500,beneficiary_member_id:'member-1',
   evidence_owner:'principal-1',evidence_group:'group-1',evidence_key:'evidence/evidence-1',evidence_sha256:bodySha,evidence_size:size,evidence_currency:'RWF',evidence_amount:12500,external_reference:'wallet-1:FT100',receiver_network:'mtn_momo',receiver_momo_number:'+250780000001',
   raw_sms_id:'raw-1',parse_attempt_id:'parse-1',relation:'accepted',raw_owner:'gateway-owner-1',raw_key:'sms/raw-1',raw_sha256:rawSha,raw_size:enc.encode(raw).length,body_sha256:bodySha,receiver_hash:'1'.repeat(64),
   source_body_sha256:bodySha,parse_outcome:'accepted',parse_profile:'profile-v1',parse_profile_json:'{"synthetic":true}',wallet_profile_json:'{"synthetic":true}',credential_id:'credential-1',identity_sha256:identity,completeness:'complete',source_mode:'live',subscription_id:7,
   job_binding:'binding-1',job_binding_version:2,job_account:'wallet-1',job_mode:'live',job_state:'completed',job_error:null,binding_owner:'gateway-owner-1',binding_account:'wallet-1',binding_version:2,binding_status:'active',subscription_evidence:'{"subscription_id":7}',
   credential_binding:'binding-1',credential_revoked:null,wallet_provider:'mtn_momo',public_code:'0780000001',wallet_hash:'1'.repeat(64),wallet_status:'active',profile_status:'approved',profile_version:'profile-v1',source_conflict:false};
 const journals=new Map();
 for(const [key,ownerId,purpose,entityId,text,plain,aad]of [
   ['sms/raw-1','gateway-owner-1','sms_receipt','raw-1',raw,rawSha,`sms:raw-1:${rawSha}`],
   ['evidence/evidence-1','principal-1','payment_evidence','evidence-1',body,bodySha,`evidence:evidence-1:${bodySha}`]]){
   const sealed=await encryption.encrypt(env,enc.encode(text),aad),scope={ownerId,purpose,entityId},cipherHash=await sha256(sealed),sourceFingerprint=await sha256(key+'source');
   const common={object_key:key,operation_id:await sha256(key),fingerprint:await sha256(key+'intent'),sha256:cipherHash,size:enc.encode(sealed).length,scope,
     http_metadata:{contentType:'application/octet-stream'},custom_metadata:{sha256:plain,key_id:env.DATA_KEY_ID,source_fingerprint:sourceFingerprint}};
   journals.set(key,{put:{...structuredClone(common),state:'committed',active_attempt:null,upload_unresolved:false,delete_tombstone:false},metadata:structuredClone(common),
     reservation:{object_key:key,source_fingerprint:sourceFingerprint,scope:structuredClone(scope),aad,key_id:env.DATA_KEY_ID,plaintext_sha256:plain,sealed_body:sealed}});
 }
 const state={row,journals,namespace:{...namespace},queries:[],decrypts:0,deletions:[],barriers:[],missing:null,duplicate:false,onQuery:null,onDecrypt:null,onAssert:null};
 const work={assert:async()=>{await state.onAssert?.();}},db={applicationWork:work};
 const sql={unsafe:async(text,values=[])=>{
   state.queries.push({text,values});await state.onQuery?.(text,values);
   if(text.startsWith('SELECT pg_advisory'))return [{}];
   if(text.includes('FROM private.storage_namespace'))return state.missing==='namespace'?[]:[structuredClone(state.namespace)];
   if(text.includes('FROM private.burimunsi_transaction_scopes'))return state.missing==='lineage'?[]:state.duplicate?[structuredClone(row),structuredClone(row)]:[structuredClone(row)];
   if(text.includes('privacy_retention_barriers'))return state.barriers.includes(values[0])?[{subject_id:values[0]}]:[];
   if(text.includes('storage_delete_intents'))return state.deletions.includes(values[0])?[{operation_id:'delete'}]:[];
   const name=text.includes('storage_put_intents')?'put':text.includes('storage_objects')?'metadata':'reservation';
   if(state.missing===name)return [];
   return [structuredClone(journals.get(values[0])[name])];
 }};
 const decrypt=async(document,aad)=>{state.decrypts++;await state.onDecrypt?.(document,aad);return encryption.decrypt(env,document,aad);};
 const verifier=new PostgresPostingCustody({qualificationOnly:true,db,groupId:'group-1',namespace,decrypt});
 return {state,env,db,sql,descriptor,verifier,work,run:()=>verifier.assertInTransaction(sql,descriptor)};
}
