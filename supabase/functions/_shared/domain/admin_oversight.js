import {ApiError} from './core.js';
import {accountDatabase} from './admin_accounts.js';

const uuid=/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const label=/^[a-z][a-z0-9_.:-]{0,119}$/;
const denied=(status,code,message)=>{throw new ApiError(status,code,message);};
const invalid=()=>denied(400,'invalid_oversight_query','Use the published bounded oversight filters.');
const unavailable=()=>denied(503,'oversight_unavailable','The oversight records could not be verified.');
const reference=value=>typeof value==='string'&&uuid.test(value)?value:null;
function decimal(value){return typeof value==='string'&&/^[1-9][0-9]{0,18}$/.test(value)&&BigInt(value)<=9223372036854775807n;}
function auditId(value){const id=String(value??'');if(!decimal(id))unavailable();return id;}
function fields(url,allowed){const seen=new Set();for(const key of url.searchParams.keys()){if(!allowed.includes(key)||seen.has(key))invalid();seen.add(key);}}
function filter(url,key,pattern){const value=url.searchParams.get(key);if(value!==null&&!pattern.test(value))invalid();return value;}
function limitOf(url){const raw=url.searchParams.get('limit')??'25';if(!/^[1-9][0-9]{0,2}$/.test(raw)||Number(raw)>100)invalid();return Number(raw);}
function timestamp(value){if(typeof value!=='string'||!Number.isFinite(Date.parse(value)))unavailable();return new Date(value).toISOString();}
function action(value){if(typeof value!=='string'||!label.test(value))unavailable();return value;}
function grants(account,actor,permission){
 if(!account?.permissions?.includes(permission)||!actor?.permissions?.has(permission)||actor.surface!=='admin'||actor.userId!==account.principal_id||actor.sessionId!==account.auth_session_id)
  denied(403,'permission_required','This oversight view is unavailable to the current account.');
}
async function read(env,account,permission,sql,args=[]){
 // The current BFF account, session and grant are checked in the same SQL
 // transaction that returns the rows. No unguarded SELECT result is released.
 const scoped=accountDatabase(env,account,permission);
 const result=await scoped.DB.batch([scoped.DB.prepare(sql).bind(...args)]);
 if(!Array.isArray(result?.[0]?.results))unavailable();return result[0].results;
}

