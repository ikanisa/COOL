// Source-bound observations of real WASM dependencies in pinned Edge Runtime.
// Completed observations never constitute an accepted roster parser contract.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir,readdir,lstat} from 'node:fs/promises';
import {createWriteStream} from 'node:fs';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createServer} from 'node:net';
import {resolve,join} from 'node:path';

const HERE=import.meta.dirname,BINARY_SHA='7883510fe308b4b5c49ec0a8e2020ec81c5fa41133239f3969a372b1cbf107ba';
const sha=value=>createHash('sha256').update(value).digest('hex');
const sleep=milliseconds=>new Promise(resolve=>setTimeout(resolve,milliseconds));
const sorted=items=>items.sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0);
async function snapshot(root){
 const files=[];
 async function walk(relative){
  const path=join(root,relative),stat=await lstat(path);assert(!stat.isSymbolicLink(),'Probe inputs cannot be symlinks');
  if(stat.isDirectory()){
   for(const name of (await readdir(path)).sort())if(name!=='__pycache__')await walk(relative?relative+'/'+name:name);
  }else{assert(stat.isFile());files.push({path:relative,sha256:sha(await readFile(path))});}
 }
 await walk('');return sorted(files);
}
async function requireFresh(path){
 try{await lstat(path);throw Error('Fresh output path required');}catch(error){if(error.code!=='ENOENT')throw error;}
}
async function run(binary,prepared,attempt,receipt){
 assert.equal(process.env.COLLECT_CI_SYNTHETIC,'true');assert.equal(sha(await readFile(binary)),BINARY_SHA);
 await requireFresh(attempt);await requireFresh(receipt);
 const preparedReceipt=JSON.parse(await readFile(join(prepared,'prepared.json'),'utf8'));
 assert.equal(preparedReceipt.contract,'collect.roster.native-probe.prepared.v1');assert.equal(preparedReceipt.synthetic_only,true);
 const sourceBefore=await snapshot(HERE);assert.deepEqual(sourceBefore,preparedReceipt.source_inputs,'Prepared services must bind the current exact probe source');
 const preparedBefore=await snapshot(prepared),manifest=JSON.parse(await readFile(join(prepared,'corpus/manifest.json'),'utf8'));
 assert.equal(manifest.synthetic_only,true);assert.equal(manifest.fixtures.length,35);
 const selected=manifest.fixtures.filter(item=>['image','pdf'].includes(item.kind));
 for(const item of selected){assert.match(item.path,/^[a-z0-9.-]+$/);assert.equal(sha(await readFile(join(prepared,'corpus',item.path))),item.sha256);}
 const port=createServer();await new Promise((resolve,reject)=>{port.once('error',reject);port.listen(9178,'127.0.0.1',resolve);});await new Promise(resolve=>port.close(resolve));
 await mkdir(attempt,{mode:0o700});
 const log=createWriteStream(join(attempt,'runtime.private.log'),{flags:'wx',mode:0o600});
 const child=spawn(binary,['start','--ip','127.0.0.1','--port','9178','--main-service',join(prepared,'main'),'--policy','oneshot','--max-parallelism','1'],
  {cwd:attempt,env:{PATH:process.env.PATH,DENO_DIR:join(attempt,'cache'),DENO_NO_UPDATE_CHECK:'1',QUAL_ISOLATION_SENTINEL:'SYNTHETIC_CANARY'},stdio:['ignore','pipe','pipe']});
 child.stdout.pipe(log,{end:false});child.stderr.pipe(log,{end:false});
 const results=[];let failure=null;
 async function request(lane,fixture,body){
  const started=Date.now(),response=await fetch('http://127.0.0.1:9178/'+lane,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
  const text=await response.text();assert(text.length<=16384);const value=JSON.parse(text);
  const expectedFrames=fixture.path.startsWith('animation-3.')?3:fixture.path.startsWith('animation-21.')?21:null;
  const result={lane,fixture:fixture.path,fixture_sha256:fixture.sha256,expected_accept:fixture.accepted,http_status:response.status,response:value,elapsed_ms:Date.now()-started,
   acceptance_matches_expected:value.ok===fixture.accepted,
   ...(expectedFrames!==null?{expected_frames:expectedFrames,complete_frame_decode_match:value.ok===true?value.frames===expectedFrames:null}:{})};
  results.push(result);assert.notEqual(value.stage,'worker_boot','Real parser worker must boot');return result;
 }
 try{
  let ready=false;const deadline=Date.now()+30000;
  while(Date.now()<deadline){
   if(child.exitCode!==null||child.signalCode!==null)throw Error('Native probe runtime exited');
   try{const response=await fetch('http://127.0.0.1:9178/ready',{signal:AbortSignal.timeout(500)});await response.arrayBuffer();if(response.status===404){ready=true;break;}}catch{}
   await sleep(100);
  }
  assert(ready,'Native probe startup deadline');
  for(const strict of [false,true])for(const fixture of selected.filter(item=>item.kind==='image')){
   const base64=(await readFile(join(prepared,'corpus',fixture.path))).toString('base64');
   const format=fixture.path.endsWith('.jpg')?'Jpeg':fixture.path.endsWith('.png')?(strict&&fixture.path.startsWith('animation-')?'APng':'Png'):'WebP';
   const result=await request('image',fixture,{base64,format,strict});result.image_mode=strict?'warning_strict_and_explicit_apng':'default';
  }
  for(const lane of ['pdfium','qpdf'])for(const fixture of selected.filter(item=>item.kind==='pdf')){
   await request(lane,fixture,{base64:(await readFile(join(prepared,'corpus',fixture.path))).toString('base64')});
  }
  const fixture=selected.find(item=>item.path==='pages-2.pdf');
  const version=await request('qpdf',fixture,{base64:(await readFile(join(prepared,'corpus',fixture.path))).toString('base64'),version:true});version.engine_version_observation=true;
  assert.match(version.response.output,/^(?:qpdf|this\.program) version 12\.2\.0(?:\n|$)/);
 }catch(error){failure={name:error.name,message:String(error.message).slice(0,240)};}
 finally{
  if(child.exitCode===null&&child.signalCode===null){
   child.kill('SIGTERM');for(let i=0;i<150&&child.exitCode===null&&child.signalCode===null;i++)await sleep(100);
   if(child.exitCode===null&&child.signalCode===null){child.kill('SIGKILL');for(let i=0;i<50&&child.exitCode===null&&child.signalCode===null;i++)await sleep(100);}
  }
  await new Promise(resolve=>log.end(resolve));
 }
 try{assert.deepEqual(await snapshot(HERE),sourceBefore,'Probe source changed during execution');assert.deepEqual(await snapshot(prepared),preparedBefore,'Prepared dependency/corpus bytes changed during execution');assert.equal(sha(await readFile(binary)),BINARY_SHA);}
 catch(error){failure={name:error.name,message:String(error.message).slice(0,240)};}
 const get=(lane,path,mode)=>results.find(item=>item.lane===lane&&item.fixture===path&&(!mode||item.image_mode===mode));
 const findings={
  default_jpeg_accepts_truncation:get('image','truncated.jpg','default')?.response.ok===true,
  strict_warning_check_rejects_truncated_jpeg:get('image','truncated.jpg','warning_strict_and_explicit_apng')?.response.ok===false,
  default_png_drops_animation_frames:get('image','animation-3.png','default')?.response.frames===1,
  default_png_accepts_over_limit_animation:get('image','animation-21.png','default')?.response.ok===true,
  explicit_apng_codec_rejects_valid_animation:get('image','animation-3.png','warning_strict_and_explicit_apng')?.response.ok===false,
  rendering_alone_accepts_active_pdf:get('pdfium','javascript.pdf')?.response.ok===true,
  rendering_alone_accepts_expansion_pdf:get('pdfium','object-stream-expansion.pdf')?.response.ok===true,
  qpdf_structure_matches_ten_existing_pdf_labels:results.filter(item=>item.lane==='qpdf'&&!item.engine_version_observation).length===10&&results.filter(item=>item.lane==='qpdf'&&!item.engine_version_observation).every(item=>item.acceptance_matches_expected),
 };
 const result={contract:'collect.roster.native-dependency-observations.v2',status:failure?'incomplete':'completed',checked_at:new Date().toISOString(),
  binary_sha256:BINARY_SHA,runtime:'supabase/edge-runtime:v1.77.4',native_deno:'2.1.4',synthetic_only:true,
  parser_contract_qualified:false,production_acceptance:false,provider_accuracy_verified:false,provider_calls:0,
  original_signed_decoder_contract_implemented:false,native_workbook_decoder_implemented:false,
  source_inputs:sourceBefore,source_sha256:sha(JSON.stringify(sourceBefore)),prepared_inputs:preparedBefore,prepared_sha256:sha(JSON.stringify(preparedBefore)),
  dependencies:preparedReceipt.packages,configured_worker_limits:{memory_mb:384,cpu_soft_ms:4000,cpu_hard_ms:5000,wall_ms:10000,fresh_worker_per_request:true,network_denied:true,environment_denied:true,filesystem_write_denied:true,subprocess_denied:true,concurrency:1},
  resource_exhaustion_acceptance:false,file_read_not_found_is_not_permission_denial:true,findings,results,failure,
  native_process_stopped:child.exitCode!==null||child.signalCode!==null,private_log_retained:true};
 await writeFile(receipt,JSON.stringify(result,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({status:result.status,observations:results.length,findings,parser_contract_qualified:false,production_acceptance:false}));
 if(failure)process.exitCode=1;
}
assert.equal(process.argv.length,6,'binary prepared-directory fresh-private-attempt safe-receipt required');
await run(...process.argv.slice(2).map(value=>resolve(value)));
