import {first,uuid} from './core.js';
import {accountDatabase} from './admin_accounts.js';
import {marker,list,filters,relatedPage,ledgerSql,ledgerRow,evidenceMetadataSql,evidenceMetadata,exact,iso,fail} from './admin_records.js';

const proposalSql=`SELECT r.*,s.member_revision,s.membership_revision,s.collection_revision,s.payment_identity_json,
 s.receiver_number,s.receiver_network,s.receiver_label,u.public_id AS member_public_id,
 (SELECT json_extract(a.details_json,'$.reason') FROM audit_log a WHERE a.entity_type='reconciliation' AND a.entity_id=r.id
  AND a.action='propose_payment_reconciliation_v2' ORDER BY a.id DESC LIMIT 1) AS proposal_reason,
 (SELECT json_extract(a.details_json,'$.reason') FROM audit_log a WHERE a.entity_type='reconciliation' AND a.entity_id=r.id
  AND a.action IN ('approve_payment_reconciliation_v2','reject_payment_reconciliation_v2') ORDER BY a.id DESC LIMIT 1) AS review_reason
 FROM reconciliations r LEFT JOIN admin_bridge_reconciliation_snapshots s ON s.reconciliation_id=r.id
 JOIN users u ON u.id=r.proposed_member_id`;
function proposalRow(r){return {id:r.id,payment_id:r.payment_id,member_user_id:r.proposed_member_id,member_public_id:r.member_public_id,
 status:r.status,version:r.status==='proposed'?1:2,expected_payment_version:exact(r.expected_payment_revision),evidence_id:r.evidence_id,
 proposed_by_principal_id:r.proposed_by,reviewed_by_principal_id:r.approved_by,created_at:iso(r.created_at),reviewed_at:r.approved_at?iso(r.approved_at):null,
 request_id:r.request_id,reason:r.proposal_reason??null,review_reason:r.review_reason??null,
 snapshot_available:r.payment_identity_json!==null,payment_identity:r.payment_identity_json?JSON.parse(r.payment_identity_json):null,
 member_version:r.member_revision,membership_version:r.membership_revision,group_version:r.collection_revision,
 receiver_identity:r.payment_identity_json?{momo_number_or_code:r.receiver_number,network:r.receiver_network,label:r.receiver_label}:null};}
export async function canonicalReconciliationRead(env,account,actor,parts,url){
 if(!actor.permissions.has('reconciliations.read'))fail(403,'permission_required','Payment reconciliation is unavailable.');
 if(parts[0]==='members'){
  if(!actor.permissions.has('users.read'))fail(403,'permission_required','Member review is unavailable.');
  const f=filters(url,['transaction_id','search','limit','offset']),transactionId=uuid(url.searchParams.get('transaction_id'),'transaction_id');
  const scoped=accountDatabase(env,account,'users.read'),condition=`u.access_status='active' AND m.active=1 AND c.status='active'
   AND u.full_name!='' AND u.momo_number!='' AND u.member_type!='operator' AND m.collection_id=(SELECT collection_id FROM payments WHERE id=?)
   AND (?='' OR instr(lower(u.full_name),lower(?))>0 OR instr(u.public_id,?)>0 OR instr(u.momo_number,?)>0)`;
  const args=[transactionId,f.search,f.search,f.search,f.search],from=`FROM users u JOIN memberships m ON m.user_id=u.id JOIN collections c ON c.id=m.collection_id WHERE ${condition}`;
  const [count,result]=await scoped.DB.batch([scoped.DB.prepare(`SELECT count(*) AS total ${from}`).bind(...args),
   scoped.DB.prepare(`SELECT u.id AS member_user_id,u.revision AS member_version,u.member_type,u.public_id,u.full_name AS display_name,u.momo_provider,u.momo_number,u.momo_pay_code,
    m.revision AS membership_version,m.role AS membership_role,c.id AS group_id,c.title AS group_title,c.revision AS group_version ${from}
    ORDER BY u.full_name,u.public_id,c.id LIMIT ? OFFSET ?`).bind(...args,f.limit,f.offset)]);
  const total=exact(count.results[0].total),values=result.results.map(r=>({...r,payment_identity:{display_name:r.display_name,momo_provider:r.momo_provider,momo_number:r.momo_number,momo_pay_code:r.momo_pay_code}}));
  if(values.length!==Math.max(0,Math.min(f.limit,total-f.offset)))fail(503,'invalid_source_data','Member review is unavailable.');
  return {...marker,transaction_id:transactionId,rows:values,total,limit:f.limit,offset:f.offset,next_offset:f.offset+values.length<total?f.offset+values.length:null};
 }
 if(parts.length===0){
  const f=filters(url,undefined,'transactions'),result=await list(accountDatabase(env,account,'payments.read'),'transactions',url);
  return {...result,limit:f.limit,offset:f.offset,next_offset:f.offset+result.rows.length<result.total?f.offset+result.rows.length:null};
 }
 if(parts.length!==1)fail(404,'not_found','This reconciliation view is unavailable.');
 if(!actor.permissions.has('users.read'))fail(403,'permission_required','Recorded member identity review is unavailable.');
 const resourceId=uuid(parts[0]),f=filters(url,['relation','limit','offset']),relation=url.searchParams.get('relation'),scoped=accountDatabase(env,account,'reconciliations.read');
 const result=await list(scoped,'transactions',new URL(url.origin),{id:resourceId});if(!result.rows.length)fail(404,'not_found','This payment was not found.');
 const resource=result.rows[0],group=await first(scoped,'SELECT id,status,revision,receiver_momo_number,receiver_network,receiver_display_label FROM collections WHERE id=?',resource.group_id);
 const relations={evidence:[evidenceMetadataSql,[resourceId],evidenceMetadata],proposals:[`${proposalSql} WHERE r.payment_id=?`,[resourceId],proposalRow]};
 if(actor.permissions.has('ledger.read'))relations.ledger_entries=[`SELECT * FROM (${ledgerSql}) WHERE payment_id=?`,[resourceId],ledgerRow];
 if(relation&&!Object.hasOwn(relations,relation))fail(400,'invalid_filter','This reconciliation page is unavailable.');
 const related={};for(const [name,[query,args,map]] of Object.entries(relations)){
  if(relation&&relation!==name)continue;const page=await relatedPage(scoped,query,args,map,f);related[name]={rows:page.rows,...page.page};
 }
 return {...marker,resource_type:'reconciliations',resource,current_actor_id:account.id,current_principal_id:account.principal_id,
  can_propose:actor.permissions.has('reconciliations.propose')&&group.status==='active'&&['recorded','ambiguous'].includes(resource.status)&&resource.member_user_id===null&&resource.allocated_amount_rwf===0,
  can_review:actor.permissions.has('reconciliations.review')&&account.role!=='staff',
  group_state:{id:group.id,status:group.status,version:exact(group.revision),receiver:{momo_number_or_code:group.receiver_momo_number,network:group.receiver_network,label:group.receiver_display_label}},related};
}
