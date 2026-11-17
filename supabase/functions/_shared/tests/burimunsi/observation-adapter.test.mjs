// In-memory SQL/transport doubles with the actual PIN request gate and AES-GCM.
// These tests do not establish PostgreSQL guard behavior or provider delivery.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createPhonePinRequestGate,PIN_CONTEXT_SQL} from '../../domain/burimunsi/phone-pin-request.js';
import {PostgresNativeObservations,OBSERVATION_UNRESOLVED_SQL,observationContentFingerprint} from '../../domain/burimunsi/postgres-observations.js';
import {PostgresStorageWitnesses} from '../../domain/burimunsi/postgres-storage-witnesses.js';
import {ObservationUploadUnresolved} from '../../domain/burimunsi/errors.js';
import {validateProviderProfile} from '../../domain/momo_pipeline.js';
import {decrypt} from '../../domain/encryption.js';
import {canonicalJson,sha256} from '../../domain/burimunsi/values.js';
import {HELD_V2_PROTOCOL,HELD_V2_MIGRATION_SHA,HELD_V2_READY_IDENTITY_SQL} from '../../domain/burimunsi/held-recovery-v2.js';

const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const now=Date.now(),group='synthetic-group',principal='synthetic-principal',installation=id(1),account=id(2),session=id(3);
const device='d'.repeat(64),token='a'.repeat(64);
const pinRow={collection_id:group,principal_user_id:principal,native_session_id:session,account_id:account,installation_id:installation,
 profile:'internal_receiver',role:'admin',capabilities:['records.read','sms.read','gateway.manage'],created_at:now-1000,expires_at:now+1800000};
const actor={id:account,sessionId:session,principalUserId:principal,installationId:installation,groupId:group,
 role:'admin',capabilities:pinRow.capabilities,installationProfile:'internal_receiver',active:true,revoked:false,expiresAt:pinRow.expires_at};
const v2Release={sourceSha256:'a'.repeat(64),migrationSha256:HELD_V2_MIGRATION_SHA};
const incoming={requestId:id(5),rawSender:'Example Money',rawBody:'Received 250 RWF. Reference: 1234.',
 sourceMode:'live',complete:true,capturedAt:'2026-11-11T12:00:00.000Z',serviceCentreAt:null,inboxReceivedAt:null,subscriptionId:null};
const profileJson=JSON.stringify({sender_allowlist:['Example Money'],incoming_prefixes:['Received'],currency_aliases:['RWF'],
 transaction_id_prefixes:['Reference:'],date_format:'YMD_HMS',utc_offset_minutes:120});
const ctx=()=>({collectionId:group,accountId:account,principalUserId:principal,sessionId:session,installationId:installation,
 grantId:id(4),grantVersion:1,consentGeneration:1,status:'active',profile_status:'approved',profile_version:'synthetic-v1',
 profile_json:profileJson,currency:'RWF',timezone:'Africa/Kigali',profile_sha256:'b'.repeat(64),profile_tuple_sha256:'c'.repeat(64)});
const sqlError=(code,message='synthetic database refusal')=>Object.assign(new Error(message),{code});

