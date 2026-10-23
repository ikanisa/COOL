import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash, createHmac} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createCollectTransport, routeCollectTarget, SUPABASE_ORIGIN} from '../deploy/platform-supabase-free/transport.mjs';
import freeHost, {createFreeHost, config as edgeConfig} from '../deploy/platform-supabase-free/netlify/edge-functions/collect-transport.js';
import {PUBLIC_CONFIG, validatePublicConfiguration} from '../deploy/platform-supabase-free/public-config.mjs';
import {callbackResult} from '../supabase/functions/_shared/domain/google_auth.js';
const FRONT = 'https://platform-admin.collect.ikanisa.com';
const cookie = '__Host-collect_admin=opaque_fixture; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=3600';
function fixture(options = {}) {
  const calls = [];
  const handle = createCollectTransport({frontendOrigin: FRONT, fetchImpl: async req => {
    calls.push(req); return new Response('{"ok":true}', {headers:{'Content-Type':'application/json'}});
  }, ...options});
  return {handle, calls};
}
function request(path, options = {}) {
  const headers = new Headers(options.headers);
  // Browser Admin mutations carry Origin. Individual rejection tests construct
  // an originless Request explicitly rather than silently weakening this guard.
  if (!['GET','HEAD','OPTIONS'].includes(options.method ?? 'GET') && !headers.has('Origin')) headers.set('Origin', FRONT);
  return new Request(FRONT + path, {...options, headers});
}
async function code(response) { return (await response.json()).code; }

