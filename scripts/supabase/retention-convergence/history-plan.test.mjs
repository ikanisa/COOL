import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonical} from '../../../supabase/functions/_shared/storage/protocol.js';
import {pinnedBranchInputs} from './ordered-chain-fixture.mjs';
import {planManagedHistory} from './history-plan.mjs';

const sha=x=>createHash('sha256').update(x).digest('hex');
const base=(await pinnedBranchInputs()).migrations.slice(0,14).map(x=>({version:x.name.slice(0,14),
 name:x.name.slice(15,-4),statement_count:1,source_sha256:x.sha256}));
const plan=rows=>{const serialized=canonical(rows);return planManagedHistory(serialized,sha(serialized));};

test('history candidate keeps divergent originals unrecorded and uses distinct ordered versions',async()=>{
 const result=await plan(base);
 assert.equal(result.project_ref,'rrlduytparvsjfmegalh');assert.equal(result.status,'analysis_only');
 assert.equal(result.observed_history_count,14);assert.equal(result.source_file_count,65);assert.equal(result.pending_action_count,52);
 assert.equal(result.history_written,false);assert.equal(result.execution_supported,false);
 assert.equal(result.source_directory_push_safe,false);assert.equal(result.production_authorized,false);
 assert.deepEqual(result.excluded_divergent_originals.map(x=>x.version),['20261114110000','20261114110200']);
 assert.deepEqual(result.actions.filter(x=>x.kind==='branch_candidate').map(x=>x.version),['20261114110001','20261114110201']);
 assert.equal(result.actions.at(-1).version,'20261114110400');assert.equal(result.actions.at(-1).kind,'forward_candidate');
 assert.equal(result.actions.filter(x=>x.work_in_progress).length,2);
 assert.ok(result.actions.every((x,i,a)=>i===0||a[i-1].version<x.version));
 assert.ok(result.actions.every(x=>!['20261114110000','20261114110200'].includes(x.version)));
 assert.ok(result.actions.filter(x=>x.kind==='branch_candidate').every(x=>x.source_sha256!==x.executable_sha256));
});

for(const [name,change] of [
 ['extra history',x=>x.push({...x.at(-1),version:'20261023174001'})],
 ['missing history',x=>x.pop()],
 ['duplicate history',x=>x[13]={...x[12]}],
 ['changed name',x=>x[3].name='changed'],
 ['changed statement hash',x=>x[3].source_sha256='a'.repeat(64)],
 ['multiple statements',x=>x[3].statement_count=2],
 ['unexpected fields',x=>x[3].unexpected=true],
 ['changed ordering',x=>[x[3],x[4]]=[x[4],x[3]]],
])test('history candidate refuses '+name,async()=>{
 const rows=structuredClone(base);change(rows);
 await assert.rejects(plan(rows),{code:name==='extra history'||name==='missing history'?'history_candidate_observation_invalid':'history_candidate_observation_changed'});
});

test('history candidate rejects unpinned and noncanonical input',async()=>{
 const body=canonical(base);await assert.rejects(planManagedHistory(body,'0'.repeat(64)),{code:'history_candidate_observation_invalid'});
 const duplicate=body.replace('"statement_count":1','"statement_count":1,"statement_count":1');
 assert.notEqual(duplicate,body);await assert.rejects(planManagedHistory(duplicate,sha(duplicate)),{code:'history_candidate_observation_invalid'});
});
