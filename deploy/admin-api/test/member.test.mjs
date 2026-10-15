import test,{before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {Miniflare,convertV4MiniflareOptions} from 'miniflare';
import {handleMember,MemberError} from '../src/member.mjs';
const origin='https://app-preview.collect.ikanisa.com',root=fileURLToPath(new URL('..',import.meta.url));
let runtime,db,env,requestNumber=0;const emails=[];const run=(sql,...p)=>db.prepare(sql).bind(...p).run();
async function call(path,data,auth=null,headers={}){const r=new Request(origin+'/api/member/'+path,{method:data==null?'GET':'POST',headers:{'X-Collect-Client':'native','CF-Connecting-IP':`2001:db8::${(++requestNumber).toString(16)}`,...(data==null?{}:{'Content-Type':'application/json'}),...(auth?{Authorization:'Bearer '+auth.accessToken}:{}),...headers},...(data==null?{}:{body:JSON.stringify(data)})});try{const result=await handleMember(r,env,{});return{status:result.status,body:await result.json(),headers:result.headers};}catch(e){if(e instanceof MemberError)return{status:e.status,body:{error:{code:e.code}}};throw e;}}
async function login(email){const r=await call('auth/request-code',{email});assert.equal(r.status,200);const code=/code is (\d{6})/.exec(emails.at(-1).text)[1];const v=await call('auth/verify-code',{email,challengeId:r.body.challengeId,code});assert.equal(v.status,200);return v.body;}
const cmd=(a,name,params={})=>call('command',{name,params},a);
before(async()=>{runtime=new Miniflare(convertV4MiniflareOptions({modules:true,script:'export default {fetch(){return new Response("ok")}}',compatibilityDate:'2026-10-04',d1Databases:['ADMIN_DB'],r2Buckets:['MEMBER_MEDIA']}));db=await runtime.getD1Database('ADMIN_DB');
 for(const name of ['0001_admin_accounts.sql','0002_collect_core.sql','0003_posted_verification_guard.sql','0004_operating_actions.sql','0005_member_cloudflare.sql','0006_gateway_cloudflare.sql','0007_email_only_dispatch.sql','0008_admin_people.sql']){const sql=await readFile(new URL('../migrations/'+name,import.meta.url),'utf8');const split=spawnSync(process.execPath,['-e',"const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"],{cwd:root,input:sql,encoding:'utf8'});assert.equal(split.status,0,split.stderr);await db.batch(JSON.parse(split.stdout).map(s=>db.prepare(s)));}
 env={MEMBER_MEDIA:await runtime.getR2Bucket('MEMBER_MEDIA'),ADMIN_DB:db,MEMBER_ORIGIN:origin,MEMBER_AUTH_PEPPER:'synthetic-test-only-secret-'.repeat(3),ENVIRONMENT:'test',EMAIL:{send:async p=>{emails.push(p);return{messageId:crypto.randomUUID()};}}};});
after(async()=>runtime?.dispose());
let alice,bob,group;
test('email OTP is single-use, provider-accepted only, with no code or native secrets in browser response',async()=>{
 const email='Alice@Example.com',issued=await call('auth/request-code',{email});assert.equal(issued.status,200);assert.equal(JSON.stringify(issued.body).includes('code'),false);const code=/code is (\d{6})/.exec(emails.at(-1).text)[1];
 assert.equal((await call('auth/verify-code',{email,challengeId:issued.body.challengeId,code:'wrong'})).status,400);
 const v=await call('auth/verify-code',{email,challengeId:issued.body.challengeId,code});assert.equal(v.status,200);alice=v.body;assert.equal(alice.user.email,'alice@example.com');assert.match(alice.accessToken,/^[a-f0-9]{64}$/);assert.equal((await call('auth/verify-code',{email,challengeId:issued.body.challengeId,code})).status,400);
 const browserIssue=await call('auth/request-code',{email:'browser@example.com'},null,{Origin:origin,'Sec-Fetch-Site':'same-origin'});const browserCode=/code is (\d{6})/.exec(emails.at(-1).text)[1];const browser=await call('auth/verify-code',{email:'browser@example.com',challengeId:browserIssue.body.challengeId,code:browserCode},null,{Origin:origin,'Sec-Fetch-Site':'same-origin'});assert.equal(browser.status,200);assert.equal(browser.body.accessToken,undefined);assert.match(browser.headers.get('set-cookie'),/HttpOnly/);assert.match(browser.headers.get('set-cookie'),/Secure/);
});
test('member group/profile/intent flows store real data and never post a payment',async()=>{
 bob=await login('bob@example.com');let r=await cmd(alice,'update_current_member_profile',{p_country_code:'RW',p_momo_provider:'mtn_momo',p_momo_number:'0781234567',p_momo_pay_code:''});assert.equal(r.status,200);assert.equal(r.body.data.momo_number,'0781234567');
 r=await cmd(alice,'create_private_group',{group_name:'Member savings',group_description:'Fresh group',receiver_momo_number:'0781234567',receiver_label:'Group receiver',group_collection_type:'ikimina'});assert.equal(r.status,200);group=r.body.data;
 const groups=await cmd(alice,'list_current_user_collections');assert.equal(groups.body.data[0].id,group);assert.equal(groups.body.data[0].receiver_network,'mtn_momo');
 assert.equal((await cmd(bob,'get_group_share_code',{p_collection_id:group})).status,409);
 const link=(await cmd(alice,'get_group_share_code',{p_collection_id:group})).body.data;assert.equal((await cmd(bob,'join_group_by_share_code',{p_group_code:link})).body.data,group);
 r=await cmd(bob,'create_contribution_intent',{collection:group,p_expected_amount_rwf:1234});assert.equal(r.status,200);assert.equal(r.body.data.status,'pending');assert.equal(r.body.data.amount_minor,1234);
 const history=(await cmd(bob,'list_current_member_history_page')).body.data;assert.equal(history.total_count,0);assert.deepEqual(history.own_totals,{RWF:0});
 assert.equal((await db.prepare('SELECT count(*) n FROM collect_transactions').first()).n,0);assert.deepEqual((await db.prepare('PRAGMA foreign_key_check').all()).results,[]);
});
test('preference revisions conflict, sharing rotates with replay, and member permissions remain scoped',async()=>{
 const before=(await cmd(alice,'get_notification_preferences_v2')).body.data;assert.equal(before.exists,true);const params={p_expected_revision:before.revision,p_preferences:{contribution_confirmations:true,payment_reminders:false,group_updates:true,security_notices:true}};assert.equal((await cmd(alice,'set_notification_preferences_v2',params)).status,200);assert.equal((await cmd(alice,'set_notification_preferences_v2',params)).status,409);
 const request={p_collection_id:group,p_request_id:crypto.randomUUID()},rotated=await cmd(alice,'rotate_group_share_code_v2',request);assert.equal(rotated.status,200);assert.deepEqual((await cmd(alice,'rotate_group_share_code_v2',request)).body.data,rotated.body.data);
 assert.equal((await cmd(bob,'archive_group',{collection:group})).status,409);assert.equal((await cmd(bob,'unknown')).status,404);
});
test('privacy requires matching fresh email challenge and creates intake only',async()=>{
 const issue=await call('privacy/request-code',{},bob);const code=/code is (\d{6})/.exec(emails.at(-1).text)[1];const verified=await call('privacy/verify-code',{challengeId:issue.body.challengeId,code},bob);assert.equal(verified.status,200);assert.equal((await call('auth/session',null,bob)).body.user,null);bob=verified.body;
 const id=crypto.randomUUID(),receipt=await call('privacy/submit',{p_request_id:id,p_reason:'Not needed'},bob);assert.equal(receipt.status,200);assert.equal(receipt.body.data.erasure_completed,false);assert.equal(receipt.body.data.request_id,id);assert.equal((await call('privacy/review',{p_request_id:id},bob)).body.data.review_state,'awaiting_review');
});
test('email change, suspension and refresh atomically revoke old credentials',async()=>{
 const renewed=await call('auth/refresh',{},alice,{'X-Collect-Refresh':alice.refreshToken});assert.equal(renewed.status,200);assert.equal((await cmd(alice,'get_current_member_profile')).status,401);alice=renewed.body;
 await run('UPDATE collect_users SET email=? WHERE id=?','alice.changed@example.com',alice.user.id);assert.equal((await cmd(alice,'get_current_member_profile')).status,401);assert.equal((await call('auth/refresh',{},alice,{'X-Collect-Refresh':alice.refreshToken})).status,401);
 await run("UPDATE collect_users SET status='suspended' WHERE id=?",bob.user.id);assert.equal((await cmd(bob,'get_current_member_profile')).status,401);
});
test('local email unavailable, cross-site rejection and missing provider never create verified sessions',async()=>{const previous=env.ENVIRONMENT;env.ENVIRONMENT='local';assert.equal((await call('auth/request-code',{email:'local@example.com'})).status,503);env.ENVIRONMENT=previous;assert.equal((await call('auth/request-code',{email:'cross@example.com'},null,{Origin:'https://attacker.invalid'})).status,403);});


test('invited identities activate, OTP attempts lock out, and a failed provider cannot activate a challenge',async()=>{
 const at=Math.floor(Date.now()/1000),id=crypto.randomUUID();
 await run("INSERT INTO collect_users(id,email,status,created_at,updated_at) VALUES(?,'invited@example.com','invited',?,?)",id,at,at);
 await run("INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,'009911','Invited fixture',?,?)",id,at,at);
 const invited=await login('invited@example.com');assert.equal(invited.user.id,id);assert.equal((await cmd(invited,'get_current_member_profile')).body.data.public_id,'009911');
 const issued=await call('auth/request-code',{email:'locked@example.com'}),code=/code is (\d{6})/.exec(emails.at(-1).text)[1];
 for(let i=0;i<8;i++)assert.equal((await call('auth/verify-code',{email:'locked@example.com',challengeId:issued.body.challengeId,code:code==='111111'?'222222':'111111'})).status,400);
 assert.equal((await call('auth/verify-code',{email:'locked@example.com',challengeId:issued.body.challengeId,code})).status,400);
 const sender=env.EMAIL;env.EMAIL={send:async()=>{throw new Error('test provider unavailable');}};
 assert.equal((await call('auth/request-code',{email:'failed@example.com'})).status,503);env.EMAIL=sender;
 assert.equal((await db.prepare("SELECT state FROM member_email_challenges WHERE email='failed@example.com'").first()).state,'failed');
});

test('private R2 receipt evidence preserves exact bytes, rejects collisions and never confirms money',async()=>{
 const owner=await login('receipt@example.com'),id=crypto.randomUUID(),raw='  MoMo receipt text\n',payload={client_envelope_id:id,raw_sender:'MobileMoney',raw_body:raw};
 assert.equal((await call('receipts',payload,owner)).status,403);
 await cmd(owner,'record_sms_access_consent',{enabled:true});
 const submitted=await call('receipts',payload,owner);assert.equal(submitted.status,200);assert.equal(submitted.body.data.processing,'needs_review');
 const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw)))].map(x=>x.toString(16).padStart(2,'0')).join('');assert.equal(submitted.body.data.receipt.body_sha256,hash);
 assert.deepEqual((await call('receipts',payload,owner)).body,submitted.body);
 assert.equal((await call('receipts',{...payload,raw_body:'changed'},owner)).status,409);
 const orphan=crypto.randomUUID();await env.MEMBER_MEDIA.put(`member-receipts/${owner.user.id}/${orphan}`,JSON.stringify({raw_sender:'MobileMoney',raw_body:'existing bytes'}));
 assert.equal((await call('receipts',{...payload,client_envelope_id:orphan},owner)).status,409);
 assert.equal((await db.prepare('SELECT count(*) n FROM member_receipt_submissions WHERE id=?').bind(orphan).first()).n,0);
 const concurrent=crypto.randomUUID(),attempt=()=>call('receipts',{...payload,client_envelope_id:concurrent},owner),both=await Promise.all([attempt(),attempt()]);assert.deepEqual(both.map(x=>x.status),[200,200]);
 const stored=await env.MEMBER_MEDIA.get(`member-receipts/${owner.user.id}/${id}`);assert.deepEqual(await stored.json(),{raw_sender:'MobileMoney',raw_body:raw});
 assert.equal((await db.prepare('SELECT count(*) n FROM collect_transactions').first()).n,0);
});

