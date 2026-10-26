// Synthetic definitions only; Root owns all runtime, network denial and private TMPDIR.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readdir,readFile,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import REAL from './REFERENCE.json' with {type:'json'};
import {CAPS,FORMAT,SCOPE,validateStorageMetadataCell,sealStorageMetadataTable,validateStorageMetadataSnapshot,compileCaptureRequest,compileFixtureCaptureRequest,assembleCaptureResponse,encryptStorageMetadataSnapshot,decryptStorageMetadataSnapshot,captureStorageMetadata,writeStorageMetadataBundle,restoreStorageMetadataInert} from './storage.mjs';
import {syntheticSnapshot,syntheticValue,SYNTHETIC_PROJECT} from './native-definition.mjs';
import {canonical,sha} from '../current-archive/codec.mjs';
import {decryptSnapshot as legacyDecrypt} from '../current-archive/bundle.mjs';
import {createManagementTransport} from '../current-archive/transport.mjs';
import {decryptAuthSnapshot} from '../managed-auth-archive/auth.mjs';
const clone=x=>JSON.parse(JSON.stringify(x));
const project=SYNTHETIC_PROJECT,requestId='1ce5ab4a-3238-443b-97fc-d0c16e15f5b0';
const proof=(r,fixture=false)=>({format:fixture?'collect.managed-storage.metadata.synthetic-counts.v1':'collect.managed-storage.counts.parsed.v1',...(fixture?{fixture:true}:{}),project_ref:project.project_ref,reference_sha256:sha(canonical(r)),within_row_caps:true,storage_identifiers_returned:false,metadata_bodies_returned:false,version_values_returned:false,object_bodies_read:false,capture_dispatched:false,total_rows:'0',tables:r.relations.map(t=>({schema:'storage',name:t.name,rows:'0',rows_at_least:'0',exact:true})),metadata_only_preflight:true,storage_quiescence_proven:false,query_sha256:'a'.repeat(64),response_sha256:'b'.repeat(64)});
function responseFixture(){
 const counts=proof(REAL),request=compileCaptureRequest(REAL,counts,requestId),s=syntheticSnapshot();s.fixture=false;s.reference=REAL;s.reference_sha256=sha(canonical(REAL));s.postgres.database='postgres';s.postgres.application_name='collect.storagemeta.'+requestId.replaceAll('-','');s.counts_preflight_sha256=sha(canonical(counts));
 const target=REAL.relations.find(t=>t.name==='objects'),columns=REAL.columns.filter(c=>c.relation_oid===target.oid),cells=columns.map(c=>syntheticValue(REAL,c,0));s.tables=s.tables.map(t=>t.name==='objects'?sealStorageMetadataTable(REAL,'objects',[cells]):t);
 const payload={format:'collect.managed-storage.metadata.capture-response.v1',request_id:requestId,reference_sha256:sha(canonical(REAL)),counts_preflight_sha256:sha(canonical(counts)),postgres:s.postgres,tables:s.tables.map((t,index)=>{const cells=t.rows.map(r=>r.cells);let bytes=0,max=0;for(const row of cells)for(const value of row)if(value!==null){const n=Buffer.byteLength(value);bytes+=n;max=Math.max(max,n);}return {schema:'storage',name:t.name,measure:{index,rows:String(cells.length),bytes:String(bytes),max_cell:String(max)},cells};})};
 return {counts,request,reference:REAL,project,payload};
}
const wire=f=>({status:201,body:Buffer.from(JSON.stringify([{kind:f.payload.format,payload:JSON.stringify(f.payload)}]))});

