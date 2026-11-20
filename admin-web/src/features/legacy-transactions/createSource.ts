/* eslint-disable no-control-regex -- Reject control characters in source search. */
import {parseSmsDetail, parseSmsPage, type SmsReceipt} from '../operations/contracts';
import type {CreateContext, CreateIntent, CreateTargets} from './create';
import {sha256Text} from '../core/pendingAttempt';

export interface CreateSource {
  receiptId:string; factId:string; sourceSha256:string; bodySha256:string; payloadSha256:string; parserVersion:string;
  payeeId:string; network:'mtn_momo'|'airtel_money'; reference:string; amount:number; payerName:string|null;
  payerLast3:string|null; payeeNumber:string|null; payeeCode:string|null; parsedAt:number; receivedAt:number;
}
function fail():never {throw new Error('The preserved receiver source could not be verified.');}
function access(context:CreateContext){
  if(!context.isCurrent()||context.financialModel!=='transaction_journals'||context.identity.role==='staff'||
      !context.permissions.includes('sms.read')||!context.identity.permissions.includes('sms.read')||!Number.isFinite(Date.parse(context.identity.expiresAt))||Date.parse(context.identity.expiresAt)<=Date.now())fail();
}
function source(row:SmsReceipt):CreateSource {
  if(row.source_kind!=='receiver'||row.evidence_level!=='receiver_ingress_unverified'||row.extraction_status!=='parsed'||row.direction!=='incoming'||row.is_payment!==1||
      !row.source_fact_id||!row.source_body_sha256||!row.source_payload_sha256||!row.parser_version||!row.payee_id||!row.network||!row.momo_transaction_reference||!row.amount_rwf||
      !row.parsed_at||!row.received_at||row.conflicting_reference_count!==0||row.transaction_id!==null||row.source_sha256!==row.source_payload_sha256)fail();
  return {receiptId:row.id,factId:row.source_fact_id,sourceSha256:row.source_sha256,bodySha256:row.source_body_sha256,payloadSha256:row.source_payload_sha256,
    parserVersion:row.parser_version,payeeId:row.payee_id,network:row.network,reference:row.momo_transaction_reference,amount:row.amount_rwf,payerName:row.payer_name,
    payerLast3:row.payer_last3,payeeNumber:row.payee_momo_number,payeeCode:row.payee_momo_code,parsedAt:row.parsed_at,receivedAt:row.received_at};
}
/** One bounded server page; callers should search further when the result is truncated. */
export async function searchCreateSources(context:CreateContext,search:string,payeeId:string){
  access(context);if(search.length>200||/[\x00-\x1f\x7f]/.test(search)||!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(payeeId))fail();
  const query=new URLSearchParams({source_kind:'receiver',extraction_status:'parsed',search:search.trim(),limit:'100',offset:'0'});
  const page=parseSmsPage(await context.request(`sms/receipts?${query}`),0,100);access(context);
  if(page.rows.some(row=>row.source_kind!=='receiver'||row.extraction_status!=='parsed'))fail();
  const choices=page.rows.flatMap(row=>{try{const item=source(row);return item.payeeId===payeeId?[item]:[];}catch{return [];}});
  if(new Set(choices.map(item=>item.factId)).size!==choices.length)fail();
  return {choices,truncated:page.total>page.rows.length};
}
export async function loadCreateSource(context:CreateContext,receiptId:string){
  access(context);if(!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(receiptId))fail();
  const canExtract=context.permissions.includes('sms.extract')&&context.identity.permissions.includes('sms.extract');
  const value=parseSmsDetail(await context.request(`sms/receipts/receiver/${receiptId}`),'receiver',receiptId,context.identity.id,canExtract);access(context);return source(value.resource);
}
function localPhone(value:string){return value.startsWith('+250')?`0${value.slice(4)}`:value.startsWith('250')?`0${value.slice(3)}`:value;}
export function validateCreateSource(value:CreateSource,body:CreateIntent,targets:CreateTargets){
  if(value.factId!==body.source_fact_id||value.payeeId!==targets.payee.id||value.network!==targets.payee.network||value.reference!==body.provider_reference||value.amount!==body.amount_rwf)fail();
  const route=targets.payee.route,isPhone=/^(?:07[2389][0-9]{7}|2507[2389][0-9]{7})$/.test(route);
  if(isPhone&&value.payeeNumber&&localPhone(value.payeeNumber)!==localPhone(route)||!isPhone&&value.payeeCode&&value.payeeCode!==route)fail();
}
export async function createSourceHash(value:CreateSource){return sha256Text(JSON.stringify(value));}
