import test from 'node:test';import assert from 'node:assert/strict';
import {pgInteger} from '../../domain/burimunsi/postgres-values.js';
import {PostgresRecordsStore} from '../../domain/burimunsi/postgres-records-store.js';
for(const value of [null,undefined,'',false,true,NaN,Infinity,1.2,'1.2','1e3',' 0','01','0x10','9007199254740992',{},[]])test('reject non-integer database value '+String(value),()=>assert.throws(()=>pgInteger(value),/invalid_database_integer/));
for(const value of [0,'0',1,'10000',-1,'-10000','9007199254740991','-9007199254740991'])test('retain exact integer '+String(value),()=>assert.equal(pgInteger(value),Number(value)));
test('bounds are explicit for counters and revisions',()=>{assert.throws(()=>pgInteger(-1,{minimum:0}));assert.throws(()=>pgInteger(2,{maximum:1}));assert.equal(pgInteger('1',{minimum:1,maximum:1}),1)});
function fixture(row){
 const queries=[];const sql={unsafe:async(q,v)=>{queries.push(q);return [q.includes(' AS source_conflict')&&!Object.hasOwn(row,'source_conflict')?{...row,source_conflict:false}:row]}};
 return {queries,store:new PostgresRecordsStore({authority:{groupId:'g',session:async()=>null,read:fn=>fn(sql)},sourceReader:{revision:async()=>'',page:async()=>null,detail:async()=>null}})};
}
test('null database balance cannot turn into zero member savings',async()=>{
 const f=fixture({id:'m',collection_id:'g',full_name:'Example',momo_number:'+250780000816',balance:null,active:1,revision:1});
 await assert.rejects(f.store.withReadSnapshot(tx=>tx.readDetail({groupId:'g',kind:'member',id:'m'})),/invalid_database_integer/);
});
test('native member projection normalizes the existing local MoMo route only',async()=>{
 const f=fixture({id:'m',collection_id:'g',full_name:'Exact Member Name',momo_number:'0780000816',phone:'+250790000111',balance:'10000',active:1,revision:'2'});
 const row=await f.store.withReadSnapshot(tx=>tx.readDetail({groupId:'g',kind:'member',id:'m'}));
 assert.equal(row.phone,'+250780000816');assert.equal(row.name,'Exact Member Name');assert.equal(row.balanceRwf,10000);assert.equal(row.version,2);
});
test('payment reference normalization preserves original masked payer and timestamp evidence',async()=>{
 const f=fixture({id:'p',collection_id:'g',payer_name:' Exact Provider Name ',payer_identifier:'*********816',amount_minor:10000,
  transaction_datetime_raw:'08/10/2026 15:15:20',provider_transaction_id:'90000000001',has_conflict:0,payment_status:'confirmed',version:1,member_id:'m',momo_number:'0780000816'});
 const row=await f.store.withReadSnapshot(tx=>tx.readDetail({groupId:'g',kind:'payment',id:'p'}));
 assert.equal(row.memberPhone,'+250780000816');assert.equal(row.payerPhoneRaw,'*********816');assert.equal(row.payerNameRaw,' Exact Provider Name ');assert.equal(row.atRaw,'08/10/2026 15:15:20');
});
test('an unallocated payment does not acquire an invented member phone',async()=>{
 const f=fixture({id:'p',collection_id:'g',amount_minor:10000,has_conflict:0,version:1,allocation_state:'unallocated',momo_number:null});
 const row=await f.store.withReadSnapshot(tx=>tx.readDetail({groupId:'g',kind:'payment',id:'p'}));assert.equal(row.memberId,null);assert.equal(row.memberPhone,null);
});
test('native transaction exposes an original SMS link only to its authorized capture account',async()=>{
 const row={id:'p',collection_id:'g',payer_name:null,payer_identifier:null,amount_minor:null,
  transaction_datetime_raw:null,provider_transaction_id:null,has_conflict:0,version:1,allocation_state:'not_applicable',
  momo_number:null,native_source_id:'source-1',event_kind:'outgoing',fee_minor:null,wallet_balance_after_minor:null,
  native_meta:{sourceId:'source-1',outcome:'successful',canReveal:false}};
 const f=fixture(row);const read=()=>f.store.withReadSnapshot(tx=>tx.readDetail({groupId:'g',kind:'payment',id:'p'}));
 const restricted=await read();assert.equal(restricted.sourceId,null);assert.equal(restricted.direction,'outgoing');
 assert.equal(restricted.amountRwf,null);assert.equal(restricted.ftId,null);
 row.source_conflict=true;assert.equal((await read()).state,'recorded');
 row.native_meta.canReveal=true;assert.equal((await read()).sourceId,'source-1');
 delete row.native_meta.canReveal;await assert.rejects(read(),/invalid_transaction_projection/);
});
for(const [status,posted,conflict,allocation,expected] of [
 ['confirmed',true,0,'linked','posted'],['confirmed',false,0,'linked','processing'],
 ['confirmed',false,0,'unallocated','unallocated'],['corrected',false,0,'linked','corrected'],
 ['reversed',false,0,'linked','reversed'],['confirmed',true,1,'linked','conflict']
])test('payment state requires canonical credit or its actual non-credit state '+[status,posted,conflict,allocation].join('/'),async()=>{
 const f=fixture({id:'p',collection_id:'g',amount_minor:10000,payment_status:status,ledger_posted:posted,
  has_conflict:conflict,version:1,allocation_state:allocation,momo_number:null});
 const row=await f.store.withReadSnapshot(tx=>tx.readDetail({groupId:'g',kind:'payment',id:'p'}));assert.equal(row.state,expected);
});
test('a conflicting source changes the managed payment state without requiring a flag update',async()=>{
 const f=fixture({id:'p',collection_id:'g',amount_minor:10000,payment_status:'confirmed',ledger_posted:true,
  has_conflict:0,source_conflict:true,version:1,allocation_state:'linked',momo_number:null});
 const row=await f.store.withReadSnapshot(tx=>tx.readDetail({groupId:'g',kind:'payment',id:'p'}));
 assert.equal(row.state,'conflict');
});
test('signed ledger projection normalizes member reference without rewriting source evidence',async()=>{
 const f=fixture({total:1,id:'e',collection_id:'g',transaction_id:'p',amount_minor:-10000,source_at:'EXACT SOURCE TIME',ft_id:'90000000001',payer_name:' Exact Payer ',momo_number:'0780000816'});
 const page=await f.store.withReadSnapshot(tx=>tx.readPage({groupId:'g',kind:'ledger',memberId:'m',limit:40,q:'',filter:'all'}));
 assert.equal(page.items[0].memberPhone,'+250780000816');assert.equal(page.items[0].amountRwf,-10000);assert.equal(page.items[0].payerNameRaw,' Exact Payer ');assert.equal(page.items[0].atRaw,'EXACT SOURCE TIME');
});
test('masked member identity cannot borrow a complete login phone',async()=>{
 const f=fixture({id:'m',collection_id:'g',full_name:'Example',momo_number:'*********816',phone:'+250780000816',balance:0,active:1,revision:1});
 await assert.rejects(f.store.withReadSnapshot(tx=>tx.readDetail({groupId:'g',kind:'member',id:'m'})),error=>error.code==='invalid_member_projection'&&error.status===503);
});
test('home projects the canonical ledger amount for each recent credit',async()=>{
 const sql={unsafe:async q=>{
  if(q.startsWith('SELECT coalesce(sum(amount_minor)'))return[{balance:'12000'}];
  if(q.startsWith('SELECT coalesce(sum(c.credited_amount)'))return[{today:'12000'}];
  if(q.includes(' AS unallocated_amount'))return[{members:'1',unallocated:'0',unallocated_amount:'0'}];
  return[{id:'p',collection_id:'g',payer_name:'Example',payer_identifier:'***111',amount_minor:'11000',credited_amount:'12000',
   transaction_datetime_raw:'2026-11-11 12:00:00',provider_transaction_id:'synthetic-ref',has_conflict:0,source_conflict:false,payment_status:'confirmed',ledger_posted:true,version:1,momo_number:null}];
 }};
 const store=new PostgresRecordsStore({authority:{groupId:'g',session:async()=>null,read:fn=>fn(sql)},sourceReader:{revision(){},page(){},detail(){}}});
 const home=await store.withReadSnapshot(tx=>tx.canonicalHome('g'));
 assert.equal(home.groupBalanceRwf,12000);assert.equal(home.todayRwf,12000);assert.equal(home.recentPayments[0].amountRwf,12000);
 assert.equal(home.recentPayments[0].state,'posted');assert.equal(home.recentPayments[0].sourceId,null);
});
for(const kind of ['payments','ledger','staff','audit'])test('revision SQL bounds result materialization for '+kind,async()=>{
 const f=fixture({id:'one',version:1});await f.store.withReadSnapshot(tx=>tx.listRevision('g',kind,'m'));
 assert.match(f.queries[0],/LIMIT 100001/);
});


test('Members reads a bounded generation without projecting every member',async()=>{
 const f=fixture({id:'one',revision:1});
 const revision=await f.store.withReadSnapshot(tx=>tx.memberListingRevision('g'));
 assert.equal(typeof revision,'string');
 assert.match(f.queries[0],/SELECT revision FROM private\.member_history_versions WHERE collection_id=\$1/);
 assert.doesNotMatch(f.queries[0],/FROM app\.memberships|from app\.users/i);
});
