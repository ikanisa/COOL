import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeListingQuery,selectListing,canonicalListingInstant,listingText} from '../../domain/burimunsi/listing-query.js';
import {RecordsService} from '../../domain/burimunsi/records-service.js';
import {PostgresRecordsStore} from '../../domain/burimunsi/postgres-records-store.js';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {ScopedCursor} from '../../domain/burimunsi/cursor.js';
import {validateNativeQuery} from '../../domain/burimunsi/wire/native-contract.mjs';
import {actor,admin} from './fixtures.mjs';

const NOW=1794657600000;
const at=i=>new Date(NOW+i*1000).toISOString();
function entry(i){
 const item={id:'tx-'+String(i).padStart(4,'0'),groupId:'group-1',payerNameRaw:'Person '+i,payerPhoneRaw:'*********123',amountRwf:i,
  atRaw:at(i),ftId:'F'+i,state:'recorded',version:1,memberId:null,memberPhone:null,sourceId:null,
  direction:i%2?'incoming':'outgoing',outcome:i%3?'successful':'failed',sourceKind:'observation',feeRwf:null,walletBalanceAfterRwf:null};
 return {item,at:at(i),amount:i,direction:item.direction,outcome:item.outcome,filters:['recorded'],search:listingText([item.id,item.payerNameRaw,item.ftId].join(' '))};
}
const all=Array.from({length:151},(_,i)=>entry(i+1));
function fixture(){
 const state={entries:structuredClone(all),actor:{...actor,expiresAt:NOW+1000000},snapshots:0};
 const tx={reloadActor:async()=>state.actor,loadBinding:async()=>null,
  readListingSnapshot:async()=>{state.snapshots++;return {entries:state.entries,asOf:at(0)};}};
 const service=new RecordsService({store:{withReadSnapshot:fn=>fn(tx)},groupId:'group-1',cursor:new ScopedCursor(new Uint8Array(32).fill(9)),clock:()=>NOW});
 return {state,service};
}
test('filter and sort cover rows beyond the first loaded page with exact total',()=>{
 const p=selectListing(all,'payments',{sort:'amount_desc',minRwf:'140',limit:3});
 assert.equal(p.totalCount,12);assert.deepEqual(p.items.map(r=>r.amountRwf),[151,150,149]);assert.deepEqual(p.after,{offset:3});
});
test('all matching records paginate without duplicates or hidden truncation',()=>{
 const ids=[];let after=null;
 do{const p=selectListing(all,'payments',{sort:'oldest',limit:40},after);ids.push(...p.items.map(r=>r.id));after=p.after;}while(after);
 assert.equal(ids.length,151);assert.equal(new Set(ids).size,151);assert.equal(ids[150],'tx-0151');
});
test('inclusive start and exclusive end use canonical UTC instants',()=>{
 const p=selectListing(all,'payments',{sort:'newest',fromAt:at(148),untilAt:at(151)});
 assert.deepEqual(p.items.map(r=>r.amountRwf),[150,149,148]);
});
test('missing provider date and notice amount remain null and sort last',()=>{
 const notice={...entry(999),at:null,amount:null,item:{...entry(999).item,amountRwf:null,ftId:null,direction:'other',outcome:'unknown'}};
 assert.equal(selectListing([...all,notice],'payments',{sort:'amount_desc'}).items[0].amountRwf,151);
 assert.equal(selectListing([notice],'payments',{sort:'newest',minRwf:'0'}).totalCount,0);
 assert.equal(selectListing([notice],'payments',{sort:'newest',fromAt:at(0)}).totalCount,0);
});
test('direction/outcome and credit are independent full-data predicates',()=>{
 const rows=[entry(1),entry(2),{...entry(3),item:{...entry(3).item,state:'posted'}}];
 assert.deepEqual(selectListing(rows,'payments',{sort:'newest',direction:'incoming',outcome:'successful',credit:'uncredited'}).items.map(r=>r.id),['tx-0001']);
 assert.equal(selectListing(rows,'payments',{sort:'newest',credit:'credited'}).items.length,1);
});
test('member active/balance/name/phone filtering has deterministic ID ties',()=>{
 const rows=[['m2','Beta',100,false],['m1','Alpha',200,true],['m3','Alpha',300,true]].map(([id,name,balance,active])=>({item:{id,active},name:listingText(name),phone:id,amount:balance,at:at(1),search:name.toLowerCase()}));
 assert.deepEqual(selectListing(rows,'members',{sort:'name_asc',active:'active',minRwf:'200'}).items.map(r=>r.id),['m1','m3']);
 assert.deepEqual(selectListing(rows,'members',{sort:'balance_desc',limit:1}).items.map(r=>r.id),['m3']);
});
test('signed ledger and history bounds keep corrections negative',()=>{
 const rows=[-100,50,300].map((amount,i)=>({item:{id:'e'+i,kind:'ledger_entry'},amount,at:at(i),search:''}));
 assert.equal(selectListing(rows,'ledger',{sort:'amount_asc',maxRwf:'0'}).items[0].id,'e0');
 assert.equal(selectListing(rows,'history',{sort:'amount_asc',filter:'ledger_entry',maxRwf:'0'}).totalCount,1);
});
test('search is literal and never interprets wildcard or SQL syntax',()=>{
 assert.equal(selectListing(all,'payments',{sort:'newest',q:'Person 151'}).totalCount,1);
 assert.equal(selectListing(all,'payments',{sort:'newest',q:'%'}).totalCount,0);
 assert.equal(selectListing(all,'payments',{sort:'newest',q:"' OR 1=1"}).totalCount,0);
});
test('a duplicate source row is an error rather than silent deduplication',()=>assert.throws(()=>selectListing([all[0],all[0]],'payments',{sort:'newest'}),/invalid_snapshot/));
test('over-budget source data fails explicitly',()=>assert.throws(()=>selectListing(Array(100001),'payments',{sort:'newest'}),/snapshot_limit/));
for(const query of [{sort:'random'},{minRwf:'1e3'},{minRwf:'1.5'},{maxRwf:'9007199254740992'},{minRwf:'20',maxRwf:'10'},
 {fromAt:'2026-02-30T00:00:00Z'},{fromAt:'2026-11-14T00:00:00'},{fromAt:at(2),untilAt:at(1)},{direction:'in'},{credit:'verified'},{q:'bad\nvalue'},{groupId:'other'}])
 test('invalid payment selector fails '+JSON.stringify(query),()=>assert.throws(()=>normalizeListingQuery('payments',query)));
