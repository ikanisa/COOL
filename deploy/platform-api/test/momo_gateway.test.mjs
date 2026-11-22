import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fixture,hash} from './admin_sms_support/fixture.mjs';
import {processMomoJob} from '../src/momo_pipeline.js';
import {momoGatewayRoute} from '../src/momo_gateway.js';
const synthetic=JSON.parse(await readFile(new URL('fixtures/momo-synthetic.json',import.meta.url),'utf8'));
const date=()=>new Date().toISOString();
async function operator(f,options={}){const account=await f.seedAccount(options);return {...await f.stepUp(await f.login(account)),account};}
const action=(f,cookie,path,data,key=randomUUID())=>f.call('/api/admin/momo/'+path,{cookie,data,headers:{'Idempotency-Key':key}});
async function setup(t){
 const f=await fixture(t,{MOMO_PROCESSING_PAUSED:'true'}, {migrationsThrough:15}),owner=await operator(f);
 const account=await action(f,owner.cookie,'accounts',{provider:'mtn_momo',public_code:'+250788123456',recipient_name:'Synthetic receiving account',reason:'Controlled test receiving account'});assert.equal(account.status,200,JSON.stringify(account));
 const binding=await action(f,owner.cookie,'bindings',{receiving_account_id:account.body.id,reason:'Pair controlled incoming test phone'});assert.equal(binding.status,200,JSON.stringify(binding));
 const installation=randomUUID(),pairBody={pairing_code:binding.body.pairing_code,installation_id:installation};
 const pair=await f.call('/v1/momo/gateway/pair',{origin:null,data:pairBody});assert.equal(pair.status,200,JSON.stringify(pair));
 const headers={Authorization:'Bearer '+pair.body.gateway_token};
 const capture=extra=>({client_envelope_id:randomUUID(),raw_sender:synthetic.sender,raw_body:synthetic.body,gateway_binding_id:pair.body.binding.id,
 gateway_binding_version:pair.body.binding.version,service_centre_at:date(),captured_at:date(),inbox_received_at:null,source_mode:'live',subscription_id:null,complete:true,...extra});
 const ingest=body=>f.call('/v1/momo/gateway/ingest',{origin:null,data:body,headers});
 return {f,owner,account,binding,installation,pairBody,pair,headers,capture,ingest};
}
async function accepted(s,extra={}){const body=s.capture(extra),reply=await s.ingest(body);assert.equal(reply.status,200,JSON.stringify(reply));
 const profile=await action(s.f,s.owner.cookie,`accounts/${s.account.body.id}/profile`,{profile:synthetic.profile,profile_version:'synthetic.v1',reason:'Synthetic provider fixtures only, no production approval'});assert.equal(profile.status,200,JSON.stringify(profile));
 const env={DB:s.f.db,PRIVATE_MEDIA:await s.f.mf.getR2Bucket('PRIVATE_MEDIA'),DATA_KEY_ID:'admin-test-v1',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),AI:{run:async()=>({response:structuredClone(synthetic.output)})}};
 const result=await processMomoJob(env,reply.body.receipt.raw_sms_id);assert.equal(result.state,'completed');
 return {body,reply,tx:await s.f.db.prepare('SELECT * FROM momo_transactions WHERE id=?').bind(result.transaction_id).first()};
}

