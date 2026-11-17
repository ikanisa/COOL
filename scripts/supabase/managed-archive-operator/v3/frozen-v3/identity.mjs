// Session observation: no data mutation or cancellation is performed here.
import {readCapture,recordServerClosure} from './journal.mjs';
import {isManagedReconciliationPeer} from '../../current-pg-transfer/managed-target.mjs';
import {isSyntheticReconciliationSocket} from '../../current-pg-transfer/reconcile.mjs';
const fail=code=>{throw Object.assign(Error(code),{captureCode:code});};
const stamp="to_char(%s AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')";
const startStamp=stamp.replace('%s','pg_postmaster_start_time()');
const backendStamp=stamp.replace('%s','backend_start');
function guard(c,{mode,database}){
 const p=c?.connectionParameters,s=c?.connection?.stream;
 if(!c||!s?.destroy||typeof c.query!=='function'||p?.database!==database||p?.user!=='postgres'||p.replication||p.options||p.binary)fail('SESSION_REFUSED');
 if(mode==='managed'){if(database!=='postgres'||!isManagedReconciliationPeer(p,s))fail('SESSION_REFUSED');}
 else if(mode==='synthetic'){if(!/^collect_archive_[a-f0-9]{24}_test$/.test(database)||!isSyntheticReconciliationSocket(p.host))fail('SESSION_REFUSED');}
 else fail('SESSION_REFUSED');
}
function query(c,deadline){return async(...args)=>{
 const ms=deadline-Date.now();if(ms<=0){c.connection.stream.destroy();fail('QUERY_UNKNOWN');}let timer;
 try{return await Promise.race([Promise.resolve().then(()=>c.query(...args)),new Promise((_,reject)=>{timer=setTimeout(()=>{c.connection.stream.destroy();reject(Object.assign(Error('QUERY_UNKNOWN'),{captureCode:'QUERY_UNKNOWN'}));},Math.min(ms,5000));})]);}
 finally{clearTimeout(timer);}
};}
async function stop(c){try{c.connection?.stream?.destroy();}catch{}try{await Promise.race([c.end(),new Promise(r=>setTimeout(r,1500))]);}catch{}}
async function connectBounded(factory,deadline){
 let expired=false,timer;const pending=Promise.resolve().then(factory);
 pending.then(c=>{if(expired)void stop(c);},()=>{});
 try{return await Promise.race([pending,new Promise((_,reject)=>{timer=setTimeout(()=>{expired=true;reject(Object.assign(Error('CONNECT_UNKNOWN'),{captureCode:'CONNECT_UNKNOWN'}));},Math.max(0,deadline-Date.now()));})]);}
 finally{clearTimeout(timer);}
}
export async function identifyCaptureBackend(client,{mode,database,applicationName,timeoutMs=5000}={}){
 guard(client,{mode,database});if(!/^collect_cap_[a-f0-9]{32}$/.test(applicationName??'')||client.connectionParameters.application_name!==applicationName)fail('SESSION_REFUSED');
 const q=query(client,Date.now()+timeoutMs);let begun=false;
 try{
  const begin=await q('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');begun=true;if(begin.command!=='BEGIN')fail('SESSION_REFUSED');
  await q("SET LOCAL search_path=pg_catalog,pg_temp; SET LOCAL statement_timeout='4s'");await q('SELECT pg_stat_clear_snapshot()');
  const result=await q(`SELECT current_database() database,session_user session_user,current_user active_user,
   current_setting('application_name') application_name,current_setting('server_version_num') version,
   current_setting('cluster_name') cluster,inet_server_addr() IS NULL socket,pg_backend_pid()::int pid,
   (SELECT system_identifier::text FROM pg_control_system()) system_identifier,${startStamp} postmaster_start,
   (SELECT ${backendStamp} FROM pg_stat_activity WHERE pid=pg_backend_pid()) backend_start`);
  const x=result.rows?.[0];
  if(result.rows?.length!==1||x.database!==database||x.session_user!=='postgres'||x.active_user!=='postgres'||x.application_name!==applicationName||
   !/^17[0-9]{4}$/.test(x.version??'')||x.pid!==client.processID||!Number.isSafeInteger(x.pid)||
   (mode==='synthetic'?(x.cluster!=='collect_archive_next_fixture'||!x.socket):x.socket))fail('SESSION_REFUSED');
  if((await q('ROLLBACK')).command!=='ROLLBACK')fail('SESSION_REFUSED');begun=false;
  return {pid:x.pid,backendStart:x.backend_start,systemIdentifier:x.system_identifier,postmasterStart:x.postmaster_start,
   database:x.database,sessionUser:x.session_user,applicationName:x.application_name};
 }catch(e){if(begun)try{await q('ROLLBACK');}catch{}throw e;}
}
async function sample(c,record,mode,deadline){
 guard(c,{mode,database:record.database});const q=query(c,deadline);let begun=false;
 try{
  const begin=await q('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');begun=true;if(begin.command!=='BEGIN')fail('OBSERVATION_UNKNOWN');
  await q("SET LOCAL search_path=pg_catalog,pg_temp; SET LOCAL statement_timeout='4s'");
  const who=(await q(`SELECT current_database() database,session_user session_user,current_user active_user,
   pg_backend_pid()::int pid,current_setting('server_version_num') version,current_setting('cluster_name') cluster,inet_server_addr() IS NULL socket,
   (SELECT system_identifier::text FROM pg_control_system()) system_identifier,${startStamp} postmaster_start,
   ((SELECT rolsuper FROM pg_roles WHERE rolname=current_user) OR pg_has_role(current_user,'pg_read_all_stats','USAGE')) readable`)).rows?.[0];
  if(!who||who.database!==record.database||who.session_user!==record.sessionUser||who.active_user!==record.sessionUser||
   who.system_identifier!==record.systemIdentifier||who.postmaster_start!==record.postmasterStart||!/^17[0-9]{4}$/.test(who.version??'')||
   who.readable!==true||!Number.isSafeInteger(who.pid)||who.pid===record.pid||who.pid!==c.processID||
   (mode==='synthetic'?(who.cluster!=='collect_archive_next_fixture'||!who.socket):who.socket))fail('OBSERVATION_UNKNOWN');
  // pg_stat_activity may cache a transaction's earlier view even under READ
  // COMMITTED. Clear it immediately before the combined activity/locks read.
  await q('SELECT pg_stat_clear_snapshot()');
  const state=(await q(`SELECT (SELECT count(*)::int FROM pg_stat_activity WHERE pid=$1) pid_hits,
   (SELECT count(*)::int FROM pg_stat_activity WHERE application_name=$2) name_hits,
   (SELECT count(*)::int FROM pg_locks WHERE pid=$1) lock_hits`,[record.pid,record.applicationName])).rows?.[0];
  if(!state||state.pid_hits!==0||state.name_hits!==0||state.lock_hits!==0)fail('OBSERVATION_UNKNOWN');
  if((await q('ROLLBACK')).command!=='ROLLBACK')fail('OBSERVATION_UNKNOWN');begun=false;return who.pid;
 }finally{if(begun)try{await q('ROLLBACK');}catch{}await stop(c);}
}
// connectObserver is a trusted test/adapter boundary, never a credential source.
// Managed CLI must itself construct exact pinned TLS clients for each call.
export async function reconcileCaptureClosure({root,manifestSha256,mode,connectObserver,timeoutMs=15000}={}){
 if(!['synthetic','managed'].includes(mode)||typeof connectObserver!=='function'||!Number.isSafeInteger(timeoutMs)||timeoutMs<1000||timeoutMs>30000)return {status:'unknown_do_not_retry'};
 let job;try{job=await readCapture(root,manifestSha256);}catch{return {status:'unknown_do_not_retry'};}
 const deadline=Date.now()+timeoutMs;let first,second;
 try{
  first=await sample(await connectBounded(connectObserver,deadline),job.backend,mode,deadline);
  await new Promise(r=>setTimeout(r,250));
  second=await sample(await connectBounded(connectObserver,deadline),job.backend,mode,deadline);
  if(first===second||Date.now()>=deadline)fail('OBSERVATION_UNKNOWN');
  await recordServerClosure(job);return {status:'actor_and_server_closure_observed',writeAuthorized:false};
 }catch{return {status:'unknown_do_not_retry',writeAuthorized:false};}
}
