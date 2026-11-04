import {ApiError,first,uuid,integer,now} from './core.js';
import {coreStatuses,coreOrdering,coreSearch} from './admin_search.js';
import {evidenceSensitivitySql,evidenceSensitivity} from './evidence_provenance.js';

// These read adapters receive an already authorized D1 binding from the route.
export {marker,permission,lists,list,filters,overview,operatingDetail,relatedPage,ledgerSql,ledgerRow,evidenceMetadataSql,evidenceMetadata,exact,iso,fail,unavailable};

const marker={contract_version:2,model:'canonical_evidence_ledger'};
const contributionBasis='reconciled_evidence_entries',collectedBasis='retained_received_evidence';
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const unavailable=()=>fail(501,'operation_unavailable','This action is unavailable for the current evidence ledger.');
const iso=value=>{if(typeof value!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)||!Number.isFinite(Date.parse(value)))fail(503,'invalid_source_data','A record timestamp is unavailable.');return value;};
const exact=(v,{signed=false}={})=>{if(!Number.isSafeInteger(v)||(!signed&&v<0))fail(503,'invalid_source_data','Workspace measurements are unavailable.');return v;};
const amountString=v=>{if(typeof v!=='string'||!/^(0|[1-9][0-9]*)$/.test(v))fail(503,'invalid_source_data','Workspace measurements are unavailable.');return v;};
const masked=v=>v?`••••${v.slice(v.length>=8?-4:-2)}`:null;
const maskedEmail=v=>v?`${v.slice(0,1)}•••${v.slice(v.lastIndexOf('@'))}`:null;
const permission={groups:'collections',users:'users',members:'users',payees:'receivers',transactions:'payments',ledgers:'ledger'};
const common=(r,title,subtitle,amount,status=r.status)=>({id:r.id,title,subtitle,amount,status,created_at:iso(r.created_at),country_code:'RW',currency_code:'RWF'});

export const adminBridgeMetrics={
 users:'Users',app_users:'App users',direct_users:'Direct users',admin_users:'Admin users',staff_users:'Staff users',
 groups:'Groups',active_members:'Active members',payees:'Payees',active_payees:'Active payees',transactions:'Transactions',
 unallocated_transactions:'Unallocated transactions',ledger_entries:'Ledger entries',reversed_entries:'Reversal entries',payment_evidence:'Retained payment evidence',
 total_recorded_rwf:'Recorded evidence amount',total_reconciled_rwf:'Reconciled evidence amount',
 total_unallocated_rwf:'Unallocated evidence amount',total_net_contributions_rwf:'Net recorded contributions',
};

const personSql=`SELECT u.id,u.public_id,u.phone,u.email,u.full_name,u.member_type,u.momo_provider,u.momo_number,u.momo_pay_code,
 u.access_status AS status,u.revision,u.created_at,u.updated_at,l.admin_user_id AS operator_admin_id,a.id AS joined_operator_admin_id,a.role AS operator_role,a.status AS operator_status,
 (SELECT count(*) FROM memberships m JOIN collections g ON g.id=m.collection_id WHERE m.user_id=u.id AND m.active=1 AND g.status='active') AS active_groups,
 COALESCE((SELECT sum(e.amount_minor) FROM ledger_entries e WHERE e.member_id=u.id),0) AS net_contributed_rwf
 FROM users u LEFT JOIN admin_principal_links l ON l.user_id=u.id LEFT JOIN admin_users a ON a.id=l.admin_user_id`;
