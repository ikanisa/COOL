import test from 'node:test';import assert from 'node:assert/strict';
import {createPostgresNativePorts,composePostgresNativeRequest,composePostgresNativeWorkers} from '../../domain/burimunsi/compose-postgres.js';
import {PostgresCanonicalStore} from '../../domain/burimunsi/postgres-canonical-store.js';
// Contract-only assembly fixtures. No live database, provider or network access.
const unexpected=()=>{throw Error('Assembly must not perform I/O')};
function options(){return {
 admission:{verified:true,groupId:'group-1'},config:{enabled:true,groupId:'group-1',origin:'https://example.test'},
 db:{transaction:unexpected,context:unexpected,readContext:unexpected,applicationWork:{assert:unexpected}},
 bridges:{createOperatorPrincipal:unexpected,gateway:authority=>({authority,withAuthorityTransaction:unexpected,withReadSnapshot:unexpected}),
  commands:{postContribution:unexpected,createDirectMember:unexpected,setMembershipActive:unexpected,enqueueEligibleRematch:unexpected},
  identities:{policy:unexpected,members:unexpected,verified:unexpected},receiptAdmission:{assertInTransaction:unexpected},
  sources:{assertLineage:unexpected,load:unexpected},canonicalIngest:{ingest:unexpected,outcome:unexpected},sourceReader:{revision:unexpected,page:unexpected,detail:unexpected}},
 secrets:{pinPepper:new Uint8Array(32).fill(1),pinPepperId:'test-only',cursorKey:new Uint8Array(32).fill(2)},networkBucket:unexpected
};}
test('SQL adapters share one admitted authority and do no assembly I/O',()=>{
 const o=options(),ports=createPostgresNativePorts(o);
 assert.ok(ports.canonical instanceof PostgresCanonicalStore);assert.ok(Object.isFrozen(ports));
 assert.equal(ports.canonical.authority,ports.auth);assert.equal(ports.jobs.authority,ports.auth);assert.equal(ports.records.authority,ports.auth);assert.equal(ports.gateway.authority,ports.auth);
 assert.equal(ports.canonical.commands,o.bridges.commands);assert.equal(ports.canonical.jobs,ports.jobs);assert.equal(ports.auth.db,o.db);
});
test('handler composition is explicit and contains no database/network side effect',()=>assert.equal(typeof composePostgresNativeRequest(options()),'function'));
for(const key of ['commands','identities','receiptAdmission','sources','canonicalIngest','sourceReader'])test('no missing bridge fallback: '+key,()=>{
 const o=options();delete o.bridges[key];assert.throws(()=>createPostgresNativePorts(o));
});
for(const change of ['disabled','unverified','wrong-group','missing-work','principal','gateway','invalid-attempts'])test('admission/assembly guard '+change,()=>{
 const o=options();
 if(change==='disabled')o.config.enabled=false;if(change==='unverified')o.admission.verified=false;if(change==='wrong-group')o.admission.groupId='other';
 if(change==='missing-work')delete o.db.applicationWork;if(change==='principal')delete o.bridges.createOperatorPrincipal;
 if(change==='gateway')o.bridges.gateway=()=>({});if(change==='invalid-attempts')o.config.maxReceiptAttempts=100;
 assert.throws(()=>createPostgresNativePorts(o));
});

test('opt-in rematch adapter assembles without I/O and owns enrollment enqueue',()=>{
 const o=options();o.config.rematchEnabled=true;o.bridges.rematchAdmission={assertInTransaction:unexpected};delete o.bridges.commands.enqueueEligibleRematch;
 const ports=createPostgresNativePorts(o);assert(ports.rematches);assert.equal(ports.rematches.authority,ports.auth);
 assert.notEqual(ports.canonical.jobs,ports.jobs);assert.equal(typeof ports.canonical.commands.enqueueEligibleRematch,'function');
});
test('enabled rematching without authoritative admission cannot start',()=>{const o=options();o.config.rematchEnabled=true;assert.throws(()=>createPostgresNativePorts(o));});
test('rematching stays absent by default',()=>assert.equal(createPostgresNativePorts(options()).rematches,undefined));
test('string-valued rematch activation is rejected',()=>{const o=options();o.config.rematchEnabled='true';assert.throws(()=>createPostgresNativePorts(o));});

