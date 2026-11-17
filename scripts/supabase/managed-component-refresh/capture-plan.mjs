// Offline planning for a separately reviewed managed-component capture.
// Importing this module does not dispatch a request or read any credential.
import {createHash,randomUUID} from 'node:crypto';
import {constants as FS} from 'node:fs';
import {lstat,mkdir,open,realpath} from 'node:fs/promises';
import {dirname,isAbsolute,relative,resolve,sep} from 'node:path';
import {pathToFileURL} from 'node:url';

const ROOT=resolve(import.meta.dirname,'../../..');
const OTHER='/Volumes/T7/01 Projects/COLLECT';
const NODE='/Volumes/PRO-G40/Development/Node/bin/node';
const PIN=resolve(import.meta.dirname,'CAPTURE-SOURCE-PINS.json');
const PREFLIGHT_PIN='58f63cebba51903806cc0587cf5cb6f92f0c582fbb6053ba0df16bfb6c4fd482';
const PROJECT='rrlduytparvsjfmegalh';
const HASH=/^[a-f0-9]{64}$/;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const INPUTS=Object.freeze([
 'scripts/supabase/managed-component-refresh/capture-plan.mjs',
 'scripts/supabase/managed-component-refresh/capture-plan.test.mjs',
 'scripts/supabase/managed-component-refresh/capture-runner.mjs',
 'scripts/supabase/managed-component-refresh/capture-runner.test.mjs',
 'scripts/supabase/managed-component-refresh/capture-json.mjs',
 'scripts/supabase/managed-component-refresh/capture-fixtures.mjs',
 'scripts/supabase/managed-component-refresh/CAPTURE-README.md',
 'scripts/supabase/managed-component-refresh/preflight.mjs',
 'scripts/supabase/managed-component-refresh/SOURCE-PINS.json',
 'scripts/supabase/current-archive/bundle.mjs',
 'scripts/supabase/current-archive/codec.mjs',
 'scripts/supabase/current-archive/sql.mjs',
 'scripts/supabase/current-archive/restore.mjs',
 'scripts/supabase/managed-auth-archive/REFERENCE.json',
 'scripts/supabase/managed-auth-archive/counts.mjs',
 'scripts/supabase/managed-auth-archive/auth.mjs',
 'scripts/supabase/managed-auth-archive/native-definition.mjs',
 'scripts/supabase/managed-storage-archive-v2/REFERENCE.json',
 'scripts/supabase/managed-storage-archive-v2/counts.mjs',
 'scripts/supabase/managed-storage-archive-v2/storage.mjs',
 'scripts/supabase/managed-storage-archive-v2/native-definition.mjs',
]);
class Refused extends Error{constructor(code){super(code);this.code=code;}}
const need=(ok,code)=>{if(!ok)throw new Refused(code);};
const sha=x=>createHash('sha256').update(x).digest('hex');
const exact=(x,keys)=>x!==null&&typeof x==='object'&&!Array.isArray(x)&&Object.getPrototypeOf(x)===Object.prototype&&Object.keys(x).sort().join('\0')===[...keys].sort().join('\0');
const within=(p,r)=>{const x=relative(r,p);return x===''||x!=='..'&&!x.startsWith('..'+sep)&&!isAbsolute(x);};
export const separated=(a,b)=>!within(a,b)&&!within(b,a);
export const rootedPath=p=>typeof p==='string'&&isAbsolute(p)&&resolve(p)===p;