function fixture(){
 const state={enabled:true,generation:1,row:null,rows:new Map(),sourceKeys:new Map(),requests:new Map(),media:new Map(),legacySources:[],witnesses:new Map(),recoveryHolds:new Map(),puts:0,commits:0,audits:[],revealGranted:true,active:true,allowLegacyFixture:true};
 const work={assert:async()=>{if(!state.active)throw new Error('synthetic lease revoked');}};
 let env;
 const allowed=()=>{if(!state.active||!state.enabled)throw sqlError('42501');};
 const sql={unsafe:async(query,args=[])=>{
  if(query===PIN_CONTEXT_SQL)return [pinRow];
  if(query.startsWith('SET TRANSACTION'))return [];
  if(query===HELD_V2_READY_IDENTITY_SQL)return state.v2MissingGuard?[]:[{ok:state.v2GuardDrift!==true}];
  if(query.includes('burimunsi_held_v2_ready')){
   allowed();if(!state.revealGranted)throw sqlError('42501');
   if(state.v2MigrationDrift||state.v2SourceDrift||state.v2CatalogDrift)throw sqlError('55000');
   const [source,generation,migration]=args;
   if(generation!==state.generation)throw sqlError('40001');
   if(source!=='a'.repeat(64)||migration!==HELD_V2_MIGRATION_SHA)throw sqlError('55000');
   if(state.onV2Ready)await state.onV2Ready();
   return [{result:{groupId:group,sourceSha256:source,migrationSha256:migration,consentGeneration:generation}}];
  }
  if(query.includes('observation_consent_current'))return [{result:{enabled:state.enabled,generation:state.generation}}];
  if(query.includes('observation_set_consent')){
   const [enabled,generation]=args;if(generation<state.generation||generation===state.generation&&enabled!==state.enabled)throw sqlError('40001');
   state.enabled=enabled;state.generation=generation;return [{result:{enabled:state.badEcho?!enabled:enabled,generation}}];
  }
  if(query.includes('observation_context')){allowed();return [{result:{...ctx(),sessionId:state.liveSessionId??session,consentGeneration:state.generation}}];}
  if(query.includes('observation_reconcile_verified_status')){allowed();(state.statusCalls??=[]).push('verified');return [{result:state.reconcileStatus??{groupId:group,hasPending:false,
   hasRecorded:false,recordedCount:0,hasUnmatchedCanonical:false,revision:'f'.repeat(64)}}];}
  if(query.includes('observation_reconcile_status')){allowed();(state.statusCalls??=[]).push('legacy');return [{result:state.reconcileStatus??{groupId:group,hasPending:false,
   hasRecorded:false,recordedCount:0,hasUnmatchedCanonical:false,revision:'f'.repeat(64)}}];}
  if(query.includes('observation_legacy_present')){allowed();return [{result:state.legacyPresent===true}];}
  if(query.includes('observation_legacy_retry_prepare')){
   allowed();const [requestId,fingerprint,sourceId]=args;
   if(!state.requests.has(requestId)&&state.allowLegacyFixture){
    const pending=[...state.requests.values()].filter(value=>value.requestId!==state.row?.requestId).length;
    if(pending>=16)throw sqlError('54000');state.requests.set(requestId,{requestId,fingerprint,sourceId});
   }
   const prior=state.requests.get(requestId);
   if(!prior||prior.fingerprint!==fingerprint||prior.sourceId!==sourceId)throw sqlError('55000');
   return [{result:{...ctx(),profile_tuple_sha256:state.tupleChangedOnPrepare?'e'.repeat(64):ctx().profile_tuple_sha256,
    consentGeneration:state.generation,requestId,fingerprint,sourceId}}];
  }
  if(query.includes('observation_key_prepare')||query.includes('sms_recovery_prepare')){
   if(query.includes('sms_recovery_prepare')){if(state.onRecoveryPrepare)await state.onRecoveryPrepare();if(!state.revealGranted)throw sqlError('42501');}
   if(query.includes('sms_recovery_prepare')&&args.length===11&&
    (args[9]!=='a'.repeat(64)||args[10]!==HELD_V2_MIGRATION_SHA||state.v2MigrationDrift||state.v2SourceDrift||state.v2CatalogDrift))throw sqlError('55000');
   allowed();const [key,content,body,requestId,fingerprint,sourceId,profileVersion,profileHash,generation]=args;
   if(generation!==state.generation||profileVersion!=='synthetic-v1'||profileHash!=='b'.repeat(64))throw sqlError('40001');
   const prior=state.sourceKeys.get(key);
   if(prior&&(prior.content!==content||prior.body!==body))throw sqlError('23505');
   if(prior&&prior.sourceId!==sourceId){const record=state.rows.get(prior.sourceId);if(!record)throw sqlError('55000');
    return [{result:{kind:'duplicate',record:structuredClone(record)}}];}
   if(!prior){state.sourceKeys.set(key,{content,body,sourceId});state.requests.set(requestId,{requestId,fingerprint,sourceId});}
   else if(state.requests.get(requestId)?.fingerprint!==fingerprint)throw sqlError('23505');
   return [{result:{kind:'new',context:{...ctx(),profile_tuple_sha256:state.tupleChangedOnPrepare?'e'.repeat(64):ctx().profile_tuple_sha256,
    consentGeneration:state.generation,requestId,fingerprint,sourceId}}}];
  }
  if(query.includes('collect_sms_witness_reserve')){
   allowed();const [mode,key,owner,collection,fingerprint,body,received,storage]=args;
   if(mode==='recovery'&&!state.revealGranted)throw sqlError('42501');
   const prior=state.witnesses.get(key);
   if(prior){if(prior.owner!==owner||prior.collection!==collection||prior.fingerprint!==fingerprint||prior.body!==body||prior.received!==received)throw sqlError('23505');
    return [{result:false}];}
   if(mode==='recovery'&&[...state.witnesses.values()].some(w=>
    w.collection===collection&&w.body===body&&w.key!==key))throw sqlError('55000');
   state.witnesses.set(key,{mode,key,owner,collection,fingerprint,body,received,storage});return [{result:true}];
  }
  if(query.includes('burimunsi_sms_recovery_ack_snapshot')){
   allowed();if(!state.revealGranted)throw sqlError('42501');
   const [sourceId,requestId,fingerprint,sourceKey,content,body,received]=args,key='sms/'+sourceId,
    request=state.requests.get(requestId),w=state.witnesses.get(key),hold=state.recoveryHolds.get(sourceId),
    source=state.sourceKeys.get(sourceKey),record=state.rows.get(sourceId),item=state.media.get(key);
   if(!request||request.sourceId!==sourceId||request.fingerprint!==fingerprint||!w||w.collection!==group||w.owner!==principal||
    w.fingerprint!==fingerprint||w.body!==body||w.received!==received||!hold||hold.fingerprint!==fingerprint||hold.generation!==state.generation||
    !source||source.sourceId!==sourceId||source.content!==content||source.body!==body||!record||!item||state.ackIncomplete)
    return [{result:null}];
   const descriptor=item.descriptor,size=new TextEncoder().encode(item.sealed).length,cipherSha=await sha256(item.sealed),
    custom={...descriptor.customMetadata,source_fingerprint:item.fingerprint},
    objectDescriptor={key,size,sha256:cipherSha,scope:descriptor.scope,httpMetadata:descriptor.httpMetadata,customMetadata:custom};
   const put={object_key:key,operation_id:await sha256('collect.storage.put.v1\n'+key),fingerprint:await sha256(canonicalJson(objectDescriptor)),
    sha256:cipherSha,size,scope:descriptor.scope,http_metadata:descriptor.httpMetadata,custom_metadata:custom,
    state:'committed',active_attempt:null,upload_unresolved:false,delete_tombstone:false};
   const metadata={...structuredClone(put)},reservation={object_key:key,source_fingerprint:item.fingerprint,scope:descriptor.scope,
    aad:descriptor.aad,key_id:descriptor.keyId,plaintext_sha256:descriptor.plaintextSha256};
   const proof={record:structuredClone(record),namespace:{origin:'https://example.invalid',bucket:'collect-evidence'},
    put,metadata,reservation,reservationCipherSha256:null,reservationCipherSize:null};
   if(state.tamperAckProof)state.tamperAckProof(proof);return [{result:proof}];
  }
  if(query.includes('burimunsi_sms_recovery_hold')){
   allowed();if(!state.revealGranted)throw sqlError('42501');
   const [sourceId,requestId,fingerprint,body,received]=args,key='sms/'+sourceId;
   const request=state.requests.get(requestId),w=state.witnesses.get(key),hold=state.recoveryHolds.get(sourceId);
   if(!request||request.sourceId!==sourceId||request.fingerprint!==fingerprint||!w||w.fingerprint!==fingerprint||w.body!==body||w.received!==received)
    throw sqlError('55000');
   if(hold&&(hold.fingerprint!==fingerprint||hold.body!==body||hold.received!==received))throw sqlError('55000');
   if(!hold)state.recoveryHolds.set(sourceId,{key,collection:w.collection,fingerprint,body,received,generation:state.generation});
   return [{result:true}];
  }
  if(query.includes('collect_sms_held_resume_check')){
   allowed();const [sourceId,requestId,fingerprint,body,received]=args,hold=state.recoveryHolds.get(sourceId);
   if(!hold)return [{result:false}];
   if(!state.revealGranted||hold.generation!==state.generation)throw sqlError('42501');
   const request=state.requests.get(requestId);
   if(!request||request.sourceId!==sourceId||request.fingerprint!==fingerprint||hold.fingerprint!==fingerprint||
    hold.body!==body||hold.received!==received)throw sqlError('55000');
   return [{result:true}];
  }
  if(query.includes('observation_key_lookup')){
   allowed();const [key,content,body]=args,prior=state.sourceKeys.get(key);
   if(!prior)return [{result:null}];if(prior.content!==content||prior.body!==body)throw sqlError('23505','burimunsi_observation_source_conflict');
   const record=state.rows.get(prior.sourceId);if(!record)throw sqlError('55000','burimunsi_observation_source_pending');
   // The real SQL key lookup returns the current actor's session, not the
   // historical observation's original session.
   return [{result:{...structuredClone(record),sessionId:state.liveSessionId??session,consentGeneration:state.generation}}];
  }
  if(query.includes('observation_legacy_candidates')){
   allowed();if(!state.revealGranted)throw sqlError('42501');
   const candidates=state.legacySources.filter(x=>x.collectionId===group&&x.accountId===account&&x.lineage===principal&&x.bodySha256===args[0]);
   if(candidates.length>4)throw sqlError('55000');
   return [{result:candidates.map(x=>{
    const record=state.rows.get(x.sourceId);if(!record)throw sqlError('55000');
    return {...structuredClone(record),sessionId:state.liveSessionId??session,consentGeneration:state.generation};
   }).sort((a,b)=>a.id.localeCompare(b.id))}];
  }
  if(query.includes('observation_prepare')){
   allowed();const [requestId,fingerprint,sourceId,profileVersion,profileHash,generation]=args;
   if(generation!==state.generation||profileVersion!=='synthetic-v1'||profileHash!=='b'.repeat(64))throw sqlError('40001');
   const prior=state.requests.get(requestId);
   if(prior&&prior.fingerprint!==fingerprint)throw sqlError('23505');
   if(!prior){
    const pending=[...state.requests.values()].filter(value=>value.requestId!==state.row?.requestId).length;
    if(pending>=16)throw sqlError('54000');
    state.requests.set(requestId,{requestId,fingerprint,sourceId});
   }
   return [{result:{...ctx(),profile_tuple_sha256:state.tupleChangedOnPrepare?'e'.repeat(64):ctx().profile_tuple_sha256,
    consentGeneration:state.generation,requestId,fingerprint,sourceId}}];
  }
  if(query.includes('observation_hint_profile')){allowed();return [{result:state.hintProfile?structuredClone(state.hintProfile):null}];}
  if(query.includes('observation_lookup')){allowed();if(state.row&&state.row.requestId===args[0]&&state.row.fingerprint!==args[1])throw sqlError('23505');
   return [{result:state.row?.requestId===args[0]?structuredClone(state.row):null}];}
  if(query===OBSERVATION_UNRESOLVED_SQL){
   const item=state.media.get(args[0]);if(!item||state.missingIntent)return [];
   const {descriptor,sealed,fingerprint:sourceFingerprint}=item,sha=await sha256(sealed),size=new TextEncoder().encode(sealed).length;
   const customMetadata={...descriptor.customMetadata,source_fingerprint:sourceFingerprint};
   const d={key:args[0],size,sha256:sha,scope:descriptor.scope,httpMetadata:descriptor.httpMetadata,customMetadata};
   const record={object_key:args[0],operation_id:await sha256('collect.storage.put.v1\n'+args[0]),fingerprint:await sha256(canonicalJson(d)),
    sha256:sha,size,scope:descriptor.scope,http_metadata:descriptor.httpMetadata,custom_metadata:customMetadata,
    state:state.statusState??'pending',active_attempt:null,upload_unresolved:state.uploadUnresolved===true,delete_tombstone:false,
    reservation_scope:descriptor.scope,aad:descriptor.aad,key_id:descriptor.keyId,plaintext_sha256:descriptor.plaintextSha256,
    source_fingerprint:sourceFingerprint,reservation_present:true,reservation_cipher_sha256:sha,reservation_cipher_size:size,
    metadata_present:state.statusState==='committed',metadata_matches:state.statusState==='committed'?true:null,has_delete:false};
   if(state.tamperStatus)state.tamperStatus(record);return [record];
  }
  if(query.includes('FROM private.storage_put_intents WHERE object_key=$1 FOR UPDATE'))
   return [{state:'committed',active_attempt:null,upload_unresolved:state.uploadUnresolved===true,delete_tombstone:false}];
  if(query.includes('observation_commit')){
   allowed();if(args[8]!==state.generation)throw sqlError('42501');
   const [requestId,fingerprint,sourceId,bodySha256,objectSha,sizeBytes]=args;
   const admitted=state.requests.get(requestId);
   if(!admitted||admitted.fingerprint!==fingerprint||admitted.sourceId!==sourceId)throw sqlError('42501');
   state.row={id:sourceId,sourceId,requestId,bodySha256,object_key:'sms/'+sourceId,object_sha256:objectSha,
    size_bytes:sizeBytes,createdAt:now,principalUserId:principal,sessionId:session,consentGeneration:state.generation,fingerprint};
   state.rows.set(sourceId,state.row);
   state.commits++;
   if(state.lostCommit){state.lostCommit=false;throw sqlError('08006');}
   return [{result:structuredClone(state.row)}];
  }
  if(query.includes('observation_history_own')){allowed();if(!state.revealGranted)throw sqlError('42501');
   return [{result:state.row?.id===args[0]?structuredClone(state.row):null}];}
  if(query.includes('observation_own')){allowed();if(args[1]&&!state.revealGranted)throw sqlError('42501');
   return [{result:state.row?.id===args[0]?structuredClone(state.row):null}];}
  if(query.includes('burimunsi_observation_page')){
   allowed();state.pageReadCount=(state.pageReadCount??0)+1;
   const [q,,limit,offset]=args;
   const rows=(state.pageRows??[]).filter(r=>r.id.includes(q));
   return [{result:{revision:state.pageRevision??'f'.repeat(64),totalCount:rows.length,items:rows.slice(offset,offset+limit)}}];
  }
  if(query.includes('storage_namespace'))return [{origin:'https://example.invalid',bucket:'collect-evidence'}];
  if(query.includes('observation_history_reveal_audit')){allowed();if(!state.revealGranted)throw sqlError('42501');
   state.audits.push({id:args[0],reason:args[2]});return [{result:structuredClone(state.row)}];}
  throw new Error('Unexpected synthetic SQL query');
 }};
 const db={applicationWork:work,setClaims:()=>{},context:async()=>{},readContext:async()=>{},transaction:fn=>fn(sql)};
 const gate=createPhonePinRequestGate({secrets:{pinPepper:new Uint8Array(32),pinPepperId:'synthetic'},networkBucket:async()=>'e'.repeat(64),clock:()=>now});
 const request=new Request('https://example.invalid/v1/burimunsi/home',{headers:{'X-BuriMunsi-Auth':'phone_pin',
  'X-BuriMunsi-Profile':'internal_receiver','X-BuriMunsi-Installation':installation,'X-BuriMunsi-Device':device,
  'X-BuriMunsi-Group':group,authorization:'Bearer '+token}});
 const media={namespace:{origin:'https://example.invalid',bucket:'collect-evidence'},put:async(key,sealed,options)=>{
   state.puts++;const descriptor={scope:options.scope,aad:options.aad,keyId:'synthetic-key',plaintextSha256:options.customMetadata.sha256,
    requestDigest:options.sourceDigest,httpMetadata:options.httpMetadata,customMetadata:options.customMetadata};
   const fingerprint=await sha256(canonicalJson(descriptor)),prior=state.media.get(key);
   if(prior&&prior.fingerprint!==fingerprint)throw new Error('synthetic storage conflict');
   if(!prior)state.media.set(key,{sealed,fingerprint,descriptor});
   if(state.onPut)await state.onPut();
  },get:async key=>{if(state.onGet)await state.onGet();const x=state.media.get(key);return x?{text:async()=>x.sealed}:null;},
  getVerifiedReadOnly:async(key,proof)=>{
   state.readOnlyGets=(state.readOnlyGets??0)+1;if(state.onReadOnly)await state.onReadOnly();
   const value=state.media.get(key);if(!value)throw new Error('synthetic missing object');
   const bytes=new TextEncoder().encode(value.sealed);
   if(bytes.length!==proof.size||await sha256(value.sealed)!==proof.sha256)throw new Error('synthetic proof mismatch');
   return bytes;
  }};
 env={DB:db,PRIVATE_MEDIA:media,BUILD_SOURCE_ID:'a'.repeat(64),DATA_KEY_ID:'synthetic-key',DATA_ENCRYPTION_KEY:Buffer.alloc(32,7).toString('base64')};
 const authority={db,groupId:group,read:fn=>{state.readTransactions=(state.readTransactions??0)+1;return fn(sql);},write:async fn=>{
   state.writeTransactions=(state.writeTransactions??0)+1;
   const result=await fn(sql);if(state.lostAudit&&state.audits.length){state.lostAudit=false;throw sqlError('08006');}return result;
  },session:async()=>state.active?{...structuredClone(actor),sessionId:state.liveSessionId??session}:null,assertOwned:work.assert};
 const custody={namespace:{origin:'https://example.invalid',bucket:'collect-evidence'},
  journal:async(_tx,key)=>{const value=state.media.get(key);if(!value)throw new Error('synthetic journal missing');
   return {reservation:{key_id:'synthetic-key',source_fingerprint:value.fingerprint},put:{object_key:key}};},
  sameJournal:(a,b)=>canonicalJson(a)===canonicalJson(b),decrypt:(sealed,aad)=>decrypt(env,sealed,aad)};
 const witnesses={stage:async(_binding,targets)=>targets,prefetch:async targets=>{
   if(state.onPrefetch)await state.onPrefetch();
   for(const target of targets){if(state.onGet)await state.onGet();if(!state.media.has(target.key))throw new Error('synthetic missing object');}
  },sealed:async(_binding,key)=>{const value=state.media.get(key);if(!value)throw new Error('synthetic missing object');return value.sealed;},forget:()=>{}};
 return {state,env,run:fn=>gate({request,env},async()=>fn(new PostgresNativeObservations({authority,env,
  validateProviderProfile,custody,storageWitnesses:witnesses,clock:()=>now})))};
}

