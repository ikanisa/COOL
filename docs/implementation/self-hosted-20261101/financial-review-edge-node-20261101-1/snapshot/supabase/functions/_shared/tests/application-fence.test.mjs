import test from 'node:test';
import {setImmediate} from 'node:timers';
import assert from 'node:assert/strict';
import {openApplicationWork,applicationWork,applicationWorkTuple,guardedFetch,noteUnknownEffect,sqlFenceBackend} from '../application-fence.js';
import {createWorkspaceSmtpEmail} from '../workspace-smtp-email.js';
import {sendTransactionalEmail} from '../domain/email_delivery.js';
import {SupabaseNativeTransport} from '../storage/supabase-transport.js';
import {PostgresStorageJournal} from '../storage/postgres-journal.js';
const SOURCE='a'.repeat(64),OTHER='b'.repeat(64);
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return{promise,resolve,reject};};
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function fixture(){
 const rows=new Map(),events=[];let mode='open',lost=false,registerError=false,closeLost=false,foreignStatus=false;
 const row=id=>({...rows.get(id),mode});
 const backend={async register(id,source,kind){events.push('register');if(mode!=='open')throw Error('collect_fence_closed');rows.set(id,{contractVersion:1,admissionId:id,epoch:1,sourceSha256:source,kind,state:'active'});if(registerError)throw Error('lost registration reply');return row(id);},async lease(id){events.push('lease');return{row:row(id),async assert(){events.push('assert');if(lost)throw Error('connection lost');return row(id);},async release(){events.push('release');}};},async close(id,epoch,source,state,reason,externalDispatches,uncertainDispatches){events.push('close');const value={...rows.get(id),state,reason,externalDispatches,uncertainDispatches};rows.set(id,value);if(closeLost)throw Error('lost commit reply');return{...value};},async status(id){events.push('status');return{...rows.get(id),found:rows.has(id),...(foreignStatus?{sourceSha256:OTHER}:{})};}};
 return{backend,rows,events,setMode:value=>{mode=value;},lose:()=>{lost=true;},lostRegistration:()=>{registerError=true;},lostClose:()=>{closeLost=true;},foreignStatus:()=>{foreignStatus=true;},open:kind=>openApplicationWork({backend,sourceSha256:SOURCE,kind:kind??'http_collect'})};
}

test('missing or forged work, malformed source and closed admission fail before actual fetch',async()=>{
 let effects=0;const previous=globalThis.fetch;globalThis.fetch=async()=>{effects++;throw Error('unexpected effect');};
 try{for(const env of [{},{COLLECT_FENCE_WORK:{assert(){}}}])await assert.rejects(guardedFetch(env,'auth','https://synthetic.invalid'),{code:'application_fence_unavailable'});assert.throws(()=>applicationWork({COLLECT_FENCE_WORK:{}}),{code:'application_fence_unavailable'});const f=fixture();await assert.rejects(openApplicationWork({backend:f.backend,sourceSha256:'not-source',kind:'http_collect'}));f.setMode('quiescing');await assert.rejects(f.open(),{code:'application_fenced'});assert.equal(effects,0);assert.equal(f.events.filter(x=>x==='register').length,1);assert.equal(f.rows.size,0);}finally{globalThis.fetch=previous;}
});

test('registration reply loss leaves original durable active row and is never retried or replaced',async()=>{
 const f=fixture();f.lostRegistration();await assert.rejects(f.open());assert.deepEqual(f.events,['register']);assert.equal(f.rows.size,1);assert.equal([...f.rows.values()][0].state,'active');
});

test('quiesce between registration and initial WORK proof cancels without provider or business work',async()=>{
 const f=fixture(),lease=f.backend.lease;f.backend.lease=async(...args)=>{f.setMode('quiescing');return lease(...args);};await assert.rejects(f.open(),{code:'application_fenced'});const row=[...f.rows.values()][0];assert.equal(row.state,'settled');assert.equal(row.reason,'cancelled_before_work');assert.equal(row.externalDispatches,0);assert.deepEqual(f.events,['register','lease','close','release']);
});

test('all three runtime work kinds retain their source and opaque admission identity',async()=>{
 for(const kind of ['http_collect','http_admin','jobs']){const f=fixture(),work=await f.open(kind),tuple=applicationWorkTuple(work);assert.equal(tuple[2],SOURCE);assert.equal(f.rows.get(tuple[0]).kind,kind);assert.match(tuple[0],/^[a-f0-9-]{36}$/);assert.equal((await work.finish()).applicationWorkFinished,true);}
});

test('already-admitted work drains in QUIESCING while new work stays closed',async()=>{
 const f=fixture(),work=await f.open();f.setMode('quiescing');let effects=0;await work.dispatch('smtp',()=>{effects++;return 'original';});await assert.rejects(f.open(),{code:'application_fenced'});const result=await work.finish();assert.equal(effects,1);assert.equal(result.state,'settled');assert.equal(result.externalDispatches,1);assert.equal(result.providerSettlement,false);assert.equal(result.wholeSystemAcceptance,false);assert.equal(result.humanMessagesFenced,false);
});