test('only nominated project and the two fixed function protocols can be routed', () => {
  const query = '?a=one%2Btwo&a=three&url=https%3A%2F%2Fevil.invalid';
  assert.equal(routeCollectTarget('/v1/rpc/member_profile' + query).upstream,
    SUPABASE_ORIGIN + '/functions/v1/collect-api/v1/rpc/member_profile' + query);
  assert.equal(routeCollectTarget('/functions/v1/admin-api/api/admin/auth/session').upstream,
    SUPABASE_ORIGIN + '/functions/v1/admin-api/api/admin/auth/session');
  assert.equal(routeCollectTarget('/functions/v1/collect-api/v1/rpc/member_profile').upstream,
    SUPABASE_ORIGIN + '/functions/v1/collect-api/v1/rpc/member_profile');
  assert.equal(routeCollectTarget('/assets/app.js'), null);
  for (const path of ['/functions/v1/evil/api/admin/auth/session', '/functions/v1/admin-api/v1/rpc/x', '/functions/v1/collect-api/api/admin/auth/session']) {
    assert.throws(() => routeCollectTarget(path), /proxy_route_not_allowed/);
  }
});
test('raw path confusion is refused before URL normalization', () => {
  for (const path of ['//evil.invalid/v1/a', '/v1/../api/admin/x', '/v1/%2e%2e/x', '/v1/%2fadmin', '/v1/%252e/x', '/v1//auth/otp', '/v1/a\\b', '/v1/a#x', '/v1/a\n']) {
    assert.throws(() => routeCollectTarget(path), /proxy_path_invalid/, path);
  }
});
test('configuration cannot nominate an attacker frontend or a different project', () => {
  assert.throws(() => createCollectTransport({frontendOrigin:'https://evil.invalid'}));
  assert.equal(SUPABASE_ORIGIN, 'https://rrlduytparvsjfmegalh.supabase.co');
});
test('static assets fall through with no upstream request', async () => {
  const {handle,calls}=fixture(); assert.equal(await handle(request('/assets/main.js')),null); assert.equal(calls.length,0);
});
test('wrong host, origin and spoofed authority are denied without a backend call', async () => {
  const {handle,calls}=fixture();
  assert.equal((await handle(new Request('https://collect.ikanisa.com/api/admin/auth/session'))).status,421);
  for (const headers of [{Host:'evil.invalid'}, {Origin:'https://evil.invalid'}, {'Sec-Fetch-Site':'cross-site'}, {'X-Collect-Actor':'owner'}, {'X-Collect-Original-Path':'/api/admin/team'}, {'X-Forwarded-Host':'evil.invalid'}]) {
    assert.ok((await handle(request('/api/admin/auth/session',{headers}))).status>=400);
  }
  assert.equal(calls.length,0);
});
test('raw target mismatch and encoded function-path injection never forward', async () => {
  const {handle,calls}=fixture();
  assert.equal(await code(await handle(request('/v1/auth/otp'),{rawTarget:'/v1/../v1/auth/otp'})), 'proxy_path_invalid');
  assert.equal(await code(await handle(request('/v1/auth/otp'),{rawTarget:'/api/admin/auth/session'})), 'proxy_path_invalid');
  assert.equal(calls.length,0);
});
test('exact mutation bytes, method, query, idempotency, cookies and signatures survive once', async () => {
  let observed;
  const bytes=new Uint8Array([0,32,123,195,169,10,255]);
  const {handle}=fixture({fetchImpl:async req=>{
    observed={url:req.url,method:req.method,bytes:new Uint8Array(await req.arrayBuffer()),headers:req.headers,redirect:req.redirect,cache:req.cache};
    return new Response('{"ok":true}',{headers:{'Content-Type':'application/json','Set-Cookie':cookie}});
  }});
  const response=await handle(request('/functions/v1/admin-api/api/admin/team?cursor=a%2Bb',{method:'PATCH',headers:{
    Origin:FRONT,'Content-Type':'application/json','Idempotency-Key':'fixture-operation-1',Cookie:'__Host-collect_admin=old_fixture',
    'X-Collect-CSRF':'fixture-csrf','X-Collect-Requested-With':'collect-admin','X-Collect-Admin':'1',
    'X-Collect-Gateway-Key-Id':'fixture-key','X-Collect-Gateway-Signature':'fixture-signature',
    Authorization:'Bearer fixture-user-token',apikey:'sb_publishable_fixture',
    'CF-Connecting-IP':'spoofed','X-Forwarded-Proto':'http',
  },body:bytes}));
  assert.equal(response.status,200);
  assert.equal(observed.url,SUPABASE_ORIGIN+'/functions/v1/admin-api/api/admin/team?cursor=a%2Bb');
  assert.equal(observed.method,'PATCH');assert.deepEqual(observed.bytes,bytes);
  assert.equal(observed.headers.get('Cookie'),'__Host-collect_admin=old_fixture');
  assert.equal(observed.headers.get('Idempotency-Key'),'fixture-operation-1');
  assert.equal(observed.headers.get('X-Collect-Gateway-Signature'),'fixture-signature');
  assert.equal(observed.headers.get('Authorization'),'Bearer fixture-user-token');
  assert.equal(observed.headers.get('Origin'),FRONT);assert.equal(observed.headers.get('X-Collect-Admin'),'1');
  assert.equal(observed.headers.has('CF-Connecting-IP'),false);assert.equal(observed.headers.has('X-Forwarded-Proto'),false);
  assert.equal(observed.headers.get('Accept-Encoding'),'identity');assert.equal(observed.redirect,'manual');assert.equal(observed.cache,'no-store');
  assert.equal(response.headers.get('Set-Cookie'),cookie);
  assert.match(response.headers.get('Cache-Control'),/no-store/);assert.equal(response.headers.get('CDN-Cache-Control'),'no-store');
});
test('request size limit checks both declared and streamed bytes before effects',async()=>{
  const {handle,calls}=fixture({maxRequestBytes:3});
  assert.equal((await handle(request('/v1/functions/x',{method:'POST',headers:{'Content-Length':'4'},body:'1234'}))).status,413);
  assert.equal((await handle(request('/v1/functions/x',{method:'POST',body:'1234'}))).status,413);assert.equal(calls.length,0);
});
test('response size limit checks advertised and actual bytes',async()=>{
  for(const headers of [{},{'Content-Length':'50'}]){
    const {handle}=fixture({maxResponseBytes:3,fetchImpl:async()=>new Response('12345',{headers})});
    assert.equal(await code(await handle(request('/v1/query/public-collections'))),'proxy_response_too_large');
  }
});
test('redirects and Location headers cannot forward credentials elsewhere',async()=>{
  for(const status of [302,307,200]){
    const {handle}=fixture({fetchImpl:async()=>new Response('',{status,headers:{Location:'https://evil.invalid'}})});
    assert.deepEqual(await (await handle(request('/api/admin/auth/session'))).json(),{code:'proxy_outcome_unknown',reason:'proxy_redirect_denied'});
  }
});
test('cookies are preserved only with the approved host-only secure opaque contract',async()=>{
  for(const invalid of [cookie+'; Domain=.ikanisa.com',cookie.replace('; Secure',''),cookie.replace('; HttpOnly',''),cookie.replace('Path=/','Path=/api'),cookie.replace('__Host-collect_admin','other_cookie'),cookie+'; SameSite=None',cookie+'; SameSite=Strict',cookie+'; Secure',cookie+'; Path=/evil',cookie+'; Max-Age=1']){
    const {handle}=fixture({fetchImpl:async()=>new Response('{}',{headers:{'Set-Cookie':invalid}})});
    assert.deepEqual(await (await handle(request('/api/admin/auth/session'))).json(),{code:'proxy_outcome_unknown',reason:'proxy_cookie_invalid'});
  }
  const {handle}=fixture({fetchImpl:async()=>new Response('{}',{headers:{'Set-Cookie':cookie}})});
  assert.equal(await code(await handle(request('/v1/query/public-collections'))),'proxy_cookie_invalid');
});
test('explicit renderer marker plus CSP restores only qualified HTML routes',async()=>{
  const html='<!doctype html><html><body>Collect verification</body></html>';
  const {handle}=fixture({fetchImpl:async()=>new Response(html,{headers:{'Content-Type':'text/plain','X-Collect-Document':'collect.turnstile.v1','Content-Security-Policy':"default-src 'none'; frame-ancestors https://platform-admin.collect.ikanisa.com"}})});
  const response=await handle(request('/functions/v1/collect-api/v1/security/challenge?attempt_id=fixture&parent_origin='+encodeURIComponent(FRONT)));
  assert.equal(response.status,200);assert.equal(response.headers.get('Content-Type'),'text/html; charset=utf-8');assert.equal(await response.text(),html);
  assert.equal(response.headers.get('X-Content-Type-Options'),'nosniff');
});
test('unmarked text, missing CSP or API HTML are never promoted into the frontend origin',async()=>{
  for(const headers of [{'Content-Type':'text/plain'},{'Content-Type':'text/plain','X-Collect-Document':'collect.turnstile.v1'}]){
    const {handle}=fixture({fetchImpl:async()=>new Response('<html></html>',{headers})});
    assert.equal(await code(await handle(request('/v1/security/challenge'))),'proxy_document_unqualified');
  }
  const {handle}=fixture({fetchImpl:async()=>new Response('<html></html>',{headers:{'Content-Type':'text/html'}})});
  assert.equal(await code(await handle(request('/v1/rpc/x'))),'proxy_document_unqualified');
});
test('duplicate challenge controls and foreign parent origin are denied before rendering',async()=>{
  const {handle,calls}=fixture();
  assert.equal((await handle(request('/v1/security/challenge?attempt_id=a&attempt_id=b'))).status,400);
  assert.equal((await handle(request('/v1/security/challenge?parent_origin=https%3A%2F%2Fevil.invalid'))).status,403);
  assert.equal(calls.length,0);
});
test('HEAD preserves empty-body semantics and qualified document headers',async()=>{
  const {handle}=fixture({fetchImpl:async()=>new Response(null,{headers:{'Content-Type':'text/plain','X-Collect-Document':'collect.turnstile.v1','Content-Security-Policy':"default-src 'none'"}})});
  const response=await handle(request('/v1/security/challenge',{method:'HEAD'}));
  assert.equal(await response.text(),'');assert.equal(response.headers.get('Content-Type'),'text/html; charset=utf-8');
});
test('no-content responses and privacy script routes retain their proper types',async()=>{
  const empty=fixture({fetchImpl:async()=>new Response(null,{status:204})});
  assert.equal((await empty.handle(request('/api/admin/auth/logout',{method:'POST',body:'{}'}))).status,204);
  const script=fixture({fetchImpl:async()=>new Response('void 0',{headers:{'Content-Type':'application/javascript'}})});
  const response=await script.handle(request('/functions/v1/collect-api/privacy/account-deletion/portal.js'));
  assert.equal(response.status,200);assert.equal(response.headers.get('Content-Type'),'application/javascript');
});
test('unknown mutations are not retried or reported as rejected',async()=>{
  let calls=0;const {handle}=fixture({fetchImpl:async()=>{calls++;throw new Error('private upstream failure');}});
  const response=await handle(request('/api/admin/team/invite',{method:'POST',body:'{}'}));
  assert.equal(response.status,502);assert.equal(await code(response),'proxy_outcome_unknown');assert.equal(calls,1);
});
test('deadline aborts upstream and retains an unknown mutation outcome',async()=>{
  const {handle}=fixture({timeoutMs:10,fetchImpl:req=>new Promise((_,reject)=>req.signal.addEventListener('abort',()=>reject(new Error('aborted')),{once:true}))});
  const response=await handle(request('/api/admin/team/invite',{method:'POST',body:'{}'}));
  assert.equal(response.status,504);assert.equal(await code(response),'proxy_outcome_unknown');
});

