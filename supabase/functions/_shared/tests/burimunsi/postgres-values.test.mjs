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
for(const kind of ['payments','members','ledger','staff','audit'])test('revision SQL bounds result materialization for '+kind,async()=>{
 const f=fixture({id:'one',version:1});await f.store.withReadSnapshot(tx=>tx.listRevision('g',kind,'m'));
 assert.match(f.queries[0],/LIMIT 100001/);
});
