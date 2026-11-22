import test from 'node:test';import assert from 'node:assert/strict';
import {authorityFixture,I} from './posting-authority-fixture.mjs';
import {PostgresPostingAuthority} from '../../domain/burimunsi/postgres-posting-authority.js';
const phases=['before_preparation','after_preparation_source','before_preparation_storage','after_preparation_storage','before_allocation','after_allocation','before_posting','after_posting'];
for(const phase of phases)test('native financial proof at '+phase,async t=>{
 const f=authorityFixture();t.after(f.close);const proof=await f.run(phase);
 assert.deepEqual(proof,{contractVersion:1,kind:'native_operator',mode:'exception',groupId:I.group,receiptId:'transaction-1',requestId:I.request,
  actorId:I.account,sessionId:I.session,principalUserId:I.principal,principalSessionId:I.canonical});
 assert(Object.isFrozen(proof));assert.notEqual(proof.sessionId,proof.principalSessionId);
 assert.equal(f.h.guards.length,2);assert.equal(f.h.reads,2);assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM app.mutation_guards').get().n,0);
 const v=f.h.guards[0].values;assert.deepEqual(v.slice(1),[I.principal,I.canonical,Math.floor(I.now/1000),I.group,'payments.reconcile',2,null,300,'member-1',I.group]);
});
for(const [name,sql]of [
 ['inactive canonical principal',"UPDATE app.users SET access_status='disabled'"],
 ['reassigned native account',"UPDATE private.burimunsi_accounts SET principal_user_id='another-user'"],
 ['native session revoked','UPDATE private.burimunsi_sessions SET revoked=true'],
 ['native session expired',`UPDATE private.burimunsi_sessions SET expires_at=${I.now}`],
 ['native capability removed',`UPDATE private.burimunsi_accounts SET capabilities='["records.read"]'`],
 ['canonical session revoked','UPDATE app.auth_sessions SET revoked_at=123'],
 ['canonical session expired',`UPDATE app.auth_sessions SET expires_at=${Math.floor(I.now/1000)}`],
 ['canonical session missing','DELETE FROM app.auth_sessions'],
 ['member instead of admin session',"UPDATE app.auth_sessions SET surface='member'"],
 ['wrong canonical principal',"UPDATE app.auth_sessions SET user_id='another-user'"],
 ['future assurance event',`UPDATE app.auth_sessions SET mfa_at=${Math.floor(I.now/1000)+1}`]
])test('refuses '+name,async t=>{const f=authorityFixture();t.after(f.close);f.execute(sql);await assert.rejects(f.run());assert.equal(f.h.guards.length,0);});
test('unknown posting phase performs no SQL',async t=>{const f=authorityFixture();t.after(f.close);await assert.rejects(f.runtime.assertInTransaction(f.sql,{command:f.command,phase:'caller-phase'}),/posting_phase_invalid/);assert.equal(f.state.queries.length,0);});
for(const [field,value]of [['groupId','other-group'],['actorId',I.grant],['sessionId',I.issued],['mode','manual']])
 test('refuses altered command '+field,async t=>{const f=authorityFixture();t.after(f.close);f.command[field]=value;await assert.rejects(f.run());assert.equal(f.h.guards.length,0);});
