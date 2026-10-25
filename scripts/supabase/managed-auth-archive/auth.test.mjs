// Focused synthetic definitions only. Root owns all future test execution.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readdir,readFile,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import REAL from './REFERENCE.json' with {type:'json'};
import {CAPS,REFERENCE_SHA256,compileCountsRequest} from './counts.mjs';
import {syntheticSnapshot,syntheticValue,SYNTHETIC_PROJECT} from './native-definition.mjs';
import {FORMAT,SCOPE,validateAuthCell,sealAuthTable,validateAuthSnapshot,compileCaptureRequest,compileFixtureCaptureRequest,assembleCaptureResponse,encryptAuthSnapshot,decryptAuthSnapshot,captureAuth,restoreAuthInert} from './auth.mjs';
import {canonical,sha} from '../current-archive/codec.mjs';
import {decryptSnapshot as legacyDecrypt} from '../current-archive/bundle.mjs';
import {createManagementTransport} from '../current-archive/transport.mjs';
const clone=x=>JSON.parse(JSON.stringify(x));
const requestId='1ce5ab4a-3238-443b-97fc-d0c16e15f5b0';
const project=SYNTHETIC_PROJECT;
const proof=r=>({format:'collect.managed-auth.synthetic-counts.v1',reference_sha256:sha(canonical(r)),within_capture_row_caps:true,exact_auth_row_counts_measured:true,auth_cell_values_returned:false,sequence_values_returned:false,capture_dispatched:false,total_rows:'0'});
function responseFixture(){
 const counts=proof(REAL),request=compileCaptureRequest(REAL,counts,requestId),s=syntheticSnapshot();s.fixture=false;s.reference=REAL;s.reference_sha256=REFERENCE_SHA256;s.postgres.database='postgres';s.postgres.application_name='collect.authmeta.'+requestId.replaceAll('-','');s.counts_preflight_sha256=sha(canonical(counts));
 const target=REAL.relations.find(t=>t.name==='users'),columns=REAL.columns.filter(c=>c.relation_oid===target.oid),cells=columns.map(c=>syntheticValue(REAL,c,0));
 s.tables=s.tables.map(t=>t.name==='users'?sealAuthTable(REAL,'users',[cells]):t);
 const payload={format:'collect.managed-auth.capture-response.v1',request_id:requestId,reference_sha256:REFERENCE_SHA256,counts_preflight_sha256:sha(canonical(counts)),postgres:s.postgres,sequence:s.sequence,tables:s.tables.map((t,index)=>{const cells=t.rows.map(r=>r.cells);let bytes=0,max=0;for(const row of cells)for(const value of row)if(value!==null){const n=Buffer.byteLength(value);bytes+=n;max=Math.max(max,n);}return {schema:'auth',name:t.name,measure:{index,rows:String(cells.length),bytes:String(bytes),max_cell:String(max)},cells};})};
 const response={status:201,body:Buffer.from(JSON.stringify([{kind:payload.format,payload:JSON.stringify(payload)}]))};return {response,reference:REAL,counts,request,project,payload};
}
function wire(f){return {status:201,body:Buffer.from(JSON.stringify([{kind:f.payload.format,payload:JSON.stringify(f.payload)}]))};}