test('advanced own-observation selectors cover the full metadata stream without storage/reveal',async()=>{
 const f=fixture(),cursor=new (await import('../../domain/burimunsi/cursor.js')).ScopedCursor(new Uint8Array(32).fill(7));
 f.state.pageRows=Array.from({length:151},(_,i)=>({id:id(500+i),createdAt:now-i*1000}));
 await f.run(async adapter=>{
  const query={sort:'oldest',limit:2,untilAt:new Date(now-148000).toISOString()};
  const first=await adapter.page(actor,query,cursor);assert.equal(first.totalCount,2);
  assert.deepEqual(first.items.map(r=>r.id),[id(650),id(649)]);assert.equal(first.nextCursor,null);
  assert.equal(f.state.pageReadCount,2);assert.equal(f.state.puts,0);assert.equal(f.state.audits.length,0);
  assert(first.items.every(r=>!Object.hasOwn(r,'rawBody')&&!Object.hasOwn(r,'sender')&&r.financialEffects===0));
 });
});
test('advanced own-observation cursor rejects changed query and dataset',async()=>{
 const f=fixture(),cursor=new (await import('../../domain/burimunsi/cursor.js')).ScopedCursor(new Uint8Array(32).fill(7));
 f.state.pageRows=Array.from({length:3},(_,i)=>({id:id(500+i),createdAt:now-i*1000}));
 await f.run(async adapter=>{
  const first=await adapter.page(actor,{sort:'oldest',limit:1},cursor);assert(first.nextCursor);
  await assert.rejects(adapter.page(actor,{sort:'newest',limit:1,cursor:first.nextCursor},cursor),/cursor_scope_changed/);
  f.state.pageRows.push({id:id(600),createdAt:now});
  await assert.rejects(adapter.page(actor,{sort:'oldest',limit:1,cursor:first.nextCursor},cursor),/cursor_scope_changed/);
 });
});

test('consent echo and single approved profile use current native proof',async()=>{
 const f=fixture();await f.run(async adapter=>{
  assert.deepEqual(await adapter.readConsent(actor),{enabled:true,generation:1});
  assert.deepEqual(await adapter.setConsent(actor,{enabled:false,generation:2}),{enabled:false,generation:2});
  await assert.rejects(adapter.profile(actor),e=>e.code==='access_denied');
  await adapter.setConsent(actor,{enabled:true,generation:3});
  const profile=await adapter.profile(actor);assert.deepEqual(profile.senders,['Example Money']);
  assert.equal(profile.expiresAt-profile.issuedAt,86400000);
  f.state.badEcho=true;await assert.rejects(adapter.setConsent(actor,{enabled:false,generation:4}),e=>e.status===503);
 });
});

test('encrypted capture retries reconcile the same request and reject changed content',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const first=await adapter.observe(actor,incoming),second=await adapter.observe(actor,incoming);
  assert.deepEqual(second,first);assert.equal(first.status,'source_unresolved');assert.equal(first.financialEffects,0);
  assert.equal(first.bodySha256,await sha256(incoming.rawBody));assert.equal(f.state.commits,1);assert.equal(f.state.puts,1);
  assert.equal([...f.state.media.values()][0].sealed.includes(incoming.rawBody),false);
  await assert.rejects(adapter.observe(actor,{...incoming,rawBody:'Received 251 RWF. Reference: 1234.'}),e=>e.status===409);
 });
});

test('held recovery retains one encrypted source and retries the same request without a new upload',async()=>{
 const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
 await f.run(async adapter=>{
  const first=await adapter.recoverHeld(actor,held),retry=await adapter.recoverHeld(actor,held);
  assert.deepEqual(retry,first);assert.equal(first.requestId,held.requestId);
  assert.equal(first.status,'source_unresolved');assert.equal(first.financialEffects,0);assert.equal(first.autoProcessing,'held');
  assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);assert.equal(f.state.recoveryHolds.size,1);
  assert.equal([...f.state.media.values()][0].sealed.includes(held.rawBody),false);
  await assert.rejects(adapter.recoverHeld(actor,{...held,rawBody:'Received 251 RWF. Reference: 1234.'}),e=>e.status===409);
 });
});

test('v2 capability and admission fail closed for source, migration or guard drift',async()=>{
 const held={...incoming,sourceMode:'catch_up',complete:false,inboxReceivedAt:'2026-11-11T12:00:00.000Z',
  sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
 for(const change of ['v2MissingGuard','v2GuardDrift','v2MigrationDrift','v2SourceDrift','v2CatalogDrift']){
  const f=fixture();f.state[change]=true;
  await f.run(async adapter=>{
   await assert.rejects(()=>adapter.recoveryV2Capability(actor,1,v2Release),e=>e.status===503);
   await assert.rejects(()=>adapter.recoverHeldV2(actor,held,v2Release),e=>e.status===503);
   assert.equal(f.state.requests.size,0);assert.equal(f.state.puts,0);
  });
 }
});

test('v2 rechecks original consent when it changes after capability or before admission',async()=>{
 for(const when of ['after-capability','inside-admission']){
  const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,inboxReceivedAt:'2026-11-11T12:00:00.000Z',
   sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
  await f.run(async adapter=>{
   const cap=await adapter.recoveryV2Capability(actor,1,v2Release);assert.equal(cap.protocol,HELD_V2_PROTOCOL);
   if(when==='after-capability')f.state.generation=3;
   else f.state.onRecoveryPrepare=async()=>{f.state.generation=3;};
   await assert.rejects(()=>adapter.recoverHeldV2(actor,held,v2Release),e=>e.status===409);
   assert.equal(f.state.requests.size,0);assert.equal(f.state.puts,0);assert.equal(f.state.commits,0);
  });
 }
});

test('v2 rejects the old pinned source after a capability-to-admission deployment change',async()=>{
 for(const when of ['different-runtime','inside-admission']){
  const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,inboxReceivedAt:'2026-11-11T12:00:00.000Z',
   sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
  await f.run(async adapter=>{
   assert.equal((await adapter.recoveryV2Capability(actor,1,v2Release)).sourceSha256,v2Release.sourceSha256);
   if(when==='different-runtime')f.env.BUILD_SOURCE_ID='b'.repeat(64);
   else f.state.onRecoveryPrepare=async()=>{f.state.v2SourceDrift=true;};
   await assert.rejects(()=>adapter.recoverHeldV2(actor,held,v2Release),e=>[403,503].includes(e.status));
   assert.equal(f.state.requests.size,0);assert.equal(f.state.puts,0);
  });
 }
});

test('v2 retains the source-bound generation across exact held admission and ACK',async()=>{
 const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,inboxReceivedAt:'2026-11-11T12:00:00.000Z',
  sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
 await f.run(async adapter=>{
  const cap=await adapter.recoveryV2Capability(actor,1,v2Release);assert.equal(cap.groupId,group);assert.equal(cap.sourceSha256,'a'.repeat(64));
  const saved=await adapter.recoverHeldV2(actor,held,v2Release);assert.equal(saved.protocol,HELD_V2_PROTOCOL);assert.equal(saved.expectedConsentGeneration,1);
  const ack=await adapter.recoverHeldV2Ack(actor,held,v2Release);assert.equal(ack.protocol,HELD_V2_PROTOCOL);assert.equal(ack.state,'acknowledged');
  assert.equal(ack.expectedConsentGeneration,1);assert.equal(ack.retryAllowed,false);assert.equal(f.state.puts,1);
 });
});

test('v2 final ACK and retained-source proof refuse release or catalog drift during storage read',async()=>{
 const held={...incoming,sourceMode:'catch_up',complete:false,inboxReceivedAt:'2026-11-11T12:00:00.000Z',
  sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
 for(const path of ['ack','retained'])for(const change of ['v2GuardDrift','v2MigrationDrift','v2SourceDrift','v2CatalogDrift']){
  const f=fixture();await f.run(async adapter=>{
   await adapter.recoverHeldV2(actor,held,v2Release);const before={puts:f.state.puts,commits:f.state.commits};
   if(path==='ack')f.state.onReadOnly=async()=>{f.state[change]=true;};
   else f.state.onGet=async()=>{f.state[change]=true;};
   await assert.rejects(()=>path==='ack'?adapter.recoverHeldV2Ack(actor,held,v2Release):adapter.recoverHeldV2(actor,held,v2Release),
    e=>e.status===503);
   assert.deepEqual({puts:f.state.puts,commits:f.state.commits},before);
  });
 }
});

test('v2 retained-source proof rechecks the exact record with final readiness',async()=>{
 const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,inboxReceivedAt:'2026-11-11T12:00:00.000Z',
  sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
 await f.run(async adapter=>{
  await adapter.recoverHeldV2(actor,held,v2Release);
  f.state.onGet=async()=>{f.state.onV2Ready=async()=>{
   f.state.onV2Ready=null;f.state.row={...f.state.row,size_bytes:f.state.row.size_bytes+1};
  };};
  await assert.rejects(()=>adapter.recoverHeldV2(actor,held,v2Release),e=>e.status===409);
  assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
 });
});

test('first held admission fails if consent is revoked and regranted before or during server admission',async()=>{
 for(const moment of ['before-context','after-context']){
  const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
   inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
  if(moment==='before-context')f.state.generation=3;
  else f.state.onRecoveryPrepare=async()=>{f.state.generation=3;};
  await f.run(async adapter=>{
   const outcomes=await Promise.allSettled([adapter.recoverHeld(actor,held),adapter.recoverHeld(actor,held)]);
   assert(outcomes.every(x=>x.status==='rejected'&&x.reason.status===409));
   assert.equal(f.state.requests.size,0);assert.equal(f.state.recoveryHolds.size,0);
   assert.equal(f.state.puts,0);assert.equal(f.state.commits,0);
   await assert.rejects(()=>adapter.recoverHeldAck(actor,held),e=>e.status===409);
  });
 }
});

test('held request binds the confirmed generation to its admitted identity',async()=>{
 const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
 await f.run(async adapter=>{
  await adapter.recoverHeld(actor,held);
  f.state.generation=3;
  await assert.rejects(()=>adapter.recoverHeld(actor,{...held,expectedConsentGeneration:3}),e=>e.status===409);
  const proof=await adapter.recoverHeldAck(actor,{...held,expectedConsentGeneration:3});
  assert.equal(proof.state,'unconfirmed');assert.equal(proof.retryAllowed,false);assert.equal(f.state.readOnlyGets??0,0);
  assert.equal(f.state.requests.size,1);assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
 });
});

test('exact held request resumes after admission but before the first storage attempt',async()=>{
 const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
 await f.run(async adapter=>{
  const put=f.env.PRIVATE_MEDIA.put;let attempted=0;
  f.env.PRIVATE_MEDIA.put=async()=>{attempted++;throw Error('synthetic crash before storage admission');};
  await assert.rejects(()=>adapter.recoverHeld(actor,held));
  assert.equal(attempted,1);assert.equal(f.state.recoveryHolds.size,1);assert.equal(f.state.media.size,0);
  f.env.PRIVATE_MEDIA.put=put;
  const result=await adapter.recoverHeld(actor,held);
  assert.equal(result.autoProcessing,'held');assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
  assert.equal((await adapter.recoverHeldAck(actor,held)).state,'acknowledged');
 });
});

test('a held resume through either capture route rejects changed consent before storage',async()=>{
 for(const route of ['recoverHeld','observe']){
  const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
   inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
  await f.run(async adapter=>{
   const put=f.env.PRIVATE_MEDIA.put;f.env.PRIVATE_MEDIA.put=async()=>{throw Error('synthetic crash before upload');};
   await assert.rejects(()=>adapter.recoverHeld(actor,held));assert.equal(f.state.recoveryHolds.size,1);
   f.env.PRIVATE_MEDIA.put=put;f.state.generation++;
   const {expectedConsentGeneration,...ordinaryHeld}=held;
   await assert.rejects(()=>adapter[route](actor,route==='observe'?ordinaryHeld:held),e=>[403,409].includes(e.status));
   assert.equal(f.state.puts,0);assert.equal(f.state.commits,0);
  });
 }
});

test('a retained held request is not acknowledged by replay after the consent generation changes',async()=>{
 const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
 await f.run(async adapter=>{
  await adapter.recoverHeld(actor,held);f.state.generation++;
  await assert.rejects(()=>adapter.recoverHeld(actor,held),e=>e.status===403);
  assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
 });
});

test('held recovery preserves submillisecond source times across admission, exact retry and acknowledgement',async()=>{
 for(let digits=4;digits<=9;digits++){
  const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
   inboxReceivedAt:`2026-11-11T12:00:00.${'123456789'.slice(0,digits)}Z`,sourceKey:'e'.repeat(64),expectedConsentGeneration:1};
  await f.run(async adapter=>{
   const first=await adapter.recoverHeld(actor,held),retry=await adapter.recoverHeld(actor,held);
   assert.deepEqual(retry,first);assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
   const acknowledged=await adapter.recoverHeldAck(actor,held);
   assert.equal(acknowledged.state,'acknowledged');assert.equal(acknowledged.sourceId,first.sourceId);
   assert.equal(acknowledged.retryAllowed,false);
  });
 }
});

test('held recovery acknowledgement proves exact retained evidence without writes or uploads',async()=>{
 const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'a'.repeat(64),expectedConsentGeneration:1};
 await f.run(async adapter=>{
  const saved=await adapter.recoverHeld(actor,held),before={puts:f.state.puts,commits:f.state.commits,
   writes:f.state.writeTransactions,requests:f.state.requests.size,holds:f.state.recoveryHolds.size};
  const first=await adapter.recoverHeldAck(actor,held),again=await adapter.recoverHeldAck(actor,held);
  assert.deepEqual(first,{requestId:held.requestId,sourceKey:held.sourceKey,bodySha256:await sha256(held.rawBody),
   financialEffects:0,retryAllowed:false,state:'acknowledged',sourceId:saved.sourceId,autoProcessing:'held'});
  assert.deepEqual(again,first);assert.equal(f.state.readOnlyGets,2);
  assert.deepEqual({puts:f.state.puts,commits:f.state.commits,writes:f.state.writeTransactions,
   requests:f.state.requests.size,holds:f.state.recoveryHolds.size},before);
  assert(!JSON.stringify(first).includes(held.rawBody));
 });
});

