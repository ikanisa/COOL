/** SYNTHETIC PROTOTYPE ONLY: real bridge + private TLS + scratch PostgreSQL.
 * Docker helper forwards through the internal network. No host port is opened.
 */
import {readFileSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash,createHmac,randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {createRosterDecoderBridge} from '../../../supabase/functions/_shared/roster_decoder_bridge.mjs';
import {previewSmartOnboardingImport} from '../../../supabase/functions/_shared/domain/burimunsi/smart-onboarding-import.js';
import {openApplicationWork,applicationWork,guardedFetch,noteUnknownEffect} from '../../../supabase/functions/_shared/application-fence.js';
import {syntheticFenceBackend,SYNTHETIC_FENCE_SOURCE} from '../../../supabase/functions/_shared/tests/helpers/fenced-unit.js';
const [server,database,privateSettings,build]=process.argv.slice(2);
if(!/^collect-decoder-proto-\d+$/.test(server??'')||!/^collect-decoder-pg-\d+$/.test(database??'')||
 !/^[a-f0-9]{64}$/.test(build??''))throw new Error('synthetic target required');
const settings=JSON.parse(readFileSync(privateSettings,'utf8'));
const secret=settings.signing;if(!/^[a-f0-9]{64}$/.test(secret??''))throw new Error('synthetic signer required');
const corpus=new URL('../native-probe/corpus/scanned-multilingual.png',import.meta.url),bytes=readFileSync(corpus);
const source=createHash('sha256').update(bytes).digest('hex'),requestId=randomUUID(),reservationId=randomUUID();
const group='synthetic-'+randomUUID(),actor=randomUUID(),session=randomUUID(),policy='b'.repeat(64);
const sql=`BEGIN;SET LOCAL ROLE collect_runtime;SELECT set_config('burimunsi.collection_id','${group}',true);
INSERT INTO private.burimunsi_command_receipts(collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at)
VALUES('${group}','${actor}','${requestId}','${session}','burimunsi.smart_import.v1',
 encode(sha256(convert_to('burimunsi.smart_import.v1'||E'\\n'||'${group}'||E'\\n'||'${actor}'||E'\\n'||'${source}','UTF8')),'hex'),
 jsonb_build_object('v',1,'state','reserved','reservationId','${reservationId}','sourceSha256','${source}',
 'mimeType','image/png','policySha256','${policy}','decoderBuildSha256','${build}','ciphertext',NULL,'previewSha256',NULL),1);
UPDATE private.burimunsi_command_receipts SET response=jsonb_set(response,'{state}','"decode"'::jsonb) WHERE request_id='${requestId}';COMMIT;`;
execFileSync('docker',['--context','colima-supabase-local','exec','-i',database,'psql','-h','/tmp','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-q'],{input:sql,stdio:['pipe','pipe','pipe']});
const python=`import json,ssl,sys,urllib.request,urllib.error
p=json.load(sys.stdin)
ctx=ssl.create_default_context(cafile=p['ca'])
request=urllib.request.Request('https://decoder:8080/decode',data=p['body'].encode(),headers=p['headers'],method='POST')
try:
 response=urllib.request.urlopen(request,timeout=15,context=ctx)
except urllib.error.HTTPError as e: response=e
with response:
 print(json.dumps({'status':response.status,'body':response.read(7100000).decode()}))`;
function callTls(payload){
 const child=spawnSync('docker',['--context','colima-supabase-local','exec','-i',server,'python','-I','-c',python],
  {input:JSON.stringify(payload),encoding:'utf8',timeout:20000,maxBuffer:8*1024*1024});
 if(child.status!==0)throw new Error('synthetic TLS transport failed');return JSON.parse(child.stdout);
}
let requests=0;
const bridge=createRosterDecoderBridge({protocol:'roster-hmac-v1',endpoint:'https://decoder/decode',secret,approvedBuildSha256:build,
 fetchImpl:async(_url,init)=>{requests++;const out=callTls({ca:'/tmp/decoder-cert.pem',body:init.body,headers:init.headers});
  return new Response(out.body,{status:out.status,headers:{'content-type':'application/json'}});}});
const logical=()=>new Request('https://roster-decoder.internal/decode',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({
 schema_version:1,source_sha256:source,decoder_build_sha256:build,mime_type:'image/png',content_base64:bytes.toString('base64')})});
const response=await bridge.fetch(logical(),{requestId,reservationId}),result=await response.json();
assert.equal(result.source_sha256,source);assert.equal(result.content[0].type,'input_image');assert.equal(result.decoder_build_sha256,build);
await assert.rejects(bridge.fetch(logical(),{requestId,reservationId}));assert.equal(requests,2);
const count=execFileSync('docker',['--context','colima-supabase-local','exec',database,'psql','-h','/tmp','-U','postgres','-d','postgres','-A','-t','-c',
 `SELECT count(*) FROM private.synthetic_roster_replays WHERE request_id='${requestId}'::uuid`],{encoding:'utf8'}).trim();assert.equal(count,'1');
