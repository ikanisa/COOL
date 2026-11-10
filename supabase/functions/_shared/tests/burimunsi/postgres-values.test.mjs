import test from 'node:test';import assert from 'node:assert/strict';
import {pgInteger} from '../../domain/burimunsi/postgres-values.js';
import {PostgresRecordsStore} from '../../domain/burimunsi/postgres-records-store.js';
for(const value of [null,undefined,'',false,true,NaN,Infinity,1.2,'1.2','1e3',' 0','01','0x10','9007199254740992',{},[]])test('reject non-integer database value '+String(value),()=>assert.throws(()=>pgInteger(value),/invalid_database_integer/));
for(const value of [0,'0',1,'10000',-1,'-10000','9007199254740991','-9007199254740991'])test('retain exact integer '+String(value),()=>assert.equal(pgInteger(value),Number(value)));
test('bounds are explicit for counters and revisions',()=>{assert.throws(()=>pgInteger(-1,{minimum:0}));assert.throws(()=>pgInteger(2,{maximum:1}));assert.equal(pgInteger('1',{minimum:1,maximum:1}),1)});
function fixture(row){
 const queries=[];const sql={unsafe:async(q,v)=>{queries.push(q);return [row]}};
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
test('signed ledger projection normalizes member reference without rewriting source evidence',async()=>{
 const f=fixture({total:1,id:'e',collection_id:'g',transaction_id:'p',amount_minor:-10000,source_at:'EXACT SOURCE TIME',ft_id:'90000000001',payer_name:' Exact Payer ',momo_number:'0780000816'});
 const page=await f.store.withReadSnapshot(tx=>tx.readPage({groupId:'g',kind:'ledger',memberId:'m',limit:40,q:'',filter:'all'}));
 assert.equal(page.items[0].memberPhone,'+250780000816');assert.equal(page.items[0].amountRwf,-10000);assert.equal(page.items[0].payerNameRaw,' Exact Payer ');assert.equal(page.items[0].atRaw,'EXACT SOURCE TIME');
});
test('masked member identity cannot borrow a complete login phone',async()=>{
 const f=fixture({id:'m',collection_id:'g',full_name:'Example',momo_number:'*********816',phone:'+250780000816',balance:0,active:1,revision:1});
 await assert.rejects(f.store.withReadSnapshot(tx=>tx.readDetail({groupId:'g',kind:'member',id:'m'})),error=>error.code==='invalid_member_projection'&&error.status===503);
});
for(const kind of ['payments','members','ledger','staff','audit'])test('revision SQL bounds result materialization for '+kind,async()=>{
 const f=fixture({id:'one',version:1});await f.store.withReadSnapshot(tx=>tx.listRevision('g',kind,'m'));
 assert.match(f.queries[0],/LIMIT 100001/);
});
