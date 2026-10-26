import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {renderLocalChallengeDocument} from '../deploy/platform-supabase-free/local-challenge.mjs';
import {FRONT, QA, SIBLING, PATH, ATTEMPT, NOW, canonical, json, harness} from './fixtures/local-challenge-parent-harness.mjs';

test('dedicated parent handles only its exact production GET route', async () => {
  assert.equal(renderLocalChallengeDocument(new Request(FRONT+'/admin')),null);
  for (const url of ['http://platform-admin.collect.ikanisa.com'+PATH, 'https://other.example'+PATH,
    FRONT+':8443'+PATH]) {
    assert.equal(renderLocalChallengeDocument(new Request(url)).status,421);
  }
  assert.equal(renderLocalChallengeDocument({url:'https://user@platform-admin.collect.ikanisa.com'+PATH,
    method:'GET',headers:new Headers()}).status,421);
  for (const suffix of ['?port=45123','?','#private','#']) assert.equal(renderLocalChallengeDocument(new Request(FRONT+PATH+suffix)).status,400);
  for (const headers of [{Host:'other.example'},{Origin:'https://other.example'},{'Sec-Fetch-Site':'cross-site'}]) {
    assert.ok(renderLocalChallengeDocument(new Request(FRONT+PATH,{headers})).status>=400);
  }
  for (const method of ['POST','HEAD','OPTIONS']) {
    const response = renderLocalChallengeDocument(new Request(FRONT+PATH,{method}));
    assert.equal(response.status,405);assert.equal(response.headers.get('Allow'),'GET');
  }
});

