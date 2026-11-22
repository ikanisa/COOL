import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {fixture} from './support/auth_fixture.mjs';
test('public verification refuses missing real configuration, foreign parents and malformed attempts',async t=>{
 const f=await fixture({}, {entrypoint:'index.js'});t.after(()=>f.close());
 let response=await f.mf.dispatchFetch('https://api.collect.example/v1/security/challenge?attempt_id='+randomUUID());assert.equal(response.status,503);
 const ready=await fixture({TURNSTILE_SITE_KEY:'controlled-widget-public-test-key'}, {entrypoint:'index.js'});t.after(()=>ready.close());
 response=await ready.mf.dispatchFetch('https://api.collect.example/v1/security/challenge?attempt_id='+randomUUID()+'&parent_origin=https://evil.example');assert.equal(response.status,403);
 response=await ready.mf.dispatchFetch('https://api.collect.example/v1/security/challenge?attempt_id=%3Cscript%3E');assert.equal(response.status,400);
});
test('verification page exposes only public settings, binds callback to exact attempt/origin and denies caching',async t=>{
 const f=await fixture({TURNSTILE_SITE_KEY:'controlled-widget-public-test-key'}, {entrypoint:'index.js'});t.after(()=>f.close());const attempt=randomUUID();
 const response=await f.mf.dispatchFetch('https://api.collect.example/v1/security/challenge?attempt_id='+attempt+'&parent_origin=https://collect.example&theme=dark');assert.equal(response.status,200);const html=await response.text();
 assert.equal(response.headers.get('Cache-Control'),'no-store');assert.ok(response.headers.get('Content-Security-Policy').includes("frame-ancestors 'self' https://collect.example https://admin.collect.example"));
 assert.ok(html.includes(attempt));assert.ok(html.includes('collect.turnstile.v1'));assert.ok(html.includes('config.parent_origin'));assert.ok(html.includes('messageHandlers.CollectTurnstile'));assert.ok(html.includes('collect.turnstile.ready'));assert.ok(html.includes('deliver(latestMessage)'));assert.ok(html.includes("'expired-callback'"));assert.ok(!html.includes('localStorage'));assert.ok(!html.includes('AUTH_JWT_SECRET'));assert.ok(!html.includes('TURNSTILE_SECRET'));
});
