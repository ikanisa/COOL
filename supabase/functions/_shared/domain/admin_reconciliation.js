import {json,readJson,first,uuid,integer,text,stableJson,now} from './core.js';
import {marker,fail,unavailable} from './admin_records.js';
import {canonicalReconciliationRead} from './admin_reconciliation_reads.js';
import {adminRequestHistory} from './admin_request_history.js';
import {accountDatabase} from './admin_accounts.js';
import {retainedResponse} from './mutations.js';
import {financialRpc} from './payments.js';
import {keys} from './admin_operation_fields.js';
import {requestEnvironment,requestId,receipt,domainGuard} from './admin_request_aliases.js';

export async function adminReconciliationRoute(request,env,base,account,actor,parts,url){
  if(!actor.permissions.has('payments.read'))fail(403,'permission_required','Payment review is unavailable.');
  if(request.method==='GET'){
   if(!actor.permissions.has('reconciliations.read'))fail(403,'permission_required','Payment reconciliation is unavailable.');
   if(parts[0]==='requests')return json(await adminRequestHistory(base,account,parts,url));
   return json(await canonicalReconciliationRead(base,account,actor,parts,url));
  }
  if(request.method!=='POST')unavailable();
  if(!actor.permissions.has('users.read'))fail(403,'permission_required','Recorded member identity review is unavailable.');
  const data=await readJson(request),key=request.headers.get('Idempotency-Key'),rid=await requestId(account,key),source={method:request.method,path:url.pathname,body:data};
  const reconciliationBase=accountDatabase(env,account,'users.read'),scoped=requestEnvironment(reconciliationBase,account,key,rid,`reconciliations.${parts.join('.')}`,source);let result;
  if(parts.length===2&&parts[1]==='proposals'){
   if(!actor.permissions.has('reconciliations.propose'))fail(403,'permission_required','Payment attribution is unavailable.');
   keys(data,['member_user_id','amount_rwf','expected_transaction_version','expected_member_version','expected_membership_version','expected_payment_identity','reason']);
   const payload={p_payment_id:uuid(parts[0]),p_member_id:uuid(data.member_user_id),p_request_id:rid,admin_bridge_request:source};
   const replay=await retainedResponse(scoped,actor,'propose_payment_reconciliation_v2',rid,payload,{permission:'reconciliations.propose',minimumAssurance:2,freshSeconds:300});
   if(replay.found)return json({...marker,...receipt(rid,'reconciliation_proposals',replay.value.id,1),transaction_id:payload.p_payment_id,proposal_status:'proposed',settlement_status:'not_asserted'});
   const p=await first(base,'SELECT * FROM payments WHERE id=?',payload.p_payment_id);if(!p)fail(404,'not_found','This payment was not found.');
   if(integer(data.expected_transaction_version,'transaction version',1)!==p.revision)fail(409,'stale_state','The payment changed. Refresh before continuing.');
   if(integer(data.amount_rwf,'amount_rwf',1)!==p.amount_minor)unavailable();text(data.reason,'reason',500);
   const member=await first(base,`SELECT u.*,m.id AS membership_id,m.revision AS membership_revision,c.revision AS collection_revision,
    c.receiver_momo_number,c.receiver_network,c.receiver_display_label FROM users u JOIN memberships m ON m.user_id=u.id JOIN collections c ON c.id=m.collection_id
    WHERE u.id=? AND c.id=? AND m.active=1 AND u.access_status='active' AND c.status='active'`,payload.p_member_id,p.collection_id);
   if(!member)fail(409,'member_changed','The selected member is no longer eligible.');
   const memberVersion=integer(data.expected_member_version,'member version',1),membershipVersion=integer(data.expected_membership_version,'membership version',1);
   if(member.revision!==memberVersion||member.membership_revision!==membershipVersion)fail(409,'member_changed','The selected member changed.');
   const identity=data.expected_payment_identity;if(!identity||typeof identity!=='object'||Array.isArray(identity))fail(400,'invalid_payment_identity','Review the recorded member payment identity.');keys(identity,['display_name','momo_provider','momo_number','momo_pay_code']);
   const actualIdentity={display_name:member.full_name,momo_provider:member.momo_provider,momo_number:member.momo_number,momo_pay_code:member.momo_pay_code};
   if(!member.full_name||!member.momo_number||stableJson(identity)!==stableJson(actualIdentity))fail(409,'member_changed','The recorded payment identity changed.');
   const gate=domainGuard(base,`EXISTS(SELECT 1 FROM users u JOIN memberships m ON m.user_id=u.id JOIN collections c ON c.id=m.collection_id
    WHERE u.id=? AND u.revision=? AND u.access_status='active' AND m.id=? AND m.revision=? AND m.active=1 AND c.id=? AND c.revision=? AND c.status='active')`,
    [member.id,memberVersion,member.membership_id,membershipVersion,p.collection_id,member.collection_revision]);
   const snapshot=base.DB.prepare(`INSERT INTO admin_bridge_reconciliation_snapshots(reconciliation_id,collection_id,collection_revision,member_id,member_revision,membership_id,membership_revision,payment_identity_json,receiver_number,receiver_network,receiver_label,created_at)
    SELECT id,?,?,?,?,?,?,?,?,?,?,? FROM reconciliations WHERE request_id=?`).bind(p.collection_id,member.collection_revision,member.id,memberVersion,member.membership_id,membershipVersion,stableJson(actualIdentity),member.receiver_momo_number,member.receiver_network,member.receiver_display_label,now(),rid);
   if(p.evidence_id){const retained=await first(base,'SELECT receiver_momo_number,receiver_network,receiver_display_label FROM payment_evidence WHERE id=?',p.evidence_id);
    if(!retained||retained.receiver_momo_number!==member.receiver_momo_number||retained.receiver_network!==member.receiver_network||retained.receiver_display_label!==member.receiver_display_label)fail(409,'receiver_changed','The current receiver differs from the retained evidence. Review the receiver history before attribution.');}
   result=await financialRpc('propose_payment_reconciliation_v2',payload,requestEnvironment(reconciliationBase,account,key,rid,`reconciliations.${parts.join('.')}`,source,{before:[gate[0]],after:[snapshot,gate[1]]}),actor,{permission:'reconciliations.propose',freshSeconds:300,reason:data.reason});
   return json({...marker,...receipt(rid,'reconciliation_proposals',result.value.id,1),transaction_id:p.id,proposal_status:'proposed',settlement_status:'not_asserted'});
  }
  if(parts.length===3&&parts[0]==='proposals'&&parts[2]==='reviews'){
   if(!actor.permissions.has('reconciliations.review')||account.role==='staff')fail(403,'permission_required','Independent payment review is unavailable.');
   keys(data,['outcome','expected_proposal_version','expected_transaction_version','reason']);if(!['approved','rejected'].includes(data.outcome))unavailable();integer(data.expected_proposal_version,'proposal version',1,1);text(data.reason,'reason',500);
   const approved=data.outcome==='approved',operation=approved?'approve_payment_reconciliation_v2':'reject_payment_reconciliation_v2';
   const payload={p_reconciliation_id:uuid(parts[1]),p_request_id:rid,admin_bridge_request:source};
   const replay=await retainedResponse(scoped,actor,operation,rid,payload,{permission:'reconciliations.review',minimumAssurance:2,freshSeconds:300});
   if(replay.found)return json({...marker,...receipt(rid,'reconciliation_proposals',parts[1],2),transaction_id:replay.value.payment_id,proposal_status:replay.value.status,transaction_version:replay.value.payment_revision??replay.value.expected_payment_revision+1,settlement_status:'not_asserted'});
   const snapshot=await first(base,`SELECT s.*,r.payment_id,p.revision AS payment_revision FROM admin_bridge_reconciliation_snapshots s JOIN reconciliations r ON r.id=s.reconciliation_id JOIN payments p ON p.id=r.payment_id WHERE r.id=?`,payload.p_reconciliation_id);
   if(!snapshot)fail(409,'review_snapshot_unavailable','A retained identity review snapshot is required.');
   if(integer(data.expected_transaction_version,'transaction version',1)!==snapshot.payment_revision)fail(409,'stale_state','The payment changed. Refresh before continuing.');
   const identity=JSON.parse(snapshot.payment_identity_json),gate=domainGuard(base,`EXISTS(SELECT 1 FROM collections c JOIN memberships m ON m.collection_id=c.id JOIN users u ON u.id=m.user_id
    WHERE c.id=? AND c.revision=? AND c.status='active' AND c.receiver_momo_number IS ? AND c.receiver_network IS ? AND c.receiver_display_label IS ?
    AND m.id=? AND m.revision=? AND m.active=1 AND u.id=? AND u.revision=? AND u.access_status='active'
    AND u.full_name=? AND u.momo_provider=? AND u.momo_number=? AND u.momo_pay_code=?)`,[snapshot.collection_id,snapshot.collection_revision,snapshot.receiver_number,snapshot.receiver_network,snapshot.receiver_label,
    snapshot.membership_id,snapshot.membership_revision,snapshot.member_id,snapshot.member_revision,identity.display_name,identity.momo_provider,identity.momo_number,identity.momo_pay_code]);
   result=await financialRpc(operation,payload,requestEnvironment(reconciliationBase,account,key,rid,`reconciliations.${parts.join('.')}`,source,approved?{before:[gate[0]],after:[gate[1]]}:{}),actor,{permission:'reconciliations.review',freshSeconds:300,reason:data.reason});
   return json({...marker,...receipt(rid,'reconciliation_proposals',parts[1],2),transaction_id:result.value.payment_id,proposal_status:result.value.status,transaction_version:result.value.payment_revision,settlement_status:'not_asserted'});
  }
  unavailable();
}
