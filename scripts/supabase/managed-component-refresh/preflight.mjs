// Count/catalogue-only Management API preflight. It has no capture or restore
// path; the fixed SQL and parsers come from the separately pinned libraries.
import {createHash,randomUUID} from 'node:crypto';
import {constants as fsConstants} from 'node:fs';
import {lstat,mkdir,open,realpath} from 'node:fs/promises';
import {dirname,isAbsolute,relative,resolve,sep} from 'node:path';
import {pathToFileURL} from 'node:url';

const ROOT=resolve(import.meta.dirname,'../../..');
const OTHER_CHECKOUT='/Volumes/T7/01 Projects/COLLECT';
const PIN_FILE=resolve(import.meta.dirname,'SOURCE-PINS.json');
const NODE='/Volumes/PRO-G40/Development/Node/bin/node';
const TOKEN_ENV='COLLECT_COMPONENT_PREFLIGHT_ACCESS_TOKEN';
const HEX=/^[a-f0-9]{64}$/;
const INPUTS=Object.freeze([
 'scripts/supabase/managed-component-refresh/preflight.mjs',
 'scripts/supabase/managed-component-refresh/preflight.test.mjs',
 'scripts/supabase/managed-component-refresh/README.md',
 'scripts/supabase/current-archive/bundle.mjs',
 'scripts/supabase/current-archive/codec.mjs',
 'scripts/supabase/current-archive/transport.mjs',
 'scripts/supabase/managed-auth-archive/REFERENCE.json',
 'scripts/supabase/managed-auth-archive/counts.mjs',
 'scripts/supabase/managed-storage-archive-v2/REFERENCE.json',
 'scripts/supabase/managed-storage-archive-v2/counts.mjs',
]);
const PUBLIC_ERRORS=new Set([
 'ARGUMENTS_INVALID','COMPONENT_INVALID','NODE_RUNTIME_INVALID','UNSAFE_ENVIRONMENT',
 'SOURCE_ROOT_INVALID','SOURCE_PIN_REQUIRED','SOURCE_PIN_CHANGED','OUTPUT_PATH_INVALID',
 'PRIVATE_DIRECTORY_REQUIRED','TOKEN_INVALID','PROJECT_IDENTITY_INVALID','COUNT_SCOPE_INVALID',
 'JSON_INVALID','JSON_DUPLICATE_KEY','JSON_DEPTH_EXCEEDED','COUNTS_RESPONSE_BOUND',
 'HTTP_STATUS_REFUSED','REDIRECT_REFUSED','TRANSPORT_TIMEOUT','TRANSPORT_UNCONFIRMED',
 'RESPONSE_BOUND','RESPONSE_LENGTH_CHANGED','AUTH_CATALOGUE_CHANGED','STORAGE_CATALOGUE_CHANGED',
]);
class Refused extends Error{constructor(code){super(code);this.code=code;}}
const need=(condition,code)=>{if(!condition)throw new Refused(code);};
const sha=value=>createHash('sha256').update(value).digest('hex');
const exact=(x,keys)=>x!==null&&typeof x==='object'&&!Array.isArray(x)&&
 Object.getPrototypeOf(x)===Object.prototype&&Object.keys(x).sort().join('\0')===[...keys].sort().join('\0');
const within=(path,root)=>{const r=relative(root,path);return r===''||r!=='..'&&!r.startsWith('..'+sep)&&!isAbsolute(r);};
const separated=(a,b)=>!within(a,b)&&!within(b,a);

function cleanEnvironment(env){
 for(const [key,value] of Object.entries(env))if(value&&(
  /^(?:https?|all|no)_proxy$/i.test(key)||/^(?:DYLD_|LD_PRELOAD$)/i.test(key)||
  ['GLOBAL_AGENT_HTTP_PROXY','NODE_OPTIONS','NODE_PATH','NODE_USE_ENV_PROXY','NODE_EXTRA_CA_CERTS',
   'NODE_TLS_REJECT_UNAUTHORIZED','SSL_CERT_FILE','SSL_CERT_DIR','OPENSSL_CONF'].includes(key)))
  throw new Refused('UNSAFE_ENVIRONMENT');
}