test('parent has route-only nonce CSP and accessible modest Collect form', async () => {
  const response = renderLocalChallengeDocument(new Request(FRONT+PATH));
  const html = await response.text(), csp = response.headers.get('Content-Security-Policy');
  const nonce = html.match(/<script nonce="([a-f0-9]+)">/)[1];
  assert.match(csp,new RegExp("script-src 'nonce-"+nonce+"'"));
  assert.match(csp,/connect-src 'self' http:\/\/127\.0\.0\.1:\*/);
  assert.match(csp,/frame-src 'self'/);assert.match(csp,/frame-ancestors 'none'/);
  assert.doesNotMatch(csp,/unsafe-inline|unsafe-eval|https:\/\//);
  assert.match(response.headers.get('Cache-Control'),/no-store/);assert.equal(response.headers.has('Set-Cookie'),false);
  assert.match(html,/<label for="pairing">/);assert.match(html,/role="status" aria-live="polite"/);
  assert.match(html,/<title>Security verification · Collect/);assert.doesNotMatch(html,/name="(?:email|password|code)"|<script src=/);
});

test('explicit QA parent config serves only the QA origin and keeps production presentation', async () => {
  assert.equal(renderLocalChallengeDocument(new Request(QA+PATH)).status,421);
  const qa = renderLocalChallengeDocument(new Request(QA+PATH), {origin:QA});
  const production = renderLocalChallengeDocument(new Request(FRONT+PATH), {origin:FRONT});
  assert.equal(qa.status,200);assert.equal(production.status,200);
  assert.equal(renderLocalChallengeDocument(new Request(FRONT+PATH), {origin:QA}).status,421);
  assert.equal(renderLocalChallengeDocument(new Request(QA+PATH), {origin:FRONT}).status,421);
  for (const options of [{origin:SIBLING}, {origin:QA+'/'}, {origin:'http://admin-supabase-qa.collect.ikanisa.com'}, {origin:QA,unexpected:true}]) {
    assert.ok(renderLocalChallengeDocument(new Request(QA+PATH), options).status>=400);
  }
  const presentation = html => html.replace(/<script nonce="[a-f0-9]+">[\s\S]*?<\/script>/,'')
    .replaceAll(/nonce="[a-f0-9]+"/g,'nonce="RENDER_NONCE"');
  assert.equal(presentation(await qa.text()),presentation(await production.text()));
  for (const response of [qa,production]) {
    assert.match(response.headers.get('Cache-Control'),/no-store/);
    assert.equal(response.headers.has('Set-Cookie'),false);
    assert.match(response.headers.get('Content-Security-Policy'),/frame-src 'self'/);
    assert.match(response.headers.get('Content-Security-Policy'),/frame-ancestors 'none'/);
  }
});

test('QA signed pairing creates only its own origin-bound challenge iframe', async () => {
  const f = await harness({origin:QA});assert.equal(f.calls.length,0);
  assert.equal(f.descriptor.admin_origin,QA);assert.equal(f.payload.admin_origin,QA);
  await f.connect();assert.equal(f.calls.length,1);
  const call=f.calls[0];assert.equal(call.url,'http://127.0.0.1:45123/v1/collect-admin/human-challenge/offer');
  assert.equal(call.options.method,'GET');assert.equal(call.options.body,undefined);
  assert.equal(call.options.credentials,'omit');assert.equal(call.options.redirect,'error');
  const frame=f.frame(), url=new URL(frame.src);
  assert.equal(url.origin,QA);assert.equal(url.pathname,'/functions/v1/collect-api/v1/security/challenge');
  assert.deepEqual([...url.searchParams.keys()],['attempt_id','parent_origin','theme']);
  assert.equal(url.searchParams.get('parent_origin'),QA);assert.equal(url.searchParams.get('attempt_id'),ATTEMPT);
  assert.equal(frame.attributes.sandbox,'allow-scripts allow-same-origin');assert.equal(frame.referrerPolicy,'no-referrer');
  assert.equal(f.elements.pairing.value,'');assert.equal(f.elements.status.dataset.state,'verifying');
});

test('QA rejects production and sibling descriptors before requesting an offer', async () => {
  for (const origin of [FRONT,SIBLING]) {
    const f=await harness({origin:QA});await f.connect({...f.descriptor,admin_origin:origin});
    assert.equal(f.calls.length,0);assert.equal(f.frame(),undefined);assert.equal(f.elements.status.dataset.state,'failed');
  }
});

test('QA rejects validly signed offers for production or sibling origins', async () => {
  for (const origin of [FRONT,SIBLING]) {
    const f=await harness({origin:QA,response:(_,{signed,payload})=>json(signed({...payload,admin_origin:origin}))});
    await f.connect();assert.equal(f.calls.length,1);assert.equal(f.frame(),undefined);
    assert.equal(f.elements.status.dataset.state,'failed');
  }
});

test('QA accepts a candidate only from its own iframe and keeps the token in one private completion', async () => {
  const f=await harness({origin:QA});await f.connect();const frame=f.frame();
  const data={type:'collect.turnstile.v1',attempt_id:ATTEMPT,token:'SYNTHETIC_QA_ANTIABUSE_ONLY'};
  for (const changes of [{origin:FRONT},{origin:SIBLING},{origin:'https://other.example'},{source:{}},{source:f.window}]) {
    await f.candidate(data,changes);
    assert.equal(f.calls.length,1);assert.equal(f.frame(),frame);assert.equal(f.elements.status.dataset.state,'verifying');
  }
  await f.candidate(data);
  await f.window.emit('message',{origin:QA,source:frame.contentWindow,data});await f.connect();
  assert.equal(f.calls.length,2);
  const completion=f.calls[1];assert.equal(completion.url,'http://127.0.0.1:45123/v1/collect-admin/human-challenge/complete');
  assert.equal(completion.options.method,'POST');assert.equal(completion.options.headers['Content-Type'],'application/json');
  assert.deepEqual(completion.body,{type:'collect.admin.human_challenge.complete.v1',attempt_id:ATTEMPT,
    operation:f.descriptor.operation,nonce:f.payload.nonce,widget_attempt_id:ATTEMPT,token:data.token});
  for (const call of f.calls) {
    const headers=new Headers(call.options.headers);
    assert.equal(call.options.credentials,'omit');assert.equal(call.options.redirect,'error');
    assert.equal(headers.has('Cookie'),false);assert.equal(headers.has('Authorization'),false);assert.equal(headers.has('apikey'),false);
    assert.equal(call.url.includes(data.token),false);assert.equal(JSON.stringify(call.options.headers).includes(data.token),false);
  }
  assert.equal(frame.src.includes(data.token),false);assert.equal(f.html.includes(data.token),false);
  assert.equal(JSON.stringify(f.window.location).includes(data.token),false);
  assert.equal(Object.values(f.elements).some(element=>(element.textContent+element.value).includes(data.token)),false);
  assert.equal(f.frame(),undefined);assert.equal(f.timers.size,0);assert.equal(f.elements.status.dataset.state,'complete');
  assert.match(f.elements.status.textContent,/terminal for the sign-in result/);
});

test('nothing connects on load; trusted explicit Connect verifies signed offer before creating one iframe', async () => {
  const f = await harness();assert.equal(f.calls.length,0);assert.equal(f.frame(),undefined);
  await f.connect();assert.equal(f.calls.length,1);
  const call = f.calls[0];assert.equal(call.url,'http://127.0.0.1:45123/v1/collect-admin/human-challenge/offer');
  assert.equal(call.options.method,'GET');assert.equal(call.options.credentials,'omit');assert.equal(call.options.redirect,'error');
  assert.equal(call.options.mode,'cors');assert.equal(call.options.cache,'no-store');
  assert.equal(call.options.headers['X-Collect-Handoff-Attempt'],ATTEMPT);assert.equal(call.options.headers['X-Collect-Handoff-Version'],'1');
  assert.equal(call.options.body,undefined);assert.equal(call.options.headers.Cookie,undefined);assert.equal(call.options.headers.Authorization,undefined);
  const frame = f.frame(), url = new URL(frame.src);
  assert.equal(url.origin,FRONT);assert.equal(url.pathname,'/functions/v1/collect-api/v1/security/challenge');
  assert.deepEqual([...url.searchParams.keys()],['attempt_id','parent_origin','theme']);
  assert.equal(url.searchParams.get('parent_origin'),FRONT);assert.equal(url.searchParams.get('attempt_id'),ATTEMPT);
  assert.equal(frame.attributes.sandbox,'allow-scripts allow-same-origin');assert.equal(frame.referrerPolicy,'no-referrer');
  assert.equal(f.elements.status.dataset.state,'verifying');
});

test('descriptor authority, duplicate fields, hidden or embedded context fail before a request', async () => {
  for (const change of [{admin_origin:'https://other.example'},{loopback_port:80},{expires_at_ms:NOW-1},
    {expires_at_ms:NOW+120_001},{operation:'arbitrary.fetch'},{extra:'not_allowed'},{listener_public_key_ed25519:'A'.repeat(42)}]) {
    const f = await harness();await f.connect({...f.descriptor,...change});assert.equal(f.calls.length,0);assert.equal(f.frame(),undefined);
  }
  const duplicate = await harness();await duplicate.connect(JSON.stringify(duplicate.descriptor).replace('{','{"attempt_id":"'+ATTEMPT+'",'));
  assert.equal(duplicate.calls.length,0);
  const hidden = await harness();hidden.document.visibilityState='hidden';await hidden.connect();assert.equal(hidden.calls.length,0);
  const embedded = await harness({topLevel:false});await embedded.connect();assert.equal(embedded.calls.length,0);
});

test('unsupported Ed25519 and invalid signed offers never create a challenge or unsigned fallback', async () => {
  const unsupported = await harness({crypto:{subtle:{importKey:async()=>{throw Error('unsupported');}}}});
  await unsupported.connect();assert.equal(unsupported.calls.length,0);assert.equal(unsupported.elements.status.dataset.state,'failed');
  for (const mutation of [
    (signed,payload)=>({...signed(),signature_ed25519_base64url:Buffer.alloc(64).toString('base64url')}),
    (signed,payload)=>signed({...payload,operation:'admin.password.sign_in'}),
    (signed,payload)=>signed(payload,JSON.stringify(payload)),
    (signed,payload)=>signed({...payload,nonce:'A'.repeat(42)}),
    (signed,payload)=>({...signed(),unexpected:true}),
  ]) {
    const f = await harness({response:(_,{signed,payload})=>json(mutation(signed,payload))});
    await f.connect();assert.equal(f.calls.length,1);assert.equal(f.frame(),undefined);assert.equal(f.elements.status.dataset.state,'failed');
  }
});

test('foreign message origins and sources cannot transfer a token', async () => {
  const f = await harness();await f.connect();
  await f.candidate(undefined,{origin:'https://other.example'});await f.candidate(undefined,{source:{}});
  assert.equal(f.calls.length,1);assert.equal(f.elements.status.dataset.state,'verifying');
});

test('one exact iframe candidate produces one private POST and truthful non-session ACK', async () => {
  const f = await harness();await f.connect();const frame=f.frame();
  const data={type:'collect.turnstile.v1',attempt_id:ATTEMPT,token:'SYNTHETIC_ANTIABUSE_ONLY'};
  await f.candidate(data);await f.window.emit('message',{origin:FRONT,source:frame.contentWindow,data});await f.connect();
  assert.equal(f.calls.length,2);const call=f.calls[1];
  assert.equal(call.url,'http://127.0.0.1:45123/v1/collect-admin/human-challenge/complete');assert.equal(call.options.method,'POST');
  assert.equal(call.options.credentials,'omit');assert.equal(call.options.redirect,'error');assert.equal(call.options.headers['Content-Type'],'application/json');
  assert.deepEqual(call.body,{type:'collect.admin.human_challenge.complete.v1',attempt_id:ATTEMPT,operation:f.descriptor.operation,
    nonce:f.payload.nonce,widget_attempt_id:ATTEMPT,token:data.token});
  assert.equal(call.url.includes(data.token),false);assert.equal(JSON.stringify(call.options.headers).includes(data.token),false);
  assert.equal(f.frame(),undefined);assert.equal(f.elements.status.dataset.state,'complete');assert.match(f.elements.status.textContent,/terminal for the sign-in result/);
  assert.equal(f.timers.size,0);
});

test('malformed genuine iframe envelope terminates once with an error and no candidate token', async () => {
  for (const data of [{type:'collect.turnstile.v1',attempt_id:ATTEMPT,token:'private',extra:true},
    {type:'collect.turnstile.v1',attempt_id:ATTEMPT,token:'bad token'},
    {type:'collect.turnstile.v1',attempt_id:ATTEMPT,error:'unexpected'}]) {
    const f=await harness();await f.connect();await f.candidate(data);
    assert.equal(f.calls.length,2);assert.equal(f.calls[1].body.error,'invalid_token');assert.equal(f.calls[1].body.token,undefined);
    assert.equal(f.elements.status.dataset.state,'cancelled');
  }
});

test('operator cancellation sends a single terminal error after offer without sign-in claim', async () => {
  const f=await harness();await f.connect();await f.elements.cancel.emit('click');await f.elements.cancel.emit('click');
  assert.equal(f.calls.length,2);assert.equal(f.calls[1].body.error,'cancelled');assert.equal(f.calls[1].body.token,undefined);
  assert.equal(f.elements.status.dataset.state,'cancelled');assert.equal(f.frame(),undefined);
  const timeout=await harness();await timeout.connect();
  await timeout.candidate({type:'collect.turnstile.v1',attempt_id:ATTEMPT,error:'timeout'});
  assert.equal(timeout.calls.length,2);assert.equal(timeout.calls[1].body.error,'timeout');
  assert.equal(timeout.elements.status.dataset.state,'cancelled');
  assert.doesNotMatch(timeout.elements.status.textContent,/unconfirmed/);
});

test('offer denial or oversized response stops without challenge, retry or provider route', async () => {
  for (const response of [()=>{throw Error('PRIVATE_BROWSER_DETAIL');},()=>json({code:'denied'},403),
    ()=>new Response('x'.repeat(8193),{headers:{'Content-Type':'application/json'}})]) {
    const f=await harness({response});await f.connect();await f.connect();
    assert.equal(f.calls.length,1);assert.equal(f.frame(),undefined);assert.equal(f.elements.status.dataset.state,'failed');
    assert.doesNotMatch(f.elements.status.textContent,/PRIVATE_BROWSER_DETAIL/);
  }
});

test('lost completion ACK or forged session-success ACK stays unconfirmed and never resends', async () => {
  for (const reject of [true,false]) {
    const f=await harness({response:call=>call.body ? reject ? Promise.reject(Error('PRIVATE_LOST_REPLY'))
      : json({type:'collect.admin.human_challenge.ack.v1',attempt_id:ATTEMPT,operation:'admin.email_otp.send',status:'accepted_for_one_cli_operation',session_confirmed:true},202)
      : json(f.signed())});
    await f.connect();await f.candidate();await f.elements.cancel.emit('click');await f.connect();
    assert.equal(f.calls.length,2);assert.equal(f.elements.status.dataset.state,'unconfirmed');
    assert.doesNotMatch(f.elements.status.textContent,/PRIVATE_LOST_REPLY/);
  }
});

test('expiry or hiding the parent removes the widget without another request', async () => {
  for (const kind of ['expiry','hidden','pagehide']) {
    const f=await harness();await f.connect();
    if(kind==='expiry') await f.expire();
    else if(kind==='hidden'){f.document.visibilityState='hidden';await f.document.emit('visibilitychange');}
    else await f.window.emit('pagehide');
    await f.candidate();assert.equal(f.calls.length,1);assert.equal(f.frame(),undefined);assert.equal(f.timers.size,0);
  }
});

test('parent source has no credential import, persistence, logging or alternate transport', async () => {
  const source=await readFile(new URL('../deploy/platform-supabase-free/local-challenge.mjs',import.meta.url),'utf8');
  assert.doesNotMatch(source,/localStorage|sessionStorage|document\.cookie|navigator\.clipboard|console\.|WebSocket|sendBeacon|XMLHttpRequest|window\.open/);
});
