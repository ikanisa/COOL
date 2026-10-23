import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {retentionFixture,authorization,sourceId} from './support/retention_fixture.mjs';
import {planRetention} from '../src/privacy_retention.js';
import {executeRetentionTask} from '../src/privacy_retention_tasks.js';
import {SQL_CHUNK_ROWS,SQL_OWN_ROW_LIMIT} from '../src/privacy_retention_chunks.js';
const sha=value=>createHash('sha256').update(value).digest('hex');
const ok=r=>{assert.equal(r.status,200,JSON.stringify(r.body));return r.body;};
async function seedRows(f,user,count,table='support_requests'){
 const at=new Date().toISOString(),prefix=randomUUID();
 const base='WITH RECURSIVE n(v) AS (SELECT 1 UNION ALL SELECT v+1 FROM n WHERE v<?) ';
 if(table==='support_requests')await f.db.prepare(base+"INSERT INTO support_requests(id,user_id,kind,message,created_at) SELECT ?||printf('%06d',v),?,'support','SYNTHETIC CHUNK BODY',? FROM n").bind(count,prefix,user.user.id,at).run();
 if(table==='notification_events')await f.db.prepare(base+"INSERT INTO notification_events(id,user_id,event_type,title,body,created_at) SELECT ?||printf('%06d',v),?,'test','TEST','SYNTHETIC EVENT',? FROM n").bind(count,prefix,user.user.id,at).run();
 if(table==='notification_devices')await f.db.prepare(base+"INSERT INTO notification_devices(id,user_id,token_hash,owner_session_id,provider,token_ciphertext,platform,created_at,updated_at) SELECT ?||printf('%06d',v),?,?||printf('%06d',v),'synthetic-session','fcm','SYNTHETIC','android',?,? FROM n").bind(count,prefix,user.user.id,prefix,at,at).run();
}
async function setup(t,{count=610,seedExtra=false}={}){
 const f=await retentionFixture(t),member=await f.login(),other=await f.login({phone:'+250789123456'}),operator=await f.operator();await seedRows(f,member,count);await seedRows(f,other,3);
 const names=['support_requests'];if(seedExtra){for(const n of ['notification_events','notification_devices']){await seedRows(f,member,65,n);await seedRows(f,other,2,n);names.push(n);}for(const u of [member,other])await f.db.prepare('INSERT INTO notification_preferences(user_id,updated_at) VALUES(?,?)').bind(u.user.id,new Date().toISOString()).run();names.push('notification_preferences');}
 const intake=ok(await f.call('/v1/rpc/request_account_deletion_v1',{p_request_id:randomUUID(),p_reason:null},authorization(member)));f.scopeRequest=intake.request_id;const policy=await f.policy(operator);for(const n of names)policy.rules[n]={action:'erase',basis_reference:'SYNTHETIC TEST ONLY',deadline:new Date(Date.now()-60000).toISOString()};await f.policy(operator,{rules:policy.rules});
 const input={operation_id:randomUUID(),request_id:intake.request_id,expected_review_revision:0,policy_sha256:f.policySha,expected_source_id:sourceId};return {f,member,other,operator,input,names};
}
async function plan(c){return ok(await c.f.retention(c.operator,'plan',c.input));}
async function claim(c,p,name='support_requests',lease=120){const status=ok(await c.f.retention(c.operator,'status',{plan_id:p.plan_id})),task=status.tasks.find(v=>v.class_name===name);return ok(await c.f.retention(c.operator,'claim',{operation_id:randomUUID(),plan_id:p.plan_id,task_id:task.task_id,expected_task_revision:task.revision,lease_seconds:lease}));}
async function execute(c,k,operation=randomUUID(),headers={}){return c.f.retention(c.operator,'execute',{operation_id:operation,claim_id:k.claim_id,fence:k.fence},headers);}
async function start(c,p){return ok(await execute(c,await claim(c,p,'access')));}
const countOwn=async(c,table='support_requests')=>(await c.f.db.prepare('SELECT count(*) AS n FROM '+table+' WHERE user_id=?').bind(c.member.user.id).first()).n;

