import {encrypt,decrypt} from '../encryption.js';
import {digest} from '../core.js';
import {requirePort,requireThat,BuriError} from './errors.js';
import {authorize} from './policy.js';
import {hasPhonePinContext} from './phone-pin-request.js';
import {assertSmartImportPreview,isSmartImportDocument,XLSX_MIME} from './smart-onboarding-source.js';
import {requireId,requireRequestId,sha256} from './values.js';
import {defs} from './wire/burimunsi.generated.mjs';

const OPERATION='burimunsi.smart_import.v1',SHA=/^[a-f0-9]{64}$/;
const DISCLOSURE=defs['onboardingPreview.request'].properties.ocrDisclosureVersion.const;
const LIMIT=2*1024*1024;
const keys=['v','state','reservationId','sourceSha256','mimeType','policySha256','decoderBuildSha256','ciphertext','previewSha256'];
const boundKeys=[...keys,'importFlowId','ocrDisclosureVersion'];
const own=(value,names)=>value&&typeof value==='object'&&!Array.isArray(value)&&
 Object.keys(value).length===names.length&&names.every(key=>Object.hasOwn(value,key));
function baseShape(value,groupId){
 requireThat(value&&value.groupId===groupId,'access_denied',403);requireId(value.groupId);
 requireRequestId(value.actorId);requireThat(SHA.test(value.sourceSha256??'')&&isSmartImportDocument(value.mimeType)&&
  SHA.test(value.policySha256??'')&&SHA.test(value.decoderBuildSha256??''),'smart_import_journal_invalid',503);
 if(value.mimeType!==XLSX_MIME){
  requireRequestId(value.importFlowId);
  requireThat(value.ocrDisclosureVersion===DISCLOSURE,'smart_import_disclosure_required',403);
 }
}
function identity(row,groupId){
 const x=row?.response,bound=x?.v===2;
 requireThat(row?.collection_id===groupId&&row.operation===OPERATION&&
  SHA.test(row.fingerprint??'')&&(bound?own(x,boundKeys):own(x,keys)&&x.v===1)&&['reserved','decode','extract','completed'].includes(x.state)&&
  SHA.test(x.sourceSha256??'')&&isSmartImportDocument(x.mimeType)&&SHA.test(x.policySha256??'')&&SHA.test(x.decoderBuildSha256??''),
  'smart_import_journal_invalid',503);
 requireRequestId(row.actor_id);requireRequestId(row.request_id);requireRequestId(row.session_id);requireRequestId(x.reservationId);
 if(bound){
  requireRequestId(x.importFlowId);
  requireThat(x.mimeType!==XLSX_MIME&&x.ocrDisclosureVersion===DISCLOSURE,'smart_import_journal_invalid',503);
 }
 if(x.state==='completed')requireThat(typeof x.ciphertext==='string'&&x.ciphertext.length>0&&x.ciphertext.length<=3000000&&
  SHA.test(x.previewSha256??''),'smart_import_journal_invalid',503);
 else requireThat(x.ciphertext===null&&x.previewSha256===null,'smart_import_journal_invalid',503);
 return Object.freeze({groupId,actorId:row.actor_id,requestId:row.request_id,reservationId:x.reservationId,
  sourceSha256:x.sourceSha256,mimeType:x.mimeType,policySha256:x.policySha256,
  decoderBuildSha256:x.decoderBuildSha256,state:x.state,
  ...(bound?{importFlowId:x.importFlowId,ocrDisclosureVersion:x.ocrDisclosureVersion,sessionId:row.session_id}:{})});
}
function matches(actual,expected){return ['groupId','actorId','requestId','reservationId','sourceSha256','mimeType',
 'policySha256','decoderBuildSha256','importFlowId','ocrDisclosureVersion','sessionId'].every(k=>actual[k]===expected[k]);}
function aad(value){
 const binding=value.importFlowId?[value.importFlowId,value.ocrDisclosureVersion,value.sessionId]:[];
 return ['burimunsi-smart-import-v1',value.groupId,value.actorId,value.requestId,value.reservationId,
  value.sourceSha256,value.mimeType,value.policySha256,value.decoderBuildSha256,...binding].join('\n');
}
function fingerprint(v){return sha256([OPERATION,v.groupId,v.actorId,v.sourceSha256].join('\n'));}

