import {syntheticPasswordProof} from './human_fixture.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtemp,mkdir,chmod,readFile,writeFile,readdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {AdminHttp} from '../src/http_client.mjs';
import {OperatorClient} from '../src/operator_client.mjs';
import {OperationJournal,privateRead,privateWrite} from '../src/private_state.mjs';
import {ORIGINS,MARKER,receipt,request,sha} from '../src/contract.mjs';
import {fixture} from './http_fixture.mjs';
import {privateTestRoot} from './private_test_root.mjs';
const ROOT=await privateTestRoot();

test('HTTP redirects, non-JSON, oversized and malformed UTF8 bodies never become authentication or operation results',async()=>{
  for(const response of [
    new Response('{}',{status:302,headers:{Location:'https://example.invalid','Content-Type':'application/json'}}),
    new Response('<html>',{headers:{'Content-Type':'text/html'}}),
    new Response(' '.repeat(262145),{headers:{'Content-Type':'application/json'}}),
    new Response(Buffer.from([0xc3,0x28]),{headers:{'Content-Type':'application/json'}}),
  ]) {
    let calls=0;const http=new AdminHttp({origin:ORIGINS[0],fetchImpl:async(_url,options)=>{calls++;assert.equal(options.redirect,'manual');return response;}});
    await assert.rejects(http.refresh());assert.equal(calls,1);assert.equal(http.snapshot(),null);
  }
});
test('login refuses bearer/internal-token substitution and insecure, ambiguous or domain-scoped cookies',async()=>{
  const badCookies=[null,'__Host-collect_admin=not-a-token; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=3600',
    `__Host-collect_admin=${'a'.repeat(64)}; Path=/; HttpOnly; SameSite=Strict; Max-Age=3600`,
    `__Host-collect_admin=${'a'.repeat(64)}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=3600; Domain=collect.ikanisa.com`];
  for(const cookie of badCookies) {
    const headers=new Headers({'Content-Type':'application/json'});if(cookie)headers.append('Set-Cookie',cookie);
    const http=new AdminHttp({origin:ORIGINS[0],fetchImpl:async()=>new Response(JSON.stringify({access_token:'synthetic-unacceptable-token',user:{}}),{headers})});
    await assert.rejects(http.signIn('synthetic@example.invalid','synthetic-password',await syntheticPasswordProof()),/auth_cookie/);assert.equal(http.snapshot(),null);
  }
  const headers=new Headers({'Content-Type':'application/json'});
  for(const token of ['a','b'])headers.append('Set-Cookie',`__Host-collect_admin=${token.repeat(64)}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=3600`);
  const http=new AdminHttp({origin:ORIGINS[0],fetchImpl:async()=>new Response('{}',{headers})});await assert.rejects(http.signIn('synthetic@example.invalid','synthetic-password',await syntheticPasswordProof()),/ambiguous/);
});
test('strict action/DTO validators reject caller authority, missing cursor pair and invented financial/delivery semantics',()=>{
  for(const action of ['arbitrary_fetch','enqueue','enroll','send_sms'])assert.throws(()=>request(action,{}),/unsupported_action/);
  assert.throws(()=>request('list_pending',{after_job_id:randomUUID()}),/incomplete_cursor/);
  assert.throws(()=>request('list_pending',{operator_id:randomUUID()}),/unsupported_or_missing/);
  assert.throws(()=>request('get_operation',{request_id:randomUUID(),originating_session_id:randomUUID()}),/unsupported_or_missing/);
  assert.throws(()=>receipt('record_outcome',{...MARKER,attempt_id:randomUUID(),observation:'observed_sent',evidence_reference_sha256:sha('synthetic'),may_send:false,delivery_confirmed:true}),/wrong_semantic_marker/);
  assert.throws(()=>receipt('record_send_start',{...MARKER,job_id:randomUUID(),claim_token:randomUUID(),fence_version:1,attempt_id:randomUUID(),confirmation_id:randomUUID(),state:'send_started',originating_session_id:randomUUID(),public_session_id:randomUUID(),replay:true,may_send:true,acknowledgement:'first_committed_response_only'}),/reissued_permit/);
});
test('password compatibility session cannot mint proof; wrong email code keeps the session without operating effects',async t=>{
  const server=await fixture();t.after(()=>server.close());const http=new AdminHttp({origin:ORIGINS[0],fetchImpl:server.fetch,clock:()=>server.now});
  const session=await http.signIn('synthetic@example.invalid',server.password,await server.passwordProof());
  assert.equal(session.emailVerifiedAt,null);assert.equal(session.user.assuranceLevel,1);
  await assert.rejects(http.ensure(session.user.sessionId,'assisted_sms.manage'),/recent_email_sign_in_required/);
  const challenge=await http.requestEmailVerification(await server.emailProof('sensitive'));
  await assert.rejects(http.verifyEmail(challenge.challenge_id,'000000'),e=>e.code==='invalid_credentials'&&!e.outcomeUnknown);
  assert.equal(http.snapshot().user.sessionId,session.user.sessionId);assert.equal(server.counts.claim,undefined);assert.equal(server.counts['/api/admin/auth/logout'],undefined);
});
test('an aborted original write stays unknown until real readback; no retry on transport timeout',async t=>{
  const server=await fixture();t.after(()=>server.close());const http=new AdminHttp({origin:ORIGINS[0],fetchImpl:server.fetch,clock:()=>server.now,timeoutMs:100});
  await server.login(http);
  const dir=await mkdtemp(join(ROOT,'timeout-'));await chmod(dir,0o700);const journal=new OperationJournal(dir),client=new OperatorClient({http,journal,clock:()=>server.now});
  let entered,release;const reached=new Promise(resolve=>entered=resolve);server.fault={action:'claim',entered,gate:new Promise(resolve=>release=resolve)};
  const args={operator_session:http.snapshot().user.sessionId,job_id:server.first.id,request_id:randomUUID(),worker_id:'synthetic-timeout',expected_fence:0};
  const pending=client.call('claim',args);const rejected=assert.rejects(pending,/operation_outcome_unknown/);await reached;await rejected;release();
  assert.equal(server.counts.claim,1);assert.equal(server.effectCounts.claim,1);assert.equal((await journal.load(args.request_id)).last.phase,'unknown');
  const result=await client.call('get_operation',{operator_session:args.operator_session,request_id:args.request_id});assert.equal(result.observed,true);assert.equal(server.counts.claim,1);
});
test('private state refuses hard links/partial original intents and never overwrites an existing record',async()=>{
  const dir=await mkdtemp(join(ROOT,'state-boundary-'));await chmod(dir,0o700);const file=join(dir,'one.json');await privateWrite(file,{public_test:true});
  await assert.rejects(privateWrite(file,{public_test:false}),/EEXIST/);assert.equal(JSON.parse((await privateRead(file)).raw).public_test,true);
  const {link}=await import('node:fs/promises');await link(file,join(dir,'hard-link.json'));await assert.rejects(privateRead(file),/private_owned_regular/);
  const journalDir=join(dir,'operations');await mkdir(journalDir,{mode:0o700});const id=randomUUID();await mkdir(join(journalDir,id),{mode:0o700});
  const journal=new OperationJournal(journalDir);await assert.rejects(journal.load(id),/incomplete_operation_journal/);
});

