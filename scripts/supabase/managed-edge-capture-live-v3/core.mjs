// Review candidate: managed capture must run only through its pinned supervisor.
import {createHash,randomBytes} from 'node:crypto';
import {request as httpsRequest} from 'node:https';
import {constants as FS} from 'node:fs';
import {open} from 'node:fs/promises';
import {dirname,resolve,relative,isAbsolute,sep} from 'node:path';
import {types} from 'node:util';
import {privateDirectory,readPrivateFile} from '../current-archive/bundle.mjs';
import {assertUniqueJson} from '../managed-component-refresh/capture-json.mjs';
import {CaptureError,PROJECT,SLUGS,MAX_BODY,MAX_ARCHIVE,sealFunctionBodies,inspectSealedFunctionBodies,validateMetadata} from './seal.mjs';
import {inspectMultipart} from './multipart.mjs';
import {verifyPinnedSources} from './source-pins.mjs';
import {PhaseJournal} from './diagnostics.mjs';

const ORG='ghnjnepwvwknswrwzepn',UUID=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/,HASH=/^[a-f0-9]{64}$/;
const fields=['format','scope','operation_id','archive_dir','key_dir','token_path','source_pins_sha256','deadline_ms','fixture'];
const forbidden=/^(?:NODE_.*|OPENSSL_.*|SSL_.*|SSLKEYLOGFILE|LD_.*|DYLD_.*|(?:HTTP|HTTPS|ALL|NO)_PROXY)$/i;
const sha=x=>createHash('sha256').update(x).digest('hex');
const need=(x,c)=>{if(!x)throw new CaptureError(c);};
function plain(x){return x&&typeof x==='object'&&!Array.isArray(x)&&!types.isProxy(x)&&Object.getPrototypeOf(x)===Object.prototype;}
function value(x,key){const d=Object.getOwnPropertyDescriptor(x,key);need(d&&Object.hasOwn(d,'value'),'PLAN_INVALID');return d.value;}
function contains(a,b){const r=relative(a,b);return r===''||r!=='..'&&!r.startsWith('..'+sep)&&!isAbsolute(r);}
export function canonicalPlan(p){
 need(plain(p)&&Reflect.ownKeys(p).length===fields.length&&Object.keys(p).sort().join('\0')===[...fields].sort().join('\0'),'PLAN_INVALID');
 const v=Object.fromEntries(fields.map(k=>[k,value(p,k)]));
 need(v.format==='collect.edge-capture.plan.v2'&&['synthetic','managed'].includes(v.scope)&&UUID.test(v.operation_id??'')&&
  HASH.test(v.source_pins_sha256??'')&&Number.isSafeInteger(v.deadline_ms)&&v.deadline_ms>=1000&&v.deadline_ms<=3600000&&
  ['archive_dir','key_dir'].every(k=>typeof v[k]==='string'&&isAbsolute(v[k])&&resolve(v[k])===v[k])&&
  (v.scope==='synthetic'?v.token_path===null&&['normal','hang','ignore_abort','metadata_drift','other_metadata_drift','numeric_precision_drift','error_body','wrong_project'].includes(v.fixture):
   v.fixture===null&&typeof v.token_path==='string'&&isAbsolute(v.token_path)&&resolve(v.token_path)===v.token_path)&&
  !contains(v.archive_dir,v.key_dir)&&!contains(v.key_dir,v.archive_dir),'PLAN_INVALID');
 return JSON.stringify(v);
}
export const planDigest=p=>sha(Buffer.from(canonicalPlan(p),'utf8'));
export function cleanEnvironment(env=process.env,args=process.execArgv){return Array.isArray(args)&&args.length===0&&!Object.entries(env).some(([k,v])=>v&&forbidden.test(k));}
async function writeNew(path,bytes){const fd=await open(path,FS.O_WRONLY|FS.O_CREAT|FS.O_EXCL|FS.O_NOFOLLOW,0o600);try{await fd.writeFile(bytes);await fd.sync();}finally{await fd.close();}}
async function syncDir(path){const fd=await open(path,FS.O_RDONLY);try{await fd.sync();}finally{await fd.close();}}
function projectValid(p){const hasId=p?.id!==undefined&&p.id!==null,hasRef=p?.ref!==undefined&&p.ref!==null;
 return plain(p)&&(hasId||hasRef)&&(!hasId||p.id===PROJECT)&&(!hasRef||p.ref===PROJECT)&&p.organization_id===ORG&&p.status==='ACTIVE_HEALTHY';}
