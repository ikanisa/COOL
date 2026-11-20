// Separately pinned, live-capable successor. It dispatches only after an
// explicit technical gate, pinned plan/source checks and exclusive claims.
import {request as httpsRequest} from 'node:https';
import {createHash} from 'node:crypto';
import {EventEmitter} from 'node:events';
import {constants as FS} from 'node:fs';
import {lstat,open,realpath} from 'node:fs/promises';
import {dirname,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {assertUniqueJson} from './capture-json.mjs';
import {checkRuntimeArguments,compile,loadContext,rootedPath,safeEnvironment,separated,verifySources,writeNew} from './capture-plan.mjs';

const PROJECT='rrlduytparvsjfmegalh',ORG='ghnjnepwvwknswrwzepn';
const ENDPOINT='https://api.supabase.com/v1/projects/'+PROJECT;
const TOKEN_ENV='COLLECT_COMPONENT_CAPTURE_ACCESS_TOKEN';
const HASH=/^[a-f0-9]{64}$/;
const ROOT=resolve(import.meta.dirname,'../../..');
const LIVE_PIN=resolve(import.meta.dirname,'LIVE-SOURCE-PINS.json');
const NODE='/Volumes/PRO-G40/Development/Node/bin/node';
const CAPTURE_PIN='00cd926d3f524334fef028458d49f6de70755f837bfb156ab17d7f5467e259b4';
const PRIVATE_BASE='/Users/jeanbosco/Library/Application Support/Collect-Cloud-Recovery/production-metadata-20261113-122116';
const LIVE_COUNTS=Object.freeze({
 auth:Object.freeze({path:PRIVATE_BASE+'/auth-count-refresh-20261114-001/RESULT.json',sha256:'debcb294a3d6ac34fd674150e5cb8611431852d94073aac14c5db9cffd4ee93e'}),
 storage:Object.freeze({path:PRIVATE_BASE+'/storage-count-refresh-20261114-001/RESULT.json',sha256:'d6de07e1b671fc4881ed6004925e82a868fb8d4266d7351ba83abd1e8eaebf1a'}),
});
const LIVE_INPUTS=Object.freeze([
 'scripts/supabase/managed-component-refresh/capture-live.mjs',
 'scripts/supabase/managed-component-refresh/capture-live.test.mjs',
 'scripts/supabase/managed-component-refresh/capture-live-open-gate-fixture.mjs',
 'scripts/supabase/managed-component-refresh/LIVE-CAPTURE-README.md',
 'scripts/supabase/managed-component-refresh/CAPTURE-SOURCE-PINS.json',
]);
const sha=x=>createHash('sha256').update(x).digest('hex');
const exact=(x,k)=>x!==null&&typeof x==='object'&&!Array.isArray(x)&&Object.getPrototypeOf(x)===Object.prototype&&Object.keys(x).sort().join('\0')===[...k].sort().join('\0');
class Refused extends Error{constructor(code){super(code);this.code=code;}}
const need=(ok,code)=>{if(!ok)throw new Refused(code);};
const parse=(bytes,max)=>{need(Buffer.isBuffer(bytes)&&bytes.length>0&&bytes.length<=max,'WIRE_BOUND');const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);assertUniqueJson(text,max);return JSON.parse(text);};
async function absent(path){try{await lstat(path);throw new Refused('OUTPUT_EXISTS');}catch(e){if(e.code==='ENOENT')return;throw e;}}
async function stableHash(path,max){
 need(rootedPath(path)&&await realpath(path)===path,'LIVE_SOURCE_CHANGED');const before=await lstat(path);
 need(before.isFile()&&!before.isSymbolicLink()&&before.size>=0&&before.size<=max,'LIVE_SOURCE_CHANGED');
 const fd=await open(path,FS.O_RDONLY|FS.O_NOFOLLOW|FS.O_NONBLOCK),buffer=Buffer.alloc(1024*1024),hash=createHash('sha256');
 const identity=s=>[s.dev,s.ino,s.size,s.mtimeMs,s.ctimeMs,s.nlink].join(':');
 try{const first=await fd.stat();need(identity(first)===identity(before),'LIVE_SOURCE_CHANGED');let pos=0;
  while(pos<first.size){const n=await fd.read(buffer,0,Math.min(buffer.length,first.size-pos),pos);if(!n.bytesRead)break;hash.update(buffer.subarray(0,n.bytesRead));pos+=n.bytesRead;}
  const extra=await fd.read(buffer,0,1,first.size),after=await fd.stat(),last=await lstat(path);
  need(pos===first.size&&extra.bytesRead===0&&identity(first)===identity(after)&&identity(first)===identity(last),'LIVE_SOURCE_CHANGED');return hash.digest('hex');
 }finally{buffer.fill(0);await fd.close();}
}
export async function verifyLiveSources(expected){
 need(HASH.test(expected??''),'LIVE_PIN_REQUIRED');need(await realpath(ROOT)===ROOT,'LIVE_SOURCE_CHANGED');
 const before=await lstat(LIVE_PIN);need(before.isFile()&&before.size<=65536&&await realpath(LIVE_PIN)===LIVE_PIN,'LIVE_SOURCE_CHANGED');
 const fd=await open(LIVE_PIN,FS.O_RDONLY|FS.O_NOFOLLOW|FS.O_NONBLOCK);let bytes,pins;
 try{const first=await fd.stat();need(first.dev===before.dev&&first.ino===before.ino&&first.size===before.size,'LIVE_SOURCE_CHANGED');bytes=Buffer.alloc(first.size);
  let pos=0;while(pos<bytes.length){const n=await fd.read(bytes,pos,bytes.length-pos,pos);if(!n.bytesRead)break;pos+=n.bytesRead;}
  const after=await fd.stat();need(pos===bytes.length&&first.size===after.size&&first.mtimeMs===after.mtimeMs&&first.ctimeMs===after.ctimeMs&&sha(bytes)===expected,'LIVE_SOURCE_CHANGED');
  pins=parse(bytes,65536);
 }finally{bytes?.fill(0);await fd.close();}
 need(exact(pins,['format','files','node'])&&pins.format==='collect.managed-component-live-capture.sources.v1'&&exact(pins.files,LIVE_INPUTS)&&
  exact(pins.node,['path','sha256'])&&pins.node.path===NODE&&HASH.test(pins.node.sha256??''),'LIVE_SOURCE_CHANGED');
 for(const path of LIVE_INPUTS)need(HASH.test(pins.files[path]??'')&&await stableHash(resolve(ROOT,path),16*1024*1024)===pins.files[path],'LIVE_SOURCE_CHANGED');
 need(pins.files['scripts/supabase/managed-component-refresh/CAPTURE-SOURCE-PINS.json']===CAPTURE_PIN,'LIVE_SOURCE_CHANGED');
 need(process.version==='v24.19.0'&&process.execPath===NODE&&await stableHash(NODE,256*1024*1024)===pins.node.sha256,'NODE_RUNTIME_INVALID');
 return pins;
}
export function checkDispatchGate(value){need(value==='READ_ONLY_CAPTURE','DISPATCH_GATE_CLOSED');}
export function checkReceiptAuthority(component,path,digest){need(Object.hasOwn(LIVE_COUNTS,component),'COUNT_AUTHORITY_INVALID');const allowed=LIVE_COUNTS[component];need(path===allowed.path&&digest===allowed.sha256,'COUNT_AUTHORITY_INVALID');}

