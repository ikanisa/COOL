import {first,uuid,integer,now} from './core.js';
import {coreStatuses,coreOrdering,coreSearch} from './admin_search.js';
import {marker,contributionBasis,collectedBasis,fail,unavailable,iso,exact,amountString} from './admin_record_values.js';
import {lists,membershipSql,membershipRow,payeeSql,payeeRow,ledgerSql,ledgerRow,evidenceMetadataSql,evidenceMetadata} from './admin_record_sources.js';

// These read adapters receive an already authorized D1 binding from the route.
export {marker,permission,lists,list,filters,overview,operatingDetail,relatedPage,ledgerSql,ledgerRow,evidenceMetadataSql,evidenceMetadata,exact,iso,fail,unavailable};

const permission={groups:'collections',users:'users',members:'users',payees:'receivers',transactions:'payments',ledgers:'ledger'};

export const adminBridgeMetrics={
 users:'Users',app_users:'App users',direct_users:'Direct users',admin_users:'Admin users',staff_users:'Staff users',
 groups:'Groups',active_members:'Active members',payees:'Payees',active_payees:'Active payees',transactions:'Transactions',
 unallocated_transactions:'Unallocated transactions',ledger_entries:'Ledger entries',reversed_entries:'Reversal entries',payment_evidence:'Retained payment evidence',
 total_recorded_rwf:'Recorded evidence amount',total_reconciled_rwf:'Reconciled evidence amount',
 total_unallocated_rwf:'Unallocated evidence amount',total_net_contributions_rwf:'Net recorded contributions',
};

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
 // A skipped member does not need a balance or membership count unless it sorts or filters the page.
 const pageSql = type === 'members' && f.offset > 0
  ? `WITH records AS NOT MATERIALIZED (${spec.query}), selected AS (
       SELECT id FROM records${where} ORDER BY ${ordering} LIMIT ? OFFSET ?
     )
     SELECT records.* FROM records JOIN selected USING (id) ORDER BY ${ordering}`
  : `${cte} SELECT * FROM records${where} ORDER BY ${ordering} LIMIT ? OFFSET ?`;
 const [count,page]=await env.DB.batch([env.DB.prepare(`${cte} SELECT count(*) AS total FROM records${where}`).bind(...args),
  env.DB.prepare(pageSql).bind(...args,f.limit,f.offset)]);
 const total=exact(count.results[0].total),result=page.results.map(spec.row);
 if(result.length!==Math.max(0,Math.min(f.limit,total-f.offset)))fail(503,'invalid_source_data','Workspace measurements are unavailable.');
 return {...marker,rows:result,total};
}

// Every related page is counted and read in one guarded D1 batch. A scoped
// lookup must never silently fall back to the global people/receiver directory.
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