test('unqualified response compression is rejected independent of Fetch decompression behavior',async()=>{
  const {handle}=fixture({fetchImpl:async req=>{
    assert.equal(req.headers.get('Accept-Encoding'),'identity');
    return new Response('even-already-decoded-data',{headers:{'Content-Encoding':'gzip'}});
  }});
  assert.deepEqual(await (await handle(request('/api/admin/auth/session'))).json(),{code:'proxy_outcome_unknown',reason:'proxy_encoding_unqualified'});
});
test('every post-dispatch mutation response failure remains unknown with reason and no retry',async()=>{
  const cases=[
    ['proxy_response_too_large','/api/admin/team/invite',()=>new Response('large-result'),{maxResponseBytes:3}],
    ['proxy_cookie_invalid','/api/admin/team/invite',()=>new Response('{}',{headers:{'Set-Cookie':cookie+'; SameSite=None'}}),{}],
    ['proxy_encoding_unqualified','/api/admin/team/invite',()=>new Response('{}',{headers:{'Content-Encoding':'gzip'}}),{}],
    ['proxy_redirect_denied','/api/admin/team/invite',()=>new Response('',{status:307,headers:{Location:'https://evil.invalid'}}),{}],
    ['proxy_document_unqualified','/v1/security/challenge',()=>new Response('<html></html>',{headers:{'Content-Type':'text/plain'}}),{}],
  ];
  for(const [reason,path,reply,options]of cases){
    let calls=0;
    const {handle}=fixture({...options,fetchImpl:async req=>{
      calls++;assert.equal(req.headers.get('Idempotency-Key'),'fixture-operation-unknown');
      assert.equal(await req.text(),'exact-request');return reply();
    }});
    const response=await handle(request(path,{method:'POST',headers:{'Idempotency-Key':'fixture-operation-unknown'},body:'exact-request'}));
    const result=await response.json();assert.equal(result.code,'proxy_outcome_unknown');assert.equal(result.reason,reason);assert.equal(calls,1);
  }
});


