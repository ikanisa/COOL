// ROOT EXECUTOR ONLY. Original native Allocate on actual disposable PG using
// existing opaque native session and current financial guards. No real PIN,
// provider/storage upload, network port, receiver, SMS or production actor.
import assert from 'node:assert/strict';
import {registerHooks} from 'node:module';
import {writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fixturePool} from './psql-fixture-transport.mjs';
registerHooks({resolve(specifier,context,next){
 if(specifier==='npm:postgres@3.4.7')return {url:'data:text/javascript,export default function(){throw Error("Use owned isolated fixture transport")}',shortCircuit:true};
 return next(specifier,context);
}});
const {PostgresDatabase}=await import('../../functions/_shared/postgres.js');
const {openApplicationWork,sqlFenceBackend,applicationWorkTuple}=await import('../../functions/_shared/application-fence.js');
const {createPhonePinRequestGate}=await import('../../functions/_shared/domain/burimunsi/phone-pin-request.js');
const {PostgresNativeAuthStore}=await import('../../functions/_shared/domain/burimunsi/postgres-auth-store.js');
const {PostgresPhonePinSessions}=await import('../../functions/_shared/domain/burimunsi/postgres-phone-pin-sessions.js');
const {PostgresOperatorDirectory}=await import('../../functions/_shared/domain/burimunsi/postgres-operator-directory.js');
const {PostgresIdentityDirectory}=await import('../../functions/_shared/domain/burimunsi/postgres-identity-directory.js');
const {PostgresPostingAuthority}=await import('../../functions/_shared/domain/burimunsi/postgres-posting-authority.js');
const {PostgresPostingCustody}=await import('../../functions/_shared/domain/burimunsi/postgres-posting-custody.js');
const {PostgresPostingAllocation}=await import('../../functions/_shared/domain/burimunsi/postgres-posting-allocation.js');
const {PostgresSharedPosting}=await import('../../functions/_shared/domain/burimunsi/postgres-shared-posting.js');
const {PostgresCanonicalStore}=await import('../../functions/_shared/domain/burimunsi/postgres-canonical-store.js');
const {ContributionService}=await import('../../functions/_shared/domain/burimunsi/contribution-service.js');
const {PostgresStorageWitnesses}=await import('../../functions/_shared/domain/burimunsi/postgres-storage-witnesses.js');
const {PostgresPostingPreparation}=await import('../../functions/_shared/domain/burimunsi/postgres-posting-preparation.js');
const {postingEvidenceDescriptor}=await import('../../functions/_shared/domain/burimunsi/posting-preparation.js');
const {canonicalJson,sha256}=await import('../../functions/_shared/domain/burimunsi/values.js');
const {encrypt,decrypt}=await import('../../functions/_shared/domain/encryption.js');
let inputText='';for await(const bytes of process.stdin){inputText+=bytes;if(inputText.length>2*1024*1024)throw Error('fixture_input_too_large');}
const input=JSON.parse(inputText),trace=[];
const pool=fixturePool({...input,record:value=>trace.push(value)});
const group='buri-qualification-group',source='fc940000-0000-4000-8000-000000000010';
const member='fc940000-0000-4000-8000-000000000003',installation='fc940000-0000-4000-8000-000000000002';
const nativeSession='fc940000-0000-4000-8000-000000000004',account='f7000000-0000-4000-8000-000000000001';
const principal='f3000000-0000-4000-8000-000000000001',requestId='fc940000-0000-4000-8000-000000000020';
const cryptoEnv={DATA_KEY_ID:'qualification-adoption',DATA_ENCRYPTION_KEY:Buffer.alloc(32,52).toString('base64')};
const namespace={origin:'https://qualification-storage.invalid',bucket:'qualification-adoption'};
const enc=new TextEncoder(),hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const quote=value=>"'"+String(value).replaceAll("'","''")+"'";
const denied=()=>{throw Error('Fixture never authorizes an automatic or unrelated command');};
const encryptedObjects=new Map(),fixtureMediaCalls={reads:0,writes:0};
function retainFixtureObject(key,sealed,httpMetadata,customMetadata){
 assert(!encryptedObjects.has(key),'Never overwrite fixture ciphertext');
 encryptedObjects.set(key,Object.freeze({sealed,size:Buffer.byteLength(sealed),sha256:hash(sealed),
  httpMetadata:structuredClone(httpMetadata),customMetadata:structuredClone(customMetadata)}));
}
const result={format:'collect.burimunsi.adopted-native-allocation.actual-pg.v1',status:'fail',
 production_acceptance:false,gotrue_exercised:false,provider_calls:0,real_sms_or_phone:false,
 custody_mode:'original custody, preparation and encrypted witnesses; test-only in-memory object transport, no Storage/provider acceptance claim'};