for(const [kind,query]of [['sms',{minRwf:'1'}],['staff',{fromAt:at(0)}],['members',{direction:'incoming'}],['audit',{active:'inactive'}],['observations',{filter:'synced'}]])
 test('unsupported selector is not silently applied '+kind,()=>assert.throws(()=>normalizeListingQuery(kind,query)));
test('timezone-less or invalid record dates are not invented',()=>{
 assert.equal(canonicalListingInstant('2026-02-30T10:00:00Z'),null);assert.equal(canonicalListingInstant('2026-11-14 10:00:00'),null);
 assert.equal(canonicalListingInstant('2026-11-14T14:00:00+02:00'),'2026-11-14T12:00:00.000Z');
});
test('advanced cursor includes the full-data revision, query and deterministic order',async()=>{
 const {service,state}=fixture(),q={sort:'amount_desc',limit:40};
 const first=await service.page(state.actor,'payments',q);assert.equal(first.totalCount,151);assert(first.nextCursor);
 const second=await service.page(state.actor,'payments',{...q,cursor:first.nextCursor});assert.equal(second.items[0].amountRwf,111);
 await assert.rejects(service.page(state.actor,'payments',{...q,sort:'amount_asc',cursor:first.nextCursor}),/cursor_scope_changed/);
 state.entries[150].item.payerNameRaw='Changed without a version bump';
 await assert.rejects(service.page(state.actor,'payments',{...q,cursor:first.nextCursor}),/cursor_scope_changed/);
});
test('a changed hidden sort/search field also invalidates the cursor',async()=>{
 const {service,state}=fixture(),q={sort:'newest',limit:40};const first=await service.page(state.actor,'payments',q);
 state.entries[0].at=at(999);
 await assert.rejects(service.page(state.actor,'payments',{...q,cursor:first.nextCursor}),/cursor_scope_changed/);
});
test('advanced cursor cannot cross member, operator or role boundaries',async()=>{
 const {service,state}=fixture(),q={sort:'newest',limit:40};const first=await service.page(state.actor,'payments',q);
 await assert.rejects(service.page(state.actor,'payments',{...q,memberId:'other-member',cursor:first.nextCursor}),/cursor_scope_changed/);
 state.actor={...state.actor,id:'other-actor'};
 await assert.rejects(service.page(state.actor,'payments',{...q,cursor:first.nextCursor}),/cursor_scope_changed/);
 state.actor={...state.actor,capabilities:[]};const before=state.snapshots;
 await assert.rejects(service.page(state.actor,'payments',q),/access_denied/);assert.equal(state.snapshots,before);
});
test('advanced staff/SMS/audit reads retain existing Admin capability ceilings',async()=>{
 const {service,state}=fixture();
 for(const kind of ['staff','sms','audit'])await assert.rejects(service.page(state.actor,kind,{sort:'newest'}),/access_denied/);
 assert.equal(state.snapshots,0);
});
test('cross-group and sensitive rows remain rejected on the new list path',async()=>{
 const {service,state}=fixture();state.entries=[{...entry(1),item:{...entry(1).item,groupId:'other'}}];
 await assert.rejects(service.page(state.actor,'payments',{sort:'newest'}),/reader_scope_violation/);
 state.entries=[{...entry(1),item:{...entry(1).item,rawBody:'not allowed'}}];
 await assert.rejects(service.page(state.actor,'payments',{sort:'newest'}),/sensitive_projection/);
});
test('additive wire selectors validate exactly and preserve old requests',()=>{
 assert.deepEqual({...validateNativeQuery('payments','q=Example&filter=all')},{q:'Example',filter:'all'});
 assert.equal(validateNativeQuery('payments','sort=amount_desc&minRwf=100&direction=incoming').sort,'amount_desc');
 assert.equal(validateNativeQuery('history','sort=oldest&filter=ledger_entry').filter,'ledger_entry');
 for(const [kind,query]of [['sms','minRwf=100'],['members','fromAt=2026-11-14T00%3A00%3A00Z'],['payments','sort=DROP'],['payments','sort=newest&sort=oldest']])assert.throws(()=>validateNativeQuery(kind,query));
});
test('strict native HTTP carries the complete filtered/sorted total and existing role limits',async()=>{
 const {state,service}=fixture(),installation='22222222-2222-4222-8222-222222222222',requestId='11111111-1111-4111-8111-111111111111';
 state.actor={...state.actor,installationId:installation,sessionId:requestId};
 const noop=async()=>({});
 const handle=createNativeHandler({auth:{login:noop,authenticate:async()=>state.actor,logout:noop,changePasscode:noop,manageStaff:noop},
  records:service,contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  origin:'https://native.example.test',groupId:'group-1',strictContract:true,networkBucket:noop});
 const get=path=>new Request('https://native.example.test/v1/burimunsi'+path,{headers:{'x-burimunsi-installation':installation,
  'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':requestId,'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64)}});
 const response=await handle(get('/payments?sort=amount_desc&minRwf=140&limit=3'));
 assert.equal(response.status,200);const json=await response.json();assert.equal(json.data.totalCount,12);
 assert.deepEqual(json.data.items.map(r=>r.amountRwf),[151,150,149]);assert(json.data.nextCursor);
 assert.equal((await handle(get('/sms?sort=newest&minRwf=10'))).status,400);
 assert.equal((await handle(get('/staff?sort=name_asc&active=active'))).status,403);
});
test('Postgres member pages project money only for bounded, group-scoped rows',async()=>{
 const calls=[],rows=[{id:'member-1',collection_id:'group-1',full_name:'Example',momo_number:'0780000816',balance:'300',active:1,revision:1,joined_at:at(0)}];
 const sql={unsafe:async(q,args)=>{calls.push({q,args});return q.startsWith('SELECT count(*)')?[{total:1}]:rows;}};
 const store=new PostgresRecordsStore({authority:{groupId:'group-1',read:fn=>fn(sql),session:async()=>actor},sourceReader:{revision:async()=>'',page:async()=>null,detail:async()=>null},clock:()=>NOW});
 const listing=normalizeListingQuery('members',{sort:'newest',limit:3});
 const page=await store.withReadSnapshot(tx=>tx.readMemberPage({groupId:'group-1',listing,after:null,anchorId:null}));
 assert.equal(page.items[0].balanceRwf,300);assert.equal(page.totalCount,1);
 assert.match(calls[0].q,/m\.collection_id=\$1/);assert.doesNotMatch(calls[0].q,/ledger_entries/);
 assert.match(calls[1].q,/LIMIT \$2\)[\s\S]+sum\(l.amount_minor\)/);assert.deepEqual(calls[1].args,['group-1',4]);
 assert.doesNotMatch(calls[1].q,/OFFSET|INSERT|UPDATE|DELETE|raw_body|token_hash|pin_hash/i);
 await assert.rejects(store.withReadSnapshot(tx=>tx.readMemberPage({groupId:'other',listing,after:null,anchorId:null})),/access_denied/);
});
test('canonical reversal direction agrees with the new filter and returned DTO',async()=>{
 const databaseRow={id:'tx-reversal',collection_id:'group-1',canonical_event_kind:'reversal',payer_name:'Example',payer_identifier:'*********123',
  amount_minor:'1000',transaction_at:at(0),transaction_datetime_raw:'2026-11-14 14:00:00',provider_transaction_id:'R123',source_conflict:false,
  has_conflict:0,version:1,allocation_state:'unallocated',created_at:at(0),member_id:null,momo_number:null,payment_status:null,ledger_posted:false,source_id:'source-1'};
 const store=new PostgresRecordsStore({authority:{groupId:'group-1',read:fn=>fn({unsafe:async()=>[databaseRow]}),session:async()=>actor},
  sourceReader:{revision:async()=>'',page:async()=>null,detail:async()=>null},clock:()=>NOW});
 const full=await store.withReadSnapshot(tx=>tx.readListingSnapshot({groupId:'group-1',kind:'payments',memberId:null}));
 const result=selectListing(full.entries,'payments',{sort:'newest',direction:'reversal'});
 assert.equal(result.totalCount,1);assert.equal(result.items[0].direction,'reversal');assert.equal(result.items[0].outcome,'successful');
 assert.equal(selectListing(full.entries,'payments',{sort:'newest',filter:'unallocated'}).totalCount,0);
});
