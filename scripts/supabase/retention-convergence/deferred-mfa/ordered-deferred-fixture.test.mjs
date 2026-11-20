import test from 'node:test';
import assert from 'node:assert/strict';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {withPinnedHistory} from '../../testing/pinned-history-stage.mjs';

test('all pinned non-WIP predecessors execute in order while both MFA sources remain absent',{timeout:180000},async()=>{
 const {source,result}=await withPinnedHistory(65,async root=>{
  const fixture=await import(pathToFileURL(join(root,'scripts/supabase/retention-convergence/deferred-mfa/ordered-deferred-fixture.mjs')).href);
  return {source:await fixture.pinnedBranchInputs(),result:await fixture.runSyntheticDeferredMfaChain()};
 });
 assert.equal(result.status,'pass',JSON.stringify(result.error));
 assert.equal(result.fixture_removed,true);assert.equal(result.synthetic_only,true);
 assert.equal(result.history_written,false);assert.equal(result.hosted_acceptance,false);assert.equal(result.production_ready,false);
 const expected=source.migrations.map(x=>x.name),events=result.events.filter(x=>/^\d{14}_.*\.sql$/.test(x.stage));
 const deferred=['20261114110100_collect_admin_mfa_authority.sql','20261114110300_collect_admin_mfa_intent_recovery.sql'];
 assert.equal(expected.length,65);assert.equal(events.length,65);
 assert.deepEqual(events.map(x=>x.stage),expected);
 assert.deepEqual(events.filter(x=>x.status==='deferred').map(x=>x.stage),deferred);
 assert.equal(events.filter(x=>x.status==='pass').length,63);
 assert.ok(events.every((event,i)=>event.source_sha256===source.migrations[i].sha256&&event.history_recorded===false));
 assert.ok(events.filter(x=>x.status==='deferred').every(x=>x.executed_sha256===undefined));
 const substitutions=events.filter(x=>x.status==='pass'&&x.source_sha256!==x.executed_sha256);
 assert.deepEqual(substitutions.map(x=>x.stage),['20261022200028_collect_private_member_realtime.sql',
  '20261114110000_burimunsi_native_retention_positive_links.sql','20261114110200_storage_iceberg_retention_census.sql']);
 assert.equal(substitutions[0].synthetic_realtime_binding,true);
 assert.deepEqual(substitutions.slice(1).map(x=>x.candidate_substitution),['managed-branch-1100-candidate.sql','managed-branch-1102-candidate.sql']);
 assert.equal(result.events.filter(x=>x.stage.endsWith(':original-refusal')).length,2);
 assert.equal(result.events.find(x=>x.stage==='user-id-forward-candidate.sql')?.status,'pass');
 const c=result.events.find(x=>x.stage==='candidate-postconditions');
 assert.equal(c.native_classes,4);assert.equal(c.iceberg_classes,3);
 assert.equal(c.wip_functions,0);assert.equal(c.wip_columns,0);assert.equal(c.wip_policy_rows,0);assert.equal(c.wip_triggers,0);
 assert.equal(c.wip_index_absent,true);assert.equal(c.legacy_enrollment_required,true);assert.equal(c.legacy_factor_constraint,true);
 assert.equal(c.legacy_admin_authority,true);assert.equal(c.projector_ungranted,true);
 assert.equal(c.financial_runtime_functions,6);assert.equal(c.work_assert_present,true);
 assert.equal(c.event_identity_index_present,true);assert.equal(c.event_identity_guard_enabled,true);assert.equal(c.privileged,false);
});