test('cannot supply the principal from client actor data',async t=>{const f=authorityFixture();t.after(f.close);f.command.actor.principalUserId='forged';await assert.rejects(f.run(),/posting_principal_mismatch/);});
test('canonical helper denial is sanitized without an alternative session',async t=>{const f=authorityFixture();t.after(f.close);f.h.managed=false;await assert.rejects(f.run(),e=>e.code==='canonical_authority_unavailable'&&!e.message.includes('JWT'));assert.equal(f.h.guards.length,0);});
test('canonical SQL failure cannot fall back to local native capability',async t=>{const f=authorityFixture();t.after(f.close);f.h.afterCanonical=()=>{throw Error('private failure');};await assert.rejects(f.run(),/canonical_authority_unavailable/);});
test('financial guard denial is sanitized and transaction rolls back',async t=>{const f=authorityFixture();t.after(f.close);f.h.allowed=false;await assert.rejects(f.run(),e=>e.code==='posting_financial_authority_denied'&&e.status===403);assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM app.mutation_guards').get().n,0);});
test('native revocation while awaiting guard cannot produce a proof',async t=>{const f=authorityFixture();t.after(f.close);f.h.afterGuard=()=>f.execute('UPDATE private.burimunsi_sessions SET revoked=true');await assert.rejects(f.run(),/session_unavailable/);});
test('principal replacement after guard is rejected',async t=>{const f=authorityFixture();t.after(f.close);f.h.afterGuard=()=>f.execute("UPDATE app.auth_sessions SET user_id='another-user'");await assert.rejects(f.run(),/posting_principal_mismatch/);});
test('assurance binding changed after guard is rejected',async t=>{const f=authorityFixture();t.after(f.close);f.h.afterGuard=()=>f.execute('UPDATE app.auth_sessions SET mfa_at=?',Math.floor(I.now/1000));await assert.rejects(f.run(),/posting_authority_changed/);});
test('capabilities changed after guard cannot reuse earlier proof',async t=>{const f=authorityFixture();t.after(f.close);f.h.afterGuard=()=>f.execute(`UPDATE private.burimunsi_accounts SET capabilities='["records.read","payments.allocate","members.enroll"]'`);await assert.rejects(f.run(),/posting_authority_changed/);});
test('expired native session after clock advance is denied',async t=>{const f=authorityFixture();t.after(f.close);f.h.afterGuard=()=>{f.h.now=Math.floor(I.now/1000)+61;};await assert.rejects(f.run(),/session_unavailable/);});
test('admission replacement during awaited canonical read is denied',async t=>{const f=authorityFixture();t.after(f.close);f.h.afterCanonical=()=>{f.db.applicationWork={assert:async()=>{}};};await assert.rejects(f.run(),/request_not_admitted/);});
test('caller mutation after first await cannot retarget the proof',async t=>{const f=authorityFixture();t.after(f.close);f.h.afterCanonical=()=>{f.command.memberId='malicious-target';f.command.actor.principalUserId='forged';};const p=await f.run();assert.equal(p.principalUserId,I.principal);assert.equal(f.h.guards[0].values[9],'member-1');});
test('automatic work cannot borrow native managed authority',async t=>{const f=authorityFixture();t.after(f.close);f.command.mode='automatic';f.command.work={kind:'receipt',jobId:I.request,owner:'worker-1',leaseVersion:1};await assert.rejects(f.run(),/worker_financial_authority_required/);assert.equal(f.h.reads,0);});
test('trusted worker adapter receives immutable command and exact transaction',async t=>{
 const f=authorityFixture();t.after(f.close);f.command.mode='automatic';f.command.policyVersion='v1';f.command.work={kind:'receipt',jobId:I.request,owner:'worker-1',leaseVersion:1};
 const proof={contractVersion:1,kind:'admitted_worker',mode:'automatic',groupId:I.group,receiptId:'transaction-1',requestId:I.request,
   actorId:I.account,sessionId:I.session,principalUserId:I.principal,principalSessionId:I.canonical,policyVersion:'v1'};
 f.runtime.workerRuntime={assertInTransaction:async(sql,{command,phase})=>{assert.equal(sql,f.sql);assert(Object.isFrozen(command)&&Object.isFrozen(command.work));assert.equal(phase,'before_posting');return proof;}};
 assert.deepEqual(await f.run('before_posting'),proof);assert.equal(f.h.reads,0);assert.equal(f.h.guards.length,0);
});
for(const field of ['contractVersion','kind','mode','groupId','receiptId','requestId','policyVersion'])test('worker response must bind '+field,async t=>{
 const f=authorityFixture();t.after(f.close);f.command.mode='automatic';f.command.policyVersion='v1';f.command.work={kind:'receipt',jobId:I.request,owner:'worker-1',leaseVersion:1};
 const proof={contractVersion:1,kind:'admitted_worker',mode:'automatic',groupId:I.group,receiptId:'transaction-1',requestId:I.request,
 actorId:I.account,sessionId:I.session,principalUserId:I.principal,principalSessionId:I.canonical,policyVersion:'v1'};delete proof[field];
 f.runtime.workerRuntime={assertInTransaction:async()=>proof};await assert.rejects(f.run());
});
test('assembly performs no SQL, creates no principal, and requires the admitted authority',t=>{const f=authorityFixture();t.after(f.close);assert.equal(f.state.queries.length,0);assert.throws(()=>new PostgresPostingAuthority({authority:{}}));});

test('fresh native session retains millisecond precision rather than rounding issuance backwards',async t=>{
 const f=authorityFixture();t.after(f.close);f.h.millis=501;
 f.execute('UPDATE private.burimunsi_sessions SET created_at=?',I.now+500);
 assert.equal((await f.run()).principalUserId,I.principal);
});
test('a backward database clock step cannot produce a stale financial proof',async t=>{
 const f=authorityFixture();t.after(f.close);f.h.afterGuard=()=>{f.h.now=Math.floor(I.now/1000)-1;};
 await assert.rejects(f.run(),/posting_authority_changed/);
});
