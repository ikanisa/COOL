import test from 'node:test';
import assert from 'node:assert/strict';
import {identifySmartImport, previewSmartOnboardingImport, SMART_IMPORT_LIMITS} from '../../domain/burimunsi/smart-onboarding-import.js';
import {applicationWork, guardedFetch, noteUnknownEffect, openApplicationWork} from '../../application-fence.js';
import {syntheticFenceBackend, SYNTHETIC_FENCE_SOURCE} from '../helpers/fenced-unit.js';

const utf8 = value => new TextEncoder().encode(value);
const fakeKey = 'synthetic-test-key';
const fence = {trackPromise: promise => promise, onUncertain: () => {}};
const build = 'a'.repeat(64);
const decoder = handler => ({
  buildSha256: build,
  requestId: '6d746d3b-474f-4a97-a032-d80e61f44cb1',
  reservationId: '71c99d1d-5db6-4c72-9c79-cd14e6c07f70',
  port: {fetch: handler},
});
const jsonResponse = value => new Response(JSON.stringify(value), {headers: {'content-type': 'application/json'}});
const assistantOutput = rows => ({type: 'message', role: 'assistant', status: 'completed', content: [
    {type: 'output_text', text: JSON.stringify({rows}), annotations: []},
  ]});
const validOutput = rows => jsonResponse({
  object: 'response', status: 'completed', error: null, incomplete_details: null, tools: [],
  output: [assistantOutput(rows)],
});
const decoderPort = content => decoder(async request => {
  const body = await request.json();
  return jsonResponse({source_sha256: body.source_sha256, decoder_build_sha256: body.decoder_build_sha256,
    content: content(body)});
});
const image = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
const imageDecoder = () => decoderPort(body => [{type: 'input_image', image_url: `data:${body.mime_type};base64,${body.content_base64}`}]);

test('CSV parses quoted fields, normalizes phones and detects duplicate rows', async () => {
  const bytes = utf8('\ufeffMoMo name,MoMo number\r\n"Niyonsaba, Aline",0781234567\r\nSecond, +250 781 234 567\r\nBlank,invalid\r\n');
  const preview = await previewSmartOnboardingImport({bytes, mimeType: 'text/csv'});
  assert.equal(preview.sourceKind, 'csv');
  assert.deepEqual(preview.rows.map(row => [row.row, row.momoName, row.momoNumber, row.status, row.issue, row.selected]), [
    [1, 'Niyonsaba, Aline', '+250781234567', 'ready', null, true],
    [2, 'Second', '+250781234567', 'duplicate_in_file', 'duplicate_phone', false],
    [3, 'Blank', 'invalid', 'invalid', 'invalid_phone', false],
  ]);
});

test('CSV accepts multilingual headers and preserves invalid values for correction', async () => {
  const data = utf8('Nom du membre,Nom MoMo,Numéro MoMo\nAlice,Momo Alice,0781234567\nLéa,,078???\n');
  const result = await previewSmartOnboardingImport({bytes: data, mimeType: 'text/plain; charset=utf-8'});
  assert.equal(result.rows[0].momoName, 'Momo Alice');
  assert.equal(result.rows[1].momoNumber, '078???');
  assert.equal(result.rows[1].status, 'invalid');
});

test('rejects malformed CSV, binary or misleading file types without external calls', async () => {
  const bad = [
    ['name,phone\n"unterminated,0781234567', 'text/csv'],
    ['name,phone\n"closed"oops,0781234567', 'text/csv'],
    ['name,other\nAlice,123', 'text/csv'],
    ['name,phone\nAl\u0000ice,0781234567', 'text/csv'],
    ['name,phone\nAlice,0781234567', 'image/png'],
  ];
  for (const [text, mimeType] of bad) await assert.rejects(previewSmartOnboardingImport({bytes: utf8(text), mimeType}));
  assert.throws(() => identifySmartImport(new Uint8Array(0), 'text/csv'), /smart_import_size_invalid/);
  assert.throws(() => identifySmartImport(new Uint8Array(SMART_IMPORT_LIMITS.documentBytes + 1), 'text/csv'), /smart_import_size_invalid/);
  assert.throws(() => identifySmartImport(new Uint8Array([0xff, 0x00]), 'text/csv'), /smart_import_csv_invalid/);
});

