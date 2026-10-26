import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn,fork} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {mkdtemp,chmod,readFile,writeFile,rename,mkdir,symlink} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {PassThrough} from 'node:stream';
import {serveMcp,MODERN,LEGACY,unconfiguredClient,TOOLS} from '../src/mcp.mjs';
import {sha} from '../src/contract.mjs';
import {readConfig} from '../src/broker.mjs';
import {privateTestRoot} from './private_test_root.mjs';

const NODE='/Volumes/PRO-G40/Development/Node/bin/node',ROOT=await privateTestRoot(),BIN=resolve(import.meta.dirname,'../bin/mcp.mjs');
const META={'io.modelcontextprotocol/protocolVersion':MODERN,'io.modelcontextprotocol/clientCapabilities':{}};
const delay=milliseconds=>new Promise(resolve=>setTimeout(resolve,milliseconds));
function protocolPeer(input,output) {
  let pending='',next=0;const messages=[],waiters=new Map();
  output.on('data',chunk=>{
    pending+=chunk.toString('utf8');for(let index;(index=pending.indexOf('\n'))>=0;){const line=pending.slice(0,index);pending=pending.slice(index+1);const message=JSON.parse(line);messages.push(message);const waiter=waiters.get(message.id);if(waiter){clearTimeout(waiter.timer);waiters.delete(message.id);waiter.resolve(message);}}
  });
  const send=value=>input.write(JSON.stringify(value)+'\n');
  const query=(method,params={},options={})=>{
    const id=options.id??++next;
    const result=new Promise((resolve,reject)=>{const timer=setTimeout(()=>{waiters.delete(id);reject(new Error('protocol_test_timeout'));},3000);waiters.set(id,{resolve,reject,timer});});
    send({jsonrpc:'2.0',id,method,params:options.legacy?params:{...params,_meta:META}});return result;
  };
  return {send,query,messages,raw:value=>input.write(value),cancel:id=>send({jsonrpc:'2.0',method:'notifications/cancelled',params:{requestId:id}})};
}
function local(t,client=unconfiguredClient()) {
  const input=new PassThrough(),output=new PassThrough(),server=serveMcp({client,input,output});t.after(()=>server.close());return protocolPeer(input,output);
}
async function actual(t) {
  const stateDir=await mkdtemp(join(ROOT,'broker-'));await chmod(stateDir,0o700);
  const child=fork(resolve(import.meta.dirname,'broker_fixture_child.mjs'),[stateDir],{execPath:NODE,stdio:['ignore','pipe','pipe','ipc'],env:{PATH:'/usr/bin:/bin'}});
  let childStderr='';child.stderr.on('data',chunk=>childStderr+=chunk.toString());const events=[],controls=new Map();let count=0;
  const ready=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('broker_test_start_timeout:'+childStderr)),5000);child.on('message',value=>{events.push(value);if(value.event==='ready'){clearTimeout(timer);resolve(value);}if(value.id&&controls.has(value.id)){const item=controls.get(value.id);clearTimeout(item.timer);controls.delete(value.id);item.resolve(value);}});});
  const control=(command,extra={})=>new Promise((resolve,reject)=>{const id=++count,timer=setTimeout(()=>reject(new Error('fixture_control_timeout')),3000);controls.set(id,{resolve,timer});child.send({id,command,...extra});});
  const info=await ready;
  const mcp=spawn(NODE,[BIN,'--state-dir',stateDir,'--descriptor-sha256',info.descriptor.descriptor_sha256],{stdio:['pipe','pipe','pipe'],env:{PATH:'/usr/bin:/bin'}});
  let stderr='';mcp.stderr.on('data',chunk=>stderr+=chunk.toString());
  const peer=protocolPeer(mcp.stdin,mcp.stdout),session=info.descriptor.operator_session;
  t.after(async()=>{mcp.stdin.end();await new Promise(resolve=>{if(mcp.exitCode!==null||mcp.signalCode!==null)return resolve();mcp.once('exit',resolve);setTimeout(()=>mcp.kill('SIGKILL'),1000).unref();});if(child.connected)await control('close').catch(()=>{});if(child.exitCode===null&&child.signalCode===null)child.kill('SIGTERM');});
  const tool=async(action,args={})=>(await peer.query('tools/call',{name:'collect_operator_'+action,arguments:{operator_session:session,...args}})).result;
  async function prepared(){
    const claimArgs={job_id:info.jobs[0],request_id:randomUUID(),worker_id:'synthetic-mcp',expected_fence:0};
    const claim=(await tool('claim',claimArgs)).structuredContent,base={job_id:claim.job_id,claim_token:claim.claim_token,fence_version:claim.fence_version};
    const content=(await tool('get_claimed',base)).structuredContent;
    const confirm={...base,request_id:randomUUID(),confirmation_id:randomUUID(),body_sha256:content.body_sha256,destination_sha256:content.destination_sha256,destination_revision:content.destination_revision,user_confirmation:true};
    assert.equal((await tool('confirm',confirm)).isError,false);
    return {claim,base,content,confirm,start:{...base,request_id:randomUUID(),confirmation_id:confirm.confirmation_id,manual_authorization:{user_authorized:true,authorization_reference_sha256:sha('synthetic explicit human instruction')}}};
  }
  return {stateDir,child,mcp,peer,tool,control,events,info,session,prepared,stderr:()=>stderr};
}
test('modern stateless discovery and eight bounded tool schemas expose unconfigured state honestly',async t=>{
  const peer=local(t);const discovery=await peer.query('server/discover');
  assert.equal(discovery.result.resultType,'complete');assert.ok(discovery.result.supportedVersions.includes(MODERN));assert.equal(discovery.result._meta['com.ikanisa.collect/operator'].authentication_state,'unconfigured');
  const list=(await peer.query('tools/list')).result;assert.equal(list.tools.length,8);assert.deepEqual(list.tools,TOOLS);
  for(const tool of list.tools){assert.equal(tool.inputSchema.additionalProperties,false);assert.ok(tool.inputSchema.required.includes('operator_session'));assert.ok(!/password|captcha|email_code|totp|factor_id/.test(JSON.stringify(tool.inputSchema)));}
  const failed=(await peer.query('tools/call',{name:'collect_operator_list_pending',arguments:{operator_session:randomUUID()}})).result;
  assert.equal(failed.isError,true);assert.equal(failed.structuredContent.error.code,'authenticated_session_broker_unconfigured');assert.equal(failed.structuredContent.may_send,false);
});
test('modern metadata/version enforcement has no connection identity as authority',async t=>{
  const peer=local(t);
  const missing=await peer.query('tools/list',{}, {legacy:true});assert.equal(missing.error.code,-32602);
  peer.send({jsonrpc:'2.0',id:'unsupported',method:'server/discover',params:{_meta:{...META,'io.modelcontextprotocol/protocolVersion':'2099-01-01'}}});await delay(10);
  const unsupported=peer.messages.find(message=>message.id==='unsupported');assert.equal(unsupported.error.code,-32022);assert.deepEqual(unsupported.error.data.supported,[MODERN,LEGACY]);
  peer.send({jsonrpc:'2.0',id:'missing-caps',method:'ping',params:{_meta:{'io.modelcontextprotocol/protocolVersion':MODERN}}});await delay(10);assert.equal(peer.messages.find(message=>message.id==='missing-caps').error.code,-32602);
  assert.equal((await peer.query('ping')).result.resultType,'complete');
});
test('legacy initialize/initialized path works independently and does not authorize a session',async t=>{
  const peer=local(t),init=await peer.query('initialize',{protocolVersion:LEGACY,capabilities:{},clientInfo:{name:'synthetic',version:'1'}},{legacy:true});
  assert.equal(init.result.protocolVersion,LEGACY);
  assert.equal((await peer.query('tools/list',{}, {legacy:true})).error.code,-32602);
  peer.send({jsonrpc:'2.0',method:'notifications/initialized'});
  assert.equal((await peer.query('tools/list',{}, {legacy:true})).result.tools.length,8);
  assert.equal((await peer.query('initialize',{protocolVersion:LEGACY,capabilities:{},clientInfo:{}},{legacy:true})).error.code,-32600);
});
test('legacy negotiation returns its supported version for a different client version, while malformed client identity is refused',async t=>{
  const peer=local(t);const negotiated=await peer.query('initialize',{protocolVersion:'2024-11-05',capabilities:{},clientInfo:{name:'synthetic',version:'1'}},{legacy:true});
  assert.equal(negotiated.result.protocolVersion,LEGACY);
  const malformed=local(t);assert.equal((await malformed.query('initialize',{protocolVersion:LEGACY,capabilities:{},clientInfo:{}},{legacy:true})).error.code,-32602);
});
test('JSON-RPC framing rejects batches, invalid UTF8, malformed messages and unsupported method without leaking exceptions',async t=>{
  const peer=local(t);peer.raw('[{"jsonrpc":"2.0","id":1,"method":"ping"}]\n');peer.raw(Buffer.from([0xc3,0x28,0x0a]));peer.raw('{broken}\n');peer.send({jsonrpc:'2.0',id:1,result:{},method:'ping'});
  await delay(10);assert.deepEqual(peer.messages.map(message=>message.error.code),[-32600,-32700,-32700,-32600]);
  assert.equal((await peer.query('arbitrary/fetch',{url:'https://example.invalid'})).error.code,-32601);
  assert.equal((await peer.query('tools/call',{name:'unknown',arguments:{}})).error.code,-32602);
});
test('cancellation and duplicate in-flight IDs produce no late tool result or second dispatch',async t=>{
  let entered,release,calls=0;const gate=new Promise(resolve=>release=resolve),start=new Promise(resolve=>entered=resolve);
  const peer=local(t,{metadata:()=>({}),call:async(_action,_args,{signal})=>{calls++;entered();await gate;if(signal.aborted)throw new Error('cancelled');return {ok:true};}});
  peer.send({jsonrpc:'2.0',id:'cancel-me',method:'tools/call',params:{_meta:META,name:'collect_operator_list_pending',arguments:{operator_session:randomUUID()}}});
  await start;peer.cancel('cancel-me');release();await delay(10);assert.ok(!peer.messages.some(message=>message.id==='cancel-me'));assert.equal(calls,1);
  let unblock;const pending=new Promise(resolve=>unblock=resolve);let secondStart;const secondReady=new Promise(resolve=>secondStart=resolve);
  const other=local(t,{metadata:()=>({}),call:async(_a,_b,{signal})=>{calls++;secondStart();await pending;return {aborted:signal.aborted};}});
  const request={jsonrpc:'2.0',id:9,method:'tools/call',params:{_meta:META,name:'collect_operator_list_pending',arguments:{operator_session:randomUUID()}}};
  other.send(request);await secondReady;other.send(request);unblock();await delay(10);assert.equal(other.messages.length,1);assert.equal(other.messages[0].error.code,-32600);assert.equal(calls,2);
});
test('actual private Unix socket -> MCP child stdio -> authenticated HTTP preserves one session and one permit',async t=>{
  const c=await actual(t);const metadata=(await c.peer.query('server/discover')).result._meta['com.ikanisa.collect/operator'];assert.equal(metadata.operator_session,c.session);
  const queue=await c.tool('list_pending');assert.equal(queue.isError,false);const p=await c.prepared();
  const start=await c.tool('record_send_start',p.start);assert.equal(start.isError,false);assert.equal(start.structuredContent.may_send,true);assert.equal(start.structuredContent.manual_handoff.mode,'manual_mac_messages');
  const duplicate=await c.tool('record_send_start',p.start);assert.equal(duplicate.structuredContent.may_send,false);assert.equal(duplicate.structuredContent.manual_handoff,undefined);
  const resolved=await c.tool('get_operation',{request_id:p.start.request_id});assert.equal(resolved.structuredContent.receipt.may_send,false);
  const outcome=await c.tool('record_outcome',{request_id:randomUUID(),attempt_id:start.structuredContent.attempt_id,observation:'uncertain',evidence_reference_sha256:sha('synthetic uncertain observation')});assert.equal(outcome.structuredContent.delivery_confirmed,false);
  const claim=(await c.tool('claim',{job_id:c.info.jobs[1],request_id:randomUUID(),worker_id:'synthetic-mcp',expected_fence:0})).structuredContent;
  assert.equal((await c.tool('release_claim',{job_id:claim.job_id,claim_token:claim.claim_token,fence_version:claim.fence_version,request_id:randomUUID()})).isError,false);
  assert.equal((await c.control('stats')).counts.record_send_start,1);assert.equal(c.stderr(),'');
});
test('actual committed lost start response through socket/stdio yields only unknown then false resolution',async t=>{
  const c=await actual(t),p=await c.prepared();await c.control('fault_after',{action:'record_send_start'});
  const unknown=await c.tool('record_send_start',p.start);assert.equal(unknown.isError,true);assert.equal(unknown.structuredContent.error.outcome_unknown,true);
  assert.equal((await c.tool('record_send_start',{...p.start,resume_original_request:true})).isError,true);
  const resolved=await c.tool('get_operation',{request_id:p.start.request_id});assert.equal(resolved.structuredContent.receipt.may_send,false);
  assert.equal((await c.tool('record_send_start',p.start)).structuredContent.may_send,false);assert.equal((await c.control('stats')).counts.record_send_start,1);
});
test('MCP process loss after actual start commit preserves the broker original session; explicit new process resolves false without reauth/resend',async t=>{
  const c=await actual(t),p=await c.prepared();await c.control('hold',{action:'record_send_start'});
  c.peer.send({jsonrpc:'2.0',id:'lost-process',method:'tools/call',params:{_meta:META,name:'collect_operator_record_send_start',arguments:{operator_session:c.session,...p.start}}});
  for(let i=0;i<100&&!c.events.some(value=>value.event==='entered');i++)await delay(10);assert.ok(c.events.some(value=>value.event==='entered'));
  const exited=new Promise(resolve=>c.mcp.once('exit',resolve));c.mcp.kill('SIGTERM');await exited;await c.control('release');
  const successor=spawn(NODE,[BIN,'--state-dir',c.stateDir,'--descriptor-sha256',c.info.descriptor.descriptor_sha256],{stdio:['pipe','pipe','pipe'],env:{PATH:'/usr/bin:/bin'}});
  t.after(async()=>{successor.stdin.end();await new Promise(resolve=>{if(successor.exitCode!==null||successor.signalCode!==null)return resolve();successor.once('exit',resolve);setTimeout(()=>successor.kill('SIGKILL'),1000).unref();});});
  let stderr='';successor.stderr.on('data',chunk=>stderr+=chunk.toString());const peer=protocolPeer(successor.stdin,successor.stdout);
  const metadata=(await peer.query('server/discover')).result._meta['com.ikanisa.collect/operator'];assert.equal(metadata.operator_session,c.session);
  const response=await peer.query('tools/call',{name:'collect_operator_get_operation',arguments:{operator_session:c.session,request_id:p.start.request_id}});
  assert.equal(response.result.isError,false);assert.equal(response.result.structuredContent.receipt.may_send,false);assert.equal(response.result.structuredContent.receipt.originating_session_id,p.claim.originating_session_id);
  const stats=await c.control('stats');assert.equal(stats.counts.record_send_start,1);assert.equal(stats.counts['/api/admin/auth/otp'],1);assert.equal(stats.counts['/api/admin/auth/verify'],1);assert.equal(stats.counts['/api/admin/auth/login'],undefined);assert.equal(stats.counts['/api/admin/auth/mfa/verify'],undefined);assert.equal(stderr,'');
});
test('actual broker rejects a different requested session and a replaced authenticated session without adoption',async t=>{
  const c=await actual(t);const wrong=(await c.peer.query('tools/call',{name:'collect_operator_list_pending',arguments:{operator_session:randomUUID()}})).result;
  assert.equal(wrong.isError,true);assert.equal((await c.control('stats')).counts.list_pending,undefined);
  await c.control('login');const stale=await c.tool('list_pending');assert.equal(stale.isError,true);assert.equal(stale.structuredContent.error.code,'broker_session_replaced');
});
test('same-session email proof renewal over private IPC cannot adopt old claims or operation authority',async t=>{
  const c=await actual(t),p=await c.prepared();assert.equal((await c.control('reverify')).ok,true);
  const metadata=(await c.peer.query('server/discover')).result._meta['com.ikanisa.collect/operator'];assert.equal(metadata.operator_session,c.session);
  const start=await c.tool('record_send_start',p.start);assert.equal(start.isError,true);assert.equal(start.structuredContent.may_send,false);
  assert.equal(start.structuredContent.error.code,'current_unexpired_claim_required');
  const prior=await c.tool('get_operation',{request_id:p.confirm.request_id});assert.equal(prior.isError,true);assert.equal(prior.structuredContent.error.code,'original_operation_authority_required');
  const stats=await c.control('stats');assert.equal(stats.counts.record_send_start,undefined);assert.equal(stats.counts['/api/admin/auth/email/request'],1);assert.equal(stats.counts['/api/admin/auth/email/verify'],1);
});
test('same-session proof renewal while a real start response is held never yields a handoff or second start',async t=>{
  const c=await actual(t),p=await c.prepared();await c.control('hold',{action:'record_send_start'});
  const result=c.tool('record_send_start',p.start);
  for(let i=0;i<100&&!c.events.some(value=>value.event==='entered');i++)await delay(10);assert.ok(c.events.some(value=>value.event==='entered'));
  assert.equal((await c.control('reverify')).ok,true);await c.control('release');
  const refused=await result;assert.equal(refused.isError,true);assert.equal(refused.structuredContent.error.outcome_unknown,true);assert.equal(refused.structuredContent.may_send,false);assert.equal(refused.structuredContent.manual_handoff,undefined);
  assert.equal((await c.tool('record_send_start',p.start)).isError,true);
  const stats=await c.control('stats');assert.equal(stats.counts.record_send_start,1);assert.equal(stats.effects.record_send_start,1);
});
test('GET-only original-operation recovery cannot clear unknown verification with old proof or adopt newer proof',async t=>{
  const c=await actual(t),p=await c.prepared();assert.equal((await c.control('unknown_verify_old_readback')).ok,true);
  const unresolved=await c.tool('get_operation',{request_id:p.confirm.request_id});assert.equal(unresolved.isError,true);assert.equal(unresolved.structuredContent.may_send,false);
  assert.equal(unresolved.structuredContent.error.code,'recent_email_sign_in_required');
  assert.equal((await c.control('stats')).counts.get_operation,undefined);
  assert.equal((await c.control('reveal_current_proof')).ok,true);
  const renewed=await c.tool('get_operation',{request_id:p.confirm.request_id});assert.equal(renewed.isError,true);assert.equal(renewed.structuredContent.error.code,'original_operation_authority_required');
  const start=await c.tool('record_send_start',p.start);assert.equal(start.isError,true);assert.equal(start.structuredContent.may_send,false);
  const stats=await c.control('stats');assert.equal(stats.counts.get_operation,1);assert.equal(stats.counts.record_send_start,undefined);assert.equal(stats.counts['/api/admin/auth/email/request'],1);assert.equal(stats.counts['/api/admin/auth/email/verify'],1);
});
test('descriptor inode replacement and widened socket modes refuse before authenticated HTTP dispatch',async t=>{
  const c=await actual(t);await c.peer.query('server/discover');await chmod(join(c.stateDir,'operator.sock'),0o666);
  const insecure=await c.tool('list_pending');assert.equal(insecure.isError,true);assert.equal((await c.control('stats')).counts.list_pending,undefined);
  await chmod(join(c.stateDir,'operator.sock'),0o600);
  const path=join(c.stateDir,'broker.json'),raw=await readFile(path);await rename(path,path+'.preimage');await writeFile(path,raw,{mode:0o600});
  const replaced=await c.tool('list_pending');assert.equal(replaced.isError,true);assert.equal(replaced.structuredContent.error.code,'broker_descriptor_replaced');
  assert.equal((await c.control('stats')).counts.list_pending,undefined);
});
test('cancel an actually committed HTTP write through MCP: no result, no resend and original readback only',async t=>{
  const c=await actual(t);await c.control('hold',{action:'claim'});const args={operator_session:c.session,job_id:c.info.jobs[0],request_id:randomUUID(),worker_id:'synthetic-mcp',expected_fence:0};
  c.peer.send({jsonrpc:'2.0',id:'live-cancel',method:'tools/call',params:{_meta:META,name:'collect_operator_claim',arguments:args}});
  for(let i=0;i<100&&!c.events.some(value=>value.event==='entered');i++)await delay(10);assert.ok(c.events.some(value=>value.event==='entered'));
  c.peer.cancel('live-cancel');await c.control('release');await delay(30);assert.ok(!c.peer.messages.some(message=>message.id==='live-cancel'));
  const resolved=await c.tool('get_operation',{request_id:args.request_id});assert.equal(resolved.isError,false,JSON.stringify(resolved.structuredContent));assert.equal(resolved.structuredContent.observed,true);assert.equal((await c.control('stats')).counts.claim,1);
});
test('stdio EOF exits promptly and broker loss never reconnects or changes authority',async t=>{
  const c=await actual(t);await c.peer.query('server/discover');await c.control('close');await delay(10);
  const failed=await c.tool('list_pending');assert.equal(failed.isError,true);assert.equal(failed.structuredContent.error.code,'broker_reconnection_refused');
  const metadata=(await c.peer.query('server/discover')).result._meta['com.ikanisa.collect/operator'];assert.equal(metadata.authentication_state,'broker_disconnected');
  c.mcp.stdin.end();await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('EOF did not exit')),1000);c.mcp.once('exit',()=>{clearTimeout(timer);resolve();});});
});
test('explicit config digest/origin/permission guards have no primary-stage fallback or symlink shortcut',async()=>{
  const dir=await mkdtemp(join(ROOT,'configuration-'));await chmod(dir,0o700);const path=join(dir,'config.json');
  const write=async value=>{const raw=Buffer.from(JSON.stringify(value));await writeFile(path,raw,{mode:0o600});return sha(raw);};
  let digest=await write({format:'collect.operator.client-config.v1',enabled:true,origin:'https://platform-admin.collect.ikanisa.com'});assert.equal((await readConfig(path,digest)).enabled,true);
  await assert.rejects(readConfig(path,'0'.repeat(64)),/reviewed_configuration_digest/);
  digest=await write({format:'collect.operator.client-config.v1',enabled:true,origin:'https://api.collect.ikanisa.com'});await assert.rejects(readConfig(path,digest),/independently_approved/);
  digest=await write({format:'collect.operator.client-config.v1',enabled:false,origin:'https://platform-admin.collect.ikanisa.com'});await assert.rejects(readConfig(path,digest),/independently_approved/);
  await chmod(path,0o644);await assert.rejects(readConfig(path,digest),/private_owned_regular/);await chmod(path,0o600);
  const alias=join(dir,'aliased');await symlink(dir,alias);await assert.rejects(readConfig(join(alias,'config.json'),digest),/aliased_private/);
});
