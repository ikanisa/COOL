import assert from 'node:assert/strict';
import test from 'node:test';
import {ledgerSnapshot} from '../src/snapshots.ts';
import {canonical,sha256,timestamp} from '../src/util.ts';
const appId='synthetic-app',to='+250788123456';
function body(overrides={}){return {event_id:'evt-1',recipient:to,collection_id:'group-1',collection_name:'Synthetic group',member_id:'member-1',currency:'RWF',entry:{type:'contribution',amount_rwf:100},snapshot:{basis:'cumulative_contributions',scope:'all_time',member_total_rwf:0,group_total_rwf:42,posted_at:'2026-11-04T12:00:00Z',ledger_version:'v1'},...overrides};}
function facts(b){const s=b.snapshot;return {event_id:b.event_id,collection_id:b.collection_id,collection_name:b.collection_name,member_id:b.member_id,currency:'RWF',entry:{type:b.entry.type,amount_rwf:b.entry.amount_rwf},snapshot:{basis:s.basis,scope:s.scope,period_id:s.scope==='cycle'?s.period_id:null,member_total_rwf:s.member_total_rwf,group_total_rwf:s.group_total_rwf,posted_at:timestamp(s.posted_at,'posted_at'),ledger_version:s.ledger_version}};}
class FakeDB {
 constructor(){this.events=new Map();this.receipts=new Map();this.batches=[];this.reads=[];this.beforeReceipt=null;}
 key(a,b){return `${a}\n${b}`;}
 receiptKey(a,b,c){return `${a}\n${b}\n${c}`;}
 async seed(b,{recipient=b.recipient,redacted=false,withReceipt=true}={}){
  const digest=await sha256(canonical(facts(b)));this.events.set(this.key(appId,b.event_id),{facts_digest:digest,redacted_at:redacted?'2026-11-04T12:05:00Z':null});
  if(withReceipt)this.receipts.set(this.receiptKey(appId,b.event_id,recipient),{message_id:'legacy-message',state:'sent'});
 }
 prepare(sql){const db=this;return {sql,bind(...args){return {sql,args,async first(){
  db.reads.push({sql,args});
  if(sql.startsWith('SELECT * FROM ledger_notification_events'))return db.events.get(db.key(args[0],args[1]))??null;
  if(sql.startsWith('SELECT r.message_id,m.state')){
   if(db.beforeReceipt)await db.beforeReceipt(db,args);
   const receipt=db.receipts.get(db.receiptKey(args[0],args[1],args[2]));
   if(!receipt)return null;
   if(sql.includes('JOIN ledger_notification_events e')){const event=db.events.get(db.key(args[0],args[1]));return event?{...receipt,facts_digest:event.facts_digest}:null;}
   return receipt;
  }
  if(sql.startsWith('SELECT facts_digest FROM ledger_notification_events'))return db.events.get(db.key(args[0],args[1]))??null;
  throw Error(`unexpected read ${sql}`);
 }};}};}
 async batch(statements){
  assert.equal(statements.length,3);assert.match(statements[0].sql,/^INSERT INTO ledger_notification_events/);
  assert.match(statements[1].sql,/^INSERT INTO messages/);assert.match(statements[2].sql,/^INSERT INTO ledger_notification_receipts/);
  this.batches.push(statements);
  return statements.map(()=>({results:[],meta:{changes:1}}));
 }
}
function context(db,principal={type:'application',id:appId,scopes:['contributions'],allowedKinds:['receipt']}){
 return {env:{DB:db},get(key){assert.equal(key,'principal');return principal;},json(value,status=200){return {body:value,status};}};
}
const reject=(code,status)=>error=>error.code===code&&error.status===status;
const cases=[
 ['fresh zero contribution cannot queue',async()=>{const db=new FakeDB();await assert.rejects(()=>ledgerSnapshot(context(db),body({entry:{type:'contribution',amount_rwf:0}})),reject('invalid_snapshot',400));assert.equal(db.batches.length,0);}],
 ['negative zero contribution cannot queue',async()=>{const db=new FakeDB();await assert.rejects(()=>ledgerSnapshot(context(db),body({entry:{type:'contribution',amount_rwf:-0}})),reject('invalid_snapshot',400));assert.equal(db.batches.length,0);}],
 ['old zero event cannot add a new recipient',async()=>{const db=new FakeDB(),b=body({entry:{type:'contribution',amount_rwf:0}});await db.seed(b);await assert.rejects(()=>ledgerSnapshot(context(db),{...b,recipient:'+250788000002'}),reject('invalid_snapshot',400));assert.equal(db.batches.length,0);}],
 ['legacy exact zero receipt replay stays available',async()=>{for(const redacted of [false,true]){const db=new FakeDB(),b=body({entry:{type:'contribution',amount_rwf:0}});await db.seed(b,{redacted});const x=await ledgerSnapshot(context(db),b);assert.deepEqual(x,{body:{message_id:'legacy-message',state:'existing'},status:202});assert.equal(db.batches.length,0);}}],
 ['concurrent conflicting event cannot masquerade as exact replay',async()=>{const db=new FakeDB(),requested=body(),other=body({entry:{type:'contribution',amount_rwf:200}});db.beforeReceipt=async d=>{d.beforeReceipt=null;await d.seed(other);};await assert.rejects(()=>ledgerSnapshot(context(db),requested),reject('snapshot_conflict',409));assert.equal(db.batches.length,0);}],
 ['concurrent exact event remains an existing replay',async()=>{const db=new FakeDB(),b=body();db.beforeReceipt=async d=>{d.beforeReceipt=null;await d.seed(b);};const x=await ledgerSnapshot(context(db),b);assert.equal(x.body.state,'existing');assert.equal(db.batches.length,0);}],
 ['a zero refusal does not fence an older in-flight issuer',async()=>{const db=new FakeDB(),b=body({entry:{type:'contribution',amount_rwf:0}});let release;const gate=new Promise(resolve=>{release=resolve;});const older=(async()=>{await gate;await db.seed(b);})();try{await assert.rejects(()=>ledgerSnapshot(context(db),b),reject('invalid_snapshot',400));}finally{release();await older;}assert.equal(db.receipts.get(db.receiptKey(appId,b.event_id,b.recipient)).message_id,'legacy-message');assert.equal(db.batches.length,0);}],
 ['same event conflicting facts remain conflict before replay or guard',async()=>{const db=new FakeDB(),old=body({entry:{type:'contribution',amount_rwf:0}});await db.seed(old);await assert.rejects(()=>ledgerSnapshot(context(db),{...old,entry:{type:'contribution',amount_rwf:1}}),reject('snapshot_conflict',409));assert.equal(db.batches.length,0);}],
 ['redacted zero event still rejects with the redaction disposition',async()=>{const db=new FakeDB(),b=body({entry:{type:'contribution',amount_rwf:0}});await db.seed(b,{redacted:true});await assert.rejects(()=>ledgerSnapshot(context(db),{...b,recipient:'+250788000002'}),reject('source_facts_redacted',409));assert.equal(db.batches.length,0);}],
 ['redacted old event rejects a new recipient',async()=>{const db=new FakeDB(),b=body();await db.seed(b,{redacted:true});await assert.rejects(()=>ledgerSnapshot(context(db),{...b,recipient:'+250788000002'}),reject('source_facts_redacted',409));assert.equal(db.batches.length,0);}],
 ['positive contribution preserves passed snapshot values',async()=>{const db=new FakeDB(),x=await ledgerSnapshot(context(db),body());assert.equal(x.status,202);assert.equal(db.batches.length,1);const m=db.batches[0][1].args;assert.equal(m[2],'receipt');assert.equal(m[3],to);assert.match(m[4],/contribution RWF 100/);assert.match(m[4],/Your contributions: RWF 0/);assert.match(m[4],/Group contributions: RWF 42/);}],
 ['maximum positive contribution remains accepted',async()=>{const db=new FakeDB(),x=await ledgerSnapshot(context(db),body({entry:{type:'contribution',amount_rwf:Number.MAX_SAFE_INTEGER}}));assert.equal(x.status,202);assert.equal(db.batches.length,1);}],
 ['zero refund remains unchanged',async()=>{const db=new FakeDB(),x=await ledgerSnapshot(context(db),body({entry:{type:'refund',amount_rwf:0}}));assert.equal(x.status,202);assert.equal(db.batches.length,1);}],
 ['negative correction remains unchanged',async()=>{const db=new FakeDB(),x=await ledgerSnapshot(context(db),body({entry:{type:'correction',amount_rwf:-1}}));assert.equal(x.status,202);assert.equal(db.batches.length,1);}],
 ['negative or noninteger contribution is already rejected',async()=>{for(const n of [-1,1.5]){const db=new FakeDB();await assert.rejects(()=>ledgerSnapshot(context(db),body({entry:{type:'contribution',amount_rwf:n}})),reject('invalid_request',400));assert.equal(db.batches.length,0);}}],
 ['unauthorized actor is still rejected',async()=>{const db=new FakeDB();await assert.rejects(()=>ledgerSnapshot(context(db,{type:'application',id:appId,scopes:[],allowedKinds:['receipt']}),body()),reject('forbidden',403));assert.equal(db.batches.length,0);}],
 ['invalid accounting scope still rejects',async()=>{const db=new FakeDB();await assert.rejects(()=>ledgerSnapshot(context(db),body({snapshot:{basis:'available_balance',scope:'all_time',member_total_rwf:10,group_total_rwf:20,posted_at:'2026-11-04T12:00:00Z',ledger_version:'v1'}})),reject('invalid_scope',400));assert.equal(db.batches.length,0);}],
 ['existing positive exact receipt remains a replay',async()=>{const db=new FakeDB(),b=body();await db.seed(b);const x=await ledgerSnapshot(context(db),b);assert.equal(x.body.state,'existing');assert.equal(db.batches.length,0);}],
];
for(const [name,run] of cases)test(name,run);