// Bounded TLS transport. The shared transport retains concatenation chunks;
// this candidate explicitly clears every owned chunk on success or failure.
function createLiveTransport(token,environment,requestImpl=httpsRequest,onOwnedChunk=()=>{},timeoutMs=60000){
 safeEnvironment(environment);need(typeof token==='string'&&token.length>=16&&token.length<=16384&&!/[\s\x00-\x1f]/.test(token),'TOKEN_INVALID');
 async function exchange(method,url,body,expected,cap){
  const outgoing=body===null?null:Buffer.from(JSON.stringify(body));need(!outgoing||outgoing.length<=4*1024*1024,'REQUEST_BOUND');
  try{return await new Promise((resolvePromise,reject)=>{let done=false,req,res,timer,length=0;const chunks=[];
   const finish=(code,value)=>{if(done)return;done=true;clearTimeout(timer);if(code){res?.destroy();req?.destroy();for(const b of chunks)b.fill(0);reject(new Refused(code));}
    else{for(const b of chunks)b.fill(0);resolvePromise(value);}};
   timer=setTimeout(()=>finish('TRANSPORT_TIMEOUT'),timeoutMs);
   try{req=requestImpl(new URL(url),{method,agent:false,rejectUnauthorized:true,maxHeaderSize:16384,
    headers:{Authorization:'Bearer '+token,Accept:'application/json',...(outgoing?{'Content-Type':'application/json','Content-Length':String(outgoing.length)}:{})}},incoming=>{
     res=incoming;res.on('error',()=>finish('TRANSPORT_UNCONFIRMED'));res.on('aborted',()=>finish('TRANSPORT_UNCONFIRMED'));
     if(res.statusCode>=300&&res.statusCode<=399)return finish('REDIRECT_REFUSED');if(res.statusCode!==expected)return finish('HTTP_STATUS_REFUSED');
     const declared=res.headers?.['content-length'];if(declared!==undefined&&(!/^[0-9]+$/.test(String(declared))||Number(declared)>cap))return finish('RESPONSE_BOUND');
     res.on('data',chunk=>{if(done)return;const bytes=Buffer.from(chunk);onOwnedChunk(bytes);length+=bytes.length;if(length>cap){bytes.fill(0);return finish('RESPONSE_BOUND');}chunks.push(bytes);});
     res.on('end',()=>{if(declared!==undefined&&length!==Number(declared))return finish('RESPONSE_LENGTH_CHANGED');
      const joined=Buffer.concat(chunks,length);finish(null,{status:expected,body:joined});});
    });req.on('error',()=>finish('TRANSPORT_UNCONFIRMED'));req.end(outgoing??undefined);
   }catch{finish('TRANSPORT_UNCONFIRMED');}
  });}finally{outgoing?.fill(0);}
 }
 return Object.freeze({
  async readProject(){const response=await exchange('GET',ENDPOINT,null,200,1024*1024);
   try{const p=parse(response.body,1024*1024),hasRef=p?.ref!==undefined&&p.ref!==null,hasId=p?.id!==undefined&&p.id!==null;
    need(p&&(hasRef||hasId)&&(!hasRef||p.ref===PROJECT)&&(!hasId||p.id===PROJECT)&&p.organization_id===ORG&&p.status==='ACTIVE_HEALTHY','PROJECT_IDENTITY_INVALID');
    return {project_ref:PROJECT,organization_id:ORG,status:'ACTIVE_HEALTHY'};}finally{response.body.fill(0);}},
  async query(request){return exchange('POST',ENDPOINT+'/database/query',request.body,201,8*1024*1024);}
 });
}

