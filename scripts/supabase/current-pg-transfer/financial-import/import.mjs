// Disposable single-database PostgreSQL fixture only. No managed or real-data
// executor is implemented here; see README.md before integrating this code.
import {createHash,createHmac,timingSafeEqual} from 'node:crypto';
import {types} from 'node:util';

export class FinancialImportError extends Error{constructor(code){super(code);this.name='FinancialImportError';this.code=code;}}
const fail=code=>{throw new FinancialImportError(code);};
const HASH=/^[0-9a-f]{64}$/,UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const ID=/^[A-Za-z0-9_-]{1,80}$/;
const REQUEST_KEYS=['version','operation_id','collection_id','source_owner','target_owner','source_auth','target_auth','source_epoch','target_epoch'];
const PLAN_KEYS=[...REQUEST_KEYS,'context_hmac','identity_hmac','post_hmac','payment_count'];
const canonical=x=>Array.isArray(x)?'['+x.map(canonical).join(',')+']':x&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canonical(x[k])).join(',')+'}':JSON.stringify(x);
export const financialPlanDigest=serialized=>createHash('sha256').update(serialized).digest('hex');
const mac=(key,domain,value)=>createHmac('sha256',key).update('collect-synthetic-financial-import-v1\0').update(domain).update('\0').update(value).digest('hex');
const same=(a,b)=>HASH.test(a??'')&&HASH.test(b??'')&&timingSafeEqual(Buffer.from(a,'hex'),Buffer.from(b,'hex'));
function option(o,k){const d=Object.getOwnPropertyDescriptor(o,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_input');return d.value;}
function plain(o){return o&&typeof o==='object'&&!types.isProxy(o)&&Object.getPrototypeOf(o)===Object.prototype;}
const typedArrayPrototype=Object.getPrototypeOf(Uint8Array.prototype);
const typedBuffer=Object.getOwnPropertyDescriptor(typedArrayPrototype,'buffer').get;
const typedLength=Object.getOwnPropertyDescriptor(typedArrayPrototype,'byteLength').get;
const typedOffset=Object.getOwnPropertyDescriptor(typedArrayPrototype,'byteOffset').get;
const resizableBuffer=Object.getOwnPropertyDescriptor(ArrayBuffer.prototype,'resizable')?.get;
function copyKey(x){
 if(types.isProxy(x)||!Buffer.isBuffer(x)||Object.getPrototypeOf(x)!==Buffer.prototype)fail('invalid_input');
 try{const buffer=typedBuffer.call(x),length=typedLength.call(x),offset=typedOffset.call(x);
  if(types.isSharedArrayBuffer(buffer)||(resizableBuffer&&resizableBuffer.call(buffer))||length!==32)fail('invalid_input');
  const copy=Buffer.alloc(32);Uint8Array.prototype.set.call(copy,new Uint8Array(buffer,offset,length));return copy;}
 catch(e){if(e instanceof FinancialImportError)throw e;fail('invalid_input');}
}
function input(o,{plan=false}={}){
 if(!plain(o))fail('invalid_input');const mode=option(o,'mode');if(mode!=='synthetic')fail('managed_execution_closed');
 const serialized=option(o,plan?'planJson':'requestJson'),connect=option(o,'connect'),key=option(o,'key');
 if(typeof serialized!=='string'||Buffer.byteLength(serialized)>16384||typeof connect!=='function')fail('invalid_input');
 let value;try{value=JSON.parse(serialized);}catch{fail('invalid_input');}
 const expected=plan?PLAN_KEYS:REQUEST_KEYS;
 if(!plain(value)||Object.keys(value).sort().join('\0')!==[...expected].sort().join('\0')||canonical(value)!==serialized||
  value.version!=='collect.synthetic-financial-import.v1'||!UUID.test(value.operation_id??'')||
  ![value.source_auth,value.target_auth].every(x=>UUID.test(x??''))||value.source_auth===value.target_auth||
  ![value.collection_id,value.source_owner,value.target_owner].every(x=>ID.test(x??''))||value.source_owner===value.target_owner||
  ![value.source_epoch,value.target_epoch].every(x=>typeof x==='string'&&/^[1-9][0-9]{0,12}$/.test(x)))fail('invalid_input');
 if(plan){const expectedDigest=option(o,'expectedPlanSha256');if(!HASH.test(expectedDigest??'')||!same(financialPlanDigest(serialized),expectedDigest)||
  ![value.context_hmac,value.identity_hmac,value.post_hmac].every(x=>HASH.test(x??''))||
  !Number.isInteger(value.payment_count)||value.payment_count<1||value.payment_count>64)fail('invalid_input');}
 return {request:Object.freeze(value),serialized,connect,key:copyKey(key)};
}
const FIN=['payment_evidence','payments','momo_financial_links','ledger_entries','contribution_posting_snapshots'];
const UP=['sms_receipts','momo_parse_attempts','momo_transactions','momo_transaction_sources'];
const READ=[...FIN.map(n=>'src.'+n),...UP.flatMap(n=>['src.'+n,'app.'+n]),
 'src.users','app.users','src.auth_users','auth.users','src.auth_links','private.auth_links',
 'src.collections','app.collections','src.memberships','app.memberships','src.origins','private.origins',
 'src.jobs','private.jobs','src.scopes','private.scopes','src.object_proofs','private.object_proofs',
 'private.fixture_history_attestation','private.fixture_fences','private.fixture_admissions'];
const WRITE=[...FIN.map(n=>'app.'+n),'private.fixture_financial_receipts'];
export const FINANCIAL_RECONCILE_TABLES=Object.freeze(['app.users','auth.users','private.auth_links',...WRITE]);
const RECONCILE_TABLES=FINANCIAL_RECONCILE_TABLES;
const quote=s=>"'"+s.replaceAll("'","''")+"'";
// Includes all fixture relation definitions and user triggers, not just the
// columns selected by the import. No system OIDs enter the digest.
export const FINANCIAL_CATALOG_SQL=`WITH named AS (SELECT name,to_regclass(name) oid FROM unnest($1::text[]) name)
 SELECT encode(sha256(convert_to(jsonb_agg(jsonb_build_object('name',n.name,'kind',c.relkind,
  'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
  'columns',(SELECT COALESCE(jsonb_agg(jsonb_build_array(a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attgenerated,a.attidentity,
    (SELECT collname FROM pg_collation WHERE oid=a.attcollation),pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum),'[]'::jsonb)
   FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
  'constraints',(SELECT COALESCE(jsonb_agg(jsonb_build_array(k.conname,k.contype,pg_get_constraintdef(k.oid),k.convalidated,k.condeferrable,k.condeferred) ORDER BY k.conname),'[]'::jsonb)
   FROM pg_constraint k WHERE k.conrelid=c.oid),
  'indexes',(SELECT COALESCE(jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY ic.relname),'[]'::jsonb)
   FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid WHERE i.indrelid=c.oid),
  'triggers',(SELECT COALESCE(jsonb_agg(jsonb_build_array(t.tgname,t.tgenabled,t.tgtype,pg_get_triggerdef(t.oid),
    pg_get_userbyid(p.proowner),p.prosecdef,p.proconfig,l.lanname,p.prosrc) ORDER BY t.tgname),'[]'::jsonb)
   FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_language l ON l.oid=p.prolang
   WHERE t.tgrelid=c.oid AND NOT t.tgisinternal)) ORDER BY n.name)::text,'UTF8')),'hex') AS value
 FROM named n JOIN pg_class c ON c.oid=n.oid`;
export const FINANCIAL_FIXTURE_TABLES=Object.freeze([...READ,...WRITE]);
const EXPECTED_FIXTURE_CATALOG='62d1f3e2b83bf23d3d1a0ea2f074328f8002365da4bcc2b0dfd8f3b9855f1392';
const EXPECTED_RECONCILE_CATALOG='0c606c59cf4d7313abd738980a56f359763675e9db94784b27ccb7559f77776d';
const contextSql='SELECT jsonb_build_object('+READ.map(n=>quote(n)+",(SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb) FROM ONLY "+n+' t)').join(',')+")::text AS value";
const boundsSql=tables=>'SELECT COALESCE(bool_or(n>256 OR largest>32768 OR total>2000000),false) OR sum(total)>2000000 AS exceeded FROM ('+tables.map(n=>
 "SELECT count(*) AS n,COALESCE(max(octet_length(to_jsonb(t)::text)),0) AS largest,COALESCE(sum(octet_length(to_jsonb(t)::text)),0) AS total FROM ONLY "+n+' t').join(' UNION ALL ')+') q';
const identitySql=`SELECT jsonb_build_object(
 'user',(SELECT to_jsonb(t) FROM ONLY app.users t WHERE id=$1),
 'auth',(SELECT to_jsonb(t) FROM ONLY auth.users t WHERE id=$2::uuid),
 'link',(SELECT to_jsonb(t) FROM ONLY private.auth_links t WHERE auth_id=$2::uuid AND user_id=$1))::text AS value`;
function graphSql(schema,{projected=false}={}){
 const owner=(table,col)=>projected?`(to_jsonb(${table})||jsonb_build_object('${col}',$2::text))`:`to_jsonb(${table})`;
 const tables={
  payment_evidence:`SELECT COALESCE(jsonb_agg(${owner('e','owner_user_id')} ORDER BY e.id),'[]'::jsonb) FROM ONLY ${schema}.payment_evidence e WHERE e.collection_id=$1`,
  payments:`SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.id),'[]'::jsonb) FROM ONLY ${schema}.payments p WHERE p.collection_id=$1`,
  momo_financial_links:`SELECT COALESCE(jsonb_agg(${owner('f','linked_by')} ORDER BY f.transaction_id),'[]'::jsonb) FROM ONLY ${schema}.momo_financial_links f JOIN ONLY ${schema}.payments p ON p.id=f.payment_id WHERE p.collection_id=$1`,
  ledger_entries:`SELECT COALESCE(jsonb_agg(${owner('l','actor_user_id')} ORDER BY l.id),'[]'::jsonb) FROM ONLY ${schema}.ledger_entries l WHERE l.collection_id=$1`,
  contribution_posting_snapshots:`SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.ledger_entry_id),'[]'::jsonb) FROM ONLY ${schema}.contribution_posting_snapshots s JOIN ONLY ${schema}.payments p ON p.id=s.payment_id WHERE p.collection_id=$1`};
 return 'SELECT jsonb_build_object('+Object.entries(tables).map(([name,query])=>quote(name)+',('+query+')').join(',')+')::text AS value';
}
const EXPECTED_GUARD='999b0f2ebd33e11e6d0c7461c18e144b221f7cf76df6daaa6c282c693ef939b4';
const EXPECTED_JSON_VALID='6ceaad43daef880f979be7d78a07b64af581dc8abc5fcffc217fb12eee8c66aa';
async function fixture(c){
 const q=await c.query(`SELECT current_database() db,current_setting('cluster_name') cluster,session_user login,current_user role,
  inet_server_addr() IS NULL socket,current_setting('server_version_num')::int/10000 major,current_setting('session_replication_role') replication,
  (SELECT rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole FROM pg_roles WHERE rolname=current_user) privileged`);
 const x=q.rows[0];if(q.rowCount!==1||x.db!=='collect_financial_import_fixture'||x.cluster!=='collect_financial_import_fixture'||x.login!=='fixture_operator'||
  x.role!=='fixture_operator'||!x.socket||x.major!==17||x.replication!=='origin'||x.privileged!==false)fail('fixture_identity_rejected');
}
async function lock(c,{write=false}={}){
 await c.query("SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='15s'");
 await c.query('LOCK TABLE '+READ.join(',')+' IN SHARE MODE');
 await c.query('LOCK TABLE '+WRITE.join(',')+' IN '+(write?'SHARE ROW EXCLUSIVE':'SHARE')+' MODE');
}
async function visibleTables(c,tables){
 const q=await c.query(`WITH required(name) AS (SELECT unnest($1::text[])),r AS (SELECT name,to_regclass(name) oid FROM required)
  SELECT EXISTS(SELECT 1 FROM r LEFT JOIN pg_class c ON c.oid=r.oid WHERE r.oid IS NULL OR c.relkind<>'r'
   OR pg_get_userbyid(c.relowner) IS DISTINCT FROM 'fixture_bootstrap' OR c.relrowsecurity OR c.relforcerowsecurity
   OR NOT coalesce(has_table_privilege(current_user,r.oid,'SELECT'),false) OR coalesce(row_security_active(r.oid),true)
   OR EXISTS(SELECT 1 FROM pg_inherits i WHERE i.inhrelid=r.oid OR i.inhparent=r.oid)) AS bad`,[tables]);
 if(q.rows[0]?.bad!==false)fail('fixture_catalog_refused');
}
async function guard(c){
 await visibleTables(c,READ.concat(WRITE));
 const pairs=FIN.concat(UP).map(n=>['src.'+n,'app.'+n]);
 const shape=await c.query(`WITH pairs AS (SELECT unnest($1::text[]) a,unnest($2::text[]) b)
 SELECT bool_and((SELECT jsonb_agg(jsonb_build_array(attname,atttypid,atttypmod,attnotnull,attgenerated,attidentity,attcollation) ORDER BY attnum)
  FROM pg_attribute WHERE attrelid=to_regclass(a) AND attnum>0 AND NOT attisdropped)
  IS NOT DISTINCT FROM (SELECT jsonb_agg(jsonb_build_array(attname,atttypid,atttypmod,attnotnull,attgenerated,attidentity,attcollation) ORDER BY attnum)
  FROM pg_attribute WHERE attrelid=to_regclass(b) AND attnum>0 AND NOT attisdropped)) AS ok FROM pairs`,[pairs.map(x=>x[0]),pairs.map(x=>x[1])]);
 if(shape.rows[0]?.ok!==true)fail('fixture_schema_changed');
 const triggers=await c.query(`SELECT count(*)::int n,bool_and(t.tgenabled='A' AND t.tgname='fixture_financial_guard'
   AND t.tgtype=6 AND t.tgqual IS NULL AND t.tgnargs=0 AND t.tgfoid='private.fixture_financial_guard()'::regprocedure) enabled,
  bool_and(encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=$1 AND pg_get_userbyid(p.proowner)='fixture_bootstrap'
   AND NOT p.prosecdef AND p.proconfig IS NULL AND lang.lanname='plpgsql') body
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_language lang ON lang.oid=p.prolang
  WHERE NOT t.tgisinternal AND n.nspname='app' AND c.relname=ANY($2::text[])`,[EXPECTED_GUARD,FIN]);
 if(triggers.rows[0]?.n!==5||triggers.rows[0].enabled!==true||triggers.rows[0].body!==true)fail('fixture_guard_changed');
 const catalog=await c.query(FINANCIAL_CATALOG_SQL,[FINANCIAL_FIXTURE_TABLES]);
 if(catalog.rows[0]?.value!==EXPECTED_FIXTURE_CATALOG)fail('fixture_schema_changed');
 const helper=await c.query(`SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=$1
  AND pg_get_userbyid(p.proowner)='fixture_bootstrap' AND p.prokind='f' AND p.provolatile='i'
  AND p.proisstrict AND NOT p.prosecdef AND p.proconfig IS NULL AND l.lanname='plpgsql' AS ok
  FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid='app.json_valid(text)'::regprocedure`,[EXPECTED_JSON_VALID]);
 if(helper.rowCount!==1||helper.rows[0]?.ok!==true)fail('fixture_guard_changed');
 const b=await c.query(boundsSql(READ.concat(WRITE)));if(b.rows[0]?.exceeded!==false)fail('fixture_bounds_exceeded');
}
async function reconciliationGuard(c){
 await visibleTables(c,RECONCILE_TABLES);
 const catalog=await c.query(FINANCIAL_CATALOG_SQL,[RECONCILE_TABLES]);
 if(catalog.rows[0]?.value!==EXPECTED_RECONCILE_CATALOG)fail('fixture_schema_changed');
 const b=await c.query(boundsSql(RECONCILE_TABLES));if(b.rows[0]?.exceeded!==false)fail('fixture_bounds_exceeded');
}
async function value(c,sql,params=[]){const q=await c.query(sql,params);if(q.rowCount!==1||typeof q.rows[0].value!=='string'||Buffer.byteLength(q.rows[0].value)>2000000)fail('snapshot_unavailable');return q.rows[0].value;}
async function fenceAndIdentity(c,p){
 const q=await c.query(`SELECT (SELECT count(*)=2 AND bool_and(mode='fenced') FROM private.fixture_fences) AND
  EXISTS(SELECT 1 FROM private.fixture_fences WHERE side='source' AND epoch=$1::bigint) AND
  EXISTS(SELECT 1 FROM private.fixture_fences WHERE side='target' AND epoch=$2::bigint) AND
  NOT EXISTS(SELECT 1 FROM private.fixture_admissions WHERE state IS DISTINCT FROM 'settled' OR uncertain_dispatches IS DISTINCT FROM 0) AND
  EXISTS(SELECT 1 FROM src.users u JOIN src.auth_links l ON l.user_id=u.id JOIN src.auth_users a ON a.id=l.auth_id
   WHERE u.id=$3 AND u.active AND a.id=$4::uuid AND a.active) AND
  EXISTS(SELECT 1 FROM app.users u JOIN private.auth_links l ON l.user_id=u.id JOIN auth.users a ON a.id=l.auth_id
   WHERE u.id=$5 AND u.active AND a.id=$6::uuid AND a.active) AND
  EXISTS(SELECT 1 FROM src.collections WHERE id=$7 AND creator_user_id=$3) AND
  EXISTS(SELECT 1 FROM app.collections WHERE id=$7 AND creator_user_id=$5) AS ok`,
 [p.source_epoch,p.target_epoch,p.source_owner,p.source_auth,p.target_owner,p.target_auth,p.collection_id]);
 if(q.rows[0]?.ok!==true)fail('identity_or_fence_changed');
}
const CHECK_GRAPH=`WITH pay AS (SELECT * FROM ONLY src.payments WHERE collection_id=$1),
 joined AS (
 SELECT p.id pid,p.member_id,p.amount_minor,p.currency,p.intent_id,p.status,
 e.id eid,e.owner_user_id,e.object_key evidence_key,e.object_sha256 evidence_sha,e.external_reference evidence_reference,e.amount_minor evidence_amount,e.currency evidence_currency,e.collection_id evidence_collection,
 f.transaction_id,f.linked_by,f.beneficiary_member_id,
 t.amount_minor tx_amount,t.currency tx_currency,t.event_kind tx_event,t.mode tx_mode,t.parse_attempt_id tx_parse,t.receiving_account_id,t.allocation_state,t.has_conflict,
 x.raw_sms_id,x.parse_attempt_id,x.relation,
 r.owner_user_id sms_owner,r.originating_session_id,r.receiver_hash,r.object_key sms_key,r.object_sha256 sms_sha,r.body_sha256,
 a.raw_sms_id parse_sms,a.source_body_sha256,
 l.id ledger_id,l.member_id ledger_member,l.collection_id ledger_collection,l.evidence_id ledger_evidence,l.amount_minor ledger_amount,l.currency ledger_currency,l.kind,l.actor_user_id,l.posted_at ledger_posted,
 sn.ledger_entry_id snapshot_ledger,sn.posted_at snapshot_posted,
 to_jsonb(r) sms_row,to_jsonb(a) parse_row,to_jsonb(t) tx_row,to_jsonb(x) source_row,
 to_jsonb(o) origin_row,to_jsonb(j) job_row,to_jsonb(sc) scope_row,
 to_jsonb(tr) target_sms,to_jsonb(ta) target_parse,to_jsonb(tt) target_tx,to_jsonb(tx) target_source,
 to_jsonb(t_o) target_origin,to_jsonb(t_j) target_job,to_jsonb(t_sc) target_scope,
 so.object_key sms_proof,so.owner_id sms_proof_owner,so.entity_id sms_entity,so.purpose sms_purpose,so.plaintext_sha256 sms_plain,so.aad sms_aad,so.verified sms_verified,so.ciphertext_sha256 sms_cipher,to_jsonb(so) sms_proof_row,to_jsonb(ts_o) target_sms_proof,
 eo.object_key evidence_proof,eo.owner_id evidence_proof_owner,eo.entity_id evidence_entity,eo.purpose evidence_purpose,eo.plaintext_sha256 evidence_plain,eo.aad evidence_aad,eo.verified evidence_verified,eo.ciphertext_sha256 evidence_cipher,to_jsonb(eo) evidence_proof_row,to_jsonb(te_o) target_evidence_proof
 FROM pay p LEFT JOIN ONLY src.payment_evidence e ON e.id=p.evidence_id
 LEFT JOIN ONLY src.momo_financial_links f ON f.payment_id=p.id LEFT JOIN ONLY src.momo_transactions t ON t.id=f.transaction_id
 LEFT JOIN ONLY src.momo_transaction_sources x ON x.transaction_id=t.id LEFT JOIN ONLY src.sms_receipts r ON r.id=x.raw_sms_id
 LEFT JOIN ONLY src.momo_parse_attempts a ON a.id=x.parse_attempt_id LEFT JOIN ONLY src.ledger_entries l ON l.payment_id=p.id
 LEFT JOIN ONLY src.contribution_posting_snapshots sn ON sn.payment_id=p.id AND sn.ledger_entry_id=l.id
 LEFT JOIN ONLY src.origins o ON o.source_id=r.id LEFT JOIN ONLY src.jobs j ON j.source_id=r.id LEFT JOIN ONLY src.scopes sc ON sc.source_id=r.id
 LEFT JOIN ONLY app.sms_receipts tr ON tr.id=r.id LEFT JOIN ONLY app.momo_parse_attempts ta ON ta.id=a.id
 LEFT JOIN ONLY app.momo_transactions tt ON tt.id=t.id LEFT JOIN ONLY app.momo_transaction_sources tx ON tx.transaction_id=x.transaction_id AND tx.raw_sms_id=x.raw_sms_id AND tx.parse_attempt_id=x.parse_attempt_id
 LEFT JOIN ONLY private.origins t_o ON t_o.source_id=r.id LEFT JOIN ONLY private.jobs t_j ON t_j.source_id=r.id LEFT JOIN ONLY private.scopes t_sc ON t_sc.source_id=r.id
 LEFT JOIN ONLY src.object_proofs so ON so.object_key=r.object_key LEFT JOIN ONLY private.object_proofs ts_o ON ts_o.object_key=r.object_key
 LEFT JOIN ONLY src.object_proofs eo ON eo.object_key=e.object_key LEFT JOIN ONLY private.object_proofs te_o ON te_o.object_key=e.object_key
 ), balances AS (
 SELECT sn.member_balance_after_minor,sn.group_balance_after_minor,
  sum(l.amount_minor) OVER (ORDER BY sn.group_balance_after_minor,sn.ledger_entry_id ROWS UNBOUNDED PRECEDING) expected_group,
  sum(l.amount_minor) OVER (PARTITION BY l.member_id ORDER BY sn.group_balance_after_minor,sn.ledger_entry_id ROWS UNBOUNDED PRECEDING) expected_member,
  count(*) OVER (PARTITION BY sn.group_balance_after_minor) same_group_balance
 FROM ONLY src.contribution_posting_snapshots sn JOIN ONLY src.ledger_entries l ON l.id=sn.ledger_entry_id AND l.payment_id=sn.payment_id
 WHERE l.collection_id=$1
 )
 SELECT (SELECT count(*) FROM pay)::int count,
 (SELECT count(*) FROM joined)::int joined_count,
 (SELECT count(DISTINCT raw_sms_id) FROM joined)::int sms_count,
 (SELECT count(DISTINCT transaction_id) FROM joined)::int tx_count,
 (SELECT count(DISTINCT ledger_posted) FROM joined)::int timestamp_count,
 (SELECT count(*) FROM joined WHERE
  eid IS NULL OR ledger_id IS NULL OR snapshot_ledger IS NULL OR transaction_id IS NULL OR raw_sms_id IS NULL OR parse_attempt_id IS NULL OR
  member_id IS NULL OR member_id=$2 OR member_id=$3 OR intent_id IS NOT NULL OR status NOT IN ('reconciled','confirmed') OR
  owner_user_id IS DISTINCT FROM $2 OR linked_by IS DISTINCT FROM $2 OR actor_user_id IS DISTINCT FROM $2 OR
  evidence_collection IS DISTINCT FROM $1 OR evidence_amount IS DISTINCT FROM amount_minor OR evidence_currency IS DISTINCT FROM currency OR
  beneficiary_member_id IS DISTINCT FROM member_id OR tx_amount IS DISTINCT FROM amount_minor OR tx_currency IS DISTINCT FROM currency OR
  ledger_member IS DISTINCT FROM member_id OR ledger_collection IS DISTINCT FROM $1 OR ledger_evidence IS DISTINCT FROM eid OR ledger_amount IS DISTINCT FROM amount_minor OR ledger_currency IS DISTINCT FROM currency OR kind IS DISTINCT FROM 'contribution' OR
  snapshot_posted IS DISTINCT FROM ledger_posted OR NOT COALESCE(CASE
   WHEN ledger_posted ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$' AND pg_input_is_valid(ledger_posted,'timestamp with time zone')
   THEN to_char(ledger_posted::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')=ledger_posted AND ledger_posted::timestamptz<=transaction_timestamp()+interval '5 minutes'
   ELSE false END,false) OR
  tx_event IS DISTINCT FROM 'incoming_receipt' OR tx_parse IS DISTINCT FROM parse_attempt_id OR relation IS DISTINCT FROM 'accepted' OR allocation_state IS DISTINCT FROM 'linked' OR has_conflict IS DISTINCT FROM 0 OR
  sms_owner IS DISTINCT FROM $2 OR originating_session_id IS NOT NULL OR receiver_hash IS NOT NULL OR parse_sms IS DISTINCT FROM raw_sms_id OR source_body_sha256 IS DISTINCT FROM body_sha256 OR
  body_sha256 !~ '^[a-f0-9]{64}$' OR sms_sha !~ '^[a-f0-9]{64}$' OR sms_key IS DISTINCT FROM ('sms/'||raw_sms_id) OR
  evidence_key IS DISTINCT FROM ('evidence/'||eid) OR evidence_sha IS DISTINCT FROM body_sha256 OR evidence_reference IS DISTINCT FROM ('sms:'||body_sha256||':'||raw_sms_id) OR
  origin_row IS NULL OR origin_row->>'collection_id' IS DISTINCT FROM $1 OR origin_row->>'principal_user_id' IS DISTINCT FROM $2 OR origin_row->>'body_sha256' IS DISTINCT FROM body_sha256 OR origin_row->>'object_sha256' IS DISTINCT FROM sms_sha OR
  job_row IS NULL OR job_row->>'state' IS DISTINCT FROM 'completed' OR job_row->>'source_fingerprint' !~ '^[a-f0-9]{64}$' OR
  jsonb_typeof(job_row->'posting_facts') IS DISTINCT FROM 'object' OR job_row->>'collection_id' IS DISTINCT FROM $1 OR job_row->>'transaction_id' IS DISTINCT FROM transaction_id OR scope_row IS NULL OR scope_row->>'collection_id' IS DISTINCT FROM $1 OR scope_row->>'transaction_id' IS DISTINCT FROM transaction_id OR scope_row->>'receiving_account_id' IS DISTINCT FROM receiving_account_id OR
  ((job_row->'posting_facts') ?& ARRAY['event_kind','payment_outcome','currency','amount_minor','source_mode','wallet_balance_after_minor',
   'counterparty_name','counterparty_identifier','transaction_at','transaction_datetime_raw','provider_transaction_id','original_transaction_id','fee_minor','transaction_time_source','transaction_timezone']) IS DISTINCT FROM true OR
  job_row->'posting_facts'->>'event_kind' IS DISTINCT FROM tx_event OR job_row->'posting_facts'->>'payment_outcome' IS DISTINCT FROM 'successful' OR
  job_row->'posting_facts'->>'currency' IS DISTINCT FROM currency OR jsonb_typeof(job_row->'posting_facts'->'amount_minor') IS DISTINCT FROM 'number' OR
  job_row->'posting_facts'->>'amount_minor' !~ '^[1-9][0-9]{0,15}$' OR
  (job_row->'posting_facts'->'amount_minor') IS DISTINCT FROM to_jsonb(amount_minor) OR
  job_row->'posting_facts'->>'source_mode' IS DISTINCT FROM (CASE WHEN tx_mode='live' THEN 'live' ELSE 'catch_up' END) OR
  jsonb_typeof(job_row->'posting_facts'->'wallet_balance_after_minor') IS DISTINCT FROM 'number' OR NOT COALESCE(CASE
   WHEN job_row->'posting_facts'->>'wallet_balance_after_minor' ~ '^(0|[1-9][0-9]{0,15})$'
   THEN (job_row->'posting_facts'->>'wallet_balance_after_minor')::numeric<=9007199254740991 ELSE false END,false) OR
  COALESCE(jsonb_typeof(job_row->'posting_facts'->'counterparty_name'),'missing') NOT IN ('string','null') OR
  COALESCE(jsonb_typeof(job_row->'posting_facts'->'counterparty_identifier'),'missing') NOT IN ('string','null') OR
  COALESCE(jsonb_typeof(job_row->'posting_facts'->'transaction_at'),'missing') NOT IN ('string','null') OR
  COALESCE(jsonb_typeof(job_row->'posting_facts'->'transaction_datetime_raw'),'missing') NOT IN ('string','null') OR
  COALESCE(jsonb_typeof(job_row->'posting_facts'->'provider_transaction_id'),'missing') NOT IN ('string','null') OR
  COALESCE(jsonb_typeof(job_row->'posting_facts'->'original_transaction_id'),'missing') NOT IN ('string','null') OR
  COALESCE(jsonb_typeof(job_row->'posting_facts'->'transaction_time_source'),'missing') NOT IN ('string','null') OR
  COALESCE(jsonb_typeof(job_row->'posting_facts'->'transaction_timezone'),'missing') NOT IN ('string','null') OR
  NOT COALESCE(CASE WHEN jsonb_typeof(job_row->'posting_facts'->'fee_minor')='null' THEN true
   WHEN jsonb_typeof(job_row->'posting_facts'->'fee_minor')='number' AND job_row->'posting_facts'->>'fee_minor' ~ '^(0|[1-9][0-9]{0,15})$'
   THEN (job_row->'posting_facts'->>'fee_minor')::numeric<=9007199254740991 ELSE false END,false) OR
  target_sms IS DISTINCT FROM (sms_row||jsonb_build_object('owner_user_id',$3::text)) OR target_parse IS DISTINCT FROM parse_row OR target_tx IS DISTINCT FROM tx_row OR target_source IS DISTINCT FROM source_row OR
  target_origin IS DISTINCT FROM (origin_row||jsonb_build_object('principal_user_id',$3::text)) OR target_job IS DISTINCT FROM job_row OR target_scope IS DISTINCT FROM scope_row OR
  sms_proof IS NULL OR sms_proof_owner IS DISTINCT FROM $2 OR sms_entity IS DISTINCT FROM raw_sms_id OR sms_purpose IS DISTINCT FROM 'sms_receipt' OR sms_plain IS DISTINCT FROM sms_sha OR sms_aad IS DISTINCT FROM ('sms:'||raw_sms_id||':'||sms_sha) OR sms_verified IS DISTINCT FROM true OR sms_cipher !~ '^[a-f0-9]{64}$' OR target_sms_proof IS DISTINCT FROM (sms_proof_row||jsonb_build_object('owner_id',$3::text)) OR
  evidence_proof IS NULL OR evidence_proof_owner IS DISTINCT FROM $2 OR evidence_entity IS DISTINCT FROM eid OR evidence_purpose IS DISTINCT FROM 'payment_evidence' OR evidence_plain IS DISTINCT FROM evidence_sha OR evidence_aad IS DISTINCT FROM ('evidence:'||eid||':'||evidence_sha) OR evidence_verified IS DISTINCT FROM true OR evidence_cipher !~ '^[a-f0-9]{64}$' OR target_evidence_proof IS DISTINCT FROM (evidence_proof_row||jsonb_build_object('owner_id',$3::text)) OR
  NOT EXISTS(SELECT 1 FROM ONLY src.users u JOIN ONLY app.users tu ON to_jsonb(tu)=to_jsonb(u) WHERE u.id=member_id AND u.active) OR
  NOT EXISTS(SELECT 1 FROM ONLY src.memberships m JOIN ONLY app.memberships tm ON to_jsonb(tm)=to_jsonb(m) WHERE m.collection_id=$1 AND m.user_id=member_id)
 )::int bad,
 (SELECT count(*) FROM ONLY src.payment_evidence)::int all_evidence,
 (SELECT count(*) FROM ONLY src.payments)::int all_payments,
 (SELECT count(*) FROM ONLY src.momo_financial_links)::int all_links,
 (SELECT count(*) FROM ONLY src.ledger_entries)::int all_ledger,
 (SELECT count(*) FROM ONLY src.contribution_posting_snapshots)::int all_snapshots,
 (SELECT count(*) FROM balances WHERE same_group_balance<>1 OR group_balance_after_minor IS DISTINCT FROM expected_group OR member_balance_after_minor IS DISTINCT FROM expected_member)::int bad_balances,
 EXISTS(SELECT 1 FROM ONLY private.fixture_history_attestation WHERE collection_id=$1 AND complete_ledger AND no_prior_deletions AND reviewed AND evidence_sha256 ~ '^[a-f0-9]{64}$') history_attested`;
async function graphValid(c,p){
 const {rows:[r]}=await c.query(CHECK_GRAPH,[p.collection_id,p.source_owner,p.target_owner]);
 if(!r||r.count<1||r.count>64||[r.joined_count,r.sms_count,r.tx_count,r.timestamp_count,r.all_evidence,r.all_payments,r.all_links,r.all_ledger,r.all_snapshots].some(n=>n!==r.count)||r.bad!==0||r.bad_balances!==0||r.history_attested!==true)fail('financial_graph_refused');
 return r.count;
}
async function context(c,key,p){
 await fixture(c);await guard(c);await fenceAndIdentity(c,p);const count=await graphValid(c,p);
 return {count,context:mac(key,'context',await value(c,contextSql)),identity:mac(key,'identity',await value(c,identitySql,[p.target_owner,p.target_auth])),
  post:mac(key,'post',await value(c,graphSql('src',{projected:true}),[p.collection_id,p.target_owner]))};
}
async function emptyTarget(c){
 const sql='SELECT '+FIN.map(n=>`(SELECT count(*) FROM ONLY app.${n})`).join('+')+' AS n';
 const {rows:[r]}=await c.query(sql);if(Number(r.n)!==0)fail('target_financial_conflict');
}
async function receipt(c,p){const q=await c.query('SELECT operation_id::text,collection_id,plan_sha256,source_hmac,post_hmac,source_owner,target_owner,source_auth::text,target_auth::text,payment_count FROM private.fixture_financial_receipts WHERE operation_id=$1::uuid',[p.operation_id]);return q.rows[0];}
async function verifyReceipt(c,key,p,digest,r){
 if(!r||r.collection_id!==p.collection_id||r.plan_sha256!==digest||r.source_hmac!==p.context_hmac||r.post_hmac!==p.post_hmac||r.source_owner!==p.source_owner||r.target_owner!==p.target_owner||r.source_auth!==p.source_auth||r.target_auth!==p.target_auth||r.payment_count!==p.payment_count)fail('receipt_mismatch');
 if(!same(mac(key,'identity',await value(c,identitySql,[p.target_owner,p.target_auth])),p.identity_hmac))fail('identity_changed');
 if(!same(mac(key,'post',await value(c,graphSql('app'),[p.collection_id])),p.post_hmac))fail('postimage_changed');
}
const INSERTS=[
 `INSERT INTO app.payment_evidence SELECT (jsonb_populate_record(NULL::app.payment_evidence,to_jsonb(s)||jsonb_build_object('owner_user_id',$2::text))).* FROM ONLY src.payment_evidence s WHERE s.collection_id=$1 ORDER BY s.id`,
 `INSERT INTO app.payments SELECT s.* FROM ONLY src.payments s WHERE s.collection_id=$1 ORDER BY s.id`,
 `INSERT INTO app.momo_financial_links SELECT (jsonb_populate_record(NULL::app.momo_financial_links,to_jsonb(s)||jsonb_build_object('linked_by',$2::text))).* FROM ONLY src.momo_financial_links s JOIN ONLY src.payments p ON p.id=s.payment_id WHERE p.collection_id=$1 ORDER BY s.transaction_id`,
 `INSERT INTO app.ledger_entries SELECT (jsonb_populate_record(NULL::app.ledger_entries,to_jsonb(s)||jsonb_build_object('actor_user_id',$2::text))).* FROM ONLY src.ledger_entries s WHERE s.collection_id=$1 ORDER BY s.id`,
 `INSERT INTO app.contribution_posting_snapshots SELECT s.* FROM ONLY src.contribution_posting_snapshots s JOIN ONLY src.payments p ON p.id=s.payment_id WHERE p.collection_id=$1 ORDER BY s.ledger_entry_id`];
async function connectAndStart(opts,{write=false,readonly=false}={}){
 const c=await opts.connect();try{await fixture(c);await c.query(readonly?'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY':'BEGIN');
  if(readonly){await c.query("SET LOCAL lock_timeout='3s'; SET LOCAL statement_timeout='15s'");await c.query('LOCK TABLE '+RECONCILE_TABLES.join(',')+' IN ACCESS SHARE MODE');}
  else await lock(c,{write});return c;}
 catch(e){try{await c.end();}catch{}if(readonly&&e?.code==='42501')fail('fixture_catalog_refused');throw e;}
}
export async function captureSyntheticFinancialPlan(options){
 const opts=input(options);let c,started=false;
 try{c=await connectAndStart(opts);started=true;const p=opts.request;const result=await context(c,opts.key,p);await emptyTarget(c);
  const plan={...p,context_hmac:result.context,identity_hmac:result.identity,post_hmac:result.post,payment_count:result.count};
  const planJson=canonical(plan);await c.query('ROLLBACK');started=false;return {planJson,expectedPlanSha256:financialPlanDigest(planJson),writeAuthorized:false};
 }catch(e){if(c&&started)try{await c.query('ROLLBACK');}catch{}if(e instanceof FinancialImportError)throw e;fail('fixture_capture_failed');}
 finally{if(c)try{await c.end();}catch{}opts.key.fill(0);}
}
export async function importSyntheticFinancialGraph(options){
 const opts=input(options,{plan:true});let c,started=false,commitAttempted=false;
 try{c=await connectAndStart(opts,{write:true});started=true;const p=opts.request,digest=financialPlanDigest(opts.serialized),observed=await context(c,opts.key,p);
  if(observed.count!==p.payment_count||!same(observed.context,p.context_hmac)||!same(observed.identity,p.identity_hmac)||!same(observed.post,p.post_hmac))fail('preimage_changed');
  const old=await receipt(c,p);if(old){await verifyReceipt(c,opts.key,p,digest,old);await c.query('ROLLBACK');started=false;return {status:'already_applied'};}
  await emptyTarget(c);await c.query("SELECT set_config('collect.fixture_financial_operation',$1,true)",[p.operation_id]);
  for(const statement of INSERTS){const q=await c.query(statement,statement.includes('$2')?[p.collection_id,p.target_owner]:[p.collection_id]);if(q.rowCount!==p.payment_count)fail('source_changed');}
  if(!same(mac(opts.key,'post',await value(c,graphSql('app'),[p.collection_id])),p.post_hmac))fail('postimage_changed');
  await c.query(`INSERT INTO private.fixture_financial_receipts(operation_id,collection_id,plan_sha256,source_hmac,post_hmac,source_owner,target_owner,source_auth,target_auth,payment_count)
   VALUES($1::uuid,$2,$3,$4,$5,$6,$7,$8::uuid,$9::uuid,$10)`,[p.operation_id,p.collection_id,digest,p.context_hmac,p.post_hmac,p.source_owner,p.target_owner,p.source_auth,p.target_auth,p.payment_count]);
  await guard(c);commitAttempted=true;try{await c.query('COMMIT');started=false;return {status:'applied',payment_count:p.payment_count};}catch{return {status:'commit_unconfirmed_do_not_retry'};}
 }catch(e){if(c&&started&&!commitAttempted)try{await c.query('ROLLBACK');}catch{}if(e instanceof FinancialImportError)throw e;fail('fixture_transaction_failed');}
 finally{if(c)try{await c.end();}catch{}opts.key.fill(0);}
}
export async function reconcileSyntheticFinancialGraph(options){
 const opts=input(options,{plan:true});let c,started=false;
 try{c=await connectAndStart(opts,{readonly:true});started=true;await fixture(c);await reconciliationGuard(c);const p=opts.request,old=await receipt(c,p);
  if(!old){await c.query('ROLLBACK');started=false;return {status:'receipt_not_visible_do_not_retry'};}
  await verifyReceipt(c,opts.key,p,financialPlanDigest(opts.serialized),old);await c.query('ROLLBACK');started=false;return {status:'receipt_and_postimage_verified'};
 }catch(e){if(c&&started)try{await c.query('ROLLBACK');}catch{}if(e instanceof FinancialImportError)throw e;fail('fixture_reconciliation_failed');}
 finally{if(c)try{await c.end();}catch{}opts.key.fill(0);}
}
