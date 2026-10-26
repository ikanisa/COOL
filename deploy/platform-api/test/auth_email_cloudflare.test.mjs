import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './support/auth_fixture.mjs';

test('Cloudflare sends a private member code without requiring or contacting the WhatsApp relay',async t=>{
  const sent=[];
  const f=await fixture({AUTH_EMAIL_DELIVERY:'cloudflare',AUTH_EMAIL_FROM:'login@collect.example',OTP_DELIVERY_TOKEN:'',OTP_DELIVERY_URL:''},
    {emailBinding:true,outbound:async request=>{
      if(request.url!=='https://cloudflare-email.test/send')return null;
      sent.push(await request.json());return Response.json({messageId:randomUUID()});
    }});
  t.after(()=>f.close());
  const otp=await f.otp({email:'Member@Example.com'});assert.equal(otp.status,202,JSON.stringify(otp.body));
  assert.equal(sent.length,1);assert.equal(sent[0].to,'member@example.com');assert.deepEqual(sent[0].from,{email:'login@collect.example',name:'Collect'});
  const code=sent[0].text.match(/code is ([0-9]{6})/)[1];assert.ok(code);
  assert.ok(!JSON.stringify(otp.body).includes(code));
  const session=await f.call('/v1/auth/verify',{email:'member@example.com',code,challenge_id:otp.body.challenge_id,captcha_token:randomUUID()});
  assert.equal(session.status,200,JSON.stringify(session.body));assert.equal(session.body.user.email,'member@example.com');
  assert.equal((await f.actor(session.body)).body.surface,'member');
  assert.equal((await f.call('/v1/auth/verify',{email:'member@example.com',code,challenge_id:otp.body.challenge_id,captcha_token:randomUUID()})).status,401);
  assert.equal(f.trace.filter(r=>r.url==='https://trusted-relay.example/otp').length,0);
});

test('lost Cloudflare acknowledgement retains an actually delivered code and applies the cooldown',async t=>{
  let message;
  const f=await fixture({AUTH_EMAIL_DELIVERY:'cloudflare',AUTH_EMAIL_FROM:'login@collect.example'},
    {emailBinding:true,outbound:async request=>{
      if(request.url!=='https://cloudflare-email.test/send')return null;
      message=await request.json();return Response.json({});
    }});
  t.after(()=>f.close());
  const otp=await f.otp({email:'member@example.com'});assert.equal(otp.status,503);assert.equal(otp.body.error.code,'otp_delivery_unknown');
  assert.equal((await f.otp({email:'member@example.com'})).status,429);
  const code=message.text.match(/code is ([0-9]{6})/)[1];
  assert.equal((await f.call('/v1/auth/verify',{email:'member@example.com',code,challenge_id:otp.body.challenge_id,captcha_token:randomUUID()})).status,200);
});

test('missing Cloudflare binding or invalid sender fails before admitting a code request',async t=>{
  const f=await fixture({AUTH_EMAIL_DELIVERY:'cloudflare',AUTH_EMAIL_FROM:'bad\r\naddress'});t.after(()=>f.close());
  assert.equal((await f.otp({email:'member@example.com'})).status,503);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM auth_otp_challenges').first()).n,0);
});
