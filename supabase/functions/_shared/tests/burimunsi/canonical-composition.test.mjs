// Assembly contracts only. No genuine provider session or database is involved.
import test from 'node:test';import assert from 'node:assert/strict';
import {createPostgresNativePorts,composePostgresNativeWorkers} from '../../domain/burimunsi/compose-postgres.js';
const unexpected=()=>{throw Error('Assembly must not perform I/O');};
function options(kind='jobs'){
 const db={transaction:unexpected,context:unexpected,readContext:unexpected,prepare:unexpected,statement:unexpected,applicationWork:{kind,assert:unexpected}};
 const ns={origin:'https://example.test',bucket:'collect-evidence'};
 return {admission:{verified:true,groupId:'group-1'},config:{enabled:true,groupId:'group-1',origin:'https://example.test',
  canonicalIntegrationEnabled:true,sharedPostingEnabled:true,journalEvidenceEnabled:true,journalAllocationEnabled:true,postingPreparationEnabled:true,nativePostingAuthorityEnabled:true,rematchEnabled:true},db,
  bridges:{gateway:authority=>({authority,withAuthorityTransaction:unexpected,withReadSnapshot:unexpected}),
   commands:{createDirectMember:unexpected,setMembershipActive:unexpected},sourceReader:{revision:unexpected,page:unexpected,detail:unexpected},
   canonical:{env:{DB:db,MOMO_PROCESSING_PAUSED:'false'},validateProviderProfile:unexpected,applicationWorkTuple:()=>['10000000-0000-4000-8000-000000000001',1,'a'.repeat(64)]},
   posting:{custody:{namespace:ns,decrypt:unexpected},preparation:{media:{namespace:ns,put:unexpected},encrypt:unexpected,keyId:'test-key'}}},
  secrets:{pinPepper:new Uint8Array(32).fill(1),pinPepperId:'test-only',cursorKey:new Uint8Array(32).fill(2)},networkBucket:unexpected};
}
test('all canonical bridges assemble together without I/O',()=>{const p=createPostgresNativePorts(options());assert(p.managedSessions&&p.workerAuthority&&p.scheduler&&p.sources);assert.equal(p.auth.sessionBinding,p.managedSessions);assert.equal(p.canonical.authority,p.auth);});
test('HTTP receives session binding but no scheduler authority',()=>{const p=createPostgresNativePorts(options('http_admin'));assert(p.managedSessions);assert.equal(p.workerAuthority,undefined);assert.equal(p.scheduler,undefined);});
test('integrated worker exposes bounded cycle and original-source enqueue',()=>{const w=composePostgresNativeWorkers(options());for(const k of ['runScheduledCycle','enqueueRetainedSource','processReceipts','processRematches'])assert.equal(typeof w[k],'function');});
for(const key of ['identities','receiptAdmission','rematchAdmission','sources','canonicalIngest','createOperatorPrincipal'])test('competing bridge is rejected: '+key,()=>{const o=options();o.bridges[key]=key==='createOperatorPrincipal'?unexpected:{};assert.throws(()=>createPostgresNativePorts(o),/canonical_bridge_conflict/);});
for(const key of ['nativePostingAuthorityEnabled','postingPreparationEnabled','sharedPostingEnabled','journalEvidenceEnabled','journalAllocationEnabled'])test('integrated mode cannot downgrade '+key,()=>{const o=options();o.config[key]=false;assert.throws(()=>createPostgresNativePorts(o));});
test('different DB in canonical environment is rejected',()=>{const o=options();o.bridges.canonical.env.DB={};assert.throws(()=>createPostgresNativePorts(o));});
test('unbranded work rejection propagates before assembly',()=>{const o=options();o.bridges.canonical.applicationWorkTuple=()=>{throw Error('work_unbranded');};assert.throws(()=>createPostgresNativePorts(o),/work_unbranded/);});
test('caller-supplied worker bypass is rejected',()=>{const o=options();o.bridges.posting.workerRuntime={assertInTransaction:unexpected};assert.throws(()=>createPostgresNativePorts(o));});
test('string-valued activation rejected',()=>{const o=options();o.config.canonicalIntegrationEnabled='true';assert.throws(()=>createPostgresNativePorts(o),/invalid_worker_config/);});
