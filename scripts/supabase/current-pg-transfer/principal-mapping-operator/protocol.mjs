// Input and output boundaries. The managed plan is deliberately unqualified:
// the owner-confirmed four IDs and a retained source-cluster pin are absent.
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {preflightPlanDigest} from '../principal-mapping-preflight/preflight.mjs';
import {isSyntheticReconciliationSocket} from '../reconcile.mjs';
import {managedReconciliationSsl} from '../managed-target.mjs';
const PROJECT='rrlduytparvsjfmegalh',HEX=/^[a-f0-9]{64}$/;
const MANAGED_REVIEWED_PLAN_SHA256=null;
const fail=code=>{throw Object.assign(Error(code),{safeCode:code});};
const exact=(o,keys)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.getPrototypeOf(o)===Object.prototype&&!types.isProxy(o)&&Reflect.ownKeys(o).length===keys.length&&Object.keys(o).sort().join(',')===[...keys].sort().join(',')&&Object.values(Object.getOwnPropertyDescriptors(o)).every(d=>d.enumerable&&Object.hasOwn(d,'value'));
function canonical(v,depth=0){
 if(depth>12)fail('input_refused');
 if(v===null||typeof v==='string'||typeof v==='boolean'||Number.isSafeInteger(v))return JSON.stringify(v);
 if(!v||typeof v!=='object'||Array.isArray(v)||types.isProxy(v)||Object.getPrototypeOf(v)!==Object.prototype||Object.getOwnPropertySymbols(v).length)fail('input_refused');
 const d=Object.getOwnPropertyDescriptors(v),keys=Object.keys(d).sort();if(keys.some(k=>k==='__proto__'||!d[k].enumerable||!Object.hasOwn(d[k],'value')))fail('input_refused');
 return '{'+keys.map(k=>JSON.stringify(k)+':'+canonical(d[k].value,depth+1)).join(',')+'}';
}
export function planDigest(p){return createHash('sha256').update(canonical(p),'utf8').digest('hex');}
export function cleanEnvironment(env=process.env,argv=process.execArgv){
 return Array.isArray(argv)&&argv.length===0&&!Object.entries(env).some(([k,v])=>v&&/^(?:NODE_|OPENSSL_|SSL_|SSLKEYLOGFILE$|LD_|DYLD_|PG[A-Z_0-9]*$|SUPABASE_|DATABASE_URL$|POSTGRES_URL$|.*_PROXY$|NO_PROXY$)/i.test(k));
}
function password(x){return typeof x==='string'&&Buffer.byteLength(x,'utf8')>=1&&Buffer.byteLength(x,'utf8')<=1024&&!/[\u0000-\u001f\u007f\ud800-\udfff]/u.test(x);}
export function validateEnvelope(e,expected){
 if(!exact(e,['plan','sourcePassword','targetPassword'])||!password(e.sourcePassword)||!password(e.targetPassword)||!HEX.test(expected??''))fail('input_refused');
 const p=e.plan;if(!exact(p,['format','preflight','preflightSha256','sourceIdentity','deadlineMs'])||p.format!=='collect.principal-supervisor.v1'||!HEX.test(p.preflightSha256??'')||
  !Number.isSafeInteger(p.deadlineMs)||p.deadlineMs<1000||p.deadlineMs>120000||planDigest(p)!==expected)fail('plan_refused');
 let digest;try{digest=preflightPlanDigest(p.preflight);}catch{fail('plan_refused');}
 if(digest!==p.preflightSha256||!exact(p.sourceIdentity,['systemIdentifier','postmasterStartedAt','serverVersion'])||
  !/^[1-9][0-9]{9,19}$/.test(p.sourceIdentity.systemIdentifier??'')||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$/.test(p.sourceIdentity.postmasterStartedAt??'')||
  !/^17[0-9]{4}$/.test(p.sourceIdentity.serverVersion??''))fail('plan_refused');
 const f=p.preflight,s=f?.source,t=f?.target;
 const pk=['format','project_ref','owner_decision','decision_reference_sha256','source_set_sha256','max_rows','statement_timeout_ms','total_timeout_ms','source','target'];
 const sk=['kind','host','port','database','session_user','current_user','profile_sha256','auth_user_id','app_user_id'];
 const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
 const role=/^[a-z_][a-z0-9_]{0,62}$/;
 if(!exact(f,pk)||f.format!=='collect.principal-mapping-preflight.v1'||f.project_ref!==PROJECT||f.owner_decision!=='same_person_keep_cloud_primary'||
  !HEX.test(f.decision_reference_sha256??'')||!HEX.test(f.source_set_sha256??'')||!Number.isSafeInteger(f.max_rows)||f.max_rows<1||f.max_rows>64||
  !Number.isSafeInteger(f.statement_timeout_ms)||f.statement_timeout_ms<250||f.statement_timeout_ms>30000||
  !Number.isSafeInteger(f.total_timeout_ms)||f.total_timeout_ms<f.statement_timeout_ms||f.total_timeout_ms>120000||p.deadlineMs<f.total_timeout_ms+500)fail('plan_refused');
 for(const [x,source] of [[s,true],[t,false]])if(!exact(x,sk)||typeof x.host!=='string'||!role.test(x.database??'')||!role.test(x.session_user??'')||!role.test(x.current_user??'')||!uuid.test(x.auth_user_id??'')||
  typeof x.app_user_id!=='string'||Buffer.byteLength(x.app_user_id)<1||Buffer.byteLength(x.app_user_id)>128||/[\u0000-\u001f\u007f\ud800-\udfff]/u.test(x.app_user_id)||
  (source?!HEX.test(x.profile_sha256??''):x.profile_sha256!==null))fail('plan_refused');
 if(s?.kind==='synthetic'&&t?.kind==='synthetic'){
  if(!isSyntheticReconciliationSocket(s.host)||s.host!==t.host||!/^collect_fixture_[a-z0-9_]+$/.test(s.database??'')||!/^collect_fixture_[a-z0-9_]+$/.test(t.database??'')||
    !Number.isSafeInteger(s.port)||s.port<1||s.port>65535||!Number.isSafeInteger(t.port)||t.port<1||t.port>65535||s.host===t.host&&s.port===t.port&&s.database===t.database)fail('plan_refused');
  return {mode:'synthetic',plan:p};
 }
 if(s?.kind!=='local'||s.host!=='127.0.0.1'||!Number.isSafeInteger(s.port)||s.port<1||s.port>65535||
  t?.kind!=='managed'||t.host!==`db.${PROJECT}.supabase.co`||t.port!==5432||t.database!=='postgres'||t.session_user!=='postgres'||t.current_user!=='postgres')fail('plan_refused');
 // No value is inferred from email, an aggregate observation, or this input.
 // A newly reviewed exact plan/source binding and independent review must
 // change this source pin before this branch can ever connect.
 if(MANAGED_REVIEWED_PLAN_SHA256===null||expected!==MANAGED_REVIEWED_PLAN_SHA256)fail('managed_preimage_unavailable');
 return {mode:'managed',plan:p};
}
export function targetConfig(side,secret,timeout){
 if(side?.kind!=='managed'||side.host!==`db.${PROJECT}.supabase.co`||side.port!==5432||side.database!=='postgres'||side.session_user!=='postgres'||side.current_user!=='postgres'||!password(secret)||!Number.isSafeInteger(timeout)||timeout<250||timeout>10000)fail('plan_refused');
 return {host:side.host,port:5432,database:'postgres',user:'postgres',password:secret,ssl:managedReconciliationSsl(),connectionTimeoutMillis:timeout};
}
const countKeys=['auth_users','app_users','principal_links','selected_auth_rows','selected_app_rows','selected_exact_links','selected_link_touches','dangling_links','selected_auth_inactive','selected_app_inactive'];
const keys=['id','phone','email','public_id'];
const count=x=>Number.isSafeInteger(x)&&x>=0&&x<=4096;
function counts(x){return exact(x,countKeys)&&countKeys.every(k=>count(x[k]));}
function group(x){return exact(x,keys)&&keys.every(k=>count(x[k]));}
export function sanitizeObservation(r,p){
 const fields=['format','status','plan_sha256','source_set_sha256','owner_decision','source','target','conflicts','email_is_identity_proof','other_identity_mappings_inferred','historical_references_verified','provider_or_device_state_verified','quiescence_proven','write_authorized'];
 if(!exact(r,fields)||r.format!=='collect.principal-mapping-preflight.v1'||r.status!=='aggregate_observation'||r.plan_sha256!==p.preflightSha256||r.source_set_sha256!==p.preflight.source_set_sha256||r.owner_decision!=='same_person_keep_cloud_primary'||
  !counts(r.source)||!counts(r.target)||['email_is_identity_proof','other_identity_mappings_inferred','historical_references_verified','provider_or_device_state_verified','quiescence_proven','write_authorized'].some(k=>r[k]!==false))fail('result_refused');
 return validatePublicObservation({status:'aggregate_observation',source:r.source,target:r.target,conflicts:r.conflicts,email_is_identity_proof:false,other_identity_mappings_inferred:false,
  historical_references_verified:false,provider_or_device_state_verified:false,quiescence_proven:false,write_authorized:false});
}
export function validatePublicObservation(r){
 if(!exact(r,['status','source','target','conflicts','email_is_identity_proof','other_identity_mappings_inferred','historical_references_verified','provider_or_device_state_verified','quiescence_proven','write_authorized'])||r.status!=='aggregate_observation'||!counts(r.source)||!counts(r.target)||
  ['email_is_identity_proof','other_identity_mappings_inferred','historical_references_verified','provider_or_device_state_verified','quiescence_proven','write_authorized'].some(k=>r[k]!==false))fail('result_refused');
 const c=r.conflicts;if(!exact(c,['selected_auth_email_matches','cloud_auth_emails_uncomparable','selected_auth_ids_equal','other_cloud_auth_id_conflicts','other_cloud_auth_email_matches','selected_source_app_key_conflicts','unselected_source_app_key_conflicts'])||
  ![null,true,false].includes(c.selected_auth_email_matches)||!count(c.cloud_auth_emails_uncomparable)||typeof c.selected_auth_ids_equal!=='boolean'||!count(c.other_cloud_auth_id_conflicts)||
  !(c.other_cloud_auth_email_matches===null||count(c.other_cloud_auth_email_matches))||!(c.selected_source_app_key_conflicts===null||group(c.selected_source_app_key_conflicts))||!group(c.unselected_source_app_key_conflicts))fail('result_refused');
 return {status:'aggregate_observation',source:r.source,target:r.target,conflicts:c,email_is_identity_proof:false,other_identity_mappings_inferred:false,
  historical_references_verified:false,provider_or_device_state_verified:false,quiescence_proven:false,write_authorized:false};
}
