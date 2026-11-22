import {retentionColumns} from './columns.js';

// These source selectors are shared with the offline manifest compiler.
const userFields=new Set(['user_id','owner_user_id','actor_user_id','member_id','proposed_member_id','proposed_by','recipient_user_id','observer_user_id','approved_by','created_by','creator_user_id','updated_by','actor_id','claim_actor','outcome_actor']);
const sessionFields=new Set(['session_id','originating_session_id','owner_session_id','auth_session_id','enrollment_session_id','proposed_session_id','observer_session_id']);
// Receipt metadata is also a copy when the actor is a different administrator.
// Keep these exact known relations; a decision head is never an erasable cache.
const relatedSmsRequests=`SELECT r.request_id FROM request_receipts r WHERE
 r.request_id IN(SELECT request_id FROM assisted_sms_claims WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=?))
 OR r.request_id IN(SELECT request_id FROM assisted_sms_confirmations WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=?))
 OR r.request_id IN(SELECT request_id FROM assisted_sms_send_starts WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=?))
 OR r.request_id IN(SELECT request_id FROM assisted_sms_outcomes WHERE attempt_id IN(SELECT s.id FROM assisted_sms_send_starts s JOIN assisted_sms_jobs j ON j.id=s.job_id WHERE j.recipient_user_id=?))
 OR r.operation='assisted_sms.enqueue' AND json_extract(r.response_json,'$.job_id') IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=?)
 OR r.operation='assisted_sms.materialize.plan' AND EXISTS(SELECT 1 FROM json_each(CASE WHEN r.operation='assisted_sms.materialize.plan' THEN r.response_json ELSE '{}' END,'$.sources') source WHERE json_extract(source.value,'$.entry_id') IN(SELECT id FROM ledger_entries WHERE member_id=?))
 OR r.operation IN('assisted_sms.materialize.intent','assisted_sms.materialize.blocked') AND json_extract(r.response_json,'$.source_entry_id') IN(SELECT id FROM ledger_entries WHERE member_id=?)
 OR r.operation='assisted_sms.policy.configure' AND json_extract(r.response_json,'$.collection_id') IN(SELECT collection_id FROM memberships WHERE user_id=? UNION SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=?)`;

// These are observed financial/source relationships. A masked payer suffix or
// name is never enough to claim personal ownership of another receipt.
function momoRelations(subject,columns){
 const financial=Object.hasOwn(columns,'momo_financial_links');
 const transactionSql=`SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=?)${financial?` OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=? OR f.linked_by=? OR p.member_id=?))`:''}`;
 const transactionArgs=Array(financial?4:1).fill(subject);
 const rawSql=`SELECT raw.id FROM sms_receipts raw WHERE raw.owner_user_id=? OR EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=raw.id AND s.transaction_id IN(${transactionSql}))`;
 return {transactionSql,transactionArgs,rawSql,rawArgs:[subject,...transactionArgs]};
}

