import test from 'node:test';
import assert from 'node:assert/strict';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {RecordsService} from '../../domain/burimunsi/records-service.js';
import {ScopedCursor} from '../../domain/burimunsi/cursor.js';
import {BuriError} from '../../domain/burimunsi/errors.js';

const id='11111111-1111-4111-8111-111111111111',device='22222222-2222-4222-8222-222222222222';
const actor={id,sessionId:id,groupId:'group-1',role:'staff',active:true,revoked:false,
 expiresAt:9999999999999,installationId:device,installationProfile:'staff',capabilities:['records.read','members.enroll']};
function fixture(){
 const state={authorized:true,enroll:true,batchCalls:0,suggestions:[]};const noop=async()=>({});
 const tx={reloadActor:async()=>state.enroll?actor:{...actor,capabilities:['records.read']},loadBinding:async()=>null,listRevision:async()=> 'revision',
  onboardingSuggestions:async()=>({items:state.suggestions,totalCount:state.suggestions.length,after:null})};
 const records=new RecordsService({store:{withReadSnapshot:fn=>fn(tx)},groupId:'group-1',cursor:new ScopedCursor(new Uint8Array(32).fill(8)),clock:()=>1793961600000});
 const handler=createNativeHandler({auth:{login:noop,authenticate:async()=>{if(!state.authorized)throw new BuriError('session_unavailable',401);return actor;},logout:noop,changePasscode:noop,manageStaff:noop},
  records,contributions:{allocate:noop},members:{enroll:noop,setActive:noop,importMembers:async(_,body)=>{state.batchCalls++;return {requestId:body.requestId,results:body.rows.map(row=>({row:row.row,status:'created',memberId:'member-1'})),created:body.rows.length};}},
  gateway:{status:noop,replace:noop},origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop});
 const req=(path,method='GET',value)=>new Request('https://example.invalid/v1/burimunsi'+path,{method,
  headers:{'x-burimunsi-installation':device,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':id,
   'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json'},
  ...(value===undefined?{}:{body:JSON.stringify(value)})});
 return {handler,req,state};
}
test('authenticated suggestions use the new strict route and scoped envelope',async()=>{
 const {handler,req}=fixture();const r=await handler(req('/members/suggestions?q=Example&limit=20'));
 assert.equal(r.status,200);assert.deepEqual((await r.json()).data.items,[]);
});
test('a nonempty masked suggestion conforms to the installed native wire contract',async()=>{
 const {handler,req,state}=fixture();
 state.suggestions=[{candidateId:id,momoName:'Synthetic Person',last3:'123',latestSeenAt:'2026-11-13T08:00:00.000Z',sourceCount:2}];
 const r=await handler(req('/members/suggestions?limit=20'));assert.equal(r.status,200);
 const result=await r.json();assert.deepEqual(result.data.items,[{id,groupId:'group-1',...state.suggestions[0]}]);
 assert.equal(result.data.totalCount,1);assert.equal(JSON.stringify(result).includes('+250'),false);
});
test('CSV preview accepts a bounded upload larger than ordinary native commands',async()=>{
 const {handler,req}=fixture();const csv='name,phone\n'+Array.from({length:300},(_,i)=>`Synthetic Person ${i},0780000${String(i).padStart(3,'0')}`).join('\n');
 const bytes=Buffer.from(csv);assert.ok(Buffer.byteLength(bytes.toString('base64'))>8192);
 const r=await handler(req('/members/import/preview','POST',{mimeType:'text/csv',fileBytes:bytes.toString('base64'),externalOcrConsent:false}));
 assert.equal(r.status,200);const out=(await r.json()).data;assert.equal(out.sourceKind,'csv');assert.equal(out.rows.length,300);
});
test('ordinary member commands retain the original 8 KiB limit',async()=>{
 const {handler,req}=fixture();const r=await handler(req('/members','POST',{name:'x'.repeat(9000),phone:'+250780000001',requestId:id}));
 assert.equal(r.status,413);
});
test('preview cannot run before session authentication',async()=>{
 const {handler,req,state}=fixture();state.authorized=false;
 const r=await handler(req('/members/import/preview','POST',{mimeType:'text/csv',fileBytes:'bmFtZSxwaG9uZQo=',externalOcrConsent:false}));assert.equal(r.status,401);
});
test('preview rechecks the current enrollment capability before parsing',async()=>{
 const {handler,req,state}=fixture();state.enroll=false;
 const r=await handler(req('/members/import/preview','POST',{mimeType:'text/csv',fileBytes:'bmFtZSxwaG9uZQo=',externalOcrConsent:false}));
 assert.equal(r.status,403);
});
for(const [mime,bytes] of [
 ['image/png',Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a])],
 ['application/pdf',Buffer.from('%PDF-1.7\nsynthetic')],
 ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',Buffer.from([0x50,0x4b,0x03,0x04,0,0])],
])test('unconfigured '+mime+' preview fails without exposing the document',async()=>{
 const {handler,req}=fixture(),encoded=bytes.toString('base64');
 const r=await handler(req('/members/import/preview','POST',{mimeType:mime,fileBytes:encoded,externalOcrConsent:true}));
 assert.equal(r.status,503);assert.equal((await r.text()).includes(encoded),false);
});
test('batch response is correlated with the exact request',async()=>{
 const {handler,req,state}=fixture(),row={row:1,name:'Synthetic Person',phone:'+250780000001',verifiedOwnership:true,acceptedTerms:true,consentRecorded:true};
 const r=await handler(req('/members/import','POST',{requestId:id,rows:[row]}));assert.equal(r.status,200);
 assert.equal((await r.json()).data.results[0].row,1);assert.equal(state.batchCalls,1);
});
test('a full batch of Unicode names fits the authenticated batch boundary',async()=>{
 const {handler,req,state}=fixture(),rows=Array.from({length:500},(_,i)=>({row:i+1,name:'界'.repeat(100),
  phone:'078'+String(i).padStart(7,'0'),verifiedOwnership:true,acceptedTerms:true,consentRecorded:true}));
 const body={requestId:id,rows};assert.ok(Buffer.byteLength(JSON.stringify(body))>131072);
 const r=await handler(req('/members/import','POST',body));assert.equal(r.status,200);
 assert.equal((await r.json()).data.results.length,500);assert.equal(state.batchCalls,1);
});

test('advanced preview runs outside snapshots and rechecks current enrollment authority',async()=>{
 const state={inside:false,enroll:true,invoked:0};
 const tx={reloadActor:async()=>state.enroll?actor:{...actor,capabilities:['records.read']},loadBinding:async()=>null};
 const store={withReadSnapshot:async fn=>{assert.equal(state.inside,false);state.inside=true;
  try{return await fn(tx);}finally{state.inside=false;}}};
 const smartOnboardingImport={async preview({authorize}){state.invoked++;assert.equal(state.inside,false);
  assert.equal((await authorize()).id,actor.id);assert.equal(state.inside,false);state.enroll=false;
  await assert.rejects(authorize(),/access_denied/);assert.equal(state.inside,false);
  return {sourceKind:'csv',rows:[]};}};
 const records=new RecordsService({store,groupId:'group-1',cursor:new ScopedCursor(new Uint8Array(32).fill(8)),
  clock:()=>1793961600000,smartOnboardingImport});
 const output=await records.onboardingPreview(actor,{bytes:new Uint8Array([1]),mimeType:'text/csv',externalOcrConsent:false});
 assert.equal(output.sourceKind,'csv');assert.equal(state.invoked,1);
});
