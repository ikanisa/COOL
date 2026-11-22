import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {fixture,authorization,claims,signed} from './support/auth_fixture.mjs';

async function open(t){
 const f=await fixture({APP_ENVIRONMENT:'test'},{entrypoint:'index.js'});t.after(()=>f.close());return f;
}
const rpc=(f,s,body={})=>f.call('/v1/rpc/list_current_member_history_page',{p_contract_version:2,...body},authorization(s));
async function group(f,owner,title='School 10% fund'){
 const g=randomUUID(),date=new Date().toISOString();
 await f.db.batch([
  f.db.prepare(`INSERT INTO collections(id,slug,creator_user_id,title,collection_type,receiver_momo_number,receiver_network,created_at,updated_at) VALUES(?,?,?,?,'ikimina','250788123456','mtn_momo',?,?)`).bind(g,randomUUID(),owner.user.id,title,date,date),
  f.db.prepare(`INSERT INTO memberships(id,collection_id,user_id,role,joined_at) VALUES(?,?,?,'owner',?)`).bind(randomUUID(),g,owner.user.id,date),
 ]);return g;
}
// Historical rows are seeded only in isolated D1. This suite verifies the real
// authenticated history path; existing reconciliation tests prove their writes.
async function contribution(f,collection,member,amount,{reverse=false,reference=randomUUID(),time='2026-10-15T10:00:00.000Z'}={}){
 const evidence=randomUUID(),payment=randomUUID(),entry=randomUUID(),reversal=reverse?randomUUID():null;
 const statements=[
  f.db.prepare(`INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,observed_at,created_at) VALUES(?,?,?,?,?,1,'text/plain','operator_recorded',?,?,?)`).bind(evidence,collection,member.user.id,'test-history/'+evidence,'a'.repeat(64),reference,time,time),
  f.db.prepare(`INSERT INTO payments(id,collection_id,member_id,evidence_id,amount_minor,status,payer_display_name,created_at) VALUES(?,?,?,?,?,'reconciled','PRIVATE_RECEIPT_NAME',?)`).bind(payment,collection,member.user.id,evidence,amount,time),
  f.db.prepare(`INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,?,'contribution',?,?,?,?)`).bind(entry,payment,collection,member.user.id,amount,evidence,member.user.id,randomUUID(),time),
 ];
 if(reverse)statements.push(
  f.db.prepare(`INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,reverses_entry_id,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,?,'reversal',?,?,?,?,?)`).bind(reversal,payment,collection,member.user.id,-amount,entry,evidence,member.user.id,randomUUID(),'2026-10-15T12:00:00.000Z'),
  f.db.prepare("UPDATE payments SET status='reversed',revision=revision+1 WHERE id=?").bind(payment),
 );
 await f.db.batch(statements);return {payment,entry,reversal,evidence,reference};
}
async function setup(t){
 const f=await open(t),owner=await f.login({phone:'+250788123456'}),other=await f.login({phone:'+250789123456'}),g=await group(f,owner);
 const own=await contribution(f,g,owner,1000,{reverse:true,reference:'CONTROLLED-OWN-REFERENCE'});
 const another=await contribution(f,g,other,2000,{time:'2026-10-15T11:00:00.000Z'});
 return {f,owner,other,g,own,another};
}

test('signed member history retains originals and reversals and agrees with the actual ledger',async t=>{
 const {f,owner,g,own}=await setup(t),r=await rpc(f,owner);assert.equal(r.status,200,JSON.stringify(r.body));
 assert.equal(r.body.contract_version,2);assert.equal(r.body.total_count,3);
 assert.deepEqual(r.body.totals,{RWF:2000});assert.deepEqual(r.body.own_totals,{RWF:0});
 assert.deepEqual(r.body.credit_totals,{RWF:3000});assert.deepEqual(r.body.debit_totals,{RWF:1000});
 assert.deepEqual(r.body.own_credit_totals,{RWF:1000});assert.deepEqual(r.body.own_debit_totals,{RWF:1000});
 assert.deepEqual(r.body.own_collection_ids,[g]);
 const original=r.body.items.find(row=>row.entry_id===own.entry),reversal=r.body.items.find(row=>row.entry_id===own.reversal);
 assert.equal(original.payment_id,reversal.payment_id);assert.equal(reversal.reverses_entry_id,original.entry_id);assert.equal(reversal.amount_minor,-1000);
 assert.equal(original.payment_status,'reversed');assert.ok(r.body.items.every(row=>row.provider_confirmation===false&&row.settlement_status==='not_asserted'));
 assert.ok(r.body.items.every(row=>/^\d{6}$/.test(row.supporter_label)));assert.ok(!JSON.stringify(r.body).includes('PRIVATE_RECEIPT_NAME'));
 assert.equal((await f.db.prepare('SELECT sum(amount_minor) AS total FROM ledger_entries WHERE collection_id=?').bind(g).first()).total,r.body.totals.RWF);
 const legacy=await f.call('/v1/rpc/list_current_member_history_page',{},authorization(owner));assert.equal(legacy.status,200);assert.equal(legacy.body.total_count,1);
});

test('a reversal-first page uses unique entry cursors and complete signed aggregates',async t=>{
 const {f,owner,own}=await setup(t),first=await rpc(f,owner,{p_limit:1});assert.equal(first.status,200,JSON.stringify(first.body));
 assert.equal(first.body.items[0].entry_id,own.reversal);assert.equal(first.body.items[0].amount_minor,-1000);
 assert.equal(first.body.next_cursor.after,own.reversal);assert.equal(first.body.totals.RWF,2000);
 const items=[...first.body.items];let page=first.body;
 while(page.next_cursor){const r=await rpc(f,owner,{p_limit:1,p_cursor:page.next_cursor});assert.equal(r.status,200,JSON.stringify(r.body));assert.equal(r.body.revision,first.body.revision);items.push(...r.body.items);page=r.body;}
 assert.equal(items.length,3);assert.equal(new Set(items.map(row=>row.entry_id)).size,3);assert.equal(items.reduce((sum,row)=>sum+row.amount_minor,0),2000);
});