test('error HTML on a recognized document route stays unrenderable',async()=>{
  const {handle}=fixture({fetchImpl:async()=>new Response('<html><script>fixture</script></html>',{status:500,headers:{
    'Content-Type':'text/html','X-Collect-Document':'collect.turnstile.v1','Content-Security-Policy':"default-src 'none'",
  }})});
  const response=await handle(request('/v1/security/challenge'));
  assert.equal(response.status,502);assert.equal(await code(response),'proxy_document_unqualified');
});

test('Google browser callback permits only cross-site top-level navigation and a qualified document',async()=>{
  const html='<!doctype html><html><body>Return to Collect</body></html>';
  const {handle}=fixture({fetchImpl:async()=>new Response(html,{headers:{
    'Content-Type':'text/plain','X-Collect-Document':'collect.google.callback.v1',
    'Content-Security-Policy':"default-src 'none'; script-src 'nonce-fixture'; frame-ancestors 'none'",
  }})});
  const path='/functions/v1/collect-api/v1/auth/google/callback?state='+ 's'.repeat(43)+'&code=provider-code';
  const navigation=await handle(request(path,{headers:{'Sec-Fetch-Site':'cross-site','Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'}}));
  assert.equal(navigation.status,200);assert.equal(navigation.headers.get('Content-Type'),'text/html; charset=utf-8');
  const crossFetch=await handle(request(path,{headers:{'Sec-Fetch-Site':'cross-site','Sec-Fetch-Mode':'cors','Sec-Fetch-Dest':'empty'}}));
  assert.equal(crossFetch.status,403);
  assert.equal((await handle(request('/v1/auth/google/start',{method:'POST',headers:{'Sec-Fetch-Site':'cross-site','Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'},body:'{}'}))).status,403);
});

test('Google native callback permits only qualified exact token-free app handoffs',async()=>{
  for(const query of ['code='+ 'c'.repeat(43)+'&state='+ 's'.repeat(43),...['invalid_google_sign_in','google_cancelled','google_use_email_sign_in','google_sign_in_unconfirmed'].map(error=>'error='+error+'&state='+ 's'.repeat(43))]){
    const location='collect://auth/google?'+query;
    const {handle}=fixture({fetchImpl:async()=>new Response(null,{status:302,headers:{Location:location,'X-Collect-Document':'collect.google.native.v1'}})});
    const response=await handle(request('/v1/auth/google/callback?code=provider&state='+ 'z'.repeat(43)));
    assert.equal(response.status,302);assert.equal(response.headers.get('Location'),location);assert.match(response.headers.get('Cache-Control'),/no-store/);
  }
});

