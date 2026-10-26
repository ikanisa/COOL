// Synthetic definitions only. Root owns actual execution and private TMPDIR.
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {mkdtemp,mkdir,writeFile,readdir,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {objectBindings,readOnlyStorageFetch,validatePayload,encryptObjects,decryptObjects,restoreObjectsOffline,captureObjectBytes,FORMAT,ORIGIN,BUCKET,CAPS} from './objects.mjs';
import {sha,canonical} from '../current-archive/codec.mjs';
import REAL from './REFERENCE.json' with {type:'json'};
import {syntheticSnapshot,syntheticValue} from './native-definition.mjs';
import {sealStorageMetadataTable} from './storage.mjs';
const clone=x=>JSON.parse(JSON.stringify(x));
function snapshot(){
 const bucketColumns=['id','name','public'],objectColumns=['id','bucket_id','name','version','metadata','last_accessed_at'];
 return {reference:{relations:[{name:'buckets',oid:'1'},{name:'objects',oid:'2'}],columns:[...bucketColumns.map(name=>({name,relation_oid:'1'})),...objectColumns.map(name=>({name,relation_oid:'2'}))]},tables:[{name:'buckets',rows:[{cells:[BUCKET,BUCKET,'f']}]},{name:'objects',rows:Array.from({length:5},(_,i)=>({cells:['synthetic-'+i,BUCKET,'recovery/object-'+i,'version-'+i,JSON.stringify({size:2,eTag:'opaque-'+i}),'2026-10-25']}))}]};
}
function payload(){const b=objectBindings(snapshot());return {format:FORMAT,project_ref:'rrlduytparvsjfmegalh',metadata_archive_sha256:'a'.repeat(64),metadata_snapshot_sha256:'b'.repeat(64),objects:b.objects.map((o,i)=>{const {last_accessed_at,...binding}=o,body=Buffer.from('v'+i);return {ordinal:i+1,binding,before_access_time:last_accessed_at,after_access_time:last_accessed_at,bytes:body.length,sha256:sha(body),etag:'opaque-'+i,body_base64url:body.toString('base64url')};}),bucket_and_versions_equal_before_after:true,last_accessed_at_excluded_from_content_identity:true,atomic_cross_service_snapshot:false,object_body_semantics:'opaque_original_bytes_not_application_decrypted',operational_storage_restored:false,full_recovery_acceptance:false};}
const url=i=>ORIGIN+'/storage/v1/object/authenticated/'+BUCKET+'/recovery/object-'+i;
const options=(method='GET')=>({method,redirect:'error'});

test('exact private bucket and five version-bound objects refuse additions, duplicates and missing version',()=>{
 assert.equal(objectBindings(snapshot()).objects.length,5);
 for(const change of [s=>s.tables[0].rows[0].cells[2]='t',s=>s.tables[1].rows.push(s.tables[1].rows[0]),s=>s.tables[1].rows[1].cells[2]=s.tables[1].rows[0].cells[2],s=>s.tables[1].rows[0].cells[3]=null]){const s=snapshot();change(s);assert.throws(()=>objectBindings(s));}
});
test('metadata sizes refuse unsafe, over-object and total budgets before any provider access',()=>{
 for(const size of [-1,1.5,CAPS.objectBytes+1]){const s=snapshot();s.tables[1].rows[0].cells[4]=JSON.stringify({size});assert.throws(()=>objectBindings(s));}
 const s=snapshot();for(const r of s.tables[1].rows)r.cells[4]=JSON.stringify({size:CAPS.objectBytes});assert.throws(()=>objectBindings(s));
});
test('Storage request gate refuses writes, other project and unplanned key before fetch',async()=>{
 let calls=0;const g=readOnlyStorageFetch({bindings:objectBindings(snapshot()),fetchImpl:async()=>{calls++;return new Response('x');}});
 for(const [u,o] of [[url(0),options('POST')],[url(0).replace('rrlduytparvsjfmegalh','otherproject'),options()],[url(9),options()],[url(0),{...options(),body:'private'}]])await assert.rejects(g.request(u,o));assert.equal(calls,0);
});
test('successful HEAD/GET is bounded and repeated body request refuses without dispatch',async()=>{
 let calls=0;const g=readOnlyStorageFetch({bindings:objectBindings(snapshot()),fetchImpl:async(u,o)=>{calls++;return new Response(o.method==='HEAD'?null:'v0',{headers:{'content-length':'2',etag:'opaque'}});}});
 assert.equal((await g.request(url(0),options('HEAD'))).status,200);assert.equal(await(await g.request(url(0),options())).text(),'v0');await assert.rejects(g.request(url(0),options()));assert.equal(calls,2);assert.equal(g.observed().Storage_write_requests,0);
});
test('redirect/error, encoded content and oversized responses fail without accepting bytes',async()=>{
 for(const make of [()=>new Response(null,{status:302,headers:{location:'https://other.example/'}}),()=>new Response('denied',{status:403}),()=>new Response('v0',{headers:{'content-encoding':'gzip'}}),()=>new Response('v0',{headers:{'content-length':String(CAPS.objectBytes+1)}})]){
  const g=readOnlyStorageFetch({bindings:objectBindings(snapshot()),fetchImpl:async()=>make()});await assert.rejects(g.request(url(0),options()));
 }
});
test('HEAD/GET ETag and length contradictions fail independently of payload hashing',async()=>{
 for(const headers of [{etag:'changed','content-length':'2'},{etag:'opaque','content-length':'3'}]){
  const g=readOnlyStorageFetch({bindings:objectBindings(snapshot()),fetchImpl:async(u,o)=>new Response(o.method==='HEAD'?null:'v0',{headers:o.method==='HEAD'?{etag:'opaque','content-length':'2'}:headers})});await g.request(url(0),options('HEAD'));await assert.rejects(g.request(url(0),options()));
 }
});
test('whole body deadline interrupts a reader that produces no terminal data',async()=>{
 const g=readOnlyStorageFetch({bindings:objectBindings(snapshot()),requestMs:25,fetchImpl:async()=>new Response(new ReadableStream({start(){}}))});await assert.rejects(g.request(url(0),options()));
});
test('object payload refuses hash/size drift and cannot promote operational or atomic recovery',()=>{
 assert.equal(validatePayload(payload()).objects.length,5);
 for(const change of [p=>p.objects[0].body_base64url='eHg',p=>p.objects[0].bytes=3,p=>p.atomic_cross_service_snapshot=true,p=>p.full_recovery_acceptance=true,p=>p.objects[1].binding.key=p.objects[0].binding.key]){const p=payload();change(p);assert.throws(()=>validatePayload(p));}
});
test('separate AEAD format authenticates metadata and rejects wrong keys and ciphertext/header tamper',()=>{
 const key=randomBytes(32),wrong=randomBytes(32);try{const p=payload(),bytes=encryptObjects(p,key);assert.deepEqual(decryptObjects(bytes,key).payload,p);assert.throws(()=>decryptObjects(bytes,wrong));for(const f of [e=>e.header.project_ref='otherproject',e=>e.header.format='collect.managed-storage.metadata-inert-snapshot.v1',e=>{const b=Buffer.from(e.ciphertext,'base64url');b[0]^=1;e.ciphertext=b.toString('base64url');}]){const e=JSON.parse(bytes);f(e);assert.throws(()=>decryptObjects(Buffer.from(JSON.stringify(e)),key));}}finally{key.fill(0);wrong.fill(0);}
});
test('offline anonymous ordinal restore proves exact bytes and refuses existing output',async()=>{
 const base=await mkdtemp(join(tmpdir(),'collect-object-bytes-')),archive=join(base,'archive'),keys=join(base,'keys'),restore=join(base,'restore');await mkdir(archive,{mode:0o700});await mkdir(keys,{mode:0o700});const key=randomBytes(32);try{const bytes=encryptObjects(payload(),key),a=join(archive,'objects.archive'),k=join(keys,'key');await writeFile(a,bytes,{mode:0o600,flag:'wx'});await writeFile(k,key,{mode:0o600,flag:'wx'});const r=await restoreObjectsOffline({archivePath:a,keyPath:k,expectedArchiveSha256:sha(bytes),restoreDirectory:restore});assert.equal(r.all_bytes_exact,true);assert.equal(r.objects,5);assert.equal(r.provider_requests,0);assert.deepEqual((await readdir(restore)).sort(),['001.opaque','002.opaque','003.opaque','004.opaque','005.opaque','MANIFEST.json']);for(let i=0;i<5;i++)assert.equal((await readFile(join(restore,String(i+1).padStart(3,'0')+'.opaque'))).toString(),'v'+i);await assert.rejects(restoreObjectsOffline({archivePath:a,keyPath:k,expectedArchiveSha256:sha(bytes),restoreDirectory:restore}));}finally{key.fill(0);}
});

// Use a fully valid synthetic metadata snapshot to reach the capture output gate.
function captureSnapshot(){
 const s=syntheticSnapshot();s.fixture=false;s.reference=REAL;s.reference_sha256=sha(canonical(REAL));s.postgres.database='postgres';
 s.tables=s.tables.map(t=>{
  const relation=REAL.relations.find(r=>r.name===t.name),columns=REAL.columns.filter(c=>c.relation_oid===relation.oid);
  const row=(index,overrides)=>columns.map(c=>Object.hasOwn(overrides,c.name)?overrides[c.name]:syntheticValue(REAL,c,index));
  if(t.name==='buckets')return sealStorageMetadataTable(REAL,t.name,[row(0,{id:BUCKET,name:BUCKET,public:'f'})]);
  if(t.name==='objects')return sealStorageMetadataTable(REAL,t.name,Array.from({length:5},(_,i)=>row(i,{id:'00000000-0000-0000-0000-'+String(i+1).padStart(12,'0'),bucket_id:BUCKET,name:'recovery/object-'+i,version:'version-'+i,metadata:JSON.stringify({size:i===4?610:2})})));
  return t;
 });return s;
}
test('object capture refuses every checkout output before metadata/provider dispatch or directory creation',async()=>{
 const parent=await mkdtemp(join(tmpdir(),'collect-object-checkout-refusal-')),checkout=resolve(dirname(fileURLToPath(import.meta.url)),'../../..'),metadataSnapshot=captureSnapshot();let calls=0;
 const managementTransport={query:async()=>{calls++;throw Error('must not dispatch');}},fetchImpl=async()=>{calls++;throw Error('must not dispatch');};
 for(const role of ['archiveDirectory','keyDirectory','restoreDirectory'])for(const [i,blocked] of [join(checkout,'supabase','synthetic-object-output'),dirname(checkout)].entries()){
  const paths={archiveDirectory:join(parent,'archive-'+role+'-'+i),keyDirectory:join(parent,'key-'+role+'-'+i),restoreDirectory:join(parent,'restore-'+role+'-'+i)};paths[role]=blocked;
  await assert.rejects(captureObjectBytes({metadataSnapshot,metadataArchiveSha256:'a'.repeat(64),metadataSnapshotSha256:sha(canonical(metadataSnapshot)),counts:{},managementTransport,project:{},serverKey:'synthetic-not-a-provider-credential',fetchImpl,...paths,executeReviewedReadOnly:true}),e=>e.code==='OBJECT_OUTPUT_PATH_INVALID');
  assert.equal(calls,0);assert.deepEqual(await readdir(parent),[]);
 }
});
test('offline object restore refuses checkout materialization before opening archive or key',async()=>{
 const checkout=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
 for(const restoreDirectory of [join(checkout,'supabase','synthetic-object-output'),dirname(checkout)])await assert.rejects(restoreObjectsOffline({archivePath:'/missing-synthetic-archive',keyPath:'/missing-synthetic-key',expectedArchiveSha256:'a'.repeat(64),restoreDirectory}),e=>e.code==='OBJECT_OUTPUT_PATH_INVALID');
});