test('more than500 actual own rows erase in bounded durable chunks across all four adapters,with replay and truthful whole incompletion',async t=>{
 const c=await setup(t,{seedExtra:true}),p=await plan(c);await start(c,p);
 const others=Object.fromEntries(await Promise.all(c.names.map(async n=>[n,(await c.f.db.prepare('SELECT * FROM '+n+' WHERE user_id=?').bind(c.other.user.id).all()).results])));
 for(const name of c.names){let steps=0,prior=await countOwn(c,name),done=false;
  while(!done){const k=await claim(c,p,name),operation=randomUUID(),out=ok(await execute(c,k,operation));steps++;const now=await countOwn(c,name);assert.ok(prior-now<=SQL_CHUNK_ROWS);assert.equal(prior-now,out.row_chunk.ids.length);assert.equal(out.rows_remaining,now);assert.equal(out.erasure_completed,false);assert.equal(out.all_data_erased,false);
   // The real server response may be lost to its caller. Replaying the exact
   // operation must return its retained outcome without a second chunk effect.
   const replay=ok(await execute(c,k,operation));assert.deepEqual(replay,out);assert.equal(await countOwn(c,name),now);
   if(steps===1&&now){const status=ok(await c.f.retention(c.operator,'status',{plan_id:p.plan_id}));assert.equal(status.tasks.find(v=>v.class_name===name).state,'blocked');assert.equal(out.verified,false);assert.equal(out.disposition,'own_rows_chunk_absence_verified');}
   assert.deepEqual((await c.f.db.prepare('SELECT * FROM '+name+' WHERE user_id=?').bind(c.other.user.id).all()).results,others[name]);prior=now;done=out.verified;assert.ok(steps<=Math.ceil(SQL_OWN_ROW_LIMIT/SQL_CHUNK_ROWS));
  }assert.equal(prior,0);if(name==='support_requests')assert.ok(steps>1);
 }
 const ext=ok(await execute(c,await claim(c,p,'external:backups')));assert.equal(ext.verified,false);assert.equal(ext.reason,'external_copy_adapter_and_actual_inventory_required');const result=ok(await c.f.retention(c.operator,'reconcile',{plan_id:p.plan_id}));assert.equal(result.state,'blocked');assert.equal(result.all_actual_copy_outcomes_verified,false);assert.equal(result.all_data_erased,false);assert.equal((await c.f.db.prepare('PRAGMA foreign_key_check').all()).results.length,0);
});

test('partial own-row progress resumes from immutable outcomes after a mutable checkpoint head is lost',async t=>{
 const c=await setup(t),p=await plan(c);await start(c,p);const first=ok(await execute(c,await claim(c,p)));assert.equal(first.rows_remaining,610-SQL_CHUNK_ROWS);
 const task=await c.f.db.prepare("SELECT * FROM privacy_retention_tasks WHERE plan_id=? AND class_name='support_requests'").bind(p.plan_id).first();const original=await c.f.db.prepare("SELECT outcome_json FROM privacy_retention_outcomes WHERE task_id=? AND json_type(outcome_json,'$.row_chunk') IS NOT NULL").bind(task.id).first();await c.f.db.prepare("UPDATE privacy_retention_tasks SET post_images_json='{}',outcome_json='{}' WHERE id=?").bind(task.id).run();
 const second=ok(await execute(c,await claim(c,p)));assert.equal(second.rows_remaining,610-2*SQL_CHUNK_ROWS);assert.equal(second.row_chunk.parent_outcome_sha256,sha(original.outcome_json));
});