test('wrong successful HTTP status on protected send is unknown and never yields a usable challenge',async t=>{
  const server=await fixture();t.after(()=>server.close());
  const http=new AdminHttp({origin:ORIGINS[0],clock:()=>server.now,fetchImpl:async(url,options)=>{const response=await server.fetch(url,options);return url.endsWith('/auth/email/request')?new Response(await response.arrayBuffer(),{status:200,headers:response.headers}):response;}});
  const before=await server.login(http);await assert.rejects(http.requestEmailVerification(await server.emailProof('sensitive')),e=>e.code==='unexpected_response_status'&&e.outcomeUnknown);
  assert.equal(http.snapshot().user.sessionId,before.user.sessionId);assert.equal(server.counts['/api/admin/auth/email/request'],1);assert.equal(server.counts['/api/admin/auth/email/verify'],undefined);
});
test('refresh lease409 recovery is bounded and never retries an operating POST',async t=>{
  const server=await fixture();t.after(()=>server.close());let refuse=false;
  const http=new AdminHttp({origin:ORIGINS[0],clock:()=>server.now,fetchImpl:async(url,options)=>refuse&&url.endsWith('/auth/session')?Response.json({error:{code:'session_refresh_pending'}},{status:409}):server.fetch(url,options)});
  await server.login(http);refuse=true;let reads=0;
  const wrapped=new AdminHttp({origin:ORIGINS[0],fetchImpl:async()=>{reads++;return Response.json({error:{code:'session_refresh_pending'}},{status:409});}});
  await assert.rejects(wrapped.refresh(),{code:'session_refresh_pending'});assert.equal(reads,2);
  await assert.rejects(http.ensure(http.snapshot().user.sessionId,'assisted_sms.manage'),{code:'session_refresh_pending'});assert.equal(server.counts.claim,undefined);
});
