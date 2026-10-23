import {ApiError,json,readJson,first,rows,now,id,digest,stableJson,uuid,integer,text,requirePermission} from './core.js';
import {accountDatabase,adminAccountSession} from './admin_accounts.js';
import {mutation,retainedResponse} from './mutations.js';
import {encrypt,decrypt} from './encryption.js';
import {storageEntity} from '../storage-identity.js';
import {gatewayToken,momoGuard} from './momo_gateway.js';
import {validateProviderProfile,prepareMomoSourceReview} from './momo_pipeline.js';
import {receiptFactColumns,receiptFactJoins,withReceiptFacts} from './receipt_facts.js';
import {captureContent} from './admin_sms_receipts.js';

const enc=new TextEncoder(),dec=new TextDecoder(),fail=(s,c,m)=>{throw new ApiError(s,c,m);};
const keys=(body,allowed)=>{if(Object.keys(body).some(k=>!allowed.includes(k)))fail(400,'invalid_request','This action contains unsupported fields.');};
const exact=value=>{if(!Number.isSafeInteger(value))fail(503,'invalid_source_data','Transaction measurements are unavailable.');return value;};
const requestId=async(account,key)=>{if(typeof key!=='string'||!/^[a-zA-Z0-9_.-]{8,200}$/.test(key))fail(400,'idempotency_required','Supply an Idempotency-Key.');const sha=await digest(`collect-momo:${account.principal_id}:${key}`);return `${sha.slice(0,8)}-${sha.slice(8,12)}-4${sha.slice(13,16)}-8${sha.slice(17,20)}-${sha.slice(20,32)}`;};
const transactionSql=`SELECT t.*,${receiptFactColumns},a.public_code,a.recipient_name,l.payment_id,l.beneficiary_member_id,p.collection_id AS group_id,g.title AS group_name,u.full_name AS member_name,
 p.revision AS payment_version,p.intent_id,coalesce((SELECT sum(e.amount_minor) FROM ledger_entries e WHERE e.payment_id=p.id),0) AS credited_amount_minor,
 CASE WHEN p.status='reversed' THEN 'reversed' WHEN p.status IN('reconciled','confirmed') THEN 'credited'
 WHEN t.has_conflict=1 OR t.allocation_state='needs_review' THEN 'needs_review' WHEN l.payment_id IS NOT NULL THEN 'awaiting_review' ELSE 'needs_allocation' END AS status
 FROM momo_transactions t JOIN momo_receiving_accounts a ON a.id=t.receiving_account_id ${receiptFactJoins}
 LEFT JOIN momo_financial_links l ON l.transaction_id=t.id LEFT JOIN payments p ON p.id=l.payment_id
 LEFT JOIN collections g ON g.id=p.collection_id LEFT JOIN users u ON u.id=l.beneficiary_member_id`;
function query(url,allowed){for(const key of url.searchParams.keys())if(!allowed.includes(key)||url.searchParams.getAll(key).length!==1)fail(400,'invalid_filter','This MoMo filter is unavailable.');
 const offset=Number(url.searchParams.get('offset')??0),limit=Number(url.searchParams.get('limit')??25),search=url.searchParams.get('search')??'',status=url.searchParams.get('status')??'';
 if(!Number.isInteger(offset)||offset<0||offset>2147483647||!Number.isInteger(limit)||limit<1||limit>100||search.length>200||/[\x00-\x1f\x7f]/.test(search))fail(400,'invalid_filter','Choose a valid transaction filter.');
 return {offset,limit,search,status};}
function predicates(url,f){const where=[],args=[];
 if(f.search){where.push('(provider_transaction_id LIKE ? OR payer_name LIKE ?)');args.push('%'+f.search+'%','%'+f.search+'%');}
 if(f.status==='needs_attention')where.push("(status IN('needs_allocation','awaiting_review','needs_review') OR has_conflict=1)");
 else if(f.status){if(!['needs_allocation','awaiting_review','credited','reversed','needs_review'].includes(f.status))fail(400,'invalid_filter','Choose a supported payment state.');where.push(f.status==='needs_review'?'(status=? OR has_conflict=1)':'status=?');args.push(f.status);}
 for(const key of ['receiving_account_id','group_id'])if(url.searchParams.has(key)){where.push(`${key}=?`);args.push(uuid(url.searchParams.get(key),key));}
 for(const [key,op]of [['from','>='],['to','<=']])if(url.searchParams.has(key)){const value=url.searchParams.get(key);if(!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(value)||!Number.isFinite(Date.parse(value)))fail(400,'invalid_filter','Use an exact UTC transaction date.');where.push(`transaction_at ${op} ?`);args.push(value);}
 return {where:where.length?' WHERE '+where.join(' AND '):'',args};}