test('Google callback exceptions cannot become an open redirect or token URL',async()=>{
  const good='collect://auth/google?code='+ 'c'.repeat(43)+'&state='+ 's'.repeat(43);
  for(const location of ['https://evil.invalid',good+'&access_token=secret',good+'&state='+ 't'.repeat(43),good+'#fragment',good.replace('/google','/other'),good.replace('collect://auth','collect://other'),good.replace('code='+ 'c'.repeat(43),'code=short')]){
    const {handle}=fixture({fetchImpl:async()=>new Response(null,{status:302,headers:{Location:location,'X-Collect-Document':'collect.google.native.v1'}})});
    const result=await (await handle(request('/v1/auth/google/callback'))).json();
    assert.deepEqual(result,{code:'proxy_outcome_unknown',reason:'proxy_redirect_denied'},location);
  }
  for(const path of ['/api/admin/auth/google/callback','/v1/security/challenge']){
    const {handle}=fixture({fetchImpl:async()=>new Response(null,{status:302,headers:{Location:good,'X-Collect-Document':'collect.google.native.v1'}})});
    const denied=await (await handle(request(path))).json();
    assert.deepEqual(denied,path.startsWith('/api/admin/')?{code:'proxy_outcome_unknown',reason:'proxy_redirect_denied'}:{code:'proxy_redirect_denied'});
  }
  const unmarked=fixture({fetchImpl:async()=>new Response(null,{status:302,headers:{Location:good}})});
  assert.deepEqual(await (await unmarked.handle(request('/v1/auth/google/callback'))).json(),{code:'proxy_outcome_unknown',reason:'proxy_redirect_denied'});
});

test('public host configuration is exact, immutable and cannot carry private fields',()=>{
  assert.equal(validatePublicConfiguration(PUBLIC_CONFIG).backend,'supabase');
  for(const value of [null,{}, {...PUBLIC_CONFIG,backend:'cloudflare'},
    {...PUBLIC_CONFIG,supabaseOrigin:'https://other.supabase.co'},
    {...PUBLIC_CONFIG,frontendOrigin:'https://preview.netlify.app'},
    {...PUBLIC_CONFIG,memberPrefix:'/functions/v1/other'},
    {...PUBLIC_CONFIG,SUPABASE_SERVICE_ROLE_KEY:'never-accepted'},
    Object.assign(Object.create({secret:'hidden'}),PUBLIC_CONFIG)]){
    assert.throws(()=>createFreeHost({configuration:value}),/exact public/);
  }
  assert.equal(Object.isFrozen(PUBLIC_CONFIG),true);
});

test('actual Edge entrypoint owns managed routes and never sends them to SPA fallback',async()=>{
  let calls=0,next=0;const urls=[];
  const handle=createFreeHost({fetchImpl:async req=>{calls++;urls.push(req.url);return Response.json({ok:true});}});
  const context={next:async()=>{next++;return new Response('SPA');}};
  for(const path of ['/api','/api/unknown','/api/admin','/v1','/functions',
    '/functions/v1/other/v1/auth/user','/functions/v1/admin-api/v1/auth/user',
    '/functions/v1/collect-api/api/admin/auth/session']){
    const response=await handle(request(path),context);assert.equal(response.status,404,path);
  }
  assert.equal(calls,0);assert.equal(next,0);
  for(const path of ['/api/admin/auth/session','/v1/auth/user',
    '/functions/v1/admin-api/api/admin/auth/session','/functions/v1/collect-api/v1/auth/user',
    '/privacy/account-deletion/portal.js'])assert.equal((await handle(request(path),context)).status,200);
  assert.equal(calls,5);assert.equal(next,0);
  assert.ok(urls.every(url=>url.startsWith(SUPABASE_ORIGIN+'/functions/v1/')));
});

test('actual Edge static continuation preserves exact bytes and existing asset headers',async()=>{
  let next=0,calls=0;const bytes=new Uint8Array([0,1,255,13,10,195,169]);
  const handle=createFreeHost({fetchImpl:async()=>{calls++;throw Error('must not fetch');}});
  const asset=new Response(bytes,{headers:{'Content-Type':'application/wasm','Cache-Control':'public, max-age=31536000, immutable'}});
  const result=await handle(request('/_build/'+ 'a'.repeat(64)+'/engine.wasm'),{next:async()=>{next++;return asset;}});
  assert.equal(result,asset);assert.deepEqual(new Uint8Array(await result.arrayBuffer()),bytes);
  const html='<!doctype html>\r\n<html><body>Collect\u00a0Admin</body></html>\n';
  const response=await handle(request('/members/fixture'),{next:async()=>{next++;return new Response(html,{headers:{'Content-Type':'text/html','Content-Security-Policy':"default-src 'self'"}});}});
  assert.equal(await response.text(),html);assert.equal(response.headers.get('Cache-Control'),'no-store, no-transform');
  assert.equal(response.headers.get('Content-Security-Policy'),"default-src 'self'");assert.equal(calls,0);assert.equal(next,2);
  assert.equal((await handle(request('/assets/x',{method:'POST',body:'x'}),{next:()=>{throw Error('unreachable');}})).status,405);
  assert.equal((await handle(request('/index.html'),{next:async()=>{throw Error('private platform detail');}})).status,503);
});