test('R2 group photos use expiring signed URLs and cannot be adopted by another member',async()=>{
 const owner=await login('photos@example.com'),other=await login('photos.other@example.com');
 const photo='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZp8AAAAASUVORK5CYII=';
 const uploaded=await call('media/upload',{image:photo},owner);assert.equal(uploaded.status,200);const url=uploaded.body.data.image_url;
 const image=await handleMember(new Request(url),env,{});assert.equal(image.status,200);assert.equal(image.headers.get('Content-Type'),'image/png');assert.ok((await image.arrayBuffer()).byteLength>12);
 const expired=new URL(url);expired.searchParams.set('until','1');await assert.rejects(handleMember(new Request(expired),env,{}),e=>e instanceof MemberError&&e.status===403);
 const params={group_name:'Photo group',group_collection_type:'other',receiver_momo_number:'0781234567',group_image_url:url};
 assert.equal((await cmd(other,'create_private_group',params)).status,403);assert.equal((await cmd(owner,'create_private_group',params)).status,200);
 assert.equal((await call('media/upload',{image:'data:image/png;base64,SGVsbG8='},owner)).status,400);
});

test('member role changes, transfer, archive and revoked memberships enforce current group authority',async()=>{
 const owner=await login('roles.owner@example.com'),member=await login('roles.member@example.com');
 const created=await cmd(owner,'create_private_group',{group_name:'Role fixture',group_collection_type:'other',receiver_momo_number:'0781234567'}),id=created.body.data;
 const link=(await cmd(owner,'get_group_share_code',{p_collection_id:id})).body.data;await cmd(member,'join_group_by_share_code',{p_group_code:link});
 const publicId=(await cmd(member,'get_current_member_profile')).body.data.public_id;
 const roster=await cmd(member,'list_current_member_group_roster',{p_collection_id:id});assert.equal(roster.status,200);assert.equal(roster.body.data.filter(x=>x.amount_scope==='own').length,1);
 assert.equal((await cmd(owner,'add_group_admin',{collection:id,member_public_id:publicId})).status,200);
 assert.equal((await cmd(owner,'transfer_group_ownership',{collection:id,new_owner_public_id:publicId})).status,200);
 assert.equal((await cmd(owner,'archive_group',{collection:id})).status,409);
 assert.equal((await cmd(member,'get_owner_group_health',{collection:id})).status,200);
 await run("UPDATE collect_memberships SET status='removed',version=version+1 WHERE group_id=? AND user_id=?",id,owner.user.id);
 assert.equal((await cmd(owner,'list_current_member_group_roster',{p_collection_id:id})).status,409);
 assert.equal((await cmd(member,'archive_group',{collection:id})).status,200);
 assert.equal((await cmd(member,'create_contribution_intent',{collection:id,p_expected_amount_rwf:500})).status,409);
});