function sharedOptions(){const o=options();o.config.sharedPostingEnabled=true;delete o.bridges.commands.postContribution;
 o.db.prepare=unexpected;o.db.statement=unexpected;o.bridges.posting={runtime:{assertInTransaction:unexpected},allocation:{prepareInTransaction:unexpected},evidence:{assertInTransaction:unexpected}};return o;}
test('opt-in shared writer assembles without side effects',()=>{const ports=createPostgresNativePorts(sharedOptions());assert(ports.posting);assert.equal(typeof ports.canonical.commands.postContribution,'function');});
test('shared writer is absent by default',()=>assert.equal(createPostgresNativePorts(options()).posting,undefined));
test('shared writer does not silently override an existing command',()=>{const o=sharedOptions();o.bridges.commands.postContribution=unexpected;assert.throws(()=>createPostgresNativePorts(o),/posting_writer_conflict/);});
test('string activation is rejected for shared posting',()=>{const o=options();o.config.sharedPostingEnabled='true';assert.throws(()=>createPostgresNativePorts(o),/invalid_worker_config/);});
for(const k of ['runtime','allocation','evidence'])test('shared executor cannot assemble without '+k,()=>{const o=sharedOptions();delete o.bridges.posting[k];assert.throws(()=>createPostgresNativePorts(o),/collect_adapter_required/);});
test('persistent rematch and shared writer compose together without I/O',()=>{const o=sharedOptions();o.config.rematchEnabled=true;o.bridges.rematchAdmission={assertInTransaction:unexpected};delete o.bridges.commands.enqueueEligibleRematch;const ports=createPostgresNativePorts(o);assert(ports.posting&&ports.rematches);assert.equal(typeof ports.canonical.commands.postContribution,'function');});

function journalOptions(){const o=sharedOptions();o.config.journalEvidenceEnabled=true;delete o.bridges.posting.evidence;
 o.bridges.posting.custody={namespace:{origin:'https://example.test',bucket:'collect-evidence'},decrypt:unexpected};return o;}
test('concrete journal custody composes with shared posting without I/O',()=>{
 const p=createPostgresNativePorts(journalOptions());assert(p.custody);assert.equal(p.posting.evidence,p.custody);
});
test('concrete journal custody remains absent by default',()=>assert.equal(createPostgresNativePorts(sharedOptions()).custody,undefined));
test('journal custody rejects competing injected evidence verifier',()=>{const o=journalOptions();o.bridges.posting.evidence={assertInTransaction:unexpected};assert.throws(()=>createPostgresNativePorts(o),/posting_evidence_conflict/);});
test('journal custody requires the shared posting executor',()=>{const o=options();o.config.journalEvidenceEnabled=true;assert.throws(()=>createPostgresNativePorts(o),/posting_writer_required/);});
test('journal custody rejects string-valued activation',()=>{const o=sharedOptions();o.config.journalEvidenceEnabled='true';assert.throws(()=>createPostgresNativePorts(o),/invalid_worker_config/);});
test('journal custody requires real decryption binding',()=>{const o=journalOptions();delete o.bridges.posting.custody.decrypt;assert.throws(()=>createPostgresNativePorts(o));});
test('journal custody requires explicit storage namespace',()=>{const o=journalOptions();delete o.bridges.posting.custody.namespace;assert.throws(()=>createPostgresNativePorts(o));});
test('concrete custody and rematch compose jointly without I/O',()=>{const o=journalOptions();o.config.rematchEnabled=true;o.bridges.rematchAdmission={assertInTransaction:unexpected};delete o.bridges.commands.enqueueEligibleRematch;const p=createPostgresNativePorts(o);assert(p.custody&&p.rematches&&p.posting);});

