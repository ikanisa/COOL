// Root-only object-body recovery. Import has no provider or filesystem effect.
import {randomBytes,randomUUID,createCipheriv,createDecipheriv} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {mkdir,open} from 'node:fs/promises';
import {constants} from 'node:fs';
import {resolve,dirname,relative,isAbsolute,sep} from 'node:path';
import {PROJECT,canonical,sha,need,exact} from '../current-archive/codec.mjs';
import {privateDirectory,readPrivateFile} from '../current-archive/bundle.mjs';
import {SupabaseNativeTransport} from '../../../supabase/functions/_shared/storage/supabase-transport.js';
import {validKey} from '../../../supabase/functions/_shared/storage/protocol.js';
import {compileCaptureRequest,assembleCaptureResponse,validateStorageMetadataSnapshot} from './storage.mjs';
export const ORIGIN='https://'+PROJECT+'.supabase.co',BUCKET='collect-evidence';
export const FORMAT='collect.managed-storage.object-bytes.archive.v1';
export const CAPS=Object.freeze({objects:5,objectBytes:1048576,totalBytes:4194304,plaintextBytes:6291456,envelopeBytes:8454144,headerBytes:16384,bucketBytes:16384,requestMs:30000,dispatches:15});
const HASH=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const fail=code=>need(false,code),same=(a,b)=>canonical(a)===canonical(b);
const encode=key=>validKey(key).split('/').map(encodeURIComponent).join('/');

