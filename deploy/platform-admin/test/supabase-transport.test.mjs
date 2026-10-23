import test from 'node:test';
import assert from 'node:assert/strict';
import {createCollectTransport, routeCollectTarget, SUPABASE_ORIGIN} from '../src/supabase-transport.js';
import {renderedDocument, GATEWAY_CSP} from './fixtures/document-renderers.mjs';
const FRONT = 'https://admin.collect.ikanisa.com';
const cookie = '__Host-collect_admin=opaque_fixture; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=3600';
function fixture(options = {}) {
  const calls = [];
  const handle = createCollectTransport({frontendOrigin: FRONT, fetchImpl: async req => {
    calls.push(req); return new Response('{"ok":true}', {headers:{'Content-Type':'application/json'}});
  }, ...options});
  return {handle, calls};
}
function request(path, options) { return new Request(FRONT + path, options); }
async function code(response) { return (await response.json()).code; }

for (const kind of ['privacy', 'challenge', 'google']) {
  test('real frozen ' + kind + ' renderer restores its executable policy after gateway sandbox', async () => {
    const document = await renderedDocument(kind); let calls = 0;
    const {handle} = fixture({fetchImpl: async () => { calls++; return document.reply(); }});
    const response = await handle(request(document.path));
    assert.equal(response.status, 200); assert.equal(calls, 1);
    assert.equal(await response.text(), document.html);
    assert.equal(response.headers.get('Content-Type'), 'text/html; charset=utf-8');
    const policy = response.headers.get('Content-Security-Policy');
    assert.notEqual(policy, GATEWAY_CSP); assert.doesNotMatch(policy, /sandbox|unsafe-inline|unsafe-eval|\*/);
    const rules = new Map(policy.split(';').map(rule => rule.trim().split(/\s+/)).map(([name, ...values]) => [name, values]));
    assert.deepEqual(rules.get('default-src'), ["'none'"]);
    if (kind === 'privacy') {
      assert.equal(policy, document.originalPolicy);
      for (const directive of ['script-src', 'style-src', 'connect-src', 'frame-src', 'img-src']) assert.deepEqual(rules.get(directive), ["'self'"]);
      assert.deepEqual(rules.get('frame-ancestors'), ["'none'"]);
      assert.match(document.html, /src="\/functions\/v1\/collect-api\/privacy\/account-deletion\/assets\/client\.js"/);
    } else {
      const nonce = document.html.match(/<script nonce="([^"]+)"/)[1];
      if (kind === 'challenge') {
        assert.deepEqual(rules.get('script-src'), ["'nonce-" + nonce + "'", 'https://challenges.cloudflare.com']);
        assert.deepEqual(rules.get('style-src'), ["'nonce-" + nonce + "'"]);
        for (const directive of ['frame-src', 'connect-src']) assert.deepEqual(rules.get(directive), ['https://challenges.cloudflare.com']);
        assert.deepEqual(rules.get('frame-ancestors'), [FRONT]);
      } else {
        assert.equal(policy, document.originalPolicy);
        assert.deepEqual(rules.get('script-src'), ["'nonce-" + nonce + "'"]);
        assert.deepEqual(rules.get('frame-ancestors'), ["'none'"]);
      }
    }
    assert.equal(response.headers.get('Cache-Control'), 'private, no-store, max-age=0, no-transform');
    assert.equal(response.headers.get('CDN-Cache-Control'), 'no-store');
    assert.equal(response.headers.get('Surrogate-Control'), 'no-store');
    assert.equal(response.headers.get('Pragma'), 'no-cache');
    assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
    assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer');
    assert.equal(response.headers.get('Cross-Origin-Resource-Policy'), 'same-origin');
  });
}

