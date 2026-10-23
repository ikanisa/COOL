import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {fixture,authorization,admin,totp,setupMfa,claims} from './support/auth_fixture.mjs';
const modules=['groups.js','payments.js','evidence.js','notifications.js','admin.js','mutations.js','privacy.js'];
async function open(t){const f=await fixture({APP_ENVIRONMENT:'test'},{entrypoint:'index.js',extraModules:modules});t.after(()=>f.close());return f;}
const rpc=(f,s,name,body={})=>f.call('/v1/rpc/'+name,body,authorization(s));
async function group(f,owner){const g=randomUUID(),date=new Date().toISOString();await f.db.batch([f.db.prepare(`INSERT INTO collections(id,slug,creator_user_id,title,collection_type,receiver_momo_number,receiver_network,created_at,updated_at) VALUES(?,?,?,'Test group','ikimina','250788123456','mtn_momo',?,?)`).bind(g,randomUUID(),owner.user.id,date,date),f.db.prepare(`INSERT INTO memberships(id,collection_id,user_id,role,joined_at) VALUES(?,?,?,'owner',?)`).bind(randomUUID(),g,owner.user.id,date)]);return g;}
async function mfaAdmin(f){const a=await admin(f);for(const permission of ['payments.write','payments.evidence.read','collections.read','users.read','overview.read','users.manage','notifications.read'])await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(a.id,permission,new Date().toISOString()).run();const s=await f.login(a.identity),setup=await setupMfa(f,s),verified=await f.call('/v1/auth/mfa/verify',{factor_id:setup.factor.id,challenge_id:setup.challenge.id,code:totp(setup.factor.totp.secret)},authorization(s));assert.equal(verified.status,200,JSON.stringify(verified.body));return verified.body;}

test('Worker public/private boundaries, CORS and method denials execute actual D1',async t=>{
 const f=await open(t);
 let r=await f.mf.dispatchFetch('https://api.collect.example/health');assert.equal(r.status,200);assert.equal((await r.json()).database,'available');
 r=await f.mf.dispatchFetch('https://api.collect.example/health',{headers:{Origin:'https://evil.example'}});assert.equal(r.status,403);
 assert.equal((await f.call('/v1/rpc/list_current_user_collections')).status,401);
 r=await f.mf.dispatchFetch('https://api.collect.example/v1/query/public-collections');assert.deepEqual(await r.json(),[]);
 r=await f.mf.dispatchFetch('https://api.collect.example/v1/rpc/get_current_member_profile',{method:'POST',headers:{'Content-Type':'application/json'},body:'null'});assert.equal(r.status,401);
});

test('Groups, invitation rotation and account isolation preserve ownership after real HTTP',async t=>{
 const f=await open(t),owner=await f.login({phone:'+250788123456'}),other=await f.login({phone:'+250789123456'}),g=await group(f,owner);
 assert.equal((await rpc(f,owner,'list_current_user_collections')).body.length,1);assert.deepEqual((await rpc(f,other,'list_current_user_collections')).body,[]);
 assert.equal((await rpc(f,other,'get_group_share_code',{p_collection_id:g})).status,403);
 const requestId=randomUUID(),body={p_collection_id:g,p_request_id:requestId},rotated=await rpc(f,owner,'rotate_group_share_code_v2',body);assert.equal(rotated.status,200,JSON.stringify(rotated.body));
 assert.deepEqual((await rpc(f,owner,'rotate_group_share_code_v2',body)).body,rotated.body);
 assert.equal((await rpc(f,other,'join_group_by_share_code',{p_group_code:rotated.body.share_code})).body,g);
 assert.equal((await rpc(f,other,'list_current_user_collections')).body[0].is_member,true);
 await f.db.prepare(`UPDATE memberships SET role='member' WHERE collection_id=? AND user_id=?`).bind(g,owner.user.id).run();
 assert.equal((await rpc(f,owner,'rotate_group_share_code_v2',body)).status,403);
 const revoked=await f.call('/v1/auth/logout',{},authorization(other));assert.equal(revoked.status,200);
 assert.equal((await rpc(f,other,'list_current_user_collections')).status,401);
});