// Reject duplicate decoded JSON keys, including escape-equivalent keys. The
// existing count parser validates semantics after this bounded structural pass.
export function uniqueJson(text){
 need(typeof text==='string'&&Buffer.byteLength(text)<=131072,'JSON_INVALID');let at=0;
 const ws=()=>{while(at<text.length&&/[\x20\x09\x0a\x0d]/.test(text[at]))at++;};
 function str(){
  need(text[at]==='"','JSON_INVALID');const start=at++;let escaped=false;
  while(at<text.length){const c=text[at++];if(escaped){escaped=false;continue;}if(c==='\\'){escaped=true;continue;}
   if(c==='"'){try{return JSON.parse(text.slice(start,at));}catch{throw new Refused('JSON_INVALID');}}}
  throw new Refused('JSON_INVALID');
 }
 function value(depth){
  need(depth<=64,'JSON_DEPTH_EXCEEDED');ws();const c=text[at];
  if(c==='"'){str();return;}
  if(c==='{'){
   at++;ws();const keys=new Set();if(text[at]==='}'){at++;return;}
   for(;;){ws();const key=str();need(!keys.has(key),'JSON_DUPLICATE_KEY');keys.add(key);ws();need(text[at++]===':','JSON_INVALID');value(depth+1);ws();
    const end=text[at++];if(end==='}')return;need(end===',','JSON_INVALID');}
  }
  if(c==='['){at++;ws();if(text[at]===']'){at++;return;}for(;;){value(depth+1);ws();const end=text[at++];if(end===']')return;need(end===',','JSON_INVALID');}}
  const start=at;while(at<text.length&&!/[\x20\x09\x0a\x0d,\]}]/.test(text[at]))at++;
  need(at>start,'JSON_INVALID');try{JSON.parse(text.slice(start,at));}catch{throw new Refused('JSON_INVALID');}
 }
 value(0);ws();need(at===text.length,'JSON_INVALID');
}

