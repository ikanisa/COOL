import {digest,first,now,stableJson,text} from './core.js';
import {marker,filters,exact,iso,fail} from './admin_records.js';
import {accountDatabase,accountReadDatabase} from './admin_accounts.js';
import {requireFreshAdminEmail} from './admin_email_policy.js';
import {mutation,retainedResponse} from './mutations.js';
import {keys} from './admin_operation_fields.js';
import {requestId,domainGuard,receipt} from './admin_request_aliases.js';

function historyReceipt(row){
 const value=JSON.parse(row.response_json);if(value.resource_type)return value;
 if(row.operation.startsWith('operations.transactions.'))return receipt(row.request_id,'transactions',value.id??value.payment_id,value.revision??1);
 if(row.operation.startsWith('reconciliations.proposals.'))return {...marker,...receipt(row.request_id,'reconciliation_proposals',value.id,2),transaction_id:value.payment_id,proposal_status:value.status,transaction_version:value.payment_revision??value.expected_payment_revision+1,settlement_status:'not_asserted'};
 if(row.operation.startsWith('reconciliations.'))return {...marker,...receipt(row.request_id,'reconciliation_proposals',value.id,1),transaction_id:value.payment_id,proposal_status:'proposed',settlement_status:'not_asserted'};
 fail(503,'receipt_unavailable','The retained request outcome is unavailable.');
}
function requestScope(operation){
 if(/^operations\.(groups|users)\.[^.]+\.notes\.POST$/.test(operation))return 'operator_notes.post';
 if(operation==='request.cancelled')return 'requests.cancel';
 if(operation.startsWith('reconciliations.'))return operation.includes('.reviews')?'reconciliations.review':'reconciliations.propose';
 const parts=operation.split('.');if(parts[0]!=='operations'||!['groups','users','memberships','payees','transactions'].includes(parts[1]))fail(503,'receipt_unavailable','The retained request scope is unavailable.');
 const method=parts.at(-1)?.toLowerCase();if(!['post','patch'].includes(method))fail(503,'receipt_unavailable','The retained request method is unavailable.');
 return `${parts[1]}.${method}${parts[1]==='transactions'&&parts[3]==='reverse'?'.reverse':''}`;
}
function requestOutcome(row){
 if(!row)return {...marker,status:'not_found'};
 if(row.operation==='request.cancelled'){
  if(row.response_json)fail(503,'request_state_unavailable','The original request state needs review.');
  return {...marker,status:'cancelled',request_id:row.request_id,receipt:null};
 }
 return {...marker,status:row.response_json?'succeeded':'unconfirmed',request_id:row.request_id,receipt:row.response_json?historyReceipt(row):null};
}
async function originalRequest(env,account,key){return first(env,`SELECT a.request_id,a.operation,r.response_json
 FROM admin_bridge_requests a LEFT JOIN request_receipts r ON r.user_id=? AND r.request_id=a.request_id
 WHERE a.admin_user_id=? AND a.idempotency_key=?`,account.principal_id,account.id,key);}
export async function cancelOriginalRequest(env,account,actor,targetKey,data,rid,source){
 keys(data,['reason']);const reason=text(data.reason,'reason',500);
 if(reason.length<8)fail(400,'reason_required','Record a reason of at least eight characters.');
 if(!actor.permissions.has('account.manage'))fail(403,'permission_required','This action is unavailable.');
 requireFreshAdminEmail(actor);const targetId=await requestId(account,targetKey);
 if(targetId===rid)fail(400,'invalid_request','Use a separate cancellation request reference.');
 const scoped=accountDatabase(env,account,'account.manage'),operation='admin.request.cancel',
  options={permission:'account.manage',minimumAssurance:2,freshSeconds:300,entityType:'request_cancellation',entityId:targetId,
   auditDetails:{reason,target_request_id:targetId}};
 const replay=await retainedResponse(scoped,actor,operation,rid,source,options);if(replay.found)return replay.value;
 let current=await originalRequest(scoped,account,targetKey);
 if(current){const outcome=requestOutcome(current);
  if(outcome.status==='unconfirmed')fail(409,'request_unconfirmed','Keep the original reference while its state is reviewed.');
  return mutation(scoped,actor,operation,rid,source,outcome,[],options);
 }
 const guard=domainGuard(scoped,`EXISTS(SELECT 1 FROM admin_bridge_requests WHERE admin_user_id=? AND idempotency_key=? AND request_id=? AND operation='request.cancelled')`,[account.id,targetKey,targetId]);
 const result={...marker,status:'cancelled',request_id:targetId,receipt:null};
 const writes=[scoped.DB.prepare(`INSERT INTO admin_bridge_requests(admin_user_id,idempotency_key,request_id,session_id,operation,body_sha256,created_at)
  VALUES(?,?,?,?,'request.cancelled',?,?) ON CONFLICT(admin_user_id,idempotency_key) DO NOTHING`)
  .bind(account.id,targetKey,targetId,account.auth_session_id,await digest(stableJson(source)),now()),guard[0],guard[1]];
 try{return await mutation(scoped,actor,operation,rid,source,result,writes,options);}
 catch(error){
  current=await originalRequest(scoped,account,targetKey);
  if(!current||requestOutcome(current).status==='unconfirmed')throw error;
  // The original write may have won the same atomic D1 race. Return its
  // retained effect instead of claiming that a committed change was cancelled.
  return mutation(scoped,actor,operation,rid,source,requestOutcome(current),[],options);
 }
}

export async function adminRequestHistory(env,account,parts,url){
 if(parts.length>2||parts.length===2&&!parts[1])fail(404,'not_found','This request view is unavailable.');
 if(!account.permissions.includes('account.manage'))fail(403,'permission_required','Request history is unavailable.');env=accountReadDatabase(env,account,'account.manage');
 const resource=parts[1];if(resource){if(!/^[a-zA-Z0-9_.-]{8,200}$/.test(resource)||url.search)fail(400,'invalid_request','Invalid request lookup.');
   const [result]=await env.DB.batch([env.DB.prepare(`SELECT a.request_id,a.operation,r.response_json FROM admin_bridge_requests a LEFT JOIN request_receipts r ON r.user_id=? AND r.request_id=a.request_id WHERE a.admin_user_id=? AND a.idempotency_key=?`).bind(account.principal_id,account.id,resource)]);
   return requestOutcome(result.results[0]);
  }
 const f=filters(url,['limit','offset']);const [count,result]=await env.DB.batch([env.DB.prepare('SELECT count(*) AS total FROM admin_bridge_requests WHERE admin_user_id=?').bind(account.id),
   env.DB.prepare(`SELECT a.*,r.response_json FROM admin_bridge_requests a LEFT JOIN request_receipts r ON r.user_id=? AND r.request_id=a.request_id WHERE a.admin_user_id=? ORDER BY a.created_at DESC,a.request_id LIMIT ? OFFSET ?`).bind(account.principal_id,account.id,f.limit,f.offset)]);
  return {...marker,total:exact(count.results[0].total),rows:result.results.map(r=>{const outcome=requestOutcome(r);return {id:r.request_id,idempotency_key:r.idempotency_key,scope:requestScope(r.operation),status:outcome.status,receipt:outcome.receipt,created_at:iso(r.created_at)};})};
}
