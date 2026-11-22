import {ApiError,now,uuid} from './core.js';
import {receiptFactColumns,receiptFactJoins,withReceiptFacts} from './receipt_facts.js';

const fail=(s,c,m)=>{throw new ApiError(s,c,m);};
export const exactMomoMeasurement=value=>{if(!Number.isSafeInteger(value))fail(503,'invalid_source_data','Transaction measurements are unavailable.');return value;};

// The legacy assignment workflow accepts only its original managed receipt.
// A native observation deliberately has no managed session or receiver hash:
// its configured capture scope is not evidence of the receiving account.
export const MANAGED_MOMO_SOURCE_SQL=`EXISTS(SELECT 1 FROM momo_transaction_sources managed_source
 JOIN sms_receipts managed_raw ON managed_raw.id=managed_source.raw_sms_id
 JOIN momo_parse_attempts managed_attempt ON managed_attempt.id=managed_source.parse_attempt_id
  AND managed_attempt.raw_sms_id=managed_source.raw_sms_id AND managed_attempt.outcome='accepted'
  AND managed_attempt.source_body_sha256=managed_raw.body_sha256
 WHERE managed_source.transaction_id=t.id AND managed_source.parse_attempt_id=t.parse_attempt_id
 AND managed_source.relation='accepted' AND managed_raw.originating_session_id IS NOT NULL
 AND managed_raw.receiver_hash IS NOT NULL)`;
// The native scope lookup is installed by the additive auto-transaction
// migration. Keep the existing managed query usable until that feature is
// explicitly enabled on a deployment containing the lookup.
export function momoTransactionSql(env){
 const native=env?.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED==='true';
 // Enrichment is source-bound and separately retained: immutable first parse
 // rows remain intact. Project the same validated native facts as the app.
 const transactionSource=native?`momo_transactions original
 LEFT JOIN LATERAL (SELECT private.burimunsi_admin_sms_facts(original.id) AS facts) native_facts ON true
 CROSS JOIN LATERAL jsonb_populate_record(NULL::app.momo_transactions,to_jsonb(original) ||
  jsonb_strip_nulls(jsonb_build_object(
   'event_kind',native_facts.facts->'event_kind','amount_minor',native_facts.facts->'amount_minor',
   'currency',native_facts.facts->'currency','currency_scale',CASE WHEN native_facts.facts->>'currency'='RWF' THEN 0 ELSE NULL END,
   'payer_name',native_facts.facts->'counterparty_name','payer_identifier',native_facts.facts->'counterparty_identifier',
   'payer_last3',CASE WHEN native_facts.facts->>'counterparty_identifier' ~ '^[*xX•+0-9 ()-]*[0-9]{3}$' THEN right(native_facts.facts->>'counterparty_identifier',3) ELSE NULL END,
   'fee_minor',native_facts.facts->'fee_minor','wallet_balance_after_minor',native_facts.facts->'wallet_balance_after_minor',
   'transaction_at',native_facts.facts->'transaction_at','transaction_datetime_raw',native_facts.facts->'transaction_datetime_raw',
   'transaction_time_source',native_facts.facts->'transaction_time_source','transaction_timezone',native_facts.facts->'transaction_timezone',
   'provider_transaction_id',native_facts.facts->'provider_transaction_id','original_transaction_id',native_facts.facts->'original_transaction_id'
  ))) AS t`:'momo_transactions t';
 const nativeGroup=native?"CASE WHEN native_access.scope->>'kind'='visible' THEN native_access.scope->>'groupId' ELSE NULL END":'NULL';
 const nativeJoin=native?'LEFT JOIN LATERAL (SELECT private.burimunsi_admin_transaction_visibility(t.id) AS scope) native_access ON true':'';
 const nativeFilter=native?"WHERE native_access.scope->>'kind' IN ('managed','visible') AND (rf_capture.id IS NULL OR rf_capture.originating_session_id IS NOT NULL OR native_access.scope->>'kind'='visible')":
  'WHERE (rf_capture.id IS NULL OR rf_capture.originating_session_id IS NOT NULL)';
 return `SELECT t.*,${receiptFactColumns},a.public_code,a.recipient_name,l.payment_id,l.beneficiary_member_id,${nativeGroup} AS native_group_id,coalesce(p.collection_id,${nativeGroup}) AS group_id,g.title AS group_name,u.full_name AS member_name,
 p.revision AS payment_version,p.intent_id,coalesce((SELECT sum(e.amount_minor) FROM ledger_entries e WHERE e.payment_id=p.id),0) AS credited_amount_minor,
 CASE WHEN p.status='reversed' THEN 'reversed' WHEN p.status IN('reconciled','confirmed') THEN 'credited'
 WHEN ${nativeGroup} IS NOT NULL OR t.event_kind NOT IN ('incoming_receipt','reversal') THEN 'recorded'
 WHEN t.has_conflict=1 OR t.allocation_state='needs_review' THEN 'needs_review' WHEN l.payment_id IS NOT NULL THEN 'awaiting_review' ELSE 'needs_allocation' END AS status
 FROM ${transactionSource} JOIN momo_receiving_accounts a ON a.id=t.receiving_account_id ${receiptFactJoins} ${nativeJoin}
 LEFT JOIN momo_financial_links l ON l.transaction_id=t.id LEFT JOIN payments p ON p.id=l.payment_id
 LEFT JOIN collections g ON g.id=coalesce(p.collection_id,${nativeGroup}) LEFT JOIN users u ON u.id=l.beneficiary_member_id ${nativeFilter}`;
}
export function queryMomoFilters(url,allowed){for(const key of url.searchParams.keys())if(!allowed.includes(key)||url.searchParams.getAll(key).length!==1)fail(400,'invalid_filter','This MoMo filter is unavailable.');
 const offset=Number(url.searchParams.get('offset')??0),limit=Number(url.searchParams.get('limit')??25),search=url.searchParams.get('search')??'',status=url.searchParams.get('status')??'';
 if(!Number.isInteger(offset)||offset<0||offset>2147483647||!Number.isInteger(limit)||limit<1||limit>100||search.length>200||/[\x00-\x1f\x7f]/.test(search))fail(400,'invalid_filter','Choose a valid transaction filter.');
 return {offset,limit,search,status};}
