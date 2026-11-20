// Production native gate/session/pairing orchestration over the reduced SQLite
// fixture. PostgreSQL proof functions/roles/triggers are explicit doubles here;
// this proves no browser session or provider call is used, not SQL deployment.
import test from 'node:test';
import assert from 'node:assert/strict';
import {gatewayFixture,I,OLD} from './collect-gateway-fixture.mjs';
import {principalFixture,I as LEGACY} from './native-principal-fixture.mjs';
import {createPhonePinRequestGate,PIN_CONTEXT_SQL,PIN_SET_CONTEXT_SQL} from '../../domain/burimunsi/phone-pin-request.js';
import {PostgresPhonePinSessions,CURRENT_PIN_CONTEXT_SQL} from '../../domain/burimunsi/postgres-phone-pin-sessions.js';
import {PostgresNativeAuthStore} from '../../domain/burimunsi/postgres-auth-store.js';
import {NATIVE_PIN_PAIR_SQL,PAIR_TARGET_SQL,NATIVE_PIN_CUSTODY_SQL} from '../../domain/burimunsi/postgres-collect-gateway.js';
import {CONTRACT_VERSION} from '../../domain/burimunsi/wire/native-contract.mjs';
import {sha256} from '../../domain/burimunsi/values.js';

async function nativeFixture(t){
 const f=await gatewayFixture();t.after(f.close);const token='a'.repeat(64),device='d'.repeat(64);
 f.execute('ALTER TABLE private.burimunsi_sessions ADD COLUMN auth_method TEXT DEFAULT \'phone_pin\'');
 f.execute('UPDATE private.burimunsi_sessions SET token_hash=?',await sha256(token));
 f.h.managed=false;f.h.emailFresh=false;f.h.ownerLive=false;f.h.installationApproved=false;
 f.db.setClaims=()=>{};
 f.store.sessionBinding=new PostgresPhonePinSessions({db:f.db,groupId:I.group});
 f.store.session=(...args)=>PostgresNativeAuthStore.prototype.session.apply(f.store,args);
 f.actor={...f.actor,installationId:I.installation};
 const snapshot=()=>{
  const a=f.sqlite.prepare('SELECT * FROM private.burimunsi_accounts WHERE id=?').get(I.account),
   s=f.sqlite.prepare('SELECT * FROM private.burimunsi_sessions WHERE id=?').get(I.session),
   d=f.sqlite.prepare('SELECT * FROM private.burimunsi_device_grants WHERE id=?').get(I.grant);
  const expiry=Math.max(s.expires_at,f.leaseExpiresAt??0);
  const databaseNow=f.databaseNow??I.now;
  if(!a.active||a.removed||s.revoked||!d.active||s.credential_version!==a.credential_version||s.grant_version!==d.version||
   s.created_at>databaseNow+5000||expiry<=databaseNow)return null;
  return {collection_id:I.group,account_id:I.account,principal_user_id:a.principal_user_id,native_session_id:I.session,
   grant_id:I.grant,installation_id:I.installation,profile:d.profile,role:a.role,capabilities:JSON.parse(a.capabilities),
   created_at:s.created_at,expires_at:expiry,credential_version:a.credential_version,grant_version:d.version,shared_role:'owner',now_ms:databaseNow};
 };
 let current=null;const unsafe=f.sql.unsafe;
 f.sql.unsafe=async(text,args=[])=>{
  if(text===PIN_CONTEXT_SQL||text===PIN_SET_CONTEXT_SQL){
   const row=args[0]===token&&args[1]===I.installation&&args[2]===device&&args[3]==='internal_receiver'?snapshot():null;
   if(text===PIN_CONTEXT_SQL)return row?[row]:[];current=row;return row?[{result:row}]:[];
  }
  if(text===CURRENT_PIN_CONTEXT_SQL)return current&&snapshot()?[snapshot()]:[];
  if(text.includes('JOIN LATERAL private.burimunsi_pin_context() pin ON pin.native_session_id=s.id')){
   // SQLite has no PostgreSQL table-valued context function. Substitute only
   // the current independently checked fixture tuple, never caller SQL data.
   const row=current&&snapshot();if(!row)return [];
   assert.equal(row.native_session_id,I.session);assert.ok(Number.isSafeInteger(row.expires_at));
   text=text.replace('JOIN LATERAL private.burimunsi_pin_context() pin ON pin.native_session_id=s.id',
    `JOIN (SELECT '${I.session}' AS native_session_id, ${row.expires_at} AS expires_at) pin ON pin.native_session_id=s.id`);
  }
  if(text===PAIR_TARGET_SQL){f.state.queries.push({text,values:args});f.targetChecked=!!current&&args[0]===f.code&&args[1]===I.installation&&f.targetAllowed!==false;return [{allowed:f.targetChecked}];}
  if(text===NATIVE_PIN_CUSTODY_SQL){
   f.state.queries.push({text,values:args});assert.equal(f.targetChecked,true,'custody follows exact raw-code target authorization');
   assert.deepEqual(args,[I.group,I.session,I.installation,I.account]);f.custodyClaims=(f.custodyClaims??0)+1;
   const row=snapshot(),grant=f.sqlite.prepare('SELECT custodian_account_id FROM private.burimunsi_device_grants WHERE id=?').get(I.grant);
   if(!row||grant.custodian_account_id!==null&&grant.custodian_account_id!==row.account_id)throw Object.assign(Error('Synthetic custody denial'),{code:'42501'});
   f.execute('UPDATE private.burimunsi_device_grants SET custodian_account_id=? WHERE id=?',row.account_id,I.grant);
   return [{result:{claimed:true,grantId:I.grant,grantVersion:row.grant_version}}];
  }
  if(text.includes('burimunsi_gateway_retire(')){
   f.state.queries.push({text,values:args});f.retireCalls=(f.retireCalls??0)+1;
   assert.equal(args[0],I.group);assert.equal(args[1],f.code);
   assert.equal(args[3],await sha256('burimunsi.gateway.retire.v1:'+await sha256(f.code)+':'+args[2]));
   if(f.retireFailure)throw f.retireFailure;
   // Deliberately invalidate ordinary native context after the atomic SQL
   // result: the adapter may check request work, never reauthenticate it.
   current=null;
   return [{result:f.retireResult??{retired:true,handoffId:'20000000-0000-4000-8000-000000000009',requestId:args[2],reauthenticationRequired:true}}];
  }
  if(text===NATIVE_PIN_PAIR_SQL){
   f.state.queries.push({text,values:args});const row=snapshot();if(!current||!row||row.role!=='admin'||!row.capabilities.includes('gateway.manage'))return [];
   return f.sqlite.prepare(`SELECT p.*,b.owner_user_id,b.receiving_account_id,b.version AS binding_version,
    b.subscription_evidence,b.created_at AS binding_created_at,a.provider,a.public_code,a.recipient_name,a.currency,a.timezone
    FROM app.momo_gateway_pairings p JOIN app.momo_gateway_bindings b ON b.id=p.binding_id
    JOIN app.momo_receiving_accounts a ON a.id=b.receiving_account_id
    JOIN private.burimunsi_scopes s ON s.active_binding_id=b.id AND s.receiving_account_id=b.receiving_account_id
    JOIN private.burimunsi_device_grants d ON d.collection_id=s.collection_id
    WHERE p.code_sha256=? AND s.collection_id=? AND s.enabled=1 AND s.binding_version=b.version
    AND b.status='active' AND a.status='active' AND p.expires_at>? AND d.installation_id=?
    AND d.active=1 AND d.profile='internal_receiver' AND d.custodian_account_id=? AND b.owner_user_id=?`).all(
     args[0],args[1],Math.floor(I.now/1000),args[2],row.account_id,row.principal_user_id).map(r=>({...r}));
  }
  return unsafe(text,args);
 };
 f.db.statement=async(_sql,statement)=>{
  f.statements.push(statement);
  if(statement.sql.startsWith('INSERT INTO app.mutation_guards')){
   const values=statement.values;assert.equal(values[4],I.group);assert.equal(values[5],'receivers.manage');
   assert.equal(values[6],null,'PIN is never represented as AAL2');assert.equal(values[7],null,'PIN is never represented as email/MFA');
  }
  if(f.failStatement?.(statement))throw Error('synthetic statement failure');
  const result=f.sqlite.prepare(statement.sql).run(...statement.values);return {success:true,meta:{changes:Number(result.changes)}};
 };
 const gate=createPhonePinRequestGate({secrets:{pinPepper:new Uint8Array(32),pinPepperId:'synthetic'},networkBucket:async()=>assert.fail('Not a login'),clock:()=>I.now});
 const invoke=async(fn)=>gate({env:f.env,request:new Request('https://native-gateway.example.invalid/v1/burimunsi/gateway/pair',{
  method:'POST',headers:{'X-BuriMunsi-Auth':'phone_pin','X-BuriMunsi-Profile':'internal_receiver','X-BuriMunsi-Installation':I.installation,
   'X-BuriMunsi-Device':device,'X-BuriMunsi-Group':I.group,'X-BuriMunsi-Contract':CONTRACT_VERSION,authorization:'Bearer '+token}})},fn);
 const pair=(replace=false)=>invoke(async()=>f.registry.pair(f.actor,{pairingCode:f.code,replace,requestId:I.request}));
 return Object.assign(f,{invoke,pair});
}
test('native adapter uses current scoped lease instead of expired immutable session deadline',async t=>{
 const f=await nativeFixture(t);f.execute('UPDATE private.burimunsi_sessions SET expires_at=?',I.now-1);f.leaseExpiresAt=I.now+60000;
 let actor;await f.invoke(async()=>{actor=await f.store.loadSession(await sha256('a'.repeat(64)),I.installation,I.now);});
 assert.equal(actor.sessionId,I.session);assert.equal(actor.expiresAt,f.leaseExpiresAt);
 f.leaseExpiresAt=0;await assert.rejects(f.invoke(()=>assert.fail('Expired lease must deny')),e=>e.status===401);
});
test('native store accepts a database-proven PIN session only within the five-second clock bound',async t=>{
 for(const skew of [100,5000,5001]){
  const f=await nativeFixture(t);f.execute('UPDATE private.burimunsi_sessions SET created_at=?',I.now+skew);f.databaseNow=I.now+skew;
  if(skew<=5000){let actor;await f.invoke(async()=>{actor=await f.store.loadSession(await sha256('a'.repeat(64)),I.installation,I.now);});
   assert.equal(actor?.sessionId,I.session);}
  else await assert.rejects(f.invoke(()=>assert.fail('Future proof must not reach store')),e=>e.status===401);
 }
 const pin=await nativeFixture(t);pin.execute('UPDATE private.burimunsi_sessions SET created_at=?',I.now+5000);pin.databaseNow=I.now+5000;
 await pin.invoke(async()=>{assert.equal(await pin.store.loadSession(await sha256('a'.repeat(64)),I.installation,I.now-1),null);});
 for(const skew of [100,5000,5001]){
  const shifted=await nativeFixture(t);shifted.execute('UPDATE private.burimunsi_sessions SET created_at=?',I.now+skew);
  if(skew<=5000){let actor;await shifted.invoke(async()=>{actor=await shifted.store.loadSession(await sha256('a'.repeat(64)),I.installation,I.now);});
   assert.equal(actor?.sessionId,I.session);}
  else await assert.rejects(shifted.invoke(()=>assert.fail('Database future bound must deny')),e=>e.status===401);
 }
 const legacy=principalFixture();t.after(legacy.close);legacy.execute('UPDATE private.burimunsi_sessions SET created_at=?',LEGACY.now+1);
 assert.equal(await legacy.session(),null,'a non-PIN session keeps its strict creation-time check');
});
test('original signed-in Pair Receiver uses exact Admin-assigned native target without web session',async t=>{
 const f=await nativeFixture(t);
 const first=await f.pair(),second=await f.pair();assert.equal(first.gateway_token,second.gateway_token);assert.equal(first.binding.id,OLD);
 assert.equal(first.binding.collection_id,I.group);assert.equal(first.binding.subscription_id,1);assert.equal(f.h.managed,false);
 assert.equal(f.count('app.momo_gateway_credentials'),1);assert.equal(f.count('app.audit_log'),1);
 assert.equal(f.sqlite.prepare('SELECT custodian_account_id FROM private.burimunsi_device_grants WHERE id=?').get(I.grant).custodian_account_id,I.account);
});
test('genuine unassigned initial target claims custody after its exact code guard before actual credential SELECT',async t=>{
 const f=await nativeFixture(t);f.execute('UPDATE private.burimunsi_device_grants SET custodian_account_id=NULL WHERE id=?',I.grant);
 const response=await f.pair();assert.match(response.gateway_token,/^[a-f0-9]{64}$/);
 assert.equal(f.sqlite.prepare('SELECT custodian_account_id FROM private.burimunsi_device_grants WHERE id=?').get(I.grant).custodian_account_id,I.account);
 const calls=f.state.queries.map(q=>q.text),guard=calls.indexOf(PAIR_TARGET_SQL),claim=calls.indexOf(NATIVE_PIN_CUSTODY_SQL),select=calls.indexOf(NATIVE_PIN_PAIR_SQL);
 assert.ok(guard>=0&&guard<claim&&claim<select);assert.equal(f.count('app.momo_gateway_credentials'),1);
});
test('pair replace flag cannot re-pair the caller or stand in for retirement',async t=>{
 const f=await nativeFixture(t);await assert.rejects(f.pair(true),e=>e.code==='invalid_pairing_code');
 assert.equal(f.count('app.momo_gateway_credentials'),0);assert.equal(f.statements.length,0);
});
test('native retirement returns ACK only after scope-invalidating SQL and never retrieves a target credential',async t=>{
 const f=await nativeFixture(t),before=f.replacementSnapshot();
 const ack=await f.invoke(()=>f.registry.replace(f.actor,f.command));
 assert.deepEqual(ack,{retired:true,handoffId:'20000000-0000-4000-8000-000000000009',requestId:I.request,reauthenticationRequired:true});
 assert.equal(f.retireCalls,1);assert.equal(f.count('app.momo_gateway_credentials'),0);
 assert.equal(f.statements.length,0,'SQL retire owns scope-first assertion; no earlier mutation-guard scope lock');
 assert.deepEqual(f.replacementSnapshot(),before,'SQL is an explicit policy double in this host test');
 assert.equal(f.state.queries.some(q=>q.text===PAIR_TARGET_SQL),false);
});
test('unknown retirement COMMIT is never replayed or automatically re-paired by the adapter',async t=>{
 const f=await nativeFixture(t);
 await assert.rejects(f.invoke(()=>{f.loseCommit=true;return f.registry.replace(f.actor,f.command);}));
 assert.equal(f.retireCalls,1);assert.equal(f.count('app.momo_gateway_credentials'),0);
});
test('target guard denial occurs before credential lookup or mint',async t=>{
 const f=await nativeFixture(t);f.targetAllowed=false;
 await assert.rejects(f.pair(),e=>e.code==='pairing_unavailable');
 assert.equal(f.statements.some(s=>s.sql.startsWith('INSERT INTO app.momo_gateway_credentials')),false);
 assert.equal(f.state.queries.some(q=>q.text==='SELECT * FROM app.momo_gateway_credentials WHERE pairing_id=$1'),false);
 assert.equal(f.custodyClaims??0,0);
});
test('native pair unknown COMMIT recovers only existing credential without replaying credential or audit writes',async t=>{
 const f=await nativeFixture(t),result=await f.invoke(async()=>{f.loseCommit=true;return f.registry.pair(f.actor,{pairingCode:f.code,replace:false,requestId:I.request});});
 assert.match(result.gateway_token,/^[a-f0-9]{64}$/);assert.equal(f.statements.filter(s=>s.sql.startsWith('INSERT INTO app.momo_gateway_credentials')).length,1);
 assert.equal(f.count('app.momo_gateway_credentials'),1);assert.equal(f.count('app.audit_log'),1);
 const calls=f.state.queries.map(q=>q.text),readOnlyRecovery=calls.lastIndexOf('SELECT pg_advisory_xact_lock(734636924058501::bigint)');
 assert.equal(calls.slice(readOnlyRecovery+1).includes(NATIVE_PIN_CUSTODY_SQL),false,'unknown-outcome reconciliation never claims custody');
});
test('native pairing cannot return credential success when canonical audit rolls back',async t=>{
 const f=await nativeFixture(t);f.failStatement=s=>s.sql.startsWith('INSERT INTO audit_log');
 await assert.rejects(f.pair());assert.equal(f.count('app.momo_gateway_credentials'),0);assert.equal(f.count('app.audit_log'),0);
 assert.equal(f.sqlite.prepare('SELECT claimed_installation_id FROM app.momo_gateway_pairings').get().claimed_installation_id,null);
});
for(const [name,query,args]of [
 ['staff role',"UPDATE private.burimunsi_accounts SET role='staff'",[]],
 ['missing capability',"UPDATE private.burimunsi_accounts SET capabilities=?",[JSON.stringify(['records.read'])]],
 ['wrong registered custodian',"UPDATE private.burimunsi_device_grants SET custodian_account_id='another-native-account' WHERE id=?",[I.grant]],
 ['already claimed code','UPDATE app.momo_gateway_pairings SET claimed_installation_id=?',['20000000-0000-4000-8000-000000000002']],
 ['expired code','UPDATE app.momo_gateway_pairings SET expires_at=?',[Math.floor(I.now/1000)]]
])test('native pair denies '+name+' without changing receiver credential',async t=>{
 const f=await nativeFixture(t);f.execute(query,...args);await assert.rejects(f.pair());assert.equal(f.count('app.momo_gateway_credentials'),0);
});
