const test=require('node:test'),assert=require('node:assert/strict'),path=require('node:path'),http=require('node:http');
const {createHash,createHmac}=require('node:crypto');
// This recording decoder proves the signed HTTP contract and ordering only.
// Real Linux codecs and malicious uploads have a separate source-bound packet.
const settings={OPENAI_API_KEY:'synthetic-provider-key',OPENAI_ROSTER_MODEL:'synthetic-model',ROSTER_DECODER_SECRET:'synthetic-loopback-signing-secret-at-least-32-bytes',ROSTER_DECODER_BUILD_SHA256:'d'.repeat(64)};
let handler;global.Deno={env:{get:key=>settings[key]},serve:callback=>handler=callback};
require(path.join(process.env.COLLECT_EDGE_BUILD,'prepare-roster-import/index'+(process.env.COLLECT_EDGE_MODULE_SUFFIX||'.js')));
const actor='11111111-1111-4111-8111-111111111111', session='22222222-2222-4222-8222-222222222222', requestId='33333333-3333-4333-8333-333333333333', importId='44444444-4444-4444-8444-444444444444', revisionId='55555555-5555-4555-8555-555555555555', extractionId='66666666-6666-4666-8666-666666666666';
const bearer='Bearer e30.'+Buffer.from(JSON.stringify({sub:actor,session_id:session,role:'authenticated'})).toString('base64url')+'.synthetic';
const {normalizeRosterCandidates}=require(path.join(process.env.COLLECT_EDGE_BUILD,'_shared/roster_import'+(process.env.COLLECT_EDGE_MODULE_SUFFIX||'.js')));
const png='iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAFElEQVR4nGOUS+lhYGBgYgADKAUAE/ABFCFAuesAAAAASUVORK5CYII=';
const row=()=>({source_row:1,member_name:'Niyonzima Élodie',momo_name:'Élodie Niyonzima',momo_number:'0788123456',confidence:0.96});
const provider=()=>({id:'resp_fixture',object:'response',status:'completed',error:null,incomplete_details:null,output:[{id:'msg_fixture',type:'message',role:'assistant',status:'completed',content:[{type:'output_text',annotations:[],text:JSON.stringify({rows:[row()]})}]}]});
function request(patch={}) {return new Request('https://edge.test',{method:'POST',headers:{authorization:bearer,'content-type':'application/json'},body:JSON.stringify({contract_version:1,request_id:requestId,source_type:'image',mime_type:'image/png',filename:'synthetic.png',content_base64:png,ai_consent:true,consent_version:'roster-ai-extraction-v1',...patch})});}
const reservationId='77777777-7777-4777-8777-777777777777';
const {ROSTER_DECODER_TOOLCHAIN}=require(path.join(process.env.COLLECT_EDGE_BUILD,'_shared/roster_decoder'+(process.env.COLLECT_EDGE_MODULE_SUFFIX||'.js')));
let active;
function preview(source,candidates) {
 return {contract_version:1,ok:true,import_id:importId,source_sha256:source.p_original_sha256,source_kind:source.p_source_kind,source_receipt:{request_id:requestId,source_size:source.p_original_size,client_filename:source.p_client_filename,declared_mime:source.p_declared_mime,detected_type:source.p_detected_type,derived_sha256:source.p_derived_sha256,derived_assurance:source.p_source_kind==='xlsx'?'client_derived_tsv':null,extraction_id:source.p_ai_consent?extractionId:null,ai_consent:source.p_ai_consent,consent_version:source.p_consent_version,parser_version:'collect-roster-parser-v1',schema_version:'collect-roster-rows-v1'},revision_id:revisionId,parent_revision_id:null,revision_number:1,reviewed_rows_sha256:'a'.repeat(64),...normalizeRosterCandidates(candidates),can_submit:false,requires_human_review:true,processing_method:source.p_ai_consent?'openai_structured_extraction':'deterministic',model:source.p_ai_consent?'synthetic-model':null,expires_at:'2099-01-01T00:00:00Z'};
}
function setup(options={}) {
 const calls=[];active={calls,events:[],options};Object.defineProperty(calls,'events',{value:active.events});
 global.__user={user:{id:actor}};
 global.__service={rpc:async(name,args)=>{
  calls.push(name);active.events.push(name);
  if(name==='reserve_roster_resources') {
   assert.equal(args.p_actor_id,actor);assert.equal(args.p_session_id,session);assert.equal(args.p_request_id,requestId);
   active.budget=args;
   if(options.budgetError)return{data:null,error:{message:options.budgetError}};
   const receipt={contract_version:1,ok:true,reservation_id:reservationId,request_id:requestId,actor_id:actor,session_id:session,source_sha256:args.p_source_sha256,state:options.finished?'finished':'reserved',replayed:!!options.finished,expires_at:'2099-01-01T00:00:00Z'};
   options.alterBudget?.(receipt);return{data:receipt,error:null};
  }
  if(name==='verify_roster_source_integrity') {
   assert.equal(args.p_reservation_id,reservationId);assert.equal(args.p_actor_id,actor);assert.equal(args.p_session_id,session);
   assert.equal(args.p_decoder_build_sha256,settings.ROSTER_DECODER_BUILD_SHA256);
   assert.equal(args.p_decoder_receipt_sha256,active.decoderReceiptHash);
   const receipt={contract_version:1,ok:true,reservation_id:reservationId,source_sha256:active.budget.p_source_sha256,derived_sha256:active.budget.p_derived_sha256,decoder_receipt_sha256:args.p_decoder_receipt_sha256,verified:true};
   options.alterVerification?.(receipt);return{data:receipt,error:null};
  }
  if(name==='finish_roster_resources') {
   assert.equal(args.p_reservation_id,reservationId);assert.equal(args.p_actor_id,actor);assert.equal(args.p_session_id,session);
   active.outcome=args.p_outcome;
   return{data:{contract_version:1,ok:true,reservation_id:reservationId,outcome:args.p_outcome,charged:true},error:null};
  }
  if(name==='create_roster_import_source') {
   active.source=args;
   return{data:{contract_version:1,ok:true,request_id:requestId,import_id:importId,source_sha256:args.p_original_sha256,source_size:args.p_original_size,source_kind:args.p_source_kind,extraction_id:args.p_ai_consent?extractionId:null,expires_at:'2099-01-01T00:00:00Z',derived_sha256:args.p_derived_sha256,derived_assurance:args.p_source_kind==='xlsx'?'client_derived_tsv':null,state:options.finished?'preview_ready':'awaiting_preview',replayed:!!options.finished,completed_preview:options.finished?preview(args,[row()]):null,error_code:null},error:null};
  }
  if(name==='fail_roster_import_preview') return{data:{contract_version:1,ok:true,import_id:importId,state:'failed',error_code:args.p_error_code,replayed:false},error:null};
  assert.equal(name,'complete_roster_import_preview');
  return {data:preview(active.source,args.p_candidates),error:null};
 }};
 return calls;
}
async function withProvider(reply,run) {
 const original=global.fetch;let calls=0;const nonces=new Set();
 const server=http.createServer(async(req,res)=>{
  try {
   assert.equal(req.url,'/decode');assert.equal(req.method,'POST');
   const chunks=[];for await(const chunk of req)chunks.push(chunk);const raw=Buffer.concat(chunks);
   assert.equal(req.headers.authorization,'Roster-HMAC '+createHmac('sha256',settings.ROSTER_DECODER_SECRET).update(raw).digest('hex'));
   const input=JSON.parse(raw),source=Buffer.from(input.content_base64,'base64');
   assert.equal(input.source_sha256,createHash('sha256').update(source).digest('hex'));
   assert.equal(input.request_id,requestId);assert.equal(input.reservation_id,reservationId);
   assert.equal(nonces.has(input.nonce),false);nonces.add(input.nonce);
   active.events.push('decoder');
   if(active.options.decoderError){res.writeHead(422,{'content-type':'application/json'});res.end(JSON.stringify({error:active.options.decoderError}));return;}
   const receipt={contract_version:1,ok:true,request_id:input.request_id,reservation_id:input.reservation_id,nonce:input.nonce,issued_at:input.issued_at,kind:input.kind,mime:input.mime,policy_version:input.policy_version,toolchain:ROSTER_DECODER_TOOLCHAIN,source_sha256:input.source_sha256,source_size:source.length,derived_sha256:null,derived_content:null,frames:1,pages:0,pixels:6,expanded_bytes:24,decoder_build_sha256:settings.ROSTER_DECODER_BUILD_SHA256};
   active.options.alterDecoder?.(receipt);
   const payload=JSON.stringify(receipt);active.decoderReceiptHash=createHash('sha256').update(payload).digest('hex');
   const signature=active.options.badSignature?'0'.repeat(64):createHmac('sha256',settings.ROSTER_DECODER_SECRET).update(payload).digest('hex');
   res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify({payload,signature}));
  }catch(error){active.fixtureError=error;res.writeHead(500);res.end('{}');}
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));settings.ROSTER_DECODER_URL='http://127.0.0.1:'+server.address().port+'/decode';
 global.fetch=async(url,options)=>{
   if(String(url)===settings.ROSTER_DECODER_URL){assert.equal(options.redirect,'error');assert.ok(options.signal);return original(url,options);}
   calls++;active.events.push('provider');assert.equal(url,'https://api.openai.com/v1/responses');assert.equal(options.redirect,'error');assert.ok(options.signal);
   const payload=JSON.parse(options.body);assert.equal(payload.store,false);assert.equal(payload.tools,undefined);assert.equal(typeof payload.instructions,'string');
   assert.deepEqual(active.events.slice(0,5),['reserve_roster_resources','decoder','verify_roster_source_integrity','create_roster_import_source','provider']);
   return reply();
 };
 try{await run(()=>calls);if(active.fixtureError)throw active.fixtureError}finally{global.fetch=original;delete settings.ROSTER_DECODER_URL;server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
}
function assertProvenanceOnly(calls) {
 for(const name of calls)assert.ok(['reserve_roster_resources','verify_roster_source_integrity','finish_roster_resources','create_roster_import_source','complete_roster_import_preview','fail_roster_import_preview'].includes(name));
 if(calls.length)assert.equal(calls[0],'reserve_roster_resources');
 if(calls.includes('verify_roster_source_integrity'))assert.ok(calls.indexOf('verify_roster_source_integrity')<calls.indexOf('create_roster_import_source')||!calls.includes('create_roster_import_source'));
 if(calls.includes('finish_roster_resources'))assert.equal(calls.at(-1),'finish_roster_resources');
 if(calls.events.includes('provider'))assert.equal(active.outcome,calls.includes('complete_roster_import_preview')?'preview_ready':'ambiguous');
}
test('actual roster handler returns a hashed human-review preview with provenance receipts only',async()=>{
 const calls=setup();
 await withProvider(()=>new Response(JSON.stringify(provider())),async count=>{
   const result=await handler(request()),body=await result.json();
   assert.equal(result.status,200);assert.equal(body.requires_human_review,true);assert.equal(body.can_submit,false);
   assert.equal(body.ready_count,1);assert.equal(body.rows[0].member_name,row().member_name);assert.equal(body.normalized_rows[0].momo_number,'+250788123456');
   assert.equal(body.source_sha256,require('node:crypto').createHash('sha256').update(Buffer.from(png,'base64')).digest('hex'));
   assert.equal(result.headers.get('cache-control'),'no-store');assert.equal(count(),1);
 });assertProvenanceOnly(calls);
});
for(const [name,alter,code] of [
 ['incomplete',p=>{p.status='incomplete'},'roster_extraction_incomplete'],
 ['additional tool',p=>p.output.push({type:'function_call',name:'create_member',arguments:'private-provider-detail'}),'roster_provider_response_invalid'],
 ['wrong row type',p=>{p.output[0].content[0].text=JSON.stringify({rows:[{...row(),confidence:'0.96'}]})},'roster_provider_response_invalid'],
 ['duplicate answer',p=>p.output.push(structuredClone(p.output[0])),'roster_provider_response_invalid'],
 ['refusal after text',p=>p.output[0].content.push({type:'refusal',refusal:'private-provider-detail'}),'roster_provider_response_invalid'],
])test('actual roster handler rejects '+name+' with provenance receipts only',async()=>{
 const calls=setup(),payload=provider();alter(payload);
 await withProvider(()=>new Response(JSON.stringify(payload)),async count=>{
   const result=await handler(request());assert.equal(result.status,502);assert.deepEqual(await result.json(),{error:code});assert.equal(count(),1);
 });assertProvenanceOnly(calls);
});
test('actual roster handler cancels an oversized provider stream and returns an upstream error',async()=>{
 const calls=setup();let cancelled=false;
 await withProvider(()=>new Response(new ReadableStream({pull(controller){controller.enqueue(new Uint8Array(65_536).fill(32))},cancel(){cancelled=true}})),async count=>{
   const result=await handler(request());assert.equal(result.status,502);assert.deepEqual(await result.json(),{error:'roster_provider_response_too_large'});assert.equal(cancelled,true);assert.equal(count(),1);
 });assertProvenanceOnly(calls);
});
test('actual roster handler rejects malformed provider JSON without exposing its body',async()=>{
 const calls=setup();await withProvider(()=>new Response('private-provider-detail'),async()=>{
   const result=await handler(request());assert.equal(result.status,502);assert.deepEqual(await result.json(),{error:'roster_provider_response_invalid'});
 });assertProvenanceOnly(calls);
});
test('actual roster handler rejects spoofed upload before any provider request',async()=>{
 const calls=setup();await withProvider(()=>{throw new Error('must not call provider')},async count=>{
   const result=await handler(request({content_base64:Buffer.from('<html>not png</html>').toString('base64')}));assert.equal(result.status,400);assert.deepEqual(await result.json(),{error:'roster_type_mismatch'});assert.equal(count(),0);
 });assertProvenanceOnly(calls);
});
test('actual deterministic roster preview remains usable without a model call or membership mutation',async()=>{
 const calls=setup();await withProvider(()=>{throw new Error('must not call provider')},async count=>{
   const result=await handler(new Request('https://edge.test',{method:'POST',headers:{authorization:bearer,'content-type':'application/json'},body:JSON.stringify({contract_version:1,request_id:requestId,source_type:'csv',filename:'fixture.csv',mime_type:'text/csv',content_base64:Buffer.from('Member name,MoMo name,MoMo number\nAline,ALINE UWASE,0788123456').toString('base64')})})),body=await result.json();assert.equal(result.status,200);assert.equal(body.processing_method,'deterministic');assert.equal(body.can_submit,false);assert.equal(count(),0);
 });assertProvenanceOnly(calls);
});