async function postedPayment(group,member,value,{post=true}={}) {
 const at=Math.floor(Date.now()/1000),actor=crypto.randomUUID(),reviewer=crypto.randomUUID(),transaction=crypto.randomUUID(),allocation=crypto.randomUUID(),evidence=crypto.randomUUID(),journal=crypto.randomUUID();
 for(const id of [actor,reviewer])await run("INSERT INTO admin_users(id,email,role,status,created_at,updated_at) VALUES(?,?,'admin','invited',?,?)",id,id+'@example.com',at,at);
 const op=async who=>{const id=crypto.randomUUID();await run("INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,'synthetic.test',?,?,?)",id,who,crypto.randomUUID(),'a'.repeat(64),at);return id;};
 const payee=(await db.prepare("SELECT id FROM collect_payees WHERE group_id=? AND status='active'").bind(group).first()).id;
 await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at,recorded_by_admin_id) VALUES(?,?,?,'mtn_momo',?,?,?,?,?)",transaction,group,payee,'reference-'+transaction,value,at,at,actor);
 await run("INSERT INTO collect_transaction_evidence(id,transaction_id,kind,reference,artifact_sha256,recorded_by_admin_id,operation_request_id,recorded_at) VALUES(?,?,'receiver_statement','Synthetic statement',?,?,?,?)",evidence,transaction,'b'.repeat(64),actor,await op(actor),at);
 await run("INSERT INTO collect_transaction_reviews(id,transaction_id,evidence_id,outcome,transaction_version,reviewed_by_admin_id,operation_request_id,reason,reviewed_at) VALUES(?,?,?,'confirmation_recorded',2,?,?,'Synthetic independent review',?)",crypto.randomUUID(),transaction,evidence,reviewer,await op(reviewer),at);
 await run("UPDATE collect_transactions SET verification_status='confirmation_recorded',version=2,verified_by_admin_id=?,verified_at=? WHERE id=?",reviewer,at,transaction);
 await run('INSERT INTO collect_payment_allocations(id,transaction_id,group_id,member_user_id,amount_rwf,operation_request_id,created_by_admin_id,created_at) VALUES(?,?,?,?,?,?,?,?)',allocation,transaction,group,member,value,await op(actor),actor,at);
 await run("INSERT INTO collect_journals(id,group_id,transaction_id,allocation_id,operation_request_id,description,created_by_admin_id,created_at) VALUES(?,?,?,?,?,'Synthetic payment journal',?,?)",journal,group,transaction,allocation,await op(actor),actor,at);
 for(const [line,side,kind] of [[1,'debit','asset'],[2,'credit','liability']]){const account=crypto.randomUUID();await run("INSERT INTO collect_ledger_accounts(id,group_id,code,name,account_type,normal_side,created_by_admin_id,created_at) VALUES(?,?,?,'Synthetic account',?,?,?,?)",account,group,account,kind,side,actor,at);await run('INSERT INTO collect_journal_entries(id,journal_id,group_id,account_id,line_number,debit_rwf,credit_rwf) VALUES(?,?,?,?,?,?,?)',crypto.randomUUID(),journal,group,account,line,side==='debit'?value:0,side==='credit'?value:0);}
 if(post)await run("UPDATE collect_journals SET status='posted',posted_by_admin_id=?,posted_at=?,version=version+1 WHERE id=?",reviewer,at,journal);
 return{transaction,allocation,journal};
}