test('a changed full source or an unselected own row during chunk commit rolls back every selected row and checkpoint',async t=>{
 for(const mode of ['user','unselected_own_row']){const c=await setup(t),p=await plan(c);await start(c,p);ok(await execute(c,await claim(c,p)));const before=await countOwn(c),k=await claim(c,p);let r;
  if(mode==='user')r=await execute(c,k,randomUUID(),{'x-test-source-race':'user','x-test-subject':c.member.user.id});
  else{const actor=ok(await c.f.call('/__actor',{},authorization(c.operator)));actor.permissions=new Set(actor.permissions);const task=await c.f.db.prepare('SELECT * FROM privacy_retention_tasks WHERE id=?').bind(k.task_id).first(),expected=JSON.parse(task.expected_json),outside=expected.target_ids.at(-1);assert.ok(expected.target_ids.indexOf(outside)>=2*SQL_CHUNK_ROWS);let raced=false;
   const db={prepare:query=>c.f.db.prepare(query),async batch(statements){if(!raced&&statements.length>10){raced=true;const guard=randomUUID();await c.f.db.batch([
    c.f.db.prepare("INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) VALUES(?,?,'support_requests',1)").bind(guard,p.plan_id),
    c.f.db.prepare("UPDATE support_requests SET message='CONTROLLED PRIVILEGED ROW RACE' WHERE id=? AND user_id=?").bind(outside,c.member.user.id),
    c.f.db.prepare('DELETE FROM privacy_retention_guards WHERE id=?').bind(guard)]);}return c.f.db.batch(statements);}};
   await assert.rejects(executeRetentionTask({DB:db,PRIVATE_MEDIA:c.f.bucket,APP_ENVIRONMENT:'test',BUILD_SOURCE_ID:sourceId,PRIVACY_RETENTION_APPROVAL_SHA256:c.f.policySha},actor,{operation_id:randomUUID(),claim_id:k.claim_id,fence:k.fence}),e=>e.code==='privacy_retention_source_or_claim_changed');assert.equal(raced,true);r={status:409};
  }
  assert.equal(r.status,409);assert.equal(await countOwn(c),before);assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_outcomes WHERE claim_id=?').bind(k.claim_id).first()).n,0);
 }
});

test('holds,changed policy/source and expired leases deny later chunks without losing prior actual progress',async t=>{
 for(const mode of ['hold','policy','source','lease']){const c=await setup(t),p=await plan(c);await start(c,p);const first=ok(await execute(c,await claim(c,p))),before=await countOwn(c),k=await claim(c,p,'support_requests',mode==='lease'?1:120);let r;
  if(mode==='hold'){await c.f.db.prepare("INSERT INTO privacy_holds(id,user_id,category,reason_code,created_at) VALUES(?,?,'test','SYNTHETIC HOLD',?)").bind(randomUUID(),c.member.user.id,new Date().toISOString()).run();r=await execute(c,k);}
  if(mode==='policy'){const policy=JSON.parse((await c.f.db.prepare("SELECT value_json FROM runtime_config WHERE key='privacy:retention:approved:v1'").first()).value_json);await c.f.policy(c.operator,{...policy,version:'SYNTHETIC CHANGED POLICY'});r=await execute(c,k);}
  if(mode==='source'){const actor=ok(await c.f.call('/__actor',{},authorization(c.operator)));actor.permissions=new Set(actor.permissions);await assert.rejects(executeRetentionTask({DB:c.f.db,PRIVATE_MEDIA:c.f.bucket,APP_ENVIRONMENT:'test',BUILD_SOURCE_ID:'a'.repeat(64),PRIVACY_RETENTION_APPROVAL_SHA256:c.f.policySha},actor,{operation_id:randomUUID(),claim_id:k.claim_id,fence:k.fence}),e=>e.code==='privacy_retention_policy_unavailable');r={status:409};}
  if(mode==='lease'){await new Promise(resolve=>setTimeout(resolve,1200));r=await execute(c,k);assert.equal(r.body.code,'privacy_retention_claim_stale');}
  assert.equal(r.status,409,mode+JSON.stringify(r.body));if(mode!=='source')assert.equal(r.body.code,{hold:'privacy_retention_scope_changed',policy:'privacy_retention_policy_unavailable',lease:'privacy_retention_claim_stale'}[mode]);assert.equal(await countOwn(c),before);const outcomes=(await c.f.db.prepare("SELECT outcome_json FROM privacy_retention_outcomes WHERE task_id=? AND json_type(outcome_json,'$.row_chunk') IS NOT NULL").bind(k.task_id).all()).results;assert.equal(outcomes.length,1);assert.deepEqual(JSON.parse(outcomes[0].outcome_json),first);
 }
});