test('enforces row, column and individual-field limits', async () => {
  const header = 'name,phone\n';
  const row = 'User Name,0781234567\n';
  await assert.rejects(previewSmartOnboardingImport({bytes: utf8(header + row.repeat(501)), mimeType: 'text/csv'}), /smart_import_rows_limit/);
  await assert.rejects(previewSmartOnboardingImport({bytes: utf8(header + 'x'.repeat(1025) + ',0781234567'), mimeType: 'text/csv'}), /smart_import_csv_invalid/);
  await assert.rejects(previewSmartOnboardingImport({bytes: utf8(header + Array(34).fill('a').join(',')), mimeType: 'text/csv'}), /smart_import_csv_invalid/);
});

test('XLSX uses signed decoder output and never calls OpenAI', async () => {
  const bytes = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0, 0]);
  let decoded = 0;
  const d = decoderPort(body => {
    decoded++;
    assert.equal(body.mime_type, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    return [{type: 'input_text', text: 'Member name\tMoMo name\tMoMo number\nAlice\tMOMO ALICE\t0781234567'}];
  });
  const result = await previewSmartOnboardingImport({bytes, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', decoder: d});
  assert.equal(decoded, 1);
  assert.equal(result.sourceKind, 'xlsx');
  assert.equal(result.rows[0].momoName, 'MOMO ALICE');
  assert.equal(result.rows[0].momoNumber, '+250781234567');
});

test('image requires affirmative OCR consent before decoder or provider access', async () => {
  let calls = 0;
  const d = decoderPort(() => {calls++; return [];});
  await assert.rejects(previewSmartOnboardingImport({bytes: image, mimeType: 'image/png', decoder: d,
    ocr: {consent: false, apiKey: fakeKey, model: 'vision-test', fetchImpl: () => {calls++;}}}), /smart_import_consent_required/);
  assert.equal(calls, 0);
});

test('authorized image OCR uses configured model, signed bytes and no retention', async () => {
  let calls = 0;
  const result = await previewSmartOnboardingImport({bytes: image, mimeType: 'image/png', decoder: imageDecoder(),
    ocr: {...fence, consent: true, apiKey: fakeKey, model: 'vision-test', fetchImpl: async (url, options) => {
      calls++;
      assert.equal(url, 'https://api.openai.com/v1/responses');
      assert.equal(options.redirect, 'error');
      assert.equal(options.headers.Authorization, `Bearer ${fakeKey}`);
      const body = JSON.parse(options.body);
      assert.equal(body.store, false);
      assert.equal(body.model, 'vision-test');
      assert.deepEqual(body.tools, []);
      assert.equal(body.text.format.strict, true);
      assert.equal(body.input[0].content[0].type, 'input_image');
      return validOutput([{momoName: 'Alice', momoNumber: '0781234567'}]);
    }},
  });
  assert.equal(calls, 1);
  assert.equal(result.sourceKind, 'image');
  assert.equal(result.rows[0].momoNumber, '+250781234567');
  assert.equal(JSON.stringify(result).includes(fakeKey), false);
  assert.equal(JSON.stringify(result).includes('base64'), false);
});

test('PDF preserves validated source as an input_file and does not resend on failure', async () => {
  const bytes = utf8('%PDF-1.7\nsynthetic'); let calls = 0;
  const d = decoderPort(body => [{type: 'input_file', filename: 'roster.pdf', file_data: `data:application/pdf;base64,${body.content_base64}`}]);
  await assert.rejects(previewSmartOnboardingImport({bytes, mimeType: 'application/pdf', decoder: d,
    ocr: {...fence, consent: true, apiKey: fakeKey, model: 'vision-test', fetchImpl: async (_url, options) => {
      calls++; assert.equal(JSON.parse(options.body).input[0].content[0].type, 'input_file');
      throw new Error('network lost');
    }}}), /smart_import_ocr_unconfirmed/);
  assert.equal(calls, 1);
});

test('decoder must be available, return exact lineage and retain original bytes', async () => {
  const ocr = {...fence, consent: true, apiKey: fakeKey, model: 'vision-test', fetchImpl: async () => validOutput([])};
  await assert.rejects(previewSmartOnboardingImport({bytes: image, mimeType: 'image/png', ocr}), /smart_import_decoder_unavailable/);
  const wrongHash = decoder(async () => jsonResponse({source_sha256: 'b'.repeat(64), decoder_build_sha256: build, content: []}));
  await assert.rejects(previewSmartOnboardingImport({bytes: image, mimeType: 'image/png', decoder: wrongHash, ocr}), /smart_import_decoder_invalid/);
  const wrongData = decoderPort(() => [{type: 'input_image', image_url: 'https://example.invalid/other.png'}]);
  await assert.rejects(previewSmartOnboardingImport({bytes: image, mimeType: 'image/png', decoder: wrongData, ocr}), /smart_import_decoder_invalid/);
});

test('malformed, refused and oversized provider output never yields import rows', async () => {
  const values = [
    {object:'response',status:'incomplete',output:[]},
    {object:'response',status:'completed',output:[{type:'message',role:'assistant',status:'completed',content:[{type:'refusal',refusal:'no'}]}]},
    {object:'response',status:'completed',output:[{type:'message',role:'assistant',status:'completed',content:[{type:'output_text',text:'{"rows":[{"momoName":"A","momoNumber":"B","extra":1}]}',annotations:[]}]}]},
  ];
  for (const v of values) await assert.rejects(previewSmartOnboardingImport({bytes: image, mimeType: 'image/png', decoder: imageDecoder(),
    ocr: {...fence, consent: true, apiKey: fakeKey, model: 'vision-test', fetchImpl: async () => jsonResponse(v)}}));
  await assert.rejects(previewSmartOnboardingImport({bytes: image, mimeType:'image/png',decoder:imageDecoder(),
    ocr:{...fence,consent:true,apiKey:fakeKey,model:'vision-test',fetchImpl:async()=>new Response('x'.repeat(SMART_IMPORT_LIMITS.providerResponseBytes+1))}}));
});

test('OCR accepts declared reasoning metadata with exactly one completed assistant result', async () => {
  const rows = [{momoName: 'Alice', momoNumber: '0781234567'}];
  const minimal = {type: 'reasoning', id: 'rs_synthetic', summary: []};
  const declared = {...minimal, status: 'completed', encrypted_content: 'synthetic-opaque-metadata',
    summary: [{type: 'summary_text', text: '{"rows":[{"momoName":"Ignored","momoNumber":"0790000000"}]}'}],
    content: [{type: 'reasoning_text', text: 'Synthetic metadata is not an import row.'}]};
  for (const output of [[minimal, assistantOutput(rows)], [assistantOutput(rows), declared],
    [{...minimal, encrypted_content: null}, declared, assistantOutput(rows)]]) {
    let calls = 0;
    const result = await previewSmartOnboardingImport({bytes: image, mimeType: 'image/png', decoder: imageDecoder(),
      ocr: {...fence, consent: true, apiKey: fakeKey, model: 'vision-test', fetchImpl: async () => {
        calls++;
        return jsonResponse({object: 'response', status: 'completed', error: null, incomplete_details: null, tools: [], output});
      }}});
    assert.equal(calls, 1);
    assert.deepEqual(result.rows.map(row => [row.momoName, row.momoNumber]), [['Alice', '+250781234567']]);
  }
});

test('OCR rejects tools, unknown items, refusals and ambiguous or incomplete assistant results beside metadata', async () => {
  const reasoning = {type: 'reasoning', id: 'rs_synthetic', summary: []};
  const message = assistantOutput([]);
  const invalidOutputs = [
    [], [reasoning], [reasoning, message, message],
    ...['function_call', 'web_search_call', 'computer_call', 'compaction', 'unknown'].map(type => [reasoning, message, {type}]),
    [reasoning, {...message, role: 'user'}],
    ...['in_progress', 'incomplete'].map(status => [reasoning, {...message, status}]),
    [reasoning, {...message, content: [{type: 'refusal', refusal: 'Synthetic refusal.'}]}],
    [reasoning, {...message, content: [...message.content, ...message.content]}],
    [reasoning, {...message, content: [{...message.content[0], annotations: [{type: 'url_citation'}]}]}],
    [reasoning, message, null],
  ];
  for (const output of invalidOutputs) await assert.rejects(previewSmartOnboardingImport({
    bytes: image, mimeType: 'image/png', decoder: imageDecoder(),
    ocr: {...fence, consent: true, apiKey: fakeKey, model: 'vision-test', fetchImpl: async () => jsonResponse({
      object: 'response', status: 'completed', error: null, incomplete_details: null, tools: [], output,
    })}}), /smart_import_ocr_invalid/);
  for (const override of [{tools: [{type: 'function'}]}, {status: 'incomplete'},
    {error: {code: 'synthetic'}}, {incomplete_details: {reason: 'max_output_tokens'}}]) {
    await assert.rejects(previewSmartOnboardingImport({bytes: image, mimeType: 'image/png', decoder: imageDecoder(),
      ocr: {...fence, consent: true, apiKey: fakeKey, model: 'vision-test', fetchImpl: async () => jsonResponse({
        object: 'response', status: 'completed', error: null, incomplete_details: null, tools: [],
        output: [reasoning, message], ...override,
      })}}), /smart_import_ocr_invalid/);
  }
});

test('OCR rejects undeclared, malformed or unfinished reasoning metadata', async () => {
  const reasoning = {type: 'reasoning', id: 'rs_synthetic', summary: []};
  const invalidMetadata = [
    {...reasoning, id: null}, {...reasoning, id: ''}, {...reasoning, summary: null},
    {...reasoning, summary: [{type: 'output_text', text: '{"rows":[]}'}]},
    {...reasoning, summary: [{type: 'summary_text', text: 123}]},
    {...reasoning, summary: [{type: 'summary_text', text: 'metadata', tool: 'undeclared'}]},
    {...reasoning, content: null}, {...reasoning, content: [{type: 'output_text', text: '{"rows":[]}'}]},
    {...reasoning, encrypted_content: 123}, {...reasoning, status: 'incomplete'},
    {...reasoning, status: 'in_progress'}, {...reasoning, tool_calls: []},
  ];
  for (const metadata of invalidMetadata) await assert.rejects(previewSmartOnboardingImport({
    bytes: image, mimeType: 'image/png', decoder: imageDecoder(),
    ocr: {...fence, consent: true, apiKey: fakeKey, model: 'vision-test', fetchImpl: async () => jsonResponse({
      object: 'response', status: 'completed', error: null, incomplete_details: null, tools: [],
      output: [metadata, assistantOutput([])],
    })}}), /smart_import_ocr_invalid/);
});

test('missing fenced response ownership fails before decoder or provider work', async () => {
  let calls=0;
  const d=decoderPort(body=>{calls++;return [{type:'input_image',image_url:`data:${body.mime_type};base64,${body.content_base64}`}];});
  await assert.rejects(previewSmartOnboardingImport({bytes:image,mimeType:'image/png',decoder:d,
    ocr:{consent:true,apiKey:fakeKey,model:'vision-test',fetchImpl:async()=>{calls++;return validOutput([]);}}}),/smart_import_ocr_unavailable/);
  assert.equal(calls,0);
});

test('a stalled provider body is bounded, owned and left uncertain without redispatch', async () => {
  let calls=0,tracked=0,uncertain=0,cancelled=0;
  const keepalive=setTimeout(()=>{},2000);
  const body=new ReadableStream({pull:()=>new Promise(()=>{}),cancel:()=>{cancelled++;}});
  try{
    await assert.rejects(previewSmartOnboardingImport({bytes:image,mimeType:'image/png',decoder:imageDecoder(),
      ocr:{consent:true,apiKey:fakeKey,model:'vision-test',timeoutMs:20,
        trackPromise:promise=>{tracked++;return promise;},onUncertain:()=>{uncertain++;},
        fetchImpl:async()=>{calls++;return new Response(body,{headers:{'content-type':'application/json'}});}}}),/smart_import_ocr_unconfirmed/);
  }finally{clearTimeout(keepalive);}
  assert.equal(calls,1);assert.ok(tracked>=1);assert.ok(uncertain>=1);assert.equal(cancelled,1);
});

test('a truncated declared provider response is rejected and marked uncertain', async () => {
  let uncertain=0;const body=JSON.stringify({object:'response',status:'completed',output:[]});
  await assert.rejects(previewSmartOnboardingImport({bytes:image,mimeType:'image/png',decoder:imageDecoder(),
    ocr:{...fence,consent:true,apiKey:fakeKey,model:'vision-test',onUncertain:()=>{uncertain++;},
      fetchImpl:async()=>new Response(body,{headers:{'content-type':'application/json','content-length':String(utf8(body).length+1)}})}}),/smart_import_ocr_invalid/);
  assert.ok(uncertain>=1);
});


test('a provider timeout is retained by the real application fence until cancellation settles', async () => {
  const backend=syntheticFenceBackend();
  const work=await openApplicationWork({backend,sourceSha256:SYNTHETIC_FENCE_SOURCE,kind:'http_collect'});
  const env={COLLECT_FENCE_WORK:work};
  let calls=0,cancelled=0;const originalFetch=globalThis.fetch,keepalive=setTimeout(()=>{},2000);
  globalThis.fetch=async()=>{calls++;return new Response(new ReadableStream({
    pull:()=>new Promise(()=>{}),cancel:()=>{cancelled++;},
  }),{headers:{'content-type':'application/json'}});};
  try {
    await assert.rejects(previewSmartOnboardingImport({bytes:image,mimeType:'image/png',decoder:imageDecoder(),
      ocr:{consent:true,apiKey:fakeKey,model:'vision-test',timeoutMs:20,
        fetchImpl:(...args)=>guardedFetch(env,'ai',...args),
        trackPromise:promise=>applicationWork(env).waitUntil(promise),
        onUncertain:()=>noteUnknownEffect(env,'ai')}}),/smart_import_ocr_unconfirmed/);
    const outcome=await work.finish({failed:true});
    assert.equal(outcome.state,'settled');
    assert.equal(outcome.reason,'completed_with_unknown_obligation');
    assert.equal(outcome.externalDispatches,1);
    assert.equal(outcome.uncertainDispatches,1);
    assert.equal(calls,1);assert.equal(cancelled,1);
  } finally {globalThis.fetch=originalFetch;clearTimeout(keepalive);}
});


test('encoded response length is not compared to decoded fetch body length', async () => {
  const body=JSON.stringify({object:'response',status:'completed',error:null,incomplete_details:null,tools:[],
    output:[{type:'message',role:'assistant',status:'completed',content:[{type:'output_text',text:'{\"rows\":[]}',annotations:[]}]}]});
  const result=await previewSmartOnboardingImport({bytes:image,mimeType:'image/png',decoder:imageDecoder(),
    ocr:{...fence,consent:true,apiKey:fakeKey,model:'vision-test',fetchImpl:async()=>new Response(body,
      {headers:{'content-type':'application/json','content-encoding':'gzip','content-length':'1'}})}});
  assert.deepEqual(result.rows,[]);
});

test('failure to record an uncertain dispatch is surfaced and the body is cancelled', async () => {
  const sentinel=new Error('synthetic fence unavailable');let cancelled=0;
  const body=new ReadableStream({cancel:()=>{cancelled++;}});
  await assert.rejects(previewSmartOnboardingImport({bytes:image,mimeType:'image/png',decoder:imageDecoder(),
    ocr:{...fence,consent:true,apiKey:fakeKey,model:'vision-test',onUncertain:()=>{throw sentinel;},
      fetchImpl:async()=>new Response(body,{headers:{'content-type':'text/plain'}})}}),error=>error===sentinel);
  assert.equal(cancelled,1);
});


test('a late provider response cannot outlive its fenced request', async () => {
  const backend=syntheticFenceBackend();
  const work=await openApplicationWork({backend,sourceSha256:SYNTHETIC_FENCE_SOURCE,kind:'http_collect'});
  const env={COLLECT_FENCE_WORK:work};
  let releaseFetch,cancelled=0,closed=false;
  const originalFetch=globalThis.fetch,keepalive=setTimeout(()=>{},2000);
  globalThis.fetch=()=>new Promise(resolve=>{releaseFetch=resolve;});
  try {
    await assert.rejects(previewSmartOnboardingImport({bytes:image,mimeType:'image/png',decoder:imageDecoder(),
      ocr:{consent:true,apiKey:fakeKey,model:'vision-test',timeoutMs:20,
        fetchImpl:(...args)=>guardedFetch(env,'ai',...args),
        trackPromise:promise=>applicationWork(env).waitUntil(promise),
        onUncertain:()=>noteUnknownEffect(env,'ai')}}),/smart_import_ocr_unconfirmed/);
    const closing=work.finish({failed:true}).then(result=>{closed=true;return result;});
    await new Promise(resolve=>setTimeout(resolve,10));
    assert.equal(closed,false);
    releaseFetch(new Response(new ReadableStream({cancel:()=>{cancelled++;}}),
      {headers:{'content-type':'application/json'}}));
    const outcome=await closing;
    assert.equal(cancelled,1);
    assert.equal(outcome.reason,'completed_with_unknown_obligation');
    assert.equal(outcome.uncertainDispatches,1);
  } finally {globalThis.fetch=originalFetch;clearTimeout(keepalive);}
});