const groupSql=`SELECT g.*, (SELECT count(*) FROM memberships m JOIN users u ON u.id=m.user_id WHERE m.collection_id=g.id AND m.active=1 AND u.access_status='active') AS active_members FROM collections g`;
const paymentSql=`SELECT p.*,g.title AS group_title,e.receiver_display_label,e.receiver_network,e.receiver_momo_number,
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
function payeeRow(r){return {...common(r,r.label||'Recorded receiver',r.group_title,r.momo_number_or_code,r.status),group_id:r.group_id,group_name:r.group_title,
 network:r.network,momo_masked:masked(r.momo_number_or_code),momo_number_or_code:r.momo_number_or_code,
 momo_number:/^(?:\+?2507[2389]\d{7}|07[2389]\d{7})$/.test(r.momo_number_or_code)?r.momo_number_or_code:null,
 momo_pay_code:/^(?:\+?2507[2389]\d{7}|07[2389]\d{7})$/.test(r.momo_number_or_code)?null:r.momo_number_or_code,
 receiver_basis:'operator_recorded',version:exact(r.revision)};}
function transactionRow(r){
 const amount=exact(r.amount_minor),net=exact(r.net_amount);if(amount<1||net>amount)fail(503,'invalid_source_data','Payment measurements are unavailable.');
 return {...common(r,r.external_reference||r.id,`${r.group_title} · ${r.receiver_display_label||'Recorded receiver'}`,String(amount)),
 group_id:r.collection_id,group_name:r.group_title,payee_id:r.collection_id,payee_label:r.receiver_display_label??'',network:r.receiver_network??null,rail:'rwanda_momo',
 provider_reference:r.external_reference,public_reference:null,reference_source:'retained_evidence',
 amount_rwf:amount,allocated_amount_rwf:net,allocation_status:net===amount?'allocated':net>0?'partial':'unallocated',observed_at:iso(r.observed_at),
 evidence_id:r.evidence_id,evidence_level:r.authenticity,version:exact(r.revision),member_user_id:r.member_id,
 source_fact_id:null,source_kind:null,parser_version:null,source_link_basis:'not_recorded',source_review_id:null,
 source_extraction_status:null,source_body_sha256:null,source_payload_sha256:null,source_parsed_at:null,
 payer_name:r.payer_display_name||null,payer_phone:null,payer_masked_phone:null,payer_last3:null,payer_last3_known:false,
 payee_momo_number:/^(?:\+?2507[2389]\d{7}|07[2389]\d{7})$/.test(r.evidence_receiver_momo??'')?r.evidence_receiver_momo:null,payee_momo_code:r.evidence_receiver_momo&&!/^(?:\+?2507[2389]\d{7}|07[2389]\d{7})$/.test(r.evidence_receiver_momo)?r.evidence_receiver_momo:null,payee_momo_number_or_code:r.evidence_receiver_momo,
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
const lists={groups:{query:groupSql,row:groupRow,search:['title','slug','description']},users:{query:personSql,row:personRow,search:['public_id','full_name','phone','email','momo_number','momo_pay_code']},
 members:{query:`SELECT * FROM (${personSql}) WHERE active_groups>0 AND member_type!='operator'`,row:personRow,search:['public_id','full_name','phone','email','momo_number','momo_pay_code']},
 payees:{query:payeeSql,row:payeeRow,search:['label','group_title','network','momo_number_or_code']},transactions:{query:paymentSql,row:transactionRow,search:['id','external_reference','payer_display_name','group_title','receiver_display_label']},
 ledgers:{query:ledgerSql,row:ledgerRow,search:['id','kind','group_title','payment_id']}};

function filters(url,allowed=['country','search','status','limit','offset','sort'],type=null){
 for(const key of url.searchParams.keys())if(!allowed.includes(key)||url.searchParams.getAll(key).length!==1)fail(400,'invalid_filter','This filter is not supported.');
 if((url.searchParams.get('country')??'RW')!=='RW')fail(400,'invalid_filter','Only the Rwanda workspace is available.');
 const numeric=(key,fallback,min,max)=>{const raw=url.searchParams.get(key);if(raw===null)return fallback;if(!/^(0|[1-9][0-9]*)$/.test(raw))fail(400,'invalid_filter',`Invalid ${key}.`);return integer(Number(raw),key,min,max);};
 const search=url.searchParams.get('search')??'';if(search.length>200||/[\u0000-\u001f\u007f]/.test(search))fail(400,'invalid_filter','Search must contain at most 200 printable characters.');
 const sort=url.searchParams.get('sort')??'created_at_desc';if(type)coreOrdering(type,sort);else if(!['created_at_asc','created_at_desc'].includes(sort))fail(400,'invalid_filter','This sort is unsupported.');
 return {search:search.trim(),status:url.searchParams.get('status')??'',limit:numeric('limit',25,1,100),offset:numeric('offset',0,0,2147483647),sort};
}
async function list(env,type,url,{id:resourceId=null,activeOnly=false,eligiblePeople=false,groupId=null}={}){
 const spec=lists[type];if(!spec)unavailable();const f=filters(url,undefined,type),args=[],predicates=[];
 if(resourceId){predicates.push('id=?');args.push(uuid(resourceId));}
 if(activeOnly)predicates.push("status='active'");
 if(eligiblePeople)predicates.push("member_type!='operator'");
 if(groupId){
  if(type==='payees'){predicates.push('group_id=?');args.push(uuid(groupId));}
  else if(type==='members'){predicates.push("id IN (SELECT user_id FROM memberships WHERE collection_id=? AND active=1) AND EXISTS(SELECT 1 FROM collections WHERE id=? AND status='active')");args.push(uuid(groupId),groupId);}
  else fail(400,'invalid_filter','This lookup filter is unavailable.');
 }
 if(f.status){if(!coreStatuses[type].includes(f.status))fail(400,'invalid_filter','This status is unavailable for these records.');predicates.push('status=?');args.push(f.status);}
 if(f.search){const search=coreSearch(type,f.search,spec.search);predicates.push(...search.predicates);args.push(...search.args);}
 const where=predicates.length?` WHERE ${predicates.map(p=>`(${p})`).join(' AND ')}`:'',cte=`WITH records AS (${spec.query})`,ordering=coreOrdering(type,f.sort);
 const [count,page]=await env.DB.batch([env.DB.prepare(`${cte} SELECT count(*) AS total FROM records${where}`).bind(...args),
  env.DB.prepare(`${cte} SELECT * FROM records${where} ORDER BY ${ordering} LIMIT ? OFFSET ?`).bind(...args,f.limit,f.offset)]);
 const total=exact(count.results[0].total),result=page.results.map(spec.row);
 if(result.length!==Math.max(0,Math.min(f.limit,total-f.offset)))fail(503,'invalid_source_data','Workspace measurements are unavailable.');
 return {...marker,rows:result,total};
}

// Every related page is counted and read in one guarded D1 batch. A scoped
// lookup must never silently fall back to the global people/receiver directory.
const membershipSql=`SELECT m.id,m.collection_id AS group_id,m.user_id,m.role,m.active,m.revision,
 m.joined_at,g.title AS group_title,u.public_id,u.full_name AS display_name,u.member_type,
 u.phone AS whatsapp_number,u.momo_provider,u.momo_number,u.momo_pay_code,u.access_status
 FROM memberships m JOIN collections g ON g.id=m.collection_id JOIN users u ON u.id=m.user_id`;
function membershipRow(r){return {id:r.id,group_id:r.group_id,user_id:r.user_id,role:r.role,
 status:r.active===1?'active':'removed',version:exact(r.revision),joined_at:iso(r.joined_at),
 group_title:r.group_title,public_id:r.public_id,display_name:r.display_name||null,member_type:r.member_type,
 whatsapp_number:r.member_type==='app'?r.whatsapp_number:null,momo_provider:r.momo_provider||null,
 momo_number:r.momo_number||null,momo_pay_code:r.momo_pay_code||null,account_status:r.access_status};}
async function relatedPage(env,query,args,map,{limit=25,offset=0}={}){
 const [count,result]=await env.DB.batch([env.DB.prepare(`SELECT count(*) AS total FROM (${query})`).bind(...args),
  env.DB.prepare(`SELECT * FROM (${query}) ORDER BY id LIMIT ? OFFSET ?`).bind(...args,limit,offset)]);
 const total=exact(count.results[0].total),values=result.results.map(map);
 if(values.length!==Math.max(0,Math.min(limit,total-offset)))fail(503,'invalid_source_data','Related records are unavailable.');
 return {rows:values,page:{total,limit,offset,next_offset:offset+values.length<total?offset+values.length:null}};
}
function allowedOperations(type,resource,account,receiverLocked=false){
 if(account.role==='staff')return [];
 const allowed=[],add=(name,cap)=>{if(account.permissions.includes(cap))allowed.push(name);};
 if(type==='groups'&&resource.status!=='archived'){
  add('updateGroup','collections.manage');
  if(resource.status==='active'){add('createMembership','users.manage');add('updateMembership','users.manage');if(!receiverLocked)add('updatePayee','receivers.manage');add('createTransaction','payments.manage');}
 }else if(type==='users'&&resource.member_type!=='operator'&&resource.status!=='deleted'){
  add('updateUser','users.manage');if(resource.status==='active')add('createMembership','users.manage');
 }else if(type==='payees'&&resource.status==='active'&&!receiverLocked)add('updatePayee','receivers.manage');
 else if(type==='transactions'&&['reconciled','confirmed'].includes(resource.status)&&resource.allocated_amount_rwf===resource.amount_rwf)add('reverseTransaction','payments.reconcile');
 return allowed;
}
async function operatingDetail(env,account,type,resourceId,url){
 const relation=url.searchParams.get('relation'),f=filters(url,['relation','limit','offset']);
 if(!relation&&(url.searchParams.has('limit')||url.searchParams.has('offset')))fail(400,'invalid_filter','Choose a related record page.');
 const baseUrl=new URL(url.origin),result=await list(env,type,baseUrl,{id:resourceId});
 if(!result.rows.length)fail(404,'not_found','This record was not found.');
 let resource=result.rows[0];const relations={},related={},related_pages={};
 if(type==='groups'){
  const source=await first(env,'SELECT description,creator_user_id FROM collections WHERE id=?',resourceId);
  resource={...resource,description:source.description,owner_user_id:source.creator_user_id};
  if(account.permissions.includes('users.read'))relations.memberships=[`${membershipSql} WHERE m.collection_id=?`,[resourceId],membershipRow];
  if(account.permissions.includes('receivers.read'))relations.payees=[`SELECT * FROM (${payeeSql}) WHERE group_id=?`,[resourceId],payeeRow];
 }else if(type==='users'){
  if(account.permissions.includes('collections.read'))relations.memberships=[`${membershipSql} WHERE m.user_id=?`,[resourceId],membershipRow];
 }else if(type==='payees')resource={...resource,label:resource.title,group_title:resource.group_name};
 else if(type==='transactions'){
  relations.evidence=[evidenceMetadataSql,[resourceId],evidenceMetadata];
  if(account.permissions.includes('ledger.read'))relations.ledger_entries=[`SELECT * FROM (${ledgerSql}) WHERE payment_id=?`,[resourceId],ledgerRow];
 }
 if(relation&&!Object.hasOwn(relations,relation))fail(400,'invalid_filter','This related record page is unavailable.');
 for(const [name,[query,args,map]] of Object.entries(relations)){
  if(relation&&name!==relation)continue;const page=await relatedPage(env,query,args,map,relation?f:{});related[name]=page.rows;related_pages[name]=page.page;
 }
 let receiverLocked=type==='groups'&&(resource.is_platform_sponsored===true||resource.visibility==='public_approved');
 if(type==='payees'){const group=await first(env,'SELECT is_platform_sponsored,visibility_status FROM collections WHERE id=?',resource.group_id);receiverLocked=!group||group.is_platform_sponsored===1||group.visibility_status==='public_approved';}
 const allowed=allowedOperations(type,resource,account,receiverLocked);
 return {...marker,resource_type:type,resource,current_actor_id:account.id,can_manage:allowed.length>0,
  allowed_operations:allowed,related,related_pages,related_truncated:false};
}
async function overview(env,url){
 filters(url,['country']);const [result]=await env.DB.batch([env.DB.prepare(`SELECT
 (SELECT count(*) FROM users) AS users,(SELECT count(*) FROM users WHERE member_type='app') AS app_users,
 (SELECT count(*) FROM users WHERE member_type='direct') AS direct_users,
 (SELECT count(*) FROM admin_users WHERE role IN ('owner','admin') AND status='active') AS admin_users,
 (SELECT count(*) FROM admin_users WHERE role='staff' AND status='active') AS staff_users,
 (SELECT count(*) FROM collections) AS groups,
 (SELECT count(DISTINCT user_id) FROM memberships WHERE active=1) AS active_members,
 (SELECT count(*) FROM collections WHERE receiver_momo_number IS NOT NULL) AS payees,
 (SELECT count(*) FROM collections WHERE receiver_momo_number IS NOT NULL AND status='active') AS active_payees,
 (SELECT count(*) FROM payments) AS transactions,
 (SELECT count(*) FROM payments WHERE status IN ('recorded','ambiguous') AND member_id IS NULL) AS unallocated_transactions,
 (SELECT count(*) FROM ledger_entries) AS ledger_entries,
 (SELECT count(*) FROM ledger_entries WHERE kind='reversal') AS reversed_entries,
 (SELECT count(*) FROM payment_evidence) AS payment_evidence,
 (SELECT CAST(COALESCE(sum(amount_minor),0) AS TEXT) FROM payments) AS total_recorded_rwf,
 (SELECT CAST(COALESCE(sum(amount_minor),0) AS TEXT) FROM payments WHERE status IN ('reconciled','confirmed')) AS total_reconciled_rwf,
 (SELECT CAST(COALESCE(sum(amount_minor),0) AS TEXT) FROM payments WHERE status IN ('recorded','ambiguous') AND member_id IS NULL) AS total_unallocated_rwf,
 (SELECT CAST(COALESCE(sum(amount_minor),0) AS TEXT) FROM ledger_entries) AS total_net_contributions_rwf`)]);
 const source=result.results[0],amountKeys=Object.keys(adminBridgeMetrics).filter(k=>k.startsWith('total_')),
  countKeys=Object.keys(adminBridgeMetrics).filter(k=>!k.startsWith('total_'));
 const counts=Object.fromEntries(countKeys.map(k=>[k,exact(source[k])])),amounts=Object.fromEntries(amountKeys.map(k=>[k,amountString(source[k])]));
 return {...marker,country_code:'RW',measured_at:now(),counts,amounts,contribution_basis:contributionBasis,collected_basis:collectedBasis,reconciliations_available:true,
  metrics:Object.entries(adminBridgeMetrics).map(([key,label])=>({key,label,value:String(source[key]),status:'measured'}))};
}

