// Source-only proposal. Root executes; no database/API/provider dependency.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,mkdtemp,mkdir,writeFile,rm,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {validateBinding,renderSyntheticSql,loadOriginalNine,loadReviewedPlatformFixture,ORIGINAL_NINE,EXACT_TEN,EXACT_CURRENT11,EXACT_CURRENT12,EXACT_CURRENT13,EXACT_CURRENT14,MIGRATION_TEN,MIGRATION_ELEVEN,MIGRATION_TWELVE,MIGRATION_THIRTEEN,MIGRATION_FOURTEEN,ROOT_SQL11_SHA256,ROOT_SQL12_SHA256,ROOT_SQL13_SHA256,ROOT_SQL14_SHA256} from './curated-platform-fixture.mjs';
const sha=text=>createHash('sha256').update(text).digest('hex');
function input(){
 const hostedMeta='1'.repeat(64),syntheticMeta='2'.repeat(64),hosted="SELECT '"+hostedMeta+"'::text;\nSELECT '"+hostedMeta+"'::text;\n";
 const synthetic=hosted.replaceAll(hostedMeta,syntheticMeta);
 const binding={format:'collect.member.realtime.fixture-binding.v1',status:'reviewed_static_binding',project_ref:'rrlduytparvsjfmegalh',migration:MIGRATION_TEN,hosted_metadata_sha256:hostedMeta,synthetic_metadata_sha256:syntheticMeta,hosted_sql_sha256:sha(hosted),synthetic_sql_sha256:sha(synthetic),interface_sha256:'3'.repeat(64),metadata_expression_sha256:'4'.repeat(64),metadata_literal_occurrences:2,review_evidence_sha256:'5'.repeat(64)};
 return{hosted,synthetic,binding};
}
test('an unpopulated/static-unreviewed fixture descriptor cannot enable test execution',()=>{
 const {binding}=input();for(const status of ['unpopulated_pending_root_measurement_and_independent_review','observed','synthetic',''])assert.throws(()=>validateBinding({...binding,status}),/REVIEWED_REALTIME_FIXTURE_BINDING_REQUIRED/);
 for(const value of [null,{}, {...binding,test_mode:true}])assert.throws(()=>validateBinding(value),/REALTIME_BINDING_SHAPE_REQUIRED/);
 for(const key of ['hosted_metadata_sha256','synthetic_metadata_sha256','hosted_sql_sha256','synthetic_sql_sha256','review_evidence_sha256'])for(const value of [null,'',17,'a'.repeat(63)])assert.throws(()=>validateBinding({...binding,[key]:value}),/REVIEWED_REALTIME_FIXTURE_HASH_REQUIRED/);
 assert.throws(()=>validateBinding({...binding,synthetic_metadata_sha256:binding.hosted_metadata_sha256}),/DISTINCT_LOCAL_AND_HOSTED_METADATA_REQUIRED/);
});
test('synthetic SQL differs only at the two reviewed metadata literals; any code/hash/cardinality tamper refuses',()=>{
 const {binding,hosted,synthetic}=input();assert.equal(renderSyntheticSql(hosted,binding),synthetic);
 assert.equal(renderSyntheticSql(hosted,binding).replaceAll(binding.synthetic_metadata_sha256,binding.hosted_metadata_sha256),hosted);
 assert.throws(()=>renderSyntheticSql(hosted+'--changed\n',binding),/HOSTED_REALTIME_SOURCE_CHANGED/);
 assert.throws(()=>renderSyntheticSql(hosted,{...binding,synthetic_sql_sha256:'0'.repeat(64)}),/SYNTHETIC_REALTIME_SOURCE_CHANGED/);
 const one=hosted.slice(0,hosted.indexOf('\n')+1);assert.throws(()=>renderSyntheticSql(one,{...binding,hosted_sql_sha256:sha(one)}),/REALTIME_METADATA_LITERAL_COUNT_CHANGED/);
});
test('the exact current14 manifest preserves immutable SQL11 and SQL12 prefixes and rejects raw numeric chain changes',async()=>{
 assert.equal(Object.keys(ORIGINAL_NINE).length,9);assert.equal(EXACT_TEN.length,10);assert.equal(EXACT_TEN[9],MIGRATION_TEN);assert.equal(EXACT_CURRENT11.length,11);assert.deepEqual(EXACT_CURRENT11.slice(0,10),EXACT_TEN);assert.equal(EXACT_CURRENT11[10],MIGRATION_ELEVEN);assert.equal(EXACT_CURRENT12.length,12);assert.deepEqual(EXACT_CURRENT12.slice(0,11),EXACT_CURRENT11);assert.equal(EXACT_CURRENT12[11],MIGRATION_TWELVE);assert.equal(EXACT_CURRENT13.length,13);assert.deepEqual(EXACT_CURRENT13.slice(0,12),EXACT_CURRENT12);assert.equal(EXACT_CURRENT13[12],MIGRATION_THIRTEEN);assert.equal(EXACT_CURRENT14.length,14);assert.deepEqual(EXACT_CURRENT14.slice(0,13),EXACT_CURRENT13);assert.equal(EXACT_CURRENT14[13],MIGRATION_FOURTEEN);assert.equal(ORIGINAL_NINE['20261022195747_collect_application_mutation_fence.sql'],'714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497');
 const folder=await mkdtemp(join(tmpdir(),'collect-realtime-loader-'));
 try{
  await mkdir(join(folder,'supabase/migrations'),{recursive:true});
  for(const name of EXACT_TEN.slice(0,9))await writeFile(join(folder,'supabase/migrations',name),'not qualified');
  await assert.rejects(loadOriginalNine(folder),/EXACT_REVIEWED_MIGRATION_CHAIN_REQUIRED/);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_TEN),'not qualified');
  await assert.rejects(loadOriginalNine(folder),/EXACT_REVIEWED_MIGRATION_CHAIN_REQUIRED/);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_ELEVEN),'not qualified');
  await assert.rejects(loadOriginalNine(folder),/EXACT_REVIEWED_MIGRATION_CHAIN_REQUIRED/);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_TWELVE),'not qualified');
  await assert.rejects(loadOriginalNine(folder),/EXACT_REVIEWED_MIGRATION_CHAIN_REQUIRED/);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_THIRTEEN),'not qualified');
  await assert.rejects(loadOriginalNine(folder),/EXACT_REVIEWED_MIGRATION_CHAIN_REQUIRED/);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_FOURTEEN),'not qualified');
  await writeFile(join(folder,'supabase/migrations/20261023090000_unreviewed.sql'),'not qualified');
  await assert.rejects(loadOriginalNine(folder),/EXACT_REVIEWED_MIGRATION_CHAIN_REQUIRED/);
 }finally{await rm(folder,{recursive:true,force:false});}
});
test('same migration name with changed SQL is refused before fixture execution',async()=>{
 const source=resolve(import.meta.dirname,'../../..'),folder=await realpath(await mkdtemp(join(tmpdir(),'collect-realtime-source-')));
 try{
  await mkdir(join(folder,'supabase/migrations'),{recursive:true});await mkdir(join(folder,'supabase/tests/sql'),{recursive:true});
  await writeFile(join(folder,'supabase/tests/sql/00_local_auth_fixture.sql'),await readFile(join(source,'supabase/tests/sql/00_local_auth_fixture.sql')));
  for(const name of Object.keys(ORIGINAL_NINE))await writeFile(join(folder,'supabase/migrations',name),await readFile(join(source,'supabase/migrations',name)));
  await writeFile(join(folder,'supabase/migrations',MIGRATION_TEN),await readFile(join(source,'supabase/migrations',MIGRATION_TEN)));
  await writeFile(join(folder,'supabase/migrations',MIGRATION_ELEVEN),await readFile(join(source,'supabase/migrations',MIGRATION_ELEVEN)));
  await writeFile(join(folder,'supabase/migrations',MIGRATION_TWELVE),await readFile(join(source,'supabase/migrations',MIGRATION_TWELVE)));
  await writeFile(join(folder,'supabase/migrations',MIGRATION_THIRTEEN),await readFile(join(source,'supabase/migrations',MIGRATION_THIRTEEN)));
  await writeFile(join(folder,'supabase/migrations',MIGRATION_FOURTEEN),await readFile(join(source,'supabase/migrations',MIGRATION_FOURTEEN)));
  const first=Object.keys(ORIGINAL_NINE)[0];await writeFile(join(folder,'supabase/migrations',first),'--same version/name; changed body\n');
  await assert.rejects(loadOriginalNine(folder),/ORIGINAL_MIGRATION_CHANGED/);
 }finally{await rm(folder,{recursive:true,force:false});}
});

