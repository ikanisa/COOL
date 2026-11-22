import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {groupRpc} from './helpers/module-domain-groups.js';

// This fake exercises actual RPC/mutation code without a database or network.
// It models rollback and the two admission guards, but cannot prove SQL locks.
const USER='11111111-1111-4111-8111-111111111111';
const SESSION='22222222-2222-4222-8222-222222222222';
const GROUP='33333333-3333-4333-8333-333333333333';
const REQUEST='44444444-4444-4444-8444-444444444444';
const actor={userId:USER,sessionId:SESSION,surface:'member',assuranceLevel:1};

class FakeDatabase {
 constructor(){this.group={id:GROUP,status:'active',visibility:'public_approved'};this.session=true;this.user=true;this.membership=null;this.receipts=new Map();this.audits=0;this.hourCount=0;this.dayCount=0;this.beforeBatch=null;this.statements=[];}
 prepare(sql){const db=this;return {sql,values:[],bind(...values){this.values=values;return this;},async first(){
  if(sql.startsWith('SELECT * FROM request_receipts'))return db.receipts.get(valuesKey(this.values))??null;
  if(sql.startsWith('SELECT (SELECT count(*) FROM request_receipts'))return {allowed:db.hourCount<60&&db.dayCount<500};
  if(sql.includes('SELECT c.id FROM collections c JOIN memberships'))return db.allowed()&&db.membership?.active===1?{id:GROUP}:null;
  throw Error('Unexpected synthetic read: '+sql);
 }};}
 allowed(){return this.session&&this.user&&this.group.status==='active'&&this.group.visibility==='public_approved';}
 async batch(statements){
  if(this.beforeBatch){const hook=this.beforeBatch;this.beforeBatch=null;hook(this);}
  const snapshot={membership:this.membership?{...this.membership}:null,receipts:new Map(this.receipts),audits:this.audits};
  this.statements.push(statements.map(s=>s.sql));
  let insertedReceipt=false;
  try {for(const statement of statements){const {sql,values}=statement;
   if(sql.startsWith('INSERT INTO mutation_guards')){if(!this.session||!this.user)throw Error('session_changed');}
   else if(sql.startsWith('INSERT INTO request_receipts')){this.receipts.set(valuesKey(values),{operation:values[2],session_id:values[3],body_sha256:values[4],response_json:values[5]});insertedReceipt=true;}
   else if(sql.startsWith('INSERT INTO admin_bridge_guards')){
    if(!this.allowed()||(values.length===8&&(this.hourCount>=60||this.dayCount>=500))||(values.length===6&&this.membership?.active!==1))throw Error('violates check constraint "admin_bridge_state"');
   } else if(sql.startsWith('INSERT INTO memberships')){
    if(!this.membership)this.membership={id:values[0],collection_id:values[1],user_id:values[2],active:1,role:'member'};
   } else if(sql.startsWith('INSERT INTO audit_log'))this.audits++;
   else if(sql.startsWith('SELECT id FROM ')||sql.startsWith('DELETE FROM ')){}
   else throw Error('Unexpected synthetic statement: '+sql);
  }} catch(error){this.membership=snapshot.membership;this.receipts=snapshot.receipts;this.audits=snapshot.audits;throw error;}
  if(insertedReceipt){this.hourCount++;this.dayCount++;}
  return statements.map(()=>({results:[],meta:{changes:1}}));
 }
}
const valuesKey=values=>`${values[0]}:${values[1]}`;
const body=(request=REQUEST)=>({p_collection_id:GROUP,p_request_id:request});
const join=(db,input=body())=>groupRpc('join_public_group',input,{DB:db},actor);

test('public join retains one membership across retries',async()=>{
 const db=new FakeDatabase();assert.deepEqual(await join(db),{handled:true,value:GROUP});
 assert.deepEqual(await join(db),{handled:true,value:GROUP});
 assert.equal(db.membership.active,1);assert.equal(db.membership.role,'member');assert.equal(db.audits,1);assert.equal(db.receipts.size,1);
 const first=db.statements[0];
 assert.ok(first.findIndex(x=>x.includes('collections WHERE id=? FOR UPDATE'))<first.findIndex(x=>x.startsWith('INSERT INTO memberships')));
 assert.ok(first.findIndex(x=>x.includes('memberships WHERE collection_id=? AND user_id=? FOR UPDATE'))>first.findIndex(x=>x.startsWith('INSERT INTO memberships')));
});

test('private, suspended and revoked authority never create membership',async()=>{
 for(const change of [db=>db.group.visibility='private',db=>db.group.status='suspended',db=>db.session=false,db=>db.user=false]){
  const db=new FakeDatabase();db.beforeBatch=change;
  await assert.rejects(join(db));assert.equal(db.membership,null);assert.equal(db.receipts.size,0);assert.equal(db.audits,0);
 }
});

test('old replay and fresh retry cannot revive a removed member',async()=>{
 const db=new FakeDatabase();await join(db);db.membership.active=0;
 await assert.rejects(join(db),error=>error.code==='group_join_unconfirmed'&&error.status===409);
 await assert.rejects(join(db,body('55555555-5555-4555-8555-555555555555')));
 assert.equal(db.membership.active,0);assert.equal(db.receipts.size,1);assert.equal(db.audits,1);
});

test('replay refuses withdrawn group and conflicting request payload',async()=>{
 const db=new FakeDatabase();await join(db);db.group.visibility='private';
 await assert.rejects(join(db),error=>error.code==='group_join_unconfirmed');
 db.group.visibility='public_approved';
 await assert.rejects(join(db,{...body(),unexpected:'changed'}),error=>error.code==='request_conflict');
 assert.equal(db.audits,1);
});

test('fresh joins are bounded while an exact retained replay remains available',async()=>{
 const db=new FakeDatabase();db.hourCount=59;db.dayCount=499;
 await join(db);assert.equal(db.hourCount,60);assert.equal(db.dayCount,500);
 assert.deepEqual(await join(db),{handled:true,value:GROUP});
 await assert.rejects(join(db,body('55555555-5555-4555-8555-555555555555')),error=>error.code==='public_join_limited'&&error.status===429);
 assert.equal(db.receipts.size,1);assert.equal(db.audits,1);
});
