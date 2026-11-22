import {evidenceSensitivitySql,evidenceSensitivity} from './evidence_provenance.js';
import {contributionBasis,exact,iso,fail} from './admin_record_values.js';

// SQL and row projection live together so each bounded read validates the
// exact data it selects, including historical references and evidence amounts.
const masked=v=>v?`••••${v.slice(v.length>=8?-4:-2)}`:null;
const maskedEmail=v=>v?`${v.slice(0,1)}•••${v.slice(v.lastIndexOf('@'))}`:null;
const common=(r,title,subtitle,amount,status=r.status)=>({id:r.id,title,subtitle,amount,status,created_at:iso(r.created_at),country_code:'RW',currency_code:'RWF'});

const activeMembershipsForPerson=`FROM memberships m JOIN collections g ON g.id=m.collection_id
 WHERE m.user_id=u.id AND m.active=1 AND g.status='active'`;
const personSql=`SELECT u.id,u.public_id,u.phone,u.email,u.full_name,u.member_type,u.momo_provider,u.momo_number,u.momo_pay_code,
 u.access_status AS status,u.revision,u.created_at,u.updated_at,l.admin_user_id AS operator_admin_id,a.id AS joined_operator_admin_id,a.role AS operator_role,a.status AS operator_status,
 (SELECT count(*) ${activeMembershipsForPerson}) AS active_groups,
 COALESCE((SELECT sum(e.amount_minor) FROM ledger_entries e WHERE e.member_id=u.id),0) AS net_contributed_rwf
 FROM users u LEFT JOIN admin_principal_links l ON l.user_id=u.id LEFT JOIN admin_users a ON a.id=l.admin_user_id`;
const groupSql=`SELECT g.*, (SELECT count(*) FROM memberships m JOIN users u ON u.id=m.user_id WHERE m.collection_id=g.id AND m.active=1 AND u.access_status='active') AS active_members FROM collections g`;
const paymentSql=`SELECT p.*,to_jsonb(p)->>'payment_reference' AS short_payment_reference,g.title AS group_title,e.receiver_display_label,e.receiver_network,e.receiver_momo_number,
 e.authenticity,e.external_reference,e.observed_at,e.object_sha256,e.owner_user_id,e.receiver_momo_number AS evidence_receiver_momo,
 COALESCE((SELECT sum(l.amount_minor) FROM ledger_entries l WHERE l.payment_id=p.id),0) AS net_amount
 FROM payments p JOIN collections g ON g.id=p.collection_id JOIN payment_evidence e ON e.id=p.evidence_id`;
const payeeSql=`SELECT id,id AS group_id,title AS group_title,receiver_display_label AS label,receiver_network AS network,
 receiver_momo_number AS momo_number_or_code,(CASE WHEN status='active' THEN 'active' ELSE 'inactive' END) AS status,revision,created_at,updated_at
 FROM collections WHERE receiver_momo_number IS NOT NULL AND receiver_network IS NOT NULL`;
const ledgerSql=`SELECT l.*,l.kind AS status,g.title AS group_title,p.status AS payment_status FROM ledger_entries l JOIN collections g ON g.id=l.collection_id JOIN payments p ON p.id=l.payment_id`;
const evidenceMetadataSql=`SELECT e.id,e.object_sha256 AS sha256,e.size_bytes,e.content_type,e.authenticity,e.external_reference AS reference,
 e.observed_at,e.created_at,e.retained_until,e.legal_hold,${evidenceSensitivitySql} AS source_sensitivity FROM payment_evidence e JOIN payments p ON p.evidence_id=e.id WHERE p.id=?`;
const evidenceMetadata=r=>({...r,source_sensitivity:evidenceSensitivity(r.source_sensitivity),size_bytes:exact(r.size_bytes),observed_at:iso(r.observed_at),created_at:iso(r.created_at),
 retained_until:r.retained_until?iso(r.retained_until):null,legal_hold:r.legal_hold===1});