test('held acknowledgement never retries or uploads an absent or incomplete intent',async()=>{
 const held={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'b'.repeat(64),expectedConsentGeneration:1};
 for(const incomplete of ['absent','failed-upload','missing-hold','missing-witness','foreign-group','foreign-owner',
  'missing-observation','changed-request','changed-source-key','changed-consent-generation']){
  const f=fixture();await f.run(async adapter=>{
   let request=held;
   if(incomplete==='failed-upload'){
    f.state.onPut=async()=>{throw new Error('synthetic unknown upload outcome');};
    await assert.rejects(adapter.recoverHeld(actor,held));f.state.onPut=null;
   }else if(incomplete!=='absent'){
    const saved=await adapter.recoverHeld(actor,held);
    if(incomplete==='missing-hold')f.state.recoveryHolds.delete(saved.sourceId);
    if(incomplete==='missing-witness')f.state.witnesses.delete('sms/'+saved.sourceId);
    if(incomplete==='foreign-group')f.state.witnesses.get('sms/'+saved.sourceId).collection='other-group';
    if(incomplete==='foreign-owner')f.state.witnesses.get('sms/'+saved.sourceId).owner='other-owner';
    if(incomplete==='missing-observation')f.state.rows.delete(saved.sourceId);
    if(incomplete==='changed-request')request={...held,rawBody:'Received 251 RWF. Reference: 1234.'};
    if(incomplete==='changed-source-key')request={...held,sourceKey:'e'.repeat(64)};
    if(incomplete==='changed-consent-generation')f.state.generation++;
   }
   const before={puts:f.state.puts,commits:f.state.commits,writes:f.state.writeTransactions??0};
   if(incomplete==='changed-consent-generation')await assert.rejects(()=>adapter.recoverHeldAck(actor,request),e=>e.status===409);
   else {
    const result=await adapter.recoverHeldAck(actor,request);
    assert.equal(result.state,'unconfirmed');assert.equal(result.sourceId,null);
    assert.equal(result.autoProcessing,'unknown');assert.equal(result.retryAllowed,false);
   }
   assert.deepEqual({puts:f.state.puts,commits:f.state.commits,writes:f.state.writeTransactions??0},before);
   assert.equal(f.state.readOnlyGets??0,0);
  });
 }
});

test('held acknowledgement fails closed when custody, consent or authority changes during the read',async()=>{
 const held={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'c'.repeat(64),expectedConsentGeneration:1};
 for(const change of ['storage','consent','hold','namespace','metadata']){
  const f=fixture();await f.run(async adapter=>{
   const saved=await adapter.recoverHeld(actor,held),before={puts:f.state.puts,commits:f.state.commits,writes:f.state.writeTransactions};
   if(change==='metadata')f.state.tamperAckProof=proof=>{proof.put.custom_metadata.sha256='0'.repeat(64);};
   else f.state.onReadOnly=async()=>{
    if(change==='storage')throw new Error('synthetic storage outage');
    if(change==='consent')f.state.enabled=false;
    if(change==='hold')f.state.recoveryHolds.delete(saved.sourceId);
    if(change==='namespace')adapter.custody.namespace={origin:'https://other.invalid',bucket:'other'};
   };
   await assert.rejects(adapter.recoverHeldAck(actor,held),e=>[403,409,503].includes(e.status));
   assert.deepEqual({puts:f.state.puts,commits:f.state.commits,writes:f.state.writeTransactions},before);
  });
 }
});

test('held acknowledgement denies staff, revoked authority and disabled consent without probing storage',async()=>{
 const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'d'.repeat(64),expectedConsentGeneration:1};
 await f.run(async adapter=>{
  await adapter.recoverHeld(actor,held);const session=adapter.authority.session;
  for(const changed of [{role:'staff'},{groupId:'other'},{installationProfile:'staff'},{revoked:true}]){
   adapter.authority.session=async()=>({...actor,...changed});
   await assert.rejects(adapter.recoverHeldAck(actor,held),e=>e.status===403);
  }
  adapter.authority.session=session;f.state.revealGranted=false;
  await assert.rejects(adapter.recoverHeldAck(actor,held),e=>e.status===403);
  f.state.revealGranted=true;f.state.enabled=false;
  await assert.rejects(adapter.recoverHeldAck(actor,held),e=>e.status===403);
  assert.equal(f.state.readOnlyGets??0,0);
 });
});

test('held recovery refuses equal bodies even when source keys or receipt times differ',async()=>{
 const f=fixture(),first={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'1'.repeat(64)};
 await f.run(async adapter=>{
  await adapter.observe(actor,first);
  const collision={...first,expectedConsentGeneration:1,requestId:id(31),sourceKey:'2'.repeat(64),inboxReceivedAt:'2026-11-12T12:00:00.000Z'};
  await assert.rejects(adapter.recoverHeld(actor,collision),e=>e.status===503);
  assert.equal(f.state.puts,1);assert.equal(f.state.recoveryHolds.size,0);
 });
});

test('a foreign or unscoped equal-body witness does not deny recovery for this collection',async()=>{
 for(const collection of ['other-collection',null]){
  const f=fixture(),body=await sha256(incoming.rawBody),foreignKey='sms/'+id(999);
  f.state.witnesses.set(foreignKey,{key:foreignKey,collection,body});
  const held={...incoming,sourceMode:'catch_up',complete:false,
   inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'4'.repeat(64),expectedConsentGeneration:1};
  await f.run(async adapter=>{
   const result=await adapter.recoverHeld(actor,held);
   assert.equal(result.autoProcessing,'held');assert.equal(f.state.puts,1);
  });
 }
});

test('a held recovery does not block a later ordinary equal-body source',async()=>{
 const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'5'.repeat(64),expectedConsentGeneration:1};
 await f.run(async adapter=>{
  await adapter.recoverHeld(actor,held);
  const {expectedConsentGeneration,...ordinary}={...held,requestId:id(32),sourceKey:'6'.repeat(64),inboxReceivedAt:'2026-11-12T12:00:00.000Z'};
  const result=await adapter.observe(actor,ordinary);
  assert.equal(result.status,'source_unresolved');assert.equal(f.state.puts,2);
 });
});

test('held recovery requires reveal authority, current consent and an inbox identity',async()=>{
 const f=fixture(),held={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'3'.repeat(64),expectedConsentGeneration:1};
 await f.run(async adapter=>{
  await assert.rejects(adapter.recoverHeld(actor,{...held,inboxReceivedAt:null}),e=>e.status===400);
  f.state.revealGranted=false;await assert.rejects(adapter.recoverHeld(actor,held),e=>e.status===403);
  assert.equal(f.state.puts,0);assert.equal(f.state.recoveryHolds.size,0);
  f.state.revealGranted=true;f.state.enabled=false;
  await assert.rejects(adapter.recoverHeld(actor,{...held,requestId:id(32)}),e=>e.status===403);
  assert.equal(f.state.puts,0);
 });
});

test('reinstall-stable row identity reuses only the exact retained message, and preserves identical separate rows',async()=>{
 const f=fixture(),key='c'.repeat(64),catchup={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:key};
 await f.run(async adapter=>{
  const first=await adapter.observe(actor,catchup);
  const retry=await adapter.observe(actor,{...catchup,requestId:id(6),capturedAt:'2026-11-12T12:00:00.000Z'});
  assert.equal(retry.sourceId,first.sourceId);assert.equal(retry.requestId,id(6));assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
  await assert.rejects(adapter.observe(actor,{...catchup,requestId:id(7),rawBody:'Received 251 RWF. Reference: 1234.'}),e=>e.status===409);
  const separate=await adapter.observe(actor,{...catchup,requestId:id(8),sourceKey:'d'.repeat(64)});
  assert.notEqual(separate.sourceId,first.sourceId);assert.equal(f.state.commits,2);assert.equal(f.state.puts,2);
  f.state.enabled=false;await assert.rejects(adapter.observe(actor,{...catchup,requestId:id(9)}),e=>e.status===403);
 });
});