async function stableBytes(path,maximum){
 need(isAbsolute(path)&&resolve(path)===path&&await realpath(path)===path,'SOURCE_PIN_CHANGED');
 const before=await lstat(path);need(before.isFile()&&!before.isSymbolicLink()&&before.size>=0&&before.size<=maximum,'SOURCE_PIN_CHANGED');
 const fd=await open(path,fsConstants.O_RDONLY|fsConstants.O_NOFOLLOW|fsConstants.O_NONBLOCK);let bytes;
 try{
  const first=await fd.stat();const identity=s=>[s.dev,s.ino,s.size,s.mtimeMs,s.ctimeMs,s.nlink].join(':');
  need(identity(before)===identity(first),'SOURCE_PIN_CHANGED');bytes=Buffer.alloc(first.size);let pos=0;
  while(pos<bytes.length){const x=await fd.read(bytes,pos,bytes.length-pos,pos);if(!x.bytesRead)break;pos+=x.bytesRead;}
  const probe=Buffer.alloc(1),extra=await fd.read(probe,0,1,first.size);probe.fill(0);
  const after=await fd.stat(),last=await lstat(path);
  need(pos===bytes.length&&extra.bytesRead===0&&identity(first)===identity(after)&&identity(first)===identity(last),'SOURCE_PIN_CHANGED');return bytes;
 }catch(error){bytes?.fill(0);throw error;}finally{await fd.close();}
}
async function stableHash(path,maximum){
 need(isAbsolute(path)&&resolve(path)===path&&await realpath(path)===path,'SOURCE_PIN_CHANGED');
 const before=await lstat(path);need(before.isFile()&&!before.isSymbolicLink()&&before.size>=0&&before.size<=maximum,'SOURCE_PIN_CHANGED');
 const fd=await open(path,fsConstants.O_RDONLY|fsConstants.O_NOFOLLOW|fsConstants.O_NONBLOCK),buffer=Buffer.alloc(1024*1024),hash=createHash('sha256');
 try{
  const first=await fd.stat(),identity=s=>[s.dev,s.ino,s.size,s.mtimeMs,s.ctimeMs,s.nlink].join(':');
  need(identity(before)===identity(first),'SOURCE_PIN_CHANGED');let pos=0;
  while(pos<first.size){const x=await fd.read(buffer,0,Math.min(buffer.length,first.size-pos),pos);if(!x.bytesRead)break;hash.update(buffer.subarray(0,x.bytesRead));pos+=x.bytesRead;}
  const extra=await fd.read(buffer,0,1,first.size),after=await fd.stat(),last=await lstat(path);
  need(pos===first.size&&extra.bytesRead===0&&identity(first)===identity(after)&&identity(first)===identity(last),'SOURCE_PIN_CHANGED');return hash.digest('hex');
 }finally{buffer.fill(0);await fd.close();}
}
async function verifySources(expectedPin){
 need(HEX.test(expectedPin??''),'SOURCE_PIN_REQUIRED');need(await realpath(ROOT)===ROOT,'SOURCE_ROOT_INVALID');
 const raw=await stableBytes(PIN_FILE,65536);need(sha(raw)===expectedPin,'SOURCE_PIN_CHANGED');
 let pins;try{const text=raw.toString('utf8');uniqueJson(text);pins=JSON.parse(text);}catch(e){if(e instanceof Refused)throw e;throw new Refused('SOURCE_PIN_CHANGED');}
 need(exact(pins,['format','files','node'])&&pins.format==='collect.managed-component-preflight.sources.v1'&&
  exact(pins.files,INPUTS)&&exact(pins.node,['path','sha256'])&&pins.node.path===NODE&&HEX.test(pins.node.sha256??''),'SOURCE_PIN_CHANGED');
 for(const path of INPUTS){need(HEX.test(pins.files[path]??''),'SOURCE_PIN_CHANGED');need(await stableHash(resolve(ROOT,path),16*1024*1024)===pins.files[path],'SOURCE_PIN_CHANGED');}
 need(process.version==='v24.19.0'&&process.execPath===NODE,'NODE_RUNTIME_INVALID');
 need(await stableHash(NODE,256*1024*1024)===pins.node.sha256,'NODE_RUNTIME_INVALID');
 return pins;
}
async function modules(component){
 const prefix=component==='auth'?'managed-auth-archive':'managed-storage-archive-v2';
 const [counts,codec,transport,bundle]=await Promise.all([
  import(pathToFileURL(resolve(ROOT,'scripts/supabase',prefix,'counts.mjs')).href),
  import(pathToFileURL(resolve(ROOT,'scripts/supabase/current-archive/codec.mjs')).href),
  import(pathToFileURL(resolve(ROOT,'scripts/supabase/current-archive/transport.mjs')).href),
  import(pathToFileURL(resolve(ROOT,'scripts/supabase/current-archive/bundle.mjs')).href),
 ]);
 const bytes=await stableBytes(resolve(ROOT,'scripts/supabase',prefix,'REFERENCE.json'),131072);
 let reference;try{const text=bytes.toString('utf8');uniqueJson(text);reference=JSON.parse(text);}catch(e){if(e instanceof Refused)throw e;throw new Refused('SOURCE_PIN_CHANGED');}
 counts.validateReference(reference);return {counts,codec,transport,bundle,reference};
}
async function writeNew(path,value){
 const bytes=Buffer.from(JSON.stringify(value,null,2)+'\n');const fd=await open(path,fsConstants.O_WRONLY|fsConstants.O_CREAT|fsConstants.O_EXCL|fsConstants.O_NOFOLLOW,0o600);
 try{await fd.writeFile(bytes);await fd.sync();}finally{await fd.close();}
 const parent=await open(dirname(path),'r');try{await parent.sync();}finally{await parent.close();}return bytes;
}
function options(argv){
 need(argv.length===8,'ARGUMENTS_INVALID');const v={};
 for(let i=0;i<argv.length;i+=2){need(['--component','--pins-sha256','--output-dir','--token-env'].includes(argv[i])&&!Object.hasOwn(v,argv[i])&&typeof argv[i+1]==='string'&&!argv[i+1].startsWith('--'),'ARGUMENTS_INVALID');v[argv[i]]=argv[i+1];}
 need(Object.keys(v).length===4&&v['--token-env']===TOKEN_ENV,'ARGUMENTS_INVALID');return v;
}

