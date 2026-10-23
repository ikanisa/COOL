import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtemp,mkdir,readFile,readdir,chmod,symlink,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fixture} from './http_fixture.mjs';
import {AdminHttp} from '../src/http_client.mjs';
import {OperatorClient} from '../src/operator_client.mjs';
import {OperationJournal,privateRead,privateDirectory} from '../src/private_state.mjs';
import {ORIGINS,sha,canonical} from '../src/contract.mjs';
import {privateTestRoot} from './private_test_root.mjs';

const ROOT=await privateTestRoot();
async function context(t,origin=ORIGINS[0]) {
  const server=await fixture({origin});t.after(()=>server.close());
  const dir=await mkdtemp(join(ROOT,'operator-'));await chmod(dir,0o700);const journalDir=join(dir,'journal');await mkdir(journalDir,{mode:0o700});
  const http=new AdminHttp({origin,fetchImpl:server.fetch,clock:()=>server.now,timeoutMs:1000});
  const journal=await new OperationJournal(journalDir).ready();const client=new OperatorClient({http,journal,clock:()=>server.now});
  const login=()=>server.login(http);
  await login();const session=()=>http.snapshot().user.sessionId;
  const call=(action,args={},options)=>client.call(action,{operator_session:session(),...args},options);
  async function claim(job=server.first) {
    const args={job_id:job.id,request_id:randomUUID(),worker_id:'synthetic-desktop',expected_fence:job.fence};return {args,value:await call('claim',args)};
  }
  async function prepared(job=server.first) {
    const claimed=await claim(job),base={job_id:job.id,claim_token:claimed.value.claim_token,fence_version:claimed.value.fence_version};
    const content=await call('get_claimed',base);
    const confirm={...base,request_id:randomUUID(),confirmation_id:randomUUID(),body_sha256:content.body_sha256,destination_sha256:content.destination_sha256,destination_revision:content.destination_revision,user_confirmation:true};
    const confirmation=await call('confirm',confirm);
    return {claimed,base,content,confirm,confirmation,start:{...base,request_id:randomUUID(),confirmation_id:confirm.confirmation_id,manual_authorization:{user_authorized:true,authorization_reference_sha256:sha('synthetic explicit per-message authorization')}}};
  }
  return {server,http,journal,client,dir,journalDir,login,session,call,claim,prepared};
}
test('actual local HTTP email sign-in binds truthful AAL1, proof and public/canonical sessions',async t=>{
  const c=await context(t);const before=c.http.snapshot();
  assert.equal(before.user.assuranceLevel,1);assert.equal(before.user.mfaAt,null);assert.equal(before.proofState,'available');assert.equal(Date.parse(before.emailVerifiedAt),c.server.current.emailVerifiedAt);assert.notEqual(before.user.sessionId,c.server.current.canonical);
  assert.equal(c.http.metadata().credentials_persisted,false);
  assert.equal(c.server.counts['/api/admin/auth/verify'],1);assert.equal(c.server.counts['/api/admin/auth/mfa/verify'],undefined);
  const pending=await c.call('list_pending');assert.equal(pending.items.length,2);
  await c.http.logout();assert.equal(c.http.snapshot(),null);
  await assert.rejects(c.client.call('list_pending',{operator_session:before.user.sessionId}),/authentication_required/);
});
test('generic notification history permissions cannot authorize the separate assisted SMS client',async t=>{
  const c=await context(t);
  c.server.current.permissions=['notifications.read','notifications.manage'];
  await assert.rejects(c.call('list_pending'),/permission_required/);
  assert.equal(c.server.counts.list_pending,undefined);
  const args={job_id:c.server.first.id,request_id:randomUUID(),worker_id:'synthetic-desktop',expected_fence:0};
  await assert.rejects(c.call('claim',args),/permission_required/);
  assert.equal(c.server.counts.claim,undefined);
  c.server.current.permissions=['assisted_sms.read','assisted_sms.manage'];
  assert.equal((await c.call('list_pending')).items.length,2);
  assert.equal(c.server.effectCounts.claim,undefined);
});
for(const origin of ORIGINS)test(`all eight current Supabase HTTP actions, CSRF and one-use manual handoff at ${origin}`,async t=>{
  const c=await context(t,origin),p=await c.prepared();
  const sent=await c.call('record_send_start',p.start);
  assert.equal(sent.may_send,true);assert.equal(sent.manual_handoff.destination_e164,p.content.destination_e164);assert.equal(sent.manual_handoff.message_body,p.content.message_body);
  assert.equal(sent.manual_handoff.one_use,true);assert.equal(sent.provider_confirmation,false);assert.equal(sent.delivery_confirmed,false);
  const repeated=await c.call('record_send_start',p.start);assert.equal(repeated.may_send,false);assert.equal(repeated.manual_handoff,undefined);assert.equal(c.server.counts.record_send_start,1);
  const observed=await c.call('get_operation',{request_id:p.start.request_id});assert.equal(observed.receipt.may_send,false);assert.equal(observed.may_send,false);
  const outcome=await c.call('record_outcome',{attempt_id:sent.attempt_id,request_id:randomUUID(),observation:'observed_sent',evidence_reference_sha256:sha('synthetic conversation action readback')});
  assert.equal(outcome.observation,'observed_sent');assert.equal(outcome.delivery_confirmed,false);assert.equal(outcome.settlement_status,'not_asserted');
  const other=await c.claim(c.server.second);
  const released=await c.call('release_claim',{job_id:c.server.second.id,claim_token:other.value.claim_token,fence_version:other.value.fence_version,request_id:randomUUID()});assert.equal(released.fence_version,2);
});
for(const action of ['claim','confirm','record_send_start'])test(`lost committed ${action} acknowledgement resolves original UUID without resending or reissuing permission`,async t=>{
  const c=await context(t);let args;
  if(action==='claim')args={job_id:c.server.first.id,request_id:randomUUID(),worker_id:'synthetic-desktop',expected_fence:0};
  else if(action==='confirm') {
    const claimed=await c.claim(),base={job_id:c.server.first.id,claim_token:claimed.value.claim_token,fence_version:1},content=await c.call('get_claimed',base);
    args={...base,request_id:randomUUID(),confirmation_id:randomUUID(),body_sha256:content.body_sha256,destination_sha256:content.destination_sha256,destination_revision:1,user_confirmation:true};
  } else args=(await c.prepared()).start;
  c.server.fault={action,after:true};await assert.rejects(c.call(action,args),/operation_outcome_unknown/);
  const count=c.server.counts[action];await assert.rejects(c.call(action,{...args,resume_original_request:true}),/resolve_original/);assert.equal(c.server.counts[action],count);
  const resolved=await c.call('get_operation',{request_id:args.request_id});assert.equal(resolved.observed,true);assert.notEqual(resolved.receipt.may_send,true);
  const repeat=await c.call(action,args);assert.notEqual(repeat.may_send,true);assert.equal(repeat.manual_handoff,undefined);assert.equal(c.server.counts[action],count);assert.equal(c.server.effectCounts[action],1);
});
test('unobserved original write needs readback then explicit exact-UUID retry; no automatic resend',async t=>{
  const c=await context(t),args={job_id:c.server.first.id,request_id:randomUUID(),worker_id:'synthetic-desktop',expected_fence:0};
  c.server.fault={action:'claim',before:true};await assert.rejects(c.call('claim',args),/operation_outcome_unknown/);
  assert.equal(c.server.effectCounts.claim,undefined);
  await assert.rejects(c.call('claim',{...args,resume_original_request:true}),/resolve_original/);
  assert.equal((await c.call('get_operation',{request_id:args.request_id})).observed,false);
  await assert.rejects(c.call('claim',args),/resolve_original/);
  const result=await c.call('claim',{...args,resume_original_request:true});assert.equal(result.fence_version,1);assert.equal(c.server.effectCounts.claim,1);
  await assert.rejects(c.call('claim',{...args,worker_id:'replacement'}),/original_operation_payload/);
});
test('fresh same-user sign-in cannot adopt old claim or original receipt',async t=>{
  const c=await context(t),claimed=await c.claim(),old=c.session();await c.login();assert.notEqual(c.session(),old);
  await assert.rejects(c.client.call('list_pending',{operator_session:old}),/original_public_session/);
  await assert.rejects(c.call('get_claimed',{job_id:c.server.first.id,claim_token:claimed.value.claim_token,fence_version:1}),/current_unexpired_claim/);
  await assert.rejects(c.call('get_operation',{request_id:claimed.args.request_id}),/request_conflict/);
  assert.equal(c.server.effectCounts.claim,1);
});
test('email re-verification in the same public session fences claim/content and never adopts retained operations',async t=>{
  const c=await context(t),p=await c.prepared(),original=c.http.snapshot(),intent=(await c.journal.load(p.claimed.args.request_id)).intent;c.server.now+=1000;
  await c.server.reverify(c.http);
  assert.equal(c.session(),original.user.sessionId);assert.notEqual(c.http.snapshot().authority,original.authority);
  assert.equal(c.http.snapshot().user.assuranceLevel,1);assert.equal(c.http.snapshot().user.mfaAt,null);
  await assert.rejects(c.call('record_send_start',p.start),/current_unexpired_claim/);
  await assert.rejects(c.call('get_operation',{request_id:p.claimed.args.request_id}),/original_operation_authority/);
  assert.equal(c.server.effectCounts.record_send_start,undefined);assert.deepEqual((await c.journal.load(p.claimed.args.request_id)).intent,intent);
});
test('email-proof expiry, revoked cookie, role and permission changes stop before a new effect',async t=>{
  const c=await context(t),p=await c.prepared();c.server.now+=300001;
  await assert.rejects(c.call('record_send_start',p.start),error=>error.code==='recent_email_sign_in_required'&&!error.outcomeUnknown);assert.equal(c.server.counts.record_send_start,undefined);
  c.server.now-=300001;c.server.current.permissions=['assisted_sms.read'];
  await assert.rejects(c.call('record_send_start',p.start),/permission_required/);
  c.server.sessions.clear();await assert.rejects(c.call('list_pending'),/authentication_required/);assert.equal(c.http.snapshot(),null);
});
test('a response delayed across the original email-proof boundary cannot issue a usable handoff after its real commit',async t=>{
  const c=await context(t);c.server.now+=299000;const p=await c.prepared();let entered,release;
  const arrived=new Promise(resolve=>entered=resolve);c.server.fault={action:'record_send_start',entered,gate:new Promise(resolve=>release=resolve)};
  const pending=c.call('record_send_start',p.start),rejected=assert.rejects(pending,error=>error.code==='operation_outcome_unknown'&&error.outcomeUnknown===true);await arrived;
  c.server.now+=1001;release();await rejected;assert.equal(c.server.effectCounts.record_send_start,1);assert.equal((await c.journal.load(p.start.request_id)).last.phase,'unknown');
});
test('manual handoff expiry is bounded by original email proof even when the live claim remains longer',async t=>{
  const c=await context(t);c.server.now+=299000;const p=await c.prepared(),start=await c.call('record_send_start',p.start);
  assert.equal(start.may_send,true);assert.equal(Date.parse(start.manual_handoff.valid_until),Date.parse(c.http.snapshot().emailVerifiedAt)+300000);
  assert.ok(Date.parse(start.manual_handoff.valid_until)<Date.parse(p.content.claim_expires_at));
});
for(const deadline of ['claim','confirmation','session'])test(`manual handoff also retains the original ${deadline} deadline`,async t=>{
  const c=await context(t);
  if(deadline==='session')c.server.current.expires=c.server.now+60000;
  if(deadline==='confirmation')c.server.transform=(action,value)=>action==='confirm'?{...value,expires_at:new Date(c.server.now+30000).toISOString()}:value;
  const p=await c.prepared(),before=c.http.snapshot(),start=await c.call('record_send_start',p.start);
  const expected=Math.min(Date.parse(p.content.claim_expires_at),Date.parse(p.confirmation.expires_at),Date.parse(before.user.expiresAt),Date.parse(before.emailVerifiedAt)+300000);
  assert.equal(start.may_send,true);assert.equal(Date.parse(start.manual_handoff.valid_until),expected);
});
test('a committed send-start response cannot adopt renewed email proof in the same public session',async t=>{
  const c=await context(t),p=await c.prepared(),before=c.http.snapshot();let entered,release;
  const arrived=new Promise(resolve=>entered=resolve);c.server.fault={action:'record_send_start',entered,gate:new Promise(resolve=>release=resolve)};
  const pending=c.call('record_send_start',p.start),rejected=assert.rejects(pending,error=>error.code==='operation_outcome_unknown'&&error.outcomeUnknown===true);await arrived;
  const original=(await c.journal.load(p.start.request_id)).intent;
  c.server.now+=1000;await c.server.reverify(c.http);assert.equal(c.session(),before.user.sessionId);release();await rejected;
  assert.equal(c.server.effectCounts.record_send_start,1);assert.equal((await c.journal.load(p.start.request_id)).last.phase,'unknown');
  assert.deepEqual((await c.journal.load(p.start.request_id)).intent,original);
  await assert.rejects(c.call('record_send_start',p.start),/original_operation_authority/);
  await assert.rejects(c.call('get_operation',{request_id:p.start.request_id}),/original_operation_authority/);
  assert.equal(c.server.counts.record_send_start,1);
});
for(const timing of ['response-after-new-login','response-after-new-email-proof','response-after-role-change','transient-read-failure-ABA'])test(`stale in-flight claim discarded: ${timing}`,async t=>{
  const c=await context(t);let entered,release;
  const enteredPromise=new Promise(resolve=>entered=resolve),gate=new Promise(resolve=>release=resolve);
  c.server.fault={action:'claim',gate,entered};const args={job_id:c.server.first.id,request_id:randomUUID(),worker_id:'synthetic-desktop',expected_fence:0};
  const pending=c.call('claim',args);const rejection=assert.rejects(pending,/operation_outcome_unknown/);await enteredPromise;
  if(timing==='response-after-new-login')await c.login();
  else if(timing==='response-after-new-email-proof'){c.server.now+=1000;await c.server.reverify(c.http);}
  else if(timing==='response-after-role-change'){c.server.current.role='admin';await c.http.refresh();}
  else {c.server.sessionFault=503;await assert.rejects(c.http.refresh(),/session_read_failed/);await c.http.refresh();}
  release();await rejection;assert.equal(c.server.effectCounts.claim,1);
  const current=c.http.snapshot();assert.ok(current);
  await assert.rejects(c.call('get_claimed',{job_id:c.server.first.id,claim_token:c.server.first.claim.token,fence_version:1}),/current_unexpired_claim/);
});
test('exact content hashes and human per-message authorization are required before send-start',async t=>{
  const c=await context(t),p=await c.prepared();
  await assert.rejects(c.call('record_send_start',{...p.start,manual_authorization:{...p.start.manual_authorization,user_authorized:false}}),/per_message_human/);
  assert.equal(c.server.counts.record_send_start,undefined);
  const next=c.server.addJob(),claimed=await c.claim(next);c.server.transform=(action,value)=>action==='get_claimed'?{...value,message_body:value.message_body+' changed'}:value;
  await assert.rejects(c.call('get_claimed',{job_id:next.id,claim_token:claimed.value.claim_token,fence_version:1}),/content_digest_mismatch/);
});
test('wrong server origin-session/public-session and fence receipts are not adopted',async t=>{
  const c=await context(t);c.server.transform=(action,value)=>action==='claim'?{...value,public_session_id:randomUUID()}:value;
  await assert.rejects(c.claim(),/operation_outcome_unknown/);assert.equal(c.server.effectCounts.claim,1);
  c.server.transform=null;const resolved=await c.call('get_operation',{request_id:[...c.server.receipts.keys()][0]});assert.equal(resolved.observed,true);
  const p={job_id:c.server.first.id,claim_token:resolved.receipt.claim_token,fence_version:1};await c.call('get_claimed',p);
  const other=c.server.addJob();c.server.transform=(action,value)=>action==='claim'?{...value,originating_session_id:randomUUID()}:value;
  await assert.rejects(c.claim(other),/operation_outcome_unknown/);
});
test('durable journals keep original request metadata but no cookie/password/email-code/CAPTCHA/plaintext/true permit',async t=>{
  const c=await context(t),p=await c.prepared();await c.call('record_send_start',p.start);
  let text='';for(const name of await readdir(c.journalDir))for(const item of await readdir(join(c.journalDir,name)))text+=await readFile(join(c.journalDir,name,item),'utf8');
  assert.ok(!text.includes(c.server.first.destination));assert.ok(!text.includes(c.server.first.body));assert.ok(!text.includes(c.server.password));assert.ok(!text.includes(c.server.code));
  for(const token of c.server.sessions.keys())assert.ok(!text.includes(token));assert.ok(!text.includes('"may_send":true'));assert.ok(!text.includes('manual_handoff'));
  const restarted=new OperatorClient({http:c.http,journal:new OperationJournal(c.journalDir),clock:()=>c.server.now});
  const repeat=await restarted.call('record_send_start',{operator_session:c.session(),...p.start});assert.equal(repeat.may_send,false);assert.equal(c.server.counts.record_send_start,1);
});
test('concurrent clients sharing one journal cannot both dispatch the same original UUID',async t=>{
  const c=await context(t),second=new OperatorClient({http:c.http,journal:new OperationJournal(c.journalDir),clock:()=>c.server.now});
  const args={operator_session:c.session(),job_id:c.server.first.id,request_id:randomUUID(),worker_id:'synthetic-desktop',expected_fence:0};
  const results=await Promise.allSettled([c.client.call('claim',args),second.call('claim',args)]);
  assert.equal(results.filter(result=>result.status==='fulfilled').length,1);assert.equal(c.server.counts.claim,1);assert.equal(c.server.effectCounts.claim,1);
});
test('controlled post-commit journal I/O failure cannot turn the real remote outcome into a known failure or permit',async t=>{
  const c=await context(t);let appended=0;
  const faulted={load:id=>c.journal.load(id),begin:args=>c.journal.begin(args),append:async(id,status)=>{appended++;if(appended>1){const error=new Error('controlled journal I/O failure');error.code='EIO';throw error;}return c.journal.append(id,status);}};
  const client=new OperatorClient({http:c.http,journal:faulted,clock:()=>c.server.now});
  const args={operator_session:c.session(),job_id:c.server.first.id,request_id:randomUUID(),worker_id:'synthetic-desktop',expected_fence:0};
  await assert.rejects(client.call('claim',args),error=>error.code==='operation_outcome_unknown_journal_unavailable'&&error.outcomeUnknown===true);
  assert.equal(c.server.effectCounts.claim,1);assert.equal((await c.journal.load(args.request_id)).last.phase,'unknown');
  await assert.rejects(client.call('claim',args),/resolve_original/);assert.equal(c.server.counts.claim,1);
  const resolution=await c.call('get_operation',{request_id:args.request_id});assert.equal(resolution.observed,true);assert.equal(resolution.receipt.replay,true);
});
test('private journal/file boundaries reject symlinks, public modes and altered hash chains',async t=>{
  const c=await context(t),claimed=await c.claim(),file=join(c.journalDir,claimed.args.request_id,'0001.json');
  await chmod(file,0o644);await assert.rejects(privateRead(file),/private_owned_regular/);await chmod(file,0o600);
  const raw=JSON.parse(await readFile(file));raw.args.worker_id='altered';await writeFile(file,canonical(raw)+'\n',{mode:0o600});
  await assert.rejects(c.journal.load(claimed.args.request_id),/operation_journal_integrity/);
  const link=join(c.dir,'alias');await symlink(c.journalDir,link);await assert.rejects(privateDirectory(link),/aliased_private/);
});