// This helper constructs the request implementation itself; a caller cannot
// supply a socket, callback, URL, token, transport or provider response source.
export async function exerciseTransportSynthetic({kind='project',chunks=[],status=200,headers={},stall=false,emitOnDestroy=false}={}){
 need(['project','query'].includes(kind)&&Array.isArray(chunks)&&chunks.length<=64&&chunks.every(x=>typeof x==='string')&&
  chunks.reduce((n,x)=>n+Buffer.byteLength(x),0)<=8*1024*1024+1,'SYNTHETIC_WIRE_REQUIRED');
 const observed=[],summary={owned_chunks_wiped:false,provider_contacted:false},outgoing=[];
 const mock=(url,options,callback)=>{
  summary.endpoint=url.href;summary.tls_verified=options.rejectUnauthorized===true;summary.agent_disabled=options.agent===false;summary.method=options.method;
  const req=new EventEmitter();req.destroy=()=>{};req.end=body=>{if(body)outgoing.push(body);if(stall)return;
   queueMicrotask(()=>{const res=new EventEmitter();res.statusCode=status;res.headers=headers;res.destroyed=false;res.destroy=()=>{res.destroyed=true;if(emitOnDestroy)res.emit('error',new Error('synthetic destroy'));};callback(res);
    for(const chunk of chunks){if(res.destroyed)break;res.emit('data',Buffer.from(chunk));}if(!res.destroyed)res.emit('end');});};return req;};
 const transport=createLiveTransport('synthetic-transport-token-never-sent',{},mock,b=>observed.push(b),stall?10:1000);
 try{
  if(kind==='project'){const result=await transport.readProject();summary.status='completed';summary.project_valid=result.project_ref===PROJECT;}
  else{const result=await transport.query({body:{query:'synthetic',read_only:true}});summary.status='completed';summary.response_bytes=result.body.length;result.body.fill(0);}
 }catch(error){summary.status='refused';summary.code=error?.code??'SYNTHETIC_UNCONFIRMED';}
 summary.owned_chunks_wiped=observed.every(b=>b.every(x=>x===0));summary.outgoing_wiped=outgoing.every(b=>b.every(x=>x===0));return summary;
}

