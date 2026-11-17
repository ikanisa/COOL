import test from 'node:test';import assert from 'node:assert/strict';
import {gatewayFixture,I,OLD,TARGET,PAIR} from './collect-gateway-fixture.mjs';
import {PostgresCollectGateway,CANONICAL_PAIR_SQL,GATEWAY_READ_PERMISSION_SQL,createCanonicalGatewayPair} from '../../domain/burimunsi/postgres-collect-gateway.js';
import {GATEWAY_OUTCOME_SQL,readGatewayReplacementOutcome} from '../../domain/burimunsi/postgres-gateway-outcome.js';
import {createNativeHandler} from '../../domain/burimunsi/http.js';

test('closed adapter construction performs no SQL and rejects an unrelated DB',async t=>{
 const f=await gatewayFixture();t.after(f.close);const before=f.state.queries.length;
 new PostgresCollectGateway({authority:f.store,env:f.env});assert.equal(f.state.queries.length,before);
 createCanonicalGatewayPair({env:f.env,groupId:I.group});assert.equal(f.state.queries.length,before);
 assert.throws(()=>new PostgresCollectGateway({authority:f.store,env:{DB:{}}}),/collect_adapter_required/);
});
test('health is SELECT-only, distinguishes upload custody and preserves upload hold',async t=>{
 const f=await gatewayFixture();t.after(f.close);f.seedCredential();
 f.execute('INSERT INTO app.momo_gateway_captures VALUES(?,?,?)','capture-1','old-credential','2026-11-07T10:00:00.000Z');
 const before=f.sqlite.prepare('SELECT * FROM app.momo_gateway_credentials').get();
 const result=await f.registry.status(f.actor);
 assert.equal(result.pending,2);assert.equal(result.lastUpload,'2026-11-07T10:00:00.000Z');assert.equal(result.problem,'gateway_upload_held');
 assert.deepEqual(f.sqlite.prepare('SELECT * FROM app.momo_gateway_credentials').get(),before);assert.equal(f.statements.length,0);
 assert.ok(f.state.queries.some(q=>q.text.includes('READ ONLY')));
 assert.ok(f.state.queries.every(q=>!/^\s*(?:INSERT|UPDATE|DELETE|TRUNCATE)\b/.test(q.text)));
});
test('health normalizes retained receiver timestamp offsets into UTC without altering custody',async t=>{
 const f=await gatewayFixture();t.after(f.close);f.seedCredential();
 f.execute('UPDATE app.momo_gateway_credentials SET oldest_pending_at=?,last_sms_at=?','2026-11-07T12:00:00+02:00','2026-11-07T12:05:00+02:00');
 const result=await f.registry.status(f.actor);assert.equal(result.oldest,'2026-11-07T10:00:00.000Z');assert.equal(result.lastCapture,'2026-11-07T10:05:00.000Z');assert.equal(f.statements.length,0);
});
for(const gate of ['emailFresh','allowed','managed'])test('read status denies missing current '+gate,async t=>{
 const f=await gatewayFixture();t.after(f.close);f.seedCredential();f.h[gate]=false;await assert.rejects(f.registry.status(f.actor));assert.equal(f.statements.length,0);
});
const unavailable=error=>error.code==='gateway_handoff_unavailable'&&error.status===503;
const noNativeProof=error=>error.code==='session_unavailable'&&error.status===401;
test('legacy web authority cannot retire a native receiver or alter retained custody',async t=>{
 const f=await gatewayFixture();t.after(f.close);f.seedCredential();
 const before=f.replacementSnapshot(),queries=f.state.queries.length,transactions=f.state.transactions;
 await assert.rejects(f.replace(),noNativeProof);
 assert.deepEqual(f.replacementSnapshot(),before);
 assert.equal(f.state.queries.length,queries);assert.equal(f.statements.length,0);assert.equal(f.state.transactions,transactions);
});
test('no canonical write callback or alternate public run can bypass unavailable handoff',async t=>{
 const f=await gatewayFixture();t.after(f.close);let called=false;
 for(const call of [()=>f.adapter.withAuthorityTransaction(()=>{called=true;}),()=>f.adapter.run(true,()=>{called=true;})])
  await assert.rejects(call(),unavailable);
 assert.equal(called,false);assert.equal(f.state.queries.length,0);assert.equal(f.statements.length,0);
});
test('native HTTP replacement rejects absent four-proof context without ACK or business SQL',async t=>{
 const f=await gatewayFixture();t.after(f.close);f.seedCredential();const before=f.replacementSnapshot();
 const unused=()=>{throw Error('Unexpected unrelated gateway HTTP consumer');};
 const handler=createNativeHandler({auth:{login:unused,authenticate:async()=>f.actor,logout:unused,changePasscode:unused,manageStaff:unused},
  records:{home:unused,page:unused,detail:unused,exportLedger:unused,commandStatus:unused},contributions:{allocate:unused},
  members:{enroll:unused,setActive:unused},gateway:f.registry,origin:'https://native-gateway.example.invalid',networkBucket:unused});
 const response=await handler(new Request('https://native-gateway.example.invalid/v1/burimunsi/gateway/replace',{
  method:'POST',headers:{'content-type':'application/json','x-burimunsi-installation':I.installation,authorization:'Bearer '+'a'.repeat(64)},
  body:JSON.stringify(f.command)}));
 assert.equal(response.status,401);assert.deepEqual(await response.json(),{ok:false,error:{code:'session_unavailable'}});
 assert.deepEqual(f.replacementSnapshot(),before);assert.equal(f.statements.length,0);assert.equal(f.state.queries.length,0);
});
test('repeated original replacement requests cannot manufacture a lost-commit rotation or receipt',async t=>{
 const f=await gatewayFixture();t.after(f.close);f.seedCredential();const before=f.replacementSnapshot();
 f.loseCommit=true;
 await assert.rejects(f.replace(),noNativeProof);await assert.rejects(f.replace(),noNativeProof);
 assert.equal(f.loseCommit,true,'no transaction reached a COMMIT');
 assert.deepEqual(f.replacementSnapshot(),before);assert.equal(f.statements.length,0);
 f.loseCommit=false;const outcome=await f.adapter.replacementOutcome(f.actor,I.request);
 assert.equal(outcome.state,'pending');assert.equal(outcome.financialState,'unresolved');
 assert.equal(f.count('private.burimunsi_command_receipts'),0);
});
test('revoked request work is still denied before unavailable replacement may enter SQL',async t=>{
 const f=await gatewayFixture();t.after(f.close);f.state.workRevoked=true;
 await assert.rejects(f.replace(),noNativeProof);assert.equal(f.state.queries.length,0);assert.equal(f.statements.length,0);
});
test('historical control-plane receipt remains readable without enabling a replacement writer',async t=>{
 const f=await gatewayFixture();t.after(f.close);f.seedCredential();
 const response={id:OLD,installationId:TARGET,receivingAccountId:'wallet-1'};
 f.seedReplacementReceipt(response);const before=f.replacementSnapshot();
 const outcome=await f.adapter.replacementOutcome(f.actor,I.request);
 assert.equal(outcome.state,'committed');assert.equal(outcome.financialState,'not_applicable');assert.deepEqual(outcome.response,response);
 await assert.rejects(f.replace(),noNativeProof);assert.deepEqual(f.replacementSnapshot(),before);assert.equal(f.statements.length,0);
});
test('replacement outcome never crosses original canonical principal',async()=>{
 const rows=[];assert.equal(await readGatewayReplacementOutcome({unsafe:async(_q,v)=>{rows.push(v);return [];}},{groupId:'g',actorId:I.account,requestId:I.request,principalUserId:'different-principal'}),null);
 assert.equal(rows[0][3],'different-principal');assert.match(GATEWAY_OUTCOME_SQL,/origin\.principal_user_id=\$4/);
});
test('retained replacement outcomes reject secret-bearing or wrong-operation receipts',async()=>{
 const query={groupId:I.group,actorId:I.account,requestId:I.request,principalUserId:I.principal};
 const row={collection_id:I.group,actor_id:I.account,request_id:I.request,operation:'burimunsi.gateway.replace',response:{id:OLD,installationId:TARGET,receivingAccountId:'wallet-1'}};
 await assert.rejects(readGatewayReplacementOutcome({unsafe:async()=>[{...row,response:{...row.response,pairing_code:'f'.repeat(64)}}]},query));
 await assert.rejects(readGatewayReplacementOutcome({unsafe:async()=>[{...row,operation:'burimunsi.allocate'}]},query),/gateway_outcome_inconsistent/);
});
test('canonical anonymous pairing retains the same encrypted credential on explicit retry',async t=>{
 const f=await gatewayFixture();t.after(f.close);const body={pairing_code:f.code,installation_id:I.installation};
 const first=await f.pair(body),second=await f.pair(body);assert.equal(first.gateway_token,second.gateway_token);assert.equal(first.binding.owner_user_id,I.principal);assert.equal(first.binding.id,OLD);
 assert.equal(f.count('app.momo_gateway_credentials'),1);const stored=f.sqlite.prepare('SELECT * FROM app.momo_gateway_credentials').get();assert.notEqual(stored.token_ciphertext,first.gateway_token);assert.equal(stored.token_sha256.length,64);
});
test('unknown pairing COMMIT reconciles by SELECT without a second credential write',async t=>{
 const f=await gatewayFixture();t.after(f.close);f.loseCommit=true;const result=await f.pair({pairing_code:f.code,installation_id:I.installation});
 assert.equal(result.binding.id,OLD);assert.equal(f.statements.filter(st=>st.sql.startsWith('INSERT INTO app.momo_gateway_credentials')).length,1);assert.equal(f.count('app.momo_gateway_credentials'),1);
});
test('rolled-back pairing remains unconfirmed without automatic reissue',async t=>{
 const f=await gatewayFixture();t.after(f.close);f.failStatement=st=>st.sql.startsWith('INSERT INTO app.momo_gateway_credentials');
 await assert.rejects(f.pair({pairing_code:f.code,installation_id:I.installation}),/gateway_pairing_unconfirmed/);
 assert.equal(f.statements.filter(st=>st.sql.startsWith('INSERT INTO app.momo_gateway_credentials')).length,1);assert.equal(f.count('app.momo_gateway_credentials'),0);assert.equal(f.sqlite.prepare('SELECT claimed_installation_id FROM app.momo_gateway_pairings').get().claimed_installation_id,null);
});
for(const gate of ['ownerLive','emailFresh','installationApproved'])test('pairing rejects missing original '+gate,async t=>{
 const f=await gatewayFixture();t.after(f.close);f.h[gate]=false;await assert.rejects(f.pair({pairing_code:f.code,installation_id:I.installation}));assert.equal(f.count('app.momo_gateway_credentials'),0);
});
for(const [name,sql,args] of [
 ['receiving profile',"UPDATE private.burimunsi_device_grants SET profile='staff'",[]],
 ['custodian principal','UPDATE private.burimunsi_accounts SET principal_user_id=?',['another-principal']],
 ['custodian admission',"UPDATE private.burimunsi_accounts SET role='staff'",[]],
 ['account link','DELETE FROM private.burimunsi_device_accounts',[]],
 ['scope version','UPDATE private.burimunsi_scopes SET binding_version=4',[]],
 ['challenge expiry','UPDATE app.momo_gateway_pairings SET expires_at=?',[Math.floor(I.now/1000)]]
])test('canonical pairing denies changed '+name,async t=>{
 const f=await gatewayFixture();t.after(f.close);f.execute(sql,...args);
 await assert.rejects(f.pair({pairing_code:f.code,installation_id:I.installation}));assert.equal(f.count('app.momo_gateway_credentials'),0);
});
test('pairing refuses a different installation after original claim',async t=>{
 const f=await gatewayFixture();t.after(f.close);await f.pair({pairing_code:f.code,installation_id:I.installation});
 await assert.rejects(f.pair({pairing_code:f.code,installation_id:TARGET}),/pairing_claimed/);assert.equal(f.count('app.momo_gateway_credentials'),1);
});
test('closed SQL keeps scope/owner/session/receiving grant and has no read heartbeat',()=>{
 assert.match(CANONICAL_PAIR_SQL,/owner\.auth_session_id=p\.originating_session_id/);assert.match(CANONICAL_PAIR_SQL,/native\.principal_user_id=b\.owner_user_id/);
 assert.match(CANONICAL_PAIR_SQL,/d\.profile='internal_receiver'/);assert.match(CANONICAL_PAIR_SQL,/d\.installation_id=\$3::uuid/);
 assert.doesNotMatch(GATEWAY_READ_PERMISSION_SQL,/FOR (?:SHARE|UPDATE)|\b(?:INSERT|UPDATE|DELETE)\b/);
});