export function momoTransactionPredicates(url,f){const where=[],args=[];
 if(url.searchParams.has('receiving_account_id')&&url.searchParams.has('account_scope_id'))
  fail(400,'invalid_filter','Choose only one account filter.');
 if(f.search){where.push('(provider_transaction_id LIKE ? OR payer_name LIKE ?)');args.push('%'+f.search+'%','%'+f.search+'%');}
 if(f.status==='needs_attention')where.push("(status IN('needs_allocation','awaiting_review','needs_review') OR has_conflict=1)");
 else if(f.status){if(!['recorded','needs_allocation','awaiting_review','credited','reversed','needs_review'].includes(f.status))fail(400,'invalid_filter','Choose a supported payment state.');where.push(f.status==='needs_review'?'(status=? OR has_conflict=1)':'status=?');args.push(f.status);}
 for(const key of ['receiving_account_id','group_id'])if(url.searchParams.has(key)){
  where.push(key==='receiving_account_id'?`(${key}=? AND native_group_id IS NULL)`:`${key}=?`);
  args.push(uuid(url.searchParams.get(key),key));}
 // Opt-in contract: the account is the configured native capture scope or the
 // recorded managed receiving account, not proof of an SMS destination. Keep
 // the older receiving-account filter unchanged for already-installed clients.
 if(url.searchParams.has('account_scope_id')){
  where.push('receiving_account_id=?');args.push(uuid(url.searchParams.get('account_scope_id'),'account_scope_id'));
 }
 for(const [key,op]of [['from','>='],['to','<=']])if(url.searchParams.has(key)){const value=url.searchParams.get(key);if(!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(value)||!Number.isFinite(Date.parse(value)))fail(400,'invalid_filter','Use an exact UTC transaction date.');where.push(`transaction_at ${op} ?`);args.push(value);}
 return {where:where.length?' WHERE '+where.join(' AND '):'',args};}
export function momoTransactionPageRow(row,accountScope){
 const facts=withReceiptFacts(row);
 if(accountScope!==null&&row.receiving_account_id!==accountScope)
  fail(503,'invalid_source_data','Transaction account scope changed. Refresh to check again.');
 // Only the explicit new filter discloses this scoped identifier. The legacy
 // receiving-account fields remain null for native observations.
 return accountScope!==null&&row.native_group_id!=null
  ?{...facts,capture_scope_account_id:row.receiving_account_id}:facts;
}
export async function momoTransactionPage(env,url){const f=queryMomoFilters(url,['limit','offset','search','status','receiving_account_id','account_scope_id','group_id','from','to']),filter=momoTransactionPredicates(url,f),cte=`WITH records AS (${momoTransactionSql(env)})`;
 const result=await env.DB.batch([env.DB.prepare(`${cte} SELECT count(*) AS total,coalesce(sum(CASE WHEN event_kind='incoming_receipt' THEN amount_minor ELSE 0 END),0) AS received,coalesce(sum(credited_amount_minor),0) AS credited,
 coalesce(sum(CASE WHEN event_kind='incoming_receipt' AND credited_amount_minor=0 AND status!='reversed' THEN amount_minor ELSE 0 END),0) AS unallocated FROM records${filter.where}`).bind(...filter.args),
 env.DB.prepare(`${cte} SELECT * FROM records${filter.where} ORDER BY coalesce(transaction_at,created_at) DESC,id LIMIT ? OFFSET ?`).bind(...filter.args,f.limit,f.offset)]);
 const total=result[0].results[0],scope=url.searchParams.has('account_scope_id')?uuid(url.searchParams.get('account_scope_id'),'account_scope_id'):null;return {contract_version:1,rows:result[1].results.map(row=>momoTransactionPageRow(row,scope)),total:exactMomoMeasurement(total.total),limit:f.limit,offset:f.offset,
 totals:{received_minor:exactMomoMeasurement(total.received),credited_minor:exactMomoMeasurement(total.credited),unallocated_minor:exactMomoMeasurement(total.unallocated)},currency:'RWF',date_basis:'provider_transaction_time',as_of:now()};}
export async function momoPaymentChecks(env,url){
 const f=queryMomoFilters(url,['limit','offset']),cte=`WITH typed AS (
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
  env.DB.prepare(`${cte} SELECT * FROM checked ORDER BY requested_at DESC,id DESC LIMIT ? OFFSET ?`).bind(f.limit,f.offset)]),total=exactMomoMeasurement(result[0].results[0].total);
 return {contract_version:1,rows:result[1].results.map(row=>({...row,expected_amount_minor:exactMomoMeasurement(row.expected_amount_minor),source:'member_request',provider_reference_verified:false,financial_effects:0})),total,limit:f.limit,offset:f.offset,next_offset:f.offset+result[1].results.length<total?f.offset+result[1].results.length:null};
}