const PLAN_FIELDS=['format','component','project_ref','source_pins_sha256','preflight_result_path','preflight_result_sha256','counts_path','counts_file_sha256',
 'canonical_counts_sha256','preflight_intent_sha256','reference_sha256','preflight_total_rows','request_id','query_sha256','request_file_sha256','request_read_only',
 'plan_only','capture_dispatched','restore_dispatched','quiescence_proven','full_recovery_acceptance'];
async function qualify({planPath,planSha256,pinsSha256,livePinsSha256,archiveDirectory,keyDirectory,environment,syntheticRoot},mode){
 need(rootedPath(planPath)&&planPath.endsWith('/PLAN.json')&&HASH.test(planSha256??''),'PLAN_PIN_REQUIRED');
 for(const path of [archiveDirectory,keyDirectory])need(rootedPath(path),'OUTPUT_PATH_INVALID');
 safeEnvironment(environment);need(pinsSha256===CAPTURE_PIN,'SOURCE_PIN_REQUIRED');await verifyLiveSources(livePinsSha256);await verifySources(pinsSha256);
 const {readPrivateFile,privateDirectory}=await import('../current-archive/bundle.mjs');
 const raw=await readPrivateFile(planPath,131072);let plan;
 try{need(sha(raw)===planSha256,'PLAN_CHANGED');plan=parse(raw,131072);}finally{raw.fill(0);}
 need(exact(plan,PLAN_FIELDS)&&plan.format==='collect.managed-component-capture.offline-plan.v1'&&['auth','storage'].includes(plan.component)&&plan.project_ref===PROJECT&&
  plan.source_pins_sha256===pinsSha256&&plan.request_read_only===true&&plan.plan_only===true&&plan.capture_dispatched===false&&plan.restore_dispatched===false&&
  plan.quiescence_proven===false&&plan.full_recovery_acceptance===false,'PLAN_INVALID');
 if(mode==='live')checkReceiptAuthority(plan.component,plan.preflight_result_path,plan.preflight_result_sha256);
 else{need(rootedPath(syntheticRoot)&&plan.preflight_result_path?.startsWith(syntheticRoot+'/'),'SYNTHETIC_PATH_REQUIRED');await privateDirectory(syntheticRoot);}
 const context=await loadContext({component:plan.component,resultPath:plan.preflight_result_path,resultSha256:plan.preflight_result_sha256,pinsSha256,environment});
 need(plan.counts_path===context.countPath&&plan.counts_file_sha256===context.result.counts_file_sha256&&plan.canonical_counts_sha256===context.result.canonical_counts_sha256&&
  plan.preflight_intent_sha256===context.intentSha256&&plan.reference_sha256===context.result.reference_sha256&&plan.preflight_total_rows===context.result.total_rows,'PLAN_CHANGED');
 const request=compile(context,plan.request_id),reqBytes=await readPrivateFile(resolve(dirname(planPath),'CAPTURE-REQUEST.json'),4*1024*1024);
 try{need(HASH.test(plan.request_file_sha256??'')&&sha(reqBytes)===plan.request_file_sha256&&request.query_sha256===plan.query_sha256&&
  context.codec.canonical(parse(reqBytes,4*1024*1024))===context.codec.canonical(request),'REQUEST_CHANGED');}finally{reqBytes.fill(0);}
 const root=resolve(import.meta.dirname,'../../..'),other='/Volumes/T7/01 Projects/COLLECT';
 for(const path of [archiveDirectory,keyDirectory]){
  for(const blocked of [root,other,dirname(planPath),dirname(plan.preflight_result_path)])need(separated(path,blocked),'OUTPUT_PATH_INVALID');
  await privateDirectory(dirname(path));await absent(path);
 }
 need(separated(archiveDirectory,keyDirectory),'OUTPUT_PATH_INVALID');await verifySources(pinsSha256);await verifyLiveSources(livePinsSha256);
 return {context,plan,request,planPath,planSha256,pinsSha256,livePinsSha256,archiveDirectory,keyDirectory};
}