test('Edge deployment rules cover actual APIs and run before the SPA with fail-closed errors',async()=>{
  assert.equal(edgeConfig.onError,'fail');assert.equal(Object.hasOwn(edgeConfig,'cache'),false);
  assert.equal(edgeConfig.path,'/*');
  const toml=await readFile(new URL('../deploy/platform-supabase-free/netlify.toml',import.meta.url),'utf8');
  assert.match(toml,/publish\s*=\s*"\.\.\/\.\.\/build\/web"/);
  assert.match(toml,/edge_functions\s*=\s*"netlify\/edge-functions"/);
  assert.match(toml,/force\s*=\s*false/);
  assert.equal(/service_role|sb_secret_|PLATFORM_API|ASSETS|wrangler/.test(toml),false);
  assert.equal((await freeHost(new Request('https://wrong.netlify.app/api/admin/auth/session'))).status,421);
});

test('cold Admin GET and HEAD use only the trusted public origin; mutations never synthesize it',async()=>{
  let calls=0;const origins=[];
  const handle=createFreeHost({fetchImpl:async req=>{calls++;origins.push(req.headers.get('Origin'));return new Response(null,{status:204});}});
  for(const method of ['GET','HEAD'])assert.equal((await handle(request('/api/admin/auth/session',{method,headers:{'Sec-Fetch-Site':'same-origin',Cookie:'__Host-collect_admin=fixture'}}))).status,204);
  assert.deepEqual(origins,[FRONT,FRONT]);
  for(const headers of [{'Sec-Fetch-Site':'same-site'},{'Sec-Fetch-Site':'cross-site'},{Origin:'https://evil.invalid'},{'X-Forwarded-Host':'platform-admin.collect.ikanisa.com'}]){
    assert.ok((await handle(request('/api/admin/auth/session',{headers}))).status>=400);
  }
  assert.equal((await handle(new Request(FRONT+'/api/admin/auth/login',{method:'POST',body:'{}'}))).status,403);
  assert.equal(calls,2);
  const native=fixture({fetchImpl:async req=>{assert.equal(req.headers.has('Origin'),false);return Response.json({ok:true});}});
  assert.equal((await native.handle(new Request(FRONT+'/v1/auth/user',{headers:{Authorization:'Bearer fixture'}}))).status,200);
});

test('actual Edge preserves Admin CSRF/header rejection and removes upstream CORS/cache overrides',async()=>{
  let calls=0;
  const handle=createFreeHost({fetchImpl:async req=>{
    calls++;assert.equal(req.headers.get('X-Collect-Requested-With'),'collect-admin');
    assert.equal(req.headers.get('Cookie'),'__Host-collect_admin=fixture');
    assert.equal(req.headers.get('X-Collect-Admin'),'1');
    if(req.headers.get('X-Collect-CSRF')!=='csrf-fixture')return Response.json({code:'csrf_required'},{status:403});
    return Response.json({ok:true},{headers:{'Set-Cookie':cookie,'Access-Control-Allow-Origin':'*','Access-Control-Allow-Credentials':'true','Netlify-CDN-Cache-Control':'public,max-age=3600','ETag':'unsafe-cache'}});
  }});
  const headers={Origin:FRONT,Cookie:'__Host-collect_admin=fixture','X-Collect-Requested-With':'collect-admin','X-Collect-Admin':'1','Content-Type':'application/json'};
  const denied=await handle(request('/api/admin/team/invite',{method:'POST',headers,body:'{}'}));
  assert.equal(denied.status,403);assert.equal(await code(denied),'csrf_required');
  const response=await handle(request('/api/admin/team/invite',{method:'POST',headers:{...headers,'X-Collect-CSRF':'csrf-fixture'},body:'{}'}));
  assert.equal(response.headers.get('Set-Cookie'),cookie);assert.equal(response.headers.has('Access-Control-Allow-Origin'),false);
  assert.equal(response.headers.has('Access-Control-Allow-Credentials'),false);assert.equal(response.headers.has('ETag'),false);
  assert.equal(response.headers.get('Netlify-CDN-Cache-Control'),'no-store');assert.equal(calls,2);
});

test('actual Edge preserves the secure logout deletion cookie and rejects multiple custody cookies',async()=>{
  const clear='__Host-collect_admin=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0';
  const handle=createFreeHost({fetchImpl:async()=>new Response(null,{status:204,headers:{'Set-Cookie':clear}})});
  const response=await handle(request('/api/admin/auth/logout',{method:'POST',headers:{'X-Collect-CSRF':'fixture'},body:'{}'}));
  assert.equal(response.status,204);assert.equal(response.headers.get('Set-Cookie'),clear);assert.equal(await response.text(),'');
  const multiple=new Headers();multiple.append('Set-Cookie',cookie);multiple.append('Set-Cookie',clear);
  const invalid=createFreeHost({fetchImpl:async()=>new Response('{}',{headers:multiple})});
  const result=await (await invalid(request('/api/admin/auth/logout',{method:'POST',body:'{}'}))).json();
  assert.deepEqual(result,{code:'proxy_outcome_unknown',reason:'proxy_cookie_invalid'});
});

