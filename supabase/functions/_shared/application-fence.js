import {ApiError} from './domain/core.js';

const SHA=/^[a-f0-9]{64}$/, UUID=/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
export const FENCE_IO_TIMEOUT_MS=5000;
const KINDS=new Set(['http_collect','http_admin','jobs']);
const contexts=new WeakSet();
const unavailable=()=>new ApiError(503,'application_fence_unavailable','The service is temporarily unavailable. Keep the original request pending.');
const closed=()=>new ApiError(503,'application_fenced','The service is temporarily paused. Keep the original request pending.');
const need=(value)=>{if(!value)throw unavailable();};
const integer=value=>Number.isSafeInteger(value)&&value>=0;
export function fenceFailure(error){return error?.message==='collect_fence_closed'||error?.code==='application_fenced'?closed():unavailable();}
function base(row,id,source,epoch){need(row&&row.contractVersion===1&&row.admissionId===id&&row.sourceSha256===source&&Number.isSafeInteger(row.epoch)&&row.epoch>0&&(epoch===undefined||row.epoch===epoch));return row;}
function active(row,id,source,epoch){base(row,id,source,epoch);need(row.state==='active'&&['open','quiescing'].includes(row.mode));return row;}

// Only these reviewed names can be used. Neither caller SQL nor provider URLs
// enter the control plane. All values are bound parameters and remain private.
const signatures={register:'private.collect_fence_register($1::uuid,$2::text,$3::text)',
 assert:'private.collect_fence_assert_work($1::uuid,$2::bigint,$3::text)',
 close:'private.collect_fence_close($1::uuid,$2::bigint,$3::text,$4::text,$5::text,$6::integer,$7::integer)',
 status:'private.collect_fence_work_status($1::uuid)'};
async function bounded(promise){let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(unavailable()),FENCE_IO_TIMEOUT_MS);})]);}finally{clearTimeout(timer);}}
// A timed-out waiter never receives a business connection or starts SQL later.
// No transaction callback is enqueued before this bounded reservation succeeds.
export async function reserveDatabaseConnection(sql){
 need(typeof sql?.reserve==='function');const pending=Promise.resolve().then(()=>sql.reserve());
 try{return await bounded(pending);}catch(error){void pending.then(async late=>{try{await late?.release();}catch{}},()=>{});throw fenceFailure(error);}
}
async function runtimeRole(tx){await tx.unsafe('SET LOCAL ROLE collect_runtime');await tx.unsafe("SELECT pg_catalog.set_config('collect.edge_verified','true',true)");}
async function result(tx,name,values){const rows=await tx.unsafe('SELECT '+signatures[name]+' AS result',values);need(rows.length===1&&rows[0].result&&typeof rows[0].result==='object');return rows[0].result;}
export function sqlFenceBackend(businessSql,controlSql){
 need(typeof businessSql?.begin==='function'&&typeof controlSql?.reserve==='function');
 const call=(name,values)=>bounded(businessSql.begin('ISOLATION LEVEL READ COMMITTED',async tx=>{await runtimeRole(tx);return result(tx,name,values);}));
 return Object.freeze({register:(id,source,kind)=>call('register',[id,source,kind]),close:(id,epoch,source,outcome,reason,dispatches,uncertain)=>call('close',[id,epoch,source,outcome,reason,dispatches,uncertain]),status:id=>call('status',[id]),
  async lease(id,epoch,source){
   const tx=await reserveDatabaseConnection(controlSql);let beginDispatched=false,released=false,cleanup=null;
   const releaseReservation=()=>{if(released)return;released=true;tx.release();};
   const release=()=>{
    if(!cleanup)cleanup=(async()=>{
     // BEGIN can have executed even when its acknowledgement was lost. A
     // reservation is reusable only after the original ROLLBACK acknowledges.
     // postgres3.4.7 release() does not reset a transaction or its WORK lock.
     if(beginDispatched)await tx.unsafe('ROLLBACK');
     releaseReservation();
    })();
    // Bound observation, not the original cleanup. A late ACK may release once;
    // a rejection quarantines forever. Never enqueue another rollback/reset.
    return bounded(cleanup);
   };
   try{beginDispatched=true;await tx.unsafe('BEGIN ISOLATION LEVEL READ COMMITTED');await runtimeRole(tx);await tx.unsafe("SET LOCAL statement_timeout='5s'");await tx.unsafe("SET LOCAL lock_timeout='5s'");
    await tx.unsafe('SELECT pg_catalog.pg_advisory_xact_lock_shared(7346371,1)');
    const row=await result(tx,'assert',[id,epoch,source]);
    return {row,async assert(){need(!cleanup&&!released);return bounded(result(tx,'assert',[id,epoch,source]));},release};
   }catch(error){await release().catch(()=>{});throw error;}
  }
 });
}