async function core(options,makeTransport,mode){
 const q=await qualify(options,mode);let claimed=false,dispatched=false,success=false,receipt,bodyToWipe;
 const claimPath=resolve(dirname(q.planPath),'CLAIM.json'),outcomePath=resolve(dirname(q.planPath),'OUTCOME.json');
 const countClaimPath=resolve(dirname(q.plan.preflight_result_path),'CAPTURE-ONCE.json');
 try{
  // This claim is anchored to the count receipt rather than the plan: moving or
  // recreating a plan from the same receipt cannot bypass an earlier attempt.
  await writeNew(countClaimPath,Buffer.from(JSON.stringify({format:'collect.managed-component-capture.count-claim.v1',component:q.plan.component,
   count_result_sha256:q.plan.preflight_result_sha256,plan_path:q.planPath,plan_sha256:q.planSha256,query_sha256:q.plan.query_sha256,
   execution_mode:mode,live_source_pins_sha256:q.livePinsSha256,automatic_retry:false,absence_of_outcome_means_unconfirmed:true})+'\n'));
  await writeNew(claimPath,Buffer.from(JSON.stringify({format:'collect.managed-component-capture.claim.v1',component:q.plan.component,plan_sha256:q.planSha256,
   query_sha256:q.plan.query_sha256,execution_mode:mode,count_claim_path:countClaimPath,automatic_retry:false,absence_of_outcome_means_unconfirmed:true})+'\n'));claimed=true;
  const base=await makeTransport();let projectCalls=0,queryCalls=0;
  const transport=Object.freeze({
   async readProject(){need(++projectCalls===1,'PROJECT_CALL_INVALID');
    if(mode==='synthetic')await writeNew(resolve(q.archiveDirectory,'SYNTHETIC-ONLY.json'),Buffer.from(JSON.stringify({format:'collect.managed-component-capture.synthetic-only.v1',fixture:true,provider_contacted:false})+'\n'));
    return await base.readProject();},
   async query(request){need(projectCalls===1&&++queryCalls===1&&q.context.codec.canonical(request)===q.context.codec.canonical(q.request),'REQUEST_CHANGED');
    await verifyLiveSources(q.livePinsSha256);await verifySources(q.pinsSha256);
    dispatched=true;const response=await base.query(request);bodyToWipe=response?.body;
    try{need(response?.status===201&&Buffer.isBuffer(response.body)&&response.body.length<=8*1024*1024,'WIRE_BOUND');
     const outer=parse(response.body,8*1024*1024);need(Array.isArray(outer)&&outer.length===1&&exact(outer[0],['kind','payload'])&&typeof outer[0].payload==='string','WIRE_INVALID');
     assertUniqueJson(outer[0].payload,8*1024*1024);return response;
    }catch(e){response?.body?.fill(0);throw e;}}
  });
  const capture=q.plan.component==='auth'?q.context.library.captureAuth:q.context.library.captureStorageMetadata;
  receipt=await capture({transport,reference:q.context.reference,counts:q.context.counts,expectedCountsSha256:q.plan.canonical_counts_sha256,
   requestId:q.plan.request_id,archiveDirectory:q.archiveDirectory,keyDirectory:q.keyDirectory,executeReviewedReadOnly:true});
  need(projectCalls===1&&queryCalls===1&&receipt.project_ref===PROJECT&&receipt.query_sha256===q.plan.query_sha256&&receipt.counts_preflight_sha256===q.plan.canonical_counts_sha256&&
   receipt.reference_sha256===q.plan.reference_sha256&&receipt.authenticated_readback===true&&receipt.full_recovery_acceptance===false&&receipt.automatic_retry===false&&
   receipt.native_rollback_command_complete_observed===false&&dirname(receipt.archive_path)===q.archiveDirectory&&dirname(receipt.key_path)===q.keyDirectory&&
   HASH.test(receipt.archive_sha256??'')&&HASH.test(receipt.snapshot_sha256??''),'CAPTURE_RESULT_INVALID');
  const resultBytes=await q.context.bundle.readPrivateFile(resolve(q.archiveDirectory,'RESULT.json'),131072);let resultSha256;
  try{const stored=parse(resultBytes,131072);need(q.context.codec.canonical(stored)===q.context.codec.canonical(receipt),'CAPTURE_RESULT_INVALID');resultSha256=sha(resultBytes);}finally{resultBytes.fill(0);}
  await verifySources(q.pinsSha256);await verifyLiveSources(q.livePinsSha256);success=true;
  return {component:q.plan.component,execution_mode:mode,archive_directory:q.archiveDirectory,key_directory:q.keyDirectory,result_sha256:resultSha256,
   archive_sha256:receipt.archive_sha256,snapshot_sha256:receipt.snapshot_sha256,rows:receipt.rows,tables:receipt.tables,
   provider_capture_dispatched:mode==='live',synthetic_response_used:mode==='synthetic',native_rollback_command_complete_observed:false,quiescence_proven:false,full_recovery_acceptance:false};
 }finally{
  bodyToWipe?.fill(0);
  if(claimed)await writeNew(outcomePath,Buffer.from(JSON.stringify({format:'collect.managed-component-capture.outcome.v1',component:q.plan.component,plan_sha256:q.planSha256,
   execution_mode:mode,transport_query_attempted:dispatched,provider_query_attempted:mode==='live'&&dispatched,outcome:success?'COMPLETED':'REFUSED_OR_UNCONFIRMED',automatic_retry:false,preserve_partial:true,full_recovery_acceptance:false})+'\n'));
 }
}