function tableRows(snapshot,name){
 const rel=snapshot.reference.relations.find(t=>t.name===name),table=snapshot.tables.find(t=>t.name===name);
 need(rel&&table,'OBJECT_METADATA_TABLE_REQUIRED');
 const columns=snapshot.reference.columns.filter(c=>c.relation_oid===rel.oid);
 return table.rows.map(r=>{need(r.cells.length===columns.length,'OBJECT_METADATA_WIDTH');return Object.fromEntries(columns.map((c,i)=>[c.name,r.cells[i]]));});
}
export function objectBindings(snapshot){
 const buckets=tableRows(snapshot,'buckets'),objects=tableRows(snapshot,'objects');
 need(buckets.length===1&&buckets[0].id===BUCKET&&buckets[0].name===BUCKET&&buckets[0].public==='f','OBJECT_PRIVATE_BUCKET_SCOPE');
 need(objects.length===CAPS.objects,'OBJECT_EXACT_FIVE_SCOPE');
 let sum=0;const seen=new Set();
 const bindings=objects.map(row=>{
  need(row.bucket_id===BUCKET&&typeof row.id==='string'&&typeof row.name==='string'&&typeof row.version==='string'&&row.version.length>0&&row.version.length<=1024,'OBJECT_BINDING_REQUIRED');
  validKey(row.name);need(!seen.has(row.name),'OBJECT_DUPLICATE_KEY');seen.add(row.name);
  let metadata;try{metadata=JSON.parse(row.metadata);}catch{fail('OBJECT_DECLARED_METADATA_INVALID');}
  need(metadata&&typeof metadata==='object'&&!Array.isArray(metadata)&&Number.isSafeInteger(metadata.size)&&metadata.size>=0&&metadata.size<=CAPS.objectBytes,'OBJECT_DECLARED_SIZE_BOUND');
  sum+=metadata.size;need(sum<=CAPS.totalBytes,'OBJECT_TOTAL_SIZE_BOUND');
  // GET bookkeeping is not content identity. Preserve its value separately.
  const {last_accessed_at,...contentIdentity}=row;
  return {bucket:BUCKET,key:row.name,id:row.id,version:row.version,declaredBytes:metadata.size,metadata:row.metadata,contentIdentity,last_accessed_at:last_accessed_at??null};
 }).sort((a,b)=>a.key<b.key?-1:a.key>b.key?1:0);
 return {bucket:buckets[0],objects:bindings,declaredBytes:sum};
}
function contentMap(bindings){return {bucket:bindings.bucket,objects:bindings.objects.map(({last_accessed_at,...o})=>o),declaredBytes:bindings.declaredBytes};}
async function abortable(promise,signal){
 if(signal.aborted)fail('OBJECT_REQUEST_DEADLINE');let stop;
 const failed=new Promise((_,reject)=>{stop=()=>{try{fail('OBJECT_REQUEST_DEADLINE');}catch(e){reject(e);}};signal.addEventListener('abort',stop,{once:true});});
 try{return await Promise.race([promise,failed]);}finally{signal.removeEventListener('abort',stop);}
}
async function bounded(response,maximum,signal){
 const declared=response.headers.get('content-length');need(declared===null||/^(0|[1-9][0-9]*)$/.test(declared)&&Number(declared)<=maximum,'OBJECT_RESPONSE_BOUND');
 const reader=response.body?.getReader(),chunks=[];let size=0,finished=false;
 try{if(reader)for(;;){const value=await abortable(reader.read(),signal);if(value.done)break;size+=value.value.length;need(size<=maximum,'OBJECT_RESPONSE_BOUND');chunks.push(value.value);}
  need(declared===null||Number(declared)===size,'OBJECT_RESPONSE_LENGTH_CHANGED');finished=true;return Buffer.concat(chunks,size);
 }finally{if(reader){if(!finished)await reader.cancel().catch(()=>{});reader.releaseLock();}}
}
export function readOnlyStorageFetch({bindings,fetchImpl=globalThis.fetch,sample=()=>{},requestMs=CAPS.requestMs}={}){
 need(Number.isInteger(requestMs)&&requestMs>0&&requestMs<=CAPS.requestMs,'OBJECT_REQUEST_DEADLINE_BOUND');
 const allowed=new Set(bindings.objects.map(o=>'/storage/v1/object/authenticated/'+BUCKET+'/'+encode(o.key)));
 const calls=new Map(),heads=new Map();let dispatches=0,totalBytes=0;
 const request=async(input,options={})=>{
  sample();need(typeof input==='string'&&typeof fetchImpl==='function','OBJECT_FETCH_REQUIRED');const u=new URL(input),method=options.method??'GET';
  need(u.origin===ORIGIN&&!u.username&&!u.password&&!u.search&&!u.hash&&options.redirect==='error'&&options.body===undefined,'OBJECT_HTTP_SCOPE');
  const bucket=u.pathname==='/storage/v1/bucket/'+BUCKET;
  need(bucket&&method==='GET'||allowed.has(u.pathname)&&['GET','HEAD'].includes(method),'OBJECT_HTTP_METHOD_OR_PATH');
  const identity=method+' '+u.pathname,count=calls.get(identity)??0;need(count<(bucket?CAPS.objects:1)&&dispatches<CAPS.dispatches,'OBJECT_NO_RETRY_BUDGET');
  calls.set(identity,count+1);dispatches++;
  const ctl=new AbortController(),timer=setTimeout(()=>ctl.abort(),requestMs);
  try{
   const r=await abortable(fetchImpl(input,{...options,signal:ctl.signal,cache:'no-store',credentials:'omit',headers:{...options.headers,'Accept-Encoding':'identity'}}),ctl.signal);
   need(!r.redirected&&(!r.url||r.url===input)&&r.status===200,'OBJECT_PROVIDER_STATUS_OR_REDIRECT');
   need(Buffer.byteLength(canonical(Object.fromEntries(r.headers)))<=CAPS.headerBytes,'OBJECT_RESPONSE_HEADERS_BOUND');
   need(!r.headers.has('content-encoding')||r.headers.get('content-encoding')==='identity','OBJECT_ENCODED_RESPONSE');
   if(method==='HEAD'){
    const n=r.headers.get('content-length');need(n===null||/^(0|[1-9][0-9]*)$/.test(n)&&Number(n)<=CAPS.objectBytes,'OBJECT_RESPONSE_BOUND');
    heads.set(u.pathname,{etag:r.headers.get('etag'),length:n});
    await abortable(r.body?.cancel()??Promise.resolve(),ctl.signal);return new Response(null,{status:200,headers:r.headers});
   }
   const maximum=bucket?CAPS.bucketBytes:Math.min(CAPS.objectBytes,CAPS.totalBytes-totalBytes),bytes=await bounded(r,maximum,ctl.signal);
   if(!bucket){const head=heads.get(u.pathname),etag=r.headers.get('etag');need(head,'OBJECT_HEAD_REQUIRED');need(!head.etag||!etag||head.etag===etag,'OBJECT_HEAD_GET_ETAG_CHANGED');need(head.length===null||Number(head.length)===bytes.length,'OBJECT_HEAD_GET_LENGTH_CHANGED');totalBytes+=bytes.length;}sample();return new Response(bytes,{status:200,headers:r.headers});
  }finally{clearTimeout(timer);}
 };
 return {request,observed:()=>({dispatches,totalBytes,automatic_retry:false,Storage_methods:['GET','HEAD'],Storage_write_requests:0})};
}
function outputPath(path){const checkout=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');need(typeof path==='string'&&isAbsolute(path)&&resolve(path)===path&&separated(path,checkout),'OBJECT_OUTPUT_PATH_INVALID');}
async function fresh(path){outputPath(path);await privateDirectory(dirname(path));await mkdir(path,{mode:0o700});await privateDirectory(path);}
const separated=(a,b)=>{const inside=(x,y)=>{const r=relative(x,y);return r===''||r!=='..'&&!r.startsWith('..'+sep)&&!isAbsolute(r);};return !inside(a,b)&&!inside(b,a);};
async function writeNew(path,bytes){const f=await open(path,constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,0o600);try{await f.writeFile(bytes);await f.sync();}finally{await f.close();}const d=await open(dirname(path),'r');try{await d.sync();}finally{await d.close();}}
export function validatePayload(p){
 exact(p,['format','project_ref','metadata_archive_sha256','metadata_snapshot_sha256','objects','bucket_and_versions_equal_before_after','last_accessed_at_excluded_from_content_identity','atomic_cross_service_snapshot','object_body_semantics','operational_storage_restored','full_recovery_acceptance']);
 need(p.format===FORMAT&&p.project_ref===PROJECT&&HASH.test(p.metadata_archive_sha256)&&HASH.test(p.metadata_snapshot_sha256)&&p.objects.length===CAPS.objects&&p.bucket_and_versions_equal_before_after===true&&p.last_accessed_at_excluded_from_content_identity===true&&p.atomic_cross_service_snapshot===false&&p.object_body_semantics==='opaque_original_bytes_not_application_decrypted'&&p.operational_storage_restored===false&&p.full_recovery_acceptance===false,'OBJECT_PAYLOAD_SCOPE');
 let total=0;const seen=new Set();
 for(const [i,o] of p.objects.entries()){
  exact(o,['ordinal','binding','before_access_time','after_access_time','bytes','sha256','etag','body_base64url']);exact(o.binding,['bucket','key','id','version','declaredBytes','metadata','contentIdentity']);need(o.ordinal===i+1&&o.binding.bucket===BUCKET&&typeof o.binding.key==='string'&&typeof o.binding.id==='string'&&typeof o.binding.version==='string'&&o.binding.version.length>0&&!seen.has(o.binding.key),'OBJECT_PAYLOAD_BINDING');validKey(o.binding.key);seen.add(o.binding.key);
  need(Number.isSafeInteger(o.bytes)&&o.bytes>=0&&o.bytes<=CAPS.objectBytes&&o.binding.declaredBytes===o.bytes&&HASH.test(o.sha256)&&typeof o.body_base64url==='string'&&o.body_base64url.length<=Math.ceil(CAPS.objectBytes*4/3),'OBJECT_PAYLOAD_BODY_BOUND');
  const bytes=Buffer.from(o.body_base64url,'base64url');try{need(bytes.toString('base64url')===o.body_base64url&&bytes.length===o.bytes&&sha(bytes)===o.sha256,'OBJECT_PAYLOAD_BODY_CHANGED');}finally{bytes.fill(0);}total+=o.bytes;
 }
 need(total<=CAPS.totalBytes,'OBJECT_PAYLOAD_TOTAL_BOUND');return p;
}
export function encryptObjects(payload,key,{archiveId=randomUUID(),keyId=randomUUID()}={}){
 validatePayload(payload);need(Buffer.isBuffer(key)&&key.length===32&&UUID.test(archiveId)&&UUID.test(keyId),'OBJECT_CRYPTO_INPUT');const raw=Buffer.from(canonical(payload));need(raw.length>0&&raw.length<=CAPS.plaintextBytes,'OBJECT_PLAINTEXT_BOUND');
 try{const header={format:FORMAT,project_ref:PROJECT,archive_id:archiveId,key_id:keyId,cipher:'AES-256-GCM',plaintext_bytes:raw.length,object_count:CAPS.objects};const iv=randomBytes(12),c=createCipheriv('aes-256-gcm',key,iv,{authTagLength:16});c.setAAD(Buffer.from(canonical(header)));const ciphertext=Buffer.concat([c.update(raw),c.final()]);return Buffer.from(canonical({header,iv:iv.toString('base64url'),tag:c.getAuthTag().toString('base64url'),ciphertext:ciphertext.toString('base64url')}));}finally{raw.fill(0);}
}
export function decryptObjects(bytes,key){
 need(Buffer.isBuffer(bytes)&&bytes.length>0&&bytes.length<=CAPS.envelopeBytes&&Buffer.isBuffer(key)&&key.length===32,'OBJECT_ENVELOPE_BOUND');let raw;
 try{const e=JSON.parse(bytes);exact(e,['header','iv','tag','ciphertext']);const h=e.header;exact(h,['format','project_ref','archive_id','key_id','cipher','plaintext_bytes','object_count']);need(h.format===FORMAT&&h.project_ref===PROJECT&&UUID.test(h.archive_id)&&UUID.test(h.key_id)&&h.cipher==='AES-256-GCM'&&h.object_count===CAPS.objects&&Number.isSafeInteger(h.plaintext_bytes)&&h.plaintext_bytes>0&&h.plaintext_bytes<=CAPS.plaintextBytes,'OBJECT_HEADER_SCOPE');
  const decode=(v,n)=>{need(typeof v==='string'&&/^[A-Za-z0-9_-]*$/.test(v),'OBJECT_ENVELOPE_ENCODING');const b=Buffer.from(v,'base64url');need(b.toString('base64url')===v&&(n===undefined||b.length===n),'OBJECT_ENVELOPE_ENCODING');return b;};
  const iv=decode(e.iv,12),tag=decode(e.tag,16),ct=decode(e.ciphertext,h.plaintext_bytes),d=createDecipheriv('aes-256-gcm',key,iv,{authTagLength:16});d.setAAD(Buffer.from(canonical(h)));d.setAuthTag(tag);raw=Buffer.concat([d.update(ct),d.final()]);const p=JSON.parse(raw);need(canonical(p)===raw.toString('utf8'),'OBJECT_NONCANONICAL_PAYLOAD');return {header:h,payload:validatePayload(p)};
 }catch{fail('OBJECT_ARCHIVE_AUTHENTICATION_FAILED');}finally{raw?.fill(0);}
}
export async function restoreObjectsOffline({archivePath,keyPath,expectedArchiveSha256,restoreDirectory}={}){
 outputPath(restoreDirectory);need(HASH.test(expectedArchiveSha256??'')&&separated(dirname(resolve(archivePath)),dirname(resolve(keyPath))),'OBJECT_ARCHIVE_PIN');const encoded=await readPrivateFile(archivePath,CAPS.envelopeBytes);need(sha(encoded)===expectedArchiveSha256,'OBJECT_ARCHIVE_CHANGED');const key=await readPrivateFile(keyPath,32);let recovered;try{recovered=decryptObjects(encoded,key);}finally{key.fill(0);}
 await fresh(restoreDirectory);const manifest=[];
 for(const o of recovered.payload.objects){const filename=String(o.ordinal).padStart(3,'0')+'.opaque',bytes=Buffer.from(o.body_base64url,'base64url');try{const path=resolve(restoreDirectory,filename);await writeNew(path,bytes);const copy=await readPrivateFile(path,CAPS.objectBytes);try{need(copy.equals(bytes)&&sha(copy)===o.sha256,'OBJECT_OFFLINE_BYTE_PARITY');}finally{copy.fill(0);}manifest.push({ordinal:o.ordinal,file:filename,bytes:o.bytes,sha256:o.sha256});}finally{bytes.fill(0);}}
 const raw=Buffer.from(canonical(manifest));await writeNew(resolve(restoreDirectory,'MANIFEST.json'),raw);
 return {format:'collect.managed-storage.object-bytes.offline-restore.v1',objects:manifest.length,bytes:manifest.reduce((n,o)=>n+o.bytes,0),manifest_sha256:sha(raw),all_bytes_exact:true,anonymous_ordinal_filenames:true,provider_requests:0,operational_storage_restored:false,full_recovery_acceptance:false};
}
export async function captureObjectBytes({metadataSnapshot,metadataArchiveSha256,metadataSnapshotSha256,counts,managementTransport,project,serverKey,archiveDirectory,keyDirectory,restoreDirectory,sample=()=>{},fetchImpl=globalThis.fetch,executeReviewedReadOnly=false}={}){
 need(executeReviewedReadOnly===true&&HASH.test(metadataArchiveSha256??'')&&sha(canonical(metadataSnapshot))===metadataSnapshotSha256,'OBJECT_ROOT_REVIEW_REQUIRED');validateStorageMetadataSnapshot(metadataSnapshot);
 need(typeof serverKey==='string'&&serverKey.length>=32&&serverKey.length<=4096,'OBJECT_SERVER_KEY_REQUIRED');
 const saved=objectBindings(metadataSnapshot);need(saved.declaredBytes===618,'OBJECT_REVIEWED_618_DECLARED_BYTES');
 for(const path of [archiveDirectory,keyDirectory,restoreDirectory])outputPath(path);
 need([archiveDirectory,keyDirectory,restoreDirectory].every(p=>typeof p==='string'&&resolve(p)===p)&&separated(archiveDirectory,keyDirectory)&&separated(archiveDirectory,restoreDirectory)&&separated(keyDirectory,restoreDirectory),'OBJECT_SEPARATE_KEY_CUSTODY');
 await fresh(archiveDirectory);await fresh(keyDirectory);await writeNew(resolve(archiveDirectory,'INTENT.json'),Buffer.from(JSON.stringify({format:FORMAT,metadata_archive_sha256:metadataArchiveSha256,metadata_snapshot_sha256:metadataSnapshotSha256,objects:5,declared_bytes:618,Storage_write_requests:0,read_only_Management_SQL_requests_maximum:2,automatic_retry:false})+'\n'));
 const live=async()=>{sample();const request=compileCaptureRequest(metadataSnapshot.reference,counts,randomUUID());let response;try{response=await managementTransport.query(request);const snapshot=assembleCaptureResponse(response,{reference:metadataSnapshot.reference,counts,request,project});return objectBindings(snapshot);}finally{response?.body?.fill(0);sample();}};
 const downloaded=[];let complete=false;let gate;
 try{
  const before=await live();need(same(contentMap(saved),contentMap(before)),'OBJECT_SAVED_METADATA_DRIFT');
  gate=readOnlyStorageFetch({bindings:before,fetchImpl,sample});const native=new SupabaseNativeTransport({url:ORIGIN,secretKey:serverKey,bucket:BUCKET,fetchImpl:gate.request,timeoutMs:CAPS.requestMs});
  for(const [i,b] of before.objects.entries()){
   sample();const observed=await native.probe(b.key,{maxBytes:CAPS.objectBytes});need(observed.headStatus===200&&observed.getStatus===200&&observed.bucketVerified===true&&observed.bytes instanceof Uint8Array&&observed.bytes.length===b.declaredBytes,'OBJECT_BODY_READ_UNCONFIRMED');
   downloaded.push({ordinal:i+1,binding:b,bytes:Buffer.from(observed.bytes),etag:observed.etag??null});observed.bytes.fill(0);sample();
  }
  const after=await live();need(same(contentMap(before),contentMap(after)),'OBJECT_LIVE_METADATA_DRIFT');
  const payload={format:FORMAT,project_ref:PROJECT,metadata_archive_sha256:metadataArchiveSha256,metadata_snapshot_sha256:metadataSnapshotSha256,objects:downloaded.map((d,i)=>{const {last_accessed_at,...binding}=d.binding;return {ordinal:d.ordinal,binding,before_access_time:last_accessed_at,after_access_time:after.objects[i].last_accessed_at,bytes:d.bytes.length,sha256:sha(d.bytes),etag:d.etag,body_base64url:d.bytes.toString('base64url')};}),bucket_and_versions_equal_before_after:true,last_accessed_at_excluded_from_content_identity:true,atomic_cross_service_snapshot:false,object_body_semantics:'opaque_original_bytes_not_application_decrypted',operational_storage_restored:false,full_recovery_acceptance:false};
  const key=randomBytes(32),archiveId=randomUUID(),keyId=randomUUID(),archivePath=resolve(archiveDirectory,archiveId+'.objects.archive.json'),keyPath=resolve(keyDirectory,keyId+'.key');let encoded;
  try{encoded=encryptObjects(payload,key,{archiveId,keyId});await writeNew(keyPath,key);await writeNew(archivePath,encoded);const bytes=await readPrivateFile(archivePath,CAPS.envelopeBytes),savedKey=await readPrivateFile(keyPath,32);try{need(bytes.equals(encoded)&&same(decryptObjects(bytes,savedKey).payload,payload),'OBJECT_ENCRYPTED_READBACK');}finally{savedKey.fill(0);}}finally{key.fill(0);}
  const restored=await restoreObjectsOffline({archivePath,keyPath,expectedArchiveSha256:sha(encoded),restoreDirectory});sample();
  const receipt={format:'collect.managed-storage.object-bytes.capture-receipt.v1',archive_id:archiveId,key_id:keyId,archive_path:archivePath,key_path:keyPath,archive_bytes:encoded.length,archive_sha256:sha(encoded),payload_sha256:sha(canonical(payload)),metadata_archive_sha256:metadataArchiveSha256,metadata_snapshot_sha256:metadataSnapshotSha256,objects:downloaded.length,downloaded_bytes:downloaded.reduce((n,o)=>n+o.bytes.length,0),authenticated_encrypted_readback:true,bucket_and_versions_equal_before_after:true,atomic_cross_service_snapshot:false,object_body_semantics:payload.object_body_semantics,last_accessed_at_excluded_from_content_identity:true,native_read:gate.observed(),read_only_Management_SQL_requests:2,offline_restore:restored,independent_key_custody:false,operational_storage_restored:false,full_recovery_acceptance:false,automatic_retry:false};
  await writeNew(resolve(archiveDirectory,'RESULT.json'),Buffer.from(JSON.stringify(receipt,null,2)+'\n'));complete=true;return receipt;
 }catch(e){await writeNew(resolve(archiveDirectory,'FAILURE.json'),Buffer.from(JSON.stringify({state:'UNCONFIRMED_PRESERVE_ATTEMPT',code:typeof e?.code==='string'&&/^[A-Z0-9_]+$/.test(e.code)?e.code:'OBJECT_CAPTURE_UNCONFIRMED',native_read:gate?.observed()??null,automatic_retry:false,operational_storage_restored:false,full_recovery_acceptance:false})+'\n'));throw e;}
 finally{for(const d of downloaded)d.bytes.fill(0);if(!complete)sample();}
}