// These are offline loader/dispatch tests. SQL text is not executed, and the
// simulated SQL10 metadata refusal is not a native PostgreSQL acceptance claim.
test('SQL11 through SQL14 remain content-pinned when only the historical ten-prefix is requested',async()=>{
 assert.match(ROOT_SQL11_SHA256,/^[a-f0-9]{64}$/,'Root must render the exact independently supplied SQL11 pin before qualification.');
 assert.match(ROOT_SQL12_SHA256,/^[a-f0-9]{64}$/,'Root must render the exact SQL12 source pin before qualification.');
 assert.match(ROOT_SQL13_SHA256,/^[a-f0-9]{64}$/,'Root must render the exact SQL13 source pin before qualification.');
 const source=resolve(import.meta.dirname,'../../..'),folder=await realpath(await mkdtemp(join(tmpdir(),'collect-current13-pin-')));
 try{
  await mkdir(join(folder,'supabase/migrations'),{recursive:true});await mkdir(join(folder,'supabase/tests/sql'),{recursive:true});
  await writeFile(join(folder,'supabase/tests/sql/00_local_auth_fixture.sql'),await readFile(join(source,'supabase/tests/sql/00_local_auth_fixture.sql')));
  for(const name of EXACT_CURRENT14)await writeFile(join(folder,'supabase/migrations',name),await readFile(join(source,'supabase/migrations',name)));
  const original=await loadOriginalNine(folder,{requireTen:false});assert.equal(original.originals.length,9);assert.equal(original.successor.sha256,ROOT_SQL11_SHA256);assert.equal(original.initialEmailProof.name,MIGRATION_TWELVE);assert.equal(original.initialEmailProof.sha256,ROOT_SQL12_SHA256);assert.equal(original.mfaRetirement.name,MIGRATION_THIRTEEN);assert.equal(original.mfaRetirement.sha256,ROOT_SQL13_SHA256);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_ELEVEN),'-- same filename with unreviewed successor body\n');
  for(const options of [{},{requireTen:false}])await assert.rejects(loadOriginalNine(folder,options),/REVIEWED_SUCCESSOR_MIGRATION_CHANGED/);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_ELEVEN),await readFile(join(source,'supabase/migrations',MIGRATION_ELEVEN)));
  await writeFile(join(folder,'supabase/migrations',MIGRATION_TWELVE),'-- same filename with unreviewed initial proof body\n');
  for(const options of [{},{requireTen:false}])await assert.rejects(loadOriginalNine(folder,options),/REVIEWED_INITIAL_EMAIL_PROOF_MIGRATION_CHANGED/);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_TWELVE),await readFile(join(source,'supabase/migrations',MIGRATION_TWELVE)));
  await writeFile(join(folder,'supabase/migrations',MIGRATION_THIRTEEN),'-- same filename with unreviewed MFA retirement body\n');
  for(const options of [{},{requireTen:false}])await assert.rejects(loadOriginalNine(folder,options),/REVIEWED_MFA_RETIREMENT_MIGRATION_CHANGED/);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_THIRTEEN),await readFile(join(source,'supabase/migrations',MIGRATION_THIRTEEN)));
  await writeFile(join(folder,'supabase/migrations',MIGRATION_FOURTEEN),'-- changed stopped admission lifecycle body\n');
  for(const options of [{},{requireTen:false}])await assert.rejects(loadOriginalNine(folder,options),/REVIEWED_STOPPED_ADMISSION_MIGRATION_CHANGED/);
 }finally{await rm(folder,{recursive:true,force:false});}
});
test('default dispatch applies current11 uninitialized; explicit successor:false applies only the admitted ten-prefix',async()=>{
 const source=resolve(import.meta.dirname,'../../..'),fixture=await loadReviewedPlatformFixture(source);
 assert.deepEqual(fixture.names,EXACT_CURRENT11);assert.equal(fixture.rawMigrations.length,11);assert.equal(fixture.successor.name,MIGRATION_ELEVEN);assert.equal(fixture.successor.sha256,ROOT_SQL11_SHA256);
 for(const includeSuccessor of [true,false]){
  const commands=[];await fixture.apply(async sql=>{commands.push(sql);if(sha(sql)===fixture.binding.hosted_sql_sha256)throw Object.assign(new Error('member_realtime_metadata_not_reviewed'),{code:'55000'});},{includeAuth:true,includeSuccessor});
  assert.equal(commands.filter(sql=>sha(sql)===ROOT_SQL11_SHA256).length,includeSuccessor?1:0);
  assert.equal(commands.filter(sql=>[ROOT_SQL12_SHA256,ROOT_SQL13_SHA256,ROOT_SQL14_SHA256].includes(sha(sql))).length,0,'Default11 and predecessor10 cannot dispatch later migrations.');
  assert.equal(commands.filter(sql=>sql==='ROLLBACK').length,1);assert.ok(commands.some(sql=>sql.includes('UNINITIALIZED_FENCE_FIXTURE_REQUIRED')));
  assert.equal(commands.some(sql=>sql.includes('EXACT_CURRENT11_UNINITIALIZED_FIXTURE_REQUIRED')),includeSuccessor);
  assert.equal(commands.some(sql=>/^SELECT\s+private\.collect_fence_initialize\s*\(/i.test(sql.trim())),false,'Loader never forges or initializes the controller');
 }
 const commands=[];await fixture.apply(async sql=>{commands.push(sql);if(sha(sql)===fixture.binding.hosted_sql_sha256)throw Object.assign(new Error('member_realtime_metadata_not_reviewed'),{code:'55000'});});
 assert.equal(commands.filter(sql=>sha(sql)===ROOT_SQL11_SHA256).length,1,'Omitted option defaults to current11');
 assert.equal(commands.filter(sql=>[ROOT_SQL12_SHA256,ROOT_SQL13_SHA256,ROOT_SQL14_SHA256].includes(sha(sql))).length,0);
 for(const includeSuccessor of [null,0,'false']){let dispatched=0;await assert.rejects(fixture.apply(async()=>{dispatched++;},{includeSuccessor}),/BOOLEAN_FIXTURE_OPTIONS_REQUIRED/);assert.equal(dispatched,0);}
});
test('initial-email-proof SQL12 is opt-in, exact, and follows the unchanged SQL11 successor',async()=>{
 const source=resolve(import.meta.dirname,'../../..'),fixture=await loadReviewedPlatformFixture(source,{includeInitialEmailProofMigration:true});
 assert.deepEqual(fixture.names,EXACT_CURRENT12);assert.equal(fixture.rawMigrations.length,12);assert.equal(fixture.successor.name,MIGRATION_ELEVEN);assert.equal(fixture.successor.sha256,ROOT_SQL11_SHA256);
 assert.equal(fixture.initialEmailProof.name,MIGRATION_TWELVE);assert.equal(fixture.initialEmailProof.sha256,ROOT_SQL12_SHA256);assert.equal(fixture.rawMigrations.at(-1).name,MIGRATION_TWELVE);
 const commands=[];await fixture.apply(async sql=>{commands.push(sql);if(sha(sql)===fixture.binding.hosted_sql_sha256)throw Object.assign(new Error('member_realtime_metadata_not_reviewed'),{code:'55000'});},{includeAuth:true});
 assert.equal(commands.filter(sql=>sha(sql)===ROOT_SQL11_SHA256).length,1);assert.equal(commands.filter(sql=>sha(sql)===ROOT_SQL12_SHA256).length,1);assert.equal(commands.filter(sql=>sha(sql)===ROOT_SQL13_SHA256).length,0,'Explicit initial12 must not apply retirement13.');
 assert(commands.findIndex(sql=>sha(sql)===ROOT_SQL11_SHA256)<commands.findIndex(sql=>sha(sql)===ROOT_SQL12_SHA256),'SQL12 must execute after SQL11');
 assert.equal(commands.some(sql=>sql.includes('EXACT_CURRENT11_UNINITIALIZED_FIXTURE_REQUIRED')),true);
 let dispatched=0;await assert.rejects(fixture.apply(async()=>{dispatched++;},{includeSuccessor:false}),/INITIAL_EMAIL_PROOF_REQUIRES_SQL11_SUCCESSOR/);assert.equal(dispatched,0);
 await assert.rejects(loadReviewedPlatformFixture(source,{includeInitialEmailProofMigration:1}),/BOOLEAN_INITIAL_EMAIL_PROOF_MIGRATION_OPTION_REQUIRED/);
});

test('MFA retirement SQL13 is explicit and dispatches SQL11, SQL12 and SQL13 once in order',async()=>{
 const source=resolve(import.meta.dirname,'../../..');
 for(const includeInitialEmailProofMigration of [false,true]){
  const fixture=await loadReviewedPlatformFixture(source,{includeInitialEmailProofMigration,includeMfaRetirementMigration:true});
  assert.deepEqual(fixture.names,EXACT_CURRENT13);assert.equal(fixture.rawMigrations.length,13);
  assert.equal(fixture.rawMigrations.at(-2).name,MIGRATION_TWELVE);assert.equal(fixture.rawMigrations.at(-1).name,MIGRATION_THIRTEEN);
  assert.equal(fixture.mfaRetirement.sha256,ROOT_SQL13_SHA256);assert.equal(fixture.includeMfaRetirementMigration,true);
  const commands=[];await fixture.apply(async sql=>{commands.push(sql);if(sha(sql)===fixture.binding.hosted_sql_sha256)throw Object.assign(new Error('member_realtime_metadata_not_reviewed'),{code:'55000'});},{includeAuth:true});
  for(const pin of [ROOT_SQL11_SHA256,ROOT_SQL12_SHA256,ROOT_SQL13_SHA256])assert.equal(commands.filter(sql=>sha(sql)===pin).length,1);
  const positions=[ROOT_SQL11_SHA256,ROOT_SQL12_SHA256,ROOT_SQL13_SHA256].map(pin=>commands.findIndex(sql=>sha(sql)===pin));
  assert(positions[0]<positions[1]&&positions[1]<positions[2],'Retirement13 requires both unchanged predecessors first.');
  let dispatched=0;await assert.rejects(fixture.apply(async()=>{dispatched++;},{includeSuccessor:false}),includeInitialEmailProofMigration?/INITIAL_EMAIL_PROOF_REQUIRES_SQL11_SUCCESSOR/:/MFA_RETIREMENT_REQUIRES_SQL11_SUCCESSOR/);assert.equal(dispatched,0);
 }
 for(const includeMfaRetirementMigration of [null,0,1,'false'])await assert.rejects(loadReviewedPlatformFixture(source,{includeMfaRetirementMigration}),/BOOLEAN_MFA_RETIREMENT_MIGRATION_OPTION_REQUIRED/);
});
test('stopped lifecycle SQL14 is explicit, pinned and follows all13 unchanged predecessors',async()=>{
 const source=resolve(import.meta.dirname,'../../..');
 const fixture=await loadReviewedPlatformFixture(source,{includeStoppedAdmissionLifecycleMigration:true});
 assert.deepEqual(fixture.names,EXACT_CURRENT14);assert.equal(fixture.rawMigrations.length,14);
 assert.equal(fixture.stoppedAdmissionLifecycle.name,MIGRATION_FOURTEEN);assert.equal(fixture.stoppedAdmissionLifecycle.sha256,ROOT_SQL14_SHA256);
 const commands=[];await fixture.apply(async sql=>{commands.push(sql);if(sha(sql)===fixture.binding.hosted_sql_sha256)throw Object.assign(new Error('member_realtime_metadata_not_reviewed'),{code:'55000'});},{includeAuth:true});
 const pins=[ROOT_SQL11_SHA256,ROOT_SQL12_SHA256,ROOT_SQL13_SHA256,ROOT_SQL14_SHA256];
 for(const pin of pins)assert.equal(commands.filter(sql=>sha(sql)===pin).length,1);
 const positions=pins.map(pin=>commands.findIndex(sql=>sha(sql)===pin));
 assert(positions.every((value,index)=>index===0||positions[index-1]<value));
 let dispatched=0;await assert.rejects(fixture.apply(async()=>{dispatched++;},{includeSuccessor:false}),/STOPPED_ADMISSION_REQUIRES_SQL11_SUCCESSOR/);assert.equal(dispatched,0);
 for(const value of [null,0,1,'false'])await assert.rejects(loadReviewedPlatformFixture(source,{includeStoppedAdmissionLifecycleMigration:value}),/BOOLEAN_STOPPED_ADMISSION_MIGRATION_OPTION_REQUIRED/);
});
test('parity for every named application prefix still rejects changed SQL13 and unknown extra migrations',async()=>{
 const source=resolve(import.meta.dirname,'../../..'),folder=await realpath(await mkdtemp(join(tmpdir(),'collect-current13-parity-')));
 try{
  await mkdir(join(folder,'supabase/migrations'),{recursive:true});await mkdir(join(folder,'supabase/tests/sql'),{recursive:true});
  await writeFile(join(folder,'supabase/tests/sql/00_local_auth_fixture.sql'),await readFile(join(source,'supabase/tests/sql/00_local_auth_fixture.sql')));
  for(const name of EXACT_CURRENT14)await writeFile(join(folder,'supabase/migrations',name),await readFile(join(source,'supabase/migrations',name)));
  const modes=[{}, {includeInitialEmailProofMigration:true}, {includeMfaRetirementMigration:true}, {includeStoppedAdmissionLifecycleMigration:true}];
  const fixtures=await Promise.all(modes.map(options=>loadReviewedPlatformFixture(folder,options)));
  for(const [index,fixture]of fixtures.entries()){
   assert.deepEqual(fixture.names,[EXACT_CURRENT11,EXACT_CURRENT12,EXACT_CURRENT13,EXACT_CURRENT14][index]);
   await fixture.parity();
  }
  await writeFile(join(folder,'supabase/migrations',MIGRATION_THIRTEEN),'-- unreviewed retirement body\n');
  for(const fixture of fixtures)await assert.rejects(fixture.parity(),/REVIEWED_MFA_RETIREMENT_MIGRATION_CHANGED/);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_THIRTEEN),await readFile(join(source,'supabase/migrations',MIGRATION_THIRTEEN)));
  for(const fixture of fixtures)await fixture.parity();
  await writeFile(join(folder,'supabase/migrations',MIGRATION_FOURTEEN),'-- unreviewed stopped lifecycle body\n');
  for(const fixture of fixtures)await assert.rejects(fixture.parity(),/REVIEWED_STOPPED_ADMISSION_MIGRATION_CHANGED/);
  await writeFile(join(folder,'supabase/migrations',MIGRATION_FOURTEEN),await readFile(join(source,'supabase/migrations',MIGRATION_FOURTEEN)));
  for(const fixture of fixtures)await fixture.parity();
  await writeFile(join(folder,'supabase/migrations/20261023090000_unreviewed.sql'),'-- unreviewed extra migration\n');
  for(const fixture of fixtures)await assert.rejects(fixture.parity(),/EXACT_REVIEWED_MIGRATION_CHAIN_REQUIRED/);
 }finally{await rm(folder,{recursive:true,force:false});}
});