// Deliberately internal transport cannot be supplied by a test caller. Both
// the plan and output directories must be in a new private synthetic temp root.
export async function executeSynthetic(options,{wire}={}){
 const prefix='/private/tmp/collect-component-capture-test-';
 for(const path of [options?.planPath,options?.archiveDirectory,options?.keyDirectory])need(rootedPath(path)&&path.startsWith(prefix),'SYNTHETIC_PATH_REQUIRED');
 const end=options.planPath.indexOf('/',prefix.length);need(end>prefix.length,'SYNTHETIC_PATH_REQUIRED');const syntheticRoot=options.planPath.slice(0,end);
 for(const path of [options.planPath,options.archiveDirectory,options.keyDirectory])need(path.startsWith(syntheticRoot+'/'),'SYNTHETIC_PATH_REQUIRED');
 need(typeof wire==='string'&&Buffer.byteLength(wire)<=8*1024*1024,'SYNTHETIC_WIRE_REQUIRED');
 return core({...options,syntheticRoot,environment:{}},async()=>({
  async readProject(){return {project_ref:PROJECT,organization_id:ORG,status:'ACTIVE_HEALTHY'};},
  async query(){return {status:201,body:Buffer.from(wire)};}
 }),'synthetic');
}
export async function executeLive(options={}){
 let token;try{checkDispatchGate(options.dispatch);checkRuntimeArguments(process.execArgv);safeEnvironment(process.env);await verifyLiveSources(options.livePinsSha256);
  token=process.env[TOKEN_ENV];delete process.env[TOKEN_ENV];need(typeof token==='string'&&token.length>=16&&token.length<=16384&&!/[\s\x00-\x1f]/.test(token),'TOKEN_INVALID');
  return await core({...options,environment:process.env},async()=>{const transport=createLiveTransport(token,process.env);token=null;return transport;},'live');
 }finally{token=null;delete process.env[TOKEN_ENV];}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 try{checkRuntimeArguments(process.execArgv);safeEnvironment(process.env);const args=process.argv.slice(2),v={};need(args.length===14,'ARGUMENTS_INVALID');
  for(let i=0;i<args.length;i+=2){need(['--plan','--plan-sha256','--pins-sha256','--live-pins-sha256','--archive-dir','--key-dir','--dispatch'].includes(args[i])&&!Object.hasOwn(v,args[i])&&args[i+1]&&!args[i+1].startsWith('--'),'ARGUMENTS_INVALID');v[args[i]]=args[i+1];}
  const result=await executeLive({planPath:v['--plan'],planSha256:v['--plan-sha256'],pinsSha256:v['--pins-sha256'],livePinsSha256:v['--live-pins-sha256'],archiveDirectory:v['--archive-dir'],keyDirectory:v['--key-dir'],dispatch:v['--dispatch']});process.stdout.write(JSON.stringify(result)+'\n');
 }catch(error){process.stderr.write(JSON.stringify({status:'refused_or_unconfirmed',code:'CAPTURE_UNCONFIRMED',capture_dispatch_status:'see_count_claim_and_plan_outcome'})+'\n');process.exitCode=1;}
}
