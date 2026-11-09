// Production native SQL on REDUCED SQLite; provider/PG locks are simulated.
import test from 'node:test';import assert from 'node:assert/strict';
import {principalFixture,I} from './native-principal-fixture.mjs';
import {installCanonicalHarness} from './posting-authority-fixture.mjs';
import {PostgresManagedSessions} from '../../domain/burimunsi/postgres-managed-sessions.js';
import {createManagedRequestGate} from '../../domain/burimunsi/managed-request-gate.js';
function fixture(){const f=principalFixture(),h=installCanonicalHarness(f);
 f.sqlite.exec('CREATE TABLE private.burimunsi_session_links(native_session_id TEXT PRIMARY KEY,collection_id TEXT,account_id TEXT,principal_user_id TEXT,principal_session_id TEXT,created_at INTEGER,expires_at INTEGER)');
 const binding=new PostgresManagedSessions({db:f.db,groupId:I.group});f.store.sessionBinding=binding;
 return {...f,h,binding,issue:()=>f.store.createSessionIfCurrent(f.issuance),read:()=>f.store.loadSession('c'.repeat(64),I.installation,I.now)};
}
test('PIN session insertion atomically binds the existing canonical session',async()=>{const f=fixture();try{
 assert.deepEqual(await f.issue(),{created:true,expiresAt:f.issuance.expiresAt});const actor=await f.read();
 assert.equal(actor.principalSessionId,I.canonical);assert.equal(actor.principalUserId,I.principal);
 assert.equal(f.sqlite.prepare('SELECT count(*) n FROM private.burimunsi_session_links').get().n,1);
 assert.equal(f.sqlite.prepare('SELECT count(*) n FROM app.auth_sessions').get().n,1);
}finally{f.close();}});
test('native expiry is capped before INSERT to managed expiry',async()=>{const f=fixture();try{
 const expiry=Math.floor(I.now/1000)+30;f.execute('UPDATE app.auth_sessions SET expires_at=?',expiry);
 assert.equal((await f.issue()).expiresAt,expiry*1000);assert.equal((await f.read()).expiresAt,expiry*1000);
}finally{f.close();}});
test('legacy native sessions receive no invented managed linkage',async()=>{const f=fixture();try{
 await assert.rejects(f.session(),/managed_session_required/);
 assert.equal(f.sqlite.prepare('SELECT count(*) n FROM private.burimunsi_session_links').get().n,0);
}finally{f.close();}});
for(const [label,change]of [
 ['managed revocation',f=>f.execute('UPDATE app.auth_sessions SET revoked_at=1')],
 ['provider session removed',f=>{f.h.managed=false;}],
 ['managed expiry',f=>f.execute('UPDATE app.auth_sessions SET expires_at=?',Math.floor(I.now/1000))],
 ['wrong principal',f=>f.execute("UPDATE app.auth_sessions SET user_id='other-user'")],
 ['wrong surface',f=>f.execute("UPDATE app.auth_sessions SET surface='member'")],
 ['missing canonical session',f=>f.execute('DELETE FROM app.auth_sessions')]
])test('bound session denies '+label,async()=>{const f=fixture();try{await f.issue();change(f);await assert.rejects(f.read());}finally{f.close();}});
test('provider refresh with same session ID preserves binding',async()=>{const f=fixture();try{await f.issue();
 f.execute('UPDATE app.auth_sessions SET expires_at=expires_at+600');assert.equal((await f.read()).sessionId,I.issued);
}finally{f.close();}});
test('new managed login for same user cannot inherit old native token',async()=>{const f=fixture();try{await f.issue();
 const sid='20000000-0000-4000-8000-000000000009';f.execute('UPDATE app.auth_sessions SET id=?',sid);f.h.sessionId=sid;
 await assert.rejects(f.read(),/managed_session_required/);
}finally{f.close();}});
test('link failure rolls back issued native token and audit together',async()=>{const f=fixture();try{
 f.state.afterQuery=async text=>{if(text.startsWith('INSERT INTO private.burimunsi_session_links'))throw Error('test link loss');};
 await assert.rejects(f.issue());assert.equal(f.sqlite.prepare('SELECT count(*) n FROM private.burimunsi_sessions WHERE id=?').get(I.issued).n,0);
 assert.equal(f.sqlite.prepare('SELECT count(*) n FROM private.burimunsi_session_links').get().n,0);
 assert.equal(f.sqlite.prepare('SELECT count(*) n FROM private.burimunsi_audit').get().n,0);
}finally{f.close();}});
for(const [field,value]of [['account_id','another'],['principal_user_id','another'],['principal_session_id','another'],['expires_at',1]])
 test('link mismatch rejects '+field,async()=>{const f=fixture();try{await f.issue();f.execute(`UPDATE private.burimunsi_session_links SET ${field}=?`,value);await assert.rejects(f.read());}finally{f.close();}});