test('queued dispatch assertion cannot be overtaken by finish; raw provider promise keeps work active',async()=>{
 const f=fixture(),work=await f.open(),raw=deferred(),started=deferred();let closed=false,effects=0;
 const dispatch=work.dispatch('smtp',()=>{effects++;started.resolve();return raw.promise;});const completion=work.finish().then(value=>{closed=true;return value;});await started.promise;await tick();assert.equal(closed,false);assert.equal(f.events.includes('close'),false);assert.equal([...f.rows.values()][0].state,'active');raw.resolve('accepted');assert.equal(await dispatch,'accepted');const result=await completion;assert.equal(result.state,'settled');assert.equal(effects,1);assert.equal(f.events.at(-1),'release');
});

test('waitUntil task can schedule raw child work after response; neither lifetime is dropped',async()=>{
 const f=fixture(),work=await f.open(),gate=deferred(),raw=deferred(),started=deferred();
 work.waitUntil((async()=>{await gate.promise;await work.dispatch('decoder',()=>{started.resolve();return raw.promise;});})());const result=work.finish();gate.resolve();await started.promise;await tick();assert.equal(f.events.includes('close'),false);raw.resolve('complete');assert.equal((await result).externalDispatches,1);assert.equal(f.events.filter(x=>x==='close').length,1);
});

test('actual SMTP observational timeout preserves unknown receipt and holds original raw promise until settled',async()=>{
 const f=fixture(),work=await f.open(),raw=deferred(),started=deferred();const env={COLLECT_FENCE_WORK:work,COLLECT_NOTICE_SMTP_PASSWORD:'synthetic-password',AUTH_EMAIL_FROM:'info@ikanisa.com'};let sends=0,closed=false;const journal={state:'sending'};
 env.AUTH_EMAIL=createWorkspaceSmtpEmail(env,{createTransport:()=>({sendMail(){sends++;started.resolve();return raw.promise;},close(){}})});
 const previousSet=globalThis.setTimeout,previousClear=globalThis.clearTimeout;let deadline;
 globalThis.setTimeout=(fn,ms,...args)=>ms===10000?(deadline={fn:()=>fn(...args)}):previousSet(fn,ms,...args);globalThis.clearTimeout=value=>{if(value!==deadline)previousClear(value);};
 try{const observed=sendTransactionalEmail(env,{to:'synthetic@example.invalid',subject:'Collect',text:'Synthetic'});await started.promise;assert.ok(deadline);deadline.fn();await assert.rejects(observed,{code:'email_unavailable'});journal.state='unknown';const completion=work.finish().then(value=>{closed=true;return value;});await tick();assert.equal(closed,false);assert.equal(f.events.includes('close'),false);assert.equal(sends,1);raw.resolve({messageId:'<synthetic@ikanisa.com>',accepted:['synthetic@example.invalid'],rejected:[],rejectedErrors:[],response:'250 2.0.0 accepted',envelope:{from:'info@ikanisa.com',to:['synthetic@example.invalid']}});const result=await completion;assert.equal(result.state,'settled');assert.equal(result.reason,'completed_with_unknown_obligation');assert.equal(result.uncertainDispatches,1);assert.equal(result.providerSettlement,false);assert.equal(journal.state,'unknown');assert.equal(sends,1);}finally{raw.resolve({});globalThis.setTimeout=previousSet;globalThis.clearTimeout=previousClear;}
});

test('lease loss denies new dispatch and closes unfinished authority as unresolved, with no TTL clearing',async()=>{
 const f=fixture(),work=await f.open();f.lose();let effects=0;await assert.rejects(work.dispatch('auth',()=>{effects++;}));const result=await work.finish();assert.equal(effects,0);assert.equal(result.state,'unresolved');assert.equal(result.reason,'lease_lost');assert.equal(result.applicationWorkFinished,false);assert.equal([...f.rows.values()][0].state,'unresolved');assert.equal(f.events.filter(x=>x==='close').length,1);
});

test('lost close COMMIT is reconciled only by exact original readback, never by second close',async()=>{
 for(const foreign of [false,true]){const f=fixture(),work=await f.open();f.lostClose();if(foreign)f.foreignStatus();if(foreign)await assert.rejects(work.finish(),{code:'application_fence_unavailable'});else assert.equal((await work.finish()).state,'settled');assert.equal(f.events.filter(x=>x==='close').length,1);assert.equal(f.events.filter(x=>x==='status').length,1);assert.equal(f.rows.size,1);assert.equal(f.events.at(-1),'release');}
});

test('unknown HTTP result remains a retained obligation, with one physical dispatch and no replay',async()=>{
 const f=fixture(),work=await f.open(),previous=globalThis.fetch;let sends=0;globalThis.fetch=async()=>{sends++;return Response.json({private:'synthetic'}, {status:503});};
 try{assert.equal((await guardedFetch({COLLECT_FENCE_WORK:work},'auth','https://synthetic.invalid')).status,503);const result=await work.finish();assert.equal(result.state,'settled');assert.equal(result.uncertainDispatches,1);assert.equal(sends,1);assert.equal(result.providerSettlement,false);}finally{globalThis.fetch=previous;}
});