async function transactionPage(env,url){const f=query(url,['limit','offset','search','status','receiving_account_id','group_id','from','to']),filter=predicates(url,f),cte=`WITH records AS (${transactionSql})`;
 const result=await env.DB.batch([env.DB.prepare(`${cte} SELECT count(*) AS total,coalesce(sum(amount_minor),0) AS received,coalesce(sum(credited_amount_minor),0) AS credited,
 coalesce(sum(CASE WHEN credited_amount_minor=0 AND status!='reversed' THEN amount_minor ELSE 0 END),0) AS unallocated FROM records${filter.where}`).bind(...filter.args),
 env.DB.prepare(`${cte} SELECT * FROM records${filter.where} ORDER BY coalesce(transaction_at,created_at) DESC,id LIMIT ? OFFSET ?`).bind(...filter.args,f.limit,f.offset)]);
 const total=result[0].results[0];return {contract_version:1,rows:result[1].results.map(withReceiptFacts),total:exact(total.total),limit:f.limit,offset:f.offset,
 totals:{received_minor:exact(total.received),credited_minor:exact(total.credited),unallocated_minor:exact(total.unallocated)},currency:'RWF',date_basis:'provider_transaction_time',as_of:now()};}
async function paymentChecks(env,url){
 const f=query(url,['limit','offset']),cte=`WITH typed AS (
  SELECT r.*,CASE WHEN json_valid(r.message) THEN r.message ELSE '{}' END AS context FROM support_requests r WHERE r.kind='payment_review'
 ),checked AS (
  SELECT r.id,r.user_id AS member_id,u.public_id AS member_public_id,u.full_name AS member_name,r.collection_id AS group_id,g.title AS group_name,
   i.id AS intent_id,i.amount_minor AS expected_amount_minor,i.currency,r.created_at AS requested_at,r.status AS request_status,
   json_extract(r.context,'$.provider_reference') AS provider_reference,json_extract(r.context,'$.evidence_note') AS evidence_note
  FROM typed r JOIN payment_intents i ON i.id=json_extract(r.context,'$.intent_id') AND i.member_id=r.user_id AND i.collection_id=r.collection_id
   JOIN users u ON u.id=r.user_id JOIN collections g ON g.id=r.collection_id
  WHERE json_type(r.context,'$.contract_version')='integer' AND json_extract(r.context,'$.contract_version')=1
   AND json_type(r.context,'$.intent_id')='text' AND json_type(r.context,'$.collection_id')='text'
   AND json_extract(r.context,'$.collection_id')=r.collection_id
   AND json_type(r.context,'$.provider_reference') IN('null','text') AND coalesce(length(json_extract(r.context,'$.provider_reference')),0)<=160
   AND json_type(r.context,'$.evidence_note') IN('null','text') AND coalesce(length(json_extract(r.context,'$.evidence_note')),0)<=2000
   AND (SELECT count(*) FROM json_each(r.context))=5
   AND NOT EXISTS(SELECT 1 FROM json_each(r.context) WHERE key NOT IN('contract_version','intent_id','collection_id','provider_reference','evidence_note'))
 )`;
 const result=await env.DB.batch([env.DB.prepare(`${cte} SELECT count(*) AS total FROM checked`),
  env.DB.prepare(`${cte} SELECT * FROM checked ORDER BY requested_at DESC,id DESC LIMIT ? OFFSET ?`).bind(f.limit,f.offset)]),total=exact(result[0].results[0].total);
 return {contract_version:1,rows:result[1].results.map(row=>({...row,expected_amount_minor:exact(row.expected_amount_minor),source:'member_request',provider_reference_verified:false,financial_effects:0})),total,limit:f.limit,offset:f.offset,next_offset:f.offset+result[1].results.length<total?f.offset+result[1].results.length:null};
}
async function rawPayload(env,rawId){
 // accountDatabase validates current permission/MFA in batch. A standalone
 // prepare().first() would defer that check until AFTER decrypting the object.
 const [result]=await env.DB.batch([env.DB.prepare('SELECT * FROM sms_receipts WHERE id=?').bind(rawId)]),raw=result.results[0];if(!raw)fail(404,'source_unavailable','This retained source is unavailable.');
 const object=await env.PRIVATE_MEDIA.get(raw.object_key);if(!object)fail(503,'source_unavailable','Retained source storage is unavailable.');
 const bytes=await decrypt(env,await object.text(),`sms:${raw.id}:${raw.object_sha256}`);if(bytes.length!==raw.size_bytes||await digest(bytes)!==raw.object_sha256)fail(503,'source_integrity_failed','The retained source could not be verified.');return {raw,payload:JSON.parse(dec.decode(bytes))};}