test('separate Auth snapshot cannot be accepted as original app/private scope',()=>{
 const s=syntheticSnapshot();assert.equal(validateAuthSnapshot(s,{allowFixture:true}),s);const changed=clone(s);changed.scope='sql-app-private-inert-recovery-data-only';assert.throws(()=>validateAuthSnapshot(changed,{allowFixture:true}));assert.throws(()=>validateAuthSnapshot(s));
});
test('all observed inet array and enum columns accept finite synthetic native-text values',()=>{
 for(const c of REAL.columns){const t=REAL.types.find(t=>t.oid===c.type_oid);if(t.kind==='e'||['869','1009'].includes(t.oid))for(let i=0;i<8;i++)assert.equal(validateAuthCell(syntheticValue(REAL,c,i),REAL,c),syntheticValue(REAL,c,i));}
});
test('unknown enum values and unsupported descriptor mutations are refused',()=>{
 const c=REAL.columns.find(c=>REAL.types.find(t=>t.oid===c.type_oid).kind==='e');assert.throws(()=>validateAuthCell('not_an_observed_enum_label',REAL,c));const changed=clone(REAL);changed.types.find(t=>t.kind==='e').enum_labels.push({label:'unreviewed',sort_order:'99'});assert.throws(()=>compileCaptureRequest(changed,proof(changed),requestId));
});
test('NULL mandatory cells and cells beyond fixed cap are refused without echoing values',()=>{
 const c=REAL.columns.find(c=>c.not_null&&c.type_oid==='25');assert.throws(()=>validateAuthCell(null,REAL,c),e=>e.code==='AUTH_NULL_NOT_ALLOWED');assert.throws(()=>validateAuthCell('x'.repeat(CAPS.cellBytes+1),REAL,c),e=>e.code==='AUTH_CELL_BOUND'&&!e.message.includes('xxxx'));
});
test('array lower-bound multidimension NULL-element and empty distinctions remain verbatim',()=>{
 const c=REAL.columns.find(c=>c.type_oid==='1009');for(const value of ['[0:1]={a,b}','{{a,b},{c,d}}','{NULL,"NULL",""}','{}'])assert.equal(validateAuthCell(value,REAL,c),value);assert.throws(()=>validateAuthCell('["flattened","json"]',REAL,c));
});
test('row and table digest tampering or missing selected table is refused',()=>{
 const s=syntheticSnapshot(),t=REAL.relations.find(t=>t.name==='users'),columns=REAL.columns.filter(c=>c.relation_oid===t.oid);s.tables=s.tables.map(x=>x.name==='users'?sealAuthTable(s.reference,x.name,[columns.map(c=>syntheticValue(s.reference,c,0))]):x);validateAuthSnapshot(s,{allowFixture:true});const changed=clone(s);changed.tables.find(t=>t.name==='users').rows[0].cells[0]='tampered';assert.throws(()=>validateAuthSnapshot(changed,{allowFixture:true}));s.tables.pop();assert.throws(()=>validateAuthSnapshot(s,{allowFixture:true}));
});
test('AESGCM roundtrip binds Auth AAD and refuses header tamper wrong key and old reader',()=>{
 const s=syntheticSnapshot(),key=Buffer.alloc(32,7),wrong=Buffer.alloc(32,8);try{const encrypted=encryptAuthSnapshot(s,key,{allowFixture:true});assert.equal(canonical(decryptAuthSnapshot(encrypted,key,{allowFixture:true}).snapshot),canonical(s));assert.throws(()=>decryptAuthSnapshot(encrypted,wrong,{allowFixture:true}));assert.throws(()=>legacyDecrypt(encrypted,key));const x=JSON.parse(encrypted);x.header.archive_id='2d51745d-88bd-465e-a523-a8c74177cf89';assert.throws(()=>decryptAuthSnapshot(Buffer.from(canonical(x)),key,{allowFixture:true}));}finally{key.fill(0);wrong.fill(0);}
});
test('ciphertext or tag tampering and fixture envelope in live path are refused',()=>{
 const key=Buffer.alloc(32,9);try{const encrypted=encryptAuthSnapshot(syntheticSnapshot(),key,{allowFixture:true}),x=JSON.parse(encrypted);assert.throws(()=>decryptAuthSnapshot(encrypted,key));x.tag=(x.tag[0]==='A'?'B':'A')+x.tag.slice(1);assert.throws(()=>decryptAuthSnapshot(Buffer.from(canonical(x)),key,{allowFixture:true}));}finally{key.fill(0);}
});
test('counts-only SQL has no sequence state or native Auth-cell output',()=>{
 const request=compileCountsRequest(REAL,requestId);assert.equal(request.kind,'metadata');for(const word of ['last_value','is_called','log_cnt','enum_out(','array_out(','inet_out('])assert.equal(request.body.query.includes(word),false);assert.equal(request.body.query.includes('collect_fence_control'),false);
});
test('capture has guarded measurements sequence gates and explicit output settings',()=>{
 const request=compileCaptureRequest(REAL,proof(REAL),requestId),q=request.body.query;assert.equal(request.kind,'capture');assert.equal((q.match(/WHERE \(SELECT valid FROM approved\) IS TRUE/g)||[]).length,27);assert.ok(q.includes('CASE WHEN (SELECT valid FROM approved) IS TRUE AND (SELECT valid FROM auth_budget) IS TRUE THEN'));for(const field of ['DateStyle','bytea_output','extra_float_digits','IntervalStyle','standard_conforming_strings'])assert.ok(q.includes("current_setting('"+field+"')"));assert.equal(q.includes('collect_fence_control'),false);assert.ok(q.includes('last_value'));assert.ok(q.includes('is_called'));
});
test('capture computes its own row count rather than reusing prior count identity',()=>{
 const f=responseFixture(),s=assembleCaptureResponse(f.response,f);assert.equal(f.counts.total_rows,'0');assert.equal(s.tables.reduce((n,t)=>n+t.row_count,0),1);assert.equal(s.auth_quiescence_proven,false);f.response.body.fill(0);
});
test('capture refusal mismatched request identity and inconsistent byte measures fail closed',()=>{
 const f=responseFixture();f.payload.tables[0].measure.bytes='1';assert.throws(()=>assembleCaptureResponse(wire(f),f));const g=responseFixture();g.payload.request_id='0'.repeat(36);assert.throws(()=>assembleCaptureResponse(wire(g),g));assert.throws(()=>assembleCaptureResponse({status:201,body:Buffer.from('[{"kind":"collect.managed-auth.capture-response.v1","payload":"{\\"refused\\":\\"METADATA_CHANGED\\"}"}]')},g));
});
test('capture validates actual native output settings and separate sequence descriptor',()=>{
 const f=responseFixture();f.payload.postgres.bytea_output='escape';assert.throws(()=>assembleCaptureResponse(wire(f),f),e=>e.code==='AUTH_CAPTURE_CONTEXT_INVALID');const g=responseFixture();delete g.payload.sequence.last_value;assert.throws(()=>assembleCaptureResponse(wire(g),g));
});
test('fixture compiled request cannot use unchanged hosted management transport',async()=>{
 const s=syntheticSnapshot(),request=compileFixtureCaptureRequest(s.reference,proof(s.reference),requestId,s.postgres.database);let wireRequests=0;const transport=createManagementTransport({token:'synthetic-no-provider-credential',environment:{},requestImpl(){wireRequests++;throw Error('must not dispatch');}});await assert.rejects(transport.query(request),e=>e.code==='COMPILED_REQUEST_INVALID');assert.equal(wireRequests,0);
});
test('unreviewed capture refuses before transport or private output creation',async()=>{
 let calls=0;const transport={readProject:async()=>{calls++;return project;},query:async()=>{calls++;throw Error('unexpected');}};await assert.rejects(captureAuth({transport,reference:REAL,counts:proof(REAL),expectedCountsSha256:'0'.repeat(64),requestId,archiveDirectory:'/not-used-auth',keyDirectory:'/not-used-key',executeReviewedReadOnly:true}),e=>e.code==='AUTH_CAPTURE_REVIEW_REQUIRED');assert.equal(calls,0);
});
test('failed simulated capture wipes returned buffer and leaves only safe intent evidence',async()=>{
 const parent=await mkdtemp(join(tmpdir(),'collect-auth-synthetic-')),archiveDirectory=join(parent,'archive'),keyDirectory=join(parent,'key'),counts=proof(REAL),body=Buffer.from('SYNTHETIC_INVALID_RESPONSE_NEVER_PERSIST');let queries=0;const transport={readProject:async()=>project,query:async()=>{queries++;return {status:201,body};}};
 await assert.rejects(captureAuth({transport,reference:REAL,counts,expectedCountsSha256:sha(canonical(counts)),requestId,archiveDirectory,keyDirectory,executeReviewedReadOnly:true}));assert.equal(queries,1);assert.ok(body.every(b=>b===0));assert.deepEqual(await readdir(archiveDirectory),['INTENT.json']);assert.deepEqual(await readdir(keyDirectory),[]);const intent=await readFile(join(archiveDirectory,'INTENT.json'),'utf8');assert.equal(intent.includes('SYNTHETIC_INVALID_RESPONSE'),false);assert.equal((await stat(join(archiveDirectory,'INTENT.json'))).mode&0o777,0o600);
 // Preserve this controlled synthetic failed attempt; Root owns its custody/cleanup.
});
test('remote or missing local native authority refuses without constructing a client',async()=>{
 let clients=0;await assert.rejects(restoreAuthInert(syntheticSnapshot(),{adminUrl:'postgres://postgres:synthetic@remote.invalid/postgres',makeClient(){clients++;},allowFixture:true}));assert.equal(clients,0);await assert.rejects(restoreAuthInert(syntheticSnapshot(),{adminUrl:'postgres://postgres:synthetic@127.0.0.1/postgres',allowFixture:true}));
});

test('capture refuses output inside the checkout before transport or directory creation',async()=>{
 const archiveDirectory=join(fileURLToPath(new URL('.',import.meta.url)),'synthetic-source-refusal-'+process.pid+'-'+Date.now()),keyDirectory=join(tmpdir(),'collect-auth-source-refusal-key-'+process.pid+'-'+Date.now()),counts=proof(REAL);let calls=0;
 const transport={readProject:async()=>{calls++;throw Error('must not dispatch');},query:async()=>{calls++;throw Error('must not dispatch');}};
 await assert.rejects(stat(archiveDirectory),{code:'ENOENT'});await assert.rejects(stat(keyDirectory),{code:'ENOENT'});
 await assert.rejects(captureAuth({transport,reference:REAL,counts,expectedCountsSha256:sha(canonical(counts)),requestId,archiveDirectory,keyDirectory,executeReviewedReadOnly:true}),e=>e.code==='AUTH_OUTPUT_PATH_INVALID');
 assert.equal(calls,0);await assert.rejects(stat(archiveDirectory),{code:'ENOENT'});await assert.rejects(stat(keyDirectory),{code:'ENOENT'});
});