// Fixed aggregate projections: no recipient, raw error, message, token or job
// identity crosses this endpoint. Counts cover all retained rows; dates are
// record observations, not a worker heartbeat or an external delivery probe.
export const oversightHealthSql=Object.freeze([
 `SELECT unixepoch() AS observed_seconds`,
 `SELECT
  count(*) FILTER (WHERE state='pending') AS pending,
  count(*) FILTER (WHERE state='retry') AS retry,
  count(*) FILTER (WHERE state='processing') AS processing,
  count(*) FILTER (WHERE state='processing' AND lease_until<=unixepoch()) AS expired_lease,
  count(*) FILTER (WHERE state='needs_review') AS needs_review,
  count(*) FILTER (WHERE state='source_unresolved') AS source_unresolved,
  count(*) FILTER (WHERE state IN('pending','retry','processing') AND attempt_count>=max_attempts) AS attempt_exhausted,
  count(*) FILTER (WHERE last_error IS NOT NULL) AS records_with_error,
  min(CASE WHEN state IN('pending','retry') AND available_at<=unixepoch() AND attempt_count<max_attempts THEN available_at
   WHEN state='processing' AND lease_until<=unixepoch() AND attempt_count<max_attempts THEN lease_until END) AS oldest_due_at,
  max(unixepoch(updated_at)) AS last_changed_at FROM momo_processing_jobs`,
 `SELECT
  count(*) FILTER (WHERE j.state='queued') AS queued,
  count(*) FILTER (WHERE j.state='claimed') AS claimed,
  count(*) FILTER (WHERE j.state='claimed' AND c.expires_seconds<=unixepoch()) AS expired_claim,
  count(*) FILTER (WHERE j.state='send_started') AS send_started,
  count(*) FILTER (WHERE j.state='observed_sent') AS observed_sent,
  count(*) FILTER (WHERE j.state='failed_no_send') AS failed_no_send,
  count(*) FILTER (WHERE j.state='uncertain') AS uncertain,
  min(CASE WHEN j.state='queued' THEN unixepoch(j.created_at) END) AS oldest_queued_at,
  min(CASE WHEN j.state IN('send_started','uncertain') THEN s.started_seconds END) AS oldest_unobserved_send_at,
  max(unixepoch(j.created_at)) AS last_created_at
  FROM assisted_sms_jobs j LEFT JOIN assisted_sms_claims c ON c.id=j.active_claim_id
  LEFT JOIN assisted_sms_send_starts s ON s.job_id=j.id`,
 `SELECT count(*) FILTER (WHERE status='pending') AS pending,
  count(*) FILTER (WHERE status='sent') AS sent,count(*) FILTER (WHERE status='failed') AS failed,
  count(*) FILTER (WHERE status='read') AS read,
  min(CASE WHEN status='pending' THEN unixepoch(created_at) END) AS oldest_pending_at,
  max(unixepoch(created_at)) AS last_created_at FROM notification_events`,
 `SELECT count(*) FILTER (WHERE status='pending') AS pending,
  count(*) FILTER (WHERE status='accepted') AS accepted,count(*) FILTER (WHERE status='failed') AS failed,
  min(CASE WHEN status='pending' THEN created_at END) AS oldest_pending_at,
  max(updated_at) AS last_changed_at FROM admin_email_events`,
 `SELECT count(*) FILTER (WHERE state='reserved') AS reserved,
  count(*) FILTER (WHERE state='dispatching') AS dispatching,
  count(*) FILTER (WHERE state='accepted') AS accepted,
  count(*) FILTER (WHERE state='rejected') AS rejected,
  count(*) FILTER (WHERE state='unknown') AS unknown,
  count(*) FILTER (WHERE state='already_registered') AS already_registered,
  min(CASE WHEN state IN('reserved','dispatching','unknown') THEN floor(extract(epoch FROM created_at))::bigint END) AS oldest_unconfirmed_at,
  max(floor(extract(epoch FROM coalesce(finished_at,claimed_at,created_at)))::bigint) AS last_changed_at
  FROM private.admin_invitation_attempts WHERE replayed_request_id IS NULL`,
 `SELECT count(*) FILTER (WHERE state='pending') AS pending,
  count(*) FILTER (WHERE state='retry') AS retry,
  count(*) FILTER (WHERE state='claimed') AS claimed,
  count(*) FILTER (WHERE state='sending') AS sending,
  count(*) FILTER (WHERE state='accepted') AS accepted,
  count(*) FILTER (WHERE state='rejected') AS rejected,
  count(*) FILTER (WHERE state='suppressed') AS suppressed,
  count(*) FILTER (WHERE state='unknown') AS unknown,
  count(*) FILTER (WHERE state IN('claimed','sending') AND lease_until<=unixepoch()) AS expired_lease,
  count(*) FILTER (WHERE state IN('pending','retry') AND available_at<=unixepoch()) AS due,
  count(*) FILTER (WHERE last_error IS NOT NULL) AS records_with_error,
  min(CASE WHEN state IN('pending','retry') AND available_at<=unixepoch() THEN available_at END) AS oldest_due_at,
  min(CASE WHEN state IN('pending','retry') THEN created_at END) AS oldest_pending_at,
  max(updated_at) AS last_changed_at FROM notification_deliveries`,
]);
const nonnegative=value=>Number.isSafeInteger(value)&&value>=0;
function metrics(row,counts,times,observed){
 if(!row||Object.keys(row).length!==counts.length+Object.keys(times).length)unavailable();
 const result={};for(const key of counts){if(!nonnegative(row[key]))unavailable();result[key]=row[key];}
 for(const [input,output]of Object.entries(times)){
  const value=row[input];if(value!==null&&(!nonnegative(value)||value>observed+5))unavailable();
  result[output]=value===null?null:output.endsWith('_seconds')?Math.max(0,observed-value):new Date(value*1000).toISOString();
 }
 return result;
}
async function health(env,account){
 const scoped=accountDatabase(env,account,'system_health.read');
 let result;try{result=await scoped.DB.batch(oversightHealthSql.map(sql=>scoped.DB.prepare(sql)));}catch(error){if(error instanceof ApiError)throw error;unavailable();}
 if(!Array.isArray(result)||result.length!==oversightHealthSql.length||result.some(item=>!Array.isArray(item?.results)||item.results.length!==1))unavailable();
 const [clock,momo,sms,notifications,email,invitations,delivery]=result.map(item=>item.results[0]),at=clock.observed_seconds;
 if(!nonnegative(at)||Math.abs(at*1000-Date.now())>120000)unavailable();
 return {contract_version:1,scope:'admin_operational_health',database:'available',
  storage_binding:env.PRIVATE_MEDIA?'configured':'missing',
  source_revision:/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(env.BUILD_SOURCE_ID??'')?env.BUILD_SOURCE_ID:'unknown',
  checked_at:new Date(at*1000).toISOString(),external_services_checked:false,
  configuration:{momo_processing:env.MOMO_PROCESSING_PAUSED==='false'?'enabled':'paused',
   momo_extractor:env.MOMO_AI_ENABLED!=='true'?'disabled':typeof env.AI?.run==='function'?'configured':'missing',
   transactional_email:typeof env.AUTH_EMAIL?.send==='function'?'configured':'missing'},
  metrics_scope:'all_retained_rows',worker_heartbeat:'not_recorded',
  queues:{
   momo:metrics(momo,['pending','retry','processing','expired_lease','needs_review','source_unresolved','attempt_exhausted','records_with_error'],{oldest_due_at:'oldest_due_seconds',last_changed_at:'last_changed_at'},at),
   assisted_sms:{...metrics(sms,['queued','claimed','expired_claim','send_started','observed_sent','failed_no_send','uncertain'],{oldest_queued_at:'oldest_queued_seconds',oldest_unobserved_send_at:'oldest_unobserved_send_seconds',last_created_at:'last_created_at'},at),automatic_retry:false},
   notifications:{...metrics(notifications,['pending','sent','failed','read'],{oldest_pending_at:'oldest_pending_seconds',last_created_at:'last_created_at'},at),semantics:'persisted_in_app_events'},
   admin_email:{...metrics(email,['pending','accepted','failed'],{oldest_pending_at:'oldest_pending_seconds',last_changed_at:'last_changed_at'},at),semantics:'legacy_email_records'},
   invitations:{...metrics(invitations,['reserved','dispatching','accepted','rejected','unknown','already_registered'],{oldest_unconfirmed_at:'oldest_unconfirmed_seconds',last_changed_at:'last_changed_at'},at),semantics:'original_invitation_attempts',accepted_means:'provider_accepted'},
   push_delivery:{...metrics(delivery,['pending','retry','claimed','sending','accepted','rejected','suppressed','unknown','expired_lease','due','records_with_error'],{oldest_due_at:'oldest_due_seconds',oldest_pending_at:'oldest_pending_seconds',last_changed_at:'last_changed_at'},at),semantics:'persisted_push_dispatches',accepted_means:'provider_accepted',unknown_is_retryable:false},
  }};
}