function personRow(r){
 const sourceUuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
 if(!sourceUuid(r.id)||typeof r.public_id!=='string'||!/^\d{6}$/.test(r.public_id))fail(503,'invalid_source_data','A person identifier is unavailable.');
 if(!['app','direct','operator'].includes(r.member_type))fail(503,'invalid_source_data','A person type is unavailable.');
 const adminId=r.operator_admin_id??null,joinedId=r.joined_operator_admin_id??null,role=r.operator_role??null,operatorStatus=r.operator_status??null;
 if(adminId!==null){
  if(!sourceUuid(adminId)||joinedId!==adminId||!['owner','admin','staff'].includes(role)||!['invited','active','revoked'].includes(operatorStatus))fail(503,'invalid_source_data','A person operator link is unavailable.');
 }else if(joinedId!==null||role!==null||operatorStatus!==null)fail(503,'invalid_source_data','A person operator link is unavailable.');
 const net=exact(r.net_contributed_rwf),groups=exact(r.active_groups),types=[adminId!==null?(role==='staff'?'Staff':'Admin'):r.member_type==='operator'?'Operator':null,r.member_type==='app'?'App':r.member_type==='direct'?'Direct':null].filter(Boolean);
 return {...common(r,r.public_id,r.full_name||r.email||'',`${groups} groups`,r.status),public_id:r.public_id,display_name:r.full_name||null,
 display_name_recorded:!!r.full_name,person_id:r.id,collect_user_id:r.id,operator_admin_id:r.operator_admin_id??null,
 operator_public_id:r.operator_admin_id?r.public_id:null,operator_role:r.operator_role??null,operator_status:r.operator_status??null,
 user_types:types,member_type:r.member_type,phone_e164:r.phone,email:r.email,whatsapp_number:r.member_type==='app'?r.phone:null,
 momo_provider:r.momo_provider||null,momo_number:r.momo_number||null,momo_pay_code:r.momo_pay_code||null,
 total_contributed_rwf:net,posted_contributed_rwf:null,contribution_basis:contributionBasis,
 name_verification:r.full_name?'recorded_not_provider_verified':'not_recorded',phone_masked:masked(r.phone),email_masked:maskedEmail(r.email),
 active_groups:groups,account_status:r.status,version:exact(r.revision),updated_at:iso(r.updated_at)};
}
function groupRow(r){const data=JSON.parse(r.data_json);return {...common(r,r.title,`${r.collection_type} · ${r.visibility_status}`,`${exact(r.active_members)} members`),
 slug:r.slug,collection_type:r.collection_type,purpose_label:typeof data.purpose_label==='string'?data.purpose_label:null,
 visibility:r.visibility_status,is_platform_sponsored:r.is_platform_sponsored===1,active_members:exact(r.active_members),version:exact(r.revision),updated_at:iso(r.updated_at)};}
const isReceiverPhone = value => /^(?:\+?2507[2389]\d{7}|07[2389]\d{7})$/.test(value??'');

function payeeRow(r){return {...common(r,r.label||'Recorded receiver',r.group_title,r.momo_number_or_code,r.status),group_id:r.group_id,group_name:r.group_title,
 network:r.network,momo_masked:masked(r.momo_number_or_code),momo_number_or_code:r.momo_number_or_code,
 momo_number:isReceiverPhone(r.momo_number_or_code)?r.momo_number_or_code:null,
 momo_pay_code:isReceiverPhone(r.momo_number_or_code)?null:r.momo_number_or_code,
 receiver_basis:'operator_recorded',version:exact(r.revision)};}