test('Storage metadata has separate scope and cannot declare bodies sequences or operational authority',()=>{
 const s=syntheticSnapshot();assert.equal(validateStorageMetadataSnapshot(s,{allowFixture:true}),s);assert.equal(s.object_bodies_included,false);assert.equal(Object.hasOwn(s,'sequence'),false);assert.throws(()=>validateStorageMetadataSnapshot(s));for(const key of ['object_bodies_included','operational_storage_restored','production_restore_authority','full_recovery_acceptance']){const changed=clone(s);changed[key]=true;assert.throws(()=>validateStorageMetadataSnapshot(changed,{allowFixture:true}));}const changed=clone(s);changed.scope='managed-auth-inert-recovery-data-only';assert.throws(()=>validateStorageMetadataSnapshot(changed,{allowFixture:true}));
});
test('all eleven observed types including uppercase enum and text arrays accept finite synthetic cells',()=>{
 for(const c of REAL.columns)for(let i=0;i<8;i++)assert.equal(validateStorageMetadataCell(syntheticValue(REAL,c,i),REAL,c),syntheticValue(REAL,c,i));const c=REAL.columns.find(c=>c.type_oid==='1009');for(const value of ['{}','[0:1]={a,b}','{{a,b},{c,d}}','{NULL,"NULL",""}'])assert.equal(validateStorageMetadataCell(value,REAL,c),value);const en=REAL.columns.find(c=>REAL.types.find(t=>t.oid===c.type_oid).kind==='e');for(const label of ['STANDARD','ANALYTICS','VECTOR'])assert.equal(validateStorageMetadataCell(label,REAL,en),label);assert.throws(()=>validateStorageMetadataCell('not_observed',REAL,en));
});
test('unknown type or catalogue drift is refused rather than projected as another scalar',()=>{
 const r=clone(REAL);r.columns[0].type_oid='999999';assert.throws(()=>compileCaptureRequest(r,proof(r),requestId));const en=clone(REAL);en.types.find(t=>t.kind==='e').enum_labels.push({label:'UNREVIEWED',sort_order:'4'});assert.throws(()=>compileCaptureRequest(en,proof(en),requestId));
});
test('mandatory NULL row width cell and digest bounds fail without echoing sensitive synthetic text',()=>{
 const c=REAL.columns.find(c=>c.not_null&&c.type_oid==='25');assert.throws(()=>validateStorageMetadataCell(null,REAL,c),e=>e.code==='STORAGE_METADATA_NULL_NOT_ALLOWED');assert.throws(()=>validateStorageMetadataCell('x'.repeat(CAPS.cellBytes+1),REAL,c),e=>e.code==='STORAGE_METADATA_CELL_BOUND'&&!e.message.includes('xxxx'));assert.throws(()=>sealStorageMetadataTable(REAL,'objects',[['wrong width']]));const s=syntheticSnapshot();s.tables[0].sha256='0'.repeat(64);assert.throws(()=>validateStorageMetadataSnapshot(s,{allowFixture:true}));const missing=syntheticSnapshot();missing.tables.pop();assert.throws(()=>validateStorageMetadataSnapshot(missing,{allowFixture:true}));
});
test('AESGCM binds Storage metadata AAD and rejects Auth legacy readers wrong key and tamper',()=>{
 const s=syntheticSnapshot(),key=Buffer.alloc(32,7),wrong=Buffer.alloc(32,8);try{const bytes=encryptStorageMetadataSnapshot(s,key,{allowFixture:true});assert.equal(canonical(decryptStorageMetadataSnapshot(bytes,key,{allowFixture:true}).snapshot),canonical(s));assert.throws(()=>decryptStorageMetadataSnapshot(bytes,wrong,{allowFixture:true}));assert.throws(()=>decryptStorageMetadataSnapshot(bytes,key));assert.throws(()=>decryptAuthSnapshot(bytes,key,{allowFixture:true}));assert.throws(()=>legacyDecrypt(bytes,key));const x=JSON.parse(bytes);x.header.archive_id='2d51745d-88bd-465e-a523-a8c74177cf89';assert.throws(()=>decryptStorageMetadataSnapshot(Buffer.from(canonical(x)),key,{allowFixture:true}));}finally{key.fill(0);wrong.fill(0);}
});
test('sameRR capture guards all eight measure scans and budget before native cells without sequences',()=>{
 const q=compileCaptureRequest(REAL,proof(REAL),requestId).body.query;assert.ok(q.startsWith('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;'));assert.ok(q.endsWith('ROLLBACK;'));assert.equal((q.match(/WHERE \(SELECT valid FROM approved\) IS TRUE/g)||[]).length,8);assert.ok(q.includes('CASE WHEN (SELECT valid FROM storage_budget) IS TRUE THEN'));for(const word of ['last_value','is_called','pg_sequence','collect_fence_control'])assert.equal(q.includes(word),false);for(const field of ['DateStyle','bytea_output','extra_float_digits','IntervalStyle','standard_conforming_strings'])assert.ok(q.includes("current_setting('"+field+"')"));
});
test('production request needs exact reviewed Storage count proof rather than old Auth counts or estimates',()=>{
 for(const change of [c=>{c.format='collect.managed-auth.counts.parsed.v1';},c=>{c.tables[0].exact=false;},c=>{c.tables[0].rows=null;},c=>{c.query_sha256=null;},c=>{c.total_rows='1';}]){const counts=proof(REAL);change(counts);assert.throws(()=>compileCaptureRequest(REAL,counts,requestId));}assert.throws(()=>compileCaptureRequest(REAL,proof(REAL,true),requestId));
});
test('capture measures its own metadata rows and materialized generated array instead of prior count identity',()=>{
 const f=responseFixture(),s=assembleCaptureResponse(wire(f),f);assert.equal(f.counts.total_rows,'0');assert.equal(s.tables.reduce((n,t)=>n+t.row_count,0),1);const table=s.tables.find(t=>t.name==='objects'),source=REAL.relations.find(t=>t.name==='objects'),columns=REAL.columns.filter(c=>c.relation_oid===source.oid),i=columns.findIndex(c=>c.name==='path_tokens');assert.equal(columns[i].generated,'s');assert.equal(table.rows[0].cells[i],'{}');assert.equal(s.storage_quiescence_proven,false);assert.equal(s.object_bodies_included,false);
});
test('wrong native settings request identity row measures and refused payload fail closed',()=>{
 const f=responseFixture();f.payload.postgres.date_style='SQL, DMY';assert.throws(()=>assembleCaptureResponse(wire(f),f),e=>e.code==='STORAGE_METADATA_CAPTURE_CONTEXT_INVALID');const g=responseFixture();g.payload.tables[0].measure.bytes='1';assert.throws(()=>assembleCaptureResponse(wire(g),g));const h=responseFixture();h.payload.request_id='0'.repeat(36);assert.throws(()=>assembleCaptureResponse(wire(h),h));const z=responseFixture();assert.throws(()=>assembleCaptureResponse({status:201,body:Buffer.from('[{"kind":"collect.managed-storage.metadata.capture-response.v1","payload":"{\\"refused\\":\\"BUDGET\\"}"}]')},z));
});
test('fixture SQL cannot dispatch through hosted transport and unreviewed capture creates no output',async()=>{
 const s=syntheticSnapshot(),request=compileFixtureCaptureRequest(s.reference,proof(s.reference,true),requestId,s.postgres.database);let calls=0;const transport=createManagementTransport({token:'synthetic-no-provider-credential',environment:{},requestImpl(){calls++;throw Error('must not dispatch');}});await assert.rejects(transport.query(request),e=>e.code==='COMPILED_REQUEST_INVALID');assert.equal(calls,0);await assert.rejects(captureStorageMetadata({transport:{readProject:async()=>{calls++;},query:async()=>{calls++;}},reference:REAL,counts:proof(REAL),expectedCountsSha256:'0'.repeat(64),requestId,archiveDirectory:'/not-used-storage',keyDirectory:'/not-used-key',executeReviewedReadOnly:true}),e=>e.code==='STORAGE_METADATA_CAPTURE_REVIEW_REQUIRED');assert.equal(calls,0);
});
test('failed simulated response is wiped while only safe intent is persisted in private temporary custody',async()=>{
 const parent=await mkdtemp(join(tmpdir(),'collect-storage-metadata-synthetic-')),archiveDirectory=join(parent,'archive'),keyDirectory=join(parent,'key'),counts=proof(REAL),body=Buffer.from('SYNTHETIC_METADATA_NEVER_PERSIST');let calls=0;const transport={readProject:async()=>project,query:async()=>{calls++;return {status:201,body};}};await assert.rejects(captureStorageMetadata({transport,reference:REAL,counts,expectedCountsSha256:sha(canonical(counts)),requestId,archiveDirectory,keyDirectory,executeReviewedReadOnly:true}));assert.equal(calls,1);assert.ok(body.every(b=>b===0));assert.deepEqual(await readdir(archiveDirectory),['INTENT.json']);assert.deepEqual(await readdir(keyDirectory),[]);assert.equal((await readFile(join(archiveDirectory,'INTENT.json'),'utf8')).includes('SYNTHETIC_METADATA'),false);assert.equal((await stat(join(archiveDirectory,'INTENT.json'))).mode&0o777,0o600);
});
test('remote inert target refuses before constructing any native client or activating Storage',async()=>{
 let calls=0;await assert.rejects(restoreStorageMetadataInert(syntheticSnapshot(),{adminUrl:'postgres://postgres:synthetic@remote.invalid/postgres',makeClient(){calls++;},allowFixture:true}));assert.equal(calls,0);await assert.rejects(restoreStorageMetadataInert(syntheticSnapshot(),{adminUrl:'postgres://postgres:synthetic@127.0.0.1/postgres',allowFixture:true}));
});

