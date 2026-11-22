import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonical} from '../../../../supabase/functions/_shared/storage/protocol.js';
import {pinnedBranchInputs} from '../ordered-chain-fixture.mjs';
import {proposeDeferredMfaHistory} from './history-proposal.mjs';

const sha=value=>createHash('sha256').update(value).digest('hex');
const inputs=await pinnedBranchInputs();
const rows=inputs.migrations.slice(0,14).map(x=>({version:x.name.slice(0,14),name:x.name.slice(15,-4),statement_count:1,source_sha256:x.sha256}));
const propose=value=>{const body=canonical(value);return proposeDeferredMfaHistory(body,sha(body));};

test('deferred proposal keeps every non-WIP source action without inventing history',async()=>{
 const p=await propose(rows);assert.equal(p.status,'analysis_only');assert.equal(p.observed_history_count,14);
 assert.equal(p.source_file_count,65);assert.equal(p.pending_action_count,50);assert.equal(p.actions.length,50);
 assert.deepEqual(p.deferred.map(x=>x.version),['20261114110100','20261114110300']);
 assert.ok(p.deferred.every(x=>x.status==='deferred_unexecuted'&&x.history_recorded===false&&!('executable_path' in x)));
 assert.ok(p.actions.every((x,i)=>!x.work_in_progress&&(i===0||p.actions[i-1].version<x.version)));
 const originals=inputs.migrations.slice(14).filter(x=>!p.deferred.some(d=>d.version===x.name.slice(0,14)));
 assert.deepEqual(p.actions.filter(x=>x.source_version!==null).map(x=>x.source_version),originals.map(x=>x.name.slice(0,14)));
 assert.deepEqual(p.actions.filter(x=>x.kind==='branch_candidate').map(x=>x.version),['20261114110001','20261114110201']);
 assert.deepEqual(p.excluded_divergent_originals.map(x=>x.version),['20261114110000','20261114110200']);
 assert.equal(p.actions.at(-1).version,'20261114110400');
 assert.equal(p.managed_portability_qualified,false);assert.equal(p.managed_blocker_count,2);
 const identity=p.actions.find(x=>x.source_version==='20261101013157');
 assert.equal(identity.kind,'original_source');assert.equal(identity.version,'20261101013157');
 assert.equal(identity.managed_portability.status,'blocked_pending_managed_qualification');
 assert.equal(identity.managed_portability.classification,'original_predecessor_managed_binding_unqualified');
 assert.match(identity.managed_portability.detail,/separate managed binder.*scheduler-function preimage/i);
 const stopped=p.actions.find(x=>x.source_version==='20261110181002');
 assert.equal(stopped.kind,'original_source');assert.equal(stopped.version,'20261110181002');
 assert.equal(stopped.managed_portability.status,'blocked_pending_managed_qualification');
 assert.equal(stopped.managed_portability.classification,'local_vm_stopped_admission_semantics');
 assert.ok(p.deferred.every(x=>x.version<p.actions.at(-1).version));
 assert.equal(p.history_written,false);assert.equal(p.execution_supported,false);assert.equal(p.source_directory_push_safe,false);assert.equal(p.production_authorized,false);
 assert.deepEqual(p.runtime_preconditions,{COLLECT_ADMIN_TOTP_ENABLED:'not_true',COLLECT_ADMIN_TOTP_RECOVERY_ENABLED:'not_true'});
});

test('deferred proposal rejects altered or unpinned history observations',async()=>{
 const changed=structuredClone(rows);changed[4].name='altered';
 await assert.rejects(propose(changed),{code:'history_candidate_observation_changed'});
 const body=canonical(rows);await assert.rejects(proposeDeferredMfaHistory(body,'0'.repeat(64)),{code:'history_candidate_observation_invalid'});
 const missing=rows.slice(0,-1);await assert.rejects(propose(missing),{code:'history_candidate_observation_invalid'});
});
