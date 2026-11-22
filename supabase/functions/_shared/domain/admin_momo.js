import {ApiError,json,readJson,first,rows,now,id,digest,uuid,integer,text,requirePermission} from './core.js';
import {accountDatabase} from './admin_accounts.js';
import {mutation,retainedResponse} from './mutations.js';
import {gatewayToken,momoGuard} from './momo_gateway.js';
import {validateProviderProfile,prepareMomoSourceReview,momoOutcomeUnresolved,MOMO_JOB_CHECKPOINT} from './momo_pipeline.js';
import {withReceiptFacts} from './receipt_facts.js';
import {captureContent} from './admin_sms_receipts.js';
import {adminBuriMunsiSetup} from './admin_burimunsi_setup.js';
import {adminBuriMunsiObservationRoute} from './admin_burimunsi_observations.js';
import {MANAGED_MOMO_SOURCE_SQL,momoTransactionSql,queryMomoFilters as query,momoTransactionPage,momoPaymentChecks,exactMomoMeasurement} from './admin_momo_reads.js';
import {assignMomoPayment,reviewMomoConflict} from './admin_momo_payment_review.js';

export {MANAGED_MOMO_SOURCE_SQL,momoTransactionSql,momoTransactionPredicates,momoTransactionPageRow} from './admin_momo_reads.js';

const fail=(s,c,m)=>{throw new ApiError(s,c,m);};
const keys=(body,allowed)=>{if(Object.keys(body).some(k=>!allowed.includes(k)))fail(400,'invalid_request','This action contains unsupported fields.');};
const requestId=async(account,key)=>{if(typeof key!=='string'||!/^[a-zA-Z0-9_.-]{8,200}$/.test(key))fail(400,'idempotency_required','Supply an Idempotency-Key.');const sha=await digest(`collect-momo:${account.principal_id}:${key}`);return `${sha.slice(0,8)}-${sha.slice(8,12)}-4${sha.slice(13,16)}-8${sha.slice(17,20)}-${sha.slice(20,32)}`;};