test('the three exact gateway-free renderer policies are projected without broadening ancestors', async () => {
  for (const kind of ['privacy', 'challenge', 'google']) {
    const document = await renderedDocument(kind); let calls = 0;
    const {handle} = fixture({fetchImpl: async () => { calls++; return document.reply({policy: document.originalPolicy}); }});
    const response = await handle(request(document.path));
    assert.equal(response.status, 200); assert.equal(calls, 1);
    assert.equal(await response.text(), document.html);
    if (kind === 'challenge') assert.match(response.headers.get('Content-Security-Policy'), new RegExp('; frame-ancestors ' + FRONT.replaceAll('.', '\\.') + '$'));
    else assert.equal(response.headers.get('Content-Security-Policy'), document.originalPolicy);
  }
});

test('nonce-bearing HEAD documents keep their restrictive upstream policy without a GET or retry', async () => {
  for (const kind of ['privacy', 'challenge', 'google']) {
    const document = await renderedDocument(kind); let calls = 0;
    const {handle} = fixture({fetchImpl: async upstream => { calls++; assert.equal(upstream.method, 'HEAD'); return document.reply({method: 'HEAD'}); }});
    const response = await handle(request(document.path, {method: 'HEAD'}));
    assert.equal(response.status, 200); assert.equal(calls, 1); assert.equal(await response.text(), '');
    assert.equal(response.headers.get('Content-Security-Policy'), GATEWAY_CSP);
    assert.equal(response.headers.get('Cache-Control'), 'private, no-store, max-age=0, no-transform');
    assert.equal(response.headers.get('CDN-Cache-Control'), 'no-store');
    assert.equal(response.headers.get('Surrogate-Control'), 'no-store');
    assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
    assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer');
  }
});

test('missing, permissive, appended or unknown policies never authorize document promotion', async () => {
  for (const kind of ['privacy', 'challenge', 'google']) {
    const document = await renderedDocument(kind);
    for (const policy of [null, '', "default-src *; script-src 'unsafe-inline'", GATEWAY_CSP + "; script-src 'unsafe-inline'", "default-src 'none'; sandbox allow-scripts"]) {
      let calls = 0;
      const {handle} = fixture({fetchImpl: async () => { calls++; return document.reply({policy}); }});
      const response = await handle(request(document.path));
      assert.equal(response.status, 502); assert.equal(calls, 1);
      assert.equal(response.headers.get('Content-Type'), 'application/json; charset=utf-8');
      assert.equal(response.headers.get('Cache-Control'), 'private, no-store, max-age=0');
      const body = await response.json();
      assert.equal(body.code, kind === 'google' ? 'proxy_outcome_unknown' : 'proxy_document_unqualified');
      if (kind === 'google') assert.equal(body.reason, 'proxy_document_unqualified');
    }
  }
});

test('challenge opener cardinality, UUID nonce consistency and exact external script fail closed', async () => {
  const document = await renderedDocument('challenge');
  const nonce = document.html.match(/<script nonce="([^"]+)"/)[1];
  const mutations = [
    html => html.replace('<style nonce="' + nonce + '">', '<style>'),
    html => html.replace('<style nonce="' + nonce + '">', '<style nonce="11111111-1111-4111-8111-111111111111">'),
    html => html.replaceAll(nonce, 'invalid-nonce'),
    html => html.replace('https://challenges.cloudflare.com/turnstile/v0/api.js?', 'https://evil.invalid/turnstile/v0/api.js?'),
    html => html.replace('&amp;render=explicit', '&amp;render=other'),
    html => html.replace(' async defer>', ' nonce="' + nonce + '" async defer>'),
    html => html.replace('</body>', '<script nonce="' + nonce + '">void 0</script></body>'),
    html => html.replace('</head>', '<style nonce="' + nonce + '">body{}</style></head>'),
    html => html.replace('<script nonce="' + nonce + '">', '<script nonce="' + nonce + '" src="https://evil.invalid/x.js">'),
  ];
  for (const change of mutations) {
    let calls = 0;
    const {handle} = fixture({fetchImpl: async () => { calls++; return document.reply({body: change(document.html)}); }});
    const response = await handle(request(document.path));
    assert.equal(response.status, 502); assert.equal(await code(response), 'proxy_document_unqualified'); assert.equal(calls, 1);
  }
});

