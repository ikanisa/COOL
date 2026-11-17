import test from 'node:test';
import assert from 'node:assert/strict';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {withPinnedHistory} from '../testing/pinned-history-stage.mjs';

test('synthetic full chain refuses divergent originals and runs pinned candidates without writing history',{timeout:180000},async()=>{
 const result=await withPinnedHistory(65,async root=>{
  const fixture=await import(pathToFileURL(join(root,'scripts/supabase/retention-convergence/ordered-chain-fixture.mjs')).href);
  return fixture.runSyntheticOrderedChain();
 });
 assert.equal(result.status,'pass',JSON.stringify(result.error));
 assert.equal(result.fixture_removed,true);assert.equal(result.synthetic_only,true);
 assert.equal(result.history_written,false);assert.equal(result.hosted_acceptance,false);assert.equal(result.production_ready,false);
 const migrations=result.events.filter(x=>/^\d{14}_.*\.sql$/.test(x.stage));
 assert.equal(migrations.length,65);
 assert.equal(new Set(migrations.map(x=>x.stage)).size,65);
 assert.ok(migrations.every(x=>x.status==='pass'&&x.history_recorded===false));
 const differences=migrations.filter(x=>x.source_sha256!==x.executed_sha256);
 assert.deepEqual(differences.map(x=>x.stage),[
  '20261022200028_collect_private_member_realtime.sql',
  '20261114110000_burimunsi_native_retention_positive_links.sql',
  '20261114110200_storage_iceberg_retention_census.sql',
 ]);
 assert.equal(differences[0].synthetic_realtime_binding,true);
 assert.deepEqual(differences.slice(1).map(x=>x.candidate_substitution),[
  'managed-branch-1100-candidate.sql','managed-branch-1102-candidate.sql',
 ]);
 assert.deepEqual(result.events.filter(x=>x.stage.endsWith(':original-refusal')).map(x=>x.stage),[
  '20261114110000_burimunsi_native_retention_positive_links.sql:original-refusal',
  '20261114110200_storage_iceberg_retention_census.sql:original-refusal',
 ]);
 const checks=result.events.find(x=>x.stage==='candidate-postconditions');
 assert.deepEqual(checks,{stage:'candidate-postconditions',status:'pass',native_classes:4,iceberg_classes:3,mfa_enabled:false});
 assert.equal(result.events.find(x=>x.stage==='user-id-forward-candidate.sql')?.status,'pass');
});
