import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { openApplicationWork } from '../../application-fence.js';
import { createOpenSmsReceiptTransport } from '../../opensms-receipts.js';
import { drainBuriMunsiPaymentSms, scheduledPaymentSmsResult } from '../../domain/burimunsi/payment-sms-delivery.mjs';
import { renderPaymentSms } from '../../domain/burimunsi/payment-sms-template.mjs';

const sha = x => createHash('sha256').update(x).digest('hex');
const group = '11111111-1111-4111-8111-111111111111';
const scope = 'app_synthetic';
const project = 'https://rrlduytparvsjfmegalh.supabase.co';
const source = 'a'.repeat(64);
const to = '+250780000000';
const point = '2026-11-18T22:05:00.000Z';
const reference = 'FIXTURE-01';
const text = 'BuriMunsi: Ubwizigame bwa 1,250 RWF bwanditswe. Igiteranyo cyawe cyanditswe muri iri tsinda ku 2026-11-19 00:05 CAT: 28,750 RWF. Ref: FIXTURE-01.';
const row = {
  phase: 'send', collection_id: group, application_id: scope,
  attempt_id: '22222222-2222-4222-8222-222222222222', claim_token: '33333333-3333-4333-8333-333333333333',
  message_id: scope + ':payment:entry-1', idempotency_key: 'payment:entry-1', destination: to, destination_sha256: sha(to),
  posted_at: point, posted_reference: reference, amount_rwf: 1250, member_balance_rwf: 28750,
  not_after: '2026-11-19T00:05:00.000Z',
};
const available = {
  BURIMUNSI_PAYMENT_SMS_ENABLED: 'true', BURIMUNSI_PAYMENT_SMS_COLLECTION_ID: group,
  BURIMUNSI_PAYMENT_SMS_ENABLED_AT: '2026-11-18T12:00:00.000Z',
  COLLECT_RECEIPT_SMS_ENABLED: 'true', COLLECT_RECEIPT_SMS_APPROVAL_SHA256: 'b'.repeat(64),
  OPENSMS_RECEIPT_APPLICATION_ID: scope, OPENSMS_RECEIPT_APPLICATION_TOKEN: 'synthetic_key'.repeat(3),
  OPENSMS_RECEIPT_BASE_URL: project + '/functions/v1/collect-sms', SUPABASE_URL: project, APP_ENVIRONMENT: 'production',
  COLLECT_SMS_ENABLED: 'true', COLLECT_SMS_DISPATCH_PAUSED: 'false', COLLECT_SMS_CORE_SOURCE_SHA256: source, BUILD_SOURCE_ID: source,
};

async function run({ job = row, prepare = 'prepared', lost = false, config = {}, transportFactory } = {}) {
  let admission;
  const backend = {
    async register(id, sourceSha256, kind) {
      admission = { contractVersion: 1, admissionId: id, epoch: 1, sourceSha256, kind, state: 'active', mode: 'open' };
      return admission;
    },
    async lease() { return { row: admission, assert: async () => admission, release: async () => {} }; },
    async status() { return {...admission, found: admission !== undefined}; },
    async close(id, epoch, sourceSha256, state, reason, externalDispatches, uncertainDispatches) {
      return { ...admission, state, reason, externalDispatches, uncertainDispatches };
    },
  };
  const work = await openApplicationWork({ backend, sourceSha256: source, kind: 'jobs' });
  const operations = [];
  const database = {
    applicationWork: work, async context() {},
    async transaction(f) {
      return f({ async unsafe(sql, args) {
        const op = /private\.burimunsi_(\w+)_payment_sms/.exec(sql)?.[1];
        operations.push([op, args]);
        return [{ result: op === 'claim' ? (job ? [job] : []) : op === 'prepare' ? prepare : true }];
      } });
    },
  };
  const outcome = { providerAccepted: true, state: 'delivered', evidenceSha256: 'c'.repeat(64) };
  const makeTransport = () => ({
    async submit(message) {
      operations.push(['post', message]);
      if (lost) throw Error('synthetic missed reply');
      return outcome;
    },
    async inspectRecorded(message) { operations.push(['get', message]); return outcome; },
  });
  try {
    const result = await drainBuriMunsiPaymentSms(
      { ...available, ...config, DB: database, COLLECT_FENCE_WORK: work }, { makeTransport: transportFactory ?? makeTransport },
    );
    return { result, operations };
  } finally {
    await work.finish();
  }
}