test('single-use pairing recovers the same scoped token and rejects another installation',async t=>{
 const s=await setup(t),replay=await s.f.call('/v1/momo/gateway/pair',{origin:null,data:s.pairBody});assert.equal(replay.status,200);assert.deepEqual(replay.body,s.pair.body);
 assert.equal((await s.f.call('/v1/momo/gateway/pair',{origin:null,data:{...s.pairBody,installation_id:randomUUID()}})).status,409);
 assert.equal((await s.f.call('/v1/query/notification-events',{origin:null,headers:s.headers,method:'GET'})).status,401,'gateway token has no member authority');
 const credentials=(await s.f.db.prepare('SELECT * FROM momo_gateway_credentials').first());assert.ok(!credentials.token_ciphertext.includes(s.pair.body.gateway_token));
 await s.f.db.prepare("UPDATE admin_users SET status='revoked' WHERE id=?").bind(s.owner.account.adminId).run();
 assert.equal((await s.f.call('/v1/momo/gateway/status',{origin:null,method:'GET',headers:s.headers})).status,401);
});
test('first pairing requires a current active issuing administrator without consuming a denied code',async t=>{
 const f=await fixture(t,{MOMO_PROCESSING_PAUSED:'true'}, {migrationsThrough:15}),owner=await operator(f);
 const account=await action(f,owner.cookie,'accounts',{provider:'mtn_momo',public_code:'+250788123456',recipient_name:'Synthetic receiving account',reason:'Controlled first-pair authority regression'});assert.equal(account.status,200,JSON.stringify(account));
 const binding=await action(f,owner.cookie,'bindings',{receiving_account_id:account.body.id,reason:'Issue controlled unclaimed pairing code'});assert.equal(binding.status,200,JSON.stringify(binding));
 const data={pairing_code:binding.body.pairing_code,installation_id:randomUUID()};
 await f.db.prepare("UPDATE admin_users SET status='revoked' WHERE id=?").bind(owner.account.adminId).run();
 const denied=await f.call('/v1/momo/gateway/pair',{origin:null,data});assert.equal(denied.status,401,JSON.stringify(denied));assert.equal(denied.body.code,'pairing_unavailable');assert.equal(denied.body.gateway_token,undefined);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM momo_gateway_credentials').first()).n,0);
 assert.equal((await f.db.prepare('SELECT claimed_installation_id FROM momo_gateway_pairings WHERE binding_id=?').bind(binding.body.binding_id).first()).claimed_installation_id,null);
 await f.db.prepare("UPDATE admin_users SET status='active' WHERE id=?").bind(owner.account.adminId).run();
 // Revoke after the initial read, immediately before the real committing D1 batch.
 const raceEnv={DATA_KEY_ID:'admin-test-v1',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64'),DB:{prepare:q=>f.db.prepare(q),batch:async statements=>{
  await f.db.prepare("UPDATE admin_users SET status='revoked' WHERE id=?").bind(owner.account.adminId).run();return f.db.batch(statements);
 }}};
 await assert.rejects(momoGatewayRoute(new Request('https://api.collect.example/v1/momo/gateway/pair',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}),raceEnv),error=>error.status===409&&error.code==='pairing_changed');
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM momo_gateway_credentials').first()).n,0);
 assert.equal((await f.db.prepare('SELECT claimed_installation_id FROM momo_gateway_pairings WHERE binding_id=?').bind(binding.body.binding_id).first()).claimed_installation_id,null);
 await f.db.prepare("UPDATE admin_users SET status='active' WHERE id=?").bind(owner.account.adminId).run();
 const paired=await f.call('/v1/momo/gateway/pair',{origin:null,data});assert.equal(paired.status,200,JSON.stringify(paired));assert.ok(paired.body.gateway_token);
});
test('native upload atomically retains exact Unicode source and one processing obligation',async t=>{
 const s=await setup(t),body=s.capture({raw_body:'Réception\n  原文  (********007)',captured_at:'2026-10-18T08:15:00.123456789Z'}),a=await s.ingest(body),b=await s.ingest(body);
 assert.equal(a.status,200,JSON.stringify(a));assert.deepEqual(a.body,b.body);assert.equal(a.body.receipt.body_sha256,hash(body.raw_body));
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,1);assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_processing_jobs').first()).n,1);
 assert.equal((await s.ingest({...body,raw_body:body.raw_body+'changed'})).status,409);
 assert.equal((await s.ingest(s.capture({gateway_binding_id:randomUUID()}))).status,403);
 assert.equal((await s.ingest(s.capture({captured_at:'2026-02-30T00:00:00Z'}))).status,400);
 assert.equal((await s.ingest(s.capture({source_mode:'catch_up',inbox_received_at:'2020-01-01T00:00:00Z'}))).status,409);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,0);
});
test('revocation immediately removes upload and health authority while retaining pending evidence',async t=>{
 const s=await setup(t),body=s.capture();assert.equal((await s.ingest(body)).status,200);
 assert.equal((await action(s.f,s.owner.cookie,`bindings/${s.binding.body.binding_id}/revoke`,{reason:'Retire controlled incoming installation'})).status,200);
 assert.equal((await s.ingest(body)).status,401);
 assert.equal((await s.f.call('/v1/momo/gateway/status',{origin:null,method:'GET',headers:s.headers})).status,401);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM sms_receipts').first()).n,1);
});
test('received unallocated payment is visible before destination and does not create money',async t=>{
 const s=await setup(t),a=await accepted(s),page=await s.f.call('/api/admin/momo/transactions',{cookie:s.owner.cookie,method:'GET'});
 assert.equal(page.status,200,JSON.stringify(page));assert.equal(page.body.rows[0].provider_transaction_id,'001234567890');assert.equal(page.body.rows[0].payer_last3,'007');assert.equal(page.body.rows[0].group_id,null);
 assert.equal(page.body.rows[0].status,'needs_allocation');assert.deepEqual(page.body.totals,{received_minor:5000,credited_minor:0,unallocated_minor:5000});
 const updates=await s.f.call('/api/admin/sync?areas=payments&limit=100',{cookie:s.owner.cookie,method:'GET'});assert.equal(updates.status,200);assert.ok(updates.body.events.length>0);assert.ok(updates.body.events.every(e=>Object.keys(e).sort().join(',')==='area,id'));
 const staff=await operator(s.f,{role:'staff',email:'staff-fixture@example.test'});
 assert.equal((await action(s.f,staff.cookie,'bindings',{receiving_account_id:s.account.body.id,reason:'Staff must not enroll incoming gateway'})).status,403);
 assert.equal((await s.f.call(`/api/admin/momo/sources/${a.reply.body.receipt.raw_sms_id}/content`,{cookie:staff.cookie,method:'GET',headers:{'X-Collect-Review-Reason':'Controlled permission regression'}})).status,403);
});
test('allocation links once; existing independent review posts once with committed snapshots and receipt',async t=>{
 const s=await setup(t),a=await accepted(s),member=await s.f.seedMember(),group=await s.f.operation('groups',s.owner.cookie,{title:'Gateway savings',slug:'gateway-savings',collection_type:'ikimina',owner_user_id:member.id,
 receiver:{label:'Group receiver label',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Create controlled destination group'});assert.equal(group.status,200,JSON.stringify(group));
 const groupId=group.body.resource_id,native=await s.f.nativeLogin(member.phone);
 const issued=await s.f.call('/v1/rpc/create_contribution_intent',{origin:'https://collect.example',headers:{Authorization:'Bearer '+native.access_token},data:{collection:groupId,p_expected_amount_rwf:5000,p_request_id:randomUUID()}});
 assert.equal(issued.status,200,JSON.stringify(issued));assert.equal(issued.body.status,'pending');assert.ok(Date.parse(issued.body.expires_at)>Date.parse(issued.body.created_at));
 const intentId=issued.body.id;
 const body={group_id:groupId,member_id:member.id,intent_id:intentId,expected_version:1,reason:'Reviewed third-party payer evidence for this beneficiary'},key=randomUUID();
 const assigned=await action(s.f,s.owner.cookie,`transactions/${a.tx.id}/assign`,body,key);assert.equal(assigned.status,200,JSON.stringify(assigned));
 assert.deepEqual((await action(s.f,s.owner.cookie,`transactions/${a.tx.id}/assign`,body,key)).body,assigned.body);
 assert.equal((await action(s.f,s.owner.cookie,`transactions/${a.tx.id}/assign`,body)).status,409);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,0);
 const staff=await operator(s.f,{role:'staff',email:'proposer-fixture@example.test'}),user=await s.f.db.prepare('SELECT * FROM users WHERE id=?').bind(member.id).first();
 const proposed=await s.f.call(`/api/admin/reconciliations/${assigned.body.payment_id}/proposals`,{cookie:staff.cookie,headers:{'Idempotency-Key':randomUUID()},data:{member_user_id:member.id,amount_rwf:5000,expected_transaction_version:1,expected_member_version:user.revision,expected_membership_version:1,
 expected_payment_identity:{display_name:user.full_name,momo_provider:user.momo_provider,momo_number:user.momo_number,momo_pay_code:user.momo_pay_code},reason:'Reviewed independently attributed payer and member'}});assert.equal(proposed.status,200,JSON.stringify(proposed));
 const reviewKey=randomUUID(),review=()=>s.f.call(`/api/admin/reconciliations/proposals/${proposed.body.resource_id}/reviews`,{cookie:s.owner.cookie,headers:{'Idempotency-Key':reviewKey},data:{outcome:'approved',expected_proposal_version:1,expected_transaction_version:1,reason:'Independent review confirms the retained destination'}});
 const approved=await review();assert.equal(approved.status,200,JSON.stringify(approved));assert.deepEqual((await review()).body,approved.body);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,1);
 assert.equal((await s.f.db.prepare('SELECT member_balance_after_minor FROM contribution_posting_snapshots').first()).member_balance_after_minor,5000);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM notification_events').first()).n,1);
 const page=await s.f.call('/api/admin/momo/transactions',{method:'GET',cookie:s.owner.cookie});assert.equal(page.body.rows[0].status,'credited');assert.equal(page.body.totals.credited_minor,5000);
 const duplicate=await s.f.operation('transactions',s.owner.cookie,{group_id:groupId,amount_rwf:5000,provider_reference:'001234567890',observed_at:date(),evidence:'Controlled duplicate import of the same known provider transaction',reason:'An independent import must not duplicate a canonical receipt'});
 assert.equal(duplicate.status,409,JSON.stringify(duplicate));assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM payments').first()).n,1);
 await s.f.db.prepare("UPDATE momo_transactions SET has_conflict=1,allocation_state='needs_review',version=version+1 WHERE id=?").bind(a.tx.id).run();
 const attention=await s.f.call('/api/admin/momo/transactions?status=needs_attention',{method:'GET',cookie:s.owner.cookie});
 assert.equal(attention.body.rows.length,1);assert.equal(attention.body.rows[0].status,'credited');assert.equal(attention.body.rows[0].has_conflict,1);assert.equal(attention.body.totals.credited_minor,5000);
 const confirmed=await s.f.call('/v1/rpc/list_current_member_recent_intents',{origin:'https://collect.example',headers:{Authorization:'Bearer '+native.access_token},data:{p_intent_id:intentId}});
 assert.equal(confirmed.status,200,JSON.stringify(confirmed));assert.equal(confirmed.body.items[0].confirmation_status,'credited');
 assert.equal(confirmed.body.items[0].provider_transaction_reference,'001234567890');assert.equal(confirmed.body.items[0].balance_after_contribution_rwf,5000);
 assert.equal(confirmed.body.items[0].provider_transaction_at,a.tx.transaction_at);assert.notEqual(confirmed.body.items[0].provider_transaction_at,confirmed.body.items[0].posted_at,'Provider transaction time must remain distinct from financial posting time');
 const memberUpdates=await s.f.call('/v1/sync?areas=payment_intents,payments,ledger',{method:'GET',origin:'https://collect.example',headers:{Authorization:'Bearer '+native.access_token}});assert.equal(memberUpdates.status,200);assert.ok(memberUpdates.body.events.some(e=>e.area==='payment_intents'));
 const other=await s.f.nativeLogin('+250788654321'),hidden=await s.f.call('/v1/rpc/list_current_member_recent_intents',{origin:'https://collect.example',headers:{Authorization:'Bearer '+other.access_token},data:{p_intent_id:intentId}});
 assert.equal(hidden.status,200);assert.equal(hidden.body.items.length,0,'a claimed intent ID cannot reveal another member payment');
});

test('a manual import racing allocation prevents a second financial record',async t=>{
 const s=await setup(t),a=await accepted(s),member=await s.f.seedMember(),group=await s.f.operation('groups',s.owner.cookie,{title:'Overlap savings',slug:'overlap-savings',collection_type:'ikimina',owner_user_id:member.id,
 receiver:{label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Create controlled historical-overlap group'});assert.equal(group.status,200);
 s.f.setGate(async()=>{const evidenceId=randomUUID();await s.f.db.batch([
  s.f.db.prepare(`INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,receiver_momo_number,amount_minor,observed_at,created_at,receiver_network,receiver_display_label) VALUES(?,?,?,?,?,1,'text/plain','operator_recorded','001234567890',?,5000,?,?,'mtn_momo','Recorded receiver')`).bind(evidenceId,group.body.resource_id,s.owner.account.userId,'synthetic-overlap/'+evidenceId,'c'.repeat(64),member.phone,date(),date()),
  s.f.db.prepare(`INSERT INTO payments(id,collection_id,evidence_id,amount_minor,status,created_at) VALUES(?,?,?,5000,'recorded',?)`).bind(randomUUID(),group.body.resource_id,evidenceId,date())]);});
 const assigned=await s.f.call(`/api/admin/momo/transactions/${a.tx.id}/assign`,{cookie:s.owner.cookie,headers:{'Idempotency-Key':randomUUID(),'X-Test-Pause':'before_commit'},data:{group_id:group.body.resource_id,member_id:member.id,expected_version:1,reason:'Controlled overlapping receipt allocation race'}});
 assert.equal(assigned.status,409,JSON.stringify(assigned));assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM payments').first()).n,1);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_financial_links').first()).n,0);assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,0);
});