test('member balances, own roster totals and revision pagination derive only from posted allocations and fail closed on aggregate overflow',async()=>{
 const owner=await login('finance.owner@example.com'),member=await login('finance.member@example.com');
 const group=(await cmd(owner,'create_private_group',{group_name:'Financial fixture',group_collection_type:'ikimina',receiver_momo_number:'0781234567'})).body.data;
 await cmd(member,'join_group_by_share_code',{p_group_code:(await cmd(owner,'get_group_share_code',{p_collection_id:group})).body.data});
 await postedPayment(group,member.user.id,400);await postedPayment(group,owner.user.id,600);await postedPayment(group,member.user.id,999,{post:false});
 const page=await cmd(member,'list_current_member_history_page',{p_limit:1});assert.equal(page.status,200);assert.equal(page.body.data.total_count,2);assert.deepEqual(page.body.data.totals,{RWF:1000});assert.deepEqual(page.body.data.own_totals,{RWF:400});assert.ok(page.body.data.next_cursor);
 const next=await cmd(member,'list_current_member_history_page',{p_limit:1,p_cursor:page.body.data.next_cursor});assert.equal(next.status,200);assert.notEqual(next.body.data.items[0].payment_id,page.body.data.items[0].payment_id);assert.equal(next.body.data.next_cursor,null);
 const balances=(await cmd(member,'list_current_member_collection_balances')).body.data;assert.deepEqual(balances[0].balances,[{currency:'RWF',amount_raised_minor:1000,current_user_balance_minor:400}]);
 const roster=(await cmd(member,'list_current_member_group_roster',{p_collection_id:group})).body.data;assert.deepEqual(roster.find(x=>x.amount_scope==='own').contributions,[{currency:'RWF',amount_minor:400}]);assert.deepEqual(roster.find(x=>x.amount_scope==='hidden').contributions,[]);
 await postedPayment(group,owner.user.id,100);assert.equal((await cmd(member,'list_current_member_history_page',{p_cursor:page.body.data.next_cursor})).status,409);
 await postedPayment(group,member.user.id,Number.MAX_SAFE_INTEGER);
 assert.equal((await cmd(member,'list_current_member_collection_balances')).status,503);assert.equal((await cmd(member,'list_current_member_history_page')).status,503);assert.equal((await cmd(member,'list_current_member_group_roster',{p_collection_id:group})).status,503);
});

