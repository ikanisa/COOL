import {ApiError} from './core.js';

// Join the immutable FIRST accepted attempt, never a later duplicate/conflict.
// LEFT JOIN keeps broken provenance visible to the mapper instead of silently
// hiding a transaction or changing the independently counted page size.
const fields={
 rf_attempt_id:'rf_attempt.id',rf_attempt_source:'rf_attempt.raw_sms_id',
 rf_attempt_outcome:'rf_attempt.outcome',rf_attempt_digest:'rf_attempt.source_body_sha256',
 rf_parser_version:'rf_attempt.parser_version',rf_profile_version:'rf_attempt.profile_version',
 rf_parsed_at:'rf_attempt.created_at',rf_capture_id:'rf_capture.id',rf_capture_digest:'rf_capture.body_sha256',
 rf_link_transaction:'rf_source.transaction_id',rf_link_source:'rf_source.raw_sms_id',
 rf_link_attempt:'rf_source.parse_attempt_id',rf_relation:'rf_source.relation',
};
export const receiptFactColumns=Object.entries(fields).map(([name,sql])=>`${sql} AS ${name}`).join(',');
export const receiptFactJoins=`
 LEFT JOIN momo_parse_attempts rf_attempt ON rf_attempt.id=t.parse_attempt_id
 LEFT JOIN sms_receipts rf_capture ON rf_capture.id=rf_attempt.raw_sms_id
 LEFT JOIN momo_transaction_sources rf_source ON rf_source.transaction_id=t.id
  AND rf_source.raw_sms_id=rf_attempt.raw_sms_id AND rf_source.parse_attempt_id=t.parse_attempt_id`;

const fail=()=>{throw new ApiError(503,'invalid_source_data','Retained receipt facts could not be verified.');};
const id=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
const text=(value,max=512)=>typeof value==='string'&&value.length>0&&value.length<=max;
const nullableText=(value,max=512)=>value===null||text(value,max);
const exact=(value,minimum=0)=>Number.isSafeInteger(value)&&value>=minimum;
const instant=value=>typeof value==='string'&&/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)&&Number.isFinite(Date.parse(value))&&new Date(value).toISOString()===value;
const digest=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const number=value=>typeof value==='string'&&/^(?:\+?2507[2389]\d{7}|07[2389]\d{7})$/.test(value);
const code=value=>typeof value==='string'&&/^\d{4,9}$/.test(value);

/** Read-only, versioned facts. No original text, inferred identity or finality. */
export function withReceiptFacts(row){
 if(!id(row.id)||!id(row.receiving_account_id)||!id(row.parse_attempt_id)||
  row.rf_attempt_id!==row.parse_attempt_id||!id(row.rf_capture_id)||
  row.rf_attempt_source!==row.rf_capture_id||row.rf_link_source!==row.rf_capture_id||
  row.rf_link_attempt!==row.parse_attempt_id||row.rf_link_transaction!==row.id||
  row.rf_relation!=='accepted'||row.rf_attempt_outcome!=='accepted'||
  !digest(row.rf_capture_digest)||row.rf_attempt_digest!==row.rf_capture_digest||
  !text(row.rf_parser_version,200)||!text(row.rf_profile_version,200)||row.rf_profile_version==='unverified'||!instant(row.rf_parsed_at)||
  !['mtn_momo','airtel_money'].includes(row.provider)||row.event_kind!=='incoming_receipt'||
  !text(row.provider_transaction_id,160)||/\s/.test(row.provider_transaction_id)||
  !exact(row.amount_minor,1)||row.currency!=='RWF'||row.currency_scale!==0||
  !nullableText(row.payer_name)||!nullableText(row.payer_identifier)||
  row.payer_identifier!==null&&!/^(?:\+?[0-9][0-9 -]{5,24}|\*{2,}[0-9]{3,10})$/.test(row.payer_identifier)||
  row.payer_last3!==(row.payer_identifier&&/[0-9]{3}$/.test(row.payer_identifier)?row.payer_identifier.slice(-3):null)||
  ![row.fee_minor,row.wallet_balance_after_minor].every(value=>value===null||exact(value))||
  !nullableText(row.transaction_datetime_raw)||!text(row.transaction_timezone,200)||
  !text(row.recipient_name,160)||!number(row.public_code)&&!code(row.public_code))fail();
 try{new Intl.DateTimeFormat('en',{timeZone:row.transaction_timezone}).format(0);}catch{fail();}
 if(row.transaction_datetime_raw===null){
  if(row.transaction_at!==null||row.transaction_time_source!=='missing_provider_time')fail();
 }else if(!instant(row.transaction_at)||!['sms_body_and_provider_profile','sms_body_explicit_offset_and_provider_profile'].includes(row.transaction_time_source))fail();
 const receipt_facts={contract_version:1,kind:'validated_momo_extraction',transaction_id:row.id,
  capture_id:row.rf_capture_id,parse_attempt_id:row.parse_attempt_id,source_body_sha256:row.rf_capture_digest,
  parser_version:row.rf_parser_version,profile_version:row.rf_profile_version,parsed_at:row.rf_parsed_at,
  provider:row.provider,provider_transaction_id:row.provider_transaction_id,
  payer_name:row.payer_name,payer_identifier_raw:row.payer_identifier,payer_last3:row.payer_last3,
  amount_minor:row.amount_minor,currency:row.currency,currency_scale:row.currency_scale,
  fee_minor:row.fee_minor,wallet_balance_after_minor:row.wallet_balance_after_minor,
  transaction_datetime_raw:row.transaction_datetime_raw,transaction_at:row.transaction_at,
  normalization_timezone:row.transaction_timezone,transaction_time_source:row.transaction_time_source,
  public_reference:null,provider_confirmation:false,settlement_status:'not_asserted'};
 const receiving_context={account_id:row.receiving_account_id,identifier_raw:row.public_code,
  identifier_kind:number(row.public_code)?'number':'code',recipient_name:row.recipient_name,basis:'recorded_receiving_account'};
 const publicRow=Object.fromEntries(Object.entries(row).filter(([key])=>!Object.hasOwn(fields,key)));
 return {...publicRow,receipt_facts,receiving_context,provider_confirmation:false,settlement_status:'not_asserted'};
}