test('native and browser Google success/cancel/unconfirmed use the actual server renderer',async()=>{
  const state='s'.repeat(43),handoff='c'.repeat(43),path='/functions/v1/collect-api/v1/auth/google/callback?state='+ 'z'.repeat(43)+'&code=provider';
  const replies=[{code:handoff,state},...['invalid_google_sign_in','google_cancelled','google_use_email_sign_in','google_sign_in_unconfirmed'].map(error=>({error,state}))];
  for(const data of replies){
    const native=createFreeHost({fetchImpl:async()=>callbackResult({surface:'member',return_origin:null},data)});
    const response=await native(request(path,{headers:{'Sec-Fetch-Site':'cross-site','Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'}}));
    assert.equal(response.status,302);const url=new URL(response.headers.get('Location'));
    assert.equal(url.origin,'null');assert.equal(url.host,'auth');assert.equal(url.pathname,'/google');assert.equal(url.searchParams.get('state'),state);
    assert.equal(url.searchParams.get(data.code?'code':'error'),data.code??data.error);
    const browser=createFreeHost({fetchImpl:async()=>{
      const original=callbackResult({surface:'admin',return_origin:FRONT},data),headers=new Headers(original.headers);
      // Supabase's default gateway serves function HTML as text/plain.
      headers.set('Content-Type','text/plain');return new Response(original.body,{headers});
    }});
    const document=await browser(request(path,{headers:{Origin:SUPABASE_ORIGIN,'Sec-Fetch-Site':'cross-site','Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'}}));
    assert.equal(document.status,200);assert.equal(document.headers.get('Content-Type'),'text/html; charset=utf-8');
    assert.match(document.headers.get('Content-Security-Policy'),/script-src 'nonce-[A-Za-z0-9_-]{43}'/);
    const html=await document.text();assert.ok(html.includes('postMessage('));assert.ok(html.includes(JSON.stringify(FRONT)));
    assert.equal(/access_token|refresh_token|provider_token/.test(html),false);assert.ok(html.includes(data.code??data.error));
  }
});

test('foreign provider Origin requires exact Google document navigation, never API fetch',async()=>{
  const {handle,calls}=fixture();
  for(const path of ['/v1/auth/google/callback','/v1/auth/google/exchange','/api/admin/auth/session']){
    const response=await handle(request(path,{headers:{Origin:SUPABASE_ORIGIN,'Sec-Fetch-Mode':'cors','Sec-Fetch-Dest':'empty'}}));
    assert.equal(response.status,403);
  }
  const location='collect://auth/google?error=not_a_server_error&state='+ 's'.repeat(43);
  const unsafe=fixture({fetchImpl:async()=>new Response(null,{status:302,headers:{Location:location,'X-Collect-Document':'collect.google.native.v1'}})});
  const unsafeResult=await (await unsafe.handle(request('/v1/auth/google/callback'))).json();
  assert.equal(unsafeResult.code,'proxy_outcome_unknown');assert.equal(unsafeResult.reason,'proxy_redirect_denied');assert.equal(calls.length,0);
});