test('approved public contributions create membership while removed accounts remain denied',async()=>{
 const owner=await login('public.owner@example.com'),member=await login('public.member@example.com');
 const id=(await cmd(owner,'create_private_group',{group_name:'Public contribution fixture',group_collection_type:'other',receiver_momo_number:'0781234567'})).body.data;
 assert.equal((await cmd(member,'create_contribution_intent',{collection:id,p_expected_amount_rwf:100})).status,409);
 await run("UPDATE collect_groups SET visibility='public_approved',version=version+1 WHERE id=?",id);
 const intent=await cmd(member,'create_contribution_intent',{collection:id,p_expected_amount_rwf:100});assert.equal(intent.status,200);
 assert.equal((await db.prepare('SELECT status FROM collect_memberships WHERE group_id=? AND user_id=?').bind(id,member.user.id).first()).status,'active');
 await run("UPDATE collect_memberships SET status='removed',version=version+1 WHERE group_id=? AND user_id=?",id,member.user.id);
 assert.equal((await cmd(member,'create_contribution_intent',{collection:id,p_expected_amount_rwf:100})).status,409);
 assert.equal((await call('auth/session',null,owner,{'X-Collect-Session':crypto.randomUUID()})).status,401);
});

test('wire amounts reject fractional, exponent and unsafe lexemes before JSON parsing can round them',async()=>{
 for(const value of ['1.0000000000000001','1e0','1E+0','9007199254740992','9007199254740993','-1.0000000000000001']){
  const r=new Request(origin+'/api/member/command',{method:'POST',headers:{'X-Collect-Client':'native','Content-Type':'application/json'},body:`{"name":"create_contribution_intent","params":{"p_expected_amount_rwf":${value}}}`});
  await assert.rejects(handleMember(r,env,{}),e=>e instanceof MemberError&&e.status===400&&e.code==='invalid_number');
 }
 // Decimal-looking content inside a JSON string is content, not a number token.
 const r=new Request(origin+'/api/member/command',{method:'POST',headers:{'X-Collect-Client':'native','Content-Type':'application/json'},body:'{"name":"create_mobile_support_request","params":{"request_message":"Version 1.0000000000000001 e0"}}'});
 await assert.rejects(handleMember(r,env,{}),e=>e instanceof MemberError&&e.status===401);
});

