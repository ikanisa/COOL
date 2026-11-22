import { fileURLToPath } from 'node:url';
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { dispatchEmailBatch, handleEmailAdmin, EmailDispatchError } from '../src/email-dispatch.mjs';
import { digest, randomToken } from '../src/security.mjs';

let mf, db, userId, actor;
const at = () => Math.floor(Date.now() / 1000);
const run = (sql, ...args) => db.prepare(sql).bind(...args).run();
const first = (sql, ...args) => db.prepare(sql).bind(...args).first();
const sent = [];
let reject = false;
const env = { ENVIRONMENT: 'test', EMAIL: { send: async message => { sent.push(message); if (reject) throw new Error('connection lost'); return {messageId:crypto.randomUUID()}; } } };
before(async () => {
  mf = new Miniflare(convertV4MiniflareOptions({modules:true,script:'export default {fetch(){return new Response("ok")}}',compatibilityDate:'2026-10-04',d1Databases:['ADMIN_DB']}));
  db = env.ADMIN_DB = await mf.getD1Database('ADMIN_DB');
  for (const name of ['0001_admin_accounts.sql','0002_collect_core.sql','0004_operating_actions.sql']) {
    const sql = await readFile(new URL(`../migrations/${name}`, import.meta.url),'utf8');
    const split=spawnSync(process.execPath,['-e',"const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"],{cwd:fileURLToPath(new URL('..',import.meta.url)),input:sql,encoding:'utf8'});
    assert.equal(split.status,0,split.stderr);await db.batch(JSON.parse(split.stdout).map(sql=>db.prepare(sql)));
  }
  // Shared event contract; the member suite validates its complete migration.
  await run('CREATE TABLE member_notification_events(id TEXT PRIMARY KEY,user_id TEXT,status TEXT,sent_at INTEGER,provider_reference TEXT)');
  await run('CREATE TABLE member_notification_preferences(user_id TEXT PRIMARY KEY,contribution_confirmations INTEGER,payment_reminders INTEGER,group_updates INTEGER,security_notices INTEGER)');
  const sql=await readFile(new URL('../migrations/0007_email_only_dispatch.sql',import.meta.url),'utf8');
  const split=spawnSync(process.execPath,['-e',"const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"],{cwd:fileURLToPath(new URL('..',import.meta.url)),input:sql,encoding:'utf8'});
  await db.batch(JSON.parse(split.stdout).map(sql=>db.prepare(sql)));
  userId=crypto.randomUUID();await run("INSERT INTO collect_users(id,email,status,created_at,updated_at) VALUES(?,'recipient@example.com','active',?,?)",userId,at(),at());
  await run('INSERT INTO member_notification_preferences VALUES(?,1,1,1,1)',userId);
  const actorId=crypto.randomUUID(),token=await digest(randomToken());
  await run("INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,'dispatch@example.com','admin','active','test-only-no-password-login',?,?)",actorId,at(),at());
  await run('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,1,?,?)',token,crypto.randomUUID(),actorId,at(),at()+3600);
  actor={id:actorId,token_hash:token,auth_version:1,role:'admin'};
});
after(async()=>{await mf?.dispose();});
async function queue({to='recipient@example.com',memberEvent=false,channel='email'}={}) {
  const id=crypto.randomUUID(),event=memberEvent?crypto.randomUUID():null;
  if(event)await run("INSERT INTO member_notification_events(id,user_id,status) VALUES(?,?,'queued')",event,userId);
  await run('INSERT INTO collect_notification_outbox(id,recipient_user_id,channel,notification_type,deduplication_key,payload_json,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)',id,userId,channel,'group_update',crypto.randomUUID(),JSON.stringify({to,subject:'Your Collect group',text:'Your group details were updated.',...(event?{member_event_id:event}:{})}),at(),at());
  return{id,event};
}
const state=id=>first('SELECT * FROM collect_notification_outbox WHERE id=?',id);
test('concurrent dispatch claims each item once and records acceptance without claiming delivery',async()=>{
  const item=await queue({memberEvent:true}),before=sent.length;
  const outcomes=await Promise.all([dispatchEmailBatch(env),dispatchEmailBatch(env)]);
  assert.equal(sent.length,before+1);assert.equal(outcomes.reduce((n,x)=>n+x.accepted,0),1);
  const saved=await state(item.id);assert.equal(saved.status,'accepted');assert.equal(saved.delivered_at,null);assert.equal(saved.attempt_count,1);
  assert.equal(sent.at(-1).from.name,'Collect');assert.ok(sent.at(-1).html.includes('Collect'));
  assert.equal((await first('SELECT * FROM member_notification_events WHERE id=?',item.event)).status,'accepted');
});
test('recipient changes suppress frozen content before any provider call; nonemail insert is rejected',async()=>{
  const item=await queue({to:'old@example.com',memberEvent:true}),before=sent.length;
  assert.equal((await dispatchEmailBatch(env)).suppressed,1);assert.equal(sent.length,before);
  assert.equal((await state(item.id)).status,'suppressed');
  assert.equal((await first('SELECT * FROM member_notification_events WHERE id=?',item.event)).status,'suppressed');
  await assert.rejects(queue({channel:'push'}));
});
test('unknown send outcomes stay uncertain and cannot be automatically retried',async()=>{
  const item=await queue({memberEvent:true});reject=true;const before=sent.length;
  assert.equal((await dispatchEmailBatch(env)).uncertain,1);reject=false;
  assert.equal((await state(item.id)).status,'uncertain');await dispatchEmailBatch(env);assert.equal(sent.length,before+1);
  assert.equal((await first('SELECT * FROM member_notification_events WHERE id=?',item.event)).status,'uncertain');
});
test('opting out after enqueue suppresses optional email before sending',async()=>{
  const item=await queue({memberEvent:true}),before=sent.length;
  await run('UPDATE member_notification_preferences SET group_updates=0 WHERE user_id=?',userId);
  assert.equal((await dispatchEmailBatch(env)).suppressed,1);assert.equal(sent.length,before);assert.equal((await state(item.id)).status,'suppressed');
  await run('UPDATE member_notification_preferences SET group_updates=1 WHERE user_id=?',userId);
});
test('expired send-start reservations become uncertain without a provider call',async()=>{
  const item=await queue();const lease=await digest(randomToken());
  await run("UPDATE collect_notification_outbox SET status='leased',attempt_count=1,lease_token_sha256=?,lease_until=?,updated_at=? WHERE id=?",lease,at()+3,at(),item.id);
  await run("UPDATE collect_notification_outbox SET status='send_started',updated_at=? WHERE id=?",at(),item.id);
  await new Promise(resolve=>setTimeout(resolve,3100));
  const before=sent.length;await dispatchEmailBatch(env);assert.equal(sent.length,before);assert.equal((await state(item.id)).status,'uncertain');
});
test('manual dispatch has an audited replay receipt and never sends again on a repeated key',async()=>{
  await queue();const key=crypto.randomUUID(),before=sent.length;
  const request=reason=>new Request('https://admin.collect.ikanisa.com/api/admin/email/dispatch',{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify({reason})});
  const receipt=await handleEmailAdmin(request('Run requested email batch'),env,actor);
  assert.equal(receipt.accepted,1);assert.equal(receipt.status,'succeeded');assert.equal(receipt.resource_type,'email_dispatch');
  assert.deepEqual(await handleEmailAdmin(request('Run requested email batch'),env,actor),receipt);assert.equal(sent.length,before+1);
  await assert.rejects(handleEmailAdmin(request('Run different email batch'),env,actor),e=>e.status===409);
  assert.ok(await first('SELECT * FROM collect_operations_audit WHERE operation_request_id=?',receipt.request_id));
});
test('local delivery is disabled and administrator events are masked and session-fenced',async()=>{
  await assert.rejects(dispatchEmailBatch({...env,ENVIRONMENT:'local'}),e=>e instanceof EmailDispatchError&&e.status===503);
  const request=new Request('https://admin.collect.ikanisa.com/api/admin/email/events');
  const list=await handleEmailAdmin(request,env,actor);assert.ok(list.rows.length>0);assert.ok(!JSON.stringify(list).includes('recipient@example.com'));
  assert.ok(!JSON.stringify(list).includes('payload_json'));
  await run('DELETE FROM admin_sessions WHERE token_hash=?',actor.token_hash);
  await assert.rejects(handleEmailAdmin(request,env,actor),e=>e.status===401);
});