test('an unavailable original encrypted object never produces a duplicate acknowledgement',async()=>{
 const f=fixture(),catchup={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'d'.repeat(64)};
 await f.run(async adapter=>{
  const first=await adapter.observe(actor,catchup);f.state.media.delete('sms/'+first.sourceId);
  await assert.rejects(adapter.observe(actor,{...catchup,requestId:id(6)}),e=>e.status===503);
  assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
 });
});

test('reconciliation checks the exact retained source without creating or returning SMS content',async()=>{
 const f=fixture(),item={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'d'.repeat(64)};
 const proof={sourceKey:item.sourceKey,bodySha256:await sha256(item.rawBody),rawSender:item.rawSender,
  serviceCentreAt:item.serviceCentreAt,inboxReceivedAt:item.inboxReceivedAt,subscriptionId:item.subscriptionId};
 await f.run(async adapter=>{
  const absent=await adapter.reconcile(actor,proof);
  assert.deepEqual(absent,{groupId:group,sourceKey:item.sourceKey,state:'missing',sourceId:null,latestRecordedSourceId:null});
  assert.equal(f.state.puts,0);assert.equal(f.state.commits,0);
  const saved=await adapter.observe(actor,item);
  // Server retention order is scoped and informational: another retained ID
  // may be latest even though this exact phone item is already durable.
  f.state.pageRows=[{id:id(80),createdAt:now},{id:saved.sourceId,createdAt:now-1}];
  const matched=await adapter.reconcile(actor,proof);
  assert.deepEqual(matched,{groupId:group,sourceKey:item.sourceKey,state:'matched',sourceId:saved.sourceId,latestRecordedSourceId:id(80)});
  assert.equal(Object.hasOwn(matched,'rawBody'),false);assert.equal(Object.hasOwn(matched,'object_key'),false);
  assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
  await assert.rejects(adapter.reconcile(actor,{...proof,bodySha256:'e'.repeat(64)}),e=>e.status===409);
  await assert.rejects(adapter.reconcile(actor,{...proof,rawSender:'Not an approved sender'}),e=>e.status===422);
  await assert.rejects(adapter.reconcile(actor,{...proof,sourceKey:'no'}),e=>e.status===400);
  f.state.media.delete('sms/'+saved.sourceId);
  await assert.rejects(adapter.reconcile(actor,proof),e=>e.status===503);
  assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
 });
});

test('reconciliation fails closed for staff, disabled consent and unresolved reservations',async()=>{
 const f=fixture(),item={...incoming,sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'e'.repeat(64)};
 const proof={sourceKey:item.sourceKey,bodySha256:await sha256(item.rawBody),rawSender:item.rawSender,
  serviceCentreAt:item.serviceCentreAt,inboxReceivedAt:item.inboxReceivedAt,subscriptionId:item.subscriptionId};
 await f.run(async adapter=>{
  const session=adapter.authority.session;
  for(const changed of [{role:'staff'},{installationProfile:'staff'},{groupId:'other'},{revoked:true}]){
   adapter.authority.session=async()=>({...actor,...changed});
   await assert.rejects(adapter.reconcile(actor,proof),e=>e.status===403);
  }
  adapter.authority.session=session;
  f.state.enabled=false;await assert.rejects(adapter.reconcile(actor,proof),e=>e.status===403);f.state.enabled=true;
  const saved=await adapter.observe(actor,item);f.state.rows.delete(saved.sourceId);
  await assert.rejects(adapter.reconcile(actor,proof),e=>e.status===503);
  assert.equal(f.state.commits,1);assert.equal(f.state.puts,1);
 });
});

test('reconciliation rechecks consent and the exact source after reading retained storage',async()=>{
 for(const change of ['consent','generation','source']){
  const f=fixture(),item={...incoming,sourceMode:'catch_up',complete:false,
   inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'e'.repeat(64)};
  const proof={sourceKey:item.sourceKey,bodySha256:await sha256(item.rawBody),rawSender:item.rawSender,
   serviceCentreAt:item.serviceCentreAt,inboxReceivedAt:item.inboxReceivedAt,subscriptionId:item.subscriptionId};
  await f.run(async adapter=>{
   const saved=await adapter.observe(actor,item);f.state.pageRows=[{id:saved.sourceId,createdAt:now}];
   f.state.onGet=async()=>{
    if(change==='consent')f.state.enabled=false;
    if(change==='generation')f.state.generation++;
    if(change==='source')f.state.rows.delete(saved.sourceId);
   };
   await assert.rejects(adapter.reconcile(actor,proof),e=>[403,409,503].includes(e.status));
   assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
  });
 }
});

async function batchWitness(n){
 const item={...incoming,requestId:id(100+n),sourceMode:'catch_up',complete:false,
  inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:n.toString(16).padStart(64,'0')};
 return {item,proof:{sourceKey:item.sourceKey,bodySha256:await sha256(item.rawBody),rawSender:item.rawSender,
  serviceCentreAt:item.serviceCentreAt,inboxReceivedAt:item.inboxReceivedAt,subscriptionId:item.subscriptionId}};
}

async function importedWitness(f,adapter,n,overrides={}){
 const item={...incoming,requestId:id(1000+n),inboxReceivedAt:'2026-11-11T12:00:00.000Z',...overrides};
 const saved=await adapter.observe(actor,item);
 f.state.legacySources.push({sourceId:saved.sourceId,collectionId:group,accountId:account,lineage:principal,bodySha256:await sha256(item.rawBody)});
 const proof={sourceKey:n.toString(16).padStart(64,'0'),bodySha256:await sha256(item.rawBody),rawSender:item.rawSender,
  serviceCentreAt:item.serviceCentreAt,inboxReceivedAt:item.inboxReceivedAt??'2026-11-11T12:00:00.000Z',subscriptionId:item.subscriptionId};
 return {item,proof,saved};
}

// Exercise the real in-memory witness capability and AES-GCM with synthetic
// metadata and a fake object transport. No PostgreSQL or provider is contacted.
function useActualWitnesses(f,adapter){
 const trace={writes:0,inTransaction:false,reads:0,seals:0,forgotten:0,bindings:new Set(),now};
 const write=adapter.authority.write;
 adapter.authority.write=async fn=>{
  assert.equal(trace.inTransaction,false);trace.inTransaction=true;trace.writes++;
  try{return await write(fn);}finally{trace.inTransaction=false;}
 };
 adapter.custody.journal=async(_tx,key)=>{
  const value=f.state.media.get(key);if(!value)throw new Error('synthetic journal missing');
  const size=new TextEncoder().encode(value.sealed).length;
  return {reservation:{key_id:'synthetic-key',source_fingerprint:value.fingerprint},
   put:{object_key:key,size,sha256:await sha256(value.sealed)},
   metadata:{http_metadata:value.descriptor.httpMetadata,custom_metadata:value.descriptor.customMetadata}};
 };
 const media={namespace:structuredClone(adapter.custody.namespace),get:async key=>{
  assert.equal(trace.inTransaction,false,'Storage cannot be read while holding the database fence');
  trace.reads++;await f.state.onGet?.();const value=f.state.media.get(key);if(!value)return null;
  const size=new TextEncoder().encode(value.sealed).length;
  return {key,size,sha256:await sha256(value.sealed),httpMetadata:value.descriptor.httpMetadata,
   customMetadata:value.descriptor.customMetadata,text:async()=>value.sealed};
 }};
 const witnesses=new PostgresStorageWitnesses({db:adapter.authority.db,groupId:group,namespace:media.namespace,media,
  applicationWorkTuple:()=>[id(888),1,'a'.repeat(64)],clock:()=>trace.now});
 adapter.storageWitnesses={
  stage:async(binding,targets)=>{const plan=await witnesses.stage(binding,targets);trace.bindings.add(canonicalJson(binding));return plan;},
  prefetch:async plan=>{assert.equal(trace.inTransaction,false);return witnesses.prefetch(plan);},
  sealed:async(...args)=>{const result=await witnesses.sealed(...args);trace.seals++;await trace.afterSeal?.(trace.seals);return result;},
  forget:binding=>{trace.forgotten++;trace.bindings.delete(canonicalJson(binding));return witnesses.forget(binding);},
 };
 return trace;
}

test('singleton legacy batch shares its last fence and retains the real sealed witness until verification',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const a=await importedWitness(f,adapter,295);
  const trace=useActualWitnesses(f,adapter),before={puts:f.state.puts,commits:f.state.commits,audits:f.state.audits.length};
  trace.afterSeal=n=>{assert.equal(trace.inTransaction,n===2,'the final witness check must be fenced');};
  const result=await adapter.reconcileBatch(actor,{items:[a.proof]});
  assert.deepEqual(result.items,[{sourceKey:a.proof.sourceKey,state:'matched',sourceId:a.saved.sourceId}]);
  assert.equal(trace.writes,2);assert.equal(trace.reads,1);assert.equal(trace.seals,2);
  assert.equal(trace.forgotten,1);assert.equal(trace.bindings.size,0);
  assert.deepEqual({puts:f.state.puts,commits:f.state.commits,audits:f.state.audits.length},before);
 });
});

test('singleton legacy races keep item-level error codes and release their real witness',async()=>{
 const changes={
  'candidate-added':{status:409,code:'observation_item_conflict'},
  'candidate-removed':{status:409,code:'observation_item_conflict'},
  'journal':{status:503,code:'observation_item_unavailable'},
  'namespace':{status:503,code:'observation_item_unavailable'},
  'expired-witness':{status:503,code:'observation_item_unavailable'},
  'consent':{status:403,code:'access_denied'},
  'reveal':{status:403,code:'access_denied'},
  'session':{status:403,code:'access_denied'},
  'lease':{status:403,code:'access_denied'},
  'consent-after-final-seal':{status:403,code:'access_denied'},
 };
 for(const [change,expected] of Object.entries(changes)){
  const f=fixture();await f.run(async adapter=>{
   const a=await importedWitness(f,adapter,296);
   const other=change==='candidate-added'?await importedWitness(f,adapter,297):null;
   const added=other?f.state.legacySources.pop():null;
   const trace=useActualWitnesses(f,adapter);
   let reads=0,assertions=0;
   const read=adapter.authority.read,owned=adapter.authority.assertOwned;
   adapter.authority.read=async fn=>{reads++;return read(fn);};
   adapter.authority.assertOwned=async()=>{assertions++;return owned();};
   trace.afterSeal=n=>{
    if(n===1){
     if(change==='consent')f.state.enabled=false;
     if(change==='reveal')f.state.revealGranted=false;
     if(change==='session')f.state.liveSessionId=id(999);
     if(change==='lease')f.state.active=false;
     if(change==='candidate-added')f.state.legacySources.push(added);
     if(change==='candidate-removed')f.state.legacySources=[];
     if(change==='journal')f.state.media.get('sms/'+a.saved.sourceId).fingerprint='f'.repeat(64);
     if(change==='namespace')adapter.custody.namespace={origin:'https://different.invalid',bucket:'collect-evidence'};
     if(change==='expired-witness')trace.now+=300001;
    }
    if(n===2&&change==='consent-after-final-seal')f.state.enabled=false;
   };
   await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof]}),expected,change);
   assert.equal(trace.forgotten,1,change);assert.equal(trace.bindings.size,0,change);
   assert.equal(trace.inTransaction,false,change);
   if(expected.code.startsWith('observation_item_')){
    assert.equal(reads,2,`${change}: current context must be rechecked before reporting an item error`);
    assert.equal(assertions,2,`${change}: current request ownership must be rechecked before reporting an item error`);
   }
   // The enclosing synthetic request gate also checks its lease on exit.
   if(change==='lease')f.state.active=true;
  });
 }
});