test('Payment intents are actor/session bound and never manufacture ledger confirmation',async t=>{
 const f=await open(t),s=await f.login({phone:'+250788123456'}),g=await group(f,s);
 await f.db.prepare(`UPDATE users SET momo_number='250788123456' WHERE id=?`).bind(s.user.id).run();
 const body={collection:g,p_expected_amount_rwf:5000};const intent=await rpc(f,s,'create_contribution_intent',body);assert.equal(intent.status,200,JSON.stringify(intent.body));assert.equal(intent.body.status,'pending');
 assert.deepEqual((await rpc(f,s,'create_contribution_intent',body)).body,intent.body);
 assert.equal((await f.db.prepare('SELECT count(*) n FROM ledger_entries').first()).n,0);
 const list=await rpc(f,s,'list_current_member_recent_intents');assert.equal(list.body.pending_count,1);assert.equal(list.body.items[0].id,intent.body.id);
 const balance=await rpc(f,s,'list_current_member_collection_balances');assert.equal(balance.body[0].balances[0].amount_raised_minor,0);
 const history=await rpc(f,s,'list_current_member_history_page');assert.equal(history.body.total_count,0);assert.match(history.body.revision,/^[a-f0-9]{32}$/);
});

test('Concurrent preference writes atomically reject one stale revision',async t=>{
 const f=await open(t),s=await f.login({phone:'+250788123456'});
 const preferences={push_enabled:false,payment_updates:true,group_updates:false};const body={p_preferences:preferences,p_expected_revision:1};
 const results=await Promise.all([rpc(f,s,'set_notification_preferences_v2',body),rpc(f,s,'set_notification_preferences_v2',body)]);
 assert.deepEqual(results.map(r=>r.status).sort(),[200,409],JSON.stringify(results));
 assert.equal((await rpc(f,s,'get_notification_preferences_v2')).body.revision,2);
});

test('Recorded payment evidence is encrypted and retained through a single atomic reversal',async t=>{
 const f=await open(t),owner=await f.login({phone:'+250788123456'}),g=await group(f,owner),operator=await mfaAdmin(f);
 const payload={collection_id:g,amount_minor:2500,request_id:randomUUID(),evidence:'controlled financial receipt test'};
 const result=await f.call('/v1/evidence',payload,authorization(operator));assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.status,'recorded');assert.equal(result.body.evidence_level,'operator_recorded');
 const record=await f.db.prepare('SELECT * FROM payment_evidence WHERE id=?').bind(result.body.evidence_id).first();const bucket=await f.mf.getR2Bucket('PRIVATE_MEDIA');const object=await bucket.get(record.object_key);assert.ok(object);assert.ok(!(await object.text()).includes(payload.evidence));
 const read=await f.mf.dispatchFetch('https://api.collect.example/v1/evidence/'+record.id,{headers:authorization(operator)});assert.equal(read.status,200);assert.equal(await read.text(),payload.evidence);
 const denied=await f.mf.dispatchFetch('https://api.collect.example/v1/evidence/'+record.id,{headers:authorization(owner)});assert.equal(denied.status,403);
 await f.db.batch([f.db.prepare(`UPDATE payments SET member_id=?,status='reconciled' WHERE id=?`).bind(owner.user.id,result.body.id),f.db.prepare(`INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,?,'contribution',?,?,?,?)`).bind(randomUUID(),result.body.id,g,owner.user.id,2500,record.id,operator.user.id,randomUUID(),new Date().toISOString())]);
 const reversal={p_payment_id:result.body.id,p_expected_revision:1,p_request_id:randomUUID(),p_reason_code:'operator_review'};
 const reversed=await rpc(f,operator,'admin_reverse_payment_v1',reversal);assert.equal(reversed.status,200,JSON.stringify(reversed.body));assert.equal(reversed.body.status,'reversed');
 assert.equal((await f.db.prepare('SELECT sum(amount_minor) n FROM ledger_entries').first()).n,0);
 assert.equal((await f.db.prepare('SELECT count(*) n FROM payment_evidence').first()).n,1);
 assert.equal((await rpc(f,operator,'admin_reverse_payment_v1',{...reversal,p_request_id:randomUUID(),p_expected_revision:2})).status,409);
 await assert.rejects(f.db.prepare('DELETE FROM ledger_entries').run(),/immutable_ledger/);
 await assert.rejects(f.db.prepare('DELETE FROM payment_evidence').run(),/retain_financial_evidence/);
});

test('Member token cannot consume newly granted Admin authority and invalidations reveal no data',async t=>{
 const f=await open(t),s=await f.login({phone:'+250788123456'});await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(s.user.id,'overview.read',new Date().toISOString()).run();
 assert.equal((await rpc(f,s,'admin_overview')).status,403);assert.equal((await rpc(f,s,'admin_current_user')).body,null);
 const response=await f.mf.dispatchFetch('https://api.collect.example/v1/sync?cursor=0&limit=100&areas=profiles,collections',{headers:authorization(s)});assert.equal(response.status,200);const body=await response.json();assert.match(body.cursor,/^\d+$/);assert.ok(body.events.every(e=>Object.keys(e).sort().join(',')==='area,id'));
});