async function dispatchActor(role='admin') {
  const id=crypto.randomUUID(),token=await digest(randomToken()),email=role==='owner'?'info@ikanisa.com':`${id}@example.com`;
  await run('INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,?,?,\'active\',\'test-only-no-password-login\',?,?)',id,email,role,at(),at());
  await run('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,1,?,?)',token,crypto.randomUUID(),id,at(),at()+3600);
  return{id,token_hash:token,auth_version:1,role};
}
const dispatchRequest=(key=crypto.randomUUID())=>new Request('https://admin.collect.ikanisa.com/api/admin/email/dispatch',{
  method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify({reason:'Run local fixture notification batch'}),
});

test('manual dispatch rejects authority revoked during its body read with no send, receipt or audit',async()=>{
  for(const change of ['logout','auth_version','role']) {
    const current=await dispatchActor(),key=crypto.randomUUID(),item=await queue(),before=sent.length;
    const request=dispatchRequest(key),read=request.body.getReader.bind(request.body);
    request.body.getReader=()=>{
      const reader=read();let firstRead=true;
      return{async read(){
        if(firstRead){firstRead=false;
          if(change==='logout')await run('DELETE FROM admin_sessions WHERE token_hash=?',current.token_hash);
          if(change==='auth_version')await run('UPDATE admin_users SET auth_version=auth_version+1 WHERE id=?',current.id);
          if(change==='role')await run("UPDATE admin_users SET role='staff' WHERE id=?",current.id);
        }
        return reader.read();
      },cancel:reader.cancel.bind(reader)};
    };
    try {
      await assert.rejects(handleEmailAdmin(request,env,current),e=>e instanceof EmailDispatchError&&e.status===401,change);
      assert.equal(sent.length,before);
      assert.equal((await state(item.id)).status,'queued');
      assert.equal(await first('SELECT id FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?',current.id,key),null);
      assert.equal((await first('SELECT count(*) AS n FROM collect_operations_audit WHERE actor_admin_id=?',current.id)).n,0);
      assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n,0);
    } finally { await run("UPDATE collect_notification_outbox SET status='suppressed',updated_at=? WHERE id=? AND status='queued'",at(),item.id); }
  }
});

