import {test} from 'node:test';
import assert from 'node:assert/strict';
import {registerHooks} from 'node:module';
import {readJson} from '../../../supabase/functions/_shared/domain/core.js';

await import('../../../supabase/functions/_shared/tests/helpers/node-postgres-import.mjs');
registerHooks({resolve(specifier, context, next) {
  if (specifier === './momo_gateway.js' && context.parentURL?.endsWith('/domain/index.js')) {
    return {url: 'data:text/javascript,export async function momoGatewayRoute(){return new Response(null,{status:202})}', shortCircuit: true};
  }
  return next(specifier, context);
}});
const {adminRpc} = await import('../../../supabase/functions/_shared/domain/admin.js');
const {default: worker} = await import('../../../supabase/functions/_shared/domain/index.js');

test('oversize streamed JSON reports 413 when cancellation rejects or never resolves', async () => {
  for (const cancel of [() => Promise.reject(Error('synthetic cancellation failure')), () => new Promise(() => {})]) {
    let released = false;
    const request = {headers: new Headers({'content-type': 'application/json'}), body: {getReader: () => ({
      read: async () => ({done: false, value: new Uint8Array(4)}), cancel,
      releaseLock: () => { released = true; },
    })}};
    const result = await Promise.race([
      readJson(request, 3).then(() => 'unexpected_success', error => error.code),
      new Promise(resolve => setTimeout(() => resolve('timeout'), 200)),
    ]);
    assert.equal(result, 'request_too_large');
    assert.equal(released, true);
  }
});

test('admin payment evidence follows stored authenticity and rejects missing evidence', async () => {
  const actor = {permissions: new Set(['payments.read'])};
  const envFor = authenticity => ({DB: {prepare(sql) { return {bind() { return {
    first: async () => ({n: 1}),
    all: async () => ({results: [{id: 'p', payer_display_name: 'A', status: 'confirmed', evidence_authenticity: authenticity}]}),
  }; }}; }}});
  const result = await adminRpc('admin_list_payments', {}, envFor('operator_recorded'), actor);
  assert.equal(result.value.rows[0].evidence_level, 'operator_recorded');
  await assert.rejects(() => adminRpc('admin_list_payments', {}, envFor(null), actor), e => e.status === 503 && e.code === 'invalid_source_data');
});

test('missing queue policy is unavailable instead of fabricated', async () => {
  await assert.rejects(() => adminRpc('admin_get_queue_sla', {}, {}, {permissions: new Set(['overview.read'])}), e => e.status === 503 && e.code === 'queue_sla_unavailable');
});

test('shared entrypoint does not schedule processing after receipt ingest', async () => {
  const tasks = [];
  const ctx = {waitUntil: promise => tasks.push(promise)};
  await worker.scheduled({}, {MOMO_PROCESSING_PAUSED: 'false'}, ctx);
  const response = await worker.fetch(new Request('https://fixture.example/gateway/ingest', {method: 'POST'}), {ALLOWED_ORIGINS: '', MOMO_PROCESSING_PAUSED: 'false'}, ctx);
  assert.equal(response.status, 202);
  assert.equal(tasks.length, 0);
});