export async function openApplicationWork({backend,sourceSha256,kind,id=crypto.randomUUID()}={}){
 need(backend&&['register','lease','close','status'].every(name=>typeof backend[name]==='function')&&SHA.test(sourceSha256)&&KINDS.has(kind)&&UUID.test(id));
 let row,lease;
 try{row=base(await backend.register(id,sourceSha256,kind),id,sourceSha256);need(row.mode==='open'&&row.state==='active'&&row.kind===kind);}
 catch(error){throw fenceFailure(error);} // Unknown register is not retried or replaced.
 try{const pending=Promise.resolve().then(()=>backend.lease(id,row.epoch,sourceSha256));
  try{lease=await bounded(pending);}catch(error){void pending.then(late=>late?.release().catch(()=>{}),()=>{});throw error;}
  const proof=active(lease.row,id,sourceSha256,row.epoch);if(proof.mode!=='open')throw closed();}
 catch(error){
  // No handler/provider/business work has begun. This exact registration can
  // close as cancelled even if owner begin_quiesce won the race after register.
  try{await backend.close(id,row.epoch,sourceSha256,'settled','cancelled_before_work',0,0);}catch{}
  await lease?.release().catch(()=>{});throw fenceFailure(error);
 }
 const work=new ApplicationWork(backend,lease,id,row.epoch,sourceSha256,kind);contexts.add(work);return work;
}

class ApplicationWork{
 constructor(backend,lease,id,epoch,source,kind){this.backend=backend;this.lease=lease;this.id=id;this.epoch=epoch;this.source=source;this.kind=kind;this.phase='running';this.lost=false;this.pending=new Set();this.dispatches=[];this.responses=new Map();this.lostReason=null;this.check=Promise.resolve();this.completion=null;}
 tuple(){return [this.id,this.epoch,this.source];}
 async assert(){
  need(['running','finishing'].includes(this.phase)&&!this.lost);
  const check=this.check.then(async()=>{need(!this.lost);return active(await this.lease.assert(),this.id,this.source,this.epoch);});
  this.check=check.catch(()=>{this.lost=true;});
  try{return await check;}catch{this.lost=true;throw unavailable();}
 }
 track(promise,record=null){
  const raw=Promise.resolve(promise);const settled=raw.then(()=>{},()=>{if(record)record.unknown=true;});
  this.pending.add(settled);void settled.then(()=>this.pending.delete(settled));return raw;
 }
 dispatch(label,operation){
  need(typeof label==='string'&&/^[a-z_]{1,40}$/.test(label)&&typeof operation==='function'&&['running','finishing'].includes(this.phase));
  const record={label,unknown:false};
  // Track the assertion AND original operation synchronously. Even an unawaited
  // caller cannot let finish() overtake a queued permission check/provider start.
  return this.track((async()=>{await this.assert();this.dispatches.push(record);return operation();})(),record);
 }
 unknown(label){const record=this.dispatches.findLast(row=>row.label===label);if(record)record.unknown=true;}
 assertLocal(){need(['running','finishing'].includes(this.phase));}
 abandon(reason='work_lost'){this.assertLocal();need(['work_lost','lease_lost'].includes(reason));this.lost=true;this.lostReason=reason;}
 async local(operation){this.assertLocal();need(typeof operation==='function');return this.track(Promise.resolve().then(operation));}
 retainResponse(response,label){this.assertLocal();if(response?.body&&!this.responses.has(response))this.responses.set(response,{label,handled:false});}
 cleanupResponses(){
  for(const [response,item]of this.responses){if(item.handled)continue;item.handled=true;
   if(!response.body||response.bodyUsed)continue;
   // A locked body without any tracked owner is unproven work, not settlement.
   if(response.body.locked){this.lost=true;this.lostReason='work_lost';this.unknown(item.label);continue;}
   this.unknown(item.label);let raw;try{raw=response.body.cancel();}catch{this.lost=true;this.lostReason='work_lost';continue;}
   this.track(Promise.resolve(raw).catch(()=>{this.unknown(item.label);}));
  }
 }
 waitUntil(promise){need(['running','finishing'].includes(this.phase));return this.track(promise);}
 finish({failed=false}={}){
  if(this.completion)return this.completion;
  this.phase='finishing';this.completion=(async()=>{
   try{
    // A tracked task may register further raw work before it settles.
    while(true){while(this.pending.size)await Promise.all([...this.pending]);this.cleanupResponses();if(this.pending.size)continue;try{await this.assert();}catch{this.lost=true;}this.cleanupResponses();if(!this.pending.size)break;}
    this.phase='closing';const uncertain=this.dispatches.filter(row=>row.unknown).length;
    const outcome=this.lost?'unresolved':'settled',reason=this.lost?(this.lostReason??'lease_lost'):uncertain?'completed_with_unknown_obligation':failed&&this.dispatches.length===0?'work_failed_before_dispatch':'completed';
    const verify=row=>{base(row,this.id,this.source,this.epoch);need(row.state===outcome&&row.reason===reason&&row.externalDispatches===this.dispatches.length&&row.uncertainDispatches===uncertain);return row;};
    let row;
    try{row=verify(await this.backend.close(this.id,this.epoch,this.source,outcome,reason,this.dispatches.length,uncertain));}
    catch{
     // A lost close COMMIT is resolved only by exact original state. No second
     // close, new admission, TTL expiry or journal replay is attempted.
     const known=await this.backend.status(this.id).catch(()=>null);need(known?.found===true);row=verify(known);
    }
    return Object.freeze({state:row.state,reason:row.reason,externalDispatches:row.externalDispatches,uncertainDispatches:row.uncertainDispatches,applicationWorkFinished:row.state==='settled',wholeSystemAcceptance:false,providerSettlement:false,managedInternalWritesFenced:false,humanMessagesFenced:false});
   }finally{this.phase='closed';await this.lease.release().catch(()=>{});}
  })();return this.completion;
 }
}