let admin,work;
try{
 assert.equal(input.kind,'http_collect');assert.match(input.admission,/^[a-f0-9-]{36}$/);assert.match(input.sourceSha256,/^[a-f0-9]{64}$/);
 admin=await pool.reserve();
 const setup=input.template.split('-- __ADOPTION_CASES__')[0];
 assert(setup.includes('pg_temp.adoption_capture')&&setup.includes('pg_temp.adoption_finish'));
 const rawFingerprint=hash('qualification-adoption-original:'+source),rawSha=hash(input.payload);
 const rawSealed=await encrypt(cryptoEnv,enc.encode(input.payload),'sms:'+source+':'+rawSha);
 retainFixtureObject('sms/'+source,rawSealed,{contentType:'application/octet-stream'},
  {sha256:rawSha,key_id:cryptoEnv.DATA_KEY_ID,source_fingerprint:rawFingerprint});
 // The real application-commit guard validates these staged journal rows and
 // scrubs reservation bytes. Only the fixture object transport keeps ciphertext.
 await admin.fixtureScript(setup+`\nSELECT pg_temp.adoption_capture('${source}',false,true,'adoption-key',NULL,${quote(rawSealed)},${quote(cryptoEnv.DATA_KEY_ID)});
  SELECT pg_temp.adoption_finish('${source}','QUALIFICATION lease');COMMIT;`);
 await admin.unsafe("SELECT set_config('burimunsi.collection_id',$1,false)",[group]);
 const metadata=(await admin.unsafe(`SELECT t.id,t.version,x.*,r.object_sha256,r.body_sha256 FROM app.momo_transactions t
  JOIN private.burimunsi_transaction_scopes x ON x.transaction_id=t.id JOIN app.momo_transaction_sources s
  ON s.transaction_id=t.id AND s.parse_attempt_id=t.parse_attempt_id AND s.relation='accepted'
  JOIN app.sms_receipts r ON r.id=s.raw_sms_id WHERE r.id=$1`,[source]))[0];
 assert(metadata);assert.equal(metadata.policy_version,'canonical.manual.v1');
 const transaction=metadata.id,scopeBefore=await admin.unsafe('SELECT * FROM private.burimunsi_transaction_scopes WHERE transaction_id=$1',[transaction]);
 assert.equal(hash(input.payload),metadata.object_sha256);assert.equal(hash(input.body),metadata.body_sha256);
 assert.equal((await admin.unsafe('SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key=$1',['sms/'+source]))[0].sealed_body,null);
 // A distinct original native command gets its OWN real durable admission,
 // persistent SQL WORK lease and original close/readback implementation. The
 // Python-owned producer admission remains held independently by its owner.
 work=await openApplicationWork({sourceSha256:input.sourceSha256,kind:input.kind,
  backend:sqlFenceBackend(pool,pool)});
 const db=new PostgresDatabase(pool,{},work),sessions=new PostgresPhonePinSessions({db,groupId:group});
 const directory=new PostgresOperatorDirectory({db,groupId:group,managedSessions:sessions});
 const auth=new PostgresNativeAuthStore({db,groupId:group,createOperatorPrincipal:denied,sessionBinding:sessions,operatorDirectory:directory});
 // This bounded transport supplies exact synthetic encrypted objects only.
 // All witness capability, hash/journal, custody, PIN authority and financial
 // checks are the ORIGINAL production implementations, with no qualification
 // mode, reservation rehydration or external bucket/provider claim.
 const media={namespace,async get(key){
  fixtureMediaCalls.reads++;const value=encryptedObjects.get(key);assert(value,'Expected fixture ciphertext only');
  return {key,size:value.size,sha256:value.sha256,httpMetadata:structuredClone(value.httpMetadata),
   customMetadata:structuredClone(value.customMetadata),arrayBuffer:async()=>enc.encode(value.sealed).buffer};
 },async put(key,sealed,options){
  fixtureMediaCalls.writes++;assert.equal(fixtureMediaCalls.writes,1,'Exactly one preparation object');
  const plain=await decrypt(cryptoEnv,sealed,options.aad),plainSha=hash(plain);plain.fill(0);
  const keyId=JSON.parse(sealed).kid;assert.equal(keyId,cryptoEnv.DATA_KEY_ID);assert.equal(plainSha,options.customMetadata.sha256);
  const descriptor=postingEvidenceDescriptor({contractVersion:1,requestDigest:options.sourceDigest,
   evidenceId:options.scope.entityId,ownerId:options.scope.ownerId,objectKey:key},plainSha,keyId);
  assert.deepEqual(descriptor.scope,options.scope);assert.equal(descriptor.aad,options.aad);
  assert.deepEqual(descriptor.httpMetadata,options.httpMetadata);assert.deepEqual(descriptor.customMetadata,options.customMetadata);
  const fingerprint=await sha256(canonicalJson(descriptor)),custom={...options.customMetadata,source_fingerprint:fingerprint};
  retainFixtureObject(key,sealed,options.httpMetadata,custom);
  const value=encryptedObjects.get(key),operation='qualification-adoption:'+key;
  // Test object transport mirrors existing verified fixture journal staging.
  // It uses the REAL admitted native transaction and reads its positive SQL ACK.
  return auth.write(async sql=>{
   await sql.unsafe(`INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
    VALUES($1,$2,$3::jsonb,$4,$5,$6,$7)`,[key,fingerprint,options.scope,options.aad,keyId,plainSha,sealed]);
   await sql.unsafe(`INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
    VALUES($1,$2,$3,$4,$5,$6::jsonb,$7::jsonb,$8::jsonb,'committed')`,[operation,key,fingerprint,value.sha256,value.size,options.scope,options.httpMetadata,custom]);
   await sql.unsafe(`INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
    VALUES($1,$2,$3,$4,$5,$6::jsonb,$7::jsonb,$8::jsonb)`,[key,operation,fingerprint,value.sha256,value.size,options.scope,options.httpMetadata,custom]);
   const ack=(await sql.unsafe('SELECT operation_id,sha256,size,state FROM private.storage_put_intents WHERE object_key=$1',[key]))[0];
   assert.equal(ack.operation_id,operation);assert.equal(ack.sha256,value.sha256);assert.equal(Number(ack.size),value.size);assert.equal(ack.state,'committed');
   return {stored:true,metadataCommitted:true,key,operationId:ack.operation_id,sha256:ack.sha256,size:Number(ack.size)};
  });
 }};
 const storageWitnesses=new PostgresStorageWitnesses({db,groupId:group,namespace,media,applicationWorkTuple});
 const custody=new PostgresPostingCustody({db,groupId:group,namespace,decrypt:(_,aad)=>decrypt(cryptoEnv,_,aad),storageWitnesses});
 const allocation=new PostgresPostingAllocation({db,groupId:group,custody}),runtime=new PostgresPostingAuthority({authority:auth});
 const posting=new PostgresSharedPosting({db,groupId:group,runtime,allocation,evidence:custody});
 const store=new PostgresCanonicalStore({authority:auth,groupId:group,
  commands:{postContribution:(...args)=>posting.postContribution(...args),createDirectMember:denied,setMembershipActive:denied,enqueueEligibleRematch:denied},
  identities:new PostgresIdentityDirectory({db,groupId:group}),jobs:{assertPostingLease:denied}});
 const preparation=new PostgresPostingPreparation({authority:auth,posting,allocation,media,
  encrypt:(bytes,aad)=>encrypt(cryptoEnv,bytes,aad),keyId:cryptoEnv.DATA_KEY_ID});
 const service=new ContributionService({store,groupId:group,preparation});
 const gate=createPhonePinRequestGate({secrets:{},networkBucket:denied});
 const invoke=id=>gate({request:new Request('https://qualification-api.invalid/v1/burimunsi/payments/'+transaction+'/allocate',{
  method:'POST',headers:{'X-BuriMunsi-Auth':'phone_pin','X-BuriMunsi-Installation':installation,'X-BuriMunsi-Profile':'internal_receiver',
   'X-BuriMunsi-Device':'4'.repeat(64),'X-BuriMunsi-Group':group,Authorization:'Bearer '+'3'.repeat(64)}}),env:{DB:db}},
  async native=>{
   assert.equal(native.principalUserId,principal);assert.equal(native.nativeAccountId,account);
   return service.allocate({id:account,sessionId:nativeSession},{transactionId:transaction,memberId:member,
    expectedVersion:metadata.version,note:'QUALIFICATION original receipt and member verified',requestId:id});
  });
 const first=await invoke(requestId);assert.equal(first.amountRwf,1000);assert.equal(first.memberId,member);
 assert.deepEqual(await invoke(requestId),first);
 await assert.rejects(invoke('fc940000-0000-4000-8000-000000000021'),/transaction_changed/);
 // A later actual canonical source duplicate after posting must preserve the
 // original scope and ledger. It never invokes Allocate again or gains authority.
 await admin.fixtureScript(`BEGIN ISOLATION LEVEL READ COMMITTED;SET LOCAL ROLE collect_runtime;
  SELECT set_config('collect.edge_verified','true',true),
   set_config('collect.fence_admission_id',${quote(input.admission)},true),
   set_config('collect.fence_epoch',${quote(input.epoch)},true),
   set_config('collect.fence_source_sha256',${quote(input.sourceSha256)},true),
   set_config('burimunsi.collection_id',${quote(group)},true),
   set_config('burimunsi.adoption.fixture.body',${quote(input.body)},true),
   set_config('burimunsi.adoption.fixture.payload',${quote(input.payload)},true);
  SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000011');
  SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000011','QUALIFICATION lease');COMMIT;`);
 const canonicalCounts=(await admin.unsafe(`SELECT (SELECT count(*) FROM app.momo_transactions) AS facts,
  (SELECT count(*) FROM app.momo_transaction_sources WHERE relation='accepted') AS accepted,
  (SELECT count(*) FROM app.momo_transaction_sources WHERE relation='duplicate') AS duplicates,
  (SELECT count(*) FROM private.burimunsi_transaction_scopes) AS scopes`))[0];
 assert.deepEqual(canonicalCounts,{facts:1,accepted:1,duplicates:1,scopes:1});
 const counts=(await admin.unsafe(`SELECT (SELECT count(*) FROM app.payments) AS payments,
  (SELECT count(*) FROM app.ledger_entries) AS ledger,(SELECT count(*) FROM app.momo_financial_links) AS links,
  (SELECT count(*) FROM app.contribution_posting_snapshots) AS snapshots,
  (SELECT count(*) FROM private.burimunsi_command_receipts WHERE operation='burimunsi.allocate') AS receipts`))[0];
 assert.deepEqual(counts,{payments:1,ledger:1,links:1,snapshots:1,receipts:1});
 assert.deepEqual(await admin.unsafe('SELECT * FROM private.burimunsi_transaction_scopes WHERE transaction_id=$1',[transaction]),scopeBefore);
 const scrubbed=(await admin.unsafe('SELECT count(*) AS total,count(*) FILTER(WHERE sealed_body IS NULL AND cleared_at IS NOT NULL) AS scrubbed FROM private.storage_payload_reservations'))[0];
 assert.equal(scrubbed.total,3);assert.equal(scrubbed.scrubbed,3);
 assert(fixtureMediaCalls.reads>=3&&fixtureMediaCalls.writes===1);
 result.status='pass';result.original_native_allocate_executed=true;result.native_session_revalidated=true;
 result.real_storage_application_commit_guards=true;result.original_storage_witnesses_and_preparation=true;
 result.fixture_only_object_transport=true;result.fixture_media_calls=fixtureMediaCalls;result.scrubbed_reservations=scrubbed;
 result.exact_replay_same_result=true;result.second_request_did_not_repost=true;result.canonical_duplicate_did_not_repost=true;
 result.first_scope_preserved=true;result.canonical_counts=canonicalCounts;result.counts=counts;
}catch(error){result.error_type=error.name;result.error=String(error.message);result.stack=error.stack;}
finally{
 if(work){
  try{const closure=await work.finish({failed:result.status!=='pass'});result.native_work_close=closure;
   if(result.status==='pass')assert.equal(closure.applicationWorkFinished,true);
  }catch(error){result.status='fail';result.work_cleanup_error=String(error.message);}
 }
 admin?.release();
 try{await pool.end();result.owned_psql_cleanup_confirmed=true;}catch(error){result.status='fail';result.cleanup_error=String(error.message);}
 await writeFile(input.rawOutput,JSON.stringify({result,trace},null,2)+'\n',{mode:0o600,flag:'wx'});
}
process.stdout.write(JSON.stringify(result)+'\n');if(result.status!=='pass')process.exitCode=1;