test('renders the retained Kinyarwanda v2 wording and Kigali midnight with the original member balance', () => {
  assert.equal(renderPaymentSms({ amount: 1250, memberBalance: 28750, recordedAt: point, reference }), text);
  assert.throws(() => renderPaymentSms({ amount: 1250, memberBalance: 28750, recordedAt: point, reference: 'bad ref' }));
});

test('reserves and arms the exact receipt before the one POST', async () => {
  const { result, operations } = await run();
  assert.deepEqual(operations.map(([k]) => k), ['claim', 'prepare', 'post', 'finish']);
  assert.deepEqual(operations[0][1], [group, available.BURIMUNSI_PAYMENT_SMS_ENABLED_AT, scope, 1]);
  assert.equal(operations[1][1][3], sha(text));
  assert.deepEqual(operations[2][1], { messageId: row.message_id, to, notAfter: row.not_after, text });
  assert.deepEqual(operations[3][1].slice(3), ['accepted', 'delivered', 'c'.repeat(64)]);
  assert.deepEqual(result, {status: 'complete', processed: 1, outcome: 'accepted', gateway_state: 'delivered'});
});

test('changed recipient, a refused prepare or missing eligible work can never POST', async () => {
  const changed = await run({ job: { ...row, destination_sha256: '0'.repeat(64) } });
  assert.deepEqual(changed.operations.map(([op]) => op), ['claim', 'finish']);
  assert.equal(changed.result.outcome, 'suppressed');
  const declined = await run({ prepare: 'suppressed' });
  assert.deepEqual(declined.operations.map(([op]) => op), ['claim', 'prepare']);
  assert.equal(declined.result.outcome, 'suppressed');
  const held = await run({prepare: 'held'});
  assert.deepEqual(held.operations.map(([op]) => op), ['claim', 'prepare']);
  assert.deepEqual(held.result, {status: 'held', processed: 1, outcome: 'held'});
  assert.deepEqual((await run({ job: null })).result, { status: 'complete', processed: 0 });
});

test('lost submission acknowledgement is recorded and the original ID is read with no destination', async () => {
  const missed = await run({ lost: true });
  assert.deepEqual(missed.result, {status: 'unconfirmed', processed: 1, outcome: 'unknown'});
  const original = await run({ job: { ...row, phase: 'inspect', destination: null, body_sha256: sha(text) } });
  assert.deepEqual(original.operations.map(([op]) => op), ['claim', 'get', 'finish']);
  assert.deepEqual(original.operations[1][1], {
    messageId: row.message_id, text, notAfter: row.not_after, destinationSha256: sha(to),
  });
});

function gatewayDetail(state,attempts=[],parts=[]) {
  const available_at='2026-11-18T23:05:00.000Z';
  const values=[row.message_id,scope,'receipt',to,text,'80',row.not_after,available_at,''];
  const payload_digest=sha('collect-sms-payload-v1\n'+values.map(v=>Buffer.byteLength(v)+':'+v).join(''));
  return {message:{message_id:row.message_id,application_id:scope,kind:'receipt',to,text,priority:80,
    not_after:row.not_after,available_at,payload_digest,state,campaign_id:null,content_redacted_at:null,updated_at:point},
    attempts,parts};
}

const attempt=(attempt_id,parts_total)=>({message_id:row.message_id,attempt_id,installation_id:'phone-a',parts_total});
const part=(attempt_id,part_index,fields={})=>({message_id:row.message_id,attempt_id,part_index,
  sent_at:point,delivered_at:null,delivery_failed_at:null,delivery_unknown_at:null,...fields});

test('recovers the exact wire receipt by commitment and rejects the wrong phone using only GET', async () => {
  let reads = 0;
  const transport = createOpenSmsReceiptTransport({
    origin: available.OPENSMS_RECEIPT_BASE_URL, applicationId: scope, token: available.OPENSMS_RECEIPT_APPLICATION_TOKEN,
  }, { fetchImpl: async (url, options) => {
    assert.equal(options.method, 'GET');
    assert.equal(url, available.OPENSMS_RECEIPT_BASE_URL + '/v1/messages/' + encodeURIComponent(row.message_id));
    reads++;
    return Response.json(gatewayDetail('delivered',[attempt('original',1)],[part('original',0,{delivered_at:point})]));
  } });
  const stored = { messageId: row.message_id, text, notAfter: row.not_after, destinationSha256: sha(to) };
  assert.equal((await transport.inspectRecorded(stored)).state, 'delivered');
  await assert.rejects(transport.inspectRecorded({ ...stored, destinationSha256: '0'.repeat(64) }), /opensms_receipt_unconfirmed/);
  assert.equal(reads, 2);
});