/** Metadata-only cross-operator oversight. Raw details, account secrets,
 * session identifiers, payloads and free-text reasons are never selected. */
export async function adminOversightRead(request,env,account,actor,parts,url=new URL(request.url)){
 if(request.method!=='GET')denied(405,'method_not_allowed','Oversight is read-only.');
 if(parts.length===1&&parts[0]==='health'){
  fields(url,[]);grants(account,actor,'system_health.read');
  return health(env,account);
 }
 if(parts.length!==2||parts[0]!=='audit'||!['domain','accounts'].includes(parts[1]))denied(404,'oversight_not_found','This oversight view does not exist.');
 grants(account,actor,'audit.read');
 const source=parts[1];fields(url,source==='domain'?['limit','before_id','actor_id','action','entity_id']:['limit','before_id','before_seconds','actor_id','action','entity_id']);
 const limit=limitOf(url),actorId=filter(url,'actor_id',uuid),entityId=filter(url,'entity_id',uuid),event=filter(url,'action',label);
 const before=url.searchParams.get('before_id');let beforeSeconds=null;
 if(source==='domain'&&before!==null&&!decimal(before))invalid();
 if(source==='accounts'){
  const raw=url.searchParams.get('before_seconds');
  if((before===null)!==(raw===null)||before!==null&&!uuid.test(before)||raw!==null&&(!/^[1-9][0-9]{0,11}$/.test(raw)||!Number.isSafeInteger(Number(raw))))invalid();
  beforeSeconds=raw===null?null:Number(raw);
 }
 const found=source==='domain'
  ?await read(env,account,'audit.read',`SELECT id::text AS id,actor_user_id,action,entity_type,entity_id,request_id,created_at FROM audit_log
   WHERE (?::bigint IS NULL OR id<?::bigint) AND (?::text IS NULL OR actor_user_id=?)
   AND (?::text IS NULL OR action=?) AND (?::text IS NULL OR entity_id=?) ORDER BY audit_log.id DESC LIMIT ?`,
   [before,before,actorId,actorId,event,event,entityId,entityId,limit+1])
  :await read(env,account,'audit.read',`SELECT id,actor_id,subject_id,action,occurred_at FROM admin_account_audit
   WHERE (?::bigint IS NULL OR occurred_at<?::bigint OR occurred_at=?::bigint AND id<?)
   AND (?::text IS NULL OR actor_id=?) AND (?::text IS NULL OR action=?) AND (?::text IS NULL OR subject_id=?)
   ORDER BY occurred_at DESC,id DESC LIMIT ?`,
   [beforeSeconds,beforeSeconds,beforeSeconds,before,actorId,actorId,event,event,entityId,entityId,limit+1]);
 if(found.length>limit+1)unavailable();
 const rows=found.slice(0,limit).map(row=>{
  if(source==='domain')return {id:auditId(row.id),actor_id:reference(row.actor_user_id),action:action(row.action),
   entity_type:action(row.entity_type),entity_id:reference(row.entity_id),request_id:reference(row.request_id),created_at:timestamp(row.created_at)};
  if(!uuid.test(row.id??'')||!Number.isSafeInteger(row.occurred_at)||row.occurred_at<1)unavailable();
  return {id:row.id,actor_id:reference(row.actor_id),action:action(row.action),entity_type:'admin_account',
   entity_id:reference(row.subject_id),request_id:null,created_at:new Date(row.occurred_at*1000).toISOString()};
 });
 const last=found[Math.min(limit,found.length)-1];
 return {contract_version:1,scope:'cross_operator_audit_metadata',source,
  actor_reference:source==='domain'?'canonical_principal':'admin_account',limit,
  next_cursor:found.length>limit?(source==='domain'?{before_id:auditId(last.id)}:{before_id:last.id,before_seconds:last.occurred_at}):null,
  rows,details_included:false,checked_at:new Date().toISOString()};
}