test('Google callback nonce/body rejection keeps its already-dispatched exchange unknown', async () => {
  const document = await renderedDocument('google');
  const nonce = document.html.match(/<script nonce="([^"]+)"/)[1];
  const mutations = [
    html => html.replace(nonce, 'short'),
    html => html.replace('<script nonce="' + nonce + '">', '<script nonce="' + nonce + '" nonce="' + nonce + '">'),
    html => html.replace('<script nonce="' + nonce + '">', '<script nonce="' + nonce + '" src="https://evil.invalid/x.js">'),
    html => html.replace('</body>', '<script nonce="' + nonce + '">void 0</script></body>'),
    html => html.replace('</head>', '<style nonce="' + nonce + '">body{}</style></head>'),
    html => html.replace('</html>', ''),
  ];
  for (const change of mutations) {
    let calls = 0;
    const {handle} = fixture({fetchImpl: async () => { calls++; return document.reply({body: change(document.html)}); }});
    const response = await handle(request(document.path));
    assert.equal(response.status, 502); assert.equal(calls, 1);
    assert.deepEqual(await response.json(), {code: 'proxy_outcome_unknown', reason: 'proxy_document_unqualified'});
  }
});

test('privacy accepts only its own external module and stylesheet with no inline execution', async () => {
  const document = await renderedDocument('privacy');
  for (const body of [
    document.html.replace('/assets/client.js', '/assets/other.js'),
    document.html.replace('/assets/style.css', '/assets/other.css'),
    document.html.replace('</body>', '<script>void 0</script></body>'),
    document.html.replace('</head>', '<style>body{}</style></head>'),
    document.html.replace('type="module"', 'type="module" nonce="unapproved"'),
  ]) {
    let calls = 0;
    const {handle} = fixture({fetchImpl: async () => { calls++; return document.reply({body}); }});
    const response = await handle(request(document.path));
    assert.equal(response.status, 502); assert.equal(await code(response), 'proxy_document_unqualified'); assert.equal(calls, 1);
  }
});

test('document marker, exact route, MIME and valid UTF8 remain required for projection', async () => {
  const privacy = await renderedDocument('privacy'); const challenge = await renderedDocument('challenge');
  const cases = [
    {body: privacy.html, headers: {'X-Collect-Document': null}},
    {body: privacy.html, headers: {'X-Collect-Document': 'collect.turnstile.v1'}},
    {body: challenge.html},
    {body: privacy.html, headers: {'Content-Type': 'application/json'}},
    {body: 'not html'},
    {body: new Uint8Array([0xff])},
  ];
  for (const options of cases) {
    let calls = 0;
    const {handle} = fixture({fetchImpl: async () => { calls++; return privacy.reply(options); }});
    const response = await handle(request(privacy.path));
    assert.equal(response.status, 502); assert.equal(calls, 1); assert.match(response.headers.get('Content-Type'), /^application\/json/);
  }
  const {handle} = fixture({fetchImpl: async () => privacy.reply()});
  const ordinary = await handle(request('/v1/rpc/member_profile'));
  assert.equal(ordinary.headers.get('Content-Type'), 'text/plain'); assert.equal(ordinary.headers.get('Content-Security-Policy'), GATEWAY_CSP);
});