test('default-off and rejects a drifted gateway target or pause before any work', async () => {
  const result = await run({ config: { BURIMUNSI_PAYMENT_SMS_ENABLED: 'false' } });
  assert.deepEqual(result, { result: { status: 'disabled', processed: 0 }, operations: [] });
  for (const config of [{ OPENSMS_RECEIPT_BASE_URL: 'https://fixture.example' }, { COLLECT_SMS_DISPATCH_PAUSED: 'true' },
    { COLLECT_SMS_CORE_SOURCE_SHA256: 'd'.repeat(64) }]) {
    await assert.rejects(run({ config }), /burimunsi_payment_sms_unconfirmed/);
  }
});

test('BuriMunsi holds a terminal summary without its phone proof and recovers through the original GET',async()=>{
  const requests=[];
  let detail=gatewayDetail('delivered');
  const transportFactory=config=>createOpenSmsReceiptTransport(config,{fetchImpl:async (url,options)=>{
    requests.push([options.method,url]);
    if(options.method==='POST') return Response.json({message_id:row.message_id,state:'accepted'},{status:202});
    return Response.json(detail);
  }});
  const first=await run({transportFactory});
  assert.deepEqual(first.result,{status:'unconfirmed',processed:1,outcome:'unknown'});
  assert.deepEqual(first.operations.at(-1)[1].slice(3),['unknown',null,null]);
  detail=gatewayDetail('delivered',[attempt('first',2)],[
    part('first',1,{delivered_at:point}),part('first',0,{delivered_at:point})]);
  const inspection={...row,phase:'inspect',destination:null,body_sha256:sha(text)};
  const recovered=await run({job:inspection,transportFactory});
  assert.deepEqual(recovered.result,{status:'complete',processed:1,outcome:'accepted',gateway_state:'delivered'});
  assert.deepEqual(recovered.operations.map(([op])=>op),['claim','finish']);
  const [,finish]=recovered.operations.at(-1);
  assert.deepEqual(finish.slice(0,5),[group,row.attempt_id,row.claim_token,'accepted','delivered']);
  assert.match(finish[5],/^[0-9a-f]{64}$/);
  assert.deepEqual(requests.map(([method])=>method),['POST','GET','GET']);
  assert.equal(requests[1][1],requests[2][1]);
  assert.ok(requests[2][1].endsWith('/'+encodeURIComponent(row.message_id)));
});