function parseJson(b){try{const s=new TextDecoder('utf-8',{fatal:true}).decode(b);assertUniqueJson(s,1024*1024);return JSON.parse(s);}catch{throw new CaptureError('PROVIDER_RESPONSE_INVALID');}}
function selectedMetadata(raw,slug,metadataSha,contentType){
 const m={slug:raw?.slug,id:raw?.id,status:raw?.status,version:raw?.version,updated_at:raw?.updated_at,
  ezbr_sha256:raw?.ezbr_sha256??null,verify_jwt:raw?.verify_jwt??null,metadata_sha256:metadataSha,body_content_type:contentType};
 validateMetadata(m,slug);return m;
}

// This transport has no caller-supplied URL, TLS option, agent or callback.
// Metadata/body reads can still observe separate deployment points in time.
function managedTransport(token,signal,markAttempted){
 const base='https://api.supabase.com/v1/projects/'+PROJECT;
 async function get(path,cap,accept,trace){
  return new Promise((resolvePromise,reject)=>{
   let req,res,done=false,total=0,timer,chunks=[];
   const onAbort=()=>finish('CAPTURE_INTERRUPTED');
   const finish=(code,data)=>{if(done)return;done=true;clearTimeout(timer);signal?.removeEventListener('abort',onAbort);if(code){res?.destroy();req?.destroy();for(const c of chunks)c.fill(0);chunks=[];reject(new CaptureError(code));}
    else{for(const c of chunks)c.fill(0);chunks=[];resolvePromise(data);}};
   if(signal?.aborted){finish('CAPTURE_INTERRUPTED');return;}signal?.addEventListener('abort',onAbort,{once:true});
   timer=setTimeout(()=>finish('PROVIDER_TIMEOUT'),60000);
   try{markAttempted();req=httpsRequest(new URL(base+path),{method:'GET',agent:false,rejectUnauthorized:true,maxHeaderSize:16384,
    headers:{Authorization:'Bearer '+token,Accept:accept,'Accept-Encoding':'identity'}},incoming=>{
     res=incoming;res.on('error',()=>finish('PROVIDER_RESPONSE_ERROR'));res.on('aborted',()=>finish('PROVIDER_RESPONSE_ERROR'));
     const declared=res.headers['content-length'],encoding=res.headers['content-encoding'];
     trace?.response(res.statusCode,res.headers['content-type'],encoding,declared,cap);
     if(res.statusCode!==200)return finish('PROVIDER_HTTP_STATUS');
     if(encoding&&encoding!=='identity')return finish('PROVIDER_UNSUPPORTED_ENCODING');
     if(declared!==undefined&&!/^[0-9]+$/.test(String(declared)))return finish('PROVIDER_DECLARED_LENGTH_INVALID');
     if(declared!==undefined&&Number(declared)>cap)return finish('PROVIDER_SIZE_BOUND');
     res.on('data',b=>{if(done)return;const copy=Buffer.from(b);total+=copy.length;if(total>cap){copy.fill(0);return finish('PROVIDER_SIZE_BOUND');}chunks.push(copy);});
     res.on('end',()=>{if(declared!==undefined&&total!==Number(declared))return finish('PROVIDER_BODY_TRUNCATED');const b=Buffer.concat(chunks,total);trace?.body(b);finish(null,{bytes:b,contentType:res.headers['content-type']??''});});
    });req.on('error',()=>finish('PROVIDER_TRANSPORT_ERROR'));req.end();
   }catch{finish('PROVIDER_TRANSPORT_ERROR');}
  });
 }
 return Object.freeze({async project(trace){const b=await get('',1024*1024,'application/json',trace);try{return parseJson(b.bytes);}finally{b.bytes.fill(0);}},
  async metadata(slug,trace){need(SLUGS.includes(slug),'SLUG_INVALID');const b=await get('/functions/'+slug,1024*1024,'application/json',trace);return b.bytes;},
  async body(slug,trace){need(SLUGS.includes(slug),'SLUG_INVALID');const r=await get('/functions/'+slug+'/body',MAX_BODY,'multipart/form-data',trace);return {body:r.bytes,contentType:r.contentType};}});
}

