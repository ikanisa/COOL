import {ApiError,digest,id,integer,json,now,readJson,requirePermission,rows,stableJson,uuid} from './core.js';
import {assertMutationAdmission} from './mutations.js';
import {accountDatabase,adminAccountSession,adminCanonicalActor} from './admin_accounts.js';

// This is the existing fixed CollectDiagnostics boundary, not an exception,
// stack, request, breadcrumb, URL, identity or arbitrary-metadata collector.
export const diagnosticSeverities=Object.freeze({
 startupStarted:'info',startupWaiting:'info',startupTimedOut:'warning',
 startupFailed:'error',startupReady:'info',frameworkFailure:'error',
 platformFailure:'error',diagnosticsSuppressed:'warning',
});
const fields=['collect_diagnostic','code','severity','surface','environment','build_version','attempt','elapsed_ms','report_id','source_revision','fingerprint','occurrences'].sort();
const exact=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&JSON.stringify(Object.keys(value).sort())===JSON.stringify([...keys].sort());
const bad=()=>{throw new ApiError(400,'invalid_diagnostic','The diagnostic report is invalid.');};
const sameAccount=(a,b)=>['id','principal_id','auth_user_id','auth_session_id','token_hash','public_id','origin','auth_version','role'].every(k=>a[k]===b[k]);
export const diagnosticFingerprint=report=>digest(['collect.diagnostic.v1',report.surface,report.environment,report.build_version,report.source_revision,report.code].join('|'));

export async function validateDiagnosticBatch(body,surface){
 if(!exact(body,['contract_version','reports'])||body.contract_version!==1||!Array.isArray(body.reports)||body.reports.length<1||body.reports.length>8)bad();
 const result=[],seen=new Set();
 for(const value of body.reports){
  if(!exact(value,fields)||value.collect_diagnostic!==1||!Object.hasOwn(diagnosticSeverities,value.code)||
   value.severity!==diagnosticSeverities[value.code]||value.surface!==surface||!['member','admin'].includes(surface)||
   !['local','development','staging','production','unknown'].includes(value.environment)||
   typeof value.build_version!=='string'||value.build_version.length>32||! /^(?:unknown|\d+\.\d+\.\d+(?:\+\d+)?)$/.test(value.build_version)||
   typeof value.source_revision!=='string'||! /^(?:unknown|[a-f0-9]{40}|[a-f0-9]{64})$/.test(value.source_revision)||
   typeof value.report_id!=='string'||! /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(value.report_id)||
   seen.has(value.report_id)||value.fingerprint!==await diagnosticFingerprint(value))bad();
  integer(value.attempt,'diagnostic_attempt',1,1000);integer(value.elapsed_ms,'diagnostic_elapsed',0,86400000);integer(value.occurrences,'diagnostic_occurrences',1,64);
  seen.add(value.report_id);result.push({...value,payload_sha256:await digest(stableJson(value))});
 }
 return result;
}

