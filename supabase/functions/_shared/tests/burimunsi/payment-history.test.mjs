import test from 'node:test';import assert from 'node:assert/strict';
import {projectPaymentHistory,HISTORY_LIMIT} from '../../domain/burimunsi/payment-history.js';
import {RecordsService} from '../../domain/burimunsi/records-service.js';
import {PostgresRecordsStore} from '../../domain/burimunsi/postgres-records-store.js';
import {ScopedCursor} from '../../domain/burimunsi/cursor.js';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {actor} from './fixtures.mjs';
const NOW=1794132000000;
const observation=(transactionId='tx-1')=>({canonicalRecordId:transactionId,groupId:'group-1',transactionId,kind:'transaction_recorded',recordedAt:'2026-11-08T08:00:00.000Z',amountRwf:null,memberId:null});
const entry=(n=1,delta=10000)=>({...observation(),canonicalRecordId:'entry-'+n,kind:'ledger_entry',recordedAt:'2026-11-08T08:00:01.000Z',amountRwf:delta,memberId:'member-1'});
const project=rows=>projectPaymentHistory(rows,'group-1','tx-1');
function fixture(){
 const data={actor:structuredClone(actor),rows:[observation(),entry(1),entry(2,-10000)],version:1,paymentId:'tx-1',calls:0};
 const tx={reloadActor:async()=>data.actor,loadBinding:async()=>null,
 readDetail:async q=>data.missing?null:({id:data.paymentId,groupId:'group-1',version:data.version,state:'reversed'}),
 readPaymentHistory:async(g,t,max)=>{data.calls++;assert.equal(max,HISTORY_LIMIT+1);return data.rows}};
 const cursor=new ScopedCursor(new Uint8Array(32).fill(3));
 const svc=new RecordsService({store:{withReadSnapshot:fn=>fn(tx)},groupId:'group-1',cursor,clock:()=>NOW});
 return {data,tx,svc,cursor};
}
test('history records observation and signed ledger deltas, not imagined lifecycle stages',()=>{const events=project([entry(1),observation(),entry(2,-10000)]);assert.equal(events[0].kind,'transaction_recorded');assert.equal(events[0].amountRwf,null);assert.deepEqual(events.slice(1).map(e=>e.amountRwf),[10000,-10000]);assert(!events.some(e=>['refund','allocated','confirmed'].includes(e.kind)))});
test('history stable tie order is based on event IDs',()=>assert.deepEqual(project([entry(2),entry(1),observation()]).map(e=>e.id),['transaction:tx-1','ledger:entry-1','ledger:entry-2']));
test('history projection strips extra fields',()=>assert.equal(project([{...observation(),unlisted:'never-return'}])[0].unlisted,undefined));
for(const [label,patch,pattern] of [
 ['other group',{groupId:'other'},/history_scope/],['other transaction',{transactionId:'tx-2'},/history_scope/],
 ['unknown stage',{kind:'credit_guessed'},/invalid_history_event/],['invalid source ID',{canonicalRecordId:'../secret'},/invalid_id/],
 ['missing time',{recordedAt:null},/invalid_history_timestamp/],['local time without timezone',{recordedAt:'2026-11-08 08:00:01'},/invalid_history_timestamp/],
 ['invalid calendar date',{recordedAt:'2026-02-30T08:00:01.000Z'},/invalid_history_timestamp/],
 ['missing amount',{amountRwf:undefined},/invalid_history_amount/],['fractional amount',{amountRwf:100.5},/invalid_history_amount/],
 ['unsafe integer',{amountRwf:9007199254740992},/invalid_history_amount/],['zero ledger change',{amountRwf:0},/invalid_history_amount/],
 ['missing member',{memberId:null},/invalid_id/],['raw SMS leakage',{rawBody:'private'},/sensitive_projection/],
 ['credential leakage',{tokenHash:'private'},/sensitive_projection/]
])test('history fails closed: '+label,()=>assert.throws(()=>project([observation(),{...entry(),...patch}]),pattern));
test('observation cannot claim money moved',()=>assert.throws(()=>project([{...observation(),amountRwf:10000}]),/invalid_history_event/));
test('observation must refer to the exact transaction',()=>assert.throws(()=>project([{...observation(),canonicalRecordId:'tx-2'}]),/invalid_history_event/));
test('ledger rows cannot substitute for the missing source observation',()=>assert.throws(()=>project([entry()]),/history_observation_required/));
test('duplicate event IDs fail instead of being hidden',()=>assert.throws(()=>project([observation(),entry(),entry()]),/duplicate_history_event/));
test('empty history does not invent a transaction event',()=>assert.throws(()=>project([]),/history_observation_required/));
test('bounded history fails explicitly instead of silently truncating',()=>assert.throws(()=>project([observation(),...Array.from({length:HISTORY_LIMIT},(_,i)=>entry(i))]),/history_limit/));
test('history list supports paginated access without SMS permission',async()=>{const{svc}=fixture();const p=await svc.paymentHistory(actor,'tx-1',{limit:2});assert.equal(p.totalCount,3);assert(p.nextCursor);const last=await svc.paymentHistory(actor,'tx-1',{limit:2,cursor:p.nextCursor});assert.equal(last.items[0].amountRwf,-10000);assert.equal(last.nextCursor,null)});
test('advanced history filters the whole validated stream and preserves signed ledger facts',async()=>{
 const{svc}=fixture();const p=await svc.paymentHistory(actor,'tx-1',{sort:'amount_asc',filter:'ledger_entry',maxRwf:'0',limit:1});
 assert.equal(p.totalCount,1);assert.equal(p.items[0].amountRwf,-10000);assert.equal(p.nextCursor,null);
});
test('rechecking fresh authority blocks revoked readers',async()=>{const{svc,data}=fixture();data.actor.revoked=true;await assert.rejects(svc.paymentHistory(actor,'tx-1'),/session_unavailable/);assert.equal(data.calls,0)});
test('record read capability is mandatory',async()=>{const{svc,data}=fixture();data.actor.capabilities=[];await assert.rejects(svc.paymentHistory(actor,'tx-1'),/access_denied/)});
test('missing payment is a scoped 404 before querying its ledger',async()=>{const{svc,data}=fixture();data.missing=true;await assert.rejects(svc.paymentHistory(actor,'tx-1'),e=>e.status===404);assert.equal(data.calls,0)});
test('wrong payment identity from adapter is refused',async()=>{const{svc,data}=fixture();data.paymentId='tx-2';await assert.rejects(svc.paymentHistory(actor,'tx-1'),e=>e.status===404)});
test('cursor cannot cross payment identities',async()=>{const{svc,data}=fixture();const p=await svc.paymentHistory(actor,'tx-1',{limit:1});data.paymentId='tx-2';data.rows=[observation('tx-2')];await assert.rejects(svc.paymentHistory(actor,'tx-2',{limit:1,cursor:p.nextCursor}),/cursor_scope_changed/)});
test('cursor cannot cross operators',async()=>{const{svc,data}=fixture();const p=await svc.paymentHistory(actor,'tx-1',{limit:1});data.actor.id='other-operator';await assert.rejects(svc.paymentHistory(data.actor,'tx-1',{limit:1,cursor:p.nextCursor}),/cursor_scope_changed/)});
test('cursor rejects changed payment version',async()=>{const{svc,data}=fixture();const p=await svc.paymentHistory(actor,'tx-1',{limit:1});data.version++;await assert.rejects(svc.paymentHistory(actor,'tx-1',{limit:1,cursor:p.nextCursor}),/cursor_scope_changed/)});
test('cursor rejects changed ledger event facts',async()=>{const{svc,data}=fixture();const p=await svc.paymentHistory(actor,'tx-1',{limit:1});data.rows[1].amountRwf=12000;await assert.rejects(svc.paymentHistory(actor,'tx-1',{limit:1,cursor:p.nextCursor}),/cursor_scope_changed/)});
test('cursor rejects page-size changes',async()=>{const{svc}=fixture();const p=await svc.paymentHistory(actor,'tx-1',{limit:1});await assert.rejects(svc.paymentHistory(actor,'tx-1',{limit:2,cursor:p.nextCursor}),/cursor_scope_changed/)});
test('tampered cursor rejected',async()=>{const{svc}=fixture();await assert.rejects(svc.paymentHistory(actor,'tx-1',{cursor:'made.up'}),/invalid_cursor/)});
for(const query of [{limit:0},{limit:101},{limit:1.5},{limit:'2'},{cursor:''},{cursor:42},{groupId:'other'}])test('invalid history query '+JSON.stringify(query),async()=>{const{svc}=fixture();await assert.rejects(svc.paymentHistory(actor,'tx-1',query))});
function handler(){const{svc}=fixture();return createNativeHandler({
 auth:{login:async()=>{},authenticate:async()=>actor,logout:async()=>{},changePasscode:async()=>{},manageStaff:async()=>{}},records:svc,
 contributions:{allocate:async()=>{throw Error('must not mutate')}},members:{enroll:async()=>{},setActive:async()=>{}},gateway:{status:async()=>{},replace:async()=>{}},
 origin:'https://example.test',networkBucket:async()=>''});}
