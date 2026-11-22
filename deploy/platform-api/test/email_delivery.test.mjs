import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {sendTransactionalEmail,transactionalEmailAvailable} from '../src/email_delivery.js';

const message={to:'staff@example.com',subject:'Collect sign-in',text:'Synthetic message only'};

test('shared Cloudflare sender prefers AUTH_EMAIL and never silently falls back after an uncertain send',async()=>{
  const sent=[];let legacy=0;
  const env={AUTH_EMAIL_FROM:'login@collect.example',AUTH_EMAIL:{send:async value=>{sent.push(value);return {messageId:'controlled-id'};}},EMAIL:{send:async()=>{legacy++;return {messageId:'legacy'};}}};
  assert.equal(transactionalEmailAvailable(env),true);
  assert.deepEqual(await sendTransactionalEmail(env,message),{messageId:'controlled-id'});
  assert.deepEqual(sent[0].from,{email:'login@collect.example',name:'Collect'});assert.equal(legacy,0);
  env.AUTH_EMAIL.send=async()=>{throw new Error('private provider detail');};
  await assert.rejects(sendTransactionalEmail(env,message),e=>e.code==='email_unavailable'&&!e.message.includes('private provider'));
  assert.equal(legacy,0);
});

test('legacy Admin EMAIL binding retains Collect sender identity',async()=>{
  let sent;await sendTransactionalEmail({EMAIL:{send:async value=>{sent=value;return {messageId:'legacy-id'};}}},message);
  assert.deepEqual(sent.from,{email:'info@ikanisa.com',name:'Collect'});
});

test('local simulators, missing sender, malformed messages and missing acknowledgements fail closed',async()=>{
  let calls=0;const binding={send:async()=>{calls++;return {messageId:'id'};}};
  for(const env of [{AUTH_EMAIL:binding},{AUTH_EMAIL:binding,AUTH_EMAIL_FROM:'bad\r\nsender'},{EMAIL:binding,ENVIRONMENT:'local'},{EMAIL:binding,APP_ENVIRONMENT:'local'},{}]){
    assert.equal(transactionalEmailAvailable(env),false);
    await assert.rejects(sendTransactionalEmail(env,message),e=>e.code==='email_unavailable');
  }
  assert.equal(calls,0);
  for(const ack of [undefined,{}, {messageId:''},{messageId:'x'.repeat(257)},{messageId:'id\nprivate'}])
    await assert.rejects(sendTransactionalEmail({EMAIL:{send:async()=>ack}},message),e=>e.code==='email_unavailable');
  await assert.rejects(sendTransactionalEmail({EMAIL:binding},{...message,subject:'header\r\ninjection'}));assert.equal(calls,0);
});


test('the canonical default dev command overrides production vars before a simulated binding can send',async()=>{
  const config=JSON.parse(await readFile(new URL('../wrangler.jsonc',import.meta.url),'utf8'));
  const pkg=JSON.parse(await readFile(new URL('../package.json',import.meta.url),'utf8'));
  const overrides=Object.fromEntries([...pkg.scripts.dev.matchAll(/--var ([A-Z_]+):([a-z]+)/g)].map(match=>[match[1],match[2]]));
  let sent=0;const env={...config.vars,...overrides,AUTH_EMAIL:{send:async()=>{sent++;return {messageId:'unexpected'};}}};
  assert.equal(env.APP_ENVIRONMENT,'local');assert.equal(env.ENVIRONMENT,'local');
  await assert.rejects(sendTransactionalEmail(env,message),e=>e.code==='email_unavailable');assert.equal(sent,0);
});
