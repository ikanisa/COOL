import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {validateSchema} from '../../../supabase/functions/_shared/domain/burimunsi/wire/runtime.mjs';
import {validateNativeRequest} from '../../../supabase/functions/_shared/domain/burimunsi/wire/native-contract.mjs';
import {defs} from '../../../supabase/functions/_shared/domain/burimunsi/wire/burimunsi.generated.mjs';

// Captured from the exact strict-server predecessor, not a permissive-server claim.
const legacy=JSON.parse(await readFile(new URL('./fixtures/legacy-held-request.schema.json',import.meta.url),'utf8'));
const buildConfig=await readFile(new URL('../app/build.gradle.kts',import.meta.url),'utf8');
const held={requestId:'00000000-0000-4000-8000-000000000111',rawSender:'M-Money',rawBody:'Synthetic held receipt',
 sourceMode:'catch_up',complete:false,capturedAt:'2026-11-17T18:00:00Z',serviceCentreAt:null,
 inboxReceivedAt:'2026-11-17T17:59:00Z',subscriptionId:3,sourceKey:'a'.repeat(64),expectedConsentGeneration:7};

for(const operation of ['observationRecoverHeld','observationRecoverHeldAck']){
 test(`${operation}: strict old and new request contracts do not silently downgrade`,()=>{
  assert.equal(legacy.sourceCommit,'42d85017306dddeb733ab2a286c29efb5ec4990e');
  assert.equal(legacy.sourceSchemaSha256,'15749d6dbe01137160ae3f2361fcd7c0e1bc4d82b3fe388119736369313b4436');
  assert.doesNotThrow(()=>validateNativeRequest(operation,held));
  assert.throws(()=>validateSchema(legacy.definitions,`${operation}.request`,held),e=>e.code==='CONTRACT_UNKNOWN_FIELD');
  const {expectedConsentGeneration,...old}=held;
  assert.doesNotThrow(()=>validateSchema(legacy.definitions,`${operation}.request`,old));
  assert.throws(()=>validateNativeRequest(operation,old),e=>e.code==='CONTRACT_MISSING_FIELD');
  for(const bad of [0,-1,1.5,9007199254740992,'7',null])
   assert.throws(()=>validateNativeRequest(operation,{...held,expectedConsentGeneration:bad}));
 });
}

test('ordinary observation requests do not gain the held-only claim',()=>{
 const {expectedConsentGeneration,...ordinary}=held;
 assert.doesNotThrow(()=>validateNativeRequest('observation',ordinary));
 assert.throws(()=>validateNativeRequest('observation',held),e=>e.code==='CONTRACT_UNKNOWN_FIELD');
});

test('held recovery stays hard-disabled until the old-server ambiguity is resolved',()=>{
 // Guard the actual Gradle source as well as the adapter's synthetic default.
 assert.equal((buildConfig.match(/\bHELD_RECOVERY_ENABLED\b/g)??[]).length,1);
 assert.match(buildConfig,/buildConfigField\(\s*"boolean"\s*,\s*"HELD_RECOVERY_ENABLED"\s*,\s*"false"\s*\)/);
 for(const field of ['HELD_RECOVERY_APPROVED_SOURCE_SHA256','HELD_RECOVERY_APPROVED_MIGRATION_SHA256']){
  assert.equal((buildConfig.match(new RegExp('\\b'+field+'\\b','g'))??[]).length,1);
  assert.match(buildConfig,new RegExp('buildConfigField\\(\\s*"String"\\s*,\\s*"'+field+'"\\s*,\\s*quoted\\(""\\)\\s*\\)'));
 }
});

test('a permissive v1-shaped 200 cannot satisfy a v2 capability',()=>{
 const old={contractVersion:'burimunsi.native.v1',ok:true,binding:{requestId:held.requestId,installationId:'installation-1',
  generation:'1',groupId:'group-1',actorId:'admin-1'},data:{requestId:held.requestId,sourceId:'source-1',
  bodySha256:'a'.repeat(64),status:'source_unresolved',financialEffects:0,autoProcessing:'held'}};
 assert.throws(()=>validateSchema(legacy.definitions,'observationRecoverHeld.request',held),e=>e.code==='CONTRACT_UNKNOWN_FIELD');
 assert.throws(()=>validateSchema(defs,'observationRecoveryV2Capability.response',old));
});