function allocationOptions(){const o=journalOptions();o.config.journalAllocationEnabled=true;delete o.bridges.posting.allocation;return o;}
test('concrete allocation, custody and posting assemble without I/O',()=>{
 const p=createPostgresNativePorts(allocationOptions());assert(p.allocation);assert.equal(p.posting.allocation,p.allocation);assert.equal(p.allocation.custody,p.custody);
});
test('concrete allocation is absent by default',()=>assert.equal(createPostgresNativePorts(journalOptions()).allocation,undefined));
test('concrete allocation refuses competing injected allocator',()=>{const o=allocationOptions();o.bridges.posting.allocation={prepareInTransaction:unexpected};assert.throws(()=>createPostgresNativePorts(o),/posting_allocation_conflict/);});
for(const dependency of ['sharedPostingEnabled','journalEvidenceEnabled'])test('concrete allocation requires '+dependency,()=>{const o=allocationOptions();o.config[dependency]=false;assert.throws(()=>createPostgresNativePorts(o));});
test('concrete allocation refuses string-valued activation',()=>{const o=allocationOptions();o.config.journalAllocationEnabled='true';assert.throws(()=>createPostgresNativePorts(o),/invalid_worker_config/);});
test('concrete allocation does not replace the missing runtime authorization bridge',()=>{const o=allocationOptions();delete o.bridges.posting.runtime;assert.throws(()=>createPostgresNativePorts(o),/collect_adapter_required/);});
test('concrete allocator, custody and persistent rematch compose jointly without effects',()=>{const o=allocationOptions();o.config.rematchEnabled=true;o.bridges.rematchAdmission={assertInTransaction:unexpected};delete o.bridges.commands.enqueueEligibleRematch;const p=createPostgresNativePorts(o);assert(p.allocation&&p.custody&&p.rematches&&p.posting);});

function preparationOptions(){const o=allocationOptions();o.config.postingPreparationEnabled=true;
 o.bridges.posting.preparation={media:{namespace:o.bridges.posting.custody.namespace,put:unexpected},encrypt:unexpected,keyId:'test-key'};return o;}
test('preparation, allocation, custody and posting assemble without I/O',()=>{
 const p=createPostgresNativePorts(preparationOptions());assert(p.preparation);assert.equal(p.preparation.authority,p.auth);
 assert.equal(p.preparation.posting,p.posting);assert.equal(p.preparation.allocation,p.allocation);assert.equal(p.preparation.custody,p.custody);
});
test('preparation stays absent unless explicitly selected',()=>assert.equal(createPostgresNativePorts(allocationOptions()).preparation,undefined));
test('preparation rejects string-valued activation',()=>{const o=preparationOptions();o.config.postingPreparationEnabled='true';assert.throws(()=>createPostgresNativePorts(o),/invalid_worker_config/);});
for(const dependency of ['sharedPostingEnabled','journalEvidenceEnabled','journalAllocationEnabled'])test('preparation requires '+dependency,()=>{const o=preparationOptions();o.config[dependency]=false;assert.throws(()=>createPostgresNativePorts(o));});
for(const key of ['media','encrypt','keyId'])test('preparation requires trusted '+key+' binding',()=>{const o=preparationOptions();delete o.bridges.posting.preparation[key];assert.throws(()=>createPostgresNativePorts(o));});
test('preparation rejects a different provider namespace',()=>{const o=preparationOptions();o.bridges.posting.preparation.media.namespace={origin:'https://wrong.test',bucket:'collect-evidence'};assert.throws(()=>createPostgresNativePorts(o));});
test('preparation does not replace the financial-authority bridge',()=>{const o=preparationOptions();delete o.bridges.posting.runtime;assert.throws(()=>createPostgresNativePorts(o));});
test('preparation and persistent rematch can be assembled together without effects',()=>{const o=preparationOptions();o.config.rematchEnabled=true;o.bridges.rematchAdmission={assertInTransaction:unexpected};delete o.bridges.commands.enqueueEligibleRematch;const p=createPostgresNativePorts(o);assert(p.preparation&&p.rematches);});