// transportFactory exists for offline synthetic tests. The CLI never accepts a
// transport, SQL, token value, source-root override, capture or restore option.
export async function runPreflight({component,pinsSha256,outputDirectory,environment=process.env,transportFactory,requestId=randomUUID()}={}){
 need(['auth','storage'].includes(component),'COMPONENT_INVALID');cleanEnvironment(environment);
 need(typeof outputDirectory==='string'&&isAbsolute(outputDirectory)&&resolve(outputDirectory)===outputDirectory&&
  separated(outputDirectory,ROOT)&&separated(outputDirectory,OTHER_CHECKOUT),'OUTPUT_PATH_INVALID');
 let out,response,token;
 try{
  await verifySources(pinsSha256);const m=await modules(component);const request=m.counts.compileCountsRequest(m.reference,requestId);
  need(request.kind==='metadata'&&request.fixture_database===null&&request.body.read_only===true&&
   request.body.query.startsWith('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\n')&&request.body.query.endsWith('\nROLLBACK;')&&
   sha(request.body.query)===request.query_sha256,'COUNT_SCOPE_INVALID');
  await m.bundle.privateDirectory(dirname(outputDirectory));await mkdir(outputDirectory,{mode:0o700});out=outputDirectory;await m.bundle.privateDirectory(out);
  await writeNew(resolve(out,'INTENT.json'),{format:'collect.managed-component-preflight.intent.v1',component,
   project_ref:'rrlduytparvsjfmegalh',request_id:requestId,query_sha256:request.query_sha256,
   source_pins_sha256:pinsSha256,reference_sha256:m.counts.REFERENCE_SHA256,
   read_only:true,metadata_only:true,capture_dispatched:false,automatic_retry:false});
  token=environment[TOKEN_ENV];delete environment[TOKEN_ENV];
  need(typeof token==='string'&&token.length>=16&&token.length<=16384&&!/[\s\x00-\x1f]/.test(token),'TOKEN_INVALID');
  const transport=(transportFactory??(x=>m.transport.createManagementTransport(x)))({token,environment});token=null;
  const project=await transport.readProject();m.counts.identity(project);
  response=await transport.query(request);
  need(Buffer.isBuffer(response?.body)&&response.body.length>0&&response.body.length<=131072,'COUNTS_RESPONSE_BOUND');
  let outer;try{const text=new TextDecoder('utf-8',{fatal:true}).decode(response.body);uniqueJson(text);outer=JSON.parse(text);
   need(Array.isArray(outer)&&outer.length===1&&typeof outer[0]?.payload==='string','JSON_INVALID');uniqueJson(outer[0].payload);
   const payload=JSON.parse(outer[0].payload);
   need(exact(payload?.identity,['database','server_version_num','read_only','isolation','row_security','application_name',
    'server_encoding','client_encoding','timezone','backend_pid','snapshot','observed_at']),'COUNT_SCOPE_INVALID');
  }catch(error){if(error instanceof Refused)throw error;throw new Refused('JSON_INVALID');}
  const counts=m.counts.parseCountsResponse(response,{reference:m.reference,request,project});
  need(counts.metadata_only_preflight===true&&counts.capture_dispatched===false&&counts.full_recovery_acceptance===false,'COUNT_SCOPE_INVALID');
  await verifySources(pinsSha256);await m.bundle.privateDirectory(out);
  const countsBytes=await writeNew(resolve(out,'COUNTS.json'),counts);
  const checked=await m.bundle.readPrivateFile(resolve(out,'COUNTS.json'),131072);need(checked.equals(countsBytes),'SOURCE_PIN_CHANGED');checked.fill(0);
  const result={format:'collect.managed-component-preflight.result.v1',component,project_ref:project.project_ref,
   request_id:requestId,query_sha256:request.query_sha256,source_pins_sha256:pinsSha256,reference_sha256:m.counts.REFERENCE_SHA256,
   counts_file_sha256:sha(countsBytes),canonical_counts_sha256:m.codec.sha(m.codec.canonical(counts)),state:counts.state,total_rows:counts.total_rows,
   metadata_only:true,real_data_capture:false,automatic_retry:false,native_rollback_command_complete_observed:false,full_recovery_acceptance:false};
  const resultBytes=await writeNew(resolve(out,'RESULT.json'),result);
  const readback=await m.bundle.readPrivateFile(resolve(out,'RESULT.json'),131072);need(readback.equals(resultBytes),'SOURCE_PIN_CHANGED');readback.fill(0);
  return {status:'observed',component,result_path:resolve(out,'RESULT.json'),result_sha256:sha(resultBytes),
   counts_path:resolve(out,'COUNTS.json'),counts_file_sha256:result.counts_file_sha256,canonical_counts_sha256:result.canonical_counts_sha256,
   state:result.state,total_rows:result.total_rows,metadata_only:true,real_data_capture:false,full_recovery_acceptance:false};
 }catch(error){
  if(out){try{await writeNew(resolve(out,'FAILED.json'),{format:'collect.managed-component-preflight.failure.v1',component,
   code:PUBLIC_ERRORS.has(error?.code)?error.code:'PREFLIGHT_UNCONFIRMED',metadata_only:true,real_data_capture:false,automatic_retry:false,preserve_partial:true});}catch{}}
  throw error;
 }finally{token=null;delete environment[TOKEN_ENV];if(Buffer.isBuffer(response?.body))response.body.fill(0);}
}

if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 try{const v=options(process.argv.slice(2));const result=await runPreflight({component:v['--component'],pinsSha256:v['--pins-sha256'],outputDirectory:v['--output-dir']});
  process.stdout.write(JSON.stringify(result)+'\n');}
 catch(error){const code=PUBLIC_ERRORS.has(error?.code)?error.code:'PREFLIGHT_UNCONFIRMED';
  process.stderr.write(JSON.stringify({status:'refused_or_unconfirmed',code,metadata_only:true,real_data_capture:false,automatic_retry:false})+'\n');process.exitCode=1;}
}
