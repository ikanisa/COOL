import test from 'node:test';
import assert from 'node:assert/strict';
import {HISTORY_PACKET_FORMAT,HISTORY_PROFILE,HISTORY_ADDITIONS,validateSelfHostedHistoryPacket,
 snapshotSelfHostedHistorySources,verifySelfHostedHistorySources,startSelfHostedHistoryCapture} from './self-hosted-member-history.mjs';
import {mkdtemp,mkdir,symlink,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {CURRENT_MIGRATION_COUNT} from './self-hosted-current-schema.mjs';

// Contract-validator inputs only; these objects never become SQL receipts.
function contract(){
 const response={contract_version:2};
 return {format:HISTORY_PACKET_FORMAT,profile:HISTORY_PROFILE,source_inputs_sha256:'a'.repeat(64),source_sha256:'b'.repeat(64),
  fixture:{baseline:'current16',synthetic_only:true,historical_packet:false,normal_runtime_role:'collect_runtime',
   migration_count:CURRENT_MIGRATION_COUNT,complete_reviewed_chain:true,deployment_binding_acceptance:false,
   financial_rows_directly_seeded:true,financial_posting_acceptance:false,
   additive_migrations:HISTORY_ADDITIONS.map(name=>({name,sha256:'c'.repeat(64)}))},
  provider_calls:0,hosted_acceptance:false,production_acceptance:false,managed_auth_acceptance:false,
  actual_runtime_transactions_commit:true,requests:[{response:{status:200,body:response}}],
  pages:[{request_id:0,contract_version:2,response}],SQL_statement_count:1};
}

test('current additive packet cannot reuse historical current14 or current16 labels',()=>{
 assert.equal(validateSelfHostedHistoryPacket(contract()).profile,HISTORY_PROFILE);
 for(const format of ['collect.current14.actual-member-history-sql.v1','collect.current16.integration.v1','collect.selfhost.actual-member-history-sql.v1']){
  assert.throws(()=>validateSelfHostedHistoryPacket({...contract(),format}),/CURRENT_SELFHOST_HISTORY_PROFILE_REQUIRED/);
 }
 const value=contract();value.fixture.historical_packet=true;
 assert.throws(()=>validateSelfHostedHistoryPacket(value),/FIXTURE_SCOPE/);
});
test('source-bound scope cannot claim provider, hosted, managed Auth or posting acceptance',()=>{
 for(const name of ['hosted_acceptance','production_acceptance','managed_auth_acceptance']){
  assert.throws(()=>validateSelfHostedHistoryPacket({...contract(),[name]:true}),/NO_EXTERNAL_HISTORY/);
 }
 assert.throws(()=>validateSelfHostedHistoryPacket({...contract(),provider_calls:1}),/NO_EXTERNAL_HISTORY/);
 const value=contract();value.fixture.financial_posting_acceptance=true;
 assert.throws(()=>validateSelfHostedHistoryPacket(value),/FIXTURE_SCOPE/);
});
test('additive migrations and real request-response association are required',()=>{
 const missing=contract();missing.fixture.additive_migrations.pop();
 assert.throws(()=>validateSelfHostedHistoryPacket(missing),/ADDITIVE_MIGRATIONS/);
 const wrong=contract();wrong.pages[0].request_id=8;
 assert.throws(()=>validateSelfHostedHistoryPacket(wrong),/REQUEST_BINDING/);
 const replaced=contract();replaced.pages[0].response={contract_version:2,total_count:42};
 assert.throws(()=>validateSelfHostedHistoryPacket(replaced),/REQUEST_BINDING/);
 const historical=contract();historical.pages[0].contract_version=1;
 assert.throws(()=>validateSelfHostedHistoryPacket(historical),/REQUEST_BINDING/);
});
test('snapshot binds exact schema, shipping SQL and all Dart financial decoder parts',async()=>{
 const snapshot=await snapshotSelfHostedHistorySources();
 const roles=new Set(snapshot.files.map(row=>row.role));
 for(const role of ['supabase/functions/_shared/domain/member_history.js',
  'supabase/functions/_shared/domain/member_history_sql.js',
  'lib/shared/models/member_history_page.dart','lib/shared/models/member_history_signed.dart',
  'lib/shared/models/collect_payment_json.dart','lib/core/data/exact_json_values.dart',
  'test/self_hosted_member_history_sql_receipts_test.dart',
  ...HISTORY_ADDITIONS.map(name=>'supabase/migrations/'+name)])assert(roles.has(role),role);
 assert.equal(snapshot.files.filter(row=>row.role.startsWith('supabase/migrations/')).length,CURRENT_MIGRATION_COUNT);
 await verifySelfHostedHistorySources(snapshot);
 await assert.rejects(()=>verifySelfHostedHistorySources({...snapshot,source_sha256:'f'.repeat(64)}),/SOURCE_CHANGED/);
});
test('capture refuses reused output and linked output parent before writing receipts',async()=>{
 const base=await mkdtemp(join(tmpdir(),'collect-selfhost-history-test-'));
 try{
  const existing=join(base,'existing');await mkdir(existing);
  await assert.rejects(()=>startSelfHostedHistoryCapture(existing),/FRESH_HISTORY_OUTPUT/);
  const alias=join(base,'alias');await symlink(existing,alias);
  await assert.rejects(()=>startSelfHostedHistoryCapture(join(alias,'new')),/PHYSICAL_HISTORY_OUTPUT_PARENT/);
 }finally{await rm(base,{recursive:true,force:true});}
});