test('7.1MB roster transport budget and binary response pass exact hashes without body transforms',async()=>{
  const body=new Uint8Array(7_100_000);body.fill(65);body.set(new TextEncoder().encode('{"fixture":"'));
  body.set([195,169,34,125],body.length-4);
  const expected=createHash('sha256').update(body).digest('hex');let calls=0;
  const path='/functions/v1/collect-api/v1/functions/roster-import-upload?file=a%2Bb&file=c';
  const handle=createFreeHost({fetchImpl:async req=>{
    calls++;assert.equal(req.url,SUPABASE_ORIGIN+path);assert.equal(req.headers.get('Idempotency-Key'),'large-fixture');
    const incoming=new Uint8Array(await req.arrayBuffer());assert.equal(incoming.length,body.length);
    assert.equal(createHash('sha256').update(incoming).digest('hex'),expected);
    return new Response(incoming,{headers:{'Content-Type':'application/octet-stream'}});
  }});
  const response=await handle(request(path,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':'large-fixture'},body}));
  assert.equal(response.status,200);assert.equal(createHash('sha256').update(new Uint8Array(await response.arrayBuffer())).digest('hex'),expected);assert.equal(calls,1);
});

test('logical and prefixed gateway aliases preserve one canonical signature input and exact query bytes',async()=>{
  const logical='/v1/momo/gateway/ingest',query='?a=a%2Bb&a=second&url=https%3A%2F%2Fexample.invalid';
  const body='{"raw_body":"literal \\n and + signs","request_id":"synthetic"}';
  const hash=createHash('sha256').update(body).digest('hex');
  // Synthetic transport proof only. Real installed native signer/backend
  // protocol and old journal rebind remain separate qualification gates.
  const sign=input=>createHmac('sha256','synthetic-local-fixture-key').update(input).digest('hex');
  const signature=sign('POST\n'+logical+query+'\n'+hash);let calls=0;
  const handle=createFreeHost({fetchImpl:async req=>{
    calls++;const url=new URL(req.url),canonical=url.pathname.slice('/functions/v1/collect-api'.length)+url.search;
    assert.equal(canonical,logical+query);assert.equal(req.headers.get('X-Collect-Gateway-Key-Id'),'synthetic-key');
    assert.equal(req.headers.get('X-Collect-Gateway-Signature'),sign(req.method+'\n'+canonical+'\n'+createHash('sha256').update(await req.text()).digest('hex')));
    return Response.json({ok:true});
  }});
  for(const path of [logical+query,'/functions/v1/collect-api'+logical+query]){
    const response=await handle(new Request(FRONT+path,{method:'POST',headers:{'Content-Type':'application/json','X-Collect-Gateway-Key-Id':'synthetic-key','X-Collect-Gateway-Signature':signature},body}));
    assert.equal(response.status,200);
  }
  assert.equal(calls,2);
});

test('post-provider Google GET response failure is unknown and never retried',async()=>{
  let calls=0;const handle=createFreeHost({fetchImpl:async()=>{
    calls++;return new Response('<html>too large</html>',{headers:{'X-Collect-Document':'collect.google.callback.v1','Content-Security-Policy':"default-src 'none'"}});
  },transportOptions:{maxResponseBytes:3}});
  const response=await handle(request('/v1/auth/google/callback?state='+ 's'.repeat(43)+'&code=provider'));
  assert.deepEqual(await response.json(),{code:'proxy_outcome_unknown',reason:'proxy_response_too_large'});assert.equal(calls,1);
});

test('Admin session and team reads retain unknown refresh outcomes without retry',async()=>{
  for(const [path,method] of [['/api/admin/auth/session','GET'],['/api/admin/team','GET'],['/api/admin/auth/session','HEAD']]){
    let calls=0;
    const {handle}=fixture({fetchImpl:async()=>{calls++;throw new Error('synthetic lost refresh response');}});
    const response=await handle(request(path,{method,headers:{Cookie:'__Host-collect_admin=fixture','Sec-Fetch-Site':'same-origin'}}));
    assert.equal(response.status,502);
    assert.equal((await response.json()).code,'proxy_outcome_unknown');
    assert.equal(calls,1);
  }
});

test('only the dedicated local challenge document receives loopback CSP without static or upstream dispatch',async()=>{
 let upstream=0,staticCalls=0;const handler=createFreeHost({fetchImpl:async()=>{upstream++;throw Error('No upstream');}}),context={next:async()=>{staticCalls++;return new Response('fixture',{headers:{'Content-Type':'text/html','Content-Security-Policy':"connect-src 'self'"}});}};
 const response=await handler(request('/admin/auth/local-challenge',{headers:{'Sec-Fetch-Site':'same-origin'}}),context);
 assert.equal(response.status,200);assert.equal(response.headers.get('Content-Security-Policy').includes('http://127.0.0.1:*'),true);assert.equal(response.headers.get('Cache-Control').includes('no-store'),true);assert.equal(staticCalls,0);assert.equal(upstream,0);
 for(const [path,options,status]of[['/admin/auth/local-challenge?token=forbidden',{},400],['/admin/auth/local-challenge',{method:'POST'},405],['/admin/auth/local-challenge',{headers:{Origin:'https://foreign.example'}},403],['/admin/auth/local-challenge/extra',{},404]]){assert.equal((await handler(request(path,options),context)).status,status);}
 const normal=await handler(request('/admin/login'),context);assert.equal(normal.headers.get('Content-Security-Policy'),"connect-src 'self'");assert.equal(staticCalls,1);assert.equal(upstream,0);
});

test('filesystem metadata is never served through the static host, including encoded paths',async()=>{
 let reads=0;const handle=createFreeHost({fetchImpl:async()=>{throw Error('No upstream');}}),context={next:async()=>{reads++;return new Response('metadata');}};
 for(const path of ['/assets/._lazy.txt','/.DS_Store','/assets/%2e_lazy.txt','/_build/fixture/nested/.DS_Store'])assert.equal((await handle(request(path),context)).status,404);
 assert.equal(reads,0);
});