function req(path){return new Request('https://example.test/v1/burimunsi'+path,{headers:{'x-burimunsi-installation':'device-1',authorization:'Bearer '+'a'.repeat(64)}})}
test('history HTTP route returns no-store envelope',async()=>{const r=await handler()(req('/payments/tx-1/history?limit=1'));assert.equal(r.status,200);assert.equal(r.headers.get('Cache-Control'),'no-store');assert.equal((await r.json()).data.items[0].kind,'transaction_recorded')});
for(const q of ['?limit=1&limit=2','?groupId=other','?memberId=member-1','?filter=made_up'])test('history HTTP query rejects '+q,async()=>assert.equal((await handler()(req('/payments/tx-1/history'+q))).status,400));
test('history HTTP accepts the additive all filter',async()=>assert.equal((await handler()(req('/payments/tx-1/history?filter=all'))).status,200));
test('Postgres history adapter uses same-snapshot scoped canonical SQL and no mutation',async()=>{
 const calls=[];const sql={unsafe:async(query,args)=>{calls.push({query,args});return [{canonical_record_id:'tx-1',collection_id:'group-1',transaction_id:'tx-1',kind:'transaction_recorded',recorded_at:new Date('2026-11-08T08:00:00Z'),amount_minor:null,member_id:null}]}};
 const store=new PostgresRecordsStore({authority:{groupId:'group-1',read:fn=>fn(sql),session:async()=>actor},sourceReader:{revision:async()=>'',page:async()=>{},detail:async()=>{}},clock:()=>NOW});
 await store.withReadSnapshot(async tx=>{
  assert.equal((await tx.readPaymentHistory('group-1','tx-1',1001))[0].recordedAt,'2026-11-08T08:00:00.000Z');
  await assert.rejects(tx.readPaymentHistory('another','tx-1',1001),/access_denied/);
  await assert.rejects(tx.readPaymentHistory('group-1','tx-1',1002),/invalid_history_limit/);
 });
 assert.equal(calls.length,1);assert.deepEqual(calls[0].args,['group-1','tx-1',1001]);
 assert.match(calls[0].query,/l\.collection_id=x\.collection_id/);assert.match(calls[0].query,/t\.receiving_account_id=x\.receiving_account_id/);
 assert.doesNotMatch(calls[0].query,/INSERT|UPDATE|DELETE|raw_body|pin_hash/i);
});