function transactionRow(r){
 const amount=exact(r.amount_minor),net=exact(r.net_amount);if(amount<1||net>amount)fail(503,'invalid_source_data','Payment measurements are unavailable.');
 const paymentReference=r.short_payment_reference;
 if(paymentReference!=null&&(typeof paymentReference!=='string'||!/^\d{12}$/.test(paymentReference)))
  fail(503,'invalid_source_data','The payment reference is unavailable.');
 return {...common(r,r.external_reference||r.id,`${r.group_title} · ${r.receiver_display_label||'Recorded receiver'}`,String(amount)),
 ...(paymentReference!=null?{payment_reference:paymentReference}:{}),
 group_id:r.collection_id,group_name:r.group_title,payee_id:r.collection_id,payee_label:r.receiver_display_label??'',network:r.receiver_network??null,rail:'rwanda_momo',
 provider_reference:r.external_reference,public_reference:null,reference_source:'retained_evidence',
 amount_rwf:amount,allocated_amount_rwf:net,allocation_status:net===amount?'allocated':net>0?'partial':'unallocated',observed_at:iso(r.observed_at),
 evidence_id:r.evidence_id,evidence_level:r.authenticity,version:exact(r.revision),member_user_id:r.member_id,
 source_fact_id:null,source_kind:null,parser_version:null,source_link_basis:'not_recorded',source_review_id:null,
 source_extraction_status:null,source_body_sha256:null,source_payload_sha256:null,source_parsed_at:null,
 payer_name:r.payer_display_name||null,payer_phone:null,payer_masked_phone:null,payer_last3:null,payer_last3_known:false,
 payee_momo_number:isReceiverPhone(r.evidence_receiver_momo)?r.evidence_receiver_momo:null,payee_momo_code:r.evidence_receiver_momo&&!isReceiverPhone(r.evidence_receiver_momo)?r.evidence_receiver_momo:null,payee_momo_number_or_code:r.evidence_receiver_momo,
 momo_transaction_reference:null,momo_timestamp_local:null,momo_timezone_offset:null,timezone_known:false,
 source_amount_rwf:null,wallet_balance_rwf:null,source_network:null,direction:null,is_payment:null,
 payer_source_match_status:'not_recorded',payer_insights_status:r.member_id?'available':'not_attributed',
 public_reference_source_fact_id:null,public_reference_random_source:null,payee_last3_known:false,
 provider_confirmation:false,settlement_status:'not_asserted',contribution_basis:contributionBasis};
}
function ledgerRow(r){const amount=exact(r.amount_minor,{signed:true});if(!amount)fail(503,'invalid_source_data','A ledger amount is unavailable.');return {
 ...common({...r,created_at:r.posted_at},r.kind==='contribution'?'Recorded contribution':r.kind==='reversal'?'Contribution reversal':'Contribution correction',r.group_title,String(amount),r.kind),
 kind:r.kind,signed_amount_rwf:amount,amount_rwf:Math.abs(amount),payment_id:r.payment_id,transaction_id:r.payment_id,evidence_id:r.evidence_id,
 member_user_id:r.member_id,group_id:r.collection_id,group_name:r.group_title,reverses_entry_id:r.reverses_entry_id,posted_at:iso(r.posted_at),contribution_basis:contributionBasis,
 provider_confirmation:false,settlement_status:'not_asserted'};}
const peopleSearch=['public_id','full_name','phone','email','momo_number','momo_pay_code'];
const lists={groups:{query:groupSql,row:groupRow,search:['title','slug','description']},users:{query:personSql,row:personRow,search:peopleSearch},
 // Eligibility only needs one active membership. Keep the exact count in projected rows and metric sorts.
 members:{query:`${personSql} WHERE u.member_type!='operator' AND EXISTS(SELECT 1 ${activeMembershipsForPerson})`,row:personRow,search:peopleSearch},
 payees:{query:payeeSql,row:payeeRow,search:['label','group_title','network','momo_number_or_code']},transactions:{query:paymentSql,row:transactionRow,search:['id','external_reference','payer_display_name','group_title','receiver_display_label']},
 ledgers:{query:ledgerSql,row:ledgerRow,search:['id','kind','group_title','payment_id']}};

const membershipSql=`SELECT m.id,m.collection_id AS group_id,m.user_id,m.role,m.active,m.revision,
 m.joined_at,g.title AS group_title,u.public_id,u.full_name AS display_name,u.member_type,
 u.phone AS whatsapp_number,u.momo_provider,u.momo_number,u.momo_pay_code,u.access_status
 FROM memberships m JOIN collections g ON g.id=m.collection_id JOIN users u ON u.id=m.user_id`;
function membershipRow(r){return {id:r.id,group_id:r.group_id,user_id:r.user_id,role:r.role,
 status:r.active===1?'active':'removed',version:exact(r.revision),joined_at:iso(r.joined_at),
 group_title:r.group_title,public_id:r.public_id,display_name:r.display_name||null,member_type:r.member_type,
 whatsapp_number:r.member_type==='app'?r.whatsapp_number:null,momo_provider:r.momo_provider||null,
 momo_number:r.momo_number||null,momo_pay_code:r.momo_pay_code||null,account_status:r.access_status};}

export {lists,membershipSql,membershipRow,payeeSql,payeeRow,ledgerSql,ledgerRow,evidenceMetadataSql,evidenceMetadata};