test('singleton item failures cannot mask revocation or a changed context during error recheck',async()=>{
 for(const change of ['consent','context','lease']){
  const f=fixture();await f.run(async adapter=>{
   const a=await importedWitness(f,adapter,289),trace=useActualWitnesses(f,adapter);
   const read=adapter.authority.read,owned=adapter.authority.assertOwned;let reads=0,assertions=0;
   adapter.authority.read=async fn=>{
    if(++reads===2){if(change==='consent')f.state.enabled=false;if(change==='context')f.state.generation++;}
    return read(fn);
   };
   adapter.authority.assertOwned=async()=>{
    if(++assertions===2&&change==='lease')throw new Error('synthetic revoked lease');
    return owned();
   };
   trace.afterSeal=n=>{if(n===1)f.state.legacySources=[];};
   const expected=change==='consent'?{status:403,code:'access_denied'}:
    change==='context'?{status:409,code:'observation_changed'}:{status:503,code:'observation_unavailable'};
   await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof]}),expected,change);
   assert.equal(reads,2,change);assert.equal(trace.forgotten,1,change);assert.equal(trace.bindings.size,0,change);
  });
 }
});

test('singleton maps a failed item fence but keeps a later batch-wide database failure generic',async()=>{
 for(const failure of ['fence-timeout','fence-denied','later-batch-outage']){
  const f=fixture();await f.run(async adapter=>{
   const a=await importedWitness(f,adapter,290),trace=useActualWitnesses(f,adapter);
   const write=adapter.authority.write,context=adapter.context.bind(adapter);let writes=0,contexts=0;
   adapter.authority.write=async fn=>{
    if(++writes===2&&failure==='fence-timeout')throw sqlError('55P03');
    if(writes===2&&failure==='fence-denied')throw sqlError('42501');
    return write(fn);
   };
   adapter.context=async(...args)=>{
    if(++contexts===4&&failure==='later-batch-outage')throw sqlError('08006');
    return context(...args);
   };
   const expected=failure==='fence-timeout'?{status:503,code:'observation_item_unavailable'}:
    failure==='fence-denied'?{status:403,code:'access_denied'}:{status:503,code:'observation_unavailable'};
   await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof]}),expected,failure);
   assert.equal(trace.forgotten,1,failure);assert.equal(trace.bindings.size,0,failure);
  });
 }
});

test('singleton legacy batch verifies every candidate and denies ambiguous exact matches',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const first=await importedWitness(f,adapter,291);
  await importedWitness(f,adapter,292,{inboxReceivedAt:'2026-11-11T12:00:01.000Z'});
  const trace=useActualWitnesses(f,adapter);
  const result=await adapter.reconcileBatch(actor,{items:[first.proof]});
  assert.equal(result.items[0].sourceId,first.saved.sourceId);
  assert.equal(trace.writes,2);assert.equal(trace.reads,2);assert.equal(trace.seals,4);
  assert.equal(trace.forgotten,1);assert.equal(trace.bindings.size,0);
 });
 const ambiguous=fixture();await ambiguous.run(async adapter=>{
  const first=await importedWitness(ambiguous,adapter,293);
  await importedWitness(ambiguous,adapter,294);
  const trace=useActualWitnesses(ambiguous,adapter);
  await assert.rejects(adapter.reconcileBatch(actor,{items:[first.proof]}),
   e=>e.status===409&&e.code==='observation_item_conflict');
  assert.equal(trace.reads,2);assert.equal(trace.seals,2);
  assert.equal(trace.forgotten,1);assert.equal(trace.bindings.size,0);
 });
});

test('multiple retained legacy items keep their existing complete per-item fences',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const a=await importedWitness(f,adapter,298);
  const b=await importedWitness(f,adapter,299,{rawBody:'Received 299 RWF. Reference: 1299.'});
  const trace=useActualWitnesses(f,adapter);
  const result=await adapter.reconcileBatch(actor,{items:[a.proof,b.proof]});
  assert.deepEqual(result.items.map(item=>item.sourceId),[a.saved.sourceId,b.saved.sourceId]);
  assert.equal(trace.writes,5);assert.equal(trace.reads,2);assert.equal(trace.seals,4);
  assert.equal(trace.forgotten,2);assert.equal(trace.bindings.size,0);
 });
 const mixed=fixture();await mixed.run(async adapter=>{
  const a=await importedWitness(mixed,adapter,300),trace=useActualWitnesses(mixed,adapter);
  const missing={...a.proof,sourceKey:'f'.repeat(64),bodySha256:'e'.repeat(64)};
  const result=await adapter.reconcileBatch(actor,{items:[a.proof,missing]});
  assert.deepEqual(result.items.map(item=>item.state),['matched','missing']);
  assert.equal(trace.writes,3);assert.equal(trace.reads,1);assert.equal(trace.seals,2);
  assert.equal(trace.forgotten,1);assert.equal(trace.bindings.size,0);
 });
});

test('legacy reconciliation reads exact retained live and catch-up SMS without writing or exposing content',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const live=await importedWitness(f,adapter,201,{serviceCentreAt:'2026-11-11T11:59:59.000Z',subscriptionId:3});
  const catchup=await importedWitness(f,adapter,202,{sourceMode:'catch_up',complete:false,
   rawBody:'Received 251 RWF. Reference: 1235.'});
  f.state.pageRows=[{id:live.saved.sourceId,createdAt:now}];
  const before={puts:f.state.puts,commits:f.state.commits,requests:f.state.requests.size,audits:f.state.audits.length};
  const one=await adapter.reconcile(actor,{...live.proof,inboxReceivedAt:'2026-11-11T12:00:00Z'});
  assert.equal(one.state,'matched');assert.equal(one.sourceId,live.saved.sourceId);
  const batch=await adapter.reconcileBatch(actor,{items:[catchup.proof,live.proof]});
  assert.deepEqual(batch.items.map(x=>x.sourceId),[catchup.saved.sourceId,live.saved.sourceId]);
  assert(batch.items.every(x=>x.state==='matched'));
  assert.doesNotMatch(JSON.stringify({one,batch}),/rawBody|raw_sender|object_key|principal|Received/);
  assert.deepEqual({puts:f.state.puts,commits:f.state.commits,requests:f.state.requests.size,audits:f.state.audits.length},before);
 });
});

test('legacy reconciliation rejects ambiguous, missing and imprecise receipt evidence',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const a=await importedWitness(f,adapter,203);
  const wrongTime=await adapter.reconcileBatch(actor,{items:[{...a.proof,inboxReceivedAt:'2026-11-11T12:00:01.000Z'}]});
  assert.equal(wrongTime.items[0].state,'missing');
  const fractional=await adapter.reconcileBatch(actor,{items:[{...a.proof,inboxReceivedAt:'2026-11-11T12:00:00.0001Z'}]});
  assert.equal(fractional.items[0].state,'missing');
  const wrongSender=await adapter.reconcileBatch(actor,{items:[{...a.proof,rawSender:'example money'}]});
  assert.equal(wrongSender.items[0].state,'missing');
  await assert.rejects(adapter.reconcileBatch(actor,{items:[{...a.proof,inboxReceivedAt:null}]}),e=>e.status===400);
  await importedWitness(f,adapter,204);
  await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof]}),e=>e.status===409&&e.code==='observation_item_conflict');
 });
 const missing=fixture();await missing.run(async adapter=>{
  const a=await importedWitness(missing,adapter,205,{inboxReceivedAt:null});
  await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof]}),e=>e.status===503&&e.code==='observation_item_unavailable');
 });
});

test('legacy lookup enforces account, reveal, consent and one-to-one source matching',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const a=await importedWitness(f,adapter,206);
  f.state.legacySources[0].accountId=id(999);
  assert.equal((await adapter.reconcileBatch(actor,{items:[a.proof]})).items[0].state,'missing');
  f.state.legacySources[0].accountId=account;f.state.legacySources[0].collectionId='foreign';
  assert.equal((await adapter.reconcileBatch(actor,{items:[a.proof]})).items[0].state,'missing');
  f.state.legacySources[0].collectionId=group;f.state.revealGranted=false;
  await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof]}),e=>e.status===403);
  f.state.revealGranted=true;
  await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof,{...a.proof,sourceKey:'f'.repeat(64)}]}),
   e=>e.status===409&&e.code==='observation_item_conflict');
  f.state.enabled=false;await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof]}),e=>e.status===403);
 });
});

test('legacy reconciliation fails closed on object, custody and post-read authority changes',async()=>{
 for(const change of ['object','ciphertext','key','custody','reveal','consent','generation','candidate','candidate-added']){
  const f=fixture();await f.run(async adapter=>{
   const a=await importedWitness(f,adapter,207);
   const added=change==='candidate-added'?await importedWitness(f,adapter,208):null;
   const addedSource=added?f.state.legacySources.pop():null;
   const before={puts:f.state.puts,commits:f.state.commits,requests:f.state.requests.size,audits:f.state.audits.length};
   f.state.onGet=async()=>{
    if(change==='object')f.state.media.delete('sms/'+a.saved.sourceId);
    if(change==='ciphertext')f.state.media.get('sms/'+a.saved.sourceId).sealed='invalid ciphertext';
    if(change==='key'){
     const media=f.state.media.get('sms/'+a.saved.sourceId),envelope=JSON.parse(media.sealed);
     media.sealed=JSON.stringify({...envelope,kid:'unavailable-key'});
    }
    if(change==='custody')f.state.media.get('sms/'+a.saved.sourceId).fingerprint='f'.repeat(64);
    if(change==='reveal')f.state.revealGranted=false;
    if(change==='consent')f.state.enabled=false;
    if(change==='generation')f.state.generation++;
    if(change==='candidate')f.state.legacySources=[];
    if(change==='candidate-added')f.state.legacySources.push(addedSource);
   };
   await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof]}),e=>[403,409,503].includes(e.status));
   assert.deepEqual({puts:f.state.puts,commits:f.state.commits,requests:f.state.requests.size,audits:f.state.audits.length},before);
  });
 }
});

test('legacy candidate and request bounds fail closed before unbounded reads',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const sources=[];for(let n=210;n<215;n++)sources.push(await importedWitness(f,adapter,n));
  await assert.rejects(adapter.reconcileBatch(actor,{items:[sources[0].proof]}),
   e=>e.status===503&&e.code==='observation_item_unavailable');
  f.state.legacySources.pop();let reads=0;f.state.onGet=async()=>{reads++;};
  const items=Array.from({length:6},(_,i)=>({...sources[0].proof,sourceKey:(300+i).toString(16).padStart(64,'0')}));
  await assert.rejects(adapter.reconcileBatch(actor,{items}),e=>e.status===503&&e.code==='observation_item_unavailable');
  assert.equal(reads,0);
 });
});