for(const [label,change] of [
 ['source substitution',r=>{r.source_sha256='f'.repeat(64)}],
 ['another reservation',r=>{r.reservation_id=importId}],
 ['nonce replay',r=>{r.nonce=actor}],
 ['stale timestamp',r=>{r.issued_at-=90}],
 ['different decoder build',r=>{r.decoder_build_sha256='f'.repeat(64)}],
 ['different policy',r=>{r.policy_version='untrusted-policy'}],
])test('actual signed decoder HTTP rejects '+label+' before source/provider transmission',async()=>{
 const calls=setup({alterDecoder:change});await withProvider(()=>{throw new Error('must not call provider')},async count=>{
  const result=await handler(request());assert.equal(result.status,503);assert.deepEqual(await result.json(),{error:'roster_decoder_receipt_invalid'});assert.equal(count(),0);
 });assert.deepEqual(calls,['reserve_roster_resources','finish_roster_resources']);assert.equal(active.outcome,'failed');
});
test('actual decoder HTTP rejects an invalid signature before source/provider transmission',async()=>{
 const calls=setup({badSignature:true});await withProvider(()=>{throw new Error('must not call provider')},async count=>{
  const result=await handler(request());assert.equal(result.status,503);assert.deepEqual(await result.json(),{error:'roster_decoder_receipt_invalid'});assert.equal(count(),0);
 });assert.deepEqual(calls,['reserve_roster_resources','finish_roster_resources']);
});
test('actual decoder rejection preserves its fixed public code and prevents provider transmission',async()=>{
 const calls=setup({decoderError:'roster_animation_limit'});await withProvider(()=>{throw new Error('must not call provider')},async count=>{
  const result=await handler(request());assert.equal(result.status,422);assert.deepEqual(await result.json(),{error:'roster_animation_limit'});assert.equal(count(),0);
 });assert.deepEqual(calls,['reserve_roster_resources','finish_roster_resources']);
});
for(const [label,options,status,code] of [
 ['resource quota',{budgetError:'roster_resource_limit'},429,'roster_resource_limit'],
 ['active request',{budgetError:'roster_resource_in_progress'},409,'roster_resource_in_progress'],
 ['wrong actor',{alterBudget:r=>{r.actor_id=importId}},503,'roster_budget_receipt_invalid'],
 ['active replay',{alterBudget:r=>{r.replayed=true}},409,'roster_resource_in_progress'],
])test('actual roster HTTP fails closed on '+label+' before decoder/provider dispatch',async()=>{
 const calls=setup(options);await withProvider(()=>{throw new Error('must not call provider')},async count=>{
  const result=await handler(request());assert.equal(result.status,status);assert.deepEqual(await result.json(),{error:code});assert.equal(count(),0);
 });assert.deepEqual(calls,['reserve_roster_resources']);assert.deepEqual(calls.events,['reserve_roster_resources']);
});
test('actual roster HTTP rejects a mismatched durable verification before source/provider transmission',async()=>{
 const calls=setup({alterVerification:r=>{r.decoder_receipt_sha256='f'.repeat(64)}});await withProvider(()=>{throw new Error('must not call provider')},async count=>{
  const result=await handler(request());assert.equal(result.status,503);assert.deepEqual(await result.json(),{error:'roster_receipt_invalid'});assert.equal(count(),0);
 });assert.deepEqual(calls,['reserve_roster_resources','verify_roster_source_integrity','finish_roster_resources']);
});
test('actual roster HTTP returns a finished immutable preview without repeating decoder/provider work',async()=>{
 const calls=setup({finished:true});await withProvider(()=>{throw new Error('must not call provider')},async count=>{
  const result=await handler(request());assert.equal(result.status,200);assert.equal((await result.json()).requires_human_review,true);assert.equal(count(),0);
 });assert.deepEqual(calls,['reserve_roster_resources','create_roster_import_source']);assert.deepEqual(calls.events,calls);
});