test('provider acceptance followed by receipt-write failure becomes uncertain and never retries',async()=>{
  const item=await queue({memberEvent:true}),before=sent.length;
  await run("CREATE TRIGGER test_email_acceptance_write_failure BEFORE UPDATE OF status ON collect_notification_outbox WHEN NEW.status='accepted' BEGIN SELECT RAISE(ABORT,'synthetic acceptance write failure'); END");
  try { assert.equal((await dispatchEmailBatch(env)).uncertain,1); }
  finally { await run('DROP TRIGGER test_email_acceptance_write_failure'); }
  const row=await state(item.id);assert.equal(row.status,'uncertain');assert.equal(row.provider_reference,null);assert.equal(row.delivered_at,null);
  assert.equal((await first('SELECT status FROM member_notification_events WHERE id=?',item.event)).status,'uncertain');
  await dispatchEmailBatch(env);assert.equal(sent.length,before+1);assert.equal((await state(item.id)).attempt_count,1);
});

test('staff can read masked email events while only current owner/admin roles can dispatch',async()=>{
  const staff=await dispatchActor('staff'),owner=await dispatchActor('owner'),admin=await dispatchActor('admin');
  const list=await handleEmailAdmin(new Request('https://admin.collect.ikanisa.com/api/admin/email/events'),env,staff);
  assert.ok(list.rows.length>0);assert.ok(!JSON.stringify(list).includes('recipient@example.com'));
  const before=sent.length,key=crypto.randomUUID();
  await assert.rejects(handleEmailAdmin(dispatchRequest(key),env,staff),e=>e.status===403&&e.code==='permission_denied');
  assert.equal(await first('SELECT id FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?',staff.id,key),null);
  for(const current of [owner,admin])assert.equal((await handleEmailAdmin(dispatchRequest(),env,current)).status,'succeeded');
  assert.equal(sent.length,before);
});