test('batch reconciliation verifies encrypted objects in request order without page or writes',async()=>{
 const f=fixture(),a=await batchWitness(1),b=await batchWitness(2),c=await batchWitness(3);
 await f.run(async adapter=>{
  const first=await adapter.observe(actor,a.item),third=await adapter.observe(actor,c.item);
  f.state.revealGranted=false;
  const keyed=await adapter.reconcileBatch(actor,{items:[c.proof,a.proof]});
  assert(keyed.items.every(item=>item.state==='matched'));
  await assert.rejects(adapter.reconcileBatch(actor,{items:[b.proof]}),e=>e.status===403);
  f.state.revealGranted=true;
  const result=await adapter.reconcileBatch(actor,{items:[c.proof,b.proof,a.proof]});
  assert.deepEqual(result,{groupId:group,items:[{sourceKey:c.proof.sourceKey,state:'matched',sourceId:third.sourceId},
   {sourceKey:b.proof.sourceKey,state:'missing',sourceId:null},{sourceKey:a.proof.sourceKey,state:'matched',sourceId:first.sourceId}]});
  assert.equal(f.state.puts,2);assert.equal(f.state.commits,2);assert.equal(f.state.pageReadCount,undefined);
  assert.doesNotMatch(JSON.stringify(result),/rawBody|object_key|principal|Received/);
  await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof,a.proof]}),e=>e.status===400);
  await assert.rejects(adapter.reconcileBatch(actor,{items:[]}),e=>e.status===400);
 });
});

test('a batch fails closed for per-item conflicts, reservations, storage failure and unauthorized actors',async()=>{
 const f=fixture(),a=await batchWitness(4),b=await batchWitness(5),missing=await batchWitness(6);
 await f.run(async adapter=>{
  const savedA=await adapter.observe(actor,a.item),savedB=await adapter.observe(actor,b.item);
  const proofs={items:[a.proof,b.proof,missing.proof]};
  await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof,{...b.proof,bodySha256:'f'.repeat(64)}]}),e=>e.status===409&&e.code==='observation_item_conflict');
  f.state.rows.delete(savedB.sourceId);
  await assert.rejects(adapter.reconcileBatch(actor,proofs),e=>e.status===503&&e.code==='observation_item_unavailable');
  f.state.rows.set(savedB.sourceId,f.state.row);
  const encrypted=f.state.media.get('sms/'+savedA.sourceId);f.state.media.delete('sms/'+savedA.sourceId);
  await assert.rejects(adapter.reconcileBatch(actor,proofs),e=>e.status===503&&e.code==='observation_item_unavailable');
  f.state.media.set('sms/'+savedA.sourceId,{...encrypted,sealed:'invalid ciphertext'});
  await assert.rejects(adapter.reconcileBatch(actor,proofs),e=>e.status===503&&e.code==='observation_unavailable');
  f.state.media.set('sms/'+savedA.sourceId,encrypted);
  f.state.onGet=async()=>{throw new Error('synthetic transport outage');};
  await assert.rejects(adapter.reconcileBatch(actor,proofs),e=>e.status===503&&e.code==='observation_unavailable');
  f.state.onGet=null;
  const session=adapter.authority.session;
  for(const changed of [{role:'staff'},{installationProfile:'staff'},{groupId:'other'},{revoked:true}]){
   adapter.authority.session=async()=>({...actor,...changed});
   await assert.rejects(adapter.reconcileBatch(actor,proofs),e=>e.status===403);
  }
  adapter.authority.session=session;f.state.enabled=false;
  await assert.rejects(adapter.reconcileBatch(actor,proofs),e=>e.status===403);
  assert.equal(f.state.puts,2);assert.equal(f.state.commits,2);
 });
});

test('a full batch serializes retained storage reads',async()=>{
 const f=fixture(),witnesses=await Promise.all(Array.from({length:20},(_,i)=>batchWitness(20+i)));
 await f.run(async adapter=>{
  for(const witness of witnesses)await adapter.observe(actor,witness.item);
  let active=0,high=0;
  f.state.onGet=async()=>{active++;high=Math.max(high,active);await new Promise(resolve=>setTimeout(resolve,5));active--;};
  const result=await adapter.reconcileBatch(actor,{items:witnesses.map(w=>w.proof)});
  assert.equal(result.items.length,20);assert(result.items.every(x=>x.state==='matched'));
  assert.equal(high,1);assert.equal(f.state.puts,20);assert.equal(f.state.commits,20);
 });
});

test('mixed keyed and legacy witnesses do not contend with their own custody and storage locks',async()=>{
 const f=fixture(),keyedA=await batchWitness(71),keyedB=await batchWitness(72);
 await f.run(async adapter=>{
  const legacyA=await importedWitness(f,adapter,301,{rawBody:'Received 301 RWF. Reference: 1301.'});
  const legacyB=await importedWitness(f,adapter,302,{rawBody:'Received 302 RWF. Reference: 1302.'});
  const savedA=await adapter.observe(actor,keyedA.item),savedB=await adapter.observe(actor,keyedB.item);
  const before={puts:f.state.puts,commits:f.state.commits,requests:f.state.requests.size,audits:f.state.audits.length};
  let busy=false,collisions=0,operations=0;
  const locked=async fn=>{
   if(busy){collisions++;throw sqlError('55P03','synthetic mutation lock timeout');}
   busy=true;operations++;
   try{await new Promise(resolve=>setTimeout(resolve,3));return await fn();}finally{busy=false;}
  };
  const originalWrite=adapter.authority.write;
  adapter.authority.write=fn=>locked(()=>originalWrite(fn));
  f.state.onGet=()=>locked(async()=>{});
  const result=await adapter.reconcileBatch(actor,{items:[legacyA.proof,keyedA.proof,legacyB.proof,keyedB.proof]});
  assert.deepEqual(result.items.map(x=>x.sourceId),[legacyA.saved.sourceId,savedA.sourceId,legacyB.saved.sourceId,savedB.sourceId]);
  assert(result.items.every(x=>x.state==='matched'));assert.equal(collisions,0);assert(operations>=9);assert.equal(busy,false);
  assert.deepEqual({puts:f.state.puts,commits:f.state.commits,requests:f.state.requests.size,audits:f.state.audits.length},before);
 });
});

test('a concurrent storage outage cannot be masked by an item-specific failure',async()=>{
 const f=fixture(),a=await batchWitness(50),b=await batchWitness(51);
 await f.run(async adapter=>{
  const first=await adapter.observe(actor,a.item);await adapter.observe(actor,b.item);
  f.state.media.delete('sms/'+first.sourceId);let calls=0;
  f.state.onGet=async()=>{if(++calls===2){await new Promise(resolve=>setTimeout(resolve,5));throw new Error('network outage');}};
  await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof,b.proof]}),
   e=>e.status===503&&e.code==='observation_unavailable');
 });
});

test('batch can verify the same retained source after a legitimate session rotation',async()=>{
 const f=fixture(),w=await batchWitness(42);
 await f.run(async adapter=>{
  const saved=await adapter.observe(actor,w.item);
  assert.equal(f.state.row.sessionId,session);
  const rotated={...actor,sessionId:id(777)};f.state.liveSessionId=rotated.sessionId;
  const result=await adapter.reconcileBatch(rotated,{items:[w.proof]});
  assert.deepEqual(result,{groupId:group,items:[{sourceKey:w.proof.sourceKey,state:'matched',sourceId:saved.sourceId}]});
  assert.equal(f.state.row.sessionId,session); // Historic stored row is unchanged.
 });
});

test('collection status validates scope, count, custody uncertainty and authority',async()=>{
 const f=fixture();await f.run(async adapter=>{
  assert.deepEqual(await adapter.reconcileStatus(actor),{groupId:group,hasPending:true,hasRecorded:false,
   recordedCount:0,hasUnmatchedCanonical:false,revision:'f'.repeat(64)});
  assert.deepEqual(await adapter.reconcileVerifiedStatus(actor),{groupId:group,hasPending:false,hasRecorded:false,
   recordedCount:0,hasUnmatchedCanonical:false,revision:'f'.repeat(64),scope:'verified_collection'});
  assert.deepEqual(f.state.statusCalls,['legacy','verified']);
  f.state.reconcileStatus={groupId:group,hasPending:true,hasRecorded:true,recordedCount:2,
   hasUnmatchedCanonical:true,revision:'e'.repeat(64),privateValue:'not returned'};
  const actual=await adapter.reconcileStatus(actor);assert.equal(actual.hasPending,true);
  assert.equal(actual.hasUnmatchedCanonical,true);assert.equal(actual.recordedCount,2);assert(!Object.hasOwn(actual,'privateValue'));
  assert.deepEqual(await adapter.reconcileVerifiedStatus(actor),{...actual,scope:'verified_collection'});
  for(const changed of [{groupId:'other'},{revision:'bad'},{recordedCount:100001},{hasRecorded:false}]){
   const previous=f.state.reconcileStatus;f.state.reconcileStatus={...previous,...changed};
   await assert.rejects(adapter.reconcileStatus(actor),e=>e.status===503);f.state.reconcileStatus=previous;
  }
  f.state.enabled=false;await assert.rejects(adapter.reconcileStatus(actor),e=>e.status===403);
  await assert.rejects(adapter.reconcileVerifiedStatus(actor),e=>e.status===403);
  assert.equal(f.state.puts,0);assert.equal(f.state.commits,0);
 });
});

test('verified collection status denies staff, changed group and revoked or disabled consent',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const session=adapter.authority.session;
  for(const changed of [{role:'staff'},{installationProfile:'staff'},{groupId:'other'},{revoked:true},{active:false}]){
   adapter.authority.session=async()=>({...actor,...changed});
   await assert.rejects(adapter.reconcileVerifiedStatus(actor),e=>e.status===403);
  }
  assert.deepEqual(f.state.statusCalls??[],[]);
  adapter.authority.session=session;f.state.enabled=false;
  await assert.rejects(adapter.reconcileVerifiedStatus(actor),e=>e.status===403);
  assert.deepEqual(f.state.statusCalls??[],[]);
 });
});

test('batch rechecks consent and every key after storage reads before publishing',async()=>{
 for(const change of ['consent','generation','missing-becomes-pending','matched-disappears']){
  const f=fixture(),a=await batchWitness(7),b=await batchWitness(8);
  await f.run(async adapter=>{
   const saved=await adapter.observe(actor,a.item);
   const content=await observationContentFingerprint(b.proof,b.proof.bodySha256);
   f.state.onGet=async()=>{
    if(change==='consent')f.state.enabled=false;
    if(change==='generation')f.state.generation++;
    if(change==='missing-becomes-pending')f.state.sourceKeys.set(b.proof.sourceKey,{content,body:b.proof.bodySha256,sourceId:id(900)});
    if(change==='matched-disappears')f.state.rows.delete(saved.sourceId);
   };
   await assert.rejects(adapter.reconcileBatch(actor,{items:[a.proof,b.proof]}),e=>[403,409,503].includes(e.status));
   assert.equal(f.state.puts,1);assert.equal(f.state.commits,1);
  });
 }
});