test('ordinary API, JavaScript and CSS responses keep their original policy and body', async () => {
  for (const [path, type, body] of [['/v1/rpc/member_profile', 'application/json', '{"ok":true}'],
    ['/privacy/account-deletion/assets/client.js', 'text/javascript', 'export const fixture = true;'],
    ['/privacy/account-deletion/assets/style.css', 'text/css', 'body{color:CanvasText}']]) {
    let calls = 0;
    const {handle} = fixture({fetchImpl: async () => { calls++; return new Response(body, {headers: {'Content-Type': type, 'Content-Security-Policy': GATEWAY_CSP}}); }});
    const response = await handle(request(path));
    assert.equal(response.status, 200); assert.equal(calls, 1); assert.equal(await response.text(), body);
    assert.equal(response.headers.get('Content-Type'), type); assert.equal(response.headers.get('Content-Security-Policy'), GATEWAY_CSP);
    assert.equal(response.headers.get('Cache-Control'), 'private, no-store, max-age=0');
    assert.equal(response.headers.get('CDN-Cache-Control'), 'no-store');
    assert.equal(response.headers.get('Surrogate-Control'), 'no-store');
    assert.equal(response.headers.get('Pragma'), 'no-cache');
    assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
    assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer');
  }
});

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
test('configured-origin Admin reads bind legitimate originless GET and HEAD without changing custody headers',async()=>{
  for(const frontendOrigin of [FRONT,'https://collect.ikanisa.com','https://platform-admin.collect.ikanisa.com']){
    for(const path of ['/api/admin/auth/session','/functions/v1/admin-api/api/admin/team']){
      for(const method of ['GET','HEAD']){
        for(const site of [undefined,'none','same-origin']){
          let calls=0;
          const handle=createCollectTransport({frontendOrigin,fetchImpl:async req=>{
            calls++;assert.equal(req.headers.get('Origin'),frontendOrigin);
            assert.equal(req.headers.get('Cookie'),'__Host-collect_admin=opaque_fixture');
            assert.equal(req.headers.get('Authorization'),'Bearer fixture-user-token');
            assert.equal(req.headers.get('X-Collect-CSRF'),'fixture-csrf');
            assert.equal(req.method,method);
            return new Response(null,{status:204,headers:{'Set-Cookie':cookie}});
          }});
          const headers={Cookie:'__Host-collect_admin=opaque_fixture',Authorization:'Bearer fixture-user-token','X-Collect-CSRF':'fixture-csrf'};
          if(site!==undefined)headers['Sec-Fetch-Site']=site;
          const response=await handle(new Request(frontendOrigin+path,{method,headers}));
          assert.equal(response.status,204);assert.equal(calls,1);
          assert.equal(response.headers.get('Set-Cookie'),cookie);assert.equal(await response.text(),'');
        }
      }
    }
  }
});
test('Admin read origin binding rejects sibling metadata and every non-explicit write origin before dispatch',async()=>{
  const {handle,calls}=fixture();
  for(const method of ['GET','HEAD']){
    for(const headers of [{'Sec-Fetch-Site':'same-site'},{'Sec-Fetch-Site':'cross-site'},{'Sec-Fetch-Site':'unexpected'},
      {Origin:'https://collect.ikanisa.com','Sec-Fetch-Site':'same-site'},
      {Origin:'https://platform-admin.collect.ikanisa.com','Sec-Fetch-Site':'same-site'},
      {Origin:'https://evil.invalid','Sec-Fetch-Site':'same-origin'},
      {'X-Forwarded-Host':'admin.collect.ikanisa.com','Sec-Fetch-Site':'same-origin'}]){
      assert.ok((await handle(request('/api/admin/auth/session',{method,headers}))).status>=400);
    }
  }
  for(const method of ['POST','PUT','PATCH','DELETE']){
    for(const headers of [{},{'Sec-Fetch-Site':'same-origin'},{Origin:''},{Origin:'null'},
      {Origin:'https://collect.ikanisa.com'},{Origin:'https://platform-admin.collect.ikanisa.com'},{Origin:'https://evil.invalid'}]){
      const response=await handle(request('/api/admin/team/invite',{method,headers,body:'{}'}));
      assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'proxy_origin_denied'});
    }
  }
  assert.equal(calls.length,0);
  for(const method of ['POST','PUT','PATCH','DELETE']){
    assert.equal((await handle(request('/api/admin/team/invite',{method,headers:{Origin:FRONT},body:'{}'}))).status,200);
  }
  assert.equal(calls.length,4);
});
test('native member requests keep absent Origin and Admin preflight does not synthesize it',async()=>{
  const {handle,calls}=fixture();
  for(const [path,method]of [['/v1/rpc/member_profile','GET'],['/functions/v1/collect-api/v1/auth/session','HEAD'],
    ['/v1/auth/otp','POST'],['/v1/functions/member_update','PATCH'],['/api/admin/auth/session','OPTIONS']]){
    const response=await handle(request(path,{method,headers:{Authorization:'Bearer fixture-member'},
      ...(['GET','HEAD'].includes(method)?{}:{body:'{}'})}));
    assert.equal(response.status,200);assert.equal(calls.at(-1).headers.has('Origin'),false);
    assert.equal(calls.at(-1).headers.get('Authorization'),'Bearer fixture-member');
  }
  assert.equal(calls.length,5);
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
const gatewayCookie = '__cf_bm=synthetic_gateway; path=/; expires=Tue, 20 Oct 2026 18:00:00 GMT; domain=.supabase.co; HttpOnly; Secure; SameSite=None';
const rateCookie = '_cfuvid=synthetic_rate; path=/; domain=.supabase.co; HttpOnly; Secure; SameSite=None';
function upstreamCookies(values, api = 'standard') {
  const headers = new Headers({'Content-Type':'application/json'});
  for (const value of values) headers.append('Set-Cookie', value);
  if (api !== 'standard') {
    Object.defineProperty(headers, 'getSetCookie', {value:undefined});
    if (api === 'workers') Object.defineProperty(headers, 'getAll', {value(name) {
      assert.equal(this, headers); assert.equal(name, 'Set-Cookie'); return [...values];
    }});
  }
  return {status:200, statusText:'OK', ok:true, headers, body:new Response('{}').body};
}
test('upstream gateway cookies never enter Collect frontend custody',async()=>{
  for (const api of ['standard','workers','combined']) {
    for (const path of ['/api/admin/auth/session','/v1/query/public-collections']) {
      const {handle}=fixture({fetchImpl:async()=>upstreamCookies([gatewayCookie,rateCookie],api)});
      const response=await handle(request(path));
      assert.equal(response.status,200,api); assert.equal(response.headers.has('Set-Cookie'),false);
      assert.deepEqual(await response.json(),{});
    }
  }
});
test('the single strict app cookie survives gateway cookies in every order and Headers API',async()=>{
  for (const api of ['standard','workers','combined']) {
    for (const values of [[gatewayCookie,cookie,rateCookie],[cookie,gatewayCookie,rateCookie],[gatewayCookie,rateCookie,cookie]]) {
      const {handle}=fixture({fetchImpl:async()=>upstreamCookies(values,api)});
      const response=await handle(request('/api/admin/auth/session'));
      assert.equal(response.status,200,api); assert.equal(response.headers.get('Set-Cookie'),cookie);
      assert.equal(response.headers.getSetCookie().length,1);
    }
  }
});
test('gateway filtering cannot hide unknown, malformed or duplicate app custody',async()=>{
  for (const api of ['standard','workers','combined']) {
    for (const values of [[gatewayCookie,cookie,cookie],[gatewayCookie,'unknown=fixture; Secure'],
      [gatewayCookie,cookie+'; Domain=.ikanisa.com'],['__cf_bm=invalid, opaque; Path=/',cookie],
      [gatewayCookie,'__Host-collect_admin=bad, opaque; Path=/; Secure; HttpOnly; SameSite=Strict']]) {
      let calls=0;
      const {handle}=fixture({fetchImpl:async()=>{calls++;return upstreamCookies(values,api);}});
      const response=await handle(request('/api/admin/auth/session'));
      assert.deepEqual(await response.json(),{code:'proxy_outcome_unknown',reason:'proxy_cookie_invalid'},api);
      assert.equal(response.headers.has('Set-Cookie'),false); assert.equal(calls,1);
    }
  }
});
test('explicit renderer marker plus CSP restores only qualified HTML routes',async()=>{
  const document=await renderedDocument('challenge'); const html=document.html;
  const {handle}=fixture({fetchImpl:async()=>document.reply()});
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
  assert.equal((await empty.handle(request('/api/admin/auth/logout',{method:'POST',headers:{Origin:FRONT},body:'{}'}))).status,204);
  const script=fixture({fetchImpl:async()=>new Response('void 0',{headers:{'Content-Type':'application/javascript'}})});
  const response=await script.handle(request('/functions/v1/collect-api/privacy/account-deletion/portal.js'));
  assert.equal(response.status,200);assert.equal(response.headers.get('Content-Type'),'application/javascript');
});
test('unknown mutations are not retried or reported as rejected',async()=>{
  let calls=0;const {handle}=fixture({fetchImpl:async()=>{calls++;throw new Error('private upstream failure');}});
  const response=await handle(request('/api/admin/team/invite',{method:'POST',headers:{Origin:FRONT},body:'{}'}));
  assert.equal(response.status,502);assert.equal(await code(response),'proxy_outcome_unknown');assert.equal(calls,1);
});
test('deadline aborts upstream and retains an unknown mutation outcome',async()=>{
  const {handle}=fixture({timeoutMs:10,fetchImpl:req=>new Promise((_,reject)=>req.signal.addEventListener('abort',()=>reject(new Error('aborted')),{once:true}))});
  const response=await handle(request('/api/admin/team/invite',{method:'POST',headers:{Origin:FRONT},body:'{}'}));
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
    const response=await handle(request(path,{method:'POST',headers:{Origin:FRONT,'Idempotency-Key':'fixture-operation-unknown'},body:'exact-request'}));
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
  const document=await renderedDocument('google');
  const {handle}=fixture({fetchImpl:async()=>document.reply()});
  const path='/functions/v1/collect-api/v1/auth/google/callback?state='+ 's'.repeat(43)+'&code=provider-code';
  const navigation=await handle(request(path,{headers:{'Sec-Fetch-Site':'cross-site','Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'}}));
  assert.equal(navigation.status,200);assert.equal(navigation.headers.get('Content-Type'),'text/html; charset=utf-8');
  const provider=await handle(request(path,{headers:{Origin:SUPABASE_ORIGIN,'Sec-Fetch-Site':'cross-site','Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'}}));
  assert.equal(provider.status,200);assert.equal(provider.headers.get('Content-Type'),'text/html; charset=utf-8');
  const crossFetch=await handle(request(path,{headers:{'Sec-Fetch-Site':'cross-site','Sec-Fetch-Mode':'cors','Sec-Fetch-Dest':'empty'}}));
  assert.equal(crossFetch.status,403);
  assert.equal((await handle(request('/v1/auth/google/start',{method:'POST',headers:{'Sec-Fetch-Site':'cross-site','Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'},body:'{}'}))).status,403);
});
test('provider Origin exception requires an exact Google GET document navigation before dispatch',async()=>{
  const {handle,calls}=fixture();
  for(const headers of [{Origin:SUPABASE_ORIGIN},{Origin:SUPABASE_ORIGIN,'Sec-Fetch-Mode':'navigate'},
    {Origin:SUPABASE_ORIGIN,'Sec-Fetch-Dest':'document'},
    {Origin:SUPABASE_ORIGIN,'Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'iframe'},
    {Origin:'https://evil.invalid','Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'}]){
    const response=await handle(request('/v1/auth/google/callback',{headers}));
    assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'proxy_origin_denied'});
  }
  for(const [path,method]of [['/v1/auth/google/callback','HEAD'],['/v1/auth/google/callback','POST'],['/api/admin/auth/session','GET']]){
    const response=await handle(request(path,{method,headers:{Origin:SUPABASE_ORIGIN,'Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'}}));
    assert.equal(response.status,403);assert.deepEqual(await response.json(),{code:'proxy_origin_denied'});
  }
  assert.equal(calls.length,0);
});

test('Google native callback permits only qualified exact token-free app handoffs',async()=>{
  const queries=['code='+ 'c'.repeat(43)+'&state='+ 's'.repeat(43),
    ...['invalid_google_sign_in','google_cancelled','google_use_email_sign_in','google_sign_in_unconfirmed'].map(error=>'error='+error+'&state='+ 's'.repeat(43))];
  for(const query of queries){
    const location='collect://auth/google?'+query;
    const {handle}=fixture({fetchImpl:async()=>new Response(null,{status:302,headers:{Location:location,'X-Collect-Document':'collect.google.native.v1'}})});
    const response=await handle(request('/v1/auth/google/callback?code=provider&state='+ 'z'.repeat(43)));
    assert.equal(response.status,302);assert.equal(response.headers.get('Location'),location);assert.match(response.headers.get('Cache-Control'),/no-store/);
  }
});

test('Google callback exceptions cannot become an open redirect or token URL',async()=>{
  const good='collect://auth/google?code='+ 'c'.repeat(43)+'&state='+ 's'.repeat(43);
  for(const location of ['https://evil.invalid',good+'&access_token=secret',good+'&state='+ 't'.repeat(43),good+'#fragment',good.replace('/google','/other'),good.replace('collect://auth','collect://other'),good.replace('code='+ 'c'.repeat(43),'code=short'),
    'collect://auth/google?error=unknown_error&state='+ 's'.repeat(43),
    'collect://auth/google?error=google_cancelled&state='+ 's'.repeat(43)+'&access_token=secret']){
    const {handle}=fixture({fetchImpl:async()=>new Response(null,{status:302,headers:{Location:location,'X-Collect-Document':'collect.google.native.v1'}})});
    assert.deepEqual(await (await handle(request('/v1/auth/google/callback'))).json(),{code:'proxy_outcome_unknown',reason:'proxy_redirect_denied'},location);
  }
  for(const path of ['/api/admin/auth/google/callback','/v1/security/challenge']){
    const {handle}=fixture({fetchImpl:async()=>new Response(null,{status:302,headers:{Location:good,'X-Collect-Document':'collect.google.native.v1'}})});
    assert.deepEqual(await (await handle(request(path))).json(),path.startsWith('/api/admin/')?
      {code:'proxy_outcome_unknown',reason:'proxy_redirect_denied'}:{code:'proxy_redirect_denied'});
  }
  const unmarked=fixture({fetchImpl:async()=>new Response(null,{status:302,headers:{Location:good}})});
  assert.deepEqual(await (await unmarked.handle(request('/v1/auth/google/callback'))).json(),{code:'proxy_outcome_unknown',reason:'proxy_redirect_denied'});
});

test('every dispatched Admin method and Google callback GET keeps lost-response uncertainty without retry',async()=>{
  for(const path of ['/api/admin/auth/session','/functions/v1/admin-api/api/admin/team']){
    for(const method of ['GET','HEAD','POST','PUT','PATCH','DELETE']){
      let calls=0;
      const {handle}=fixture({fetchImpl:async()=>{calls++;throw new Error('synthetic lost custody response');}});
      const response=await handle(request(path,{method,headers:{Origin:FRONT,Cookie:'__Host-collect_admin=fixture'}}));
      assert.equal(response.status,502);
      assert.deepEqual(await response.json(),{code:'proxy_outcome_unknown',reason:'proxy_upstream_failure'});
      assert.equal(calls,1);
    }
  }
  let calls=0;
  const {handle}=fixture({fetchImpl:async()=>{calls++;throw new Error('synthetic lost provider exchange');}});
  const response=await handle(request('/v1/auth/google/callback?state=fixture&code=provider',{
    headers:{Origin:SUPABASE_ORIGIN,'Sec-Fetch-Site':'cross-site','Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'},
  }));
  assert.equal(response.status,502);
  assert.deepEqual(await response.json(),{code:'proxy_outcome_unknown',reason:'proxy_upstream_failure'});
  assert.equal(calls,1);
});
test('Admin refresh GET and HEAD retain unknown outcomes when returned custody cannot be qualified',async()=>{
  const cases=[
    ['proxy_cookie_invalid',()=>new Response(null,{headers:{'Set-Cookie':cookie+'; Domain=.ikanisa.com'}}),{}],
    ['proxy_response_too_large',()=>new Response(null,{headers:{'Content-Length':'10'}}),{maxResponseBytes:3}],
    ['proxy_response_too_large',()=>new Response('too large'),{maxResponseBytes:3}],
    ['proxy_encoding_unqualified',()=>new Response(null,{headers:{'Content-Encoding':'gzip'}}),{}],
    ['proxy_redirect_denied',()=>new Response(null,{status:302,headers:{Location:'https://evil.invalid'}}),{}],
    ['proxy_document_unqualified',()=>new Response('<html>unqualified</html>',{headers:{'Content-Type':'text/html'}}),{}],
  ];
  for(const method of ['GET','HEAD']){
    for(const [reason,reply,options]of cases){
      let calls=0;
      const {handle}=fixture({...options,fetchImpl:async()=>{calls++;return reply();}});
      const response=await handle(request('/api/admin/auth/session',{method,headers:{'Sec-Fetch-Site':'same-origin'}}));
      assert.equal(response.status,502);assert.deepEqual(await response.json(),{code:'proxy_outcome_unknown',reason});assert.equal(calls,1);
    }
  }
});
test('Google callback response qualification failures retain an unknown exchanged-custody outcome',async()=>{
  for(const [reason,reply,options]of [
    ['proxy_document_unqualified',()=>new Response('<html>unmarked</html>',{headers:{'Content-Type':'text/html'}}),{}],
    ['proxy_document_unqualified',()=>new Response('<html>missing CSP</html>',{headers:{'X-Collect-Document':'collect.google.callback.v1'}}),{}],
    ['proxy_response_too_large',()=>new Response('<html>large</html>'),{maxResponseBytes:3}],
    ['proxy_upstream_failure',()=>new Response(new Uint8Array([0xff]),{headers:{'Content-Type':'text/plain','X-Collect-Document':'collect.google.callback.v1','Content-Security-Policy':"default-src 'none'"}}),{}],
  ]){
    let calls=0;const {handle}=fixture({...options,fetchImpl:async()=>{calls++;return reply();}});
    const response=await handle(request('/functions/v1/collect-api/v1/auth/google/callback'));
    assert.equal(response.status,502);assert.deepEqual(await response.json(),{code:'proxy_outcome_unknown',reason});assert.equal(calls,1);
  }
});
test('Admin read and Google callback deadlines remain unknown after exactly one dispatch',async()=>{
  for(const [path,method]of [['/api/admin/auth/session','GET'],['/functions/v1/admin-api/api/admin/team','HEAD'],['/v1/auth/google/callback','GET']]){
    let calls=0;
    const {handle}=fixture({timeoutMs:10,fetchImpl:req=>new Promise((_,reject)=>{
      calls++;req.signal.addEventListener('abort',()=>reject(new Error('synthetic deadline')),{once:true});
    })});
    const response=await handle(request(path,{method}));
    assert.equal(response.status,504);assert.deepEqual(await response.json(),{code:'proxy_outcome_unknown',reason:'proxy_deadline'});assert.equal(calls,1);
  }
});
test('pre-dispatch refusals and interrupted input never acquire an unknown outcome',async()=>{
  const {handle,calls}=fixture();
  const cancelled=new AbortController();cancelled.abort();
  const response=await handle(request('/api/admin/auth/session',{method:'POST',headers:{Origin:FRONT},body:'{}',signal:cancelled.signal}));
  assert.equal(response.status,504);assert.deepEqual(await response.json(),{code:'proxy_deadline'});
  const denied=await handle(request('/v1/auth/google/callback',{headers:{Origin:SUPABASE_ORIGIN,'Sec-Fetch-Mode':'cors','Sec-Fetch-Dest':'empty'}}));
  assert.equal(denied.status,403);assert.deepEqual(await denied.json(),{code:'proxy_origin_denied'});assert.equal(calls.length,0);
});
test('ordinary member reads and Admin OPTIONS keep non-effectful unavailable classification',async()=>{
  for(const [path,method]of [['/v1/rpc/member_profile','GET'],['/v1/auth/session','HEAD'],['/api/admin/auth/session','OPTIONS']]){
    let calls=0;const {handle}=fixture({fetchImpl:async()=>{calls++;throw new Error('synthetic unavailable');}});
    const response=await handle(request(path,{method}));
    assert.equal(response.status,502);assert.deepEqual(await response.json(),{code:'proxy_unavailable'});assert.equal(calls,1);
  }
});