export async function adminMomoRoute(request,env,account,actor,parts,url){
 if(parts[0]==='native-setup')return adminBuriMunsiSetup(request,env,account,actor,parts,url);
 if(parts[0]==='observations')return adminBuriMunsiObservationRoute(request,env,account,actor,parts,url);
 const area=parts[0];if(!['accounts','bindings','transactions','sources'].includes(area))fail(404,'not_found','This MoMo view does not exist.');
 const readPermission=['accounts','bindings'].includes(area)?'receivers.read':area==='sources'?'sms.read':'payments.read';requirePermission(actor,readPermission);
 if(request.method==='GET'){
  const scoped=accountDatabase(env,account,readPermission);
  if(area==='accounts'&&parts.length===1){query(url,[]);const result=await scoped.DB.batch([scoped.DB.prepare('SELECT id,provider,public_code,recipient_name,currency,timezone,status,profile_status,profile_version,created_at FROM momo_receiving_accounts ORDER BY created_at DESC,id')]);return json({rows:result[0].results});}
  if(area==='bindings'&&parts.length===1){query(url,[]);const result=await scoped.DB.batch([scoped.DB.prepare(`SELECT b.*,c.last_contact_at,c.last_sms_at,c.pending_count,c.oldest_pending_at FROM momo_gateway_bindings b LEFT JOIN momo_gateway_credentials c ON c.binding_id=b.id ORDER BY b.created_at DESC,b.id LIMIT 100`)]);return json({rows:result[0].results});}
  if(area==='transactions'&&parts.length===1)return json(await momoTransactionPage(scoped,url));
  if(area==='transactions'&&parts.length===2&&parts[1]==='payment-checks'){
   requirePermission(actor,'users.read');requirePermission(actor,'collections.read');
   return json(await momoPaymentChecks(accountDatabase(accountDatabase(scoped,account,'users.read'),account,'collections.read'),url));
  }
  if(area==='transactions'&&parts.length===3&&parts[2]==='candidates'){
   requirePermission(actor,'users.read');requirePermission(actor,'collections.read');
   const f=query(url,['limit','offset','search']),txId=uuid(parts[1]),lookup=accountDatabase(accountDatabase(scoped,account,'users.read'),account,'collections.read');
   const condition=`t.id=? AND ${MANAGED_MOMO_SOURCE_SQL} AND t.has_conflict=0 AND t.allocation_state='unallocated' AND g.status='active' AND m.active=1 AND u.access_status='active' AND u.member_type!='operator'
    AND g.receiver_network=a.provider AND
    (CASE WHEN g.receiver_momo_number GLOB '07*' AND length(g.receiver_momo_number)=10 THEN '250'||substr(g.receiver_momo_number,2) ELSE replace(g.receiver_momo_number,'+','') END)=
    (CASE WHEN a.public_code GLOB '07*' AND length(a.public_code)=10 THEN '250'||substr(a.public_code,2) ELSE replace(a.public_code,'+','') END)
    AND (?='' OR instr(lower(u.full_name),lower(?))>0 OR instr(u.public_id,?)>0)`,args=[txId,f.search,f.search,f.search],from=`FROM momo_transactions t JOIN momo_receiving_accounts a ON a.id=t.receiving_account_id
    JOIN collections g JOIN memberships m ON m.collection_id=g.id JOIN users u ON u.id=m.user_id WHERE ${condition}`;
   const result=await lookup.DB.batch([lookup.DB.prepare(`SELECT count(*) AS n ${from}`).bind(...args),lookup.DB.prepare(`SELECT g.id AS group_id,g.title AS group_name,u.id AS member_id,u.full_name AS member_name,u.public_id AS member_public_id ${from} ORDER BY u.full_name,g.title,u.id,g.id LIMIT ? OFFSET ?`).bind(...args,f.limit,f.offset)]);
   return json({rows:result[1].results,total:exactMomoMeasurement(result[0].results[0].n),limit:f.limit,offset:f.offset});}
  if(area==='transactions'&&parts.length===2){query(url,[]);const txId=uuid(parts[1]),result=await scoped.DB.batch([scoped.DB.prepare(`SELECT * FROM (${momoTransactionSql(env)}) WHERE id=?`).bind(txId),scoped.DB.prepare(`SELECT s.raw_sms_id,s.relation,s.created_at,a.id AS attempt_id,a.outcome,a.model_id,a.schema_version,a.parser_version,a.validation_json FROM momo_transaction_sources s JOIN momo_parse_attempts a ON a.id=s.parse_attempt_id WHERE s.transaction_id=? ORDER BY a.created_at DESC LIMIT 100`).bind(txId),scoped.DB.prepare("SELECT DISTINCT parse_attempt_id FROM momo_transaction_sources WHERE transaction_id=? AND relation='conflict' ORDER BY parse_attempt_id LIMIT 101").bind(txId),scoped.DB.prepare("SELECT actor_user_id,details_json,created_at FROM audit_log WHERE action='momo.conflict.reviewed' AND entity_id=? ORDER BY id DESC LIMIT 25").bind(txId)]);if(!result[0].results.length)fail(404,'not_found','This transaction is unavailable.');return json({transaction:withReceiptFacts(result[0].results[0]),sources:result[1].results,conflicting_attempt_ids:result[2].results.map(row=>row.parse_attempt_id),conflict_reviews:result[3].results});}
  if(area==='sources'&&parts.length===1){const f=query(url,['limit','offset','status']);if(f.status&&!['pending','processing','retry','completed','needs_review','source_unresolved'].includes(f.status))fail(400,'invalid_filter','Choose a valid processing state.');
   const condition=f.status?' WHERE j.state=?':'',args=f.status?[f.status]:[],result=await scoped.DB.batch([scoped.DB.prepare(`SELECT count(*) AS total FROM momo_processing_jobs j JOIN sms_receipts s ON s.id=j.raw_sms_id AND s.originating_session_id IS NOT NULL${condition}`).bind(...args),scoped.DB.prepare(`SELECT j.*,s.body_sha256,s.received_at_device,s.created_at AS received_at,
    (SELECT id FROM momo_parse_attempts a WHERE a.raw_sms_id=j.raw_sms_id ORDER BY attempt_number DESC LIMIT 1) AS latest_attempt_id,
    (SELECT outcome FROM momo_parse_attempts a WHERE a.raw_sms_id=j.raw_sms_id ORDER BY attempt_number DESC LIMIT 1) AS latest_attempt_outcome
    FROM momo_processing_jobs j JOIN sms_receipts s ON s.id=j.raw_sms_id AND s.originating_session_id IS NOT NULL${condition} ORDER BY j.created_at DESC,j.raw_sms_id LIMIT ? OFFSET ?`).bind(...args,f.limit,f.offset)]);return json({rows:result[1].results,total:result[0].results[0].total,limit:f.limit,offset:f.offset});}
  if(area==='sources'&&parts.length===3&&parts[2]==='content'){
   const rawId=uuid(parts[1]),content=await captureContent(request,env,account,actor,['receipts','capture',rawId,'content'],url,'momo.source.revealed');
   const reveal=accountDatabase(accountDatabase(env,account,'sms.read',{mfa:true,fresh:true}),account,'sms.reveal',{mfa:true,fresh:true});
   const [attempts]=await reveal.DB.batch([reveal.DB.prepare('SELECT id,attempt_number,outcome,model_id,schema_version,parser_version,output_json,validation_json,created_at FROM momo_parse_attempts WHERE raw_sms_id=? ORDER BY attempt_number DESC LIMIT 1').bind(rawId)]);
   return json({raw_sms_id:rawId,body_sha256:content.source_sha256,raw_sender:content.raw_sender,raw_body:content.raw_body,latest_attempt:attempts.results[0]??null});}

  fail(404,'not_found','This MoMo view does not exist.');
 }
 if(request.method!=='POST'||url.search)fail(405,'method_not_allowed','Use the supported MoMo action.');
 const body=await readJson(request,32768),rid=await requestId(account,request.headers.get('Idempotency-Key')),source={path:url.pathname,body},reason=text(body.reason,'reason',500);
 if(reason.length<8)fail(400,'reason_required','Record a reason of at least eight characters.');
 const cap=area==='transactions'?'payments.write':area==='sources'?'sms.extract':'receivers.manage';requirePermission(actor,cap);
 const scoped=accountDatabase(env,account,cap,{mfa:true,fresh:true}),options={permission:cap,minimumAssurance:2,freshSeconds:300};
 if(area==='transactions'&&parts.length===3&&parts[2]==='assign')return json(await assignMomoPayment(scoped,actor,uuid(parts[1]),body,rid,source));
 if(area==='transactions'&&parts.length===3&&parts[2]==='review-conflict'){
  requirePermission(actor,'sms.extract');const reviewed=accountDatabase(accountDatabase(scoped,account,'payments.read'),account,'sms.extract',{mfa:true,fresh:true});
  return json(await reviewMomoConflict(reviewed,actor,uuid(parts[1]),body,rid,source));
 }
 if(area==='sources'&&parts.length===3&&['correct-extraction','classify-non-payment'].includes(parts[2])){
  const nonPayment=parts[2]==='classify-non-payment';keys(body,['expected_state','expected_attempt_count','expected_body_sha256','extraction','evidence_reference','reason',...(nonPayment?['classification_evidence']:[])]);
  integer(body.expected_attempt_count,'expected_attempt_count',0);if(typeof body.expected_body_sha256!=='string'||!/^[a-f0-9]{64}$/.test(body.expected_body_sha256))fail(400,'invalid_source','Use the current source digest.');
  const evidence=text(body.evidence_reference,'supporting evidence',500);if(evidence.length<8)fail(400,'evidence_required','Record the source evidence supporting this review.');
  if(nonPayment)text(body.classification_evidence,'classification evidence',2048);
  const reviewed=accountDatabase(scoped,account,'sms.read'),operation=nonPayment?'momo.source.non_payment':'momo.source.corrected';
  const prior=await retainedResponse(reviewed,actor,operation,rid,source,options);if(prior.found)return json(prior.value);
  const prepared=await prepareMomoSourceReview(reviewed,actor,uuid(parts[1]),{...body,evidence_reference:evidence},rid,{nonPayment});
  return json(await mutation(reviewed,actor,operation,rid,source,prepared.value,prepared.writes,{...options,entityType:'sms_receipt',entityId:parts[1],auditDetails:{reason,evidence_reference:evidence,parse_attempt_id:prepared.value.parse_attempt_id}}));
 }
 const operation=`momo.${parts.join('.')}`,prior=await retainedResponse(scoped,actor,operation,rid,source,options);if(prior.found)return json(prior.value);
 const writes=[];let value;
 if(area==='accounts'&&parts.length===1){keys(body,['provider','public_code','recipient_name','reason']);
  const provider=body.provider,code=text(body.public_code,'MoMo code',32);if(!['mtn_momo','airtel_money'].includes(provider)||!/^\d{4,9}$|^\+?2507[2389]\d{7}$|^07[2389]\d{7}$/.test(code))fail(400,'invalid_account','Record a supported provider and actual MoMo destination.');
  const accountId=id(),canonical=/^07[2389]\d{7}$/.test(code)?'+250'+code.slice(1):/^2507/.test(code)?'+'+code:code;
  writes.push(scoped.DB.prepare('INSERT INTO momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,currency,timezone,created_at) VALUES(?,?,?,?,?,\'RWF\',\'Africa/Kigali\',?)').bind(accountId,provider,code,text(body.recipient_name,'recipient name',160),await digest(canonical),now()));value={id:accountId,status:'active',profile_status:'unverified'};
 }else if(area==='accounts'&&parts.length===3&&parts[2]==='profile'){keys(body,['profile','profile_version','reason']);const accountId=uuid(parts[1]),row=await first(scoped,'SELECT * FROM momo_receiving_accounts WHERE id=?',accountId);if(!row)fail(404,'not_found','This receiving account is unavailable.');
  const version=text(body.profile_version,'profile version',80),profile=JSON.stringify(body.profile);if(!validateProviderProfile({...row,profile_status:'approved',profile_version:version,profile_json:profile}))fail(400,'invalid_profile','Supply an explicitly reviewed provider source profile.');
  writes.push(scoped.DB.prepare(`UPDATE momo_receiving_accounts SET profile_status='approved',profile_version=?,profile_json=? WHERE id=?`).bind(version,profile,accountId));value={id:accountId,profile_status:'approved',profile_version:version};
 }else if(area==='bindings'&&parts.length===1){keys(body,['receiving_account_id','subscription_id','reason']);const accountId=uuid(body.receiving_account_id),bindingId=id(),pairingId=id(),code=gatewayToken(),subscription=body.subscription_id==null?null:integer(body.subscription_id,'subscription_id',0,2147483647);
  const gate=momoGuard(scoped,`EXISTS(SELECT 1 FROM momo_receiving_accounts WHERE id=? AND status='active')`,[accountId]);
  writes.push(gate[0],scoped.DB.prepare(`INSERT INTO momo_gateway_bindings(id,owner_user_id,receiving_account_id,subscription_evidence,created_at) VALUES(?,?,?,?,?)`).bind(bindingId,actor.userId,accountId,subscription===null?null:JSON.stringify({subscription_id:subscription}),now()),
   scoped.DB.prepare('INSERT INTO momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,created_at) VALUES(?,?,?,?,unixepoch()+600,?)').bind(pairingId,bindingId,await digest(code),actor.sessionId,now()),gate[1]);
  value={binding_id:bindingId,version:1,pairing_code:code,expires_in_seconds:600};
 }else if(area==='bindings'&&parts.length===3&&parts[2]==='revoke'){keys(body,['reason']);const bindingId=uuid(parts[1]);
  writes.push(scoped.DB.prepare(`UPDATE momo_gateway_bindings SET status='revoked',revoked_at=? WHERE id=?`).bind(now(),bindingId),scoped.DB.prepare('UPDATE momo_gateway_credentials SET revoked_at=? WHERE binding_id=?').bind(now(),bindingId));value={binding_id:bindingId,status:'revoked'};
 }else if(area==='sources'&&parts.length===2&&parts[1]==='backfill'){
  keys(body,['reason','cursor','limit']);const limit=integer(body.limit??50,'limit',1,100),cursor=body.cursor??null,asOf=cursor?.as_of??now(),after=cursor?.after_id??'';
  if(cursor&&(Object.keys(cursor).sort().join(',')!=='after_id,as_of'||typeof asOf!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(asOf)||!Number.isFinite(Date.parse(asOf))))fail(400,'invalid_cursor','Use the returned historical cursor.');
  if(after)uuid(after,'after_id');
  const selected=await rows(scoped,`SELECT s.id FROM sms_receipts s WHERE s.originating_session_id IS NOT NULL AND s.created_at<=? AND s.id>? AND NOT EXISTS(SELECT 1 FROM momo_processing_jobs j WHERE j.raw_sms_id=s.id) ORDER BY s.id LIMIT ?`,asOf,after,limit+1),page=selected.slice(0,limit);
  for(const raw of page)writes.push(scoped.DB.prepare(`INSERT INTO momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,available_at,created_at,updated_at)
   VALUES(?,NULL,NULL,NULL,'historical','source_unresolved',unixepoch(),?,?) ON CONFLICT(raw_sms_id) DO NOTHING`).bind(raw.id,now(),now()));
  value={inventoried:page.length,next_cursor:selected.length>limit?{as_of:asOf,after_id:page.at(-1).id}:null,status:'source_review_required',financial_effects:0};
 }else if(area==='sources'&&parts.length===3&&parts[2]==='resolve'){
  keys(body,['reason','receiving_account_id','evidence_reference']);const rawId=uuid(parts[1]),accountId=uuid(body.receiving_account_id),evidence=text(body.evidence_reference,'historical evidence reference',500);
  if(evidence.length<8)fail(400,'evidence_required','Reference the evidence establishing the historical receiving account.');
  const gate=momoGuard(scoped,'changes()=1'),updated=momoGuard(scoped,'changes()=1');
  // Lock and recheck the unresolved row first. The immutable source-identity
  // trigger requires the evidence row to exist before assigning the account.
  writes.push(scoped.DB.prepare(`UPDATE momo_processing_jobs SET lease_token=lease_token
   WHERE raw_sms_id=? AND state='source_unresolved' AND attempt_count=0 AND last_error IS NULL AND binding_id IS NULL AND receiving_account_id IS NULL
   AND EXISTS(SELECT 1 FROM sms_receipts s JOIN momo_receiving_accounts a ON a.id=? AND a.receiver_hash=s.receiver_hash WHERE s.id=momo_processing_jobs.raw_sms_id AND a.status='active')`).bind(rawId,accountId),gate[0],
   scoped.DB.prepare(`INSERT INTO momo_source_resolutions(id,raw_sms_id,receiving_account_id,source_body_sha256,reviewed_by,evidence_reference,reason,created_at)
   SELECT ?,s.id,?,s.body_sha256,?,?,?,? FROM sms_receipts s WHERE s.id=?`).bind(id(),accountId,actor.userId,evidence,reason,now(),rawId),
   scoped.DB.prepare(`UPDATE momo_processing_jobs SET receiving_account_id=?,mode='historical',state='pending',max_attempts=attempt_count+4,available_at=unixepoch(),last_error=?,updated_at=?
   WHERE raw_sms_id=? AND state='source_unresolved' AND attempt_count=0 AND last_error IS NULL AND binding_id IS NULL AND receiving_account_id IS NULL`).bind(accountId,MOMO_JOB_CHECKPOINT.reparse,now(),rawId),updated[0],updated[1],gate[1]);
  value={raw_sms_id:rawId,receiving_account_id:accountId,status:'pending',mode:'historical',financial_effects:0};
 }else if(area==='sources'&&parts.length===3&&parts[2]==='reparse'){keys(body,['reason']);const rawId=uuid(parts[1]),job=await first(scoped,'SELECT * FROM momo_processing_jobs WHERE raw_sms_id=?',rawId);if(!job||!job.receiving_account_id)fail(409,'source_unresolved','Resolve this historical receiving source before parsing.');
  if(momoOutcomeUnresolved(job))fail(409,'provider_outcome_unresolved','The previous extraction outcome must be reconciled before requesting another parse.');
  if(!['completed','needs_review'].includes(job.state))fail(409,'source_changed','Refresh the source before requesting another parse.');
  // Recheck the exact observed state inside the existing authorized mutation
  // batch so a concurrent unknown outcome cannot be overwritten by a reparse.
  const gate=momoGuard(scoped,'changes()=1');
  writes.push(scoped.DB.prepare(`UPDATE momo_processing_jobs SET state='pending',max_attempts=attempt_count+4,available_at=unixepoch(),lease_token=NULL,lease_until=NULL,last_error=?,updated_at=? WHERE raw_sms_id=? AND state=? AND attempt_count=? AND last_error IS ?`).bind(MOMO_JOB_CHECKPOINT.reparse,now(),rawId,job.state,job.attempt_count,job.last_error??null),gate[0],gate[1]);value={raw_sms_id:rawId,status:'pending'};
 }else fail(404,'not_found','This MoMo action is unavailable.');
 return json(await mutation(scoped,actor,operation,rid,source,value,writes,{...options,entityType:area==='sources'?'sms_receipt':area==='transactions'?'payment':'momo_account',entityId:value.id??value.binding_id??value.raw_sms_id,auditDetails:{reason}}));
}