test('technical content seed reads through the member API and preserves operator content on replay',async()=>{
 const sql=await readFile(new URL('../seeds/member-content.sql',import.meta.url),'utf8');
 const statements=sql.split('\n').filter(line=>line.startsWith('INSERT INTO '));
 await db.batch(statements.map(s=>db.prepare(s)));await db.batch(statements.map(s=>db.prepare(s)));
 const config=await call('public/content',{name:'get_public_runtime_config'});assert.equal(config.status,200);assert.deepEqual(config.body.data.support_channels,[{key:'support.email',value:'info@ikanisa.com',display_value:'info@ikanisa.com'}]);
 const catalog=await call('public/content',{name:'get_collection_type_catalog'});assert.deepEqual(catalog.body.data.types.map(x=>x.key),['ikimina','sport','church','wedding','other']);assert.equal((await call('public/content',{name:'get_active_policy_document',params:{p_kind:'privacy'}})).status,503);
 await run("UPDATE member_content SET payload_json=? WHERE kind='get_public_runtime_config'",JSON.stringify({brand:{display_name:'Operator custom'}}));
  await db.batch(statements.map(s=>db.prepare(s)));assert.equal((await call('public/content',{name:'get_public_runtime_config'})).body.data.brand.display_name,'Operator custom');
});