test('OpenSMS commits complete per-attempt evidence and preserves documented intermediate and uncertainty states',async()=>{
  let detail;
  const transport=createOpenSmsReceiptTransport({origin:available.OPENSMS_RECEIPT_BASE_URL,applicationId:scope,token:'synthetic'},{
    fetchImpl:async()=>Response.json(detail)});
  const original={messageId:row.message_id,to,text,notAfter:row.not_after};
  const observe=async(state,attempts,parts)=>{
    detail=gatewayDetail(state,attempts,parts);return transport.inspect(original);
  };
  const d=(id,n)=>part(id,n,{delivered_at:point});
  const both=[attempt('A',2),attempt('B',2)];
  for (const [attempts,parts] of [
    [both,[d('A',0),d('B',1)]], [both,[d('A',0),d('A',0)]], [both,[d('A',0),d('A',2)]],
    [[{...attempt('A',1),message_id:'other'}],[d('A',0)]],
    [[attempt('A',1)],[{...d('A',0),message_id:'other'}]], [[attempt('A',1)],[part('A',0)]],
    [[attempt('A',1)],[part('A',0,{delivered_at:'invalid'})]], [[attempt('A',1)],[part('A',0,{delivered_at:'2026-02-31T01:00:00Z'})]],
  ]) await assert.rejects(observe('delivered',attempts,parts),/opensms_receipt_unconfirmed/);
  const positive=await observe('delivered',both,[d('A',1),d('A',0),d('B',0)]);
  assert.equal(positive.observation,'observed_sent');
  const reordered=await observe('delivered',both.toReversed(),[d('B',0),d('A',0),d('A',1)]);
  assert.equal(reordered.evidenceSha256,positive.evidenceSha256);
  assert.notEqual((await observe('delivered',both,[d('B',0),d('B',1)])).evidenceSha256,positive.evidenceSha256);
  assert.notEqual((await observe('delivered',both,[d('A',0),{...d('A',1),delivered_at:row.not_after}])).evidenceSha256,positive.evidenceSha256);
  assert.equal((await observe('sent',both,[part('A',0),part('A',1)])).observation,'observed_sent');
  const otherFailed=part('B',0,{sent_at:null,delivery_failed_at:point});
  const otherUnknown=part('B',1,{sent_at:null,delivery_unknown_at:point});
  assert.equal((await observe('sent',both,[part('A',0),part('A',1),otherFailed,otherUnknown])).observation,'observed_sent');
  for (const when of ['2026-11-18T22:05:00Z','2026-11-18T22:05:00.1Z','2026-11-18T22:05:00.12Z','2026-11-18T22:05:00.123Z']) {
    assert.equal((await observe('sent',[attempt('A',1)],[part('A',0,{sent_at:when})])).observation,'observed_sent');
  }
  for (const when of ['2026-11-18T22:05:00.123456Z','2026-11-18T22:05:00+02:00']) {
    await assert.rejects(observe('sent',[attempt('A',1)],[part('A',0,{sent_at:when})]),/opensms_receipt_unconfirmed/);
  }
  const uncertain=part('A',1,{delivery_unknown_at:point});
  const failed=part('A',1,{delivery_failed_at:point});
  await assert.rejects(observe('sent',both,[part('A',0),uncertain]),/opensms_receipt_unconfirmed/);
  await assert.rejects(observe('sent',both,[part('A',0),failed]),/opensms_receipt_unconfirmed/);
  assert.equal((await observe('delivery_unconfirmed',both,[part('A',0),uncertain])).state,'delivery_unconfirmed');
  await assert.rejects(observe('delivery_unconfirmed',both,[part('A',0),part('A',1)]),/opensms_receipt_unconfirmed/);
  for (const [state,observation] of [['queued',null],['failed','uncertain'],['outcome_unknown','uncertain']]) {
    detail=gatewayDetail(state);delete detail.parts;delete detail.attempts;
    const result=await transport.inspect(original);
    assert.equal(result.observation,observation);
    assert.equal(result.evidenceSha256,sha(JSON.stringify({message_id:row.message_id,payload_digest:detail.message.payload_digest,state,updated_at:point})));
  }
});

test('the payer journal and scheduled result keep each legitimate gateway state on the original read-only attempt',async()=>{
  const inspection={...row,phase:'inspect',destination:null,body_sha256:sha(text)};
  const states=['accepted','assigned','phone_accepted','queued','handoff_started','sent','delivered','delivery_unconfirmed',
    'partial','failed','outcome_unknown','cancelled','expired'];
  for (const state of states) {
    const evidenceId='original-phone-attempt';
    const detail=gatewayDetail(state);
    if (['sent','delivered','delivery_unconfirmed','partial'].includes(state)) {
      const fields=state==='delivered'?{delivered_at:point}:state==='delivery_unconfirmed'?{delivery_unknown_at:point}:{};
      detail.attempts.push(attempt(evidenceId,state==='partial'?2:1));
      detail.parts.push(part(evidenceId,0,fields));
    }
    let reads=0;
    const transportFactory=config=>createOpenSmsReceiptTransport(config,{fetchImpl:async(url,options)=>{
      assert.equal(options.method,'GET');assert.ok(url.endsWith('/'+encodeURIComponent(row.message_id)));
      reads++;return Response.json(detail);
    }});
    const {result,operations}=await run({job:inspection,transportFactory});
    assert.equal(reads,1);
    assert.deepEqual(operations.map(([op])=>op),['claim','finish']);
    assert.deepEqual(operations.at(-1)[1].slice(0,5),[group,row.attempt_id,row.claim_token,'accepted',state]);
    assert.deepEqual(scheduledPaymentSmsResult(result),{status:'complete',processed:1,outcome:'accepted',gateway_state:state});
  }
});