/** Durable journal over the existing fenced, scoped private command-receipt
 * class. Raw source bytes are never retained. Both new reservations and every
 * state transition revalidate the live native actor inside the same transaction.
 * Unconfirmed phases are never reset, deleted, or implicitly redispatched.
 */
export class PostgresSmartOnboardingJournal{
 constructor({authority,env,clock=()=>Date.now()}={}){
  requirePort(authority,['write','session','audit']);requireId(authority.groupId);
  requireThat(env&&typeof env==='object'&&typeof clock==='function','collect_adapter_required',503);
  Object.assign(this,{authority,env,clock,groupId:authority.groupId});
 }
 async actor(sql,sessionId,actorId){
  requireRequestId(sessionId);requireRequestId(actorId);
  const now=this.clock();requireThat(Number.isSafeInteger(now)&&now>=0,'invalid_session_clock',503);
  const actor=await this.authority.session(sql,{id:sessionId,now});
  authorize(actor,this.groupId,'members.enroll',{now});
  requireThat(actor.id===actorId&&actor.sessionId===sessionId,'session_unavailable',401);
  if(hasPhonePinContext(this.authority.db)){
   // This DB guard locks and revalidates the real PIN session, delegated staff
   // approval and shared principal until this short transaction commits.
   const rows=await sql.unsafe("SELECT private.burimunsi_pin_assert_actor('users.manage',$1,NULL,1,NULL) AS principal",[this.groupId]);
   requireThat(rows.length===1&&rows[0].principal===actor.principalUserId,'session_unavailable',401);
  }
  return actor;
 }
 async get(sql,receipt,sessionId){
  const rows=await sql.unsafe(`SELECT collection_id,actor_id,request_id,session_id,operation,fingerprint,response
   FROM private.burimunsi_command_receipts WHERE collection_id=$1 AND actor_id=$2::uuid AND request_id=$3::uuid
    AND operation=$4 FOR UPDATE`,[this.groupId,receipt.actorId,receipt.requestId,OPERATION]);
  requireThat(rows.length===1,'smart_import_pending',503);
  const found=identity(rows[0],this.groupId);
  requireThat(matches(found,receipt)&&rows[0].session_id===sessionId&&rows[0].fingerprint===await fingerprint(found),'smart_import_pending',503);
  return {row:rows[0],found};
 }
 async reserve(input){
  baseShape(input,this.groupId);requireRequestId(input.sessionId);
  const requestId=requireRequestId(input.proposedRequestId),reservationId=requireRequestId(input.proposedReservationId);
  const external=input.mimeType!==XLSX_MIME;
  const fp=await fingerprint(input),response={v:external?2:1,state:'reserved',reservationId,sourceSha256:input.sourceSha256,
   mimeType:input.mimeType,policySha256:input.policySha256,decoderBuildSha256:input.decoderBuildSha256,
   ciphertext:null,previewSha256:null,...(external?{importFlowId:input.importFlowId,ocrDisclosureVersion:input.ocrDisclosureVersion}:{})};
  const result=await this.authority.write(async sql=>{
   await this.actor(sql,input.sessionId,input.actorId);
   const inserted=await sql.unsafe(`INSERT INTO private.burimunsi_command_receipts
    (collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at)
    VALUES($1,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7::jsonb,$8) ON CONFLICT DO NOTHING RETURNING request_id`,
    [this.groupId,input.actorId,requestId,input.sessionId,OPERATION,fp,response,this.clock()]);
   const rows=await sql.unsafe(`SELECT collection_id,actor_id,request_id,session_id,operation,fingerprint,response
    FROM private.burimunsi_command_receipts WHERE collection_id=$1 AND actor_id=$2::uuid AND operation=$3 AND fingerprint=$4
    FOR UPDATE`,[this.groupId,input.actorId,OPERATION,fp]);
   requireThat(rows.length===1,'smart_import_pending',503);const found=identity(rows[0],this.groupId);
   requireThat(found.actorId===input.actorId&&found.sourceSha256===input.sourceSha256&&rows[0].fingerprint===fp,
    'smart_import_pending',503);
   if(inserted.length===1){requireThat(found.requestId===requestId&&found.reservationId===reservationId&&found.state==='reserved',
    'smart_import_pending',503);await this.authority.audit(sql,input.actorId,'burimunsi.smart_import.reserved',requestId,requestId);}
   else requireThat(inserted.length===0,'smart_import_pending',503);
   return {found,inserted:inserted.length===1,ciphertext:rows[0].response.ciphertext,previewSha256:rows[0].response.previewSha256};
  });
  if(result.inserted)return result.found;
  if(result.found.state!=='completed')return {...result.found,state:'pending'};
  requireThat(['mimeType','policySha256','decoderBuildSha256','ocrDisclosureVersion'].every(key=>result.found[key]===input[key]),
   'smart_import_disclosure_changed',409);
  let bytes;try{
   bytes=await decrypt(this.env,result.ciphertext,aad(result.found));
   requireThat(bytes.length<=LIMIT&&await digest(bytes)===result.previewSha256,'smart_import_recovery_invalid',503);
   let preview;try{preview=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}
   catch{throw new BuriError('smart_import_recovery_invalid',503);}
   assertSmartImportPreview(preview,result.found.mimeType);return {...result.found,preview};
  }finally{bytes?.fill(0);}
 }
 async advance({receipt,sessionId,phase}){
  baseShape(receipt,this.groupId);requireRequestId(sessionId);requireRequestId(receipt.requestId);requireRequestId(receipt.reservationId);
  requireThat(['decode','extract'].includes(phase),'smart_import_journal_invalid',503);
  return await this.authority.write(async sql=>{
   await this.actor(sql,sessionId,receipt.actorId);
   const {row,found}=await this.get(sql,receipt,sessionId),expected=phase==='decode'?'reserved':'decode';
   requireThat(found.state===expected,'smart_import_pending',503);
   const next={...row.response,state:phase};
   const rows=await sql.unsafe(`UPDATE private.burimunsi_command_receipts SET response=$5::jsonb
    WHERE collection_id=$1 AND actor_id=$2::uuid AND request_id=$3::uuid AND operation=$4 AND response->>'state'=$6
    RETURNING collection_id,actor_id,request_id,session_id,operation,fingerprint,response`,
    [this.groupId,receipt.actorId,receipt.requestId,OPERATION,next,expected]);
   requireThat(rows.length===1,'smart_import_pending',503);const done=identity(rows[0],this.groupId);
   requireThat(matches(done,receipt)&&done.state===phase,'smart_import_pending',503);return done;
  });
 }
 async complete({receipt,sessionId,phase,preview}){
  baseShape(receipt,this.groupId);requireRequestId(sessionId);requireRequestId(receipt.requestId);requireRequestId(receipt.reservationId);
  requireThat(phase==='decode'&&receipt.mimeType===XLSX_MIME||phase==='extract'&&receipt.mimeType!==XLSX_MIME,
   'smart_import_journal_invalid',503);
  assertSmartImportPreview(preview,receipt.mimeType);
  const bytes=new TextEncoder().encode(JSON.stringify(preview));let ciphertext,previewSha256;
  try{requireThat(bytes.length<=LIMIT,'smart_import_journal_invalid',503);
   previewSha256=await digest(bytes);ciphertext=await encrypt(this.env,bytes,aad(receipt));
  }finally{bytes.fill(0);}
  requireThat(typeof ciphertext==='string'&&ciphertext.length<=3000000,'smart_import_journal_invalid',503);
  return this.authority.write(async sql=>{
   await this.actor(sql,sessionId,receipt.actorId);
   const {row,found}=await this.get(sql,receipt,sessionId);requireThat(found.state===phase,'smart_import_pending',503);
   const next={...row.response,state:'completed',ciphertext,previewSha256};
   const rows=await sql.unsafe(`UPDATE private.burimunsi_command_receipts SET response=$5::jsonb
    WHERE collection_id=$1 AND actor_id=$2::uuid AND request_id=$3::uuid AND operation=$4 AND response->>'state'=$6
    RETURNING collection_id,actor_id,request_id,session_id,operation,fingerprint,response`,
    [this.groupId,receipt.actorId,receipt.requestId,OPERATION,next,phase]);
   requireThat(rows.length===1,'smart_import_pending',503);const done=identity(rows[0],this.groupId);
   requireThat(matches(done,receipt)&&done.state==='completed','smart_import_pending',503);
   await this.authority.audit(sql,receipt.actorId,'burimunsi.smart_import.completed',receipt.requestId,receipt.requestId);
   return done;
  });
 }
}