export async function ingestClientDiagnostics(request,env,actor,{account=null}={}){
 if(!actor?.userId||!actor?.sessionId||!['member','admin'].includes(actor.surface))throw new ApiError(401,'unauthenticated','Sign in to send diagnostics.');
 if(actor.surface==='admin'&&(!account||account.principal_id!==actor.userId||account.auth_session_id!==actor.sessionId))throw new ApiError(403,'admin_session_required','Open the Admin workspace.');
 const reports=await validateDiagnosticBatch(await readJson(request,12288),actor.surface);
 const timestamp=Math.floor(Date.now()/1000),hour=Math.floor(timestamp/3600),expires=timestamp+86400;
 // Quota accounting uses a one-way principal hash in the existing rate table.
 // No principal/session/device identifier is stored on a diagnostic report.
 const principalKey='client_diag:v1:user:'+await digest(actor.userId),globalKey='client_diag:v1:global';
 const guard=id(),writes=[
  env.DB.prepare('DELETE FROM client_diagnostic_reports WHERE report_id IN (SELECT report_id FROM client_diagnostic_reports WHERE expires_at<=? ORDER BY expires_at,report_id LIMIT 1000)').bind(timestamp),
  env.DB.prepare("DELETE FROM admin_rate_limits WHERE key_hash LIKE 'client_diag:v1:%' AND expires_at<=?").bind(timestamp),
 ];
 for(const key of [principalKey,globalKey])writes.push(env.DB.prepare(`INSERT INTO admin_rate_limits(key_hash,bucket,count,expires_at) VALUES(?,?,1,?)
  ON CONFLICT(key_hash,bucket) DO UPDATE SET count=admin_rate_limits.count+1`).bind(key,hour,(hour+2)*3600));
 writes.push(env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN
  (SELECT count FROM admin_rate_limits WHERE key_hash=? AND bucket=?)<=16 AND
  (SELECT count FROM admin_rate_limits WHERE key_hash=? AND bucket=?)<=256 THEN 1 ELSE 0 END`).bind(guard,principalKey,hour,globalKey,hour));
 for(const r of reports){
  writes.push(env.DB.prepare(`INSERT INTO client_diagnostic_reports(report_id,payload_sha256,surface,environment,build_version,source_revision,code,fingerprint,occurrences,attempt,elapsed_ms,received_hour,expires_at)
   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(report_id) DO NOTHING`).bind(r.report_id,r.payload_sha256,r.surface,r.environment,r.build_version,r.source_revision,r.code,r.fingerprint,r.occurrences,r.attempt,r.elapsed_ms,hour*3600,expires));
  const identity=id();writes.push(env.DB.prepare('INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM client_diagnostic_reports WHERE report_id=? AND payload_sha256=?) THEN 1 ELSE 0 END').bind(identity,r.report_id,r.payload_sha256));
  writes.push(env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(identity));
 }
 writes.push(env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(guard));
 try{await assertMutationAdmission(env,actor,writes);}catch(error){
  // Guard rejection discloses no retained report or quota identity. Conflicting
  // replays and quota pressure both back off, without returning false success.
  if(error?.code==='stale_state'||/admin_bridge_state/.test(String(error?.message??'')))throw new ApiError(429,'diagnostic_capacity_limited','Diagnostics are temporarily limited.');
  throw error;
 }
 return json({contract_version:1,accepted:true},202);
}

export async function clientDiagnosticGroups(env,timestamp=Math.floor(Date.now()/1000)){
 return rows(env,`SELECT surface,environment,build_version,source_revision,code,fingerprint,
  sum(occurrences)::bigint AS occurrences,count(*)::bigint AS reports,max(received_hour) AS last_received_hour
  FROM client_diagnostic_reports WHERE expires_at>? GROUP BY surface,environment,build_version,source_revision,code,fingerprint
  ORDER BY max(received_hour) DESC,fingerprint ASC LIMIT 65`,timestamp);
}

export async function readClientDiagnostics(request,env,actor,account){
 requirePermission(actor,'system_health.read');
 if(!account?.permissions?.includes('system_health.read'))throw new ApiError(403,'permission_required','Diagnostics are unavailable to this account.');
 const found=await clientDiagnosticGroups(env);
 const latest=await adminAccountSession(request,env);
 if(!sameAccount(account,latest))throw new ApiError(403,'admin_access_changed','Refresh your current Admin access.');
 const current=await adminCanonicalActor(request,env,latest,'system_health.read');
 requirePermission(current,'system_health.read');
 await assertMutationAdmission(accountDatabase(env,latest,'system_health.read'),current,[],{permission:'system_health.read'});
 return json({contract_version:1,window_hours:24,retention_hours:24,checked_at:now(),limit:64,truncated:found.length>64,
  groups:found.slice(0,64).map(r=>({surface:r.surface,environment:r.environment,build_version:r.build_version,source_revision:r.source_revision,code:r.code,severity:diagnosticSeverities[r.code],fingerprint:r.fingerprint,
   occurrences:integer(r.occurrences,'diagnostic_count',1),reports:integer(r.reports,'diagnostic_reports',1),last_received_hour:new Date(integer(r.last_received_hour,'diagnostic_hour')*1000).toISOString()}))});
}

export async function clientDiagnosticsRoute(request,env,actor,{account=null}={}){
 const url=new URL(request.url);
 if(!['/v1/diagnostics','/api/admin/diagnostics'].includes(url.pathname))return null;
 if(url.search)throw new ApiError(400,'invalid_request','Diagnostics do not accept query parameters.');
 if(request.method==='POST')return ingestClientDiagnostics(request,env,actor,{account});
 if(request.method==='GET'&&url.pathname==='/api/admin/diagnostics'&&account)return readClientDiagnostics(request,env,actor,account);
 throw new ApiError(405,'method_not_allowed','This diagnostics method is unavailable.');
}

// Existing authenticated maintenance may remove expired safe diagnostics. No
// provider calls, new scheduler, or financial work is introduced by cleanup.
export async function cleanupClientDiagnostics(env,{limit=1000}={}){
 integer(limit,'diagnostic_cleanup_limit',1,1000);const timestamp=Math.floor(Date.now()/1000);
 const result=await env.DB.batch([
  env.DB.prepare('DELETE FROM client_diagnostic_reports WHERE report_id IN (SELECT report_id FROM client_diagnostic_reports WHERE expires_at<=? ORDER BY expires_at,report_id LIMIT ?)').bind(timestamp,limit),
  env.DB.prepare("DELETE FROM admin_rate_limits WHERE key_hash LIKE 'client_diag:v1:%' AND expires_at<=?").bind(timestamp),
 ]);
 return {status:'complete',removed:result[0].meta?.changes??0,limit};
}
