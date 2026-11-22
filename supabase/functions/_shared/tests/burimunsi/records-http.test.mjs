import test from 'node:test';import assert from 'node:assert/strict';
import {RecordsService} from '../../domain/burimunsi/records-service.js';
import {ScopedCursor} from '../../domain/burimunsi/cursor.js';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {actor} from './fixtures.mjs';
import {PostgresRecordsStore} from '../../domain/burimunsi/postgres-records-store.js';
const CLOCK=1793961600000;
const payment={id:'tx-1',groupId:'group-1',payerNameRaw:'EXAMPLE PERSON',payerPhoneRaw:'*********816',amountRwf:10000,atRaw:'2026-10-08 15:15:20',ftId:'90000000001',state:'unallocated',version:1};
function records(){const data={actor:{...actor,expiresAt:CLOCK+100000},revision:'v1',rows:[payment],after:null,group:'group-1',detail:payment};const tx={reloadActor:async()=>data.actor,loadBinding:async()=>({active:true,groupId:data.group,installationId:data.actor.installationId}),canonicalHome:async()=>({groupBalanceRwf:10000,todayRwf:10000,memberCount:1,unallocatedCount:1,recentPayments:data.rows,asOf:'2026-11-06T10:00:00Z',extraSecret:'never-return'}),listRevision:async()=>data.revision,readPage:async()=>({items:data.rows,after:data.after,totalCount:data.rows.length,asOf:'2026-11-06T10:00:00Z'}),readDetail:async()=>data.detail,readAllLedger:async()=>data.rows.map(r=>({...r,memberPhone:'+250780000816'})),readCommandOutcome:async()=>data.outcome};const svc=new RecordsService({store:{withReadSnapshot:fn=>fn(tx),withCommandSnapshot:fn=>fn(tx)},groupId:'group-1',cursor:new ScopedCursor(new Uint8Array(32).fill(8)),clock:()=>CLOCK});return {svc,data,tx};}
test('home uses canonical adapter values and strips extra material',async()=>{const {svc}=records();const h=await svc.home(actor);assert.equal(h.groupBalanceRwf,10000);assert.equal(h.extraSecret,undefined)});
test('reader rejects cross-group row even if adapter is wrong',async()=>{const {svc,data}=records();data.rows=[{...payment,groupId:'another'}];await assert.rejects(svc.page(actor,'payments'),/reader_scope_violation/)});
test('ordinary transaction read rejects a leaked raw body',async()=>{const {svc,data}=records();data.rows=[{...payment,rawBody:'not-for-staff'}];await assert.rejects(svc.page(actor,'payments'),/sensitive_projection/)});
test('projection whitelist removes unrecognized properties',async()=>{const {svc,data}=records();data.rows=[{...payment,unexpected:{secret:'must-not-return'}}];const p=await svc.page(actor,'payments');assert.equal(p.items[0].unexpected,undefined)});
test('native provider notices preserve null values and direction without weakening managed rows',async()=>{
 const {svc,data}=records();
 const native={...payment,amountRwf:null,ftId:null,state:'recorded',memberId:null,memberPhone:null,sourceKind:'observation',direction:'other',outcome:'unknown',feeRwf:null,walletBalanceAfterRwf:null};
 data.rows=[native];assert.deepEqual((await svc.page(actor,'payments')).items[0],native);
 data.rows=[{...payment,amountRwf:null,ftId:null}];await assert.rejects(svc.page(actor,'payments'),/invalid_transaction_projection/);
 data.rows=[{...native,direction:'invented'}];await assert.rejects(svc.page(actor,'payments'),/invalid_transaction_projection/);
});
const nativePosted={...payment,ftId:null,state:'posted',memberId:'member-1',memberPhone:'+250780000816',sourceId:null,
 sourceKind:'observation',direction:'incoming',outcome:'successful',feeRwf:null,walletBalanceAfterRwf:12000};