export function applicationWork(env){const work=env?.COLLECT_FENCE_WORK;need(contexts.has(work));return work;}
export function applicationWorkTuple(work){need(contexts.has(work));return work.tuple();}
function guardedResponse(response,work,label){
 const readers=new Set(['json','text','arrayBuffer','blob','formData','bytes']),methods=new Map();
 const proxy=new Proxy(response,{get(target,key){const value=Reflect.get(target,key,target);if(typeof value!=='function')return value;
  if(methods.has(key))return methods.get(key);let method;
  if(readers.has(key))method=(...args)=>work.local(async()=>{try{return await value.apply(target,args);}catch(error){work.unknown(label);throw error;}});
  else if(key==='clone')method=(...args)=>{work.assertLocal();return guardedResponse(value.apply(target,args),work,label);};
  else method=value.bind(target);methods.set(key,method);return method;
 }});work.retainResponse(proxy,label);return proxy;
}
export async function guardedFetch(env,label,input,options){
 const work=applicationWork(env);
 // Span includes late response registration, so an abort after headers cannot
 // race finish() before unread-body cleanup becomes owned durable work.
 return work.waitUntil((async()=>{const response=await work.dispatch(label,()=>fetch(input,options));if(response.status>=500)work.unknown(label);return guardedResponse(response,work,label);})());
}
export function noteUnknownEffect(env,label){applicationWork(env).unknown(label);}

// A deferred context still performs exactly the same durable register/lease and
// assertion. It is useful for dependency construction; it grants no bypass.
export function deferredApplicationWork(options){
 let actual;const ready=openApplicationWork(options).then(value=>{actual=value;return value;});
 // Consumers await assert() before requesting its synchronous tuple.
 const holder={tuple(){need(actual);return actual.tuple();},async assert(){return(await ready).assert();},async dispatch(label,operation){return(await ready).dispatch(label,operation);},unknown(label){actual?.unknown(label);},assertLocal(){need(actual);actual.assertLocal();},abandon(reason){need(actual);actual.abandon(reason);},async local(operation){return(await ready).local(operation);},retainResponse(response,label){need(actual);actual.retainResponse(response,label);},waitUntil(promise){return ready.then(work=>work.waitUntil(promise));},async finish(options){return(await ready).finish(options);}};
 contexts.add(holder);return holder;
}