function sqlFixture(){
 const f=fixture(),queue=[],leases=[];let held=false;
 const control={reserve(){if(held){const waiting=deferred();queue.push(waiting);return waiting.promise;}held=true;return Promise.resolve(makeTx());}};
 function makeTx(){const tx={released:false,async unsafe(text,values=[]){if(text.startsWith('SELECT private.collect_fence_assert_work')){const lease=await f.backend.lease(...values);leases.push(lease);return[{result:await lease.assert()}];}return[];},release(){assert.equal(tx.released,false);tx.released=true;f.events.push('raw_release');if(queue.length)queue.shift().resolve(makeTx());else held=false;}};return tx;}
 const business={async begin(options,fn){if(typeof options==='function'){fn=options;}const tx={async unsafe(text,values=[]){if(text.startsWith('SELECT private.collect_fence_register'))return[{result:await f.backend.register(...values)}];if(text.startsWith('SELECT private.collect_fence_close'))return[{result:await f.backend.close(...values)}];if(text.startsWith('SELECT private.collect_fence_work_status'))return[{result:await f.backend.status(...values)}];return[];}};return fn(tx);}};
 return{f,backend:sqlFenceBackend(business,control),queue};
}

test('single control slot bounds queued admission at 5s while original provider stays live; late reservation releases',async()=>{
 const {f,backend}=sqlFixture(),first=await openApplicationWork({backend,sourceSha256:SOURCE,kind:'http_collect'}),raw=deferred(),started=deferred();let effects=0;
 const provider=first.dispatch('smtp',()=>{effects++;started.resolve();return raw.promise;});await started.promise;const start=performance.now();await assert.rejects(openApplicationWork({backend,sourceSha256:SOURCE,kind:'http_admin'}),{code:'application_fence_unavailable'});const elapsed=performance.now()-start;assert.ok(elapsed>=4500&&elapsed<8000,'pool wait must be bounded independently of PG statement/connect timeouts');assert.equal(effects,1);const values=[...f.rows.values()];assert.equal(values.filter(row=>row.state==='active').length,1);assert.equal(values.filter(row=>row.reason==='cancelled_before_work').length,1);raw.resolve();await provider;await first.finish();await tick();assert.equal(f.events.filter(x=>x==='raw_release').length,2);assert.equal(effects,1);
});

test('queued request proceeds after original raw work settles and WORK releases',async()=>{
 const {f,backend}=sqlFixture(),first=await openApplicationWork({backend,sourceSha256:SOURCE,kind:'http_collect'}),raw=deferred(),started=deferred();const provider=first.dispatch('smtp',()=>{started.resolve();return raw.promise;});await started.promise;let admitted=false;const waiting=openApplicationWork({backend,sourceSha256:SOURCE,kind:'jobs'}).then(work=>{admitted=true;return work;});await tick();assert.equal(admitted,false);raw.resolve();await provider;await first.finish();const second=await waiting;assert.equal(admitted,true);await second.finish();assert.equal(f.events.filter(x=>x==='raw_release').length,2);
});

test('native upload and DELETE require an admission before bucket/authenticated probes or mutation',async()=>{
 for(const guard of [undefined,async()=>{throw Error('application stopped');}]){let calls=0;const transport=new SupabaseNativeTransport({url:'https://synthetic.supabase.co',secretKey:'sb_secret_synthetic',authorizeMutation:guard,fetchImpl:async()=>{calls++;throw Error('unexpected wire');}});await assert.rejects(transport.uploadImmutable('synthetic.enc',new Uint8Array([1]),{}));await assert.rejects(transport.remove('synthetic.enc'));assert.equal(calls,0);}
});

test('journal inventory binds namespace in RC and reads all pages from a distinct genuinely READ ONLY RR snapshot',async()=>{
 const calls=[];let current=0;const namespace={origin:'https://synthetic.supabase.co',bucket:'collect-evidence'};
 const pool={async connect(){const id=++current;return{async query(text){calls.push({id,text});if(text.startsWith('SELECT origin,bucket'))return{rows:[namespace]};return{rows:[]};},release(){calls.push({id,text:'RELEASE'});}};}};
 const journal=new PostgresStorageJournal(pool,{namespace});assert.deepEqual(await journal.listAll(),{puts:[],metadata:[],deletes:[]});assert.equal(current,2);assert.equal(calls[0].text,'BEGIN');assert.ok(calls.some(x=>x.id===1&&x.text.startsWith('INSERT INTO private.storage_namespace')));assert.equal(calls.find(x=>x.id===2).text,'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');assert.equal(calls.filter(x=>x.id===2&&/^(INSERT|UPDATE|DELETE|TRUNCATE)/.test(x.text)).length,0);assert.equal(calls.filter(x=>x.id===2&&x.text.startsWith('SELECT * FROM private.')).length,3);
});