test('wrong managed principal cannot issue PIN-only fallback token',async()=>{const f=fixture();try{
 f.execute("UPDATE app.auth_sessions SET user_id='other'");await assert.rejects(f.issue());
 assert.equal(f.sqlite.prepare('SELECT count(*) n FROM private.burimunsi_sessions WHERE id=?').get(I.issued).n,0);
}finally{f.close();}});
function gateFixture(){const state={verified:0,projected:0,operation:0,claims:{old:true}},work={assert:async()=>{},kind:'http_admin'};
 const db={applicationWork:work,setClaims:claims=>{state.claims=claims;}},env={DB:db,AUTH_ACTOR:{stale:true},AUTH_VERIFIED:{stale:true},ADMIN_AUTH_EXCHANGE:true};
 const verified={claims:{sub:I.account,session_id:I.canonical,exp:Math.floor(I.now/1000)+60},user:{id:I.account,is_anonymous:false}};
 const deps={clock:()=>I.now,applicationWorkTuple:()=>[I.request,1,'1'.repeat(64)],verifyToken:async(e,t)=>{state.verified++;assert(!e.AUTH_ACTOR&&!e.AUTH_VERIFIED&&!e.ADMIN_AUTH_EXCHANGE);return verified;},
 projectSession:async(e,v,o)=>{state.projected++;state.options=o;e.DB.setClaims(v.claims);return {userId:I.principal,sessionId:I.canonical,surface:'admin'};}};
 const request=new Request('https://test.invalid/v1/burimunsi/home',{headers:{'X-BuriMunsi-Collect-Session':'testheader.testpayload.testsignature'}});
 return {state,db,env,work,verified,deps,request,run:(op=async()=>{state.operation++;return 7;})=>createManagedRequestGate(deps)({request,env,groupId:I.group},op)};
}
test('real verifier port invoked; only existing canonical identity projected',async()=>{const f=gateFixture();assert.equal(await f.run(),7);
 assert.equal(f.state.verified,1);assert.equal(f.state.projected,1);assert.deepEqual(f.state.options,{surface:'admin',existingLinkOnly:true});assert.deepEqual(f.state.claims,{});
 assert.deepEqual(f.env.AUTH_ACTOR,{stale:true});
});
for(const value of [null,'','not jwt','a.b.c','Bearer testheader.testpayload.testsignature','a'.repeat(8193)+'.b.c'])test('bad provider header rejected before verification '+String(value).slice(0,15),async()=>{
 const f=gateFixture();f.request.headers.delete('X-BuriMunsi-Collect-Session');if(value!==null)f.request.headers.set('X-BuriMunsi-Collect-Session',value);
 await assert.rejects(f.run(),/managed_session_required/);assert.equal(f.state.verified,0);assert.equal(f.state.operation,0);
});
for(const [label,mutate]of [['anonymous',f=>{f.verified.user.is_anonymous=true;}],['expired',f=>{f.verified.claims.exp=0;}],
 ['wrong subject',f=>{f.verified.user.id=I.session;}],['bad session ID',f=>{f.verified.claims.session_id='invented';}]])
 test('managed gate rejects '+label,async()=>{const f=gateFixture();mutate(f);await assert.rejects(f.run());assert.equal(f.state.operation,0);assert.deepEqual(f.state.claims,{});});
test('provider errors are fixed codes, never provider secret text',async()=>{const f=gateFixture();f.deps.verifyToken=async()=>{throw Error('secret-token');};
 await assert.rejects(f.run(),e=>e.message==='managed_session_required');assert.deepEqual(f.state.claims,{});
});
test('claims cleared on handler failure',async()=>{const f=gateFixture();await assert.rejects(f.run(async()=>{throw Error('failure');}));assert.deepEqual(f.state.claims,{});});
test('request DB cannot be reused concurrently',async()=>{const f=gateFixture();await f.run(async()=>{await assert.rejects(f.run(),/managed_context_busy/);return 8;});assert.deepEqual(f.state.claims,{});});
test('replaced work cannot inherit verified identity',async()=>{const f=gateFixture();f.deps.verifyToken=async()=>{f.db.applicationWork={assert:async()=>{}};return f.verified;};
 await assert.rejects(f.run(),/request_not_admitted/);assert.equal(f.state.operation,0);
});
