import test from 'node:test';
import assert from 'node:assert/strict';
import {PostgresNativeObservations} from '../../domain/burimunsi/postgres-observations.js';
import {PostgresNativeCanonicalIntake} from '../../domain/burimunsi/postgres-native-canonical-intake.js';
import {canonicalJson} from '../../domain/burimunsi/values.js';

const uuid=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const actor={id:uuid(1),sessionId:uuid(2),installationId:uuid(3),principalUserId:'person',groupId:'group'};
const sourceId=uuid(4);
const record={id:sourceId,principalUserId:'person',object_key:`sms/${sourceId}`,
 object_sha256:'a'.repeat(64),bodySha256:'b'.repeat(64),fingerprint:'c'.repeat(64),consentGeneration:1};
const failure=code=>Object.assign(new Error('synthetic refusal'),{code});

// Exercises the actual adapter; this is not evidence of PostgreSQL behavior.
function fixture(){
 const s={enabled:true,owned:true,consent:true,record:structuredClone(record),journal:{key:'stable'},staged:false,
  stageCalls:0,lostCommit:false,onStage:null,badResult:null};
 const o=Object.create(PostgresNativeObservations.prototype);
 o.env={BURIMUNSI_NATIVE_CANONICAL_INTAKE_ENABLED:'true'};o.groupId='group';
 o.authority={assertOwned:async()=>{if(!s.owned)throw failure('08006');},write:async fn=>{
  const out=await fn({unsafe:async(sql,params)=>{
   assert.match(sql,/private\.burimunsi_stage_native_receipt/);assert.deepEqual(params,[sourceId]);
   s.stageCalls++;const created=!s.staged;s.staged=true;await s.onStage?.();
   return [{result:s.badResult??{sourceId,collectionId:'group',state:'source_unresolved',financialEffects:0,created}}];
  }});if(s.lostCommit){s.lostCommit=false;throw failure('08006');}return out;
 }};
 o.current=async()=>{if(!s.owned)throw failure('42501');return {...actor};};
 o.identity=a=>({...a});
 o.own=async()=>{if(!s.consent)throw failure('42501');return s.record&&structuredClone(s.record);};
 o.namespace=async()=>({origin:'https://example.invalid',bucket:'synthetic'});
 o.custody={journal:async()=>structuredClone(s.journal),sameJournal:(a,b)=>canonicalJson(a)===canonicalJson(b)};
 o.checkJournal=async(_r,j)=>{if(j.key!=='stable')throw failure('40001');};
 return {s,o,adapter:new PostgresNativeCanonicalIntake({observations:o})};
}

test('the intake is default-off and never stages without the explicit server flag',async()=>{
 const f=fixture();delete f.o.env.BURIMUNSI_NATIVE_CANONICAL_INTAKE_ENABLED;
 await assert.rejects(f.adapter.stage(actor,sourceId),e=>e.code==='native_intake_unavailable');
 assert.equal(f.s.stageCalls,0);
});

test('a retained source produces one unresolved zero-effect outcome and an exact retry',async()=>{
 const f=fixture();const first=await f.adapter.stage(actor,sourceId),again=await f.adapter.stage(actor,sourceId);
 assert.deepEqual(first,{sourceId,collectionId:'group',state:'source_unresolved',financialEffects:0,created:true});
 assert.deepEqual(again,{...first,created:false});assert.equal(f.s.stageCalls,2);
});

test('an unknown commit response is not acknowledged; the same source reconciles',async()=>{
 const f=fixture();f.s.lostCommit=true;
 await assert.rejects(f.adapter.stage(actor,sourceId),e=>e.status===503);
 assert.equal((await f.adapter.stage(actor,sourceId)).created,false);
});

test('revoked consent, changed source or changed storage after admission is not acknowledged',async()=>{
 for(const change of ['consent','record','journal']){
  const f=fixture();f.s.onStage=()=>{
   if(change==='consent')f.s.consent=false;
   if(change==='record')f.s.record.bodySha256='d'.repeat(64);
   if(change==='journal')f.s.journal.key='changed';
  };
  await assert.rejects(f.adapter.stage(actor,sourceId),e=>[403,409].includes(e.status),change);
 }
});

test('the database cannot return a different scope or a financial effect',async()=>{
 for(const bad of [
  {sourceId,collectionId:'other',state:'source_unresolved',financialEffects:0,created:true},
  {sourceId,collectionId:'group',state:'completed',financialEffects:0,created:true},
  {sourceId,collectionId:'group',state:'source_unresolved',financialEffects:1,created:true},
  {sourceId,collectionId:'group',state:'source_unresolved',financialEffects:0,created:true,account:'invented'}
 ]){
  const f=fixture();f.s.badResult=bad;await assert.rejects(f.adapter.stage(actor,sourceId),e=>e.status===409);
 }
});