test('historical inventory uses a resumable cursor and reviewed source mapping without reposting',async t=>{
 const s=await setup(t),body=s.capture(),upload=await s.ingest(body);assert.equal(upload.status,200);
 const rawId=upload.body.receipt.raw_sms_id;await s.f.db.prepare('DELETE FROM momo_processing_jobs WHERE raw_sms_id=?').bind(rawId).run();
 const inventory=await action(s.f,s.owner.cookie,'sources/backfill',{reason:'Inventory previously retained raw sources without processing work',limit:1});assert.equal(inventory.status,200,JSON.stringify(inventory));assert.equal(inventory.body.inventoried,1);assert.equal(inventory.body.financial_effects,0);
 const wrong=await action(s.f,s.owner.cookie,`sources/${rawId}/resolve`,{receiving_account_id:randomUUID(),evidence_reference:'Controlled historical binding evidence',reason:'This unrelated account must never replace the receiving source'});assert.equal(wrong.status,409,JSON.stringify(wrong));
 const resolved=await action(s.f,s.owner.cookie,`sources/${rawId}/resolve`,{receiving_account_id:s.account.body.id,evidence_reference:'Controlled source archive and receiving account history',reason:'Historical source reviewed against the preserved receiving evidence'});assert.equal(resolved.status,200,JSON.stringify(resolved));
 const job=await s.f.db.prepare('SELECT * FROM momo_processing_jobs WHERE raw_sms_id=?').bind(rawId).first();assert.equal(job.mode,'historical');assert.equal(job.state,'pending');assert.equal(job.binding_id,null);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM momo_source_resolutions').first()).n,1);
 assert.equal((await action(s.f,s.owner.cookie,`sources/${rawId}/resolve`,{receiving_account_id:s.account.body.id,evidence_reference:'Cannot rewrite source history',reason:'A second mapping must not change an immutable source'})).status,409);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,0);
});
