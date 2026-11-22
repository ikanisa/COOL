/** Actual PostgreSQL + Collect AES-GCM, with a synthetic native-authority stub.
 * Explicitly scoped to a locally created scratch database and marker; never run
 * against an existing Collect database. No provider or customer data is used.
 */
import postgres from 'npm:postgres@3.4.7';
import {createHmac} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {openApplicationWork,applicationWork,guardedFetch,noteUnknownEffect} from '../../application-fence.js';
import {createRosterDecoderBridge} from '../../roster_decoder_bridge.mjs';
import {createGuardedSmartOnboardingImport} from '../../domain/burimunsi/smart-onboarding-dispatch.js';
import {createSmartOnboardingPolicy} from '../../domain/burimunsi/smart-onboarding-policy.js';
import {syntheticFenceBackend,SYNTHETIC_FENCE_SOURCE} from '../helpers/fenced-unit.js';
import {digest} from '../../domain/core.js';
import {PostgresSmartOnboardingJournal} from '../../domain/burimunsi/smart-onboarding-journal.js';

const target=Deno.env.get('BURI_SMART_QA_DATABASE_URL');
Deno.test({name:'synthetic PostgreSQL journal custody and source deduplication',ignore:!target,fn:async()=>{
 const url=new URL(target!);
 if(url.protocol!=='postgres:'||url.hostname!=='127.0.0.1'||url.pathname!=='/onboarding_smart_scratch'||
  url.username!=='postgres'||url.password||!url.port||url.search||url.hash)throw new Error('scratch database target required');
 const sql=postgres(target!,{ssl:false,max:4,prepare:false,connect_timeout:3});
 const check=(value:unknown,message:string)=>{if(!value)throw new Error(message);};
 try{
  const marker=await sql.unsafe('SELECT marker FROM private.synthetic_onboarding_fixture_marker');
  check(marker.length===1&&marker[0].marker==='burimunsi-onboarding-synthetic-only-v1','scratch marker required');
  const state={allowed:true,audits:[] as string[]};
  const actorId=crypto.randomUUID(),sessionId=crypto.randomUUID(),groupId='synthetic-'+crypto.randomUUID();
  const actor={id:actorId,sessionId,groupId,principalUserId:'synthetic-principal',role:'staff',active:true,revoked:false,
   capabilities:['members.enroll'],expiresAt:9999999999999};
  const authority={groupId,db:{},async write(fn:(tx:any)=>Promise<unknown>){return sql.begin(async tx=>{
   await tx.unsafe('SET LOCAL ROLE collect_runtime');await tx.unsafe("SELECT set_config('burimunsi.collection_id',$1,true)",[groupId]);
   return fn(tx);});},async session(_tx:any,{id}:{id:string}){return state.allowed&&id===sessionId?actor:null;},
   async audit(_tx:any,_actor:string,action:string){state.audits.push(action);}};
  const env={DATA_KEY_ID:'synthetic-key',DATA_ENCRYPTION_KEY:btoa(String.fromCharCode(...new Uint8Array(32).fill(7)))};
  const journal=new (PostgresSmartOnboardingJournal as any)({authority,env,clock:()=>1000000});
  const base={groupId,actorId,sessionId,sourceSha256:'a'.repeat(64),mimeType:'image/png',
   policySha256:'b'.repeat(64),decoderBuildSha256:'c'.repeat(64),importFlowId:'77777777-7777-4777-8777-777777777777',ocrDisclosureVersion:'burimunsi-ocr-disclosure-v1'};
  const input=()=>({...base,proposedRequestId:crypto.randomUUID(),proposedReservationId:crypto.randomUUID()});
  const [one,two]=await Promise.all([journal.reserve(input()),journal.reserve(input())]);
  check([one.state,two.state].sort().join(',')==='pending,reserved','concurrent duplicate was not suppressed');
  const receipt=one.state==='reserved'?one:two;
  await journal.advance({receipt,sessionId,phase:'decode'});
  await journal.advance({receipt,sessionId,phase:'extract'});
  const preview={sourceKind:'image',rows:[{row:1,momoName:'Synthetic Alice',momoNumber:'+250780000001',
   status:'ready',issue:null,selected:true}]};
  await journal.complete({receipt,sessionId,phase:'extract',preview});
  const saved=await sql.unsafe('SELECT response::text AS saved FROM private.burimunsi_command_receipts WHERE request_id=$1::uuid',[receipt.requestId]);
  check(saved.length===1&&!saved[0].saved.includes('Synthetic Alice')&&!saved[0].saved.includes('+250780000001'),
   'plaintext preview was stored');
  const recovered=await journal.reserve(input());
  check(recovered.state==='completed'&&JSON.stringify(recovered.preview)===JSON.stringify(preview),
   'encrypted original preview was not recovered');
  check(state.audits.filter(x=>x==='burimunsi.smart_import.reserved').length===1&&
   state.audits.filter(x=>x==='burimunsi.smart_import.completed').length===1,'audit identity mismatch');
  state.allowed=false;let denied=false;
  try{await journal.reserve({...input(),sourceSha256:'d'.repeat(64)});}catch{denied=true;}
  check(denied,'revoked actor was accepted');
 }finally{await sql.end({timeout:5});}
}});