async function assign(env,actor,txId,body,rid,source){
 keys(body,['group_id','member_id','intent_id','expected_version','reason']);const options={permission:'payments.write',minimumAssurance:2,freshSeconds:300};
 const prior=await retainedResponse(env,actor,'momo.assign',rid,source,options);if(prior.found)return prior.value;
 const tx=await first(env,'SELECT * FROM momo_transactions WHERE id=?',txId);if(!tx)fail(404,'not_found','This payment was not found.');
 if(tx.version!==integer(body.expected_version,'expected_version',1)||tx.has_conflict||tx.event_kind!=='incoming_receipt'||tx.allocation_state!=='unallocated')fail(409,'payment_changed','Review the current payment before assigning it.');
 const groupId=uuid(body.group_id,'group_id'),memberId=uuid(body.member_id,'member_id'),reason=text(body.reason,'reason',500);if(reason.length<8)fail(400,'reason_required','Record the evidence supporting this destination.');
 const destination=await first(env,`SELECT g.*,m.revision AS membership_revision,u.revision AS member_revision,u.full_name AS member_name
 FROM collections g JOIN memberships m ON m.collection_id=g.id JOIN users u ON u.id=m.user_id
 WHERE g.id=? AND u.id=? AND g.status='active' AND m.active=1 AND u.access_status='active'`,groupId,memberId);
 if(!destination)fail(409,'destination_unavailable','Choose an active member of this group.');
 const account=await first(env,'SELECT * FROM momo_receiving_accounts WHERE id=?',tx.receiving_account_id);
 const route=value=>/^07[2389]\d{7}$/.test(value??'')?'250'+value.slice(1):(value??'').replace(/^\+/,'');
 if(account.provider!==destination.receiver_network||route(account.public_code)!==route(destination.receiver_momo_number))fail(409,'receiver_mismatch','This group uses a different receiving account. Review the verified payment destination before attribution.');
 const intentId=body.intent_id==null?null:uuid(body.intent_id,'intent_id');
 if(intentId&&!await first(env,`SELECT id FROM payment_intents WHERE id=? AND member_id=? AND collection_id=? AND amount_minor=? AND currency='RWF' AND status IN('pending','expired')`,intentId,memberId,groupId,tx.amount_minor))fail(409,'intent_unavailable','This intent does not match the verified destination and amount.');
 // Historical/operator records can predate this pipeline. Link exact retained
 // evidence first; never treat absence from the new table as proof of no credit.
 const existing=await rows(env,`SELECT p.* FROM payments p JOIN payment_evidence e ON e.id=p.evidence_id
 WHERE e.external_reference IN(?,?) AND e.receiver_network=? AND (CASE WHEN e.receiver_momo_number GLOB '07*' AND length(e.receiver_momo_number)=10 THEN '250'||substr(e.receiver_momo_number,2) ELSE replace(e.receiver_momo_number,'+','') END)=(SELECT CASE WHEN route GLOB '07*' AND length(route)=10 THEN '250'||substr(route,2) ELSE replace(route,'+','') END FROM (SELECT ? AS route))`,tx.provider_transaction_id,`${account.id}:${tx.provider_transaction_id}`,account.provider,account.public_code);
 if(existing.length>1||existing.some(p=>p.amount_minor!==tx.amount_minor||p.collection_id!==groupId||(p.member_id!==null&&p.member_id!==memberId)))fail(409,'historical_overlap_conflict','Existing financial evidence needs reconciliation before another record can be linked.');
 if(tx.mode==='historical'&&!existing.length)fail(409,'historical_reconciliation_required','Reconcile historical evidence before enabling a new historical contribution.');
 const paymentId=existing[0]?.id??await storageEntity('momo.assign.payment',actor.userId,rid),evidenceId=await storageEntity('momo.assign.evidence',actor.userId,rid),key='evidence/'+evidenceId;
 const sourceRow=await first(env,`SELECT raw_sms_id FROM momo_transaction_sources WHERE transaction_id=? AND relation='accepted' ORDER BY created_at LIMIT 1`,tx.id);if(!sourceRow)fail(409,'source_unavailable','Review the original source first.');
 const {payload}=await rawPayload(env,sourceRow.raw_sms_id);let bytes,sha;
 if(!existing.length){bytes=enc.encode(payload.raw_body);sha=await digest(bytes);await env.PRIVATE_MEDIA.put(key,await encrypt(env,bytes,`evidence:${evidenceId}:${sha}`),{scope:{ownerId:actor.userId,purpose:'payment_evidence',entityId:evidenceId},aad:`evidence:${evidenceId}:${sha}`,sourceDigest:await digest(stableJson(source)),httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:sha,key_id:env.DATA_KEY_ID}});}
 const gate=momoGuard(env,`EXISTS(SELECT 1 FROM momo_transactions WHERE id=? AND version=? AND has_conflict=0 AND allocation_state='unallocated')
 AND EXISTS(SELECT 1 FROM collections g JOIN memberships m ON m.collection_id=g.id JOIN users u ON u.id=m.user_id
 WHERE g.id=? AND g.revision=? AND g.status='active' AND u.id=? AND u.revision=? AND u.access_status='active' AND m.active=1 AND m.revision=?)`,[tx.id,tx.version,groupId,destination.revision,memberId,destination.member_revision,destination.membership_revision]);
 const overlapGate=momoGuard(env,existing.length?`EXISTS(SELECT 1 FROM payments p JOIN payment_evidence e ON e.id=p.evidence_id
  WHERE p.id=? AND p.amount_minor=? AND p.collection_id=? AND (p.member_id IS NULL OR p.member_id=?) AND e.external_reference IN(?,?) AND e.receiver_network=? AND (CASE WHEN e.receiver_momo_number GLOB '07*' AND length(e.receiver_momo_number)=10 THEN '250'||substr(e.receiver_momo_number,2) ELSE replace(e.receiver_momo_number,'+','') END)=(SELECT CASE WHEN route GLOB '07*' AND length(route)=10 THEN '250'||substr(route,2) ELSE replace(route,'+','') END FROM (SELECT ? AS route)))`:
  `NOT EXISTS(SELECT 1 FROM payments p JOIN payment_evidence e ON e.id=p.evidence_id
  WHERE e.external_reference IN(?,?) AND e.receiver_network=? AND (CASE WHEN e.receiver_momo_number GLOB '07*' AND length(e.receiver_momo_number)=10 THEN '250'||substr(e.receiver_momo_number,2) ELSE replace(e.receiver_momo_number,'+','') END)=(SELECT CASE WHEN route GLOB '07*' AND length(route)=10 THEN '250'||substr(route,2) ELSE replace(route,'+','') END FROM (SELECT ? AS route)))`,
  existing.length?[paymentId,tx.amount_minor,groupId,memberId,tx.provider_transaction_id,`${account.id}:${tx.provider_transaction_id}`,account.provider,account.public_code]:[tx.provider_transaction_id,`${account.id}:${tx.provider_transaction_id}`,account.provider,account.public_code]);
 const writes=[gate[0],overlapGate[0],overlapGate[1]];
 if(intentId){const intentGate=momoGuard(env,`EXISTS(SELECT 1 FROM payment_intents WHERE id=? AND member_id=? AND collection_id=? AND amount_minor=? AND status IN('pending','expired'))`,[intentId,memberId,groupId,tx.amount_minor]);writes.push(intentGate[0],intentGate[1]);}
 if(!existing.length)writes.push(env.DB.prepare(`INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,receiver_momo_number,amount_minor,observed_at,created_at,receiver_network,receiver_display_label) VALUES(?,?,?,?,?,?,'text/plain','operator_recorded',?,?,?,?,?,?,?)`).bind(evidenceId,groupId,actor.userId,key,sha,bytes.length,`${account.id}:${tx.provider_transaction_id}`,destination.receiver_momo_number,tx.amount_minor,tx.transaction_at??tx.created_at,now(),destination.receiver_network,destination.receiver_display_label),
 env.DB.prepare(`INSERT INTO payments(id,collection_id,evidence_id,intent_id,amount_minor,status,payer_display_name,created_at) VALUES(?,?,?,?,?,'recorded',?,?)`).bind(paymentId,groupId,evidenceId,intentId,tx.amount_minor,tx.payer_name??'',now()));
 else if(intentId&&existing[0].intent_id!==intentId)fail(409,'historical_intent_conflict','An existing payment cannot be silently reassigned to a new intent.');
 writes.push(env.DB.prepare('INSERT INTO momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,historical_existing,created_at) VALUES(?,?,?,?,?,?,?)').bind(tx.id,paymentId,memberId,actor.userId,reason,Number(existing.length>0),now()),
 env.DB.prepare(`UPDATE momo_transactions SET allocation_state='linked',version=version+1,updated_at=? WHERE id=?`).bind(now(),tx.id),gate[1]);
 const value={transaction_id:tx.id,payment_id:paymentId,status:existing.length&&existing[0].member_id?'linked_existing':'awaiting_review',version:tx.version+1,requires_independent_review:!existing.length||!existing[0].member_id};
 try{return await mutation(env,actor,'momo.assign',rid,source,value,writes,{...options,entityType:'payment',entityId:paymentId,auditDetails:{momo_transaction_id:tx.id,reason}});}
 catch(error){throw error;}
}
async function reviewConflict(env,actor,txId,body,rid,source){
 keys(body,['expected_version','expected_conflicting_attempt_ids','decision','evidence_reference','reason']);
 if(body.decision!=='retain_original'||!Array.isArray(body.expected_conflicting_attempt_ids)||body.expected_conflicting_attempt_ids.length<1||body.expected_conflicting_attempt_ids.length>100)
  fail(400,'invalid_conflict_review','Review the exact bounded conflict set and retain the original immutable facts.');
 const expected=[...new Set(body.expected_conflicting_attempt_ids.map(value=>uuid(value,'parse attempt')))].sort();
 if(expected.length!==body.expected_conflicting_attempt_ids.length)fail(400,'invalid_conflict_review','Each conflicting attempt must be named once.');
 const version=integer(body.expected_version,'expected_version',1),evidence=text(body.evidence_reference,'supporting evidence',500);
 if(evidence.length<8)fail(400,'evidence_required','Record supporting evidence for the conflict decision.');
 const options={permission:'payments.write',minimumAssurance:2,freshSeconds:300},operation='momo.conflict.reviewed';
 const prior=await retainedResponse(env,actor,operation,rid,source,options);if(prior.found)return prior.value;
 const tx=await first(env,'SELECT * FROM momo_transactions WHERE id=?',txId),conflicts=await rows(env,"SELECT DISTINCT parse_attempt_id FROM momo_transaction_sources WHERE transaction_id=? AND relation='conflict' ORDER BY parse_attempt_id LIMIT 101",txId);
 if(!tx||tx.version!==version||!tx.has_conflict||tx.allocation_state!=='needs_review'||stableJson(conflicts.map(row=>row.parse_attempt_id))!==stableJson(expected)||
  await first(env,'SELECT 1 AS found FROM momo_financial_links WHERE transaction_id=?',txId))fail(409,'conflict_changed','Refresh the unlinked payment and its complete conflict set.');
 const slots=expected.map(()=>'?').join(','),guard=momoGuard(env,`EXISTS(SELECT 1 FROM momo_transactions WHERE id=? AND version=? AND has_conflict=1 AND allocation_state='needs_review')
  AND NOT EXISTS(SELECT 1 FROM momo_financial_links WHERE transaction_id=?)
  AND (SELECT count(DISTINCT parse_attempt_id) FROM momo_transaction_sources WHERE transaction_id=? AND relation='conflict')=?
  AND NOT EXISTS(SELECT 1 FROM momo_transaction_sources WHERE transaction_id=? AND relation='conflict' AND parse_attempt_id NOT IN(${slots}))`,[txId,version,txId,txId,expected.length,txId,...expected]);
 const value={transaction_id:txId,version:version+1,status:'needs_allocation',financial_effects:0};
 return mutation(env,actor,operation,rid,source,value,[guard[0],
  env.DB.prepare("UPDATE momo_transactions SET has_conflict=0,allocation_state='unallocated',version=version+1,updated_at=? WHERE id=?").bind(now(),txId),
  env.DB.prepare(`UPDATE momo_processing_jobs SET state='completed',last_error=NULL,updated_at=? WHERE state='needs_review' AND raw_sms_id IN
   (SELECT raw_sms_id FROM momo_transaction_sources WHERE transaction_id=? AND relation='conflict' AND parse_attempt_id IN(${slots}))
   AND (SELECT id FROM momo_parse_attempts a WHERE a.raw_sms_id=momo_processing_jobs.raw_sms_id ORDER BY attempt_number DESC LIMIT 1) IN(${slots})`).bind(now(),txId,...expected,...expected),guard[1]],
  {...options,entityType:'payment',entityId:txId,auditDetails:{decision:'retain_original',reason:body.reason,evidence_reference:evidence,dismissed_parse_attempt_ids:expected}});
}
export async function adminMomoRoute(request,env,account,actor,parts,url){
 const area=parts[0];if(!['accounts','bindings','transactions','sources'].includes(area))fail(404,'not_found','This MoMo view does not exist.');
 const readPermission=['accounts','bindings'].includes(area)?'receivers.read':area==='sources'?'sms.read':'payments.read';requirePermission(actor,readPermission);
 if(request.method==='GET'){
  const scoped=accountDatabase(env,account,readPermission);
  if(area==='accounts'&&parts.length===1){query(url,[]);const result=await scoped.DB.batch([scoped.DB.prepare('SELECT id,provider,public_code,recipient_name,currency,timezone,status,profile_status,profile_version,created_at FROM momo_receiving_accounts ORDER BY created_at DESC,id')]);return json({rows:result[0].results});}
  if(area==='bindings'&&parts.length===1){query(url,[]);const result=await scoped.DB.batch([scoped.DB.prepare(`SELECT b.*,c.last_contact_at,c.last_sms_at,c.pending_count,c.oldest_pending_at FROM momo_gateway_bindings b LEFT JOIN momo_gateway_credentials c ON c.binding_id=b.id ORDER BY b.created_at DESC,b.id LIMIT 100`)]);return json({rows:result[0].results});}
  if(area==='transactions'&&parts.length===1)return json(await transactionPage(scoped,url));
  if(area==='transactions'&&parts.length===2&&parts[1]==='payment-checks'){
   requirePermission(actor,'users.read');requirePermission(actor,'collections.read');
   return json(await paymentChecks(accountDatabase(accountDatabase(scoped,account,'users.read'),account,'collections.read'),url));
  }
  if(area==='transactions'&&parts.length===3&&parts[2]==='candidates'){
   requirePermission(actor,'users.read');requirePermission(actor,'collections.read');
   const f=query(url,['limit','offset','search']),txId=uuid(parts[1]),lookup=accountDatabase(accountDatabase(scoped,account,'users.read'),account,'collections.read');
   const condition=`t.id=? AND t.has_conflict=0 AND t.allocation_state='unallocated' AND g.status='active' AND m.active=1 AND u.access_status='active' AND u.member_type!='operator'
    AND g.receiver_network=a.provider AND
    (CASE WHEN g.receiver_momo_number GLOB '07*' AND length(g.receiver_momo_number)=10 THEN '250'||substr(g.receiver_momo_number,2) ELSE replace(g.receiver_momo_number,'+','') END)=
    (CASE WHEN a.public_code GLOB '07*' AND length(a.public_code)=10 THEN '250'||substr(a.public_code,2) ELSE replace(a.public_code,'+','') END)
    AND (?='' OR instr(lower(u.full_name),lower(?))>0 OR instr(u.public_id,?)>0)`,args=[txId,f.search,f.search,f.search],from=`FROM momo_transactions t JOIN momo_receiving_accounts a ON a.id=t.receiving_account_id
    JOIN collections g JOIN memberships m ON m.collection_id=g.id JOIN users u ON u.id=m.user_id WHERE ${condition}`;
   const result=await lookup.DB.batch([lookup.DB.prepare(`SELECT count(*) AS n ${from}`).bind(...args),lookup.DB.prepare(`SELECT g.id AS group_id,g.title AS group_name,u.id AS member_id,u.full_name AS member_name,u.public_id AS member_public_id ${from} ORDER BY u.full_name,g.title,u.id,g.id LIMIT ? OFFSET ?`).bind(...args,f.limit,f.offset)]);
   return json({rows:result[1].results,total:exact(result[0].results[0].n),limit:f.limit,offset:f.offset});}
  if(area==='transactions'&&parts.length===2){query(url,[]);const txId=uuid(parts[1]),result=await scoped.DB.batch([scoped.DB.prepare(`SELECT * FROM (${transactionSql}) WHERE id=?`).bind(txId),scoped.DB.prepare(`SELECT s.raw_sms_id,s.relation,s.created_at,a.id AS attempt_id,a.outcome,a.model_id,a.schema_version,a.parser_version,a.validation_json FROM momo_transaction_sources s JOIN momo_parse_attempts a ON a.id=s.parse_attempt_id WHERE s.transaction_id=? ORDER BY a.created_at DESC LIMIT 100`).bind(txId),scoped.DB.prepare("SELECT DISTINCT parse_attempt_id FROM momo_transaction_sources WHERE transaction_id=? AND relation='conflict' ORDER BY parse_attempt_id LIMIT 101").bind(txId),scoped.DB.prepare("SELECT actor_user_id,details_json,created_at FROM audit_log WHERE action='momo.conflict.reviewed' AND entity_id=? ORDER BY id DESC LIMIT 25").bind(txId)]);if(!result[0].results.length)fail(404,'not_found','This transaction is unavailable.');return json({transaction:withReceiptFacts(result[0].results[0]),sources:result[1].results,conflicting_attempt_ids:result[2].results.map(row=>row.parse_attempt_id),conflict_reviews:result[3].results});}
  if(area==='sources'&&parts.length===1){const f=query(url,['limit','offset','status']);if(f.status&&!['pending','processing','retry','completed','needs_review','source_unresolved'].includes(f.status))fail(400,'invalid_filter','Choose a valid processing state.');
   const condition=f.status?' WHERE j.state=?':'',args=f.status?[f.status]:[],result=await scoped.DB.batch([scoped.DB.prepare(`SELECT count(*) AS total FROM momo_processing_jobs j${condition}`).bind(...args),scoped.DB.prepare(`SELECT j.*,s.body_sha256,s.received_at_device,s.created_at AS received_at,
    (SELECT id FROM momo_parse_attempts a WHERE a.raw_sms_id=j.raw_sms_id ORDER BY attempt_number DESC LIMIT 1) AS latest_attempt_id,
    (SELECT outcome FROM momo_parse_attempts a WHERE a.raw_sms_id=j.raw_sms_id ORDER BY attempt_number DESC LIMIT 1) AS latest_attempt_outcome
    FROM momo_processing_jobs j JOIN sms_receipts s ON s.id=j.raw_sms_id${condition} ORDER BY j.created_at DESC,j.raw_sms_id LIMIT ? OFFSET ?`).bind(...args,f.limit,f.offset)]);return json({rows:result[1].results,total:result[0].results[0].total,limit:f.limit,offset:f.offset});}
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
 if(area==='transactions'&&parts.length===3&&parts[2]==='assign')return json(await assign(scoped,actor,uuid(parts[1]),body,rid,source));
 if(area==='transactions'&&parts.length===3&&parts[2]==='review-conflict'){
  requirePermission(actor,'sms.extract');const reviewed=accountDatabase(accountDatabase(scoped,account,'payments.read'),account,'sms.extract',{mfa:true,fresh:true});
  return json(await reviewConflict(reviewed,actor,uuid(parts[1]),body,rid,source));
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
  const selected=await rows(scoped,`SELECT s.id FROM sms_receipts s WHERE s.created_at<=? AND s.id>? AND NOT EXISTS(SELECT 1 FROM momo_processing_jobs j WHERE j.raw_sms_id=s.id) ORDER BY s.id LIMIT ?`,asOf,after,limit+1),page=selected.slice(0,limit);
  for(const raw of page)writes.push(scoped.DB.prepare(`INSERT INTO momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,available_at,created_at,updated_at)
   VALUES(?,NULL,NULL,NULL,'historical','source_unresolved',unixepoch(),?,?) ON CONFLICT(raw_sms_id) DO NOTHING`).bind(raw.id,now(),now()));
  value={inventoried:page.length,next_cursor:selected.length>limit?{as_of:asOf,after_id:page.at(-1).id}:null,status:'source_review_required',financial_effects:0};
 }else if(area==='sources'&&parts.length===3&&parts[2]==='resolve'){
  keys(body,['reason','receiving_account_id','evidence_reference']);const rawId=uuid(parts[1]),accountId=uuid(body.receiving_account_id),evidence=text(body.evidence_reference,'historical evidence reference',500);
  if(evidence.length<8)fail(400,'evidence_required','Reference the evidence establishing the historical receiving account.');
  const gate=momoGuard(scoped,`EXISTS(SELECT 1 FROM momo_processing_jobs j JOIN sms_receipts s ON s.id=j.raw_sms_id
   JOIN momo_receiving_accounts a ON a.id=? AND a.receiver_hash=s.receiver_hash WHERE j.raw_sms_id=? AND j.state='source_unresolved' AND j.binding_id IS NULL AND j.receiving_account_id IS NULL AND a.status='active')`,[accountId,rawId]);
  writes.push(gate[0],scoped.DB.prepare(`INSERT INTO momo_source_resolutions(id,raw_sms_id,receiving_account_id,source_body_sha256,reviewed_by,evidence_reference,reason,created_at)
   SELECT ?,s.id,?,s.body_sha256,?,?,?,? FROM sms_receipts s WHERE s.id=?`).bind(id(),accountId,actor.userId,evidence,reason,now(),rawId),
   scoped.DB.prepare(`UPDATE momo_processing_jobs SET receiving_account_id=?,mode='historical',state='pending',max_attempts=attempt_count+4,available_at=unixepoch(),last_error=NULL,updated_at=? WHERE raw_sms_id=?`).bind(accountId,now(),rawId),gate[1]);
  value={raw_sms_id:rawId,receiving_account_id:accountId,status:'pending',mode:'historical',financial_effects:0};
 }else if(area==='sources'&&parts.length===3&&parts[2]==='reparse'){keys(body,['reason']);const rawId=uuid(parts[1]),job=await first(scoped,'SELECT * FROM momo_processing_jobs WHERE raw_sms_id=?',rawId);if(!job||!job.receiving_account_id)fail(409,'source_unresolved','Resolve this historical receiving source before parsing.');
  const gate=momoGuard(scoped,`EXISTS(SELECT 1 FROM momo_processing_jobs WHERE raw_sms_id=? AND state NOT IN('processing','pending','retry'))`,[rawId]);
  writes.push(gate[0],scoped.DB.prepare(`UPDATE momo_processing_jobs SET state='pending',max_attempts=attempt_count+4,available_at=unixepoch(),lease_token=NULL,lease_until=NULL,last_error=NULL,updated_at=? WHERE raw_sms_id=?`).bind(now(),rawId),gate[1]);value={raw_sms_id:rawId,status:'pending'};
 }else fail(404,'not_found','This MoMo action is unavailable.');
 return json(await mutation(scoped,actor,operation,rid,source,value,writes,{...options,entityType:area==='sources'?'sms_receipt':area==='transactions'?'payment':'momo_account',entityId:value.id??value.binding_id??value.raw_sms_id,auditDetails:{reason}}));
}