const invalid=callTls({ca:'/tmp/decoder-cert.pem',body:'{}',headers:{'Content-Type':'application/json','Authorization':'Roster-HMAC '+'0'.repeat(64)}});
assert.equal(invalid.status,401);
assert.throws(()=>callTls({ca:'/tmp/db-cert.pem',body:'{}',headers:{'Content-Type':'application/json','Authorization':'Roster-HMAC '+'0'.repeat(64)}}));
// Restart only the synthetic supervisor; replay authority must survive in the
// separate scratch PostgreSQL service. Its short-lived TLS files are reloaded.
execFileSync('docker',['--context','colima-supabase-local','restart',server],{stdio:['ignore','pipe','pipe'],timeout:15000});
for(const file of ['db-cert.pem','decoder-cert.pem','decoder-key.pem']){
 execFileSync('docker',['--context','colima-supabase-local','exec','-i',server,'sh','-c',`cat > /tmp/${file}`],
  {input:readFileSync(join(dirname(privateSettings),file)),stdio:['pipe','pipe','pipe']});
}
await new Promise(resolve=>setTimeout(resolve,300));
const replayBody=JSON.stringify({request_id:requestId,reservation_id:reservationId,source_sha256:source,mime:'image/png',
 kind:'image',content_base64:bytes.toString('base64'),policy_version:'collect-roster-decoder-v1',nonce:randomUUID(),issued_at:Math.floor(Date.now()/1000)});
const replay=callTls({ca:'/tmp/decoder-cert.pem',body:replayBody,headers:{'Content-Type':'application/json',
 Authorization:'Roster-HMAC '+createHmac('sha256',secret).update(replayBody).digest('hex')}});
assert.equal(replay.status,409);
console.log(JSON.stringify({synthetic_only:true,private_tls:true,postgres_replay_claim:true,signed_bridge_interoperable:true,
 replay_rejected:true,replay_rejected_after_restart:true,invalid_hmac_rejected:true,wrong_ca_rejected:true,host_ports_published:false,production_acceptance:false,
 build_sha256:build,source_sha256:source}));

// Optional one-shot provider qualification. The protected settings are read in
// process; no key or provider response is printed or written to an artifact.
if(process.argv[6]){
 const provider=JSON.parse(readFileSync(process.argv[6],'utf8'));
 if(typeof provider.OPENAI_API_KEY!=='string'||typeof provider.MOMO_AI_MODEL!=='string')throw new Error('provider settings unavailable');
 const nextRequest=randomUUID(),nextReservation=randomUUID(),nextGroup='synthetic-'+randomUUID(),nextActor=randomUUID();
 const nextSql=sql.replaceAll(requestId,nextRequest).replaceAll(reservationId,nextReservation).replaceAll(group,nextGroup).replaceAll(actor,nextActor);
 execFileSync('docker',['--context','colima-supabase-local','exec','-i',database,'psql','-h','/tmp','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-q'],
  {input:nextSql,stdio:['pipe','pipe','pipe']});
 const work=await openApplicationWork({backend:syntheticFenceBackend(),sourceSha256:SYNTHETIC_FENCE_SOURCE,kind:'http_collect'});
 const env={COLLECT_FENCE_WORK:work};let observed;
 try{
  const result=await previewSmartOnboardingImport({bytes:new Uint8Array(bytes),mimeType:'image/png',
   decoder:{port:bridge,buildSha256:build,requestId:nextRequest,reservationId:nextReservation},
   ocr:{consent:true,apiKey:provider.OPENAI_API_KEY,model:provider.MOMO_AI_MODEL,
    trackPromise:p=>applicationWork(env).waitUntil(p),onUncertain:()=>noteUnknownEffect(env,'roster_ai'),
    fetchImpl:(...args)=>guardedFetch(env,'roster_ai',...args)}});
  const expected=new Set(['+250789969001','+250789969002']);
  const recognized=result.rows.filter(row=>row.status==='ready'&&expected.has(row.momoNumber));
  observed={synthetic_only:true,provider_completed:true,row_count:result.rows.length,expected_phone_count:expected.size,
   expected_phone_matches:new Set(recognized.map(row=>row.momoNumber)).size,additional_rows:result.rows.length-recognized.length};
 }catch(error){observed={synthetic_only:true,provider_completed:false,code:typeof error?.code==='string'?error.code:'provider_unavailable'};process.exitCode=1;}
 finally{const outcome=await work.finish({failed:!observed?.provider_completed});
  observed.external_dispatches=outcome.externalDispatches;observed.uncertain_dispatches=outcome.uncertainDispatches;}
 console.log(JSON.stringify(observed));
}
