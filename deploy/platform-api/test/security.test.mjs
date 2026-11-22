import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID,createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
import {fixture,authorization,admin,setupMfa,totp,claims} from './support/auth_fixture.mjs';
const {Miniflare,convertV4MiniflareOptions}=await import(process.env.COLLECT_MINIFLARE_MODULE??'miniflare');
const root=new URL('../',import.meta.url),mods=['groups.js','payments.js','evidence.js','notifications.js','admin.js','mutations.js','privacy.js'];
// Keep the original security scenarios on the now-required reason-bearing
// financial command. Missing-reason admission has its own negative probe.
const rpc=(f,s,name,body={})=>f.call('/v1/rpc/'+name,
 /^(?:propose|approve|reject)_payment_reconciliation_v2$/.test(name)
  ? {reason:'Controlled independent financial review',...body}:body,authorization(s));
async function regular(t){const f=await fixture({APP_ENVIRONMENT:'test'},{entrypoint:'index.js',extraModules:mods});t.after(()=>f.close());return f;}

// The pause exists only in this test entrypoint. Every SQL and R2 operation
// delegates to real Miniflare workerd bindings; there is no database mock.
async function paused(t,{path,phase='batch',hint=null,needle=null}={}) {
  let gate=async()=>{},mf,db;const messages=[];
  async function discover(folder,prefix=''){const result=[];for(const item of await readdir(folder,{withFileTypes:true})){if(item.isDirectory())result.push(...await discover(new URL(item.name+'/',folder),prefix+item.name+'/'));else if(!item.name.startsWith('._')&&item.name.endsWith('.js'))result.push(prefix+item.name);}return result;}
  const names=await discover(new URL('src/',root));
  const modules=[{type:'ESModule',path:fileURLToPath(new URL('test/security-entry.mjs',root)),contents:`
    import worker from '../src/index.js';
    export default {async fetch(request,env,ctx) {
      const pathname=new URL(request.url).pathname;const target=(${JSON.stringify(path)}.endsWith('/')?pathname.startsWith(${JSON.stringify(path)}):pathname===${JSON.stringify(path)})&&(${JSON.stringify(hint)}===null||request.headers.get('X-Test-Gate')===${JSON.stringify(hint)});
      let once=false;
      const pause=async(phase)=>{if(target&&!once&&phase===${JSON.stringify(phase)}){once=true;
        const result=await env.TEST_GATE.fetch('https://gate.test/phase',{method:'POST',body:JSON.stringify({phase})});if(!result.ok)throw new Error('test_gate_failure');}};
      const wrap=(statement,sql)=>new Proxy(statement,{get(target,key){if(key==='bind')return (...args)=>wrap(target.bind(...args),sql);if(key==='all')return async(...args)=>{if(${JSON.stringify(needle)}!==null&&sql.includes(${JSON.stringify(needle)}))await pause('all');return target.all(...args);};const v=Reflect.get(target,key);return typeof v==='function'?v.bind(target):v;}});
      const db=new Proxy(env.DB,{get(target,key){if(key==='prepare')return sql=>wrap(target.prepare(sql),sql);if(key==='batch')return async(...args)=>{await pause('batch');return target.batch(...args);};const v=Reflect.get(target,key);return typeof v==='function'?v.bind(target):v;}});
      const media=new Proxy(env.PRIVATE_MEDIA,{get(target,key){if(key==='get')return async(...args)=>{await pause('get');return target.get(...args);};const v=Reflect.get(target,key);return typeof v==='function'?v.bind(target):v;}});
      return worker.fetch(request,{...env,DB:db,PRIVATE_MEDIA:media},ctx);
    }};
  `},...await Promise.all(names.map(async name=>({type:'ESModule',path:fileURLToPath(new URL('src/'+name,root)),contents:await readFile(new URL('src/'+name,root),'utf8')})))];
  mf=new Miniflare((convertV4MiniflareOptions??(value=>value))({modules,modulesRoot:fileURLToPath(root),compatibilityDate:'2026-10-14',cf:false,
    d1Databases:{DB:randomUUID()},r2Buckets:{PRIVATE_MEDIA:randomUUID()},d1Persist:false,r2Persist:false,
    bindings:{APP_ENVIRONMENT:'test',AUTH_JWT_SECRET:'test-jwt-signing-key-unique-for-isolated-runtime-only-1234567890',AUTH_TOKEN_HASH_SECRET:'test-identity-hashing-key-unique-isolated-runtime-only-0987654321',AUTH_ISSUER:'collect-test',AUTH_AUDIENCE:'collect',AUTH_MEMBER_REGISTRATION_ENABLED:'true',
      OTP_DELIVERY_URL:'https://trusted-relay.example/otp',OTP_DELIVERY_TOKEN:'test-relay-token-123456789',TURNSTILE_REQUIRED:'true',TURNSTILE_SECRET:'test-turnstile-secret-123456',TURNSTILE_HOSTNAME:'collect.example',TURNSTILE_ACTION:'collect-login',
      ALLOWED_ORIGINS:'https://collect.example,https://admin.collect.example',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),DATA_KEY_ID:'security-test-v1'},
    serviceBindings:{TEST_GATE:async request=>{await gate(await request.json());return Response.json({ok:true});}},
    outboundService:async request=>{
      if(request.url==='https://challenges.cloudflare.com/turnstile/v0/siteverify')return Response.json({success:true,hostname:'collect.example',action:'collect-login',challenge_ts:new Date().toISOString()});
      assert.equal(request.url,'https://trusted-relay.example/otp');const body=await request.json();messages.push(body);return Response.json({accepted:true,request_id:body.request_id});
    }}));
  t.after(()=>mf.dispose());db=await mf.getD1Database('DB');
  for(const file of (await readdir(new URL('migrations/',root))).filter(n=>/^\d+.*\.sql$/.test(n)).sort()) {
    const sql=await readFile(new URL('migrations/'+file,root),'utf8');
    for(const statement of unstable_splitSqlQuery(sql))await db.prepare(statement).run();
  }
  const f={mf,db,messages,setGate(fn){gate=fn;},async close(){await mf.dispose();}};
  f.call=async(path,body={},headers={})=>{const method=path==='/v1/auth/user'?'GET':'POST';const response=await mf.dispatchFetch('https://api.collect.example'+path,{method,headers:{'Content-Type':'application/json','CF-Connecting-IP':'192.0.2.1',...headers},...(method==='POST'?{body:JSON.stringify(body)}:{})});return {status:response.status,body:await response.json(),headers:response.headers};};
  f.login=async(identity={phone:'+250788123456'})=>{
    const otp=await f.call('/v1/auth/otp',{...identity,captcha_token:randomUUID()});assert.equal(otp.status,202,JSON.stringify(otp.body));
    const delivered=messages.find(m=>m.request_id===otp.body.challenge_id);assert.ok(delivered);
    const result=await f.call('/v1/auth/verify',{...identity,challenge_id:otp.body.challenge_id,code:delivered.code,captcha_token:randomUUID()});assert.equal(result.status,200,JSON.stringify(result.body));return result.body;
  };return f;
}
async function group(f,s,{publicGroup=false,data={}}={}) {
  const id=randomUUID(),date=new Date().toISOString();
  await f.db.batch([f.db.prepare(`INSERT INTO collections(id,slug,creator_user_id,title,collection_type,receiver_momo_number,receiver_network,visibility_status,data_json,created_at,updated_at) VALUES(?,?,?,'Security group','ikimina','250788123456','mtn_momo',?,?,?,?)`).bind(id,randomUUID(),s.user.id,publicGroup?'public_approved':'private',JSON.stringify(data),date,date),f.db.prepare(`INSERT INTO memberships(id,collection_id,user_id,role,joined_at) VALUES(?,?,?,'owner',?)`).bind(randomUUID(),id,s.user.id,date)]);return id;
}
async function memberOf(f,g,s) {await f.db.prepare("INSERT INTO memberships(id,collection_id,user_id,role,joined_at) VALUES(?,?,?,'member',?)").bind(randomUUID(),g,s.user.id,new Date().toISOString()).run();}
async function operator(f,email='operator@example.com') {
  const a=await admin(f,{email}),date=new Date().toISOString();
  for(const permission of ['payments.write','payments.evidence.read','payments.read','users.read','audit.read','users.manage'])await f.db.prepare('INSERT OR IGNORE INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(a.id,permission,date).run();
  const s=await f.login(a.identity),setup=await setupMfa(f,s),verified=await f.call('/v1/auth/mfa/verify',{factor_id:setup.factor.id,challenge_id:setup.challenge.id,code:totp(setup.factor.totp.secret)},authorization(s));assert.equal(verified.status,200,JSON.stringify(verified.body));return verified.body;
}
async function evidence(f,s,g,extra={}) {const payload={collection_id:g,amount_minor:1000,request_id:randomUUID(),evidence:'controlled retained security test',...extra};const result=await f.call('/v1/evidence',payload,authorization(s));assert.equal(result.status,200,JSON.stringify(result.body));return result.body;}

test('a rotated invitation cannot admit a member after the hash lookup awaits',async t=>{
  const f=await paused(t,{path:'/v1/rpc/join_group_by_share_code'}),owner=await f.login(),other=await f.login({phone:'+250788123457'}),g=await group(f,owner);
  const rotated=await rpc(f,owner,'rotate_group_share_code_v2',{p_collection_id:g,p_request_id:randomUUID()});assert.equal(rotated.status,200);
  f.setGate(async()=>f.db.prepare('UPDATE collections SET share_code_hash=?,revision=revision+1 WHERE id=?').bind(createHash('sha256').update(randomUUID()).digest('hex'),g).run());
  const result=await rpc(f,other,'join_group_by_share_code',{p_group_code:rotated.body.share_code,p_request_id:randomUUID()});
  assert.ok([403,404,409].includes(result.status),`Invalidated invitation was admitted: ${JSON.stringify(result)}`);
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM memberships WHERE collection_id=? AND user_id=?').bind(g,other.user.id).first()).n,0);
});

test('ownership transfer cannot demote the owner when the recipient is removed during the request',async t=>{
  const f=await paused(t,{path:'/v1/rpc/transfer_group_ownership'}),owner=await f.login(),other=await f.login({phone:'+250788123457'}),g=await group(f,owner);await memberOf(f,g,other);
  f.setGate(async()=>f.db.prepare('UPDATE memberships SET active=0 WHERE collection_id=? AND user_id=?').bind(g,other.user.id).run());
  const result=await rpc(f,owner,'transfer_group_ownership',{p_collection_id:g,new_owner_public_id:other.user.user_metadata.public_id,p_request_id:randomUUID()});
  assert.ok([400,403,409].includes(result.status),`Transfer accepted an ineligible recipient: ${JSON.stringify(result)}`);
  assert.equal((await f.db.prepare("SELECT count(*) AS n FROM memberships WHERE collection_id=? AND user_id=? AND active=1 AND role='owner'").bind(g,owner.user.id).first()).n,1);
});

test('reconciliation approval revalidates recipient membership after a proposal is retained',async t=>{
  const f=await regular(t),member=await f.login(),g=await group(f,member),proposer=await operator(f),reviewer=await operator(f,'reviewer@example.com'),record=await evidence(f,proposer,g);
  const proposed=await rpc(f,proposer,'propose_payment_reconciliation_v2',{p_payment_id:record.id,p_member_id:member.user.id,p_request_id:randomUUID()});assert.equal(proposed.status,200,JSON.stringify(proposed.body));
  await f.db.prepare('UPDATE memberships SET active=0 WHERE collection_id=? AND user_id=?').bind(g,member.user.id).run();
  const approval=await rpc(f,reviewer,'approve_payment_reconciliation_v2',{p_reconciliation_id:proposed.body.id,p_request_id:randomUUID()});
  assert.ok([400,403,409].includes(approval.status),`Ineligible member was credited: ${JSON.stringify(approval)}`);
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM ledger_entries WHERE payment_id=?').bind(record.id).first()).n,0);
});

test('reconciliation proposal denies suspended recipients even while their membership remains active',async t=>{
  const f=await regular(t),member=await f.login(),g=await group(f,member),proposer=await operator(f),record=await evidence(f,proposer,g);
  await f.db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(member.user.id).run();
  const proposed=await rpc(f,proposer,'propose_payment_reconciliation_v2',{p_payment_id:record.id,p_member_id:member.user.id,p_request_id:randomUUID()});
  assert.ok([400,403,409].includes(proposed.status),`Suspended recipient was proposed: ${JSON.stringify(proposed)}`);
});

test('parallel evidence retries retain one payment and exactly one encrypted R2 object',async t=>{
  const f=await paused(t,{path:'/v1/evidence'}),member=await f.login(),g=await group(f,member),reviewer=await operator(f);
  let arrived=0,release;const barrier=new Promise(resolve=>release=resolve);
  f.setGate(async()=>{if(++arrived===2)release();await Promise.race([barrier,new Promise((_,reject)=>setTimeout(()=>reject(new Error('two-request barrier expired')),5000))]);});
  const payload={collection_id:g,amount_minor:1000,request_id:randomUUID(),evidence:'one retained receipt'};
  const results=await Promise.all([f.call('/v1/evidence',payload,authorization(reviewer)),f.call('/v1/evidence',payload,authorization(reviewer))]);
  assert.ok(results.every(r=>r.status===200),JSON.stringify(results));assert.equal(results[0].body.id,results[1].body.id);
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM payment_evidence').first()).n,1);
  const bucket=await f.mf.getR2Bucket('PRIVATE_MEDIA'),objects=await bucket.list({prefix:'evidence/'});
  assert.equal(objects.objects.length,1,'a losing idempotent request must reconcile or durably track its uploaded object');
});

test('evidence read rechecks its capability after an awaited R2 operation',async t=>{
  const f=await paused(t,{path:'/v1/evidence/',phase:'get'}),member=await f.login(),g=await group(f,member),reviewer=await operator(f),record=await evidence(f,reviewer,g);
  f.setGate(async()=>f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='payments.evidence.read'").bind(reviewer.user.id).run());
  const response=await f.mf.dispatchFetch('https://api.collect.example/v1/evidence/'+record.evidence_id,{headers:authorization(reviewer)});assert.equal(response.status,403);
});

test('public collection serialization cannot expose free-form private fields from stored product JSON',async t=>{
  const f=await regular(t),member=await f.login();await group(f,member,{publicGroup:true,data:{private_operator_note:'private recovery phrase',sms_secret:'private token',title:'display field'}});
  const response=await f.mf.dispatchFetch('https://api.collect.example/v1/query/public-collections');assert.equal(response.status,200);const body=await response.json();
  assert.ok(!JSON.stringify(body).includes('private recovery phrase'),'public DTO must enumerate public fields rather than spreading data_json');
  assert.ok(!JSON.stringify(body).includes('private token'));
});

test('reconciliation direct proposer self-approval stays denied and unsafe financial input is rejected',async t=>{
  const f=await regular(t),member=await f.login(),g=await group(f,member),proposer=await operator(f),record=await evidence(f,proposer,g);
  const proposal=await rpc(f,proposer,'propose_payment_reconciliation_v2',{p_payment_id:record.id,p_member_id:member.user.id,p_request_id:randomUUID()});assert.equal(proposal.status,200);
  const own=await rpc(f,proposer,'approve_payment_reconciliation_v2',{p_reconciliation_id:proposal.body.id,p_request_id:randomUUID()});assert.equal(own.status,403);assert.equal(own.body.code,'dual_review_required');
  await f.db.prepare("UPDATE users SET momo_number='250788123456' WHERE id=?").bind(member.user.id).run();
  for(const amount of [0,-1,1.5,Number.MAX_SAFE_INTEGER+1,'1000'])assert.equal((await rpc(f,member,'create_contribution_intent',{collection:g,p_expected_amount_rwf:amount,p_request_id:randomUUID()})).status,400);
});


test('successful reconciliation and reversal can read their exact retained receipt after acknowledgement loss',async t=>{
  const f=await regular(t),member=await f.login(),g=await group(f,member),proposer=await operator(f),reviewer=await operator(f,'reviewer@example.com'),record=await evidence(f,proposer,g);
  const proposal=await rpc(f,proposer,'propose_payment_reconciliation_v2',{p_payment_id:record.id,p_member_id:member.user.id,p_request_id:randomUUID()});assert.equal(proposal.status,200);
  const command={p_reconciliation_id:proposal.body.id,p_request_id:randomUUID()},approved=await rpc(f,reviewer,'approve_payment_reconciliation_v2',command);assert.equal(approved.status,200,JSON.stringify(approved.body));
  const retry=await rpc(f,reviewer,'approve_payment_reconciliation_v2',command);assert.equal(retry.status,200,'an exact retry must resolve the retained transaction, not claim it failed');assert.deepEqual(retry.body,approved.body);
  assert.equal((await f.db.prepare("SELECT count(*) AS n FROM ledger_entries WHERE kind='contribution'").first()).n,1);
  const reversal={p_payment_id:record.id,p_expected_revision:2,p_request_id:randomUUID(),p_reason_code:'operator_review'},reversed=await rpc(f,reviewer,'admin_reverse_payment_v1',reversal);assert.equal(reversed.status,200,JSON.stringify(reversed.body));
  const again=await rpc(f,reviewer,'admin_reverse_payment_v1',reversal);assert.equal(again.status,200,'a committed reversal remains discoverable for the same exact request');assert.deepEqual(again.body,reversed.body);
  assert.equal((await f.db.prepare('SELECT sum(amount_minor) AS n FROM ledger_entries').first()).n,0);
});

test('a reused payment-intent request ID cannot bypass conflict checking through another pending intent',async t=>{
  const f=await regular(t),member=await f.login(),g=await group(f,member);await f.db.prepare("UPDATE users SET momo_number='250788123456' WHERE id=?").bind(member.user.id).run();
  const originalId=randomUUID(),one=await rpc(f,member,'create_contribution_intent',{collection:g,p_expected_amount_rwf:1000,p_request_id:originalId});assert.equal(one.status,200);
  const two=await rpc(f,member,'create_contribution_intent',{collection:g,p_expected_amount_rwf:2000,p_request_id:randomUUID()});assert.equal(two.status,200);
  const conflict=await rpc(f,member,'create_contribution_intent',{collection:g,p_expected_amount_rwf:2000,p_request_id:originalId});assert.equal(conflict.status,409,'an existing pending amount must not override an unrelated retained request ID');
});

test('receipt fallback still denies a permission revoked before the losing atomic write',async t=>{
  const f=await paused(t,{path:'/v1/evidence',hint:'hold'}),member=await f.login(),g=await group(f,member),reviewer=await operator(f);
  let arrived,release;const reached=new Promise(resolve=>arrived=resolve),hold=new Promise(resolve=>release=resolve);
  f.setGate(async()=>{arrived();await hold;});
  const payload={collection_id:g,amount_minor:1000,request_id:randomUUID(),evidence:'retained exact receipt'};
  const delayed=f.call('/v1/evidence',payload,{...authorization(reviewer),'X-Test-Gate':'hold'});
  await Promise.race([reached,new Promise((_,reject)=>setTimeout(()=>reject(new Error('owned test gate was not reached')),5000))]);
  try {
    const committed=await f.call('/v1/evidence',payload,authorization(reviewer));assert.equal(committed.status,200,JSON.stringify(committed.body));
    await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='payments.write'").bind(reviewer.user.id).run();
  }finally{release();}
  const result=await delayed;assert.equal(result.status,403,'a committed receipt from another caller does not restore revoked current authority');
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM payment_evidence').first()).n,1);
});


test('an exact reversal request resolves its retained receipt after the payment revision has advanced',async t=>{
  const f=await regular(t),member=await f.login(),g=await group(f,member),reviewer=await operator(f),record=await evidence(f,reviewer,g),date=new Date().toISOString();
  await f.db.batch([f.db.prepare("UPDATE payments SET member_id=?,status='reconciled' WHERE id=?").bind(member.user.id,record.id),
    f.db.prepare("INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,?,'contribution',?,?,?,?)")
      .bind(randomUUID(),record.id,g,member.user.id,1000,record.evidence_id,reviewer.user.id,randomUUID(),date)]);
  const command={p_payment_id:record.id,p_expected_revision:1,p_request_id:randomUUID(),p_reason_code:'operator_review'};
  const first=await rpc(f,reviewer,'admin_reverse_payment_v1',command);assert.equal(first.status,200,JSON.stringify(first.body));
  const replay=await rpc(f,reviewer,'admin_reverse_payment_v1',command);assert.equal(replay.status,200,'the same committed request must read back its existing reversal');assert.deepEqual(replay.body,first.body);
  assert.equal((await f.db.prepare("SELECT count(*) AS n FROM ledger_entries WHERE kind='reversal'").first()).n,1);
});

test('group roster fails closed when complete ledger totals exceed exact financial integer precision',async t=>{
  const f=await regular(t),member=await f.login(),g=await group(f,member),reviewer=await operator(f),date=new Date().toISOString(),amount=Number.MAX_SAFE_INTEGER-1;
  for(let i=0;i<2;i++){
    const record=await evidence(f,reviewer,g,{amount_minor:amount});
    await f.db.batch([f.db.prepare("UPDATE payments SET member_id=?,status='reconciled' WHERE id=?").bind(member.user.id,record.id),
      f.db.prepare("INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,?,'contribution',?,?,?,?)")
        .bind(randomUUID(),record.id,g,member.user.id,amount,record.evidence_id,reviewer.user.id,randomUUID(),date)]);
  }
  const balance=await rpc(f,member,'list_current_member_collection_balances');assert.equal(balance.status,503);
  const roster=await rpc(f,member,'list_current_member_group_roster',{p_collection_id:g});assert.equal(roster.status,503,'roster must not emit an inexact aggregate even when each contribution is individually safe');
});

test('roster read does not disclose owner-only totals after membership is revoked during the awaited query',async t=>{
  const f=await paused(t,{path:'/v1/rpc/list_current_member_group_roster',phase:'all',needle:'coalesce(sum(l.amount_minor)'}),owner=await f.login(),member=await f.login({phone:'+250788123457'}),g=await group(f,owner);await memberOf(f,g,member);
  f.setGate(async()=>f.db.prepare('UPDATE memberships SET active=0 WHERE collection_id=? AND user_id=?').bind(g,owner.user.id).run());
  const result=await rpc(f,owner,'list_current_member_group_roster',{p_collection_id:g});assert.equal(result.status,403,'a prior owner lookup cannot authorize a later roster read after revocation');
});