Deno.test({name:'synthetic signed decoder and provider flow with real PostgreSQL recovery',ignore:!target,fn:async()=>{
 const url=new URL(target!);
 if(url.protocol!=='postgres:'||url.hostname!=='127.0.0.1'||url.pathname!=='/onboarding_smart_scratch'||
  url.username!=='postgres'||url.password||!url.port||url.search||url.hash)throw new Error('scratch database target required');
 const sql=postgres(target!,{ssl:false,max:2,prepare:false,connect_timeout:3});
 const work=await (openApplicationWork as any)({backend:syntheticFenceBackend(),sourceSha256:SYNTHETIC_FENCE_SOURCE,kind:'http_collect'});
 const originalFetch=globalThis.fetch;
 try{
  const marker=await sql.unsafe('SELECT marker FROM private.synthetic_onboarding_fixture_marker');
  if(marker.length!==1||marker[0].marker!=='burimunsi-onboarding-synthetic-only-v1')throw new Error('scratch marker required');
  const actorId=crypto.randomUUID(),sessionId=crypto.randomUUID(),groupId='synthetic-'+crypto.randomUUID();
  const actor={id:actorId,sessionId,groupId,principalUserId:'synthetic-principal',role:'staff',active:true,revoked:false,
   capabilities:['members.enroll'],expiresAt:9999999999999};
  const authority={groupId,db:{},async write(fn:(tx:any)=>Promise<unknown>){return sql.begin(async tx=>{
   await tx.unsafe('SET LOCAL ROLE collect_runtime');await tx.unsafe("SELECT set_config('burimunsi.collection_id',$1,true)",[groupId]);return fn(tx);});},
   async session(_tx:any,{id}:{id:string}){return id===sessionId?actor:null;},async audit(){}};
  const key='synthetic-openai-key-not-real-123456789',secret='synthetic-supervisor-secret-1234567890123456789',
   build='a'.repeat(64),endpoint='https://decoder.example.invalid/decode',now=Date.now();
  const policy={schema_version:1,status:'approved',enabled:true,purpose:'collect_roster_pdf_image_extraction',provider:'openai',
   responses_endpoint:'https://api.openai.com/v1/responses',decoder_url:'https://roster-decoder.internal/decode',
   approval_id:crypto.randomUUID(),approval_evidence_sha256:'b'.repeat(64),decoder_build_sha256:build,
   project_id:'proj-synthetic',organization_id:'org-synthetic',model:'fixture-vision',
   processing_region_evidence_ref:'ref:region',retention_evidence_ref:'ref:retention',
   decoder_processor_evidence_ref:'ref:decoder',decoder_region_evidence_ref:'ref:region',decoder_retention_evidence_ref:'ref:retention',
   approved_at:new Date(now-1000).toISOString(),valid_until:new Date(now+60000).toISOString()};
  const raw=JSON.stringify(policy),env:any={COLLECT_FENCE_WORK:work,ROSTER_AI_APPROVAL_JSON:raw,ROSTER_AI_APPROVAL_SHA256:await digest(raw),
   ROSTER_DECODER_BUILD_SHA256:build,OPENAI_PROJECT_ID:policy.project_id,OPENAI_ORGANIZATION_ID:policy.organization_id,
   ROSTER_AI_MODEL:policy.model,OPENAI_API_KEY:key,DATA_KEY_ID:'synthetic-key',
   DATA_ENCRYPTION_KEY:btoa(String.fromCharCode(...new Uint8Array(32).fill(7)))};
  const tools={python:'3.12',pillow:'12.3.0',pypdfium2:'5.2.0',pypdf:'6.19.0',openpyxl:'3.1.5',defusedxml:'0.7.1'};
  let decodes=0,providers=0;
  globalThis.fetch=async(url:any,init:any)=>{
   if(url===endpoint){decodes++;const wire=JSON.parse(init.body);
    if(init.headers.Authorization!=='Roster-HMAC '+createHmac('sha256',secret).update(init.body).digest('hex'))throw new Error('bad synthetic signature');
    const payload=JSON.stringify({contract_version:1,request_id:wire.request_id,reservation_id:wire.reservation_id,nonce:wire.nonce,
     issued_at:Math.floor(Date.now()/1000),kind:wire.kind,mime:wire.mime,decoder_build_sha256:build,ok:true,
     policy_version:'collect-roster-decoder-v1',toolchain:tools,source_sha256:wire.source_sha256,
     source_size:Buffer.from(wire.content_base64,'base64').length,derived_sha256:null,frames:1,pages:0,pixels:1,expanded_bytes:4,derived_content:null});
    return Response.json({payload,signature:createHmac('sha256',secret).update(payload).digest('hex')});
   }
   if(url!=='https://api.openai.com/v1/responses')throw new Error('unexpected synthetic network target');providers++;
   return Response.json({object:'response',status:'completed',error:null,incomplete_details:null,tools:[],
    output:[{type:'message',role:'assistant',status:'completed',content:[{type:'output_text',annotations:[],
     text:JSON.stringify({rows:[{momoName:'Synthetic Bob',momoNumber:'0780000002'}]})}]}]});
  };
  env.ROSTER_DECODER=(createRosterDecoderBridge as any)({protocol:'roster-hmac-v1',endpoint,secret,approvedBuildSha256:build,
   fetchImpl:(...args:any[])=>(guardedFetch as any)(env,'decoder',...args),trackPromise:(p:Promise<unknown>)=>applicationWork(env).waitUntil(p),
   onUncertain:()=>noteUnknownEffect(env,'decoder')});
  const journal=new (PostgresSmartOnboardingJournal as any)({authority,env,clock:()=>Date.now()});
  const importer=(createGuardedSmartOnboardingImport as any)({env,groupId,journal,policy:(createSmartOnboardingPolicy as any)({env})});
  const bytes=new Uint8Array(await readFile(new URL('../../../../../tools/roster-decoder/native-probe/corpus/scanned-multilingual.png',import.meta.url)));
  const params={actor,groupId,bytes,mimeType:'image/png',externalOcrConsent:true,importFlowId:'77777777-7777-4777-8777-777777777777',ocrDisclosureVersion:'burimunsi-ocr-disclosure-v1',authorize:async()=>actor};
  const first=await importer.preview(params),recovered=await importer.preview(params);
  if(first.rows[0].momoNumber!=='+250780000002'||JSON.stringify(first)!==JSON.stringify(recovered)||decodes!==1||providers!==1)
   throw new Error('synthetic end-to-end recovery failed');
  const row=await sql.unsafe('SELECT response::text AS value FROM private.burimunsi_command_receipts WHERE collection_id=$1',[groupId]);
  if(row.length!==1||row[0].value.includes('Synthetic Bob')||row[0].value.includes('0780000002'))throw new Error('plaintext preview stored');
 }finally{globalThis.fetch=originalFetch;await work.finish();await sql.end({timeout:5});}
}});