test('concurrent OTP acceptance and refresh rotation each have one winner with no stale-token reuse',async()=>{
 const email='parallel.auth@example.com',issued=await call('auth/request-code',{email}),code=/code is (\d{6})/.exec(emails.at(-1).text)[1];
 const replies=await Promise.all([1,2].map(()=>call('auth/verify-code',{email,challengeId:issued.body.challengeId,code})));
 assert.equal(replies.filter(x=>x.status===200).length,1);assert.ok(replies.filter(x=>x.status!==200).every(x=>[400,409].includes(x.status)));
 const signed=replies.find(x=>x.status===200).body;
 assert.equal((await db.prepare('SELECT count(*) AS n FROM collect_users WHERE email=?').bind(email).first()).n,1);
 assert.equal((await db.prepare('SELECT count(*) AS n FROM member_sessions WHERE user_id=?').bind(signed.user.id).first()).n,1);
 const refreshed=await Promise.all([1,2].map(()=>call('auth/refresh',{},signed,{'X-Collect-Refresh':signed.refreshToken})));
 assert.deepEqual(refreshed.map(x=>x.status).sort(),[200,401]);
 const current=refreshed.find(x=>x.status===200).body;
 assert.equal(current.user.sessionId,signed.user.sessionId);assert.ok(current.accessToken!==signed.accessToken);assert.ok(current.refreshToken!==signed.refreshToken);
 assert.equal((await cmd(signed,'get_current_member_profile')).status,401);
 assert.equal((await call('auth/refresh',{},signed,{'X-Collect-Refresh':signed.refreshToken})).status,401);
 assert.equal((await cmd(current,'get_current_member_profile')).status,200);
 assert.equal((await db.prepare('SELECT count(*) AS n FROM member_sessions WHERE user_id=?').bind(signed.user.id).first()).n,1);
});

test('browser cookies and native bearer credentials cannot substitute for or override the other channel',async()=>{
 const native=await login('transport.native@example.com'),browser=await login('transport.browser@example.com');
 const cookie=`__Host-collect_member=${browser.accessToken}; __Host-collect_member_refresh=${browser.refreshToken}`;
 const command={name:'get_current_member_profile',params:{}},web={Origin:origin,'Sec-Fetch-Site':'same-origin'};
 assert.equal((await call('command',command,native,web)).status,401,'Browser requests must ignore bearer tokens');
 assert.equal((await call('command',command,null,{Cookie:cookie})).status,401,'Native requests must ignore cookies');
 const result=await call('command',command,native,{...web,Cookie:cookie});
 assert.equal(result.status,200);assert.equal(result.body.data.id,browser.user.id);
 assert.equal((await call('command',command,native,{...web,Cookie:cookie,'X-Collect-Session':native.user.sessionId})).status,401);
 assert.equal((await call('command',command,null,{...web,Cookie:`${cookie}; __Host-collect_member=${browser.accessToken}`})).status,401);
 assert.equal((await call('command',command,native,{...web,Cookie:cookie,'Sec-Fetch-Site':'cross-site'})).status,403);
 assert.equal((await call('command',command,native,{Origin:'https://attacker.invalid'})).status,403);
 assert.equal((await call('auth/sign-out',{},null,{...web,Cookie:cookie})).status,200);
 assert.equal((await call('auth/refresh',{},browser,{'X-Collect-Refresh':browser.refreshToken})).status,401);
 assert.equal((await cmd(native,'get_current_member_profile')).status,200,'Signing out another session must not erase this native session');
});