test('payment details negotiate a scoped reference while predecessor bytes and original identifiers survive',async()=>{
 const {svc,data,tx}=records(),installation='22222222-2222-4222-8222-222222222222',requestId='11111111-1111-4111-8111-111111111111';
 data.actor={...data.actor,sessionId:requestId,installationId:installation};
 data.detail={...payment,memberId:null,memberPhone:null,sourceId:'original-source'};
 const noop=async()=>({});
 const origin='https://native.example.test',referenceHeader='X-BuriMunsi-Payment-Reference-Version';
 const handle=createNativeHandler({auth:{login:noop,authenticate:async()=>data.actor,logout:noop,changePasscode:noop,manageStaff:noop},
  records:svc,contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  origin,groupId:'group-1',strictContract:true,networkBucket:noop});
 const get=(version,path='/payments/tx-1')=>handle(new Request(origin+'/v1/burimunsi'+path,{headers:{
  'x-burimunsi-installation':installation,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':requestId,
  'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),...(version?{[referenceHeader]:version}:{})}}));
 const before=await get();assert.equal(before.status,200);assert.equal(before.headers.has(referenceHeader),false);
 const bytes=await before.text(),original=JSON.parse(bytes).data;
 assert.deepEqual([original.id,original.ftId,original.sourceId],['tx-1','90000000001','original-source']);
 assert.deepEqual((await (await get('1')).json()).data,{payment:original,paymentReference:null});
 data.detail.paymentReference='100000000017';
 assert.equal(await (await get()).text(),bytes);
 const expanded=await get('1');assert.equal(expanded.status,200);assert.equal(expanded.headers.get(referenceHeader),'1');
 assert.deepEqual((await expanded.json()).data,{payment:original,paymentReference:'100000000017'});
 assert.equal((await get('2')).status,400);
 for(const bad of ['short',100000000017,'100000000017\n']){
  data.detail.paymentReference=bad;const denied=await get('1');assert.equal(denied.status,503);assert.equal(denied.headers.has(referenceHeader),false);
 }
 data.detail={...data.detail,paymentReference:'100000000017',id:'other'};
 assert.equal((await get('1')).status,503);
 data.detail={...data.detail,id:'tx-1',groupId:'other'};assert.equal((await get('1')).status,404);
 tx.readDetail=()=>assert.fail('revoked actor reached payment details');tx.reloadActor=async()=>null;
 assert.equal((await get('1')).status,401);
});
test('actual PostgreSQL native projection and RecordsService agree on all linked financial states',async()=>{
 const {svc}=records(),sourceId='30000000-0000-4000-8000-000000000001';
 for(const state of ['posted','reversed','corrected']){
  const databaseRow={id:'tx-1',collection_id:'group-1',native_source_id:sourceId,
   native_meta:{sourceId,canReveal:false,outcome:'successful'},source_conflict:false,
   payer_name:'EXAMPLE PERSON',payer_identifier:'*********816',amount_minor:'10000',transaction_datetime_raw:'2026-10-08 15:15:20',
   provider_transaction_id:null,payment_status:state==='posted'?'reconciled':state,ledger_posted:state==='posted',
   has_conflict:0,allocation_state:'linked',version:'1',member_id:'member-1',momo_number:'0780000816',event_kind:'incoming_receipt',
   fee_minor:null,wallet_balance_after_minor:'12000'};
  const store=new PostgresRecordsStore({authority:{groupId:'group-1',read:fn=>fn({unsafe:async()=>[databaseRow]}),session:async()=>null},
   sourceReader:{revision:async()=>'',page:async()=>null,detail:async()=>null},nativeAutoRecordsEnabled:true});
  const row=await store.withReadSnapshot(tx=>tx.readDetail({groupId:'group-1',kind:'payment',id:'tx-1'}));
  assert.equal(row.state,state);assert.equal(svc.projectRows([row],'payments')[0].state,state);
  assert.equal(row.sourceId,null);assert.equal(row.memberPhone,'+250780000816');
 }
});
test('a canonical native contribution is readable on home, the payment list and member-scoped payment detail',async()=>{
 const {svc,data}=records();data.rows=[nativePosted];data.detail=nativePosted;
 assert.equal((await svc.home(actor)).recentPayments[0].state,'posted');
 assert.equal((await svc.page(actor,'payments',{memberId:'member-1'})).items[0].memberId,'member-1');
 assert.equal((await svc.detail(actor,'payment','tx-1')).state,'posted');
 data.rows=[{...nativePosted,memberPhone:null}];
 assert.equal((await svc.page(actor,'payments')).items[0].memberPhone,null);
});
test('native posted state requires an incoming success, positive amount and canonical member reference',async()=>{
 const {svc,data}=records();
 for(const row of [{...nativePosted,memberId:null},{...nativePosted,memberPhone:undefined},
  {...nativePosted,memberId:'bad id'}, {...nativePosted,memberPhone:'*********816'},
  {...nativePosted,direction:'outgoing'},{...nativePosted,outcome:'pending'},
  {...nativePosted,amountRwf:null},{...nativePosted,amountRwf:-1},{...nativePosted,amountRwf:0},
  {...nativePosted,state:'recorded'}]){
  data.rows=[row];await assert.rejects(svc.page(actor,'payments'),/invalid_transaction_projection/);
 }
});
test('strict native Home, member and member-payment responses carry a posted SMS credit',async()=>{
 const {svc,data}=records(),installation='22222222-2222-4222-8222-222222222222',requestId='11111111-1111-4111-8111-111111111111';
 data.actor={...data.actor,sessionId:requestId,installationId:installation};data.rows=[nativePosted];
 const noop=async()=>({});
 const fn=createNativeHandler({auth:{login:noop,authenticate:async()=>data.actor,logout:noop,changePasscode:noop,manageStaff:noop},
  records:svc,contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  origin:'https://native.example.test',groupId:'group-1',strictContract:true,networkBucket:noop});
 const get=path=>new Request('https://native.example.test/v1/burimunsi'+path,{headers:{
  'x-burimunsi-installation':installation,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':requestId,
  'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64)}});
 let response=await fn(get('/home'));assert.equal(response.status,200);assert.equal((await response.json()).data.recentPayments[0].state,'posted');
 response=await fn(get('/payments?memberId=member-1&limit=40'));assert.equal(response.status,200);
 assert.equal((await response.json()).data.items[0].memberId,'member-1');
 data.detail={id:'member-1',groupId:'group-1',name:'Synthetic Person',phone:'+250780000816',balanceRwf:10000,active:true,version:1};
 response=await fn(get('/members/member-1'));assert.equal(response.status,200);assert.equal((await response.json()).data.balanceRwf,10000);
});
for(const state of ['reversed','corrected'])test('native '+state+' remains readable through Home, scoped list and strict payment detail',async()=>{
 const {svc,data,tx}=records(),installation='22222222-2222-4222-8222-222222222222',requestId='11111111-1111-4111-8111-111111111111';
 data.actor={...data.actor,sessionId:requestId,installationId:installation};
 const row={...nativePosted,state};data.rows=[row];data.detail=row;
 const balance=state==='reversed'?0:5000;
 tx.canonicalHome=async()=>({groupBalanceRwf:balance,todayRwf:balance,memberCount:1,unallocatedCount:0,recentPayments:data.rows,asOf:'2026-11-06T10:00:00Z'});
 assert.equal((await svc.home(data.actor)).groupBalanceRwf,balance);
 assert.equal((await svc.page(data.actor,'payments',{memberId:'member-1'})).items[0].state,state);
 assert.equal((await svc.detail(data.actor,'payment','tx-1')).state,state);
 const noop=async()=>({});const fn=createNativeHandler({auth:{login:noop,authenticate:async()=>data.actor,logout:noop,changePasscode:noop,manageStaff:noop},
  records:svc,contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  origin:'https://native.example.test',groupId:'group-1',strictContract:true,networkBucket:noop});
 const get=path=>new Request('https://native.example.test/v1/burimunsi'+path,{headers:{
  'x-burimunsi-installation':installation,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':requestId,
  'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64)}});
 for(const path of ['/home','/payments?memberId=member-1&limit=40','/payments/tx-1']){
  const response=await fn(get(path));assert.equal(response.status,200,path);const {data:value}=await response.json();
  assert.equal(path==='/home'?value.recentPayments[0].state:path.includes('?')?value.items[0].state:value.state,state);
 }
 data.rows=[{...row,memberPhone:null}];assert.equal((await svc.page(data.actor,'payments')).items[0].state,state);
 for(const invalid of [{...row,groupId:'other-group'},{...row,memberId:null},{...row,outcome:'pending'},
  {...row,direction:'outgoing'},{...row,amountRwf:0},{...row,state:'invented'}]){
  data.rows=[invalid];await assert.rejects(svc.page(data.actor,'payments'));
 }
});
test('staff raw SMS denial uses fresh server role',async()=>{const {svc,data}=records();data.actor.role='staff';data.actor.capabilities.push('sms.read');await assert.rejects(svc.detail(actor,'sms','sms-1'),/access_denied/)});
test('revoked account denied inside consistent read snapshot',async()=>{const {svc,data}=records();data.actor.revoked=true;await assert.rejects(svc.home(actor),/session_unavailable/)});
test('a missing native session denies Members before looking up a binding or reading a page',async()=>{
 const {svc,data,tx}=records();
 data.actor=null;
 const unexpected=()=>assert.fail('unexpected read after session loss');
 tx.loadBinding=unexpected;tx.memberListingRevision=unexpected;tx.readMemberPage=unexpected;
 await assert.rejects(svc.page(actor,'members'),{code:'session_unavailable',status:401});
});
test('stale pagination cursor cannot silently mix snapshots',async()=>{const {svc,data}=records();data.after={id:'tx-1',at:'date'};const p=await svc.page(actor,'payments');data.revision='v2';await assert.rejects(svc.page(actor,'payments',{cursor:p.nextCursor}),/cursor_scope_changed/)});
test('pagination scope includes filters and search',async()=>{const {svc,data}=records();data.after={id:'tx-1',at:'date'};const p=await svc.page(actor,'payments');await assert.rejects(svc.page(actor,'payments',{cursor:p.nextCursor,q:'different'}),/cursor_scope_changed/)});
test('payment pagination cursor cannot cross member filters',async()=>{const {svc,data}=records();data.after={offset:1};const p=await svc.page(actor,'payments',{memberId:'member-1'});await assert.rejects(svc.page(actor,'payments',{memberId:'member-2',cursor:p.nextCursor}),/cursor_scope_changed/)});
test('unknown operation outcome stays pending instead of unsafe rejection',async()=>{const {svc}=records();assert.equal((await svc.commandStatus(actor,'c038b0d7-182b-4a61-a289-9475cf22a9a3')).state,'pending')});
test('operation status cannot cross accounts',async()=>{const {svc,data}=records();data.outcome={state:'committed',groupId:'group-1',actorId:'another'};await assert.rejects(svc.commandStatus(actor,'c038b0d7-182b-4a61-a289-9475cf22a9a3'),/command_scope/)});
test('CSV exports retained fields and not hidden internal IDs',async()=>{const {svc}=records();const csv=await svc.exportLedger(actor,'member-1');assert.match(csv,/90000000001/);assert.doesNotMatch(csv,/tx-1/) });

function handler(){const calls=[];const a={...actor,sessionId:'native-session'};const auth={login:async(c,n)=>{calls.push(['login',c,n]);return {token:'d'.repeat(64)}},authenticate:async(token,id)=>{if(token!=='a'.repeat(64))throw Object.assign(new Error('secret must not escape'),{});calls.push(['authenticate',id]);return a;},logout:async()=>({signedOut:true}),changePasscode:async()=>({reauthenticationRequired:true}),manageStaff:async(_,c)=>{calls.push(['staff',c]);return {applied:true}}};const records={home:async()=>({groupBalanceRwf:10000}),page:async(_,kind,q)=>{calls.push(['page',kind,q]);return {items:[]}},detail:async(_,k,id)=>({id}),exportLedger:async()=> 'FT Id,amount\r\n90000000001,10000\r\n',commandStatus:async(_,id)=>({requestId:id,state:'pending'})};const fn=createNativeHandler({auth,records,contributions:{allocate:async(_,c)=>{calls.push(['allocate',c]);return {state:'posted'}}},members:{enroll:async()=>({id:'member-1'}),setActive:async()=>({applied:true})},gateway:{status:async()=>({pending:0}),replace:async()=>({replaced:true})},origin:'https://native.example.test',networkBucket:async()=> 'b'.repeat(64)});return {fn,calls};}
const request=(path,method='GET',body,extra={})=>new Request('https://native.example.test/v1/burimunsi'+path,{method,headers:{'x-burimunsi-installation':'device-1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json',...extra},body:body===undefined?undefined:JSON.stringify(body)});
test('native handler returns no-store JSON envelope',async()=>{const {fn}=handler();const r=await fn(request('/home'));assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');assert.equal((await r.json()).data.groupBalanceRwf,10000)});
test('login passes only phone/PIN and server network bucket',async()=>{const {fn,calls}=handler();const r=await fn(request('/session/login','POST',{phone:'0780000001',pin:'0007'},{'x-burimunsi-device':'c'.repeat(64)}));assert.equal(r.status,200);assert.equal(calls[0][0],'login');assert.equal(calls[0][2],'b'.repeat(64))});
test('login cannot inject role',async()=>{const {fn}=handler();const r=await fn(request('/session/login','POST',{phone:'0780000001',pin:'0007',role:'admin'}));assert.equal(r.status,400)});
test('allocation uses path identity and original request key',async()=>{const {fn,calls}=handler();const command={memberId:'member-1',expectedVersion:1,note:'Confirmed identity',requestId:crypto.randomUUID()};assert.equal((await fn(request('/payments/tx-1/allocate','POST',command))).status,200);assert.equal(calls.at(-1)[1].transactionId,'tx-1');assert.equal(calls.at(-1)[1].requestId,command.requestId)});
test('handler rejects cross-origin browser requests',async()=>{const {fn}=handler();assert.equal((await fn(request('/home','GET',undefined,{origin:'https://attacker.example'}))).status,403)});
test('handler rejects duplicate query parameters',async()=>{const {fn}=handler();assert.equal((await fn(request('/payments?q=a&q=b'))).status,400)});
test('handler rejects unsupported query member scope',async()=>{const {fn}=handler();assert.equal((await fn(request('/payments?groupId=another'))).status,400)});
test('request stream larger than 8KiB rejected',async()=>{const {fn}=handler();assert.equal((await fn(request('/members','POST',{name:'x'.repeat(9000),phone:'0780000001',requestId:crypto.randomUUID()}))).status,413)});
test('unknown route is 404 not HTML application fallback',async()=>{const {fn}=handler();const r=await fn(request('/unknown'));assert.equal(r.status,404);assert.match(r.headers.get('content-type'),/application\/json/)});
test('unexpected failure does not expose stack or secret',async()=>{const {fn}=handler();const r=await fn(request('/home','GET',undefined,{authorization:'Bearer '+ 'f'.repeat(64)}));assert.equal(r.status,503);assert.equal(await r.text(),'{"ok":false,"error":{"code":"service_unavailable"}}')});
test('staff credential action includes requestId in allowlist',async()=>{const {fn,calls}=handler();const c={action:'disable',id:'staff-1',expectedVersion:2,requestId:crypto.randomUUID()};assert.equal((await fn(request('/staff','PATCH',c))).status,200);assert.deepEqual(calls.at(-1)[1],c)});
test('statement content type and attachment filename controlled',async()=>{const {fn}=handler();const r=await fn(request('/members/member-1/ledger.csv'));assert.match(r.headers.get('content-type'),/text\/csv/);assert.match(r.headers.get('content-disposition'),/burimunsi-ledger.csv/)});
test('status read never resends a payment command',async()=>{const {fn,calls}=handler();const r=await fn(request('/operations/request-1'));assert.equal((await r.json()).data.state,'pending');assert.equal(calls.filter(c=>c[0]==='allocate').length,0)});

function smsRecords(){const f=records();f.data.actor.role='admin';f.data.actor.installationProfile='internal_receiver';f.data.actor.capabilities=[...f.data.actor.capabilities,'sms.read'];return f;}
for(const filter of ['queued','duplicate','synced','rejected'])test('SMS filter is authenticated and scoped: '+filter,async()=>{const {svc,data}=smsRecords();data.rows=[{id:'sms-1',groupId:'group-1',sender:'M-Money',at:'2026-11-07T12:00:00Z',preview:'Synthetic receipt',state:filter}];assert.equal((await svc.page(actor,'sms',{filter})).items[0].state,filter)});
test('an SMS source adapter cannot silently ignore its filter',async()=>{const {svc,data}=smsRecords();data.rows=[{id:'sms-1',groupId:'group-1',state:'synced'}];await assert.rejects(svc.page(actor,'sms',{filter:'queued'}),/receipt_filter_contract_violation/)});
test('payment filters reject receipt state vocabulary',async()=>{const {svc}=records();await assert.rejects(svc.page(actor,'payments',{filter:'queued'}),/invalid_filter/)});
test('SMS cursors cannot be reused with a different receipt filter',async()=>{const {svc,data}=smsRecords();data.rows=[{id:'sms-1',groupId:'group-1',state:'queued'}];data.after={offset:1};const first=await svc.page(actor,'sms',{filter:'queued'});await assert.rejects(svc.page(actor,'sms',{filter:'duplicate',cursor:first.nextCursor}),/cursor_scope_changed/)});