async function capture({plan,expectedPlanSha256,transport,managed,signal}){
 const encoded=canonicalPlan(plan);need(HASH.test(expectedPlanSha256??'')&&sha(Buffer.from(encoded))===expectedPlanSha256,'PLAN_PIN_MISMATCH');
 plan=JSON.parse(encoded);
 need(plan.scope===(managed?'managed':'synthetic'),'PLAN_INVALID');
 need(signal===null||signal instanceof AbortSignal,'INPUT_INVALID');const checkAbort=()=>need(!signal?.aborted,'CAPTURE_INTERRUPTED');checkAbort();
 if(managed)need(cleanEnvironment(),'ENVIRONMENT_REFUSED');
 else need(plan.archive_dir.startsWith('/private/tmp/collect-edge-capture-test-')&&plan.key_dir.startsWith('/private/tmp/collect-edge-capture-test-'),'SYNTHETIC_ROOT_REQUIRED');
 await privateDirectory(plan.archive_dir);await privateDirectory(plan.key_dir);
 const claim=resolve(plan.archive_dir,'EDGE-CAPTURE-CLAIM.json'),outcome=resolve(plan.archive_dir,'EDGE-CAPTURE-OUTCOME.json');
 await writeNew(claim,Buffer.from(JSON.stringify({format:'collect.edge-capture.claim.v2',scope:plan.scope,project_ref:PROJECT,operation_id:plan.operation_id,plan_sha256:expectedPlanSha256,automatic_retry:false,claim_scope:'archive_directory'})+'\n'));await syncDir(plan.archive_dir);
 let key,tokenBytes,token,archive,claimed=true,completed=false,attempted=false;const records=[];
 const diagnostic=new PhaseJournal({archiveDir:plan.archive_dir,scope:plan.scope,operationId:plan.operation_id,planSha256:expectedPlanSha256});
 const wipePending=v=>{if(Buffer.isBuffer(v))v.fill(0);else if(v&&typeof v==='object')for(const k of ['body','bytes','archive'])if(Buffer.isBuffer(v[k]))v[k].fill(0);};
 async function step(name,slug,fn){await diagnostic.start(name,slug);let result;try{result=await fn(diagnostic);await diagnostic.complete();return result;}
  catch(e){wipePending(result);try{await diagnostic.failed(e);}catch{}throw e;}}
 try{
  checkAbort();const keyPath=resolve(plan.key_dir,plan.operation_id+'.key');key=await step('KEY_CREATE',null,async()=>{const b=randomBytes(32);try{await writeNew(keyPath,b);await syncDir(plan.key_dir);return b;}catch(e){b.fill(0);throw e;}});
  if(managed){const acquired=await step('TOKEN_READ',null,async()=>{const b=await readPrivateFile(plan.token_path,16384);try{const s=new TextDecoder('utf-8',{fatal:true}).decode(b).replace(/\r?\n$/,'');
   need(s.length>=16&&s.length<=16384&&!/[\s\x00-\x1f]/.test(s),'TOKEN_INVALID');return {bytes:b,token:s};}catch(e){b.fill(0);throw e;}});
   tokenBytes=acquired.bytes;token=acquired.token;transport=managedTransport(token,signal,()=>{attempted=true;});}
  need(transport&&['project','metadata','body'].every(k=>typeof transport[k]==='function'),'TRANSPORT_INVALID');
  checkAbort();const project=await step('PROJECT_GET',null,t=>transport.project(t));await step('PROJECT_IDENTITY',null,()=>need(projectValid(project),'PROJECT_IDENTITY_INVALID'));
  for(const slug of SLUGS){
   checkAbort();const beforeBytes=await step('METADATA_BEFORE_GET',slug,async t=>{const b=await transport.metadata(slug,t);need(Buffer.isBuffer(b),'PROVIDER_RESPONSE_INVALID');return b;});let beforeRaw,beforeHash;
   try{await step('METADATA_BEFORE_VALIDATE',slug,()=>{need(beforeBytes.length<=1024*1024,'PROVIDER_RESPONSE_INVALID');beforeHash=sha(beforeBytes);beforeRaw=parseJson(beforeBytes);selectedMetadata(beforeRaw,slug,beforeHash,'multipart/form-data; boundary=x');});}finally{beforeBytes.fill(0);}
   const response=await step('BODY_GET',slug,async t=>{const r=await transport.body(slug,t);need(plain(r)&&Buffer.isBuffer(r.body),'BODY_INVALID');return r;});const record={metadata:null,body:response.body};records.push(record);
   await step('BODY_VALIDATE',slug,t=>{t.response(null,response.contentType,undefined,undefined,MAX_BODY);t.body(record.body);const recognized=inspectMultipart(record.body,response.contentType);record.metadata=selectedMetadata(beforeRaw,slug,beforeHash,recognized.contentType);});
   const afterBytes=await step('METADATA_AFTER_GET',slug,async t=>{const b=await transport.metadata(slug,t);need(Buffer.isBuffer(b),'PROVIDER_RESPONSE_INVALID');return b;});
   try{await step('METADATA_AFTER_COMPARE',slug,()=>{need(afterBytes.length<=1024*1024,'PROVIDER_RESPONSE_INVALID');parseJson(afterBytes);need(beforeHash===sha(afterBytes),'DEPLOYMENT_CHANGED');});}finally{afterBytes.fill(0);}
  }
  checkAbort();
  const sealed=await step('ARCHIVE_SEAL',null,()=>sealFunctionBodies({records,operationId:plan.operation_id,scope:plan.scope,planSha256:expectedPlanSha256,key}));archive=sealed.archive;
  const archivePath=resolve(plan.archive_dir,plan.operation_id+'.edge.gcm');await step('ARCHIVE_WRITE',null,async()=>{await writeNew(archivePath,archive);await syncDir(plan.archive_dir);});
  const checked=await step('ARCHIVE_READBACK',null,async()=>{let saved,savedKey;try{saved=await readPrivateFile(archivePath,MAX_ARCHIVE);savedKey=await readPrivateFile(keyPath,32);
   need(sha(saved)===sha(archive),'ARCHIVE_CHANGED');return inspectSealedFunctionBodies({archive:saved,key:savedKey,operationId:plan.operation_id,scope:plan.scope,planSha256:expectedPlanSha256});}
   finally{saved?.fill(0);savedKey?.fill(0);}});
  const functions=checked.functions.map(({body_content_type,...safe})=>safe);
  const receipt={format:'collect.edge-capture.receipt.v2',scope:plan.scope,project_ref:PROJECT,operation_id:plan.operation_id,plan_sha256:expectedPlanSha256,
   archive_sha256:checked.archive_sha256,archive_bytes:archive.length,functions,authenticated_readback:true,
   key_custody_independent:false,provider_settings_included:false,provider_secret_configuration_included:false,
   source_may_contain_sensitive_material:true,metadata_response_compared:true,recognized_multipart_envelope:true,source_content_extracted:false,deployability_proven:false,coordinated_snapshot:false};
  await step('RECEIPT_WRITE',null,async()=>{await writeNew(resolve(plan.archive_dir,'EDGE-CAPTURE-RESULT.json'),Buffer.from(JSON.stringify(receipt)+'\n'));await syncDir(plan.archive_dir);});completed=true;
  return receipt;
 }finally{
  for(const r of records)r.body.fill(0);key?.fill(0);tokenBytes?.fill(0);token=undefined;archive?.fill(0);
  if(claimed){await writeNew(outcome,Buffer.from(JSON.stringify({format:'collect.edge-capture.outcome.v2',scope:plan.scope,operation_id:plan.operation_id,
   plan_sha256:expectedPlanSha256,provider_read_attempted:attempted,outcome:completed?'COMPLETED':'UNCONFIRMED',automatic_retry:false})+'\n'));await syncDir(plan.archive_dir);}
 }
}
// Callers must use the reviewed process supervisor; direct import is not an OS
// isolation boundary. The pin is checked again inside the worker before reads.
export async function captureManaged(o){need(plain(o)&&Reflect.ownKeys(o).sort().join(',')==='expectedPlanSha256,plan,signal','INPUT_INVALID');
 const plan=value(o,'plan');await verifyPinnedSources(plan?.source_pins_sha256);return capture({plan,expectedPlanSha256:value(o,'expectedPlanSha256'),signal:value(o,'signal'),managed:true});}
export async function captureSynthetic(o){need(plain(o)&&Reflect.ownKeys(o).sort().join(',')==='expectedPlanSha256,plan,signal,transport','INPUT_INVALID');
 const plan=value(o,'plan');await verifyPinnedSources(plan?.source_pins_sha256);return capture({plan,expectedPlanSha256:value(o,'expectedPlanSha256'),transport:value(o,'transport'),signal:value(o,'signal'),managed:false});}