test('expired and previously emailed OTPs cannot restore an old email or suspended account',async()=>{
 const expiredEmail='expired.auth@example.com',expired=await call('auth/request-code',{email:expiredEmail}),expiredCode=/code is (\d{6})/.exec(emails.at(-1).text)[1];
 await run('UPDATE member_email_challenges SET created_at=1,expires_at=2 WHERE id=?',expired.body.challengeId);
 assert.equal((await call('auth/verify-code',{email:expiredEmail,challengeId:expired.body.challengeId,code:expiredCode})).status,400);
 assert.equal(await db.prepare('SELECT id FROM collect_users WHERE email=?').bind(expiredEmail).first(),null);
 for(const change of ['email','status']) {
  const email=`pending.${change}@example.com`,signed=await login(email),pending=await call('auth/request-code',{email}),code=/code is (\d{6})/.exec(emails.at(-1).text)[1];
  if(change==='email')await run('UPDATE collect_users SET email=? WHERE id=?',`changed.${email}`,signed.user.id);
  else await run("UPDATE collect_users SET status='suspended' WHERE id=?",signed.user.id);
  assert.equal((await call('auth/verify-code',{email,challengeId:pending.body.challengeId,code})).status,400);
  assert.equal((await db.prepare('SELECT state FROM member_email_challenges WHERE id=?').bind(pending.body.challengeId).first()).state,'failed');
  assert.equal((await db.prepare('SELECT count(*) AS n FROM member_sessions WHERE user_id=?').bind(signed.user.id).first()).n,0);
 }
});

test('sign-out is idempotent for expired or absent targets and refresh-only browser cookies',async()=>{
 const signed=await login('logout.expired@example.com');
 await run('UPDATE member_sessions SET created_at=1,expires_at=2 WHERE id=?',signed.user.sessionId);
 const headers={'X-Collect-Session':signed.user.sessionId};
 assert.equal((await call('auth/sign-out',{},signed,headers)).status,200);
 assert.equal((await call('auth/sign-out',{},signed,headers)).status,200);
 assert.equal(await db.prepare('SELECT id FROM member_sessions WHERE id=?').bind(signed.user.sessionId).first(),null);
 const browser=await login('logout.browser@example.com');
 const web={Origin:origin,'Sec-Fetch-Site':'same-origin',Cookie:`__Host-collect_member_refresh=${browser.refreshToken}`,'X-Collect-Session':browser.user.sessionId};
 const result=await call('auth/sign-out',{},null,web);
 assert.equal(result.status,200);assert.deepEqual(result.body,{ok:true,signedOut:true});
 const cleared=result.headers.getSetCookie();assert.equal(cleared.length,2);assert.ok(cleared.every(x=>x.includes('Max-Age=0')&&x.includes('HttpOnly')&&x.includes('Secure')));
 assert.equal((await call('auth/refresh',{},browser,{'X-Collect-Refresh':browser.refreshToken})).status,401);
 const absent=await call('auth/sign-out',{},null,{Origin:origin,'Sec-Fetch-Site':'same-origin','X-Collect-Session':browser.user.sessionId});
 assert.equal(absent.status,200);assert.equal(absent.headers.getSetCookie().length,2);
});

test('stale sign-out intent cannot clear or revoke a replacement browser or native session',async()=>{
 const old=await login('logout.old@example.com'),current=await login('logout.current@example.com');
 const web={Origin:origin,'Sec-Fetch-Site':'same-origin',Cookie:`__Host-collect_member=${current.accessToken}; __Host-collect_member_refresh=${current.refreshToken}`,'X-Collect-Session':old.user.sessionId};
 const result=await call('auth/sign-out',{},null,web);
 assert.equal(result.status,401);assert.equal(result.body.error.code,'account_changed');assert.equal(result.headers?.get('Set-Cookie')??null,null);
 assert.equal((await call('auth/sign-out',{},old,{'X-Collect-Session':old.user.sessionId,'X-Collect-Refresh':current.refreshToken})).status,401);
 assert.equal((await cmd(old,'get_current_member_profile')).status,200);
 assert.equal((await cmd(current,'get_current_member_profile')).status,200);
 assert.equal((await call('auth/sign-out',{},old,{'X-Collect-Session':old.user.sessionId})).status,200);
 assert.equal((await call('auth/sign-out',{},old,{'X-Collect-Session':old.user.sessionId})).status,200);
 assert.equal((await cmd(current,'get_current_member_profile')).status,200);
});