test('new unkeyed native catch-up stays pending instead of bypassing deduplication',async()=>{
 const f=fixture(),catchup={...incoming,sourceMode:'catch_up',complete:false,inboxReceivedAt:'2026-11-11T12:00:00.000Z'};
 f.state.allowLegacyFixture=false;
 await f.run(async adapter=>{await assert.rejects(adapter.observe(actor,catchup),e=>e.status===503);assert.equal(f.state.puts,0);});
});
test('new unkeyed native live capture is also held without affecting the managed gateway',async()=>{
 const f=fixture();f.state.allowLegacyFixture=false;
 await f.run(async adapter=>{await assert.rejects(adapter.observe(actor,incoming),e=>e.status===503);assert.equal(f.state.puts,0);});
});

test('a multiline sender message is retained and revealed without changing its bytes',async()=>{
 const f=fixture(),message={...incoming,rawBody:'Received 250 RWF.\nReference:\t1234.\r\nThank you.'};
 await f.run(async adapter=>{
  const ack=await adapter.observe(actor,message);
  const revealed=await adapter.reveal(actor,ack.sourceId,{reason:'Inspect source message',requestId:id(9)});
  assert.equal(revealed.rawBody,message.rawBody);assert.equal(ack.bodySha256,await sha256(message.rawBody));
 });
});

test('a lost commit reply reconciles instead of writing or sending twice',async()=>{
 const f=fixture();f.state.lostCommit=true;
 await f.run(async adapter=>{const result=await adapter.observe(actor,incoming);assert.equal(result.requestId,incoming.requestId);
  assert.equal(f.state.commits,1);assert.equal(f.state.puts,1);});
});

test('revoking consent after storage prevents commit and acknowledgment',async()=>{
 const f=fixture();f.state.onPut=async()=>{f.state.enabled=false;f.state.generation=2;};
 await f.run(async adapter=>await assert.rejects(adapter.observe(actor,incoming),e=>e.status===403));
 assert.equal(f.state.puts,1);assert.equal(f.state.commits,0);assert.equal(f.state.row,null);
});

test('unconfirmed uploads have a bounded per-owner admission and exact retries reuse it',async()=>{
 const f=fixture();f.state.onPut=async()=>{throw new Error('synthetic unknown storage outcome');};
 await f.run(async adapter=>{
  for(let n=20;n<36;n++)await assert.rejects(adapter.observe(actor,{...incoming,requestId:id(n)}),e=>e.status===503);
  assert.equal(f.state.requests.size,16);assert.equal(f.state.puts,16);
  await assert.rejects(adapter.observe(actor,{...incoming,requestId:id(36)}),e=>e.status===429);
  assert.equal(f.state.puts,16);
  f.state.onPut=null;const ack=await adapter.observe(actor,{...incoming,requestId:id(20)});
  assert.equal(ack.requestId,id(20));assert.equal(f.state.requests.size,16);assert.equal(f.state.commits,1);
 });
});

test('own raw disclosure requires revalidated reveal authority and a committed audit',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const ack=await adapter.observe(actor,incoming),reason='Review synthetic source';
  const first=await adapter.reveal(actor,ack.sourceId,{reason,requestId:id(6)});
  assert.equal(first.rawBody,incoming.rawBody);assert.equal(first.financialEffects,0);assert.equal(f.state.audits.length,1);
  assert.equal(JSON.stringify(f.state.audits).includes(incoming.rawBody),false);
  f.state.onPrefetch=async()=>{f.state.revealGranted=false;};
  await assert.rejects(adapter.reveal(actor,ack.sourceId,{reason,requestId:id(7)}),e=>e.status===403);
  assert.equal(f.state.audits.length,1);
 });
});

test('unknown audit commit returns no plaintext success',async()=>{
 const f=fixture();await f.run(async adapter=>{
  const ack=await adapter.observe(actor,incoming);f.state.lostAudit=true;
  await assert.rejects(adapter.reveal(actor,ack.sourceId,{reason:'Review synthetic source',requestId:id(8)}),e=>e.status===503);
  assert.equal(f.state.audits.length,1);
 });
});

async function hintProof(){return {profileSha256:await sha256(profileJson),profile:{provider:'mtn_momo',status:'active',
 profile_status:'approved',profile_version:'synthetic-v1',profile_json:profileJson,currency:'RWF',timezone:'Africa/Kigali'}};}
const inbox={...incoming,rawBody:'Received 250 RWF. Reference: 1234. Thank you.',sourceMode:'catch_up',complete:false,
 inboxReceivedAt:'2026-11-11T12:00:00.000Z',sourceKey:'a'.repeat(64)};
test('opt-in partial hints are profile-bound, audited quotations with no financial effect',async()=>{
 const f=fixture();f.env.BURIMUNSI_OBSERVATION_HINTS_ENABLED='true';f.state.hintProfile=await hintProof();
 await f.run(async adapter=>{const capture=await adapter.observe(actor,inbox);
  const result=await adapter.reveal(actor,capture.sourceId,{requestId:id(30),reason:'Review this source',displayHintsVersion:1});
  assert.equal(result.financialEffects,0);assert.equal(result.displayHints.kind,'partial_inbox_display_only');
  assert.equal(result.displayHints.profileSha256,f.state.hintProfile.profileSha256);assert.equal(result.displayHints.bodySha256,capture.bodySha256);
  assert.equal(f.state.audits.length,1);assert.ok(result.displayHints.hints.length>0);
  for(const hint of result.displayHints.hints)assert.equal(result.rawBody.slice(hint.start,hint.end),hint.text);
 });
});
test('missing, changed, disabled or mismatched hint profiles do not suppress audited raw reveal',async()=>{
 for(const mode of ['disabled','missing','changed','wrong_hash','version_control']){
  const f=fixture();f.env.BURIMUNSI_OBSERVATION_HINTS_ENABLED=mode==='disabled'?'false':'true';
  f.state.hintProfile=mode==='missing'?null:await hintProof();
  if(mode==='wrong_hash')f.state.hintProfile.profileSha256='0'.repeat(64);
  if(mode==='version_control')f.state.hintProfile.profile.profile_version='synthetic\u0085v1';
  if(mode==='changed')f.state.onPrefetch=()=>{f.state.hintProfile=null;};
  await f.run(async adapter=>{const capture=await adapter.observe(actor,inbox);
   const result=await adapter.reveal(actor,capture.sourceId,{requestId:id(31),reason:'Review this source',displayHintsVersion:1});
   assert.equal(result.displayHints,null,mode);assert.equal(result.rawBody,inbox.rawBody);assert.equal(f.state.audits.length,1);
  });
 }
});
test('legacy reveal omits hint fields and completed live messages produce no partial hint',async()=>{
 const f=fixture();f.env.BURIMUNSI_OBSERVATION_HINTS_ENABLED='true';f.state.hintProfile=await hintProof();
 await f.run(async adapter=>{const capture=await adapter.observe(actor,incoming);
  const old=await adapter.reveal(actor,capture.sourceId,{requestId:id(32),reason:'Review this source'});
  assert.equal(Object.hasOwn(old,'displayHints'),false);
  const requested=await adapter.reveal(actor,capture.sourceId,{requestId:id(33),reason:'Review this source',displayHintsVersion:1});
  assert.equal(requested.displayHints,null);
 });
});

test('a profile tuple change before admission rejects capture before object upload',async()=>{
 const f=fixture();f.state.tupleChangedOnPrepare=true;
 await f.run(async adapter=>{await assert.rejects(adapter.observe(actor,inbox),e=>e.status===409);});
 assert.equal(f.state.puts,0);assert.equal(f.state.commits,0);
});

test('unresolved upload stays pending and returns a retryable status instead of an access denial',async()=>{
 const f=fixture();f.state.onPut=()=>{f.state.uploadUnresolved=true;};
 await f.run(async adapter=>{await assert.rejects(adapter.observe(actor,inbox),e=>e instanceof ObservationUploadUnresolved&&e.requestId===inbox.requestId);});
 assert.equal(f.state.puts,1);assert.equal(f.state.commits,0);assert.equal(f.state.requests.size,1);
});

test('a durable unknown PUT is request-bound and the exact retry makes no second provider call',async()=>{
 const f=fixture();f.state.onPut=()=>{f.state.uploadUnresolved=true;throw new Error('synthetic unknown PUT');};
 await f.run(async adapter=>{
  for(let i=0;i<2;i++)await assert.rejects(adapter.observe(actor,inbox),e=>
   e instanceof ObservationUploadUnresolved&&e.status===503&&e.requestId===inbox.requestId&&!JSON.stringify(e).includes(inbox.rawBody));
  assert.equal(f.state.puts,1);assert.equal(f.state.requests.size,1);assert.equal(f.state.row,null);assert.equal(f.state.commits,0);
  await assert.rejects(adapter.observe(actor,{...inbox,rawBody:'Received 251 RWF. Reference: 1234.'}),e=>e.status===409);
 });
});

for(const [label,tamper] of [
 ['different owner',r=>r.scope={...r.scope,ownerId:'another-principal'}],
 ['different reservation scope',r=>r.reservation_scope={...r.reservation_scope,entityId:id(99)}],
 ['missing retained ciphertext',r=>r.reservation_present=false],
 ['changed ciphertext',r=>r.reservation_cipher_sha256='e'.repeat(64)],
 ['changed ciphertext length',r=>r.reservation_cipher_size++],
 ['changed request fingerprint',r=>r.source_fingerprint='e'.repeat(64)],
 ['changed plaintext digest',r=>r.plaintext_sha256='e'.repeat(64)],
 ['changed operation identity',r=>r.operation_id='e'.repeat(64)],
 ['changed object fingerprint',r=>r.fingerprint='e'.repeat(64)],
 ['changed AAD',r=>r.aad+='changed'],
 ['invalid key identity',r=>r.key_id='bad/key'],
 ['changed metadata',r=>r.custom_metadata={...r.custom_metadata,source_fingerprint:'e'.repeat(64)}],
 ['delete intent',r=>r.has_delete=true],['tombstone',r=>r.delete_tombstone=true],
 ['unverified committed metadata',r=>{r.state='committed';r.metadata_present=true;r.metadata_matches=false;}],
 ['inconsistent pending metadata',r=>{r.state='pending';r.metadata_present=true;}]
])test('unresolved PUT status refuses '+label,async()=>{
 const f=fixture();f.state.onPut=()=>{f.state.uploadUnresolved=true;throw new Error('synthetic unknown PUT');};f.state.tamperStatus=tamper;
 await f.run(async adapter=>await assert.rejects(adapter.observe(actor,inbox),e=>
  e.status===503&&e.code==='observation_unavailable'&&!(e instanceof ObservationUploadUnresolved)));
 assert.equal(f.state.commits,0);assert.equal(f.state.row,null);
});

test('in-flight-only and missing journal outcomes remain generic; revoked consent remains denied',async()=>{
 for(const mode of ['active_only','missing_intent','consent_revoked']){
  const f=fixture();f.state.onPut=()=>{
   if(mode!=='active_only')f.state.uploadUnresolved=true;
   if(mode==='missing_intent')f.state.missingIntent=true;
   if(mode==='consent_revoked')f.state.enabled=false;
   throw new Error('synthetic unknown PUT');
  };
  if(mode==='active_only')f.state.tamperStatus=r=>{r.active_attempt=id(90);};
  await f.run(async adapter=>await assert.rejects(adapter.observe(actor,inbox),e=>
   mode==='consent_revoked'?e.status===403:e.status===503&&e.code==='observation_unavailable'));
  assert.equal(f.state.commits,0);assert.equal(f.state.row,null);
 }
});
