// Current reviewed chain port of the retained native control scenarios; original13 runner is unchanged.
import postgres from 'npm:postgres@3.4.7';
import {readFile} from 'node:fs/promises';
import {installCurrentFixtureAdditions,validateCurrentFixtureDescriptor,reviewedCurrentMigrations} from './self-hosted-current-schema.mjs';
import {pathToFileURL,fileURLToPath} from 'node:url';
const ROOT=fileURLToPath(new URL('../../../',import.meta.url));
if(Deno.env.get('COLLECT_CI_SYNTHETIC')!=='true')throw Error('EXPLICIT_SYNTHETIC_CI_REQUIRED');
const descriptor=JSON.parse(await readFile(Deno.env.get('COLLECT_CONTROL_FIXTURE_DESCRIPTOR')!,'utf8'));
const target=validateCurrentFixtureDescriptor(descriptor,{purpose:'backend'}),SOURCE=descriptor.source_sha256;
const rtTarget=new URL(descriptor.control_runtime_url);
if(rtTarget.protocol!==target.protocol||rtTarget.hostname!==target.hostname||rtTarget.port!==target.port||rtTarget.pathname!==target.pathname||
 !/^collect_control_[a-f0-9]{12}$/.test(rtTarget.username)||!/^([a-f0-9]{48})$/.test(rtTarget.password)||rtTarget.search||rtTarget.hash)
 throw Error('BOOTSTRAP_OWNED_CONTROL_RUNTIME_REQUIRED');
