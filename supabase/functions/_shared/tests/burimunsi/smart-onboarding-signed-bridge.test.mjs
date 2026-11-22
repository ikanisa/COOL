/** Cross-module contract only: the supervisor and OpenAI are synthetic.
 * This executes the real signed bridge and onboarding preview together; it
 * does not qualify the native decoder, network fence, provider, or live data. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,createHmac,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRosterDecoderBridge} from '../../roster_decoder_bridge.mjs';
import {previewSmartOnboardingImport} from '../../domain/burimunsi/smart-onboarding-import.js';

const secret='synthetic-roster-bridge-signing-key-0123456789';
const build='a'.repeat(64),endpoint='https://decoder.example.invalid/decode';
const key='synthetic-provider-key';
const toolchain={python:'3.12',pillow:'12.3.0',pypdfium2:'5.2.0',pypdf:'6.19.0',openpyxl:'3.1.5',defusedxml:'0.7.1'};
const corpus=new URL('../../../../../tools/roster-decoder/native-probe/corpus/',import.meta.url);
const hash=value=>createHash('sha256').update(value).digest('hex');
const rows=[{momoName:'Example Member',momoNumber:'0781234567'}];
const providerResponse=()=>Response.json({object:'response',status:'completed',error:null,incomplete_details:null,tools:[],
 output:[{type:'message',role:'assistant',status:'completed',content:[{type:'output_text',annotations:[],text:JSON.stringify({rows})}]}]});

function fixture({badSignature=false,animated=false}={}){
 const calls={decoder:0,provider:0,uncertain:0};
 const port=createRosterDecoderBridge({protocol:'roster-hmac-v1',endpoint,secret,approvedBuildSha256:build,
  onUncertain:()=>calls.uncertain++,fetchImpl:async(url,init)=>{
   calls.decoder++;assert.equal(url,endpoint);assert.equal(init.redirect,'error');
   assert.equal(init.headers.Authorization,'Roster-HMAC '+createHmac('sha256',secret).update(init.body).digest('hex'));
   const wire=JSON.parse(init.body),derived=wire.kind==='xlsx'?'Member name\tMoMo name\tMoMo number\nExample\tExample Member\t0781234567':null;
   const frames=wire.kind==='image'?(animated?2:1):0;
   const payload=JSON.stringify({contract_version:1,request_id:wire.request_id,reservation_id:wire.reservation_id,nonce:wire.nonce,
    issued_at:Math.floor(Date.now()/1000),kind:wire.kind,mime:wire.mime,decoder_build_sha256:build,ok:true,
    policy_version:'collect-roster-decoder-v1',toolchain,source_sha256:wire.source_sha256,
    source_size:Buffer.from(wire.content_base64,'base64').length,derived_sha256:derived===null?null:hash(derived),
    frames,pages:wire.kind==='pdf'?1:0,pixels:wire.kind==='image'?frames:wire.kind==='pdf'?1:0,
    expanded_bytes:wire.kind==='image'?frames*4:0,derived_content:derived});
   return Response.json({payload,signature:badSignature?'0'.repeat(64):createHmac('sha256',secret).update(payload).digest('hex')});
  }});
 const decoder={port,buildSha256:build,requestId:randomUUID(),reservationId:randomUUID()};
 const ocr={consent:true,apiKey:key,model:'fixture-vision',trackPromise:promise=>promise,onUncertain:()=>calls.uncertain++,fetchImpl:async(url,init)=>{
  calls.provider++;assert.equal(url,'https://api.openai.com/v1/responses');assert.equal(init.redirect,'error');
  assert.equal(init.headers.Authorization,`Bearer ${key}`);assert.equal(JSON.parse(init.body).store,false);return providerResponse();
 }};
 return {decoder,ocr,calls};
}

for(const [filename,mime,kind] of [
 ['scanned-multilingual.png','image/png','image'],['scanned-multilingual.pdf','application/pdf','pdf'],
 ['multilingual.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','xlsx'],
])test('onboarding preview accepts a verified signed '+kind+' bridge response',async()=>{
 const f=fixture(),bytes=new Uint8Array(await readFile(new URL(filename,corpus)));
 const result=await previewSmartOnboardingImport({bytes,mimeType:mime,decoder:f.decoder,ocr:f.ocr});
 assert.equal(result.sourceKind,kind);assert.equal(result.rows[0].momoName,'Example Member');
 assert.equal(result.rows[0].momoNumber,'+250781234567');assert.equal(f.calls.decoder,1);
 assert.equal(f.calls.provider,kind==='xlsx'?0:1);
});

test('signature failure or animated image cannot dispatch to the provider',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus)));
 for(const options of [{badSignature:true},{animated:true}]){
  const f=fixture(options);
  await assert.rejects(previewSmartOnboardingImport({bytes,mimeType:'image/png',decoder:f.decoder,ocr:f.ocr}),/smart_import_decoder_unavailable/);
  assert.equal(f.calls.decoder,1);assert.equal(f.calls.provider,0);
 }
});

test('missing consent prevents both decoder and provider dispatch',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=fixture();f.ocr.consent=false;
 await assert.rejects(previewSmartOnboardingImport({bytes,mimeType:'image/png',decoder:f.decoder,ocr:f.ocr}),/smart_import_consent_required/);
 assert.equal(f.calls.decoder,0);assert.equal(f.calls.provider,0);
});
