import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createAdminWorker} from '../src/index.js';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';

const profile = {format:'collect.deployment.v1',id:'collect-private-test',mode:'self_hosted',environment:'production',
  supabase_origin:'https://supabase.example.test',member_api_origin:'https://api.example.test',
  admin_origin:'https://admin.example.test',public_origin:'https://collect.example.test',google_callback_origin:'https://admin.example.test'};
const encoded = canonicalProfile(profile);
const env = {COLLECT_BACKEND:'supabase',ADMIN_ORIGIN:profile.admin_origin,SUPABASE_URL:profile.supabase_origin,
  APP_ENVIRONMENT:'production',COLLECT_DEPLOYMENT_PROFILE:encoded,
  COLLECT_DEPLOYMENT_PROFILE_SHA256:createHash('sha256').update(encoded).digest('hex'),
  ASSETS:{fetch(){throw Error('Unexpected static fallback');}},PLATFORM_API:{fetch(){throw Error('Unexpected legacy backend');}}};
const request = (path, options={}) => new Request(profile.admin_origin+path,options);

test('self-hosted Admin binds the verified profile and preserves same-origin cookie authority', async()=>{
  let calls=0;
  const worker=createAdminWorker({fetchImpl:async upstream=>{
    calls++;
    assert.equal(upstream.url,profile.supabase_origin+'/functions/v1/admin-api/api/admin/auth/session');
    assert.equal(upstream.headers.get('origin'),profile.admin_origin);
    assert.equal(upstream.headers.get('cookie'),'__Host-collect_admin=original');
    return Response.json({user:null});
  }});
  assert.equal((await worker.fetch(request('/api/admin/auth/session',{headers:{Cookie:'__Host-collect_admin=original'}}),env)).status,200);
  assert.equal(calls,1);
});

test('private upstream changes network routing but never public cookie or Origin identity',async()=>{
  let calls=0;
  const worker=createAdminWorker({fetchImpl:async upstream=>{
    calls++;assert.equal(upstream.url,'http://kong:8000/functions/v1/admin-api/api/admin/team');
    assert.equal(upstream.headers.get('origin'),profile.admin_origin);
    assert.equal(upstream.headers.get('x-collect-csrf'),'same-session-csrf');
    assert.deepEqual(await upstream.json(),{request_id:'original'});
    return Response.json({ok:true});
  }});
  const response=await worker.fetch(request('/api/admin/team',{method:'POST',headers:{Origin:profile.admin_origin,'X-Collect-CSRF':'same-session-csrf','Content-Type':'application/json'},body:JSON.stringify({request_id:'original'})}),{...env,SUPABASE_INTERNAL_URL:'http://kong:8000'});
  assert.equal(response.status,200);assert.equal(calls,1);
});

test('profile hash, environment, public origin, and private upstream disagreement all fail before dispatch',async()=>{
  let calls=0;const worker=createAdminWorker({fetchImpl:async()=>{calls++;throw Error('Unexpected upstream');}});
  for(const changes of [
    {COLLECT_DEPLOYMENT_PROFILE_SHA256:'0'.repeat(64)}, {COLLECT_DEPLOYMENT_PROFILE:encoded+' '},
    {SUPABASE_URL:'https://other.example.test'}, {APP_ENVIRONMENT:'qualification'},
    {COLLECT_BACKEND:'cloudflare'}, {SUPABASE_INTERNAL_URL:'http://untrusted.example.com'},
    {SUPABASE_INTERNAL_URL:'https://supabase.example.test/elsewhere'},
  ])for(const path of ['/api/admin/auth/session','/index.html']){
    assert.equal((await worker.fetch(request(path),{...env,...changes})).status,503);
  }
  assert.equal(calls,0);
});

test('sibling configured frontend does not gain Admin request authority',async()=>{
  let calls=0;const worker=createAdminWorker({fetchImpl:async()=>{calls++;throw Error('Unexpected upstream');}});
  for(const origin of [profile.public_origin,profile.member_api_origin,'https://unrelated.example.test']){
    assert.equal((await worker.fetch(request('/api/admin/team',{headers:{Origin:origin}}),env)).status,403);
  }
  assert.equal(calls,0);
});

test('self-hosted human challenge renders only at its configured Admin origin without an automatic provider request',async()=>{
  let calls=0;const worker=createAdminWorker({fetchImpl:async()=>{calls++;throw Error('Unexpected provider');}});
  const response=await worker.fetch(request('/admin/auth/local-challenge'),env);
  assert.equal(response.status,200);assert.match(response.headers.get('Content-Security-Policy'),/frame-ancestors 'none'/);
  assert.match(await response.text(),/https:\/\/admin\.example\.test/);assert.equal(calls,0);
});