// Portability guards: every output is checked before any filesystem or transport effect.
test('metadata capture refuses archive/key checkout descendants and ancestors before any creation or transport',async()=>{
 const parent=await mkdtemp(join(tmpdir(),'collect-storage-checkout-refusal-')),checkout=resolve(dirname(fileURLToPath(import.meta.url)),'../../..'),counts=proof(REAL);let calls=0;
 const transport={readProject:async()=>{calls++;throw Error('must not dispatch');},query:async()=>{calls++;throw Error('must not dispatch');}};
 for(const [i,blocked] of [join(checkout,'supabase','synthetic-storage-output'),dirname(checkout)].entries())for(const role of ['archiveDirectory','keyDirectory']){
  const paths={archiveDirectory:join(parent,'archive-'+i+'-'+role),keyDirectory:join(parent,'key-'+i+'-'+role)};paths[role]=blocked;
  await assert.rejects(captureStorageMetadata({transport,reference:REAL,counts,expectedCountsSha256:sha(canonical(counts)),requestId,...paths,executeReviewedReadOnly:true}),e=>e.code==='STORAGE_METADATA_OUTPUT_PATH_INVALID');
  assert.deepEqual(await readdir(parent),[]);assert.equal(calls,0);
 }
});
test('direct metadata bundle writer refuses either checkout output before directory access or key generation',async()=>{
 const parent=await mkdtemp(join(tmpdir(),'collect-storage-writer-refusal-')),checkout=resolve(dirname(fileURLToPath(import.meta.url)),'../../..'),f=responseFixture(),snapshot=assembleCaptureResponse(wire(f),f);
 for(const role of ['archiveDirectory','keyDirectory']){
  const paths={archiveDirectory:join(parent,'archive-'+role),keyDirectory:join(parent,'key-'+role)};paths[role]=join(checkout,'supabase','synthetic-storage-output');
  await assert.rejects(writeStorageMetadataBundle(snapshot,paths),e=>e.code==='STORAGE_METADATA_OUTPUT_PATH_INVALID');assert.deepEqual(await readdir(parent),[]);
 }
});
