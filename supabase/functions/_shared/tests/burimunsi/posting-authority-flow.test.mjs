import test from 'node:test';import assert from 'node:assert/strict';
import {preparedFlow,ids,count} from './prepared-contribution-fixture.mjs';
import {installCanonicalHarness} from './posting-authority-fixture.mjs';
import {PostgresPostingAuthority} from '../../domain/burimunsi/postgres-posting-authority.js';
// SQL boundary integration. Native session projection here remains synthetic;
// production native session SELECT/INSERT runs separately in principal tests.
// Managed-session helper and financial guard are simulated, not real PostgreSQL.
async function flow(){
 const f=await preparedFlow('exception');
 const h=installCanonicalHarness(f,{principal:ids.otherActor,canonicalSession:'00000011-1111-4111-8111-111111111111',now:Date.parse('2026-11-07T08:01:00Z')});
 f.writer.runtime=new PostgresPostingAuthority({authority:f.authority});h.phases=[];
 const proof=f.writer.runtime.assertInTransaction.bind(f.writer.runtime);
 f.writer.runtime.assertInTransaction=(sql,input)=>{h.phases.push(input.phase);return proof(sql,input);};return {...f,h};
}
test('connected native allocation prepares evidence and posts with canonical authority proof',async t=>{
 const f=await flow();t.after(f.close);const result=await f.allocate();
 assert.equal(result.amountRwf,12500);assert.equal(count(f,'app.ledger_entries'),1);assert.equal(f.state.puts,1);
 assert.equal(new Set(f.h.phases).size,8);
 assert.equal(f.h.guards.length,f.h.phases.length*2,'every proof executes insert and delete guards');
 assert.equal(count(f,'app.mutation_guards'),0);assert.equal(count(f,'private.burimunsi_command_receipts'),1);
 const audit=f.sqlite.prepare("SELECT actor_user_id,actor_session_id FROM app.audit_log WHERE action='payment.contribution.committed'").get();
 assert.equal(audit.actor_user_id,ids.otherActor);assert.equal(audit.actor_session_id,f.h.sessionId);assert.notEqual(audit.actor_session_id,ids.session);
});
test('completed native command replays without storage or a second ledger effect',async t=>{
 const f=await flow();t.after(f.close);const result=await f.allocate(),guards=f.h.guards.length;
 assert.deepEqual(await f.allocate(),result);assert.equal(f.state.puts,1);assert.equal(count(f,'app.ledger_entries'),1);assert.equal(f.h.guards.length,guards);
});
for(const field of ['allowed','managed'])test('denied '+field+' authority before preparation creates no evidence or credit',async t=>{
 const f=await flow();t.after(f.close);f.h[field]=false;await assert.rejects(f.allocate());
 assert.equal(f.state.puts,0);assert.equal(count(f,'app.ledger_entries'),0);assert.equal(count(f,'app.payments'),0);
});
for(const at of ['afterPreparation','afterPut'])test('canonical permission revoked at '+at+' refuses credit',async t=>{
 const f=await flow();t.after(f.close);f.state[at]=()=>{f.h.allowed=false;};await assert.rejects(f.allocate());
 assert.equal(f.state.puts,1);assert.equal(count(f,'app.ledger_entries'),0);assert.equal(count(f,'app.payments'),0);
 assert.equal(count(f,'private.burimunsi_command_receipts'),0);assert.equal(count(f,'app.mutation_guards'),0);
});
for(const change of ['principal','session','expiry'])test('changed canonical '+change+' after evidence cannot post',async t=>{
 const f=await flow();t.after(f.close);f.state.afterPreparation=()=>{
  if(change==='principal')f.sqlite.exec("UPDATE app.auth_sessions SET user_id='other-canonical-user'");
  if(change==='session')f.h.sessionId=ids.session;
  if(change==='expiry')f.sqlite.prepare('UPDATE app.auth_sessions SET expires_at=?').run(f.h.now);
 };await assert.rejects(f.allocate());assert.equal(count(f,'app.ledger_entries'),0);assert.equal(count(f,'app.payments'),0);
});
test('permission loss immediately after shared ledger writes rolls back every financial effect',async t=>{
 const f=await flow();t.after(f.close);const execute=f.db.statement;
 f.db.statement=async(sql,stmt)=>{const result=await execute(sql,stmt);if(stmt.sql.startsWith('INSERT INTO audit_log'))f.h.allowed=false;return result;};
 await assert.rejects(f.allocate());for(const table of ['payments','ledger_entries','momo_financial_links','contribution_posting_snapshots','notification_events'])assert.equal(count(f,'app.'+table),0,table);
 assert.equal(count(f,'private.burimunsi_command_receipts'),0);
});
test('lost final commit response retains one canonical credit with the new authority bridge',async t=>{
 const f=await flow();t.after(f.close);f.state.beforeFinancial=()=>{f.state.commitLost=true;};
 assert.equal((await f.allocate()).amountRwf,12500);assert.equal(count(f,'app.ledger_entries'),1);assert.equal(f.state.puts,1);
});