export function safeEnvironment(env){
 for(const [key,value] of Object.entries(env))if(value&&(/^(?:https?|all|no)_proxy$/i.test(key)||
  /^(?:NODE_|OPENSSL_|SSL_|SSLKEYLOGFILE$|LD_|DYLD_)/i.test(key)||/^GLOBAL_AGENT_HTTP_PROXY$/i.test(key)))throw new Refused('UNSAFE_ENVIRONMENT');
}
export function checkRuntimeArguments(args){need(Array.isArray(args)&&args.length===0,'UNSAFE_EXEC_ARGS');}
async function stableHash(path,maximum){
 need(rootedPath(path)&&await realpath(path)===path,'SOURCE_CHANGED');
 const before=await lstat(path);need(before.isFile()&&!before.isSymbolicLink()&&before.size>=0&&before.size<=maximum,'SOURCE_CHANGED');
 const fd=await open(path,FS.O_RDONLY|FS.O_NOFOLLOW|FS.O_NONBLOCK),buffer=Buffer.alloc(1024*1024),hash=createHash('sha256');
 const ident=s=>[s.dev,s.ino,s.size,s.mtimeMs,s.ctimeMs,s.nlink].join(':');
 try{const first=await fd.stat();need(ident(first)===ident(before),'SOURCE_CHANGED');let p=0;
  while(p<first.size){const n=await fd.read(buffer,0,Math.min(buffer.length,first.size-p),p);if(!n.bytesRead)break;hash.update(buffer.subarray(0,n.bytesRead));p+=n.bytesRead;}
  const probe=await fd.read(buffer,0,1,first.size),after=await fd.stat(),last=await lstat(path);
  need(p===first.size&&probe.bytesRead===0&&ident(first)===ident(after)&&ident(first)===ident(last),'SOURCE_CHANGED');return hash.digest('hex');
 }finally{buffer.fill(0);await fd.close();}
}
async function pinnedManifest(expected){
 need(HASH.test(expected??''),'SOURCE_PIN_REQUIRED');need(await realpath(ROOT)===ROOT,'SOURCE_CHANGED');
 const expectedSize=65536,before=await lstat(PIN);need(before.isFile()&&before.size<=expectedSize&&await realpath(PIN)===PIN,'SOURCE_CHANGED');
 const fd=await open(PIN,FS.O_RDONLY|FS.O_NOFOLLOW|FS.O_NONBLOCK);let bytes;
 try{const initial=await fd.stat();need(initial.dev===before.dev&&initial.ino===before.ino&&initial.size===before.size,'SOURCE_CHANGED');
  bytes=Buffer.alloc(initial.size);let n=0;while(n<bytes.length){const x=await fd.read(bytes,n,bytes.length-n,n);if(!x.bytesRead)break;n+=x.bytesRead;}
  const after=await fd.stat();need(n===bytes.length&&initial.size===after.size&&initial.mtimeMs===after.mtimeMs&&initial.ctimeMs===after.ctimeMs&&sha(bytes)===expected,'SOURCE_CHANGED');
  return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
 }finally{bytes?.fill(0);await fd.close();}
}
export async function verifySources(expected){
 const pins=await pinnedManifest(expected);
 need(exact(pins,['format','files','node'])&&pins.format==='collect.managed-component-capture.sources.v1'&&
  exact(pins.files,INPUTS)&&exact(pins.node,['path','sha256'])&&pins.node.path===NODE&&HASH.test(pins.node.sha256??''),'SOURCE_CHANGED');
 for(const path of INPUTS){need(HASH.test(pins.files[path]??''),'SOURCE_CHANGED');need(await stableHash(resolve(ROOT,path),16*1024*1024)===pins.files[path],'SOURCE_CHANGED');}
 need(process.version==='v24.19.0'&&process.execPath===NODE&&await stableHash(NODE,256*1024*1024)===pins.node.sha256,'NODE_RUNTIME_INVALID');
 need(await stableHash(resolve(import.meta.dirname,'SOURCE-PINS.json'),65536)===PREFLIGHT_PIN,'PREFLIGHT_SOURCE_CHANGED');
 return pins;
}
async function modules(component){
 const dir=component==='auth'?'managed-auth-archive':'managed-storage-archive-v2';
 const [library,codec,bundle,preflight,countsLibrary]=await Promise.all([
  import(pathToFileURL(resolve(ROOT,'scripts/supabase',dir,component==='auth'?'auth.mjs':'storage.mjs')).href),
  import(pathToFileURL(resolve(ROOT,'scripts/supabase/current-archive/codec.mjs')).href),
  import(pathToFileURL(resolve(ROOT,'scripts/supabase/current-archive/bundle.mjs')).href),
  import(pathToFileURL(resolve(import.meta.dirname,'preflight.mjs')).href),
  import(pathToFileURL(resolve(ROOT,'scripts/supabase',dir,'counts.mjs')).href),
 ]);
 const refPath=resolve(ROOT,'scripts/supabase',dir,'REFERENCE.json');
 const fd=await open(refPath,FS.O_RDONLY|FS.O_NOFOLLOW|FS.O_NONBLOCK);let bytes;
 try{const s=await fd.stat();need(s.isFile()&&s.size>0&&s.size<=131072,'SOURCE_CHANGED');bytes=Buffer.alloc(s.size);
  let n=0;while(n<bytes.length){const x=await fd.read(bytes,n,bytes.length-n,n);if(!x.bytesRead)break;n+=x.bytesRead;}need(n===bytes.length,'SOURCE_CHANGED');
  const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);preflight.uniqueJson(text);const reference=JSON.parse(text);
  countsLibrary.validateReference(reference);return {library,codec,bundle,preflight,countsLibrary,reference};
 }finally{bytes?.fill(0);await fd.close();}
}
function decode(bytes,uniqueJson){const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);uniqueJson(text);return JSON.parse(text);}
export async function loadContext({component,resultPath,resultSha256,pinsSha256,environment=process.env}){
 need(['auth','storage'].includes(component),'COMPONENT_INVALID');safeEnvironment(environment);
 need(rootedPath(resultPath)&&resultPath.endsWith('/RESULT.json')&&HASH.test(resultSha256??''),'RESULT_PIN_REQUIRED');
 await verifySources(pinsSha256);const m=await modules(component);
 const data=await m.bundle.readPrivateFile(resultPath,131072);let result,counts,intent;
 try{need(sha(data)===resultSha256,'RESULT_CHANGED');result=decode(data,m.preflight.uniqueJson);}finally{data.fill(0);}
 const fields=['format','component','project_ref','request_id','query_sha256','source_pins_sha256','reference_sha256','counts_file_sha256','canonical_counts_sha256','state','total_rows','metadata_only','real_data_capture','automatic_retry','native_rollback_command_complete_observed','full_recovery_acceptance'];
 need(exact(result,fields)&&result.format==='collect.managed-component-preflight.result.v1'&&result.component===component&&result.project_ref===PROJECT&&
  UUID.test(result.request_id??'')&&HASH.test(result.query_sha256??'')&&result.source_pins_sha256===PREFLIGHT_PIN&&result.reference_sha256===m.countsLibrary.REFERENCE_SHA256&&
  HASH.test(result.counts_file_sha256??'')&&HASH.test(result.canonical_counts_sha256??'')&&result.metadata_only===true&&result.real_data_capture===false&&
  result.automatic_retry===false&&result.native_rollback_command_complete_observed===false&&result.full_recovery_acceptance===false,'RESULT_INVALID');
 const countPath=resolve(dirname(resultPath),'COUNTS.json'),bytes=await m.bundle.readPrivateFile(countPath,131072);
 try{need(sha(bytes)===result.counts_file_sha256,'COUNTS_CHANGED');counts=decode(bytes,m.preflight.uniqueJson);}finally{bytes.fill(0);}
 const intentBytes=await m.bundle.readPrivateFile(resolve(dirname(resultPath),'INTENT.json'),131072);let intentSha256;
 try{intentSha256=sha(intentBytes);intent=decode(intentBytes,m.preflight.uniqueJson);}finally{intentBytes.fill(0);}
 need(exact(intent,['format','component','project_ref','request_id','query_sha256','source_pins_sha256','reference_sha256','read_only','metadata_only','capture_dispatched','automatic_retry'])&&
  intent.format==='collect.managed-component-preflight.intent.v1'&&intent.component===component&&intent.project_ref===PROJECT&&intent.request_id===result.request_id&&
  intent.query_sha256===result.query_sha256&&intent.source_pins_sha256===PREFLIGHT_PIN&&intent.reference_sha256===result.reference_sha256&&
  intent.read_only===true&&intent.metadata_only===true&&intent.capture_dispatched===false&&intent.automatic_retry===false,'INTENT_INVALID');
 const state=component==='auth'?'COUNTS_WITHIN_ROW_CAPS_REQUIRES_ROOT_CAPTURE_REVIEW':'EXACT_COUNTS_AND_SAFE_AGGREGATES_PARSED';
 need(m.codec.sha(m.codec.canonical(counts))===result.canonical_counts_sha256&&counts.project_ref===PROJECT&&counts.reference_sha256===result.reference_sha256&&
  counts.query_sha256===result.query_sha256&&counts.state===state&&result.state===state&&counts.total_rows===result.total_rows&&counts.metadata_only_preflight===true&&
  counts.capture_dispatched===false&&counts.full_recovery_acceptance===false,'COUNTS_INVALID');
 if(component==='auth')need(counts.format==='collect.managed-auth.counts.parsed.v1'&&counts.within_capture_row_caps===true&&counts.exact_auth_row_counts_measured===true&&
  counts.auth_cell_values_returned===false&&counts.sequence_values_returned===false&&counts.auth_quiescence_proven===false,'COUNTS_INVALID');
 else need(counts.format==='collect.managed-storage.counts.parsed.v1'&&counts.within_row_caps===true&&counts.storage_quiescence_proven===false&&
  counts.storage_identifiers_returned===false&&counts.metadata_bodies_returned===false&&counts.version_values_returned===false&&counts.object_bodies_read===false,'COUNTS_INVALID');
 return {...m,result,counts,resultPath,resultSha256,countPath,intentSha256,pinsSha256,component};
}
export function compile(context,requestId){
 need(UUID.test(requestId??''),'REQUEST_ID_INVALID');const request=context.library.compileCaptureRequest(context.reference,context.counts,requestId);
 need(exact(request,['method','url','fixture_database','body','kind','request_id','query_sha256','max_response_bytes'])&&
  exact(request.body,['query','read_only'])&&request.method==='POST'&&request.url==='https://api.supabase.com/v1/projects/'+PROJECT+'/database/query'&&
  request.fixture_database===null&&request.kind==='capture'&&request.request_id===requestId&&request.body.read_only===true&&request.max_response_bytes===8*1024*1024&&
  typeof request.body.query==='string'&&Buffer.byteLength(request.body.query)<=2*1024*1024&&
  request.body.query.startsWith('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\n')&&request.body.query.endsWith('\nROLLBACK;')&&
  sha(request.body.query)===request.query_sha256,'REQUEST_INVALID');return request;
}
export async function writeNew(path,bytes){
 const fd=await open(path,FS.O_WRONLY|FS.O_CREAT|FS.O_EXCL|FS.O_NOFOLLOW,0o600);
 try{await fd.writeFile(bytes);await fd.sync();}finally{await fd.close();}
 const d=await open(dirname(path),FS.O_RDONLY);try{await d.sync();}finally{await d.close();}
}
async function makePlanCore({component,resultPath,resultSha256,pinsSha256,outputDirectory,environment=process.env,requestId=randomUUID()}={}){
 need(rootedPath(outputDirectory)&&separated(outputDirectory,ROOT)&&separated(outputDirectory,OTHER)&&separated(outputDirectory,dirname(resultPath)),'OUTPUT_PATH_INVALID');
 const c=await loadContext({component,resultPath,resultSha256,pinsSha256,environment});const request=compile(c,requestId);
 const requestBytes=Buffer.from(JSON.stringify(request,null,2)+'\n');need(requestBytes.length<=4*1024*1024,'REQUEST_INVALID');
 await verifySources(pinsSha256);await c.bundle.privateDirectory(dirname(outputDirectory));await mkdir(outputDirectory,{mode:0o700});await c.bundle.privateDirectory(outputDirectory);
 await writeNew(resolve(outputDirectory,'CAPTURE-REQUEST.json'),requestBytes);
 const plan={format:'collect.managed-component-capture.offline-plan.v1',component,project_ref:PROJECT,source_pins_sha256:pinsSha256,
  preflight_result_path:resultPath,preflight_result_sha256:resultSha256,counts_path:c.countPath,counts_file_sha256:c.result.counts_file_sha256,
  canonical_counts_sha256:c.result.canonical_counts_sha256,preflight_intent_sha256:c.intentSha256,reference_sha256:c.result.reference_sha256,
  preflight_total_rows:c.result.total_rows,request_id:requestId,query_sha256:request.query_sha256,request_file_sha256:sha(requestBytes),
  request_read_only:true,plan_only:true,capture_dispatched:false,restore_dispatched:false,quiescence_proven:false,full_recovery_acceptance:false};
 const planBytes=Buffer.from(JSON.stringify(plan,null,2)+'\n');await writeNew(resolve(outputDirectory,'PLAN.json'),planBytes);
 for(const [name,expected] of [['CAPTURE-REQUEST.json',sha(requestBytes)],['PLAN.json',sha(planBytes)]]){
  const bytes=await c.bundle.readPrivateFile(resolve(outputDirectory,name),4*1024*1024);try{need(sha(bytes)===expected,'OUTPUT_CHANGED');}finally{bytes.fill(0);}}
 return {component,plan_path:resolve(outputDirectory,'PLAN.json'),plan_sha256:sha(planBytes),request_sha256:request.query_sha256,
  request_file_sha256:sha(requestBytes),capture_dispatched:false,restore_dispatched:false};
}
export async function makePlan(options={}){checkRuntimeArguments(process.execArgv);return makePlanCore(options);}
// The test-only entry point is restricted to one private synthetic temp root;
// it can never consume the real count receipts or prepare a live plan.
export async function makePlanSynthetic(options={}){
 const prefix='/private/tmp/collect-component-capture-test-',path=options.resultPath;
 need(rootedPath(path)&&path.startsWith(prefix),'SYNTHETIC_PATH_REQUIRED');const end=path.indexOf('/',prefix.length);
 need(end>prefix.length,'SYNTHETIC_PATH_REQUIRED');const root=path.slice(0,end);
 need(rootedPath(options.outputDirectory)&&options.outputDirectory.startsWith(root+'/'),'SYNTHETIC_PATH_REQUIRED');
 const {privateDirectory}=await import('../current-archive/bundle.mjs');await privateDirectory(root);return makePlanCore(options);
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 try{checkRuntimeArguments(process.execArgv);const args=process.argv.slice(2),values={};need(args.length===10,'ARGUMENTS_INVALID');
  for(let i=0;i<args.length;i+=2){need(['--component','--pins-sha256','--result','--result-sha256','--output-dir'].includes(args[i])&&!Object.hasOwn(values,args[i])&&args[i+1]&&!args[i+1].startsWith('--'),'ARGUMENTS_INVALID');values[args[i]]=args[i+1];}
  const result=await makePlan({component:values['--component'],pinsSha256:values['--pins-sha256'],resultPath:values['--result'],resultSha256:values['--result-sha256'],outputDirectory:values['--output-dir']});process.stdout.write(JSON.stringify(result)+'\n');
 }catch(error){process.stderr.write(JSON.stringify({status:'refused',code:/^[A-Z_]+$/.test(error?.code??'')?error.code:'PLAN_UNCONFIRMED',capture_dispatched:false,restore_dispatched:false})+'\n');process.exitCode=1;}
}
