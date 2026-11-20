// Synthetic-only preparation. Managed capture is deliberately disabled.
// The dormant provider transport needs a separately reviewed launcher.
import {createHash,randomBytes} from 'node:crypto';
import {request as httpsRequest} from 'node:https';
import {constants as FS} from 'node:fs';
import {open} from 'node:fs/promises';
import {dirname,resolve,relative,isAbsolute,sep} from 'node:path';
import {types} from 'node:util';
import {privateDirectory,readPrivateFile} from '../current-archive/bundle.mjs';
import {assertUniqueJson} from '../managed-component-refresh/capture-json.mjs';
import {CaptureError,PROJECT,SLUGS,MAX_BODY,MAX_ARCHIVE,sealFunctionBodies,inspectSealedFunctionBodies,validateMetadata} from './seal.mjs';

const ORG='ghnjnepwvwknswrwzepn',UUID=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/,HASH=/^[a-f0-9]{64}$/;
const fields=['format','scope','operation_id','archive_dir','key_dir','token_path'];
const forbidden=/^(?:NODE_.*|OPENSSL_.*|SSL_.*|SSLKEYLOGFILE|LD_.*|DYLD_.*|(?:HTTP|HTTPS|ALL|NO)_PROXY)$/i;
const sha=x=>createHash('sha256').update(x).digest('hex');
const need=(x,c)=>{if(!x)throw new CaptureError(c);};
function plain(x){return x&&typeof x==='object'&&!Array.isArray(x)&&!types.isProxy(x)&&Object.getPrototypeOf(x)===Object.prototype;}
function value(x,key){const d=Object.getOwnPropertyDescriptor(x,key);need(d&&Object.hasOwn(d,'value'),'PLAN_INVALID');return d.value;}
function contains(a,b){const r=relative(a,b);return r===''||r!=='..'&&!r.startsWith('..'+sep)&&!isAbsolute(r);}
export function canonicalPlan(p){
 need(plain(p)&&Reflect.ownKeys(p).length===fields.length&&Object.keys(p).sort().join('\0')===[...fields].sort().join('\0'),'PLAN_INVALID');
 const v=Object.fromEntries(fields.map(k=>[k,value(p,k)]));
 need(v.format==='collect.edge-capture.plan.v1'&&['synthetic','managed'].includes(v.scope)&&UUID.test(v.operation_id??'')&&
  ['archive_dir','key_dir'].every(k=>typeof v[k]==='string'&&isAbsolute(v[k])&&resolve(v[k])===v[k])&&
  (v.scope==='synthetic'?v.token_path===null:typeof v.token_path==='string'&&isAbsolute(v.token_path)&&resolve(v.token_path)===v.token_path)&&
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

// This transport has no caller-supplied URL, TLS option, agent or callback.
// Metadata/body reads can still observe separate deployment points in time.
function managedTransport(token){
 const base='https://api.supabase.com/v1/projects/'+PROJECT;
 async function get(path,cap,accept){
  return new Promise((resolvePromise,reject)=>{
   let req,res,done=false,total=0,timer,chunks=[];
   const finish=(code,data)=>{if(done)return;done=true;clearTimeout(timer);if(code){res?.destroy();req?.destroy();for(const c of chunks)c.fill(0);chunks=[];reject(new CaptureError(code));}
    else{for(const c of chunks)c.fill(0);chunks=[];resolvePromise(data);}};
   timer=setTimeout(()=>finish('PROVIDER_UNCONFIRMED'),60000);
   try{req=httpsRequest(new URL(base+path),{method:'GET',agent:false,rejectUnauthorized:true,maxHeaderSize:16384,
    headers:{Authorization:'Bearer '+token,Accept:accept}},incoming=>{
     res=incoming;res.on('error',()=>finish('PROVIDER_UNCONFIRMED'));res.on('aborted',()=>finish('PROVIDER_UNCONFIRMED'));
     if(res.statusCode!==200)return finish('PROVIDER_UNCONFIRMED');
     const declared=res.headers['content-length'],encoding=res.headers['content-encoding'];
     if(encoding&&encoding!=='identity'||declared!==undefined&&(!/^[0-9]+$/.test(String(declared))||Number(declared)>cap))return finish('PROVIDER_BOUND');
     res.on('data',b=>{if(done)return;const copy=Buffer.from(b);total+=copy.length;if(total>cap){copy.fill(0);return finish('PROVIDER_BOUND');}chunks.push(copy);});
     res.on('end',()=>{if(declared!==undefined&&total!==Number(declared))return finish('PROVIDER_UNCONFIRMED');const b=Buffer.concat(chunks,total);finish(null,b);});
    });req.on('error',()=>finish('PROVIDER_UNCONFIRMED'));req.end();
   }catch{finish('PROVIDER_UNCONFIRMED');}
  });
 }
 return Object.freeze({async project(){const b=await get('',1024*1024,'application/json');try{return parseJson(b);}finally{b.fill(0);}},
  async metadata(slug){need(SLUGS.includes(slug),'SLUG_INVALID');const b=await get('/functions/'+slug,1024*1024,'application/json');try{return parseJson(b);}finally{b.fill(0);}},
  async body(slug){need(SLUGS.includes(slug),'SLUG_INVALID');return get('/functions/'+slug+'/body',MAX_BODY,'application/octet-stream');}});
}

async function capture({plan,expectedPlanSha256,transport,managed}){
 const encoded=canonicalPlan(plan);need(HASH.test(expectedPlanSha256??'')&&sha(Buffer.from(encoded))===expectedPlanSha256,'PLAN_PIN_MISMATCH');
 plan=JSON.parse(encoded);
 need(plan.scope===(managed?'managed':'synthetic'),'PLAN_INVALID');
 if(managed)need(cleanEnvironment(),'ENVIRONMENT_REFUSED');
 else need(plan.archive_dir.startsWith('/private/tmp/collect-edge-capture-test-')&&plan.key_dir.startsWith('/private/tmp/collect-edge-capture-test-'),'SYNTHETIC_ROOT_REQUIRED');
 await privateDirectory(plan.archive_dir);await privateDirectory(plan.key_dir);
 const claim=resolve(plan.archive_dir,'EDGE-CAPTURE-CLAIM.json'),outcome=resolve(plan.archive_dir,'EDGE-CAPTURE-OUTCOME.json');
 await writeNew(claim,Buffer.from(JSON.stringify({format:'collect.edge-capture.claim.v1',scope:plan.scope,project_ref:PROJECT,operation_id:plan.operation_id,plan_sha256:expectedPlanSha256,automatic_retry:false})+'\n'));await syncDir(plan.archive_dir);
 let key,tokenBytes,token,archive,claimed=true,completed=false,attempted=false;const records=[];
 try{
  key=randomBytes(32);const keyPath=resolve(plan.key_dir,plan.operation_id+'.key');await writeNew(keyPath,key);await syncDir(plan.key_dir);
  if(managed){tokenBytes=await readPrivateFile(plan.token_path,16384);token=new TextDecoder('utf-8',{fatal:true}).decode(tokenBytes).replace(/\r?\n$/,'');
   need(token.length>=16&&token.length<=16384&&!/[\s\x00-\x1f]/.test(token),'TOKEN_INVALID');transport=managedTransport(token);}
  need(transport&&['project','metadata','body'].every(k=>typeof transport[k]==='function'),'TRANSPORT_INVALID');
  attempted=managed;need(projectValid(await transport.project()),'PROJECT_IDENTITY_INVALID');
  for(const slug of SLUGS){
   const beforeRaw=await transport.metadata(slug),before=validateMetadata({...beforeRaw,ezbr_sha256:beforeRaw?.ezbr_sha256??null},slug);
   const body=await transport.body(slug);need(Buffer.isBuffer(body),'BODY_INVALID');records.push({metadata:{...beforeRaw,ezbr_sha256:beforeRaw?.ezbr_sha256??null},body});
   const afterRaw=await transport.metadata(slug),after=validateMetadata({...afterRaw,ezbr_sha256:afterRaw?.ezbr_sha256??null},slug);
   need(JSON.stringify(before)===JSON.stringify(after),'DEPLOYMENT_CHANGED');
  }
  const sealed=sealFunctionBodies({records,operationId:plan.operation_id,scope:plan.scope,planSha256:expectedPlanSha256,key});archive=sealed.archive;
  const archivePath=resolve(plan.archive_dir,plan.operation_id+'.edge.gcm');await writeNew(archivePath,archive);await syncDir(plan.archive_dir);
  const saved=await readPrivateFile(archivePath,MAX_ARCHIVE),savedKey=await readPrivateFile(keyPath,32);
  let checked;try{need(sha(saved)===sha(archive),'ARCHIVE_CHANGED');checked=inspectSealedFunctionBodies({archive:saved,key:savedKey,operationId:plan.operation_id,scope:plan.scope,planSha256:expectedPlanSha256});}
  finally{saved.fill(0);savedKey.fill(0);}
  const receipt={format:'collect.edge-capture.receipt.v1',scope:plan.scope,project_ref:PROJECT,operation_id:plan.operation_id,plan_sha256:expectedPlanSha256,
   archive_sha256:checked.archive_sha256,archive_bytes:archive.length,functions:checked.functions,authenticated_readback:true,
   key_custody_independent:false,provider_settings_included:false,provider_secret_configuration_included:false,
   source_may_contain_sensitive_material:true,source_content_extracted:false,deployability_proven:false,coordinated_snapshot:false};
  await writeNew(resolve(plan.archive_dir,'EDGE-CAPTURE-RESULT.json'),Buffer.from(JSON.stringify(receipt)+'\n'));await syncDir(plan.archive_dir);completed=true;
  return receipt;
 }finally{
  for(const r of records)r.body.fill(0);key?.fill(0);tokenBytes?.fill(0);token=undefined;archive?.fill(0);
  if(claimed){await writeNew(outcome,Buffer.from(JSON.stringify({format:'collect.edge-capture.outcome.v1',scope:plan.scope,operation_id:plan.operation_id,
   plan_sha256:expectedPlanSha256,provider_read_attempted:attempted,outcome:completed?'COMPLETED':'UNCONFIRMED',automatic_retry:false})+'\n'));await syncDir(plan.archive_dir);}
 }
}
// The provider transport remains unreachable until a reviewed successor exists.
export async function captureManaged(){throw new CaptureError('MANAGED_CAPTURE_NOT_ENABLED');}
export async function captureSynthetic(o){need(plain(o)&&Reflect.ownKeys(o).sort().join(',')==='expectedPlanSha256,plan,transport','INPUT_INVALID');
 return capture({plan:value(o,'plan'),expectedPlanSha256:value(o,'expectedPlanSha256'),transport:value(o,'transport'),managed:false});}