test('advertised history search is literal, membership scoped and supports Collect IDs and retained references',async t=>{
 const {f,owner,g,own}=await setup(t),publicId=(await f.db.prepare('SELECT public_id FROM users WHERE id=?').bind(owner.user.id).first()).public_id;
 for(const search of ['School','10%',publicId,'#'+publicId,own.reference,own.payment]){
  const r=await rpc(f,owner,{p_query:search});assert.equal(r.status,200,JSON.stringify(r.body));assert.equal(r.body.total_count,['School','10%'].includes(search)?3:2);assert.ok(r.body.items.every(row=>row.collection_id===g));
 }
 const literal=await rpc(f,owner,{p_query:'_'});assert.equal(literal.status,200);assert.equal(literal.body.total_count,0);
 const single=await rpc(f,owner,{p_query:own.reversal});assert.equal(single.status,200);assert.equal(single.body.total_count,1);assert.equal(single.body.totals.RWF,-1000);assert.equal(single.body.credit_totals.RWF,0);assert.equal(single.body.debit_totals.RWF,1000);
 const name=await rpc(f,owner,{p_query:'PRIVATE_RECEIPT_NAME'});assert.equal(name.body.total_count,0);
});

test('all financial sorts match signed amount, instant and entry identity order',async t=>{
 const {f,owner}=await setup(t);
 for(const sort of ['newest','oldest','highest','lowest']){
  const r=await rpc(f,owner,{p_sort:sort});assert.equal(r.status,200,JSON.stringify(r.body));
  const sorted=[...r.body.items].sort((a,b)=>{
   if(['highest','lowest'].includes(sort)&&a.amount_minor!==b.amount_minor)return sort==='highest'?b.amount_minor-a.amount_minor:a.amount_minor-b.amount_minor;
   return (sort==='oldest'?a.posted_at.localeCompare(b.posted_at):b.posted_at.localeCompare(a.posted_at))||a.entry_id.localeCompare(b.entry_id);
  });assert.deepEqual(r.body.items,sorted);
 }
});

test('cursor identity is bound to the exact filters, session and ledger state',async t=>{
 const {f,owner,g}=await setup(t),first=await rpc(f,owner,{p_limit:1}),cursor=first.body.next_cursor;
 assert.equal(first.status,200);
 for(const extra of [{p_sort:'oldest'},{p_query:'School'},{p_collection_id:g}])assert.equal((await rpc(f,owner,{...extra,p_cursor:cursor})).status,409);
 // Seed a second genuine session in isolated D1; do not bypass or relax the
 // OTP cooldown merely to exercise this history-specific ownership boundary.
 const identity=claims(owner.access_token),sessionId=randomUUID();
 await f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)")
  .bind(sessionId,owner.user.id,identity.auth_time,identity.iat,identity.exp).run();
 const anotherSession={access_token:signed({...identity,session_id:sessionId})};
 assert.equal((await rpc(f,anotherSession,{p_cursor:cursor})).status,409);
 await contribution(f,g,owner,500,{time:'2026-10-15T13:00:00.000Z'});
 assert.equal((await rpc(f,owner,{p_cursor:cursor})).status,409);
});

test('cross-group, removed-membership and revoked-session reads disclose no financial rows',async t=>{
 const {f,owner,other,g}=await setup(t),privateGroup=await group(f,other,'PRIVATE OTHER GROUP');
 await contribution(f,privateGroup,other,900);
 const denied=await rpc(f,owner,{p_collection_id:privateGroup});assert.equal(denied.status,200);assert.equal(denied.body.total_count,0);
 await f.db.prepare('UPDATE memberships SET active=0 WHERE collection_id=? AND user_id=?').bind(g,owner.user.id).run();
 const removed=await rpc(f,owner);assert.equal(removed.status,200);assert.equal(removed.body.total_count,0);assert.deepEqual(removed.body.own_collection_ids,[]);
 await f.call('/v1/auth/logout',{},authorization(owner));assert.equal((await rpc(f,owner)).status,401);
});

test('unsupported history versions and forged filters or cursors are refused',async t=>{
 const f=await open(t),owner=await f.login({phone:'+250788123456'});
 for(const body of [{p_contract_version:3},{p_contract_version:'2'},{p_query:[]},{p_query:'a\u0000b'},{p_sort:'__proto__'},{p_subject_id:randomUUID()},{p_cursor:{revision:'a'.repeat(32),after:randomUUID(),extra:true}}]){
  const r=await rpc(f,owner,body);assert.ok([400,409].includes(r.status),JSON.stringify({body,result:r}));
 }
});

test('unsafe gross transport totals are refused even when their signed net would fit',async t=>{
 const f=await open(t),owner=await f.login({phone:'+250788123456'}),g=await group(f,owner);
 await contribution(f,g,owner,9007199254740991,{reverse:true});
 await contribution(f,g,owner,1);
 const r=await rpc(f,owner);assert.equal(r.status,503);assert.equal(r.body.code,'history_unavailable');
});

test('noncanonical source timestamps cannot silently change financial event order',async t=>{
 const f=await open(t),owner=await f.login({phone:'+250788123456'}),g=await group(f,owner);
 await contribution(f,g,owner,1000,{time:'2026-10-15T10:00:00+02:00'});
 const r=await rpc(f,owner);assert.equal(r.status,503);assert.equal(r.body.code,'history_unavailable');
});