export function retentionSelection(table,subject,catalog=retentionColumns){
 const columns=catalog[table],parts=[],args=[];
 const add=(query,...values)=>{parts.push(query);args.push(...values);};
 // The report schema has no subject/session/device mapping. Do not fabricate
 // personal ownership from the random report UUID or release-level fingerprint.
 // Global expiry is a separate maintenance observation, not account erasure.
 // External/unmapped-identifier classes remain required and unverified.
 if(table==='client_diagnostic_reports')return {sql:'0=1',args:[]};
 if(table==='admin_email_otp_challenges')add('principal_user_id=? OR user_id IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=?)',subject,subject);
 if(table==='auth_google_flows')add('google_subject IN(SELECT subject FROM auth_google_identities WHERE user_id=?) OR email IN(SELECT lower(email) FROM users WHERE id=?)',subject,subject);
 if(Object.hasOwn(catalog,'momo_processing_jobs')){
  const r=momoRelations(subject,catalog),bindings=`SELECT id FROM momo_gateway_bindings WHERE owner_user_id=? OR receiving_account_id IN(SELECT receiving_account_id FROM momo_transactions WHERE id IN(${r.transactionSql}))`,bindingArgs=[subject,...r.transactionArgs];
  if(table==='sms_receipts')add(`id IN(${r.rawSql})`,...r.rawArgs);
  if(['momo_transactions','momo_transaction_sources','momo_financial_links'].includes(table))add(`${table==='momo_transactions'?'id':'transaction_id'} IN(${r.transactionSql})`,...r.transactionArgs);
  if(['momo_processing_jobs','momo_parse_attempts','momo_transaction_sources','momo_gateway_captures','momo_source_resolutions'].includes(table))add(`raw_sms_id IN(${r.rawSql})`,...r.rawArgs);
  if(table==='momo_source_resolutions')add('reviewed_by=?',subject);
  if(table==='momo_gateway_bindings')add(`id IN(${bindings})`,...bindingArgs);
  if(['momo_gateway_credentials','momo_gateway_pairings'].includes(table))add(`binding_id IN(${bindings})`,...bindingArgs);
  if(table==='momo_receiving_accounts')add(`id IN(SELECT receiving_account_id FROM momo_gateway_bindings WHERE id IN(${bindings})) OR id IN(SELECT receiving_account_id FROM momo_transactions WHERE id IN(${r.transactionSql}))`,...bindingArgs,...r.transactionArgs);
  if(table==='momo_financial_links')add('beneficiary_member_id=? OR linked_by=?',subject,subject);
  if(Object.hasOwn(catalog,'momo_financial_links')){
   const linkedPayments=`SELECT payment_id FROM momo_financial_links WHERE transaction_id IN(${r.transactionSql})`;
   if(table==='payments')add(`id IN(${linkedPayments})`,...r.transactionArgs);
   if(['ledger_entries','contribution_posting_snapshots'].includes(table))add(`payment_id IN(${linkedPayments})`,...r.transactionArgs);
   if(table==='payment_evidence')add(`id IN(SELECT evidence_id FROM payments WHERE id IN(${linkedPayments}))`,...r.transactionArgs);
   if(table==='collections')add(`id IN(SELECT collection_id FROM payments WHERE id IN(${linkedPayments}))`,...r.transactionArgs);
  }
  if(table==='momo_processing_guards')return {sql:'1=1',args:[]};
  if(['request_receipts','audit_log'].includes(table))add(`request_id IN(SELECT request_id FROM request_receipts WHERE operation='momo.assign' AND json_extract(response_json,'$.transaction_id') IN(${r.transactionSql}))`,...r.transactionArgs);
  if(table==='request_receipts')add(`json_extract(response_json,'$.raw_sms_id') IN(${r.rawSql}) OR json_extract(response_json,'$.transaction_id') IN(${r.transactionSql})`,...r.rawArgs,...r.transactionArgs);
  if(table==='audit_log')add(`entity_id IN(${r.rawSql}) OR entity_id IN(${r.transactionSql})`,...r.rawArgs,...r.transactionArgs);
 }
 if(table==='users')add('id=?',subject);
 if(table==='collections')add('id IN(SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=? UNION SELECT collection_id FROM assisted_sms_jobs WHERE recipient_user_id=?)',subject,subject);
 // Diagnostic principal quota hashes are still reidentifiable for a known
 // subject. The existing full rate-table inventory deliberately retains them
 // (including their expiry); TTL does not grant this engine deletion authority.
 if(['runtime_config','admin_account_role_capabilities','auth_rate_buckets','admin_rate_limits','notification_email_job_dispatches'].includes(table))return {sql:'1=1',args:[]};
 if(['request_receipts','audit_log'].includes(table))add('request_id IN('+relatedSmsRequests+')',...Array(9).fill(subject));
 if(table.startsWith('assisted_sms_')){
  if(columns.includes('job_id'))add('job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=?)',subject);
  if(['assisted_sms_outcomes','assisted_sms_dispatches'].includes(table))add('attempt_id IN(SELECT s.id FROM assisted_sms_send_starts s JOIN assisted_sms_jobs j ON j.id=s.job_id WHERE j.recipient_user_id=?)',subject);
  if(columns.includes('collection_id'))add('collection_id IN(SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=? UNION SELECT collection_id FROM assisted_sms_jobs WHERE recipient_user_id=?)',subject,subject);
 }
 for(const column of columns){
  if(userFields.has(column))add('"'+column+'"=?',subject);
  if(sessionFields.has(column))add('"'+column+'" IN(SELECT id FROM auth_sessions WHERE user_id=?)',subject);
  if(['admin_user_id','actor_admin_id','observer_admin_id'].includes(column)||table==='admin_users'&&column==='id'||['admin_sessions','admin_challenges','admin_email_events','admin_role_assignments'].includes(table)&&column==='user_id')add('"'+column+'" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=?)',subject);
  if(column==='collection_id')add('collection_id IN(SELECT collection_id FROM memberships WHERE user_id=? UNION SELECT id FROM collections WHERE creator_user_id=?)',subject,subject);
  if(column==='request_id'&&(table.startsWith('privacy_')||table==='deletion_reviews'))add('request_id IN(SELECT id FROM deletion_requests WHERE user_id=?)',subject);
  if(column==='request_id'&&table==='auth_identity_rate_aliases')add('request_id IN(SELECT id FROM auth_otp_challenges WHERE identity_value IN(SELECT phone FROM users WHERE id=? UNION SELECT email FROM users WHERE id=?))',subject,subject);
  if(['import_id','source_import_id'].includes(column))add('"'+column+'" IN(SELECT id FROM roster_imports WHERE user_id=? UNION SELECT source_import_id FROM roster_members WHERE linked_user_id=?)',subject,subject);
  if(column==='subject_id')add('subject_id=? OR subject_id IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=?)',subject,subject);
  if(column==='reservation_id')add('reservation_id IN(SELECT id FROM native_reservations WHERE user_id=?)',subject);
  if(column==='processing_id')add('processing_id IN(SELECT id FROM roster_processing_records WHERE actor_user_id=?)',subject);
  if(column==='reconciliation_id')add('reconciliation_id IN(SELECT id FROM reconciliations WHERE proposed_member_id=? OR proposed_by=? OR approved_by=?)',subject,subject,subject);
  if(column==='linked_user_id')add('linked_user_id=?',subject);
  if(column==='payment_id')add('payment_id IN(SELECT id FROM payments WHERE member_id=?)',subject);
  if(column==='evidence_id')add('evidence_id IN(SELECT evidence_id FROM payments WHERE member_id=? UNION SELECT id FROM payment_evidence WHERE owner_user_id=?)',subject,subject);
  if(column==='identity_value')add('identity_value IN(SELECT phone FROM users WHERE id=? UNION SELECT email FROM users WHERE id=?)',subject,subject);
  if(column==='identity_hash')add('identity_hash IN(SELECT identity_hash FROM auth_otp_challenges WHERE identity_value IN(SELECT phone FROM users WHERE id=? UNION SELECT email FROM users WHERE id=?))',subject,subject);
  if(column==='entity_id')add('entity_id=?',subject);
 }
 return {sql:parts.length?'('+parts.join(' OR ')+')':'0=1',args};
}
