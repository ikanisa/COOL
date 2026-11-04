import test from 'node:test';
import assert from 'node:assert/strict';
import {createCollectTransport as createAdmin} from '../src/supabase-transport.js';
import {createCollectTransport as createNetlify} from '../../platform-supabase-free/transport.mjs';

const origin = 'https://admin.collect.ikanisa.com';
const encoded = new TextEncoder();
function fragmented(text, {empty = 4096, cancel = () => {}} = {}) {
  const bytes = encoded.encode(text); let position = -empty;
  return new ReadableStream({
    pull(controller) {
      if (position < 0) { position++; controller.enqueue(new Uint8Array()); }
      else if (position < bytes.length) controller.enqueue(bytes.subarray(position, ++position));
      else controller.close();
    },
    cancel,
  });
}
function request(path, {body, ...options} = {}) {
  return new Request(origin + path, {...options, ...(body ? {body, duplex: 'half'} : {})});
}

for (const [name, create] of [['admin', createAdmin], ['netlify', createNetlify]]) {
  test(name + ' accepts fragmented exact-limit request and response', async () => {
    let calls = 0; let received;
    const handle = create({frontendOrigin: origin, maxRequestBytes: 4, maxResponseBytes: 4,
      fetchImpl: async req => { calls++; received = await req.text(); return new Response(fragmented('wxyz')); }});
    const result = await handle(request('/v1/query/public-collections', {method: 'POST', body: fragmented('abcd')}));
    assert.equal(result.status, 200); assert.equal(await result.text(), 'wxyz');
    assert.equal(received, 'abcd'); assert.equal(calls, 1);
  });
  test(name + ' rejects fragmented oversized request without dispatch', async () => {
    let calls = 0; let cancelled = 0;
    const handle = create({frontendOrigin: origin, maxRequestBytes: 4,
      fetchImpl: async () => { calls++; return new Response('unexpected'); }});
    const result = await handle(request('/v1/query/public-collections', {
      method: 'POST', body: fragmented('abcde', {cancel() { cancelled++; }}),
    }));
    assert.equal(result.status, 413); assert.deepEqual(await result.json(), {code: 'proxy_request_too_large'});
    assert.equal(calls, 0); assert.equal(cancelled, 1);
  });
  test(name + ' keeps oversized post-dispatch response outcome unknown', async () => {
    let calls = 0; let cancelled = 0;
    const handle = create({frontendOrigin: origin, maxResponseBytes: 4,
      fetchImpl: async () => { calls++; return new Response(fragmented('abcde', {cancel() { cancelled++; }})); }});
    const result = await handle(request('/v1/query/public-collections', {method: 'POST', body: fragmented('a')}));
    assert.equal(result.status, 502);
    assert.deepEqual(await result.json(), {code: 'proxy_outcome_unknown', reason: 'proxy_response_too_large'});
    assert.equal(calls, 1); assert.equal(cancelled, 1);
  });
  test(name + ' cancellation unblocks an aborted input before dispatch', async () => {
    let calls = 0; let cancelled = 0; let started;
    const waiting = new Promise(resolve => { started = resolve; });
    const body = new ReadableStream({pull() { started(); return new Promise(() => {}); }, cancel() { cancelled++; }});
    const controller = new AbortController();
    const handle = create({frontendOrigin: origin, fetchImpl: async () => { calls++; return new Response(); }});
    const pending = handle(request('/v1/query/public-collections', {method: 'POST', body, signal: controller.signal}));
    await waiting; controller.abort();
    const result = await pending;
    assert.equal(result.status, 504); assert.deepEqual(await result.json(), {code: 'proxy_deadline'});
    assert.equal(calls, 0); assert.equal(cancelled, 1);
  });
  test(name + ' rejects a non-byte response and retains unknown outcome', async () => {
    let calls = 0; let cancelled = 0;
    const body = new ReadableStream({pull(controller) { controller.enqueue('not bytes'); }, cancel() { cancelled++; }});
    const handle = create({frontendOrigin: origin, fetchImpl: async () => { calls++; return new Response(body); }});
    const result = await handle(request('/v1/query/public-collections', {method: 'POST', body: fragmented('a')}));
    assert.equal(result.status, 502);
    assert.deepEqual(await result.json(), {code: 'proxy_outcome_unknown', reason: 'proxy_upstream_failure'});
    assert.equal(calls, 1); assert.equal(cancelled, 1);
  });
  test(name + ' rejects a non-byte request before dispatch', async () => {
    let calls = 0; let cancelled = 0;
    const body = new ReadableStream({pull(controller) { controller.enqueue('not bytes'); }, cancel() { cancelled++; }});
    const handle = create({frontendOrigin: origin, fetchImpl: async () => { calls++; return new Response(); }});
    const result = await handle(request('/v1/query/public-collections', {method: 'POST', body}));
    assert.equal(result.status, 502); assert.deepEqual(await result.json(), {code: 'proxy_unavailable'});
    assert.equal(calls, 0); assert.equal(cancelled, 1);
  });
  test(name + ' aborted upstream stays unknown when cancellation stalls or rejects', async () => {
    for (const outcome of ['stall', 'reject']) {
      let calls = 0; let cancelled = 0; let started; let rejectPull;
      const waiting = new Promise(resolve => { started = resolve; });
      const body = new ReadableStream({
        pull() { started(); return new Promise((_, reject) => { rejectPull = reject; }); },
        cancel() { cancelled++; return outcome === 'stall' ? new Promise(() => {}) : Promise.reject(Error('synthetic cancel')); },
      });
      const handle = create({frontendOrigin: origin, fetchImpl: async () => { calls++; return new Response(body); }});
      const controller = new AbortController();
      const pending = handle(request('/v1/query/public-collections', {method: 'POST', body: fragmented('a'), signal: controller.signal}));
      await waiting; controller.abort();
      const result = await pending;
      assert.equal(result.status, 504);
      assert.deepEqual(await result.json(), {code: 'proxy_outcome_unknown', reason: 'proxy_deadline'});
      assert.equal(calls, 1); assert.equal(cancelled, 1);
      rejectPull(Error('synthetic late pull failure'));
      await new Promise(resolve => setImmediate(resolve));
    }
  });
}