const role=rtTarget.username;
let installed:any;
for(const k of Object.keys(Deno.env.toObject()))if(k.startsWith('PG'))Deno.env.delete(k);
const owner=postgres(target.href,{max:1,prepare:false,ssl:false,connect_timeout:5,onnotice:()=>{}});
const receipts:any[]=[];let checks=0,stage='setup';const pools:any[]=[];
const need=(value:unknown,code:string)=>{checks++;if(!value)throw Error(code);};
const pause=(ms:number)=>new Promise<void>(r=>setTimeout(r,ms));
const defer=()=>Promise.withResolvers<void>();
const fenceRuntime:any=await import('../../../supabase/functions/_shared/application-fence.js');
const {sqlFenceBackend,openApplicationWork,reserveDatabaseConnection}=fenceRuntime;
const {leaseOwnedControlPool}=await import('../../../supabase/functions/_shared/postgres.js');
async function status(){return(await owner.unsafe('SELECT private.collect_fence_owner_status() AS result'))[0].result;}
async function locks(){return(await owner.unsafe("SELECT count(*)::int AS count FROM pg_locks WHERE database=(SELECT oid FROM pg_database WHERE datname=current_database()) AND locktype='advisory' AND classid=7346371 AND objid=1 AND objsubid=2 AND mode='ShareLock' AND granted"))[0].count;}
async function clients(){return(await owner.unsafe("SELECT count(*)::int AS count,count(*) FILTER(WHERE state='idle')::int AS idle,count(*) FILTER(WHERE state='idle in transaction')::int AS idle_transaction FROM pg_stat_activity WHERE usename=$1",[role]))[0];}
async function worker(id:string){const m=await import(pathToFileURL(ROOT+'supabase/functions/_shared/postgres.js').href+'?worker='+id);const sql=m.connection(rtTarget.href),control=m.fenceConnection(rtTarget.href);pools.push(sql,control);return{sql,control,backend:sqlFenceBackend(sql,control)};}
async function stopPools(){const ended=pools.splice(0);await Promise.all(ended.map(p=>p.end({timeout:1})));await pause(40);}
async function rt(fn:()=>Promise<any>){try{return await fn();}catch(e){return{error:e};}}
try{
 const identity=(await owner.unsafe("SELECT current_database() AS db,current_user AS actor,current_setting('server_version_num')::int AS version,inet_server_port() AS port,current_setting('max_connections')::int AS maximum,current_setting('superuser_reserved_connections')::int AS super_reserved,current_setting('reserved_connections')::int AS reserved"))[0];
 need(identity.db===target.pathname.slice(1)&&identity.actor==='postgres'&&Math.floor(identity.version/10000)===17&&identity.port===Number(target.port),'IDENTITY');
 const ordinaryCeiling=identity.maximum-identity.super_reserved-identity.reserved;need(identity.maximum===60&&identity.super_reserved===3&&identity.reserved===0&&ordinaryCeiling===57,'ACTUAL_60_3_0_AND_ORDINARY57_REQUIRED');
 installed=await installCurrentFixtureAdditions(owner);
 // Only the dedicated fixture bootstrap may create/grant this login. The
 // normal owner retains ADMIN=false on collect_runtime, matching production.
 const runtimeRole=(await owner.unsafe('SELECT rolcanlogin,rolinherit,rolsuper,rolbypassrls,rolcreatedb,rolcreaterole,rolreplication FROM pg_roles WHERE rolname=$1',[role]))[0];
 need(runtimeRole?.rolcanlogin===true&&['rolinherit','rolsuper','rolbypassrls','rolcreatedb','rolcreaterole','rolreplication'].every(key=>runtimeRole[key]===false),'NORMAL_CONTROL_LOGIN_REQUIRED');
 const memberships=await owner.unsafe('SELECT p.rolname,m.admin_option,m.inherit_option,m.set_option FROM pg_auth_members m JOIN pg_roles p ON p.oid=m.roleid JOIN pg_roles u ON u.oid=m.member WHERE u.rolname=$1',[role]);
 need(memberships.length===1&&memberships[0].rolname==='collect_runtime'&&memberships[0].admin_option===false&&memberships[0].inherit_option===false&&memberships[0].set_option===true,'EXACT_CONTROL_SET_ROLE_REQUIRED');
 const initial=await status();need(initial.mode==='open'&&initial.activeAdmissions===0&&initial.resourceLimits.activeWorkLimit===8,'INITIAL_OPEN8');
 receipts.push({scenario:'reviewed_current_chain_fixture',migrations:installed.migrations,identity:{version:identity.version,ordinary_max:ordinaryCeiling,maximum:identity.maximum,superuser_reserved:identity.super_reserved,other_reserved:identity.reserved},managed_provider_calls:0});

 stage='candidate_eight';
 const candidate=await worker('eight');const before=performance.now();
 const works=await Promise.all(Array.from({length:8},()=>openApplicationWork({backend:candidate.backend,sourceSha256:SOURCE,kind:'http_admin'})));const admittedMs=performance.now()-before;
 need(admittedMs<5000&&await locks()===8,'EIGHT_REAL_LEASES');
 const gates=works.map(()=>defer()),dispatches=works.map((w:any,i:number)=>w.dispatch('synthetic',()=>gates[i].promise));await pause(20);
 const capacityBefore=(await owner.unsafe('SELECT count(*)::int AS n FROM private.collect_fence_admissions'))[0].n,ninthId=crypto.randomUUID();const ninth=await rt(()=>openApplicationWork({backend:candidate.backend,sourceSha256:SOURCE,kind:'http_collect',id:ninthId}));
 need(ninth.error?.code==='application_fence_unavailable','NINTH_REFUSED');need((await owner.unsafe('SELECT count(*)::int AS n FROM private.collect_fence_admissions'))[0].n===capacityBefore,'NINTH_NO_ROW');
 let rawCapacity=false;try{await candidate.backend.register(ninthId,SOURCE,'http_collect');}catch(e){rawCapacity=(e as any)?.message==='collect_fence_capacity';}need(rawCapacity,'NINTH_ACTUAL_SQL_CAPACITY');
 const op=crypto.randomUUID();await owner.unsafe('SELECT private.collect_fence_begin_quiesce($1::uuid,1,$2)',[op,SOURCE]);
 const denied=await rt(()=>openApplicationWork({backend:candidate.backend,sourceSha256:SOURCE,kind:'jobs'}));need(denied.error?.code==='application_fenced','QUIESCE_DENIED');
 const finishFlags=works.map(()=>false),finishes=works.map((w:any,i:number)=>w.finish().then((v:any)=>{finishFlags[i]=true;return v;}));await pause(5200);
 need(finishFlags.every(x=>!x)&&await locks()===8&&(await status()).activeAdmissions===8,'STALLED_ALL_RETAINED_AFTER5S');
 async function drainTimeout(){let timedOut=false;try{await owner.begin(async tx=>{await tx.unsafe("SET LOCAL lock_timeout='100ms'");await tx.unsafe('SELECT private.collect_fence_drain($1::uuid,1,$2)',[op,SOURCE]);});}catch(e){timedOut=(e as any)?.code==='55P03';}need(timedOut,'DRAIN_REAL_TIMEOUT');}
 await drainTimeout();for(let i=0;i<7;i++)gates[i].resolve();await Promise.all(dispatches.slice(0,7));await Promise.all(finishes.slice(0,7));
 need(await locks()===1&&(await status()).activeAdmissions===1&&!finishFlags[7],'LAST_ORIGINAL_RETAINED');await drainTimeout();gates[7].resolve();await dispatches[7];await finishes[7];
 const drained=(await owner.unsafe('SELECT private.collect_fence_drain($1::uuid,1,$2) AS result',[op,SOURCE]))[0].result;need(drained.mode==='fenced'&&drained.applicationFenceComplete&&await locks()===0,'ALL_DRAINED');
 const replay=await rt(()=>openApplicationWork({backend:candidate.backend,sourceSha256:SOURCE,kind:'http_admin',id:works[0].id}));need(replay.error,'NO_REPLAY_WHILE_FENCED');
 const released=(await owner.unsafe('SELECT private.collect_fence_release($1::uuid,1,$2) AS result',[crypto.randomUUID(),SOURCE]))[0].result;need(released.mode==='open'&&released.epoch===2,'RELEASE2');
 const replay2=await rt(()=>openApplicationWork({backend:candidate.backend,sourceSha256:SOURCE,kind:'http_admin',id:works[0].id}));need(replay2.error,'ORIGINAL_KEY_NO_REPLAY');
 receipts.push({scenario:'candidate_same_isolate_eight',admission_ms:Math.round(admittedMs),leases:8,all_originals_held_beyond5s:true,ninth_refused_by_actual_SQL_capacity:true,new_registration_denied_during_quiesce:true,drain_waited_all8:true,last_original_stall_blocked_drain:true,exact_original_keys_never_replayed:true,actual_business_pool_max:candidate.sql.options.max,actual_control_allocator_slots:candidate.control.capacity,actual_control_driver_pool_max:1});await stopPools();

 stage='native_shutdown_cannot_end_held_work';
 const shutdownWorker=await worker('held-shutdown'),rollbackGate=defer();let protectedEnds=0,requestedRollbacks=0;
 const protectedControl=leaseOwnedControlPool(()=>{const p:any=postgres(rtTarget.href,{max:1,prepare:false,ssl:false,onnotice:()=>{}}),reserve=p.reserve.bind(p),end=p.end.bind(p);p.end=(...args:any[])=>{protectedEnds++;return end(...args);};p.reserve=async()=>{const tx=await reserve();return new Proxy(tx,{get(target,key){if(key==='unsafe')return async(text:string,values?:any[])=>{if(text==='ROLLBACK'){requestedRollbacks++;await rollbackGate.promise;}return target.unsafe(text,values);};return Reflect.get(target,key,target);}});};return p;});pools.push(protectedControl);
 const protectedBackend=sqlFenceBackend(shutdownWorker.sql,protectedControl),protectedWork=await openApplicationWork({backend:protectedBackend,sourceSha256:SOURCE,kind:'http_admin'});
 const heldShutdown=await rt(()=>protectedControl.end({timeout:0}));need(heldShutdown.error&&protectedEnds===0&&await locks()===1,'SHUTDOWN_CANNOT_END_HELD_WORK');
 const protectedFinish=protectedWork.finish();await pause(50);const rollbackShutdown=await rt(()=>protectedControl.end({timeout:0}));need(rollbackShutdown.error&&requestedRollbacks===1&&protectedEnds===0&&await locks()===1,'SHUTDOWN_CANNOT_END_ORIGINAL_PENDING_ROLLBACK');
 rollbackGate.resolve();await protectedFinish;need(await protectedControl.end({timeout:0})===undefined&&protectedEnds===1&&await locks()===0,'ORIGINAL_ACK_ALONE_RETIRES_POOL');
 receipts.push({scenario:'actual_driver_shutdown_observes_only',fault:'original_ROLLBACK_dispatch_delayed_in_controlled_boundary',poolShutdown_while_WORK_held:false,poolShutdown_while_original_rollback_pending:false,physical_pool_end_calls_before_original_ACK:0,real_WORK_lock_retained:true,physical_pool_end_calls_after_original_ACK:protectedEnds,poolShutdown_after_original_ACK:true});await stopPools();

 stage='native_delayed_cleanup_ack';
 const late=await worker('late-ack'),ack=defer();let rollbackCalls=0,releases=0,firstReservation=true;
 const delayedControl={async reserve(){const tx=await late.control.reserve(),isOriginal=firstReservation;firstReservation=false;return new Proxy(tx,{get(target,key){if(key==='unsafe')return async(text:string,values?:any[])=>{if(isOriginal&&text==='ROLLBACK'){rollbackCalls++;await target.unsafe(text,values);await ack.promise;return [];}return target.unsafe(text,values);};if(key==='release')return()=>{releases++;return target.release();};return Reflect.get(target,key,target);}});}};
 const lateBackend=sqlFenceBackend(late.sql,delayedControl),lateWork=await openApplicationWork({backend:lateBackend,sourceSha256:SOURCE,kind:'http_admin'});
 const heldSeven=await Promise.all(Array.from({length:7},()=>late.control.reserve()));let finishedLate=false;const lateFinish=lateWork.finish().then((v:any)=>{finishedLate=true;return v;});
 await pause(50);const ninthLease=await rt(()=>reserveDatabaseConnection(delayedControl));need(ninthLease.error?.code==='application_fence_unavailable','NATIVE_LATE_RESERVE_BOUNDED');await lateFinish;
 need(finishedLate&&rollbackCalls===1&&releases===0&&(await lateBackend.status(lateWork.id)).state==='settled','CLEANUP_ACK_NOT_REUSED');
 ack.resolve();await pause(100);need(rollbackCalls===1&&releases===1&&late.control.pendingReservations===0,'ORIGINAL_ACK_RELEASE_AND_QUEUED_WAITER_EXPIRED');heldSeven.forEach(tx=>tx.release());
 receipts.push({scenario:'actual_driver_delayed_rollback_ack',fault:'actual_SQL_ROLLBACK_acknowledgement_delayed_in_test_boundary',original_rollback_calls:rollbackCalls,reservation_releases_before_ack:0,reservation_releases_after_ack:releases,queued_waiter_expired5s:true,expired_waiter_never_constructed_pool:true,original_cleanup_not_replayed:true});await stopPools();

 stage='native_rejected_cleanup_ack';
 const quarantine=await worker('rejected-ack'),quarantineRaw:any[]=[];quarantine.control=leaseOwnedControlPool(()=>{const p=postgres(rtTarget.href,{max:1,prepare:false,ssl:false,onnotice:()=>{}});quarantineRaw.push(p);return p;});pools.push(quarantine.control);let quarantineRollbacks=0,quarantineReleases=0;
 const rejectedControl={async reserve(){const tx=await quarantine.control.reserve();return new Proxy(tx,{get(target,key){if(key==='unsafe')return async(text:string,values?:any[])=>{if(text==='ROLLBACK'){quarantineRollbacks++;await target.unsafe(text,values);throw Error('SYNTHETIC_ACK_LOSS');}return target.unsafe(text,values);};if(key==='release')return()=>{quarantineReleases++;return target.release();};return Reflect.get(target,key,target);}});}};
 const rejectedBackend=sqlFenceBackend(quarantine.sql,rejectedControl),rejectedWork=await openApplicationWork({backend:rejectedBackend,sourceSha256:SOURCE,kind:'http_admin'});await rejectedWork.finish();
 const seven=await Promise.all(Array.from({length:7},()=>quarantine.control.reserve()));const quarantineWait=await rt(()=>reserveDatabaseConnection(quarantine.control));need(quarantineWait.error?.code==='application_fence_unavailable'&&quarantineRollbacks===1&&quarantineReleases===0,'ACTUAL_DRIVER_QUARANTINE');
 need((await rejectedBackend.status(rejectedWork.id)).state==='settled'&&await locks()===0,'EXACT_CLOSE_PRESERVED_ON_ACK_LOSS');seven.forEach(tx=>tx.release());await pause(100);
 need(quarantineReleases===0,'NO_QUARANTINE_RELEASE_AFTER_OTHER_CAPACITY');
 const quarantineShutdown=await rt(()=>quarantine.control.end({timeout:0}));need(quarantineShutdown.error,'QUARANTINED_SHUTDOWN_REJECTS');pools.splice(pools.indexOf(quarantine.control),1);await quarantineRaw[0].end({timeout:0});
 receipts.push({poolShutdown:false,administrative_fixture_teardown:'captured_original_raw_driver_handle_closed_after_assertions_only',scenario:'actual_driver_rejected_rollback_ack',fault:'actual_SQL_ROLLBACK_acknowledgement_rejected_in_test_boundary',original_rollback_calls:quarantineRollbacks,quarantined_reservation_releases:quarantineReleases,exact_durable_close_preserved:true,ninth_reservation_refused5s:true});await stopPools();

 stage='native_pool_end_ack';
 const endedAck=defer();let endCalls=0,createdPools=0;
 const endControlled=leaseOwnedControlPool(()=>{createdPools++;const p:any=postgres(rtTarget.href,{max:1,prepare:false,ssl:false,onnotice:()=>{}}),end=p.end.bind(p);p.end=(...args:any[])=>{endCalls++;return end(...args).then(()=>endedAck.promise);};return p;});pools.push(endControlled);
 const endHeld=await Promise.all(Array.from({length:8},()=>endControlled.reserve()));need(createdPools===8,'ALLOCATOR_LAZY_LOCAL8');endHeld.forEach(tx=>tx.release());await pause(50);
 const endQueued=await rt(()=>reserveDatabaseConnection(endControlled));need(endQueued.error?.code==='application_fence_unavailable'&&createdPools===8&&endCalls===8,'NO_SLOT_REUSE_BEFORE_ORIGINAL_END_ACK');
 await pause(20);need(endControlled.pendingReservations===0,'EXPIRED_QUEUE_REMOVED');endedAck.resolve();await pause(150);need(createdPools===8&&endCalls===8,'EXPIRED_WAITER_NEVER_CONSTRUCTS_POOL');const afterEndAck=await endControlled.reserve();afterEndAck.release();await pause(100);need(createdPools===9&&endCalls===9,'END_ACK_FREES_SLOT_FOR_NEW_REQUEST');
 receipts.push({scenario:'actual_driver_original_pool_end_ack',fault:'actual_driver_end_acknowledgement_delayed_in_test_boundary',lazy_created_max_before_ack:8,queued_waiter_refused5s:true,original_end_calls_before_ack:8,expired_queued_waiter_never_constructed_pool:true,new_request_pool_retired_after_ack:true});await stopPools();

 stage='native_allocated_late_reservation';
 const allocatedAck=defer();let allocatedPools=0,allocatedReleases=0;
 const allocated=leaseOwnedControlPool(()=>{allocatedPools++;const p:any=postgres(rtTarget.href,{max:1,prepare:false,ssl:false,onnotice:()=>{}}),reserve=p.reserve.bind(p);p.reserve=async()=>{const tx=await reserve();await allocatedAck.promise;return new Proxy(tx,{get(target,key){if(key==='release')return()=>{allocatedReleases++;return target.release();};return Reflect.get(target,key,target);}});};return p;});pools.push(allocated);
 const allocatedLate=await rt(()=>reserveDatabaseConnection(allocated));need(allocatedLate.error?.code==='application_fence_unavailable'&&allocatedPools===1&&allocatedReleases===0,'ALLOCATED_LATE_ACK_BOUNDED');allocatedAck.resolve();await pause(150);need(allocatedReleases===1&&allocated.pendingReservations===0,'ALLOCATED_LATE_CONNECTION_RELEASED_ONCE');
 receipts.push({scenario:'actual_driver_allocated_late_reservation',fault:'actual_driver_reserve_acknowledgement_delayed_after_allocation',observation_timeout5s:true,already_allocated_pools:allocatedPools,late_reservation_releases:allocatedReleases,SQL_BEGIN_after_timeout:0});await stopPools();

 stage='lease_owned_warm_envelope';
 const warm=[];
 for(let i=0;i<5;i++){
  const w=await worker('warm'+i);const reserved=await Promise.all(Array.from({length:4},()=>w.sql.reserve()));reserved.forEach(tx=>tx.release());
  const attempts=await Promise.all(Array.from({length:8},()=>rt(()=>openApplicationWork({backend:w.backend,sourceSha256:SOURCE,kind:'http_admin'}))));const good=attempts.filter(x=>!x.error),failed=attempts.filter(x=>x.error);await Promise.all(good.map(x=>x.finish()));
  let count=await clients();const until=performance.now()+1500;while(count.count!==4*(i+1)&&performance.now()<until){await pause(20);count=await clients();}
  const state=await status();need(state.activeAdmissions===0&&state.unresolvedAdmissions===0&&good.length===8&&failed.length===0,'WARM_ALL8_NO_ACTIVE');need(count.count===4*(i+1)&&count.idle===count.count&&count.idle_transaction===0,'ZERO_RETAINED_WARM_CONTROL_SOCKETS');
  warm.push({worker:i+1,admitted:good.length,refused:failed.length,clients:count.count,retained_business:4*(i+1),retained_control:count.count-4*(i+1),idle:count.idle,idle_transaction:count.idle_transaction,active_work:state.activeAdmissions});
 }
 const beforeIdle=performance.now();let remaining=(await clients()).count;while(remaining&&performance.now()-beforeIdle<25000){await pause(300);remaining=(await clients()).count;}
 need(remaining===0&&await locks()===0,'TWENTY_SECOND_BUSINESS_IDLE_DRAIN');
 receipts.push({scenario:'lease_owned_control_warm_envelope',endpoint:'direct_native_PG_not_transaction_pooler',workers:warm,ordinary_cap:ordinaryCeiling,global_active_work_limit:8,proof:'five sequential isolates each admit8; control sockets return0 after actual end; only unchanged business4 sockets remain per worker',business_idle_drain_ms:Math.round(performance.now()-beforeIdle),idle_drained_to:remaining,business_warm_global_capacity_closed:false});
 await stopPools();await reviewedCurrentMigrations();need(await locks()===0,'FINAL_NO_WORK_LOCKS');
 console.log(JSON.stringify({format:'collect.selfhost.control.native.v1',state:'PASS_CURRENT_BOUNDED_CONTROL_NATIVE',current_schema:installed,checks,receipts,hosted_mutations:0,provider_calls:0,adopted:false,production_capacity_closed:false}));
}catch(e){console.log(JSON.stringify({state:'UNCONFIRMED',stage,checks,safe_code:/^[A-Z0-9_]{1,80}$/.test((e as any)?.message??'')?(e as any).message:null,sqlstate:/^[0-9A-Z]{5}$/.test((e as any)?.code??'')?(e as any).code:null,receipts}));Deno.exitCode=1;}
finally{await stopPools().catch(()=>{});await owner.end({timeout:1});}
