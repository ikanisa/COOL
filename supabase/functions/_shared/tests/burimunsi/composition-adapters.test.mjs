import test from 'node:test';import assert from 'node:assert/strict';
import {composeNativeRequest} from '../../domain/burimunsi/compose.js';
import {PostgresNativeAuthStore} from '../../domain/burimunsi/postgres-auth-store.js';
import {PostgresRecordsStore} from '../../domain/burimunsi/postgres-records-store.js';
const noop=async()=>null;
const auth=Object.fromEntries(['consumeAttempts','findAccount','findDeviceGrant','createSessionIfCurrent','loadSession','changePinIfCurrent','mutateStaff','findStaff','retainedStaffCommand','revokeSession'].map(k=>[k,noop]));
const options=()=>({admission:{verified:true,groupId:'g'},config:{enabled:true,groupId:'g',origin:'https://example.test'},ports:{auth,records:{withReadSnapshot:noop},canonical:{inCanonicalTransaction:noop,inMemberTransaction:noop},gateway:{withAuthorityTransaction:noop,withReadSnapshot:noop}},secrets:{pinPepper:new Uint8Array(32).fill(1),pinPepperId:'test-key',cursorKey:new Uint8Array(32).fill(2)},networkBucket:noop});
test('full composition creates request handler only with explicit admitted ports',()=>assert.equal(typeof composeNativeRequest(options()),'function'));
test('composition rejects a canonical adapter without its member transaction',()=>{const o=options();delete o.ports.canonical.inMemberTransaction;assert.throws(()=>composeNativeRequest(o),/collect_adapter_required/);});
for(const kind of ['admission','enabled','secret','canonical','source','network'])test('composition fails closed: '+kind,()=>{const o=options();if(kind==='admission')o.admission.verified=false;if(kind==='enabled')o.config.enabled=false;if(kind==='secret')o.secrets.pinPepper=new Uint8Array(1);if(kind==='canonical')o.ports.canonical={};if(kind==='source')o.ports.records={};if(kind==='network')o.networkBucket=null;assert.throws(()=>composeNativeRequest(o));});
function fakeDatabase(){const calls=[];const tx={unsafe:async(sql,values=[])=>{calls.push({sql,values});return []}};return {calls,db:{applicationWork:{assert:async()=>{}},transaction:async fn=>{calls.push({sql:'BEGIN'});const result=await fn(tx);calls.push({sql:'COMMIT'});return result},context:async()=>calls.push({sql:'EXISTING_WRITE_FENCE'}),readContext:async()=>calls.push({sql:'EXISTING_READ_FENCE'})}};}
test('auth write adapter uses existing fence, canonical advisory lock, and server scope before work',async()=>{const {calls,db}=fakeDatabase();const store=new PostgresNativeAuthStore({db,groupId:'g',createOperatorPrincipal:noop});await store.write(async()=>calls.push({sql:'WORK'}));assert.deepEqual(calls.map(c=>c.sql),['BEGIN','EXISTING_WRITE_FENCE','SELECT pg_advisory_xact_lock(734636924058501::bigint)',"SELECT set_config('burimunsi.collection_id',$1,true)",'WORK','COMMIT']);assert.deepEqual(calls[3].values,['g']);});
test('auth read adapter explicitly selects repeatable read and read-only before existing context',async()=>{const {calls,db}=fakeDatabase();const store=new PostgresNativeAuthStore({db,groupId:'g',createOperatorPrincipal:noop});await store.read(async()=>calls.push({sql:'READ'}));assert.equal(calls[1].sql,'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY');assert.equal(calls[2].sql,'EXISTING_READ_FENCE');});
test('auth adapter never accepts a caller-selected other group',async()=>{const {calls,db}=fakeDatabase();const store=new PostgresNativeAuthStore({db,groupId:'g',createOperatorPrincipal:noop});await assert.rejects(store.findAccount('other','+250780000816'),/access_denied/);assert.equal(calls.length,0);});
test('auth adapter requires existing principal command, not a generated privileged user',()=>{const {db}=fakeDatabase();assert.throws(()=>new PostgresNativeAuthStore({db,groupId:'g'}));});
test('records adapter requires existing raw-source reader',()=>assert.throws(()=>new PostgresRecordsStore({authority:{read:noop,session:noop,groupId:'g'},sourceReader:{}})));

test('advanced smart import composition requires an explicit enabled port',()=>{
 const o=options();o.config.smartOnboardingAdvancedEnabled=true;
 assert.throws(()=>composeNativeRequest(o),/collect_adapter_required/);
 o.ports.smartOnboardingImport={preview:noop};assert.equal(typeof composeNativeRequest(o),'function');
 o.config.smartOnboardingAdvancedEnabled=false;assert.throws(()=>composeNativeRequest(o),/smart_import_config_conflict/);
});
test('held recovery activates only for its configured collection with complete ports',()=>{
 const o=options();o.config.nativeObservationEnabled=true;
 o.config.heldRecovery={sourceSha256:'a'.repeat(64),groupId:'another-group'};
 // Another group composes without receiving recovery capabilities.
 assert.equal(typeof composeNativeRequest(o),'function');
 o.config.heldRecovery={sourceSha256:'a'.repeat(64),groupId:'g'};
 assert.throws(()=>composeNativeRequest(o),/collect_adapter_required/);
 o.ports.observations={recoveryV2Capability:noop,recoverHeldV2:noop,recoverHeldV2Ack:noop,reconcileVerifiedStatus:noop};
 assert.equal(typeof composeNativeRequest(o),'function');
 o.config.heldRecovery={sourceSha256:'bad',groupId:'g'};
 assert.throws(()=>composeNativeRequest(o),/held_recovery_configuration_invalid/);
 o.config.heldRecovery={sourceSha256:'a'.repeat(64),groupId:'g'};o.config.nativeObservationEnabled=false;
 assert.throws(()=>composeNativeRequest(o),/held_recovery_configuration_invalid/);
});