test('global context500,own row2000 and1MiB preimage limits still reject uncovered inventories',async t=>{
 for(const mode of ['context','own','bytes']){const c=await setup(t,{count:1});
  if(mode==='context')await c.f.db.prepare("WITH RECURSIVE n(v) AS (SELECT 1 UNION ALL SELECT v+1 FROM n WHERE v<501) INSERT INTO auth_rate_buckets(bucket_key,used,window_ends_at) SELECT 'SYNTHETIC GLOBAL '||v,0,9999999999 FROM n").run();
  if(mode==='own')await seedRows(c.f,c.member,SQL_OWN_ROW_LIMIT);
  if(mode==='bytes')await c.f.db.prepare('UPDATE support_requests SET message=? WHERE user_id=?').bind('S'.repeat(1024*1024),c.member.user.id).run();
  const r=await c.f.retention(c.operator,'inspect',{request_id:c.input.request_id,expected_review_revision:0,expected_source_id:sourceId});assert.equal(r.status,409);assert.equal(r.body.code,'privacy_retention_inventory_limit',mode+JSON.stringify(r.body));assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_plans').first()).n,0);
 }
});

// Construct only the prior immutable task shape in the actual D1 planner
// insert. This is synthetic historical-shape coverage, not a claim that a
// complete historical application or a live erasure ran here.
async function historicalPlan(c){
 const actor=ok(await c.f.call('/__actor',{},authorization(c.operator)));actor.permissions=new Set(actor.permissions);let adapted=0;
 const db={prepare(query){const statement=c.f.db.prepare(query);if(!query.startsWith('INSERT INTO privacy_retention_tasks('))return statement;
  return {bind(...args){if(['support_requests','notification_devices','notification_preferences','notification_events'].includes(args[2])){const expected=JSON.parse(args[4]);assert.ok(expected.row_chunks);delete expected.row_chunks;assert.deepEqual(Object.keys(expected).sort(),['context_sha256','count','sha256','target_ids']);args[4]=JSON.stringify(expected);adapted++;}return statement.bind(...args);}};
 },batch:statements=>c.f.db.batch(statements)};
 const result=await planRetention({DB:db,PRIVATE_MEDIA:c.f.bucket,APP_ENVIRONMENT:'test',BUILD_SOURCE_ID:sourceId,PRIVACY_RETENTION_APPROVAL_SHA256:c.f.policySha},actor,c.input);assert.equal(adapted,4);return result;
}
test('legacy immutable own-row tasks still delete present rows or verify actual prior absence without a negative count guard',async t=>{
 for(const alreadyAbsent of [false,true]){const c=await setup(t,{count:120}),p=await historicalPlan(c);await start(c,p);
  const foreign=(await c.f.db.prepare('SELECT * FROM support_requests WHERE user_id=?').bind(c.other.user.id).all()).results;
  if(alreadyAbsent){const guard=randomUUID();await c.f.db.batch([
   c.f.db.prepare("INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) VALUES(?,?,'support_requests',1)").bind(guard,p.plan_id),
   c.f.db.prepare('DELETE FROM support_requests WHERE user_id=?').bind(c.member.user.id),
   c.f.db.prepare('DELETE FROM privacy_retention_guards WHERE id=?').bind(guard)]);}
  const out=ok(await execute(c,await claim(c,p)));assert.equal(out.verified,true);assert.equal(out.disposition,'own_rows_absence_verified');assert.equal(out.rows_erased_or_confirmed_absent,120);assert.equal(Object.hasOwn(out,'row_chunk'),false);assert.equal(out.all_data_erased,false);assert.equal(await countOwn(c),0);assert.deepEqual((await c.f.db.prepare('SELECT * FROM support_requests WHERE user_id=?').bind(c.other.user.id).all()).results,foreign);assert.equal((await c.f.db.prepare('PRAGMA foreign_key_check').all()).results.length,0);
 }
});
