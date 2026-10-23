import { parseAdminSmsFacts, SMS_PARSER_VERSION } from '../src/admin-sms.mjs';
import { digest } from '../src/security.mjs';

export const transactionAdditionalFields = [
  'transaction_reference','reference_payer_last3_known','reference_payee_last3_known','reference_source_fact_id','reference_random_source',
  'source_fact_id','source_link_basis','source_review_id','source_kind','parser_version','source_extraction_status','source_body_sha256','source_payload_sha256','source_parsed_at',
  'payer_name','payer_phone','payer_masked_phone','payer_last3','payer_last3_known','payee_momo_number','payee_momo_code','payee_momo_number_or_code',
  'momo_transaction_reference','momo_timestamp_local','momo_timezone_offset','timezone_known','source_amount_rwf','wallet_balance_rwf','source_network','direction','is_payment',
  'payer_source_match_status','payer_insights_status','provider_confirmation','settlement_status',
];

// Local database evidence only. The Admin SMS suite separately verifies durable
// R2 extraction; these fixtures exercise transaction linkage and DTO contracts.
export async function receiverFact(db,{actorId,payeeId,reference,amount=700,payerPhone='***567',payerName='ALICE UMUHOZA',offset='+02:00',suffix='',time=Math.floor(Date.now()/1000)}) {
  const id=crypto.randomUUID(),ingress=crypto.randomUUID(),request=crypto.randomUUID();
  const sender='M-Money',body=`You have received RWF ${amount} from ${payerName} (${payerPhone}). Financial Transaction Id: ${reference}. Your new balance is RWF 50000. at 2026-10-05 12:35:45 ${offset} ${suffix}`;
  const payload=JSON.stringify({raw_sender:sender,raw_body:body}),bodyHash=await digest(body),payloadHash=await digest(payload);
  const q=(sql,...values)=>db.prepare(sql).bind(...values);
  await db.batch([
    q('INSERT INTO collect_receipt_ingress(id,source_key,external_message_id,payee_id,payload_sha256,payload_object_key,received_at) VALUES(?,?,?,?,?,?,?)',ingress,'qa.transaction_facts',crypto.randomUUID(),payeeId,payloadHash,`qa/${ingress}`,time),
    q("INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,'sms.extract',?,?,?)",request,actorId,crypto.randomUUID(),'a'.repeat(64),time),
  ]);
  const facts={id,source_kind:'receiver',member_submission_id:null,receiver_ingress_id:ingress,source_body_sha256:bodyHash,source_payload_sha256:payloadHash,parser_version:SMS_PARSER_VERSION,
    ...parseAdminSmsFacts(sender,body),parsed_by_admin_id:actorId,operation_request_id:request,parsed_at:time};
  await q(`INSERT INTO collect_sms_facts(${Object.keys(facts).join(',')}) VALUES(${Object.keys(facts).map(()=>'?').join(',')})`,...Object.values(facts)).run();
  return {...facts,body,request};
}

export async function memberFact(db,{actorId,userId,reference,amount=700,payerPhone='***567',time=Math.floor(Date.now()/1000)}) {
  const id=crypto.randomUUID(),submission=crypto.randomUUID(),request=crypto.randomUUID(),sender='M-Money';
  const body=`You have received RWF ${amount} from ALICE UMUHOZA (${payerPhone}). Financial Transaction Id: ${reference}. at 2026-10-05 12:35:45 +02:00`;
  const bodyHash=await digest(body),payloadHash=await digest(JSON.stringify({raw_sender:sender,raw_body:body}));
  const q=(sql,...values)=>db.prepare(sql).bind(...values);
  await db.batch([
    q('INSERT INTO member_receipt_submissions(id,user_id,body_hash,raw_sender,payload_object_key,received_at,created_at) VALUES(?,?,?,?,?,?,?)',submission,userId,bodyHash,sender,`qa/${submission}`,time,time),
    q("INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,'sms.extract',?,?,?)",request,actorId,crypto.randomUUID(),'a'.repeat(64),time),
  ]);
  const facts={id,source_kind:'member',member_submission_id:submission,receiver_ingress_id:null,source_body_sha256:bodyHash,source_payload_sha256:payloadHash,parser_version:SMS_PARSER_VERSION,
    ...parseAdminSmsFacts(sender,body),parsed_by_admin_id:actorId,operation_request_id:request,parsed_at:time};
  await q(`INSERT INTO collect_sms_facts(${Object.keys(facts).join(',')}) VALUES(${Object.keys(facts).map(()=>'?').join(',')})`,...Object.values(facts)).run();
  return {...facts,body,request,submission};
}