// v0.11: shipping request/worker composition, still with no assembly I/O.
test('prepared native handler composes with all real adapter classes',()=>assert.equal(typeof composePostgresNativeRequest(preparationOptions()),'function'));
test('prepared receipt-worker entrypoint assembles but does not execute',()=>{
 const w=composePostgresNativeWorkers(preparationOptions());assert(Object.isFrozen(w));
 assert.equal(typeof w.processReceipts,'function');assert.equal(w.processRematches,undefined);
});
test('prepared rematch-worker entrypoint uses explicit rematch selection',()=>{
 const o=preparationOptions();o.config.rematchEnabled=true;o.bridges.rematchAdmission={assertInTransaction:unexpected};
 const w=composePostgresNativeWorkers(o);assert.equal(typeof w.processRematches,'function');
});
test('prepared workers refuse missing genuine runtime authority',()=>{
 const o=preparationOptions();delete o.bridges.posting.runtime;assert.throws(()=>composePostgresNativeWorkers(o),/collect_adapter_required/);
});
test('prepared workers refuse missing media rather than choosing another storage path',()=>{
 const o=preparationOptions();delete o.bridges.posting.preparation.media;assert.throws(()=>composePostgresNativeWorkers(o));
});
test('worker wrapper rejects an invalid batch before any transaction',async()=>{
 const w=composePostgresNativeWorkers(preparationOptions());await assert.rejects(w.processReceipts({owner:'worker',profile:{version:'test'},limit:1000}),/invalid_worker_config/);
});
test('worker wrapper cannot take a replacement group or contribution service in batch arguments',async()=>{
 const w=composePostgresNativeWorkers(preparationOptions());
 await assert.rejects(w.processReceipts({owner:'worker',profile:{version:'test'},store:{},groupId:'other',contributions:{automaticallyAllocate:unexpected}}),/Assembly must not perform I\/O/);
});

// v0.12: optional concrete native financial proof; automatic authority stays explicit.
function nativeAuthorityOptions(){const o=sharedOptions();o.config.nativePostingAuthorityEnabled=true;delete o.bridges.posting.runtime;return o;}
test('native principal proof assembles without SQL or an injected native verifier',()=>{const p=createPostgresNativePorts(nativeAuthorityOptions());assert.equal(p.posting.runtime,p.postingAuthority);assert.equal(p.postingAuthority.authority,p.auth);});
test('native principal proof remains absent by default',()=>assert.equal(createPostgresNativePorts(sharedOptions()).postingAuthority,undefined));
test('native proof rejects competing runtime selection',()=>{const o=nativeAuthorityOptions();o.bridges.posting.runtime={assertInTransaction:unexpected};assert.throws(()=>createPostgresNativePorts(o),/posting_authority_conflict/);});
test('native proof requires shared posting',()=>{const o=options();o.config.nativePostingAuthorityEnabled=true;assert.throws(()=>createPostgresNativePorts(o),/posting_writer_required/);});
test('native proof rejects string-valued selection',()=>{const o=sharedOptions();o.config.nativePostingAuthorityEnabled='true';assert.throws(()=>createPostgresNativePorts(o),/invalid_worker_config/);});
test('worker-only adapter without the explicit proof selector is ambiguous',()=>{const o=sharedOptions();o.bridges.posting.workerRuntime={assertInTransaction:unexpected};assert.throws(()=>createPostgresNativePorts(o),/posting_authority_conflict/);});
test('native proof cannot start an automatic worker without genuine worker authority',()=>assert.throws(()=>composePostgresNativeWorkers(nativeAuthorityOptions()),/collect_adapter_required/));
test('native and explicitly supplied worker authority compose without I/O',()=>{const o=nativeAuthorityOptions();o.bridges.posting.workerRuntime={assertInTransaction:unexpected};assert.equal(typeof composePostgresNativeWorkers(o).processReceipts,'function');});
test('native proof composes with the complete prepared writer',()=>{const o=preparationOptions();o.config.nativePostingAuthorityEnabled=true;delete o.bridges.posting.runtime;const p=createPostgresNativePorts(o);assert(p.preparation&&p.postingAuthority);assert.equal(p.preparation.posting.runtime,p.postingAuthority);});
